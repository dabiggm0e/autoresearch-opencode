#!/bin/bash
# enforce-autoresearch-state.sh - State enforcement for autoresearch.jsonl
# Usage: bash ./scripts/enforce-autoresearch-state.sh <command> [args]
# Reference: SKILL.md autoresearch skill specification
set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly JSONL_FILE="${PROJECT_ROOT}/autoresearch.jsonl"
readonly MD_FILE="${PROJECT_ROOT}/autoresearch.md"
readonly WORKLOG_FILE="${PROJECT_ROOT}/worklog.md"
readonly BACKUP_SCRIPT="${SCRIPT_DIR}/backup-state.sh"

# Exit codes (SKILL.md line 50)
readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_FAILURE=1
readonly EXIT_JSONL_CORRUPTION=2
readonly EXIT_MISSING_BASELINE=3
readonly EXIT_MARKDOWN_INCONSISTENCY=4
readonly EXIT_ATOMIC_WRITE_FAILURE=5
readonly EXIT_RECOVERY_FAILED=6

# =============================================================================
# UTILITY FUNCTIONS (SKILL.md line 15-22)
# =============================================================================

print_error() { echo "ERROR: $1" >&2; }
print_warning() { echo "WARNING: $1" >&2; }
print_info() { echo "INFO: $1"; }
print_success() { echo "SUCCESS: $1"; }

assert_file_exists() {
    local file="$1" description="${2:-file}"
    [[ ! -f "$file" ]] && { print_error "${description} missing: ${file}"; return 1; }
    return 0
}

atomic_write() {
    local target_file="$1" content="$2" temp_file="${1}.tmp.$$"
    echo "$content" > "$temp_file" 2>/dev/null || { rm -f "$temp_file"; return 1; }
    mv "$temp_file" "$target_file" 2>/dev/null || { rm -f "$temp_file"; return 1; }
}

# =============================================================================
# STATE QUERIES (SKILL.md line 100-106)
# =============================================================================

get_current_run_count() {
    [[ ! -f "$JSONL_FILE" ]] && { echo 0; return 0; }
    local count
    count=$(grep -c '"type":"run"' "$JSONL_FILE" 2>/dev/null) || count=0
    echo "$count"
}

get_next_run_number() { echo $(($(get_current_run_count) + 1)); }

get_last_updated_marker() {
    [[ ! -f "$MD_FILE" ]] && return 0
    grep -m 1 "^Last updated: Run #" "$MD_FILE" 2>/dev/null | sed 's/^Last updated: //' || echo ""
}

get_best_kept_metric() {
    [[ ! -f "$JSONL_FILE" ]] && return 0
    grep '"status":"kept"' "$JSONL_FILE" 2>/dev/null | grep -o '"metric":"[^"]*"' | head -1 | sed 's/"metric":"\([^"]*\)"/\1/' || echo ""
}

get_last_result_hash() {
    [[ ! -f "$JSONL_FILE" ]] && return 0
    grep '"type":"result"' "$JSONL_FILE" 2>/dev/null | tail -1 | grep -o '"hash":"[^"]*"' | sed 's/"hash":"\([^"]*\)"/\1/' || echo ""
}

