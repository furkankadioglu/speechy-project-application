#!/usr/bin/env bash
# Speechy — aggregate test runner. Runs API, client (Swift), and UI suites in
# sequence and exits non-zero if any suite fails.
#
#   ./run-all-tests.sh          # run everything
#   ./run-all-tests.sh api      # run a single suite (api | client | ui)
#   ./run-all-tests.sh --fast   # skip UI (needs npm + browser install on fresh clones)

cd "$(dirname "$0")"

# ── Config ────────────────────────────────────────────────────────────────────
SUITES=(api client ui)
FILTER="${1:-}"
case "$FILTER" in
    --fast) SUITES=(api client) ;;
    api|client|ui) SUITES=("$FILTER") ;;
    "") ;;
    -h|--help)
        sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        echo "Unknown argument: $FILTER" >&2
        exit 2
        ;;
esac

# ── Paths ─────────────────────────────────────────────────────────────────────
API_RUN="tests/api/run.sh"
CLIENT_RUN="desktop/SpeechToText/Tests/run.sh"
UI_RUN="tests/ui/run.sh"

LOG_DIR="tests/logs"
mkdir -p "$LOG_DIR"

# ── Output helpers ────────────────────────────────────────────────────────────
BOLD=$'\033[1m'; GREEN=$'\033[32m'; RED=$'\033[31m'; BLUE=$'\033[34m'; DIM=$'\033[2m'; RESET=$'\033[0m'

heading() { printf "\n%s━━━ %s ━━━%s\n\n" "$BOLD$BLUE" "$1" "$RESET"; }
pass()    { printf "%s✓%s %s\n" "$GREEN" "$RESET" "$1"; }
fail()    { printf "%s✗%s %s\n" "$RED" "$RESET" "$1"; }

# ── Run a suite, capture exit code + duration ────────────────────────────────
run_suite() {
    local name="$1" script="$2" logfile="$LOG_DIR/$name-combined.log"

    if [[ ! -x "$script" ]]; then
        chmod +x "$script" 2>/dev/null || true
    fi

    heading "$name"
    local started=$SECONDS
    if bash "$script" 2>&1 | tee "$logfile"; then
        local code=${PIPESTATUS[0]}
    else
        local code=${PIPESTATUS[0]}
    fi
    local elapsed=$(( SECONDS - started ))

    if [[ $code -eq 0 ]]; then
        pass "$name suite passed ${DIM}(${elapsed}s)${RESET}"
    else
        fail "$name suite FAILED with exit $code ${DIM}(${elapsed}s, see $logfile)${RESET}"
    fi
    return $code
}

# ── Main ──────────────────────────────────────────────────────────────────────
total_failed=0
summary_lines=()

for suite in "${SUITES[@]}"; do
    case "$suite" in
        api)    run_suite "api"    "$API_RUN"    ;;
        client) run_suite "client" "$CLIENT_RUN" ;;
        ui)     run_suite "ui"     "$UI_RUN"     ;;
    esac
    code=$?
    if [[ $code -eq 0 ]]; then
        summary_lines+=("PASS $suite")
    else
        summary_lines+=("FAIL $suite (exit $code)")
        total_failed=$((total_failed + 1))
    fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
heading "Summary"
for line in "${summary_lines[@]}"; do
    if [[ "$line" == PASS* ]]; then
        pass "${line#PASS }"
    else
        fail "${line#FAIL }"
    fi
done
printf "\n"

if [[ $total_failed -eq 0 ]]; then
    printf "%sAll %d suite(s) passed.%s\n" "$GREEN$BOLD" "${#SUITES[@]}" "$RESET"
    exit 0
else
    printf "%s%d suite(s) failed.%s\n" "$RED$BOLD" "$total_failed" "$RESET"
    exit 1
fi
