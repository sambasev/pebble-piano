#!/bin/bash
# Rebuilds and restarts PianoPad whenever a source file changes.
#
#   scripts/dev_watch.sh            # in the folder to watch (the repo or a worktree)
#
# Each change: build; if the build works, quit the running PianoPad and start the new one;
# if it fails, the old app keeps running and the errors are printed. Every build's result
# goes to .build/dev-watch.log (Claude reads it to fix compile errors). Ctrl-C stops it.
set -u
cd "$(dirname "$0")/.." || exit 1
root=$(pwd)
log="$root/.build/dev-watch.log"
mkdir -p "$root/.build"
stamp="$root/.build/dev-watch.stamp"
app_pid=""

snapshot() {  # newest modification time of anything that affects the build
    find Sources Package.swift Lessons Books -type f \( -name '*.swift' -o -name '*.json' -o -name '*.pdf' -o -name 'Package.swift' \) \
        -newer "$stamp" -print -quit 2>/dev/null
}

stop_app() {
    [ -n "$app_pid" ] && kill "$app_pid" 2>/dev/null && wait "$app_pid" 2>/dev/null
    pkill -x PianoPad 2>/dev/null
    app_pid=""
}

build_and_run() {
    touch "$stamp"
    echo "── $(date '+%H:%M:%S') building $(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null) in $root" | tee "$log"
    if swift build --product PianoPad 2>&1 | tee -a "$log" | grep -E "error:|warning: unre|Compiling|Build complete" | grep -v "^\[.*Compiling" ; then :; fi
    if grep -q "error:" "$log"; then
        echo "✗ BUILD FAILED $(date '+%H:%M:%S') — the app still running is the previous build" | tee -a "$log"
        osascript -e 'display notification "Build failed — see .build/dev-watch.log" with title "PianoPad"' 2>/dev/null
        return
    fi
    stop_app
    "$root/.build/debug/PianoPad" >>"$root/.build/dev-watch.app.log" 2>&1 &
    app_pid=$!
    echo "✓ BUILD OK $(date '+%H:%M:%S') — PianoPad restarted (pid $app_pid)" | tee -a "$log"
}

trap 'stop_app; exit 0' INT TERM
build_and_run
while true; do
    sleep 2
    if [ -n "$(snapshot)" ]; then
        sleep 1   # let a batch of edits finish
        build_and_run
    fi
done
