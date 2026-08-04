import Toybox.Lang;

//! A QR module matrix: `size` x `size` bytes, 1 for a dark module.
(:glance)
class QrMatrix {
    public var size as Number;
    public var modules as ByteArray;

    function initialize(side as Number) {
        size = side;
        modules = new [side * side]b;
    }

    function get(x as Number, y as Number) as Number {
        return modules[y * size + x];
    }

    function set(x as Number, y as Number, dark as Number) as Void {
        modules[y * size + x] = dark;
    }
}

//! QR code generator: byte mode, error-correction level M, versions 1-12.
//!
//! Generating on the watch removes the network from the critical path and sidesteps Garmin bug
//! CIQQA-3382, where `makeImageRequest` is proxied through Garmin's image service and returns
//! 404 for domains it cannot fetch.
//!
//! Byte mode only. Numeric and alphanumeric modes would pack some payloads into a smaller
//! symbol, but byte mode is always valid and covers every input the settings editor accepts.
//! Version 12 at level M holds 290 data codewords, comfortably past the 256-character limit.
//!
//! Level M corrects ~15% damage, which is the right trade-off on a watch: enough resilience for
//! a scanner reading a curved, glare-prone screen without shrinking the modules as Q or H would.
//!
//! The tables are the standard ones and are checked against reference output from
//! github.com/skip2/go-qrcode, the library the server-side generator uses.
(:glance)
module Qr {

    const MAX_VERSION = 12;
    const MODE_BYTE = 4;

    //! Per version: total data codewords, EC codewords per block, then the two block groups as
    //! (count, data codewords each). Group 2 is absent when its count is 0.
    const VERSIONS = [
        [ 16, 10, 1, 16, 0,  0],  // v1, 21x21
        [ 28, 16, 1, 28, 0,  0],  // v2, 25x25
        [ 44, 26, 1, 44, 0,  0],  // v3, 29x29
        [ 64, 18, 2, 32, 0,  0],  // v4, 33x33
        [ 86, 24, 2, 43, 0,  0],  // v5, 37x37
        [108, 16, 4, 27, 0,  0],  // v6, 41x41
        [124, 18, 4, 31, 0,  0],  // v7, 45x45
        [154, 22, 2, 38, 2, 39],  // v8, 49x49
        [182, 22, 3, 36, 2, 37],  // v9, 53x53
        [216, 26, 4, 43, 1, 44],  // v10, 57x57
        [254, 30, 1, 50, 4, 51],  // v11, 61x61
        [290, 22, 6, 36, 2, 37]   // v12, 65x65
    ];

    //! Alignment pattern centre coordinates, indexed by version - 1.
    const ALIGNMENT = [
        [],
        [6, 18],
        [6, 22],
        [6, 26],
        [6, 30],
        [6, 34],
        [6, 22, 38],
        [6, 24, 42],
        [6, 26, 46],
        [6, 28, 50],
        [6, 30, 54],
        [6, 32, 58]
    ];

    //! 15-bit format information for level M, indexed by mask. BCH(15,5) plus the 0x5412 mask,
    //! precomputed because it never changes.
    const FORMAT_INFO = [
        0x5412, 0x5125, 0x5E7C, 0x5B4B, 0x45F9, 0x40CE, 0x4F97, 0x4AA0
    ];

    //! 18-bit version information, required from version 7. Indexed by version - 7.
    const VERSION_INFO = [
        0x07C94, 0x085BC, 0x09A99, 0x0A4D3, 0x0BBF6, 0x0C762
    ];

    // ------------------------------------------------------------------ entry point

    //! Build the matrix for `text`, or null when it does not fit in version 12.
    function encode(text as String) as QrMatrix? {
        return encodeWithMask(text, -1);
    }

