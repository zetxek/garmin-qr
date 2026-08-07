#!/usr/bin/env bash
#
# End-to-end test in the Connect IQ simulator, with a live HTTP round-trip to the code service.
#
#   ./scripts/simulator-test.sh [device]
#
# Several simulator invocations, sharing the simulator's persistent app storage:
#
#   0. settings  codes that exist in the settings editor but not in storage — a fresh install
#                configured from the phone before it was ever opened — survive the first launch
#                and leave `codesList` saveable (issue #30). Boot only, no network.
#   1. seed    two codes, one QR containing an `&` and one barcode containing a space, with
#              their image cache cleared
#   2. run     the real app for a while, so it reconciles settings, drains the download queue
#              and caches whatever the service returns
#   3. verify  both images arrived, are attributed to the right codes, and have the shape the
#              endpoint should have produced; then that a warm start queues nothing
#
# Needs network access. `monkeydo` always exits 1, so results are read out of its output.
set -uo pipefail

DEVICE="${1:-fenix7pro}"
OUT_DIR="${OUT_DIR:-bin}"
DEVELOPER_KEY="${DEVELOPER_KEY:-$HOME/Documents/garmin-sdk/developer_key}"
# How long to let the app run. Two images plus the glance image over a simulated BLE link.
APP_RUN_SECONDS="${APP_RUN_SECONDS:-30}"

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
    # `return`, not `exit`: this runs inside $(...), so an exit here would only end the
    # subshell and leave the caller running with an empty SDK_BIN.
    return 2
}

if ! SDK_BIN="$(find_sdk)"; then
    exit 2
fi
mkdir -p "$OUT_DIR"

build() {  # build <output> <jungle> [--unit-test]
    "$SDK_BIN/monkeyc" \
        -o "$1" \
        -y "$DEVELOPER_KEY" \
        -d "$DEVICE" \
        -f "$2" \
        -w -l 2 \
        ${3:-} || exit 1
}

echo "==> Building app and integration fixtures for $DEVICE"
build "$OUT_DIR/app.prg" monkey.jungle
build "$OUT_DIR/integration.prg" monkey-integration.jungle --unit-test

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

if [ -z "${DISPLAY:-}" ] && command -v Xvfb >/dev/null 2>&1; then
    export DISPLAY=:99
    Xvfb :99 -screen 0 1280x1024x24 >/dev/null 2>&1 &
    sleep 3
fi

if ! pgrep -f "ConnectIQ.app/Contents/MacOS/simulator" >/dev/null 2>&1 \
   && ! pgrep -x simulator >/dev/null 2>&1; then
    echo "==> Starting simulator"
    # Prefer the `simulator` binary over the `connectiq` wrapper: the wrapper starts and
    # listens on a hosted CI runner, but monkeydo never gets a response from it. The
    # connectiq-tester image's own runner launches `simulator` directly for the same reason.
    SIMULATOR="$(command -v simulator || command -v connectiq || echo "$SDK_BIN/connectiq")"
    "$SIMULATOR" >/dev/null 2>&1 &
fi
wait_for_simulator || exit 1

run_fixture() {  # run_fixture <test name>
    local name="$1"
    local output
    local log="$OUT_DIR/integration-$name.log"
    # See run-tests.sh: a command substitution would outlive `timeout` because monkeydo's JVM
    # keeps the pipe open.
    if command -v timeout >/dev/null 2>&1; then
        timeout -k 10 "${TEST_TIMEOUT:-600}" \
            "$SDK_BIN/monkeydo" "$OUT_DIR/integration.prg" "$DEVICE" -t "$name" >"$log" 2>&1
    else
        "$SDK_BIN/monkeydo" "$OUT_DIR/integration.prg" "$DEVICE" -t "$name" >"$log" 2>&1
    fi
    output="$(cat "$log")"
    echo "$output" | sed -n '/Executing test/,$p'
    if echo "$output" | grep -qE '^PASSED \(passed=[0-9]+, failed=0, errors=0\)'; then
        return 0
    fi
    return 1
}

run_app() {  # run_app <seconds>
    "$SDK_BIN/monkeydo" "$OUT_DIR/app.prg" "$DEVICE" >/dev/null 2>&1 &
    local pid=$!
    sleep "$1"
    kill "$pid" >/dev/null 2>&1
    wait "$pid" 2>/dev/null
}

# Issue #30. Boot only, so it needs no network and only a few seconds: the question is what
# `getInitialView` does to codes that exist in the settings editor but not yet in storage.
echo
echo "==> 0/3 Settings round trip: codes configured before the first launch"
run_fixture integrationSeedIssue30 || { echo "==> Seeding failed" >&2; exit 1; }
run_app "${BOOT_RUN_SECONDS:-10}"
run_fixture integrationVerifyIssue30 || { echo "==> Settings round trip failed" >&2; exit 1; }

echo
echo "==> 1/3 Seeding two codes with no cached images"
run_fixture integrationSeed || { echo "==> Seeding failed" >&2; exit 1; }

echo
echo "==> 2/3 Running the app for ${APP_RUN_SECONDS}s so it downloads them"
run_app "$APP_RUN_SECONDS"

echo
echo "==> 3/3 Verifying what the app actually cached"
FAILED=0
run_fixture integrationVerify || FAILED=1
run_fixture integrationVerifyNoRedownload || FAILED=1

echo
if [ "$FAILED" -eq 0 ]; then
    echo "==> Simulator end-to-end test passed"
    exit 0
fi

echo "==> Simulator end-to-end test failed" >&2
cat >&2 <<'HINT'

    If the failure is "the download never completed", check these in order:

    1. Settings > Glance Launch Mode must be "Launch in Normal Mode". In glance mode the
       simulator runs only the glance, which never downloads by design, so the app under
       test never runs at all. This is the most common cause.

    2. The simulator must be signed in to Garmin Connect. Image requests are proxied
       through that account; until you sign in every request fails.

    3. Run the diagnostic and look at lastError:

           monkeydo bin/integration.prg <device> -t integrationDump

       404 means the code service refused Garmin's image fetcher while still answering
       curl normally. The app is not at fault in that case -- see
       docs/superpowers/specs/ for the investigation.
HINT
exit 1
