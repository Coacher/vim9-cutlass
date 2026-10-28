#!/usr/bin/env bash
# Runs the vim9-cutlass test suite in isolation from the user's session.
#
# Environment:
#   VIM_BIN    terminal Vim binaries separated by spaces, default: vim
#   GVIM_BIN   gVim binaries separated by spaces, default: gvim; empty skips GUI
#   DISPLAYS   display variants to run, default: none x11 wayland xwayland
#   CONFIGS    plugin configurations to run, see matrices.vim
#   CASES      Vim pattern selecting case ids
#   MATRICES   Vim pattern selecting matrix names
#   RESULTS    directory for reports, default: test/results
#   TIMEOUT    seconds per Vim process, default: 900
#   VERBOSE    1 prints every report line, default prints failures and summaries

set -u

test_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(dirname "$test_dir")
results=${RESULTS:-$test_dir/results}
vim_bins=${VIM_BIN-vim}
gvim_bins=${GVIM_BIN-gvim}
displays=${DISPLAYS:-none x11 wayland xwayland}
configs=${CONFIGS:-black named distinct plus star exclude usermap cut cutx}
timeout_seconds=${TIMEOUT:-900}
verbose=${VERBOSE:-0}
# Builds that never reach a display server run on one variant: none when
# selected, otherwise the first variant that starts
headless_display=
case " $displays " in *" none "*) headless_display=none ;; esac

# shellcheck source=display.sh
. "$test_dir/display.sh"

scratch=$(mktemp -d)
mkdir -p "$scratch/home" "$scratch/runtime"
chmod 700 "$scratch/runtime"
trap 'stop_display; rm -rf "$scratch"' EXIT

total_pass=0
total_fail=0
total_skip=0
total_known=0
# The display server where a build and kind ran every case
declare -A full_servers
failed_runs=()
skipped_runs=()

log() {
    printf '%s\n' "$*"
}

# Everything the user's session could leak in is dropped here
base_env=(
    "PATH=$PATH"
    "HOME=$scratch/home"
    "XDG_RUNTIME_DIR=$scratch/runtime"
    "TERM=xterm-256color"
    "LANG=C.UTF-8"
    "LC_ALL=C.UTF-8"
    "NO_AT_BRIDGE=1"
)

# Caches the feature probe per binary, as every display variant asks for it
declare -A features
has_feature() {
    local key="$1 $2"
    if [ -z "${features[$key]:-}" ]; then
        # The subshell keeps bash from reporting a probe the timeout killed
        if (timeout -s KILL "$timeout_seconds" env -i "${base_env[@]}" \
            "$1" -v -u NONE -i NONE -N --not-a-term -es \
            -c "if has('$2') | qall! | endif" -c 'cquit!' </dev/null; exit $?) >/dev/null 2>&1; then
            features[$key]=1
        else
            features[$key]=0
        fi
    fi
    [ "${features[$key]}" = 1 ]
}

# A gVim that cannot use the display falls back to terminal mode, and one
# on a compositor without input devices crashes on the first clipboard write
gui_starts() {
    # The subshell exits normally after a crash, so bash reports no signal
    (timeout -s KILL "$timeout_seconds" env -i "${base_env[@]}" "${display_env[@]}" \
        "$1" -f -g -u NONE -i NONE -N --not-a-term \
        -c 'silent! call setreg("+", "x")' \
        -c 'if has("gui_running") | qall! | endif' -c 'cquit!' </dev/null; exit $?) >/dev/null 2>&1
}

# Terminal Vim draws its screen into the log, mostly as escape sequences
# around every fed key.  Only the text is kept, a cursor jump as a space;
# the log is filtered after Vim exits, as Vim behaves differently when its
# output goes to a pipe.
screen_text() {
    LC_ALL=C sed -i 's#\x1b\[[0-9]*C# #g; s#\x1b\[[0-?]*[ -/]*[@-~]##g;
        s#\x1b[]P][^\x07\x1b]*\(\x07\|\x1b\\\)##g; s#\x1b[ -/]*.##g; s#[\x01-\x08\x0b-\x1f\x7f]##g;
        /^[[:space:]]*$/d' "$1"
}

# Builds without Vim9 script must reject the plugin without side effects
degraded_check() {
    local bin=$1 run_dir=$2 out
    # Without 'nomore' the error list stops at a More prompt that never ends
    out=$(timeout -s KILL "$timeout_seconds" env -i "${base_env[@]}" "$bin" -u NONE -i NONE -N --not-a-term \
        -c 'set nomore' -c "source $repo_dir/plugin/cutlass.vim" -c 'map' -c 'map!' -c 'qall!' \
        </dev/null 2>&1)
    local status=$?
    printf '%s\n' "$out" >"$run_dir/vim.log"
    screen_text "$run_dir/vim.log"
    if [ $status -eq 0 ] && [ "$(printf '%s' "$out" | grep -c 'No mapping found')" -eq 2 ]; then
        log "SUMMARY $(basename "$bin") degraded: 1 passed, 0 failed, 0 skipped (no vim9script)"
        total_pass=$((total_pass + 1))
    else
        log "FAIL $(basename "$bin") degraded: plugin left mappings or failed, see $run_dir/vim.log"
        total_fail=$((total_fail + 1))
        failed_runs+=("$(basename "$bin")/degraded")
    fi
}

# Turns the FAIL lines of a report into GitHub Actions error annotations
annotate() {
    local report=$1 run=$2
    sed -n 's/^FAIL \(.*\)/\1/p' "$report" | while IFS= read -r id; do
        printf '::error title=%s::%s\n' "$run" "$id"
    done
}

