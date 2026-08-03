#!/usr/bin/env bash
#
# Build the unit-test binary and run it in the Connect IQ simulator.
#
#   ./scripts/run-tests.sh [device]
#
# Works on a developer Mac and inside the CI container. `monkeydo` always exits 1, so the
# result has to be read out of its output — that is the whole reason this script exists.
set -uo pipefail

DEVICE="${1:-fenix7pro}"
OUT_DIR="${OUT_DIR:-bin}"
DEVELOPER_KEY="${DEVELOPER_KEY:-$HOME/Documents/garmin-sdk/developer_key}"

find_sdk() {
    if command -v monkeyc >/dev/null 2>&1; then
        dirname "$(command -v monkeyc)"
        return
    fi
    local cfg="$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg"
    if [ -f "$cfg" ]; then
        echo "$(head -n1 "$cfg")/bin"
        return
    fi
    echo "Could not locate the Connect IQ SDK; put monkeyc on PATH." >&2
    exit 2
}

SDK_BIN="$(find_sdk)"
mkdir -p "$OUT_DIR"

echo "==> Building unit tests for $DEVICE"
"$SDK_BIN/monkeyc" \
    -o "$OUT_DIR/test.prg" \
    -y "$DEVELOPER_KEY" \
    -d "$DEVICE" \
    -f monkey.jungle \
    -w -l 2 \
    --unit-test || exit 1

# The simulator listens on 1234 once it is ready to accept a push. Waiting for the port beats a
# fixed sleep: too short and `monkeydo` blocks forever waiting for a simulator that is not up,
# which is how the CI job came to sit for 25 minutes.
wait_for_simulator() {
    local deadline=$(( $(date +%s) + ${SIMULATOR_START_TIMEOUT:-90} ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        # The probe runs in a subshell, so no descriptor leaks into this one. Do not "tidy up"
        # with `exec 3<&- 2>/dev/null` here: `exec` with no command applies the redirection to
        # the shell itself, which silently discards stderr for the rest of the script.
        if (exec 3<>/dev/tcp/127.0.0.1/1234) 2>/dev/null; then
            echo "==> Simulator ready"
            return 0
        fi
        sleep 2
    done
    echo "==> Simulator did not become ready on port 1234" >&2
    return 1
}


# Printed when a run produces nothing useful. Without it a CI failure shows an empty log and
# says nothing about whether the display, the simulator or the push was the problem.
dump_diagnostics() {
    echo "--- diagnostics ---" >&2
    echo "DISPLAY=${DISPLAY:-<unset>}" >&2
    if command -v xdpyinfo >/dev/null 2>&1; then
        xdpyinfo >/dev/null 2>&1 && echo "X display: reachable" >&2 || echo "X display: NOT reachable" >&2
    fi
    echo "simulator processes:" >&2
    pgrep -af "simulator|connectiq" 2>/dev/null | head -5 >&2 || echo "  none" >&2
    if (exec 3<>/dev/tcp/127.0.0.1/1234) 2>/dev/null; then
        echo "port 1234: listening" >&2
    else
        echo "port 1234: not listening" >&2
    fi
    echo "monkeydo output (${LOG:-unset}):" >&2
    if [ -s "${LOG:-/nonexistent}" ]; then sed -n '1,40p' "$LOG" >&2; else echo "  <empty>" >&2; fi
    echo "--- end diagnostics ---" >&2
}

# The simulator is a GUI process; on a headless machine it needs a virtual display.
if [ -z "${DISPLAY:-}" ] && command -v Xvfb >/dev/null 2>&1; then
    export DISPLAY=:99
    Xvfb :99 -screen 0 1280x1024x24 >/dev/null 2>&1 &
    # Wait for the display itself, rather than assuming a fixed delay is enough.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        if ! command -v xdpyinfo >/dev/null 2>&1 || xdpyinfo >/dev/null 2>&1; then break; fi
        sleep 1
    done
fi

if ! pgrep -f "ConnectIQ.app/Contents/MacOS/simulator" >/dev/null 2>&1 \
   && ! pgrep -x simulator >/dev/null 2>&1; then
    echo "==> Starting simulator"
    SIMULATOR="$(command -v connectiq || echo "$SDK_BIN/connectiq")"
    "$SIMULATOR" >"${OUT_DIR}/simulator.log" 2>&1 &
fi
LOG="$OUT_DIR/test-output.txt"
wait_for_simulator || { dump_diagnostics; exit 1; }

# `monkeydo` blocks forever if the simulator never becomes ready, which turns a broken CI
# environment into a job that hangs for hours instead of failing. `timeout` is not present on
# macOS by default, so it is used only when available.
TEST_TIMEOUT="${TEST_TIMEOUT:-600}"
echo "==> Running tests on $DEVICE"

# Output goes to a file rather than a command substitution on purpose. `monkeydo` is a shell
# script that spawns a JVM; with `OUTPUT="$(timeout ... monkeydo)"` the substitution waits for
# every writer of the pipe to close, so killing monkeydo leaves the JVM holding stdout and the
# shell blocks anyway — which is exactly how the CI job sat for 25 minutes.
if command -v timeout >/dev/null 2>&1; then
    timeout -k 10 "$TEST_TIMEOUT" "$SDK_BIN/monkeydo" "$OUT_DIR/test.prg" "$DEVICE" -t >"$LOG" 2>&1
    STATUS=$?
else
    "$SDK_BIN/monkeydo" "$OUT_DIR/test.prg" "$DEVICE" -t >"$LOG" 2>&1
    STATUS=$?
fi
OUTPUT="$(cat "$LOG")"
echo "$OUTPUT"

if [ "$STATUS" -eq 124 ]; then
    echo "==> Timed out after ${TEST_TIMEOUT}s waiting for the simulator" >&2
    dump_diagnostics
    exit 1
fi

# monkeydo exits 1 whatever happens, so the summary line is the source of truth.
if echo "$OUTPUT" | grep -qE '^PASSED \(passed=[0-9]+, failed=0, errors=0\)'; then
    echo "==> Tests passed"
    exit 0
fi

echo "==> Tests failed" >&2
dump_diagnostics
exit 1