    //! As `encode`, but with the mask forced. Any mask produces a valid symbol -- the choice is
    //! recorded in the format bits -- so this exists to let tests compare against a reference
    //! encoder's output without depending on both picking the same mask.
    function encodeWithMask(text as String, forcedMask as Number) as QrMatrix? {
        var utf8 = text.toUtf8Array();
        var length = utf8.size();
        // toUtf8Array can append a null terminator; it is not part of the payload.
        while (length > 0 && utf8[length - 1] == 0) { length--; }
        if (length == 0) { return null; }

        var data = new [length]b;
        for (var i = 0; i < length; i++) { data[i] = utf8[i] & 0xFF; }

        var version = chooseVersion(data.size());
        if (version < 0) { return null; }

        var codewords = buildCodewords(data, version);
        return buildMatrix(codewords, version, forcedMask);
    }

    //! The smallest version whose data capacity holds `byteCount`, or -1 if none does.
    function chooseVersion(byteCount as Number) as Number {
        for (var version = 1; version <= MAX_VERSION; version++) {
            var capacityBits = (VERSIONS[version - 1] as Array)[0] * 8;
            var neededBits = 4 + countBits(version) + (byteCount * 8);
            if (neededBits <= capacityBits) { return version; }
        }
        return -1;
    }

    //! The character-count field is 8 bits up to version 9 and 16 bits from version 10.
    function countBits(version as Number) as Number {
        return version < 10 ? 8 : 16;
    }

    // ------------------------------------------------------------------ data encoding

    //! Mode indicator, length, payload, terminator, padding, then error correction, interleaved
    //! into the final codeword stream.
    function buildCodewords(data as ByteArray, version as Number) as ByteArray {
        var spec = VERSIONS[version - 1] as Array;
        var totalData = spec[0] as Number;
        var ecPerBlock = spec[1] as Number;

        var bits = new BitWriter();
        bits.write(MODE_BYTE, 4);
        bits.write(data.size(), countBits(version));
        for (var i = 0; i < data.size(); i++) {
            bits.write(data[i], 8);
        }

        // Terminator: up to four zero bits, fewer if the capacity is nearly full.
        var capacityBits = totalData * 8;
        var terminator = capacityBits - bits.length;
        if (terminator > 4) { terminator = 4; }
        if (terminator > 0) { bits.write(0, terminator); }
        bits.padToByte();

        // Alternating pad bytes until the data capacity is full.
        var pad = [0xEC, 0x11] as Array<Number>;
        var padIndex = 0;
        while (bits.length < capacityBits) {
            bits.write(pad[padIndex], 8);
            padIndex = (padIndex + 1) % 2;
        }

        return interleave(bits.bytes(), spec, ecPerBlock);
    }

    //! Split the data into its blocks, append each block's error correction, then interleave
    //! both -- data codewords first, taking one from each block in turn, then EC the same way.
    function interleave(data as ByteArray, spec as Array, ecPerBlock as Number) as ByteArray {
        var groups = [[spec[2] as Number, spec[3] as Number], [spec[4] as Number, spec[5] as Number]];

        var blocks = [] as Array<ByteArray>;
        var ecBlocks = [] as Array<ByteArray>;
        var at = 0;
        var longest = 0;
        for (var g = 0; g < 2; g++) {
            var count = (groups[g] as Array)[0] as Number;
            var length = (groups[g] as Array)[1] as Number;
            for (var b = 0; b < count; b++) {
                var block = data.slice(at, at + length);
                at += length;
                blocks.add(block);
                ecBlocks.add(ReedSolomon.encode(block, ecPerBlock));
                if (length > longest) { longest = length; }
            }
        }

        var out = new [0]b;
        for (var i = 0; i < longest; i++) {
            for (var b = 0; b < blocks.size(); b++) {
                var block = blocks[b] as ByteArray;
                if (i < block.size()) { out.add(block[i]); }
            }
        }
        for (var i = 0; i < ecPerBlock; i++) {
            for (var b = 0; b < ecBlocks.size(); b++) {
                out.add((ecBlocks[b] as ByteArray)[i]);
            }
        }
        return out;
    }

    // ------------------------------------------------------------------ matrix

