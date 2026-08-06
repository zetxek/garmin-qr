import Toybox.Lang;

//! Code 128 encoder, subsets B and C.
//!
//! Generating the barcode on the watch takes the network out of the critical path. It also
//! sidesteps Garmin bug CIQQA-3382, where `makeImageRequest` is proxied through Garmin's image
//! service and returns 404 for domains it cannot fetch.
//!
//! Subset B covers printable ASCII 32-126, which is what the settings editor accepts. Subset C
//! packs two digits into one symbol, so it is used for runs of four or more digits: a 16-digit
//! loyalty number is 123 modules instead of 211, and wider bars on a small screen are markedly
//! easier for a scanner to read.
//!
//! The subset-switching rule and the pattern table are the same ones the server-side generator
//! uses, and the output is asserted module-for-module against it in the tests.
(:glance)
module Code128 {

    const START_B = 104;
    const START_C = 105;
    const CODE_B = 100;
    const CODE_C = 99;
    const STOP = 106;
    const FIRST_PRINTABLE = 32;
    const LAST_PRINTABLE = 126;

    //! Which subset is currently active while encoding.
    const SUBSET_NONE = 0;
    const SUBSET_B = 1;
    const SUBSET_C = 2;

    //! One string per symbol value; "1" is a bar, "0" a space. Values 0-105 are 11 modules
    //! wide, the stop pattern is 13.
    const PATTERNS = [
        "11011001100", "11001101100", "11001100110", "10010011000",
        "10010001100", "10001001100", "10011001000", "10011000100",
        "10001100100", "11001001000", "11001000100", "11000100100",
        "10110011100", "10011011100", "10011001110", "10111001100",
        "10011101100", "10011100110", "11001110010", "11001011100",
        "11001001110", "11011100100", "11001110100", "11101101110",
        "11101001100", "11100101100", "11100100110", "11101100100",
        "11100110100", "11100110010", "11011011000", "11011000110",
        "11000110110", "10100011000", "10001011000", "10001000110",
        "10110001000", "10001101000", "10001100010", "11010001000",
        "11000101000", "11000100010", "10110111000", "10110001110",
        "10001101110", "10111011000", "10111000110", "10001110110",
        "11101110110", "11010001110", "11000101110", "11011101000",
        "11011100010", "11011101110", "11101011000", "11101000110",
        "11100010110", "11101101000", "11101100010", "11100011010",
        "11101111010", "11001000010", "11110001010", "10100110000",
        "10100001100", "10010110000", "10010000110", "10000101100",
        "10000100110", "10110010000", "10110000100", "10011010000",
        "10011000010", "10000110100", "10000110010", "11000010010",
        "11001010000", "11110111010", "11000010100", "10001111010",
        "10100111100", "10010111100", "10010011110", "10111100100",
        "10011110100", "10011110010", "11110100100", "11110010100",
        "11110010010", "11011011110", "11011110110", "11110110110",
        "10101111000", "10100011110", "10001011110", "10111101000",
        "10111100010", "11110101000", "11110100010", "10111011110",
        "10111101110", "11101011110", "11110101110", "11010000100",
        "11010010000", "11010011100", "1100011101011"
    ];

    //! True when every character can be represented. Subset B covers printable ASCII only.
    function canEncode(text as String) as Boolean {
        if (text.length() == 0) { return false; }
        var chars = text.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            var code = chars[i].toNumber();
            if (code < FIRST_PRINTABLE || code > LAST_PRINTABLE) { return false; }
        }
        return true;
    }

    function isDigit(code as Number) as Boolean {
        return code >= 0x30 && code <= 0x39;
    }

    //! Subset C encodes two digits per symbol, so it only pays for a run of four digits -- or
    //! two, once already in C, since staying costs nothing.
    function shouldUseSubsetC(chars as Array, from as Number, subset as Number) as Boolean {
        var needed = subset == SUBSET_C ? 2 : 4;
        if (from + needed > chars.size()) { return false; }
        for (var i = 0; i < needed; i++) {
            if (!isDigit(chars[from + i].toNumber())) { return false; }
        }
        return true;
    }

    //! The symbol values for `text`, including start, checksum and stop.
    function symbolsFor(text as String) as Array<Number>? {
        if (!canEncode(text)) { return null; }

        var chars = text.toCharArray();
        var symbols = [] as Array<Number>;
        var subset = SUBSET_NONE;
        var i = 0;

        while (i < chars.size()) {
            if (shouldUseSubsetC(chars, i, subset)) {
                if (subset != SUBSET_C) {
                    symbols.add(subset == SUBSET_NONE ? START_C : CODE_C);
                    subset = SUBSET_C;
                }
                var tens = chars[i].toNumber() - 0x30;
                var units = chars[i + 1].toNumber() - 0x30;
                symbols.add(tens * 10 + units);
                i += 2;
            } else {
                if (subset != SUBSET_B) {
                    symbols.add(subset == SUBSET_NONE ? START_B : CODE_B);
                    subset = SUBSET_B;
                }
                symbols.add(chars[i].toNumber() - FIRST_PRINTABLE);
                i++;
            }
        }

        // Checksum: the start symbol plus every later symbol weighted by its position.
        var checksum = symbols[0];
        for (var n = 1; n < symbols.size(); n++) {
            checksum += n * symbols[n];
        }
        symbols.add(checksum % 103);
        symbols.add(STOP);
        return symbols;
    }

    //! Encode to one byte per module, 1 for a bar and 0 for a space.
    //! Returns null when the text cannot be represented, so the caller can fall back.
    function encode(text as String) as ByteArray? {
        var symbols = symbolsFor(text);
        if (symbols == null) { return null; }

        var width = 0;
        for (var i = 0; i < symbols.size(); i++) {
            width += (PATTERNS[symbols[i]] as String).length();
        }

        var modules = new [width]b;
        var at = 0;
        for (var i = 0; i < symbols.size(); i++) {
            var pattern = PATTERNS[symbols[i]] as String;
            for (var j = 0; j < pattern.length(); j++) {
                modules[at] = pattern.substring(j, j + 1).equals("1") ? 1 : 0;
                at++;
            }
        }
        return modules;
    }
}
