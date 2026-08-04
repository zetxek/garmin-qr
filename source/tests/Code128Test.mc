import Toybox.Lang;
import Toybox.Test;

//! Code 128 encoder tests.
//!
//! The expected module strings were dumped from github.com/boombuler/barcode -- the same
//! library the server-side generator uses -- so a barcode generated on the watch is asserted to
//! be bit-for-bit what the service would have returned, including where the encoder switches
//! between subsets B and C. "1" is a bar, "0" a space.
(:test)
function code128MatchesTheReferenceEncoder(logger as Test.Logger) as Boolean {
    TestSupport.assertCode128(logger, "HELLO",
        "110100100001100010100010001101000100011011101000110111010001110110110001010001100011101011");
    TestSupport.assertCode128(logger, "MEMBER 12345",
        "11010010000101110110001000110100010111011000100010110001000110100011000101110110110011001011101111010110011100100010110001011110111011011100100101100100001100011101011");
    TestSupport.assertCode128(logger, "A",
        "1101001000010100011000100010110001100011101011");
    TestSupport.assertCode128(logger, "Wikipedia",
        "11010010000111010001101000011010011000010010100001101001010011110010110010000100001001101000011010010010110000111100100101100011101011");
    TestSupport.assertCode128(logger, "1234567890123456",
        "110100111001011001110010001011000111000101101100001010011011110110101100111001000101100011100010110110010111001100011101011");
    TestSupport.assertCode128(logger, "12345",
        "1101001110010110011100100010110001011110111011011100100111010110001100011101011");
    TestSupport.assertCode128(logger, "0000",
        "110100111001101100110011011001100110011001101100011101011");
    TestSupport.assertCode128(logger, "AB12",
        "1101001000010100011000100010110001001110011011001110010110010111001100011101011");
    TestSupport.assertCode128(logger, "A1B2",
        "1101001000010100011000100111001101000101100011001110010101100010001100011101011");
    return true;
}

//! Subset B covers printable ASCII only. Anything else must be reported rather than encoded
//! wrongly, so the caller can fall back to the service.
(:test)
function code128RejectsWhatItCannotEncode(logger as Test.Logger) as Boolean {
    Test.assertMessage(Code128.encode("caf\u00e9") == null, "non-ASCII is rejected");
    Test.assertMessage(Code128.encode("") == null, "empty text is rejected");
    Test.assertMessage(Code128.encode("tab\there") == null, "control characters are rejected");
    Test.assertMessage(Code128.encode(" ") != null, "a space is the first encodable character");
    Test.assertMessage(Code128.encode("~") != null, "a tilde is the last encodable character");
    logger.debug("rejects unencodable input instead of producing a wrong barcode");
    return true;
}

//! Subset C is the reason a loyalty number stays readable on a watch: half the symbols means
//! double the module width for the same screen.
(:test)
function code128UsesSubsetCForDigitRuns(logger as Test.Logger) as Boolean {
    var digits = Code128.encode("1234567890123456");
    var pureB = 11 + (16 * 11) + 11 + 13;
    Test.assertMessage(digits.size() < pureB,
        "16 digits should be narrower than subset B alone: " + digits.size() + " vs " + pureB);
    logger.debug("16 digits -> " + digits.size() + " modules (subset B alone would be " + pureB + ")");

    // Two digits are not worth a subset switch.
    var short = Code128.symbolsFor("AB12");
    Test.assertMessage(short.indexOf(Code128.CODE_C) < 0, "a two-digit run stays in subset B");
    return true;
}

//! Every symbol is 11 modules except the 13-module stop, so a text with no digit runs has a
//! width fixed by its length.
(:test)
function code128WidthFollowsTextLength(logger as Test.Logger) as Boolean {
    for (var n = 1; n <= 12; n++) {
        var text = "";
        for (var i = 0; i < n; i++) { text += "A"; }
        var modules = Code128.encode(text);
        var expected = 11 + (n * 11) + 11 + 13;  // start + data + checksum + stop
        Test.assertEqualMessage(modules.size(), expected,
            n + " characters should be " + expected + " modules");
    }
    logger.debug("width scales as start + 11n + checksum + stop");
    return true;
}