    function buildMatrix(codewords as ByteArray, version as Number, forcedMask as Number) as QrMatrix {
        var size = 17 + (4 * version);
        var matrix = new QrMatrix(size);
        var reserved = new [size * size]b;

        drawFinder(matrix, reserved, 0, 0);
        drawFinder(matrix, reserved, size - 7, 0);
        drawFinder(matrix, reserved, 0, size - 7);
        drawAlignment(matrix, reserved, version);
        drawTiming(matrix, reserved, size);
        reserveFormat(reserved, size, version);

        // The dark module is always just above the bottom-left format area.
        matrix.set(8, size - 8, 1);
        reserved[(size - 8) * size + 8] = 1;

        placeData(matrix, reserved, codewords, size);
        if (version >= 7) { drawVersion(matrix, size, version); }

        var mask = forcedMask >= 0 ? forcedMask : chooseMask(matrix, reserved, size);
        applyMask(matrix, reserved, size, mask);
        drawFormat(matrix, size, mask);
        return matrix;
    }

    function drawFinder(matrix as QrMatrix, reserved as ByteArray, ox as Number, oy as Number) as Void {
        // The 7x7 finder plus its one-module separator, clipped to the matrix.
        for (var dy = -1; dy <= 7; dy++) {
            for (var dx = -1; dx <= 7; dx++) {
                var x = ox + dx;
                var y = oy + dy;
                if (x < 0 || y < 0 || x >= matrix.size || y >= matrix.size) { continue; }
                var onBorder = (dx == 0 || dx == 6) && dy >= 0 && dy <= 6;
                var onSide = (dy == 0 || dy == 6) && dx >= 0 && dx <= 6;
                var inCore = dx >= 2 && dx <= 4 && dy >= 2 && dy <= 4;
                matrix.set(x, y, (onBorder || onSide || inCore) ? 1 : 0);
                reserved[y * matrix.size + x] = 1;
            }
        }
    }

    function drawAlignment(matrix as QrMatrix, reserved as ByteArray, version as Number) as Void {
        var centres = ALIGNMENT[version - 1] as Array<Number>;
        var size = matrix.size;
        for (var i = 0; i < centres.size(); i++) {
            for (var j = 0; j < centres.size(); j++) {
                var cx = centres[i];
                var cy = centres[j];
                // The three corners are occupied by finder patterns.
                if (reserved[cy * size + cx] == 1) { continue; }
                for (var dy = -2; dy <= 2; dy++) {
                    for (var dx = -2; dx <= 2; dx++) {
                        var ring = (dx == -2 || dx == 2 || dy == -2 || dy == 2);
                        var centre = (dx == 0 && dy == 0);
                        matrix.set(cx + dx, cy + dy, (ring || centre) ? 1 : 0);
                        reserved[(cy + dy) * size + (cx + dx)] = 1;
                    }
                }
            }
        }
    }

    function drawTiming(matrix as QrMatrix, reserved as ByteArray, size as Number) as Void {
        for (var i = 8; i < size - 8; i++) {
            var dark = (i % 2 == 0) ? 1 : 0;
            if (reserved[6 * size + i] == 0) {
                matrix.set(i, 6, dark);
                reserved[6 * size + i] = 1;
            }
            if (reserved[i * size + 6] == 0) {
                matrix.set(6, i, dark);
                reserved[i * size + 6] = 1;
            }
        }
    }

    //! Mark the areas the format and version information will occupy so data placement skips
    //! them; the bits themselves are written after masking.
    function reserveFormat(reserved as ByteArray, size as Number, version as Number) as Void {
        for (var i = 0; i < 9; i++) {
            if (reserved[8 * size + i] == 0) { reserved[8 * size + i] = 1; }
            if (reserved[i * size + 8] == 0) { reserved[i * size + 8] = 1; }
        }
        for (var i = 0; i < 8; i++) {
            reserved[8 * size + (size - 1 - i)] = 1;
            reserved[(size - 1 - i) * size + 8] = 1;
        }
        if (version >= 7) {
            for (var i = 0; i < 6; i++) {
                for (var j = 0; j < 3; j++) {
                    reserved[i * size + (size - 11 + j)] = 1;
                    reserved[(size - 11 + j) * size + i] = 1;
                }
            }
        }
    }

