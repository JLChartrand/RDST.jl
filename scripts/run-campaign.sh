#!/usr/bin/env bash
#
# One-command setup for a validation campaign on a dedicated machine.
#
# The pieces this wraps -- throughput.jl, campaign.jl, the systemd unit -- each
# do one thing and are documented where they live. What was still manual is the
# order and the arithmetic: benchmark before the machine gets busy, calibrate
# before committing to a plan, size --jobs from the measured peak RSS rather
# than from nproc, and install a supervisor that survives a logout and a reboot.
#
#     ./scripts/run-campaign.sh prepare --battery=crush
#     ./scripts/run-campaign.sh start   --battery=crush
#     ./scripts/run-campaign.sh run     --battery=crush   # both of the above
#     ./scripts/run-campaign.sh status  --battery=crush
#     ./scripts/run-campaign.sh stop    --battery=crush
#     ./scripts/run-campaign.sh collect --battery=crush
#
# There is no default battery, here or in campaign.jl. A stray argument must not
# be able to start a two-week BigCrush sweep.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly TEMPLATE="$SCRIPT_DIR/testu01/randomdatastreams-campaign.service"

BATTERY=""
OUT=""
JOBS=""
SKIP_BENCHMARK=0
ALLOW_DIRTY=0

# ------------------------------------------------------------------ utilities

say()  { printf '\n=== %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf '\nerror: %s\n' "$*" >&2; exit 1; }

usage() {
    sed -n '3,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "${1:-1}"
}

unit_name() { echo "randomdatastreams-$BATTERY"; }
unit_file() { echo "$HOME/.config/systemd/user/$(unit_name).service"; }

parse_args() {
    for a in "$@"; do
        case "$a" in
            --battery=*)      BATTERY="${a#*=}" ;;
            --out=*)          OUT="${a#*=}" ;;
            --jobs=*)         JOBS="${a#*=}" ;;
            --skip-benchmark) SKIP_BENCHMARK=1 ;;
            --allow-dirty)    ALLOW_DIRTY=1 ;;
            -h|--help)        usage 0 ;;
            *)                die "unknown option: $a" ;;
        esac
    done
    case "$BATTERY" in
        smallcrush|crush|bigcrush) ;;
        "") die "--battery is required: smallcrush, crush or bigcrush" ;;
        *)  die "unknown battery: $BATTERY" ;;
    esac
    OUT="${OUT:-$HOME/$BATTERY-results}"
}

# ------------------------------------------------------------------- checks

check_environment() {
    say "Checking the environment"

    command -v julia >/dev/null || die "julia is not on PATH"
    info "julia:  $(julia --version)"

    [ -f "$TEMPLATE" ] || die "missing unit template: $TEMPLATE"

    git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
        || die "$REPO_ROOT is not a git checkout -- the scripts need one, and
       every result file records the commit that produced it. Clone the
       repository rather than using an installed copy of the package."

    local commit dirty
    commit=$(git -C "$REPO_ROOT" rev-parse --short=12 HEAD)
    dirty=$(git -C "$REPO_ROOT" status --porcelain)
    info "commit: $commit"

    if [ -n "$dirty" ]; then
        if [ "$ALLOW_DIRTY" -eq 1 ]; then
            info "tree:   DIRTY (results will be marked so; you passed --allow-dirty)"
        else
            die "the working tree has uncommitted changes, so the commit recorded
       in every result file would not describe the code that ran. Commit or
       stash them, or pass --allow-dirty if you know what you are doing."
        fi
    else
        info "tree:   clean"
    fi

    systemctl --user show-environment >/dev/null 2>&1 \
        || die "systemctl --user is not available in this session. Log in over
       SSH with a proper user session, or run campaign.jl under tmux instead
       (it will not survive a reboot)."
}

# --------------------------------------------------------------- benchmarking

