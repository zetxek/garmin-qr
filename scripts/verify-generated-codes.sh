#!/usr/bin/env bash
#
# Scan codes captured from the simulator and check they decode to the expected text.
#
#   ./scripts/verify-generated-codes.sh <qr.png> <expected-text> [<barcode.png> <expected-text>]
#
# Comparing matrices against a reference encoder proves the bits are right; this proves the
# pixels a scanner sees are right too. Capture a frame with the simulator's
# File > Save Screen Capture while the code is on screen.
#
# Needs zbar: brew install zbar
set -uo pipefail

if ! command -v zbarimg >/dev/null 2>&1; then
    echo "zbarimg not found. Install it with: brew install zbar" >&2
    exit 2
fi
if ! command -v magick >/dev/null 2>&1; then
    echo "ImageMagick not found. Install it with: brew install imagemagick" >&2
    exit 2
fi

status=0

check() {  # check <image> <expected>
    local image="$1" expected="$2"
    local scaled
    scaled="$(mktemp -t codescan).png"
    # Upscale with nearest neighbour: the watch screen is small and zbar wants a few pixels per
    # module, but smoothing would blur the module edges it relies on.
    magick "$image" -filter point -resize 400% "$scaled"

    local decoded
    decoded="$(zbarimg --quiet --raw "$scaled" 2>/dev/null | head -1)"
    rm -f "$scaled"

    if [ "$decoded" = "$expected" ]; then
        echo "PASS  $(basename "$image") -> $decoded"
    else
        echo "FAIL  $(basename "$image")" >&2
        echo "        expected: $expected" >&2
        echo "        decoded : ${decoded:-<nothing>}" >&2
        status=1
    fi
}

# Validate before reading positionals: under `set -u` a missing $1 exits with an unset-variable
# error that says nothing useful, and an odd count would silently skip the incomplete pair.
if [ "$#" -ne 2 ] && [ "$#" -ne 4 ]; then
    echo "usage: $(basename "$0") <text> <expected> [<text> <expected>]" >&2
    exit 2
fi

check "$1" "$2"
if [ "$#" -eq 4 ]; then
    check "$3" "$4"
fi

exit "$status"