    //! Data is placed in two-module-wide columns, right to left, alternating upwards and
    //! downwards, skipping the vertical timing pattern at column 6.
    function placeData(matrix as QrMatrix, reserved as ByteArray, codewords as ByteArray, size as Number) as Void {
        var bitIndex = 0;
        var totalBits = codewords.size() * 8;
        var upward = true;

        for (var right = size - 1; right >= 1; right -= 2) {
            if (right == 6) { right = 5; }  // column 6 is the timing pattern
            for (var step = 0; step < size; step++) {
                var y = upward ? (size - 1 - step) : step;
                for (var c = 0; c < 2; c++) {
                    var x = right - c;
                    if (reserved[y * size + x] == 1) { continue; }
                    var bit = 0;
                    if (bitIndex < totalBits) {
                        bit = (codewords[bitIndex / 8] >> (7 - (bitIndex % 8))) & 1;
                        bitIndex++;
                    }
                    matrix.set(x, y, bit);
                }
            }
            upward = !upward;
        }
    }

    // ------------------------------------------------------------------ masking

    function maskAt(mask as Number, x as Number, y as Number) as Boolean {
        switch (mask) {
            case 0: return (y + x) % 2 == 0;
            case 1: return y % 2 == 0;
            case 2: return x % 3 == 0;
            case 3: return (y + x) % 3 == 0;
            case 4: return ((y / 2) + (x / 3)) % 2 == 0;
            case 5: return ((y * x) % 2) + ((y * x) % 3) == 0;
            case 6: return (((y * x) % 2) + ((y * x) % 3)) % 2 == 0;
            default: return (((y + x) % 2) + ((y * x) % 3)) % 2 == 0;
        }
    }

    function applyMask(matrix as QrMatrix, reserved as ByteArray, size as Number, mask as Number) as Void {
        for (var y = 0; y < size; y++) {
            for (var x = 0; x < size; x++) {
                if (reserved[y * size + x] == 1) { continue; }
                if (maskAt(mask, x, y)) {
                    matrix.set(x, y, matrix.get(x, y) == 1 ? 0 : 1);
                }
            }
        }
    }

    //! Try all eight masks and keep the one the standard's penalty rules like best.
    //!
    //! This runs inside the app's startup slice, so it has to stay well inside the Connect IQ
    //! watchdog. Two things make it affordable: each candidate is rendered once into a flat
    //! scratch buffer rather than mutating and un-mutating the matrix, and the penalty rules
    //! index that buffer directly instead of going through accessors -- a method call per module
    //! across eight candidates was the whole cost, and it tripped the watchdog before a single
    //! code could be drawn.
    //!
    //! The mask is recorded in the format information, so any choice decodes; this only affects
    //! how easy the symbol is for a scanner to read.
    function chooseMask(matrix as QrMatrix, reserved as ByteArray, size as Number) as Number {
        var best = 0;
        var bestPenalty = -1;
        var scratch = new [size * size]b;
        var base = matrix.modules;

        for (var mask = 0; mask < 8; mask++) {
            var i = 0;
            for (var y = 0; y < size; y++) {
                for (var x = 0; x < size; x++) {
                    var v = base[i];
                    if (reserved[i] == 0 && maskAt(mask, x, y)) { v = v == 1 ? 0 : 1; }
                    scratch[i] = v;
                    i++;
                }
            }
            writeFormatInto(scratch, size, mask);

            var penalty = penaltyFor(scratch, size);
            if (bestPenalty < 0 || penalty < bestPenalty) {
                bestPenalty = penalty;
                best = mask;
            }
        }
        return best;
    }

    //! Format bits are part of what a scanner sees, so a candidate is scored with them present.
    function writeFormatInto(buffer as ByteArray, size as Number, mask as Number) as Void {
        var bits = FORMAT_INFO[mask] as Number;
        for (var i = 0; i < 15; i++) {
            var bit = (bits >> i) & 1;
            if (i < 6) {
                buffer[i * size + 8] = bit;
            } else if (i == 6) {
                buffer[7 * size + 8] = bit;
            } else if (i == 7) {
                buffer[8 * size + 8] = bit;
            } else if (i == 8) {
                buffer[8 * size + 7] = bit;
            } else {
                buffer[8 * size + (14 - i)] = bit;
            }

            if (i < 8) {
                buffer[8 * size + (size - 1 - i)] = bit;
            } else {
                buffer[(size - 15 + i) * size + 8] = bit;
            }
        }
    }

    function penaltyFor(m as ByteArray, size as Number) as Number {
        return penaltyRuns(m, size) + penaltyBlocks(m, size)
            + penaltyFinderLike(m, size) + penaltyBalance(m, size);
    }

    //! Rule 1: five or more same-coloured modules in a row or column.
    function penaltyRuns(m as ByteArray, size as Number) as Number {
        var penalty = 0;
        for (var line = 0; line < size; line++) {
            var rowBase = line * size;
            var runH = 1;
            var runV = 1;
            var lastH = m[rowBase];
            var lastV = m[line];
            for (var i = 1; i < size; i++) {
                var h = m[rowBase + i];
                if (h == lastH) {
                    runH++;
                    if (runH == 5) { penalty += 3; } else if (runH > 5) { penalty++; }
                } else {
                    runH = 1;
                    lastH = h;
                }

                var v = m[i * size + line];
                if (v == lastV) {
                    runV++;
                    if (runV == 5) { penalty += 3; } else if (runV > 5) { penalty++; }
                } else {
                    runV = 1;
                    lastV = v;
                }
            }
        }
        return penalty;
    }

    //! Rule 2: every 2x2 block of one colour.
    function penaltyBlocks(m as ByteArray, size as Number) as Number {
        var penalty = 0;
        for (var y = 0; y < size - 1; y++) {
            var row = y * size;
            var next = row + size;
            for (var x = 0; x < size - 1; x++) {
                var v = m[row + x];
                if (v == m[row + x + 1] && v == m[next + x] && v == m[next + x + 1]) {
                    penalty += 3;
                }
            }
        }
        return penalty;
    }

    //! Rule 3: a 1011101 finder-like run with four light modules on one side, which a scanner
    //! could mistake for a real finder. Tracked as a rolling 11-bit window so each module is
    //! read once per direction.
    function penaltyFinderLike(m as ByteArray, size as Number) as Number {
        var penalty = 0;
        var forward = 0x5D0;   // 10111010000
        var backward = 0x05D;  // 00001011101
        var mask11 = 0x7FF;

        for (var line = 0; line < size; line++) {
            var rowBase = line * size;
            var windowH = 0;
            var windowV = 0;
            for (var i = 0; i < size; i++) {
                windowH = ((windowH << 1) | m[rowBase + i]) & mask11;
                windowV = ((windowV << 1) | m[i * size + line]) & mask11;
                if (i >= 10) {
                    if (windowH == forward || windowH == backward) { penalty += 40; }
                    if (windowV == forward || windowV == backward) { penalty += 40; }
                }
            }
        }
        return penalty;
    }

    //! Rule 4: how far the proportion of dark modules strays from half.
    function penaltyBalance(m as ByteArray, size as Number) as Number {
        var dark = 0;
        var total = size * size;
        for (var i = 0; i < total; i++) {
            if (m[i] == 1) { dark++; }
        }
        var percent = (dark * 100) / total;
        var deviation = percent > 50 ? percent - 50 : 50 - percent;
        return (deviation / 5) * 10;
    }

    // ------------------------------------------------------------------ format and version

    function drawFormat(matrix as QrMatrix, size as Number, mask as Number) as Void {
        var bits = FORMAT_INFO[mask] as Number;
        for (var i = 0; i < 15; i++) {
            var bit = (bits >> i) & 1;

            // Copy around the top-left finder.
            if (i < 6) {
                matrix.set(8, i, bit);
            } else if (i == 6) {
                matrix.set(8, 7, bit);
            } else if (i == 7) {
                matrix.set(8, 8, bit);
            } else if (i == 8) {
                matrix.set(7, 8, bit);
            } else {
                matrix.set(14 - i, 8, bit);
            }

            // Duplicate copy split between the other two finders.
            if (i < 8) {
                matrix.set(size - 1 - i, 8, bit);
            } else {
                matrix.set(8, size - 15 + i, bit);
            }
        }
    }

