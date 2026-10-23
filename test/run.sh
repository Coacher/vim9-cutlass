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
configs=${CONFIGS:-black named distinct plus star exclude usermap cut}
timeout_seconds=${TIMEOUT:-900}
verbose=${VERBOSE:-0}

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

# The GUI flavour only shows in the "version with GTK3 GUI." line
has_gui() {
    "$1" --version 2>/dev/null | grep -q 'version with [^ ]* GUI\.'
}

has_vim9script() {
    env -i "${base_env[@]}" "$1" -v -u NONE -i NONE -N --not-a-term -es \
        -c 'if has("vim9script") | qall! | endif' -c 'cquit!' </dev/null >/dev/null 2>&1
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

# Builds without Vim9 script must reject the plugin without side effects
degraded_check() {
    local bin=$1 run_dir=$2 out
    # Without 'nomore' the error list stops at a More prompt that never ends
    out=$(timeout -s KILL "$timeout_seconds" env -i "${base_env[@]}" "$bin" -u NONE -i NONE -N --not-a-term \
        -c 'set nomore' -c "source $repo_dir/plugin/cutlass.vim" -c 'map' -c 'map!' -c 'qall!' \
        </dev/null 2>&1)
    local status=$?
    printf '%s\n' "$out" >"$run_dir/vim.log"
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

run_process() {
    local bin=$1 kind=$2 display=$3 config=$4
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
        "CUTLASS_CASES=${CASES:-}" "CUTLASS_MATRICES=${MATRICES:-}" \
        timeout -s KILL "$timeout_seconds" "$bin" "${args[@]}" </dev/null >"$run_dir/vim.log" 2>&1
    local status=$?
    if [ ! -f "$run_dir/report.txt" ]; then
        log "FAIL $display/$config/$name-$kind: no report, exit status $status, see $run_dir/vim.log"
        if [ -n "${GITHUB_ACTIONS:-}" ]; then
            printf '::error title=%s::no report, exit status %s\n' "$display/$config/$name-$kind" "$status"
        fi
        total_fail=$((total_fail + 1))
        failed_runs+=("$display/$config/$name-$kind")
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
    local summary
    summary=$(grep '^SUMMARY' "$run_dir/report.txt")
    local pass fail skip known
    pass=$(printf '%s' "$summary" | sed -n 's/.*: \([0-9]*\) passed.*/\1/p')
    fail=$(printf '%s' "$summary" | sed -n 's/.* \([0-9]*\) failed.*/\1/p')
    skip=$(printf '%s' "$summary" | sed -n 's/.* \([0-9]*\) skipped.*/\1/p')
    known=$(printf '%s' "$summary" | sed -n 's/.* \([0-9]*\) known.*/\1/p')
    total_pass=$((total_pass + ${pass:-0}))
    total_fail=$((total_fail + ${fail:-0}))
    total_skip=$((total_skip + ${skip:-0}))
    total_known=$((total_known + ${known:-0}))
    if [ "${fail:-0}" -gt 0 ] || [ -z "$summary" ]; then
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
    if [ "$kind" = gui ] && ! has_gui "$bin"; then
        log "SKIP $bin: no GUI support"
        skipped_runs+=("$bin: no GUI")
        return
    fi
    if ! has_vim9script "$bin"; then
        if [ "$display" = none ]; then
            local run_dir="$results/$display/degraded/$(basename "$bin")-$kind"
            mkdir -p "$run_dir"
            degraded_check "$bin" "$run_dir"
        fi
        return
    fi
    if [ "$kind" = gui ] && ! gui_starts "$bin"; then
        log "SKIP $bin: GUI cannot run on display $display"
        skipped_runs+=("$bin: no GUI on $display")
        return
    fi
    for config in $configs; do
        run_process "$bin" "$kind" "$display" "$config"
    done
}

mkdir -p "$results"
for display in $displays; do
    if ! start_display "$display"; then
        log "SKIP display $display: $skip_reason"
        skipped_runs+=("display $display: $skip_reason")
        continue
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