run_benchmark() {
    if [ "$SKIP_BENCHMARK" -eq 1 ]; then
        say "Skipping the throughput benchmark (--skip-benchmark)"
        return
    fi

    say "Throughput benchmark, before the machine gets busy"
    local out="$HOME/throughput-$(hostname)-$(date +%Y%m%d).txt"

    # Pin to one core: on a hybrid CPU the scheduler will otherwise move the
    # process between performance and efficiency cores mid-run, and the minimum
    # reported comes from whichever core happened to be fastest.
    local pin=()
    if command -v taskset >/dev/null; then
        pin=(taskset -c 0)
        info "pinned to CPU 0 -- note in the write-up which core type that is"
    else
        info "taskset not found: not pinned. On a hybrid CPU, treat the numbers"
        info "as indicative only."
    fi

    "${pin[@]}" julia -O3 "$SCRIPT_DIR/benchmarks/throughput.jl" | tee "$out"
    info "written to $out"
}

# --------------------------------------------------------------- calibration

physical_cores() {
    if command -v lscpu >/dev/null; then
        local n
        n=$(lscpu -p=Core,Socket 2>/dev/null | grep -v '^#' | sort -u | wc -l)
        [ "${n:-0}" -gt 0 ] && { echo "$n"; return; }
    fi
    getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1
}

# Sets JOBS, unless the caller already did.
calibrate() {
    say "Calibrating: one job of $BATTERY, measured"

    local log="$HOME/calibration-$BATTERY.txt"
    local cores mem_kb peak_kb
    cores=$(physical_cores)
    mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)

    if command -v /usr/bin/time >/dev/null; then
        /usr/bin/time -v julia "$SCRIPT_DIR/testu01/campaign.jl" \
            --battery="$BATTERY" --out="$OUT" --calibrate 2>&1 | tee "$log"
        peak_kb=$(awk '/Maximum resident set size/ {print $NF}' "$log" | tail -1)
    else
        info "GNU time not found: running without a memory measurement."
        julia "$SCRIPT_DIR/testu01/campaign.jl" \
            --battery="$BATTERY" --out="$OUT" --calibrate 2>&1 | tee "$log"
        peak_kb=""
    fi

    info "calibration log: $log"

    if [ -n "$JOBS" ]; then
        info "jobs: $JOBS (you set it explicitly)"
        return
    fi

    if [ -n "${peak_kb:-}" ] && [ "${peak_kb:-0}" -gt 0 ] && [ "$mem_kb" -gt 0 ]; then
        # Leave a fifth of memory to the rest of the machine, and never exceed
        # the physical core count: these jobs are CPU-bound, so hyperthreads buy
        # little and cost cache.
        local by_mem
        by_mem=$(( mem_kb * 8 / 10 / peak_kb ))
        JOBS=$(( by_mem < cores ? by_mem : cores ))
        [ "$JOBS" -lt 1 ] && JOBS=1
        info "peak RSS per job: $(( peak_kb / 1024 )) MiB"
        info "physical cores:   $cores"
        info "memory:           $(( mem_kb / 1024 / 1024 )) GiB"
        info "jobs chosen:      $JOBS   (min of cores and 80% of memory / peak)"
    else
        JOBS=$(( cores / 4 ))
        [ "$JOBS" -lt 1 ] && JOBS=1
        info "no memory measurement: falling back to cores/4 = $JOBS"
    fi
}

# ------------------------------------------------------------------ the unit

install_unit() {
    say "Installing the systemd user unit"

    mkdir -p "$(dirname "$(unit_file)")"

    sed -e "s|^WorkingDirectory=.*|WorkingDirectory=$REPO_ROOT|" \
        -e "s|^Environment=CAMPAIGN_OUT=.*|Environment=CAMPAIGN_OUT=$OUT|" \
        -e "s|^ExecStart=.*|ExecStart=/usr/bin/env julia --startup-file=no scripts/testu01/campaign.jl --battery=$BATTERY --jobs=$JOBS --out=$OUT|" \
        -e "/^ *--battery=bigcrush/d" \
        -e "s|^Description=.*|Description=RandomDataStreams.jl $BATTERY validation campaign|" \
        -e "s|^# --- edit these three.*|# --- generated by scripts/run-campaign.sh; re-run it rather than editing ---|" \
        "$TEMPLATE" > "$(unit_file)"

    # `linger` is the line that matters: without it systemd kills user services
    # at logout, which is exactly what this campaign has to survive.
    if [ "$(loginctl show-user "$USER" -p Linger --value 2>/dev/null)" != "yes" ]; then
        info "enabling linger so the campaign survives logout"
        loginctl enable-linger "$USER" \
            || info "could not enable linger -- ask an administrator, or the"
        info "campaign will stop when you disconnect."
    else
        info "linger already enabled"
    fi

    systemctl --user daemon-reload
    info "unit: $(unit_file)"
    grep '^ExecStart=' "$(unit_file)" | sed 's/^/    /'
}

# ------------------------------------------------------------------ commands

cmd_prepare() {
    check_environment
    run_benchmark
    calibrate
    install_unit

    say "Ready"
    info "output directory: $OUT"
    cat <<EOF

    Start it with:

        $0 start --battery=$BATTERY

EOF
}

cmd_start() {
    [ -f "$(unit_file)" ] || die "no unit for $BATTERY yet -- run 'prepare' first"
    systemctl --user start "$(unit_name)"
    say "Started"
    systemctl --user --no-pager status "$(unit_name)" | head -12 || true
    cat <<EOF

    It now runs without you. Useful later:

        $0 status  --battery=$BATTERY     # how far along
        $0 collect --battery=$BATTERY     # bundle the results
        touch $OUT/STOP                   # stop cleanly, keeping what is running
        $0 stop    --battery=$BATTERY     # stop now, losing only jobs in flight

    Restarting resumes: the driver reads summary.tsv and does what is missing.

EOF
}

cmd_status() {
    say "Service"
    systemctl --user --no-pager status "$(unit_name)" 2>/dev/null | head -12 \
        || info "not running"

    say "Progress"
    julia "$SCRIPT_DIR/testu01/campaign.jl" \
        --battery="$BATTERY" --out="$OUT" --status || true

    if [ -f "$OUT/summary.tsv" ]; then
        say "Finished jobs: $(( $(wc -l < "$OUT/summary.tsv") - 1 ))"
        info "in $OUT/summary.tsv"
    fi
}

cmd_stop() {
    systemctl --user stop "$(unit_name)"
    say "Stopped. Everything already finished is recorded in $OUT/summary.tsv"
}

cmd_collect() {
    [ -d "$OUT" ] || die "no output directory at $OUT"

    local stamp bundle staging
    stamp=$(date +%Y%m%d-%H%M)
    bundle="$HOME/randomdatastreams-$BATTERY-$stamp.tar.gz"
    staging=$(mktemp -d)
    trap 'rm -rf "$staging"' RETURN

    # Everything a later session needs to write up the results: the batteries,
    # the timings, the calibration, and the commit they were all measured at.
    mkdir -p "$staging/results"
    cp -r "$OUT/." "$staging/results/"
    cp "$HOME"/throughput-*.txt "$staging/" 2>/dev/null || true
    cp "$HOME"/calibration-*.txt "$staging/" 2>/dev/null || true

    {
        echo "host:    $(hostname)"
        echo "date:    $(date -Is)"
        echo "battery: $BATTERY"
        echo "commit:  $(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
        echo "julia:   $(julia --version)"
        command -v lscpu >/dev/null && lscpu | grep -E 'Model name|^CPU\(s\)|Thread|Core'
    } > "$staging/environment.txt"

    tar -czf "$bundle" -C "$staging" .

    say "Bundled"
    info "$bundle  ($(du -h "$bundle" | cut -f1))"
}

# ---------------------------------------------------------------------- main

[ $# -ge 1 ] || usage 1
command="$1"; shift

case "$command" in -h|--help|help) usage 0 ;; esac

parse_args "$@"

case "$command" in
    prepare) cmd_prepare ;;
    start)   cmd_start ;;
    run)     cmd_prepare; cmd_start ;;
    status)  cmd_status ;;
    stop)    cmd_stop ;;
    collect) cmd_collect ;;
    -h|--help|help) usage 0 ;;
    *)       die "unknown command: $command" ;;
esac