    function drawVersion(matrix as QrMatrix, size as Number, version as Number) as Void {
        var bits = VERSION_INFO[version - 7] as Number;
        for (var i = 0; i < 18; i++) {
            var bit = (bits >> i) & 1;
            var row = i / 3;
            var col = i % 3;
            matrix.set(size - 11 + col, row, bit);
            matrix.set(row, size - 11 + col, bit);
        }
    }
}

//! Collects bits MSB-first into whole bytes.
(:glance)
class BitWriter {
    public var length as Number = 0;
    private var buffer as ByteArray;
    private var current as Number = 0;

    function initialize() {
        buffer = new [0]b;
    }

    function write(value as Number, bitCount as Number) as Void {
        for (var i = bitCount - 1; i >= 0; i--) {
            var bit = (value >> i) & 1;
            current = (current << 1) | bit;
            length++;
            if (length % 8 == 0) {
                buffer.add(current & 0xFF);
                current = 0;
            }
        }
    }

    function padToByte() as Void {
        while (length % 8 != 0) { write(0, 1); }
    }

    function bytes() as ByteArray {
        return buffer;
    }
}

//! Reed-Solomon error correction over GF(256) with the QR primitive polynomial 0x11D.
//!
//! Multiplication goes through log/antilog tables. The bit-by-bit carry-less version is easier
//! to read but runs eight inner iterations per multiply, and with thousands of multiplies per
//! symbol that was enough to trip the Connect IQ watchdog ("Code Executed Too Long") before a
//! single code could be drawn.
//!
//! Checked against the worked example in the QR specification; an earlier attempt produced
//! plausible-looking but wrong codewords, which only a known vector caught.
(:glance)
module ReedSolomon {

    var expTable as ByteArray or Null = null;
    var logTable as ByteArray or Null = null;

    function ensureTables() as Void {
        if (expTable != null) { return; }
        var exp = new [512]b;
        var log = new [256]b;
        var x = 1;
        for (var i = 0; i < 255; i++) {
            exp[i] = x;
            log[x] = i;
            x = x << 1;
            if (x >= 256) { x = (x ^ 0x11D) & 0xFF; }
        }
        for (var i = 255; i < 512; i++) { exp[i] = exp[i - 255]; }
        expTable = exp;
        logTable = log;
    }

    function multiply(a as Number, b as Number) as Number {
        if (a == 0 || b == 0) { return 0; }
        ensureTables();
        var exp = expTable as ByteArray;
        var log = logTable as ByteArray;
        return exp[log[a] + log[b]];
    }

    //! Coefficients of the divisor polynomial, highest term omitted because it is always 1.
    function divisor(degree as Number) as ByteArray {
        ensureTables();
        var exp = expTable as ByteArray;
        var log = logTable as ByteArray;

        var result = new [degree]b;
        result[degree - 1] = 1;
        var root = 1;
        for (var i = 0; i < degree; i++) {
            var logRoot = log[root];
            for (var j = 0; j < degree; j++) {
                var v = result[j];
                result[j] = v == 0 ? 0 : exp[log[v] + logRoot];
                if (j + 1 < degree) { result[j] = result[j] ^ result[j + 1]; }
            }
            root = root == 0 ? 0 : exp[log[root] + log[2]];
        }
        return result;
    }

    //! `ecCount` error-correction codewords for `data`.
    function encode(data as ByteArray, ecCount as Number) as ByteArray {
        ensureTables();
        var exp = expTable as ByteArray;
        var log = logTable as ByteArray;
        var div = divisor(ecCount);
        var result = new [ecCount]b;

        for (var d = 0; d < data.size(); d++) {
            var factor = data[d] ^ result[0];
            for (var i = 0; i < ecCount - 1; i++) { result[i] = result[i + 1]; }
            result[ecCount - 1] = 0;
            if (factor != 0) {
                var logFactor = log[factor];
                for (var i = 0; i < ecCount; i++) {
                    var c = div[i];
                    if (c != 0) { result[i] = result[i] ^ exp[log[c] + logFactor]; }
                }
            }
        }
        return result;
    }
}

//! Builds a QR code a slice at a time.
//!
//! Connect IQ runs a watchdog that kills any single execution slice that takes too long, and a
//! whole QR -- Reed-Solomon, data placement, then scoring eight mask candidates -- is well past
//! it even after optimisation. `Qr.encode` is still the right call from a test, where no
//! watchdog applies; on a device the work is spread across timer ticks by calling `advance()`
//! until it returns true.
(:app)
class QrBuilder {

    public var matrix as QrMatrix?;
    public var failed as Boolean = false;

    private var text as String;
    private var version as Number = -1;
    private var reserved as ByteArray?;
    private var scratch as ByteArray?;
    private var size as Number = 0;
    private var step as Number = 0;
    private var bestMask as Number = 0;
    private var bestPenalty as Number = -1;

    function initialize(payload as String) {
        text = payload;
    }

    //! Do one slice of work. Returns true when the matrix is ready (or has failed).
    function advance() as Boolean {
        if (failed || step > 10) { return true; }

        try {
            if (step == 0) {
                buildCodewordsStep();
            } else if (step == 1) {
                buildMatrixStep();
            } else if (step <= 9) {
                scoreMaskStep(step - 2);
            } else {
                finishStep();
            }
        } catch (e) {
            Log.warn("[QrBuilder] generation failed: " + e.getErrorMessage());
            failed = true;
            return true;
        }

        step++;
        return step > 10;
    }

    private var codewords as ByteArray?;

    private function buildCodewordsStep() as Void {
        var utf8 = text.toUtf8Array();
        var length = utf8.size();
        while (length > 0 && utf8[length - 1] == 0) { length--; }
        if (length == 0) { failed = true; return; }

        var data = new [length]b;
        for (var i = 0; i < length; i++) { data[i] = utf8[i] & 0xFF; }

        version = Qr.chooseVersion(length);
        if (version < 0) { failed = true; return; }
        codewords = Qr.buildCodewords(data, version);
    }

    private function buildMatrixStep() as Void {
        size = 17 + (4 * version);
        var m = new QrMatrix(size);
        var res = new [size * size]b;

        Qr.drawFinder(m, res, 0, 0);
        Qr.drawFinder(m, res, size - 7, 0);
        Qr.drawFinder(m, res, 0, size - 7);
        Qr.drawAlignment(m, res, version);
        Qr.drawTiming(m, res, size);
        Qr.reserveFormat(res, size, version);
        m.set(8, size - 8, 1);
        res[(size - 8) * size + 8] = 1;
        Qr.placeData(m, res, codewords as ByteArray, size);
        if (version >= 7) { Qr.drawVersion(m, size, version); }

        matrix = m;
        reserved = res;
        scratch = new [size * size]b;
    }

    private function scoreMaskStep(mask as Number) as Void {
        var m = matrix as QrMatrix;
        var res = reserved as ByteArray;
        var buffer = scratch as ByteArray;
        var base = m.modules;

        var i = 0;
        for (var y = 0; y < size; y++) {
            for (var x = 0; x < size; x++) {
                var v = base[i];
                if (res[i] == 0 && Qr.maskAt(mask, x, y)) { v = v == 1 ? 0 : 1; }
                buffer[i] = v;
                i++;
            }
        }
        Qr.writeFormatInto(buffer, size, mask);

        var penalty = Qr.penaltyFor(buffer, size);
        if (bestPenalty < 0 || penalty < bestPenalty) {
            bestPenalty = penalty;
            bestMask = mask;
        }
    }

    private function finishStep() as Void {
        var m = matrix as QrMatrix;
        Qr.applyMask(m, reserved as ByteArray, size, bestMask);
        Qr.drawFormat(m, size, bestMask);
        // The scratch buffers are the biggest allocation here; let them go.
        scratch = null;
        reserved = null;
        codewords = null;
    }
}