# Counts a test process that left no usable report as one failed case
broken_run() {
    local run=$1 reason=$2 log_file=$3
    log "FAIL $run: $reason, see $log_file"
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        printf '::error title=%s::%s\n' "$run" "$reason"
    fi
    total_fail=$((total_fail + 1))
    failed_runs+=("$run")
}

run_process() {
    local bin=$1 kind=$2 display=$3 config=$4 scope=$5
    local name
    name=$(basename "$bin")
    local run_dir="$results/$display/$config/$name-$kind"
    mkdir -p "$run_dir"
    rm -f "$run_dir"/report.txt "$run_dir"/junit.xml "$run_dir"/results.jsonl
    local args=(-u NONE -i NONE -N -S "$test_dir/runner.vim")
    if [ "$kind" = gui ]; then
        args=(-f -g "${args[@]}")
    else
        args=(--not-a-term "${args[@]}")
    fi
    env -i "${base_env[@]}" "${display_env[@]}" \
        "CUTLASS_CONFIG=$config" "CUTLASS_DISPLAY=$display" "CUTLASS_RESULTS=$run_dir" \
        "CUTLASS_CASES=${CASES:-}" "CUTLASS_MATRICES=${MATRICES:-}" "CUTLASS_SCOPE=$scope" \
        timeout -s KILL "$timeout_seconds" "$bin" "${args[@]}" </dev/null >"$run_dir/vim.log" 2>&1
    local status=$?
    if [ "$kind" = term ]; then
        screen_text "$run_dir/vim.log"
    fi
    if [ ! -f "$run_dir/report.txt" ]; then
        broken_run "$display/$config/$name-$kind" "no report, exit status $status" "$run_dir/vim.log"
        return
    fi
    local summary
    summary=$(grep '^SUMMARY' "$run_dir/report.txt")
    # The harness replaces the report with its error; a write that failed
    # leaves a report without counts
    if [ -z "$summary" ]; then
        local reason
        reason=$(grep '^HARNESS ERROR' "$run_dir/report.txt")
        broken_run "$display/$config/$name-$kind" \
            "${reason:-no summary in the report, exit status $status}" "$run_dir/report.txt"
        return
    fi
    if [ "$verbose" = 1 ]; then
        cat "$run_dir/report.txt"
    else
        grep -v '^    ' "$run_dir/report.txt"
    fi
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        annotate "$run_dir/report.txt" "$display/$config/$name-$kind"
    fi
    local pass fail skip known
    pass=$(printf '%s' "$summary" | sed -n 's/.*: \([0-9]*\) passed.*/\1/p')
    fail=$(printf '%s' "$summary" | sed -n 's/.* \([0-9]*\) failed.*/\1/p')
    skip=$(printf '%s' "$summary" | sed -n 's/.* \([0-9]*\) skipped.*/\1/p')
    known=$(printf '%s' "$summary" | sed -n 's/.* \([0-9]*\) known.*/\1/p')
    total_pass=$((total_pass + ${pass:-0}))
    total_fail=$((total_fail + ${fail:-0}))
    total_skip=$((total_skip + ${skip:-0}))
    total_known=$((total_known + ${known:-0}))
    if [ "${fail:-0}" -gt 0 ]; then
        failed_runs+=("$display/$config/$name-$kind")
    fi
}

run_binary() {
    local bin=$1 kind=$2 display=$3 config
    if ! command -v "$bin" >/dev/null 2>&1; then
        log "SKIP $bin: binary not found"
        skipped_runs+=("$bin: not found")
        return
    fi
    if [ "$kind" = gui ] && ! has_feature "$bin" gui; then
        log "SKIP $bin: no GUI support"
        skipped_runs+=("$bin: no GUI")
        return
    fi
    if ! has_feature "$bin" vim9script; then
        if [ "$display" = none ]; then
            local run_dir="$results/$display/degraded/$(basename "$bin")-$kind"
            mkdir -p "$run_dir"
            degraded_check "$bin" "$run_dir"
        fi
        return
    fi
    # Without the clipboard feature Vim never reaches a display server, so
    # every other display variant would repeat the run
    if [ "$display" != "$headless_display" ] && ! has_feature "$bin" clipboard; then
        log "SKIP $bin: no clipboard, runs on display $headless_display only"
        skipped_runs+=("$bin: no clipboard on $display")
        return
    fi
    if [ "$kind" = gui ] && ! gui_starts "$bin"; then
        log "SKIP $bin: GUI cannot run on display $display"
        skipped_runs+=("$bin: no GUI on $display")
        return
    fi
    # Only the clipboard cases reach a different state under another
    # display server, so a build runs every case on none and on the first
    # server it reaches, and the clipboard cases on the other servers
    local scope=all
    if [ "$display" != none ]; then
        if [ -n "${full_servers[$bin $kind]:-}" ]; then
            scope=clipboard
        else
            full_servers[$bin $kind]=$display
        fi
    fi
    for config in $configs; do
        run_process "$bin" "$kind" "$display" "$config" "$scope"
    done
}

mkdir -p "$results"
for display in $displays; do
    if ! start_display "$display"; then
        log "SKIP display $display: $skip_reason"
        skipped_runs+=("display $display: $skip_reason")
        continue
    fi
    if [ -z "$headless_display" ]; then
        headless_display=$display
    fi
    for bin in $vim_bins; do
        run_binary "$bin" term "$display"
    done
    if [ "$display" != none ]; then
        for bin in $gvim_bins; do
            run_binary "$bin" gui "$display"
        done
    fi
    stop_display
done

log "TOTAL: $total_pass passed, $total_fail failed, $total_skip skipped, $total_known known"
for run in "${skipped_runs[@]}"; do
    log "  skipped: $run"
done
for run in "${failed_runs[@]}"; do
    log "  failed: $run"
done
[ "$total_fail" -eq 0 ] && [ "${#failed_runs[@]}" -eq 0 ]
