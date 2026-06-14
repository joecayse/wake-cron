#!/usr/bin/env bats
# =============================================================================
# wake-cron test suite
# Mocks: sudo, pmset, launchctl — no root or real LaunchAgents required.
# =============================================================================

WAKE_CRON="$BATS_TEST_DIRNAME/../wake-cron"
MOCK_DIR="$BATS_TEST_DIRNAME/mocks"

setup() {
    export MOCK_LOG
    MOCK_LOG=$(mktemp -d)
    export WAKE_CRON_PLIST_DIR="$MOCK_LOG/LaunchAgents"
    export WAKE_CRON_JOBS_FILE="$MOCK_LOG/jobs"
    mkdir -p "$WAKE_CRON_PLIST_DIR"
    export PATH="$MOCK_DIR:$PATH"
}

teardown() {
    rm -rf "$MOCK_LOG"
}

# Helper: run wake-cron and capture output + exit code
wkcron() { run bash "$WAKE_CRON" "$@"; }

# Helper: assert a string appears in output (-- prevents grep treating value as a flag)
contains() { echo "$output" | grep -qF -- "$1"; }

# =============================================================================
# Argument validation
# =============================================================================

@test "no arguments prints usage and exits non-zero" {
    wkcron
    [ "$status" -ne 0 ]
    contains "wake-cron"
}

@test "wrong number of arguments exits non-zero" {
    wkcron 06:15
    [ "$status" -ne 0 ]
}

@test "invalid time format is rejected" {
    wkcron "25:00" "/bin/true"
    [ "$status" -ne 0 ]
    contains "Invalid time format"
}

@test "invalid time format — letters rejected" {
    wkcron "ab:cd" "/bin/true"
    [ "$status" -ne 0 ]
    contains "Invalid time format"
}

@test "unknown flag exits non-zero" {
    wkcron 06:15 "/bin/true" --bogus
    [ "$status" -ne 0 ]
}

# =============================================================================
# Issue #2: Help flag
# =============================================================================

@test "-help exits 0 and prints usage" {
    wkcron -help
    [ "$status" -eq 0 ]
    contains "COMMANDS"
    contains "--timeout"
}

@test "--help exits 0 and prints usage" {
    wkcron --help
    [ "$status" -eq 0 ]
    contains "COMMANDS"
}

# =============================================================================
# Scheduling a job
# =============================================================================

@test "schedule creates a plist file" {
    wkcron 06:15 "/bin/true"
    [ "$status" -eq 0 ]
    local hash
    hash=$(echo "/bin/true" | md5 -q | head -c 8)
    [ -f "$WAKE_CRON_PLIST_DIR/com.wake-cron.${hash}.plist" ]
}

@test "schedule prints JOB_ID in output" {
    wkcron 06:15 "/bin/true"
    [ "$status" -eq 0 ]
    local hash
    hash=$(echo "/bin/true" | md5 -q | head -c 8)
    contains "$hash"
}

@test "schedule adds entry to jobs registry" {
    wkcron 06:15 "/bin/true"
    [ "$status" -eq 0 ]
    [ -f "$WAKE_CRON_JOBS_FILE" ]
    grep -qF "/bin/true" "$WAKE_CRON_JOBS_FILE"
}

@test "schedule calls launchctl load" {
    wkcron 06:15 "/bin/true"
    grep -q "launchctl load" "$MOCK_LOG/launchctl_calls"
}

@test "schedule calls pmset with wake time" {
    wkcron 06:15 "/bin/true"
    grep -q "pmset repeat wake" "$MOCK_LOG/pmset_calls"
}

@test "plist contains correct exec hour and minute" {
    wkcron 06:15 "/bin/true"
    local hash plist
    hash=$(echo "/bin/true" | md5 -q | head -c 8)
    plist="$WAKE_CRON_PLIST_DIR/com.wake-cron.${hash}.plist"
    grep -q "<integer>6</integer>" "$plist"
    grep -q "<integer>15</integer>" "$plist"
}

@test "plist wraps command with timeout" {
    wkcron 06:15 "/bin/true"
    local hash plist
    hash=$(echo "/bin/true" | md5 -q | head -c 8)
    plist="$WAKE_CRON_PLIST_DIR/com.wake-cron.${hash}.plist"
    grep -q "timeout" "$plist"
}

@test "plist uses login shell flag -l" {
    wkcron 06:15 "/bin/true"
    local hash plist
    hash=$(echo "/bin/true" | md5 -q | head -c 8)
    plist="$WAKE_CRON_PLIST_DIR/com.wake-cron.${hash}.plist"
    grep -q "\-l" "$plist"
}

@test "schedule is idempotent — second call does not duplicate registry entry" {
    wkcron 06:15 "/bin/true"
    wkcron 06:15 "/bin/true"
    local count
    count=$(grep -c "/bin/true" "$WAKE_CRON_JOBS_FILE" || true)
    [ "$count" -eq 1 ]
}

# =============================================================================
# Issue #1: Timeout guardrail
# =============================================================================

@test "default timeout is 300s" {
    wkcron 06:15 "/bin/true"
    contains "300s"
}

@test "--timeout flag overrides default" {
    wkcron 06:15 "/bin/true" --timeout 60
    contains "60s"
    local hash plist
    hash=$(echo "/bin/true" | md5 -q | head -c 8)
    plist="$WAKE_CRON_PLIST_DIR/com.wake-cron.${hash}.plist"
    grep -q "timeout 60" "$plist"
}

@test "--timeout requires a numeric argument" {
    wkcron 06:15 "/bin/true" --timeout abc
    [ "$status" -ne 0 ]
}

# =============================================================================
# pmset wake time calculation (5-minute buffer)
# =============================================================================

@test "wake time is 5 minutes before exec time" {
    wkcron 06:15 "/bin/true"
    grep -q "06:10:00" "$MOCK_LOG/pmset_calls"
}

@test "wake time wraps correctly at hour boundary (06:00 → 05:55)" {
    wkcron 06:00 "/bin/true"
    grep -q "05:55:00" "$MOCK_LOG/pmset_calls"
}

@test "wake time wraps correctly at midnight (00:00 → 23:55)" {
    wkcron 00:00 "/bin/true"
    grep -q "23:55:00" "$MOCK_LOG/pmset_calls"
}

# =============================================================================
# Multiple jobs — pmset uses earliest wake time
# =============================================================================

@test "with two jobs pmset is set to earliest wake time" {
    wkcron 08:00 "/bin/echo early"
    wkcron 14:00 "/bin/echo late"
    # 08:00 job wakes at 07:55; 14:00 job wakes at 13:55
    # final pmset call must be 07:55
    local last_pmset
    last_pmset=$(grep "pmset repeat wake" "$MOCK_LOG/pmset_calls" | tail -1)
    echo "$last_pmset" | grep -q "07:55:00"
}

# =============================================================================
# Issue #4: list subcommand
# =============================================================================

@test "list with no jobs prints friendly message" {
    wkcron list
    [ "$status" -eq 0 ]
    contains "No wake-cron jobs"
}

@test "list shows scheduled job" {
    wkcron 06:15 "/bin/true"
    wkcron list
    [ "$status" -eq 0 ]
    contains "/bin/true"
    contains "06:15"
}

@test "list shows JOB_ID" {
    wkcron 06:15 "/bin/true"
    local hash
    hash=$(echo "/bin/true" | md5 -q | head -c 8)
    wkcron list
    contains "$hash"
}

@test "list shows REMAINING column" {
    wkcron 06:15 "/bin/true"
    wkcron list
    contains "REMAINING"
}

@test "list shows STATUS column" {
    wkcron 06:15 "/bin/true"
    wkcron list
    contains "STATUS"
}

# =============================================================================
# Issue #3: modify subcommand
# =============================================================================

@test "modify updates exec time in registry" {
    wkcron 06:15 "/bin/true"
    local hash
    hash=$(echo "/bin/true" | md5 -q | head -c 8)
    wkcron modify "$hash" 08:30
    [ "$status" -eq 0 ]
    grep -q "8|30" "$WAKE_CRON_JOBS_FILE"
}

@test "modify reloads the plist" {
    wkcron 06:15 "/bin/true"
    local hash
    hash=$(echo "/bin/true" | md5 -q | head -c 8)
    wkcron modify "$hash" 08:30
    local load_count
    load_count=$(/usr/bin/grep -c "launchctl load" "$MOCK_LOG/launchctl_calls" || true)
    [ "$load_count" -ge 2 ]
}

@test "modify with invalid JOB_ID exits non-zero" {
    wkcron modify "deadbeef" 08:30
    [ "$status" -ne 0 ]
    contains "No job found"
}

@test "modify with invalid time format exits non-zero" {
    wkcron 06:15 "/bin/true"
    local hash
    hash=$(echo "/bin/true" | md5 -q | head -c 8)
    wkcron modify "$hash" "25:99"
    [ "$status" -ne 0 ]
    contains "Invalid time format"
}

@test "modify preserves command payload" {
    wkcron 06:15 "/bin/true"
    local hash
    hash=$(echo "/bin/true" | md5 -q | head -c 8)
    wkcron modify "$hash" 09:00
    local plist="$WAKE_CRON_PLIST_DIR/com.wake-cron.${hash}.plist"
    grep -q "/bin/true" "$plist"
}

# =============================================================================
# Issue #5: remove subcommand
# =============================================================================

@test "remove unloads and deletes the plist" {
    wkcron 06:15 "/bin/true"
    local hash
    hash=$(echo "/bin/true" | md5 -q | head -c 8)
    wkcron remove "$hash"
    [ "$status" -eq 0 ]
    [ ! -f "$WAKE_CRON_PLIST_DIR/com.wake-cron.${hash}.plist" ]
}

@test "remove cleans registry entry" {
    wkcron 06:15 "/bin/true"
    local hash
    hash=$(echo "/bin/true" | md5 -q | head -c 8)
    wkcron remove "$hash"
    ! grep -qF "/bin/true" "$WAKE_CRON_JOBS_FILE" 2>/dev/null || \
        [ "$(grep -c "/bin/true" "$WAKE_CRON_JOBS_FILE")" -eq 0 ]
}

@test "remove calls pmset cancel when last job is removed" {
    wkcron 06:15 "/bin/true"
    local hash
    hash=$(echo "/bin/true" | md5 -q | head -c 8)
    wkcron remove "$hash"
    grep -q "pmset repeat cancel" "$MOCK_LOG/pmset_calls"
}

@test "remove with invalid JOB_ID exits non-zero" {
    wkcron remove "deadbeef"
    [ "$status" -ne 0 ]
    contains "No job found"
}

@test "remove leaves remaining jobs intact" {
    wkcron 06:15 "/bin/echo job-a"
    wkcron 09:00 "/bin/echo job-b"
    local hash_a
    hash_a=$(echo "/bin/echo job-a" | md5 -q | head -c 8)
    wkcron remove "$hash_a"
    grep -qF "/bin/echo job-b" "$WAKE_CRON_JOBS_FILE"
}