get_run_by_number() {
    local run_num="$1" current=0
    [[ ! -f "$JSONL_FILE" ]] && return 0
    while IFS= read -r line; do
        [[ "$line" =~ \"type\":\"run\" ]] && { ((current++)); [[ $current -eq $run_num ]] && { echo "$line"; return 0; }; }
    done < "$JSONL_FILE"
    return 1
}

get_result_by_run() {
    local run_num="$1" in_run=0 current_run=0 result_run=0
    [[ ! -f "$JSONL_FILE" ]] && return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ \"type\":\"run\" ]]; then
            ((current_run++))
            in_run=1
        elif [[ "$line" =~ \"type\":\"result\" ]] && [[ $in_run -eq 1 ]]; then
            result_run=$(echo "$line" | grep -o '"run":[0-9]*' | cut -d: -f2 || echo "0")
            if [[ "$result_run" == "$run_num" ]]; then
                echo "$line"
                return 0
            fi
            in_run=0
        fi
    done < "$JSONL_FILE"
    return 1
}

# =============================================================================
# VALIDATION (SKILL.md line 107-108)
# =============================================================================

validate_jsonl_syntax() {
    local line_num=0 errors=0
    [[ ! -f "$JSONL_FILE" ]] && { print_error "JSONL missing: ${JSONL_FILE}"; return 1; }
    [[ ! -s "$JSONL_FILE" ]] && { print_error "JSONL empty: ${JSONL_FILE}"; return 1; }
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++)) || true
        [[ -z "$line" ]] && continue
        echo "$line" | jq . >/dev/null 2>&1 || { print_error "Invalid JSON line ${line_num}: ${line:0:100}"; ((errors++)); }
    done < "$JSONL_FILE"
    
    [[ $errors -gt 0 ]] && { print_error "JSONL validation failed: ${errors} errors"; return 1; }
    return 0
}

validate_config_header() {
    local first_line=$(head -n 1 "$JSONL_FILE" 2>/dev/null || echo "")
    echo "$first_line" | jq -e '.type == "config"' >/dev/null 2>&1 || \
        { print_error "Missing/invalid config header"; return 1; }
    return 0
}

# =============================================================================
# CONSISTENCY CHECKS (SKILL.md line 200-203)
# =============================================================================

check_run_sequence() {
    [[ ! -f "$JSONL_FILE" ]] && { print_error "JSONL missing for sequence check"; return 1; }
    
    local run_count
    run_count=$(get_current_run_count | tr -d '\n ')
    local expected=1 actual=0
    [[ $run_count -eq 0 ]] && { print_info "No runs in JSONL"; return 0; }
    
    while IFS= read -r line; do
        if [[ "$line" =~ \"type\":\"run\" ]]; then
            ((actual++)) || true
            [[ $actual -ne $expected ]] && { print_error "Run gap: expected ${expected}, got ${actual}"; return 1; }
            ((expected++)) || true
        fi
    done < "$JSONL_FILE"
    
    [[ $actual -ne $run_count ]] && { print_error "Count mismatch: ${actual} vs ${run_count}"; return 1; }
    return 0
}

check_markdown_consistency() {
    [[ ! -f "$MD_FILE" ]] && { print_warning "Markdown missing"; return 0; }
    [[ ! -f "$JSONL_FILE" ]] && { print_warning "JSONL missing"; return 0; }
    
    local jsonl_count=$(get_current_run_count) md_marker=$(get_last_updated_marker)
    [[ -z "$md_marker" ]] && { [[ $jsonl_count -gt 0 ]] && { print_error "Missing marker with ${jsonl_count} runs"; return 1; }; return 0; }
    
    local md_run=$(echo "$md_marker" | grep -o 'Run #[0-9]*' | grep -o '[0-9]*' || echo "0")
    [[ "$md_run" != "$jsonl_count" ]] && { print_error "MD mismatch: marker #${md_run} vs JSONL #${jsonl_count}"; return 1; }
    return 0
}

check_worklog_consistency() {
    [[ ! -f "$WORKLOG_FILE" ]] && { print_warning "Worklog missing"; return 0; }
    [[ ! -f "$JSONL_FILE" ]] && { print_warning "JSONL missing"; return 0; }
    
    local jsonl_count=$(get_current_run_count) worklog_count=$(grep -c "^# Run #" "$WORKLOG_FILE" 2>/dev/null || echo 0)
    [[ $worklog_count -ne $jsonl_count ]] && { print_warning "Worklog/JSONL mismatch: ${worklog_count} vs ${jsonl_count}"; return 1; }
    return 0
}

check_result_completeness() {
    [[ ! -f "$JSONL_FILE" ]] && { print_error "JSONL missing"; return 1; }
    
    local run_count=$(get_current_run_count) missing=0
    [[ $run_count -eq 0 ]] && { print_info "No runs to check"; return 0; }
    
    for ((run=1; run<=run_count; run++)); do
        get_result_by_run "$run" >/dev/null 2>&1 || { print_error "Run #${run} missing result"; ((missing++)); }
    done
    
    [[ $missing -gt 0 ]] && { print_error "Missing results: ${missing}"; return 1; }
    return 0
}

# =============================================================================
# VIOLATION DETECTION (SKILL.md line 250-253)
# =============================================================================

detect_format_violations() {
    [[ ! -f "$JSONL_FILE" ]] && return 0
    
    local violations=0 run_count=$(get_current_run_count)
    [[ $run_count -eq 0 ]] && return 0
    
    while IFS= read -r result_line; do
        local result_run=$(echo "$result_line" | grep -o '"run":[0-9]*' | grep -o '[0-9]*' || echo "0")
        [[ $result_run -gt $run_count || $result_run -eq 0 ]] && { print_error "Orphan result: run=${result_run}"; ((violations++)); }
    done < <(grep '"type":"result"' "$JSONL_FILE" 2>/dev/null || true)
    
    [[ $violations -gt 0 ]] && return 1
    return 0
}

detect_orphan_results() {
    [[ ! -f "$JSONL_FILE" ]] && return 0
    local run_count=$(get_current_run_count)
    [[ $run_count -eq 0 ]] && return 0
    
    while IFS= read -r result_line; do
        local result_run=$(echo "$result_line" | grep -o '"run":[0-9]*' | grep -o '[0-9]*' || echo "0")
        [[ $result_run -gt $run_count || $result_run -eq 0 ]] && { print_error "Orphan result: run=${result_run}"; return 1; }
    done < <(grep '"type":"result"' "$JSONL_FILE" 2>/dev/null || true)
    return 0
}

detect_missing_baseline() {
    [[ ! -f "$JSONL_FILE" ]] && { print_error "JSONL missing"; return 1; }
    
    local first_run=$(grep -m 1 '"type":"run"' "$JSONL_FILE" 2>/dev/null | head -1 || echo "")
    [[ -z "$first_run" ]] && { print_error "No runs - baseline missing"; return 1; }
    
    local first_run_num=$(echo "$first_run" | grep -o '"run":[0-9]*' | grep -o '[0-9]*' || echo "0")
    [[ "$first_run_num" != "1" ]] && { print_error "Baseline missing - first run is #${first_run_num}"; return 1; }
    return 0
}

detect_missing_marker() {
    [[ ! -f "$MD_FILE" ]] && { print_error "Markdown missing: ${MD_FILE}"; return 1; }
    grep -q "^Last updated:" "$MD_FILE" 2>/dev/null || { print_error "Missing 'Last updated' marker"; return 1; }
    return 0
}

# =============================================================================
# COMMANDS (SKILL.md line 350-355)
# =============================================================================

command_validate() {
    print_info "Starting comprehensive validation..."
    local errors=0
    
    assert_file_exists "$JSONL_FILE" "JSONL" || ((errors++)) || true
    
    if [[ $errors -eq 0 ]]; then
        validate_jsonl_syntax || ((errors++)) || true
        validate_config_header || ((errors++)) || true
        check_run_sequence || ((errors++)) || true
        check_result_completeness || ((errors++)) || true
        detect_format_violations || ((errors++)) || true
        detect_missing_baseline || ((errors++)) || true
        detect_orphan_results || ((errors++)) || true
        if [[ -f "$MD_FILE" ]]; then
            check_markdown_consistency || ((errors++)) || true
        fi
        if [[ -f "$WORKLOG_FILE" ]]; then
            check_worklog_consistency || ((errors++)) || true
        fi
    fi
    
    [[ $errors -gt 0 ]] && { print_error "Validation failed: ${errors} errors"; return $EXIT_GENERAL_FAILURE; }
    print_success "Validation passed - state consistent"
    return $EXIT_SUCCESS
}

command_pre_experiment() {
    print_info "Running pre-experiment validation..."
    
    assert_file_exists "$JSONL_FILE" "JSONL" || { print_error "Cannot start: JSONL missing"; return $EXIT_GENERAL_FAILURE; }
    detect_missing_baseline || { print_error "Cannot start: baseline missing"; return $EXIT_MISSING_BASELINE; }
    validate_jsonl_syntax || { print_error "Cannot start: JSONL errors"; return $EXIT_JSONL_CORRUPTION; }
    assert_file_exists "$MD_FILE" "Markdown" || { print_error "Cannot start: Markdown missing"; return $EXIT_GENERAL_FAILURE; }
    detect_missing_marker || { print_error "Cannot start: marker missing"; return $EXIT_MARKDOWN_INCONSISTENCY; }
    detect_format_violations || { print_error "Cannot start: format violations"; return $EXIT_GENERAL_FAILURE; }
    
    print_success "Pre-experiment validation passed"
    print_info "State: $(get_current_run_count) run(s), best: $(get_best_kept_metric)"
    return $EXIT_SUCCESS
}

command_log_result() {
    local run_num="$1" hash="$2" metric="$3" status="$4" description="$5"
    
    [[ -z "$run_num" || -z "$hash" || -z "$metric" || -z "$status" || -z "$description" ]] && \
        { print_error "Missing arguments"; return $EXIT_GENERAL_FAILURE; }
    [[ ! "$run_num" =~ ^[0-9]+$ ]] && { print_error "Invalid run: ${run_num}"; return $EXIT_GENERAL_FAILURE; }
    [[ "$status" != "kept" && "$status" != "replaced" ]] && { print_error "Invalid status: ${status}"; return $EXIT_GENERAL_FAILURE; }
    [[ ! -f "$JSONL_FILE" ]] && { print_error "JSONL missing"; return $EXIT_GENERAL_FAILURE; }
    validate_jsonl_syntax || { print_error "Cannot log: JSONL errors"; return $EXIT_JSONL_CORRUPTION; }
    get_run_by_number "$run_num" >/dev/null 2>&1 || { print_error "Run #${run_num} missing"; return $EXIT_GENERAL_FAILURE; }
    get_result_by_run "$run_num" >/dev/null 2>&1 && { print_error "Result exists for run #${run_num}"; return $EXIT_GENERAL_FAILURE; }
    [[ ! -w "$(dirname "$JSONL_FILE")" ]] && { print_error "Not writable"; return $EXIT_ATOMIC_WRITE_FAILURE; }
    
    local result_entry=$(jq -n --argjson run "$run_num" --arg hash "$hash" --arg metric "$metric" \
        --arg status "$status" --arg desc "$description" \
        '{type: "result", run: $run, hash: $hash, metric: $metric, status: $status, description: $desc}')
    
    local new_content=$(cat "$JSONL_FILE")$'\n'"${result_entry}"
    atomic_write "$JSONL_FILE" "$new_content" || { print_error "Write failed"; return $EXIT_ATOMIC_WRITE_FAILURE; }
    
    if [[ -f "$MD_FILE" ]]; then
        local marker="Last updated: Run #${run_num}"
        if grep -q "^Last updated:" "$MD_FILE" 2>/dev/null; then
            sed "s/^Last updated:.*/${marker}/" "$MD_FILE" > "${MD_FILE}.tmp.$$" && mv "${MD_FILE}.tmp.$$" "$MD_FILE"
        else
            echo "$marker" >> "$MD_FILE"
        fi
    fi
    
    print_success "Result logged for run #${run_num}: ${metric} (${status})"
    return $EXIT_SUCCESS
}

command_detect_violations() {
    print_info "Scanning for all violations..."
    local violations=0
    
    echo "=== Violation Detection Report ==="
    
    echo "1. Format Violations:"
    if detect_format_violations 2>/dev/null; then
        echo "   [PASS] OK"
    else
        ((violations++)) || true
        echo "   [FAIL] Format violations detected"
    fi
    
    echo "2. Missing Baseline:"
    if detect_missing_baseline 2>/dev/null; then
        echo "   [PASS] OK"
    else
        ((violations++)) || true
        echo "   [FAIL] Baseline missing"
    fi
    
    echo "3. Missing Marker:"
    if detect_missing_marker 2>/dev/null; then
        echo "   [PASS] OK"
    else
        ((violations++)) || true
        echo "   [FAIL] Marker missing"
    fi
    
    echo "4. Orphan Results:"
    if detect_orphan_results 2>/dev/null; then
        echo "   [PASS] OK"
    else
        ((violations++)) || true
        echo "   [FAIL] Orphan results detected"
    fi
    
    echo "5. Run Sequence:"
    if check_run_sequence 2>/dev/null; then
        echo "   [PASS] OK"
    else
        ((violations++)) || true
        echo "   [FAIL] Run sequence broken"
    fi
    
    echo "6. Result Completeness:"
    if check_result_completeness 2>/dev/null; then
        echo "   [PASS] OK"
    else
        ((violations++)) || true
        echo "   [FAIL] Missing results"
    fi
    
    echo "7. Markdown Consistency:"
    if check_markdown_consistency 2>/dev/null; then
        echo "   [PASS] OK"
    else
        ((violations++)) || true
        echo "   [FAIL] Markdown inconsistent"
    fi
    
    echo "8. Worklog Consistency:"
    if check_worklog_consistency 2>/dev/null; then
        echo "   [PASS] OK"
    else
        ((violations++)) || true
        echo "   [FAIL] Worklog inconsistent"
    fi
    
    echo "=== Summary: ${violations} violations ==="
    [[ $violations -eq 0 ]] && { print_success "No violations"; return $EXIT_SUCCESS; }
    print_error "Violations: ${violations}"; return $EXIT_GENERAL_FAILURE
}

command_recovery() {
    print_info "Attempting recovery..."
    
    [[ ! -f "$BACKUP_SCRIPT" ]] && { print_error "Backup script missing"; print_warning "Manual recovery required"; return $EXIT_RECOVERY_FAILED; }
    
    bash "$BACKUP_SCRIPT" --restore 2>&1 || { print_error "Backup restore failed"; return $EXIT_RECOVERY_FAILED; }
    
    if validate_jsonl_syntax && check_run_sequence && detect_missing_baseline; then
        print_success "Recovery successful"
        return $EXIT_SUCCESS
    else
        print_error "Recovery verification failed"
        return $EXIT_RECOVERY_FAILED
    fi
}

command_summary() {
    print_info "=== Autoresearch State Summary ==="
    
    if [[ -f "$JSONL_FILE" ]]; then
        echo "JSONL: ${JSONL_FILE}"
        echo "Runs: $(get_current_run_count)"
        echo "Last Hash: $(get_last_result_hash)"
        echo "Best Metric: $(get_best_kept_metric)"
    else
        echo "JSONL: NOT FOUND"
    fi
    
    if [[ -f "$MD_FILE" ]]; then
        echo "Markdown: ${MD_FILE}"
        echo "Marker: $(get_last_updated_marker)"
    else
        echo "Markdown: NOT FOUND"
    fi
    
    if [[ -f "$WORKLOG_FILE" ]]; then
        echo "Worklog: ${WORKLOG_FILE} ($(grep -c "^# Run #" "$WORKLOG_FILE" 2>/dev/null || echo 0) runs)"
    else
        echo "Worklog: NOT FOUND"
    fi
    
    echo "Status:"
    check_run_sequence 2>/dev/null && echo "  [OK] Sequence" || echo "  [FAIL] Sequence"
    detect_missing_baseline 2>/dev/null && echo "  [OK] Baseline" || echo "  [FAIL] Baseline"
    check_markdown_consistency 2>/dev/null && echo "  [OK] Markdown" || echo "  [FAIL] Markdown"
    echo "=== End Summary ==="
    return $EXIT_SUCCESS
}

# =============================================================================
# RECOVERY HELP (SKILL.md line 501-550)
# =============================================================================

recovery_help() {
    cat << 'EOF'
MANUAL RECOVERY PROCEDURES

1. RECOVER FROM BACKUP
   cp autoresearch.jsonl.bak.LATEST autoresearch.jsonl
   jq . autoresearch.jsonl > /dev/null
   validate

2. RECONSTRUCT MISSING BASELINE
   Create run #1 entry and corresponding result
   Update markdown marker

3. RECONSTRUCT MISSING MARKER
   echo "Last updated: Run #N" >> autoresearch.md

4. RECONSTRUCT WORKLOG
   Sync worklog.md entries with JSONL runs

5. FIX FORMAT VIOLATIONS
   Review JSONL with jq .
   Remove/fix incorrect entries

6. FIX ORPHAN RESULTS
   Cross-reference result run numbers
   Remove orphans

7. REBUILD COMPLETE STATE
   Create new JSONL with config header
   Re-add runs from backup
   Verify with validate
EOF
}

# =============================================================================
# HELP (SKILL.md line 551-600)
# =============================================================================

print_usage() {
    cat << 'EOF'
enforce-autoresearch-state.sh - State enforcement for autoresearch

USAGE:
  bash ./scripts/enforce-autoresearch-state.sh <command> [args]

DESCRIPTION:
  This script enforces consistency and completeness of the autoresearch
  state machine as defined in SKILL.md. It provides validation, logging,
  recovery, and diagnostic capabilities for maintaining the experiment state.

COMMANDS:
  validate              Run all validation checks on current state
  pre-experiment        Pre-flight validation before starting experiment
  log-result <n> <h> <m> <s> <d>  Log result (run hash metric status desc)
  detect-violations     Scan for all possible violations and report
  recovery              Attempt automatic recovery from backup
  summary               Print current state summary
  recovery-help         Display manual recovery procedure documentation
  help                  Show this help message

COMMAND DETAILS:

  validate:
    Runs comprehensive validation including:
    - JSONL syntax validation (each line valid JSON)
    - Config header presence check
    - Run sequence integrity (1, 2, 3, ...)
    - Result completeness (each run has result)
    - Format violations (incorrect field types)
    - Baseline presence (run #1 exists)
    - Orphan result detection
    - Markdown consistency check
    - Worklog consistency check
    
  pre-experiment:
    Validates state is ready for new experiment:
    - JSONL file exists and is readable
    - Baseline (run #1) is present
    - No JSONL syntax errors
    - Markdown file exists with marker
    - No format violations
    
  log-result:
    Atomically writes result entry to JSONL:
    - Validates all arguments
    - Checks run exists
    - Verifies no existing result for this run
    - Writes result atomically using temp file
    - Updates markdown "Last updated" marker
    
  detect-violations:
    Comprehensive violation detection report:
    - Scans all detection functions
    - Reports pass/fail for each check
    - Provides total violation count
    
  recovery:
    Attempts automatic recovery:
    - Calls backup-state.sh --restore
    - Verifies recovered state
    - Reports success or manual recovery needed
    
  summary:
    Quick state overview:
    - Run count and latest metrics
    - File locations and status
    - Consistency indicators

EXIT CODES:
  0  Success - operation completed successfully
  1  General validation failure - checks failed
  2  JSONL corruption detected - invalid JSON
  3  Missing baseline - run #1 not found
  4  Markdown/worklog inconsistency - out of sync
  5  Cannot perform atomic writes - permission issue
  6  Recovery failed - automatic recovery unsuccessful

EXAMPLES:
  # Check state consistency
  bash ./scripts/enforce-autoresearch-state.sh validate
  
  # Validate ready to start experiment
  bash ./scripts/enforce-autoresearch-state.sh pre-experiment
  
  # Log a result after experiment #5
  bash ./scripts/enforce-autoresearch-state.sh log-result 5 "abc123" "0.85" "kept" "Improved accuracy"
  
  # Find and report all violations
  bash ./scripts/enforce-autoresearch-state.sh detect-violations
  
  # Attempt recovery from backup
  bash ./scripts/enforce-autoresearch-state.sh recovery
  
  # View current state summary
  bash ./scripts/enforce-autoresearch-state.sh summary
  
  # Get manual recovery help
  bash ./scripts/enforce-autoresearch-state.sh recovery-help

FILE LOCATIONS:
  State files in project root:
  - autoresearch.jsonl - Main state file (JSON Lines)
  - autoresearch.md    - Markdown documentation
  - worklog.md         - Worklog entries (optional)

See SKILL.md for complete state machine specification.
EOF
}

# =============================================================================
# MAIN ENTRY POINT
# =============================================================================

# Main entry point - processes command-line arguments and dispatches
# to the appropriate command handler function.
# Ref: SKILL.md line 580
main() {
    # Require command argument - if none provided, show usage
    [[ $# -lt 1 ]] && { print_error "No command specified"; print_usage; return $EXIT_GENERAL_FAILURE; }
    
    local command="$1"
    shift
    
    # Dispatch to command handler based on first argument
    case "$command" in
        validate)
            command_validate
            ;;
        pre-experiment)
            command_pre_experiment
            ;;
        log-result)
            # log-result requires 5 arguments: run hash metric status description
            if [[ $# -lt 5 ]]; then
                print_error "Missing arguments for log-result"
                return $EXIT_GENERAL_FAILURE
            fi
            command_log_result "$@"
            ;;
        detect-violations)
            command_detect_violations
            ;;
        recovery)
            command_recovery
            ;;
        summary)
            command_summary
            ;;
        recovery-help)
            recovery_help
            ;;
        help|--help|-h)
            print_usage
            return $EXIT_SUCCESS
            ;;
        *)
            print_error "Unknown command: ${command}"
            print_usage
            return $EXIT_GENERAL_FAILURE
            ;;
    esac
}

# Execute main function with all command-line arguments
main "$@"