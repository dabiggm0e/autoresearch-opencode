---
name: autoresearch
description: Set up and run an autonomous experiment loop for any optimization target. Use when asked to start autoresearch or run experiments.
---

# Autoresearch

Autonomous experiment loop: try ideas, keep what works, discard what doesn't, never stop.

## Setup

1. Ask (or infer): **Goal**, **Command**, **Metric** (+ direction), **Files in scope**, **Constraints**.
2. `git checkout -b autoresearch/<goal>-<date>`
3. Read the source files. Understand the workload deeply before writing anything.
4. `mkdir -p experiments` then write `autoresearch.md`, `autoresearch.sh`, and `experiments/worklog.md` (see below). Commit all three.
5. Initialize experiment (write config header to `autoresearch.jsonl`) → run baseline → log result → start looping immediately.

### `autoresearch.md`

This is the heart of the session. A fresh agent with no context should be able to read this file and run the loop effectively. Invest time making it excellent.

```markdown
# Autoresearch: <goal>

## Objective
<Specific description of what we're optimizing and the workload.>

## Metrics
- **Primary**: <name> (<unit>, lower/higher is better)
- **Secondary**: <name>, <name>, ...

## How to Run
`./autoresearch.sh` — outputs `METRIC name=number` lines.

## Files in Scope
<Every file the agent may modify, with a brief note on what it does.>

## Off Limits
<What must NOT be touched.>

## Constraints
<Hard rules: tests must pass, no new deps, etc.>

## What's Been Tried
<Update this section as experiments accumulate. Note key wins, dead ends,
and architectural insights so the agent doesn't repeat failed approaches.>
```

**MANDATORY:** Update `autoresearch.md` after EVERY experiment. See the Logging Results section (step 4) for the exact protocol. The "What's Been Tried" section must reflect all runs in autoresearch.jsonl immediately after each result is logged.

### `autoresearch.sh`

Bash script (`set -euo pipefail`) that: pre-checks fast (syntax errors in <1s), runs the benchmark, outputs `METRIC name=number` lines. Keep it fast — every second is multiplied by hundreds of runs. Update it during the loop as needed.

---

## Enforcement Script

**The enforcement script automates all autoresearch operations.** Use it for validation, logging, and recovery.

```bash
# Validate state before experiment
bash ./scripts/enforce-autoresearch-state.sh validate

# Log result after experiment
bash ./scripts/enforce-autoresearch-state.sh log-result "$RUN" "$HASH" "$METRIC" "$STATUS" "$DESCRIPTION"

# Pre-experiment validation
bash ./scripts/enforce-autoresearch-state.sh pre-experiment

# Recovery from data loss
bash ./scripts/enforce-autoresearch-state.sh recovery
```

See script help for details: `bash ./scripts/enforce-autoresearch-state.sh help`

---

## JSONL State Protocol

All experiment state lives in `autoresearch.jsonl`. This is the source of truth for resuming across sessions.

### Config Header

The first line (and any re-initialization line) is a config header:

```json
{"type":"config","name":"<session name>","metricName":"<primary metric name>","metricUnit":"<unit>","bestDirection":"lower|higher"}
```

Rules:
- First line of the file is always a config header.
- Each subsequent config header (re-init) starts a new **segment**. Segment index increments with each config header.
- The baseline for a segment is the first result line after the config header.

### Result Lines

Each experiment result is appended as a JSON line:

```json
{"run":1,"commit":"abc1234","metric":42.3,"metrics":{"secondary_metric":123},"status":"keep","description":"baseline","timestamp":1234567890,"segment":0}
```

Fields:
- `run`: sequential run number (1-indexed, across all segments)
- `commit`: 7-char git short hash (the commit hash AFTER the auto-commit for keeps, or current HEAD for discard/crash)
- `metric`: primary metric value (0 for crashes)
- `metrics`: object of secondary metric values — **once you start tracking a secondary metric, include it in every subsequent result**
- `status`: `keep` | `discard` | `crash`
- `description`: short description of what this experiment tried
- `timestamp`: Unix epoch seconds
- `segment`: current segment index

### Initialization (equivalent of `init_experiment`)

To initialize, write the config header to `autoresearch.jsonl`:

```bash
echo '{"type":"config","name":"<name>","metricName":"<metric>","metricUnit":"<unit>","bestDirection":"<lower|higher>"}' > autoresearch.jsonl
```

To re-initialize (change optimization target), **append** a new config header:

```bash
echo '{"type":"config","name":"<name>","metricName":"<metric>","metricUnit":"<unit>","bestDirection":"<lower|higher>"}' >> autoresearch.jsonl
```

---

<<<<<<< HEAD
## Data Integrity Protocol

**CRITICAL: JSONL data must never be corrupted or lost.**

### Pre-Experiment Validation (MANDATORY)

**BEFORE running each experiment, execute these validation checks:**

1. **Count existing runs in JSONL** to determine the next run number
2. **Verify JSONL integrity** - last 5 lines must be valid JSON
3. **Check worklog consistency** - count entries in worklog.md should match JSONL count
4. **Validate atomic write capability** - ensure temp file creation works
5. **Confirm autoresearch.md "Last updated" marker** exists and matches JSONL count

**If any validation fails, DO NOT proceed with the experiment. Fix the issue first.**

```bash
# Pre-experiment validation (run BEFORE each experiment)
pre_experiment_validation() {
    local jsonl_file="autoresearch.jsonl"
    local worklog_file="experiments/worklog.md"
    
    echo "  Pre-experiment validation started..." >&2
    
    # 1. Count existing runs
    if [[ -f "$jsonl_file" ]]; then
        local run_count=$(grep -c '"run":' "$jsonl_file" 2>/dev/null || echo 0)
        echo "  Current runs in JSONL: $run_count" >&2
    else
        echo "  ERROR: JSONL file does not exist!" >&2
        return 1
    fi
    
    # 2. Verify JSONL integrity
    if ! tail -n 5 "$jsonl_file" 2>/dev/null | while IFS= read -r line; do
        if [[ -n "$line" ]] && ! echo "$line" | python3 -m json.tool >/dev/null 2>&1; then
            echo "  ERROR: Invalid JSON found in JSONL file!" >&2
            return 1
        fi
    done; then
        echo "  ERROR: JSONL integrity check failed!" >&2
        return 1
    fi
    echo "  JSONL integrity: OK" >&2
    
    # 3. Check worklog consistency
    if [[ -f "$worklog_file" ]]; then
        local worklog_count=$(grep -c "^### Run" "$worklog_file" 2>/dev/null || echo 0)
        if [[ "$worklog_count" -ne "$run_count" ]]; then
            echo "  WARNING: Worklog has $worklog_count runs, JSONL has $run_count runs!" >&2
            echo "  This indicates data loss. Check backups before proceeding." >&2
        else
            echo "  Worklog consistency: OK" >&2
        fi
    fi
    
    # 4. Validate atomic write capability
    local temp_test="autoresearch.jsonl.tmp_validation.$$"
    if ! touch "$temp_test" 2>/dev/null; then
        echo "  ERROR: Cannot create temp file for atomic writes!" >&2
        return 1
    fi
    rm -f "$temp_test"
    echo "  Atomic write capability: OK" >&2
    
    # 5. Confirm autoresearch.md marker
    if [[ -f "autoresearch.md" ]]; then
        if ! grep -qP '\*Last updated: Run #\d+ on [0-9-]+\*' autoresearch.md 2>/dev/null; then
            echo "  WARNING: Missing 'Last updated' marker in autoresearch.md!" >&2
        fi
    fi
    
    echo "  Pre-experiment validation: PASSED" >&2
    return 0
}

# MANDATORY: Call this BEFORE each experiment
pre_experiment_validation || {
    echo "  CRITICAL: Pre-experiment validation failed. Fix issues before proceeding." >&2
    return 1
}
```

### Pre-Write Validation (before appending to JSONL)

Before writing any new experiment result, validate the JSONL file:

```bash
# Validate JSONL file before writing
validate_jsonl() {
    local jsonl_file="autoresearch.jsonl"
    
    if [[ -f "$jsonl_file" ]]; then
        # Count existing runs
        local run_count=$(grep -c '"run":' "$jsonl_file" 2>/dev/null || echo 0)
        echo "Current runs in JSONL: $run_count" >&2
        
        # Verify last 5 lines are valid JSON
        tail -n 5 "$jsonl_file" 2>/dev/null | while IFS= read -r line; do
            if ! echo "$line" | python3 -m json.tool >/dev/null 2>&1; then
                echo "WARNING: Invalid JSON found in state file" >&2
                return 1
            fi
        done
        
        echo "JSONL validation: OK" >&2
        return 0
    fi
    return 0  # File doesn't exist yet, that's OK
}

# Call validation before any write
validate_jsonl || {
    echo "  WARNING: JSONL validation failed. Proceeding with caution." >&2
}
```

### Atomic Write Pattern (STRENGTHENED)

**CRITICAL: Never append directly to JSONL. Use the atomic write pattern with pre-write validation and post-write verification.**

```bash
write_jsonl_entry() {
    local entry="$1"
    local jsonl_file="autoresearch.jsonl"
    local temp_file="${jsonl_file}.tmp.$$"
    local expected_run=$(echo "$entry" | python3 -c "import sys,json; print(json.load(sys.stdin).get('run',0))" 2>/dev/null || echo 0)
    
    echo "  Starting atomic write for run #$expected_run..." >&2
    
    # PRE-WRITE VALIDATION
    echo "  Pre-write validation..." >&2
    
    # 1. Validate the entry is valid JSON BEFORE any write operations
    if ! echo "$entry" | python3 -m json.tool >/dev/null 2>&1; then
        echo "  ERROR: Entry is not valid JSON, aborting write" >&2
        return 1
    fi
    echo "  Entry JSON validity: OK" >&2
    
    # 2. Verify JSONL file exists and is readable
    if [[ ! -f "$jsonl_file" ]]; then
        echo "  ERROR: JSONL file does not exist!" >&2
        return 1
    fi
    
    # 3. Validate current JSONL integrity
    if ! tail -n 5 "$jsonl_file" 2>/dev/null | while IFS= read -r line; do
        if [[ -n "$line" ]] && ! echo "$line" | python3 -m json.tool >/dev/null 2>&1; then
            echo "  ERROR: JSONL file is corrupted, aborting write!" >&2
            return 1
        fi
    done; then
        echo "  ERROR: JSONL integrity check failed, aborting!" >&2
        return 1
    fi
    echo "  JSONL integrity: OK" >&2
    
    # 4. Ensure we can create temp file
    if ! touch "$temp_file" 2>/dev/null; then
        echo "  ERROR: Cannot create temp file for atomic write!" >&2
        return 1
    fi
    
    # CREATE TEMP FILE WITH EXISTING CONTENT
    cat "$jsonl_file" > "$temp_file" 2>/dev/null || {
        echo "  ERROR: Cannot read JSONL file!" >&2
        rm -f "$temp_file"
        return 1
    }
    
    # APPEND NEW ENTRY
    echo "$entry" >> "$temp_file"
    
    # POST-WRITE VERIFICATION (before atomic move)
    echo "  Post-write verification (pre-move)..." >&2
    
    # 1. Verify temp file contains expected entry
    if ! tail -n 1 "$temp_file" | python3 -c "import sys,json; json.load(sys.stdin)" >/dev/null 2>&1; then
        echo "  ERROR: Temp file last line is not valid JSON!" >&2
        rm -f "$temp_file"
        return 1
    fi
    
    # 2. Count runs in temp file (should be expected_run)
    local temp_count=$(grep -c '"run":' "$temp_file" 2>/dev/null || echo 0)
    if [[ "$temp_count" -lt "$expected_run" ]]; then
        echo "  ERROR: Temp file has $temp_count runs, expected $expected_run!" >&2
        rm -f "$temp_file"
        return 1
    fi
    echo "  Temp file run count: OK ($temp_count runs)" >&2
    
    # ATOMIC MOVE (guaranteed all-or-nothing)
    if ! mv "$temp_file" "$jsonl_file" 2>/dev/null; then
        echo "  ERROR: Atomic move failed!" >&2
        return 1
    fi
    
    # FINAL POST-WRITE VERIFICATION
    echo "  Final post-write verification..." >&2
    
    # 1. Verify JSONL file contains expected run count
    local new_count=$(grep -c '"run":' "$jsonl_file" 2>/dev/null || echo 0)
    if [[ "$new_count" -lt "$expected_run" ]]; then
        echo "  ERROR: Write verification failed! Expected $expected_run runs, got $new_count!" >&2
        echo "  DATA LOSS MAY HAVE OCCURRED. Check backups immediately." >&2
        return 1
    fi
    echo "  Final run count: OK ($new_count runs)" >&2
    
    # 2. Verify integrity of written file
    if ! tail -n 1 "$jsonl_file" | python3 -m json.tool >/dev/null 2>&1; then
        echo "  ERROR: Written entry is not valid JSON!" >&2
        return 1
    fi
    echo "  Final integrity check: OK" >&2
    
    echo "  Atomic write completed successfully for run #$expected_run" >&2
    return 0
}
```

### Post-Write Verification

After every write operation, verify the data was written correctly:

```bash
verify_write() {
    local expected_run=$1
    local jsonl_file="autoresearch.jsonl"
    
    if [[ -f "$jsonl_file" ]]; then
        local actual_count=$(grep -c '"run":' "$jsonl_file" 2>/dev/null || echo 0)
        
        if [[ "$actual_count" -lt "$expected_run" ]]; then
            echo "  WARNING: Run count mismatch! Expected $expected_run, got $actual_count" >&2
            echo "This may indicate data loss in previous writes." >&2
            return 1
        fi
        
        echo "Write verification: OK (run $expected_run present)" >&2
        return 0
    fi
    return 1
}
```

---

### User-Confirmable Actions

Before any user-confirmable action (e.g., manual intervention, major changes, discarding multiple experiments), create a backup:

```bash
# Backup state before user-confirmable action
backup_before_confirm() {
    echo "  User confirmation required. Creating backup..." >&2
    
    # Use backup utility if available
    if [[ -f "./scripts/backup-state.sh" ]]; then
        ./scripts/backup-state.sh backup autoresearch.jsonl 2>/dev/null || true
    else
        # Fallback: simple backup
        cp autoresearch.jsonl "autoresearch.jsonl.backup.$(date +%s)" 2>/dev/null || true
    fi
    
    echo "Backup created. Awaiting user confirmation..." >&2
}
```

**Always call `backup_before_confirm` before any operation that requires user approval.**

---

### Dashboard Data Consistency Check

When generating the dashboard, check for data consistency:

#### Automatic Synchronization Check (MANDATORY)

**Every time the dashboard is generated, automatically run this sync check:**

```bash
dashboard_sync_check() {
    local jsonl_file="autoresearch.jsonl"
    local worklog_file="experiments/worklog.md"
    
    echo "  Running dashboard synchronization check..." >&2
    
    # Count runs in JSONL
    local jsonl_count=0
    if [[ -f "$jsonl_file" ]]; then
        jsonl_count=$(grep -c '"run":' "$jsonl_file" 2>/dev/null || echo 0)
    fi
    
    # Count runs in worklog
    local worklog_count=0
    if [[ -f "$worklog_file" ]]; then
        worklog_count=$(grep -c "^### Run" "$worklog_file" 2>/dev/null || echo 0)
    fi
    
    echo "  JSONL runs: $jsonl_count, Worklog runs: $worklog_count" >&2
    
    # If mismatch, auto-generate recovery guidance
    if [[ "$jsonl_count" -ne "$worklog_count" ]]; then
        local diff=$((jsonl_count - worklog_count))
        if [[ $diff -gt 0 ]]; then
            echo "  WARNING: $diff runs in JSONL are not documented in worklog!" >&2
            echo "  ACTION: Generate missing worklog entries from JSONL data." >&2
        else
            local abs_diff=$((-diff))
            echo "  WARNING: $abs_diff runs in worklog are not in JSONL!" >&2
            echo "  ACTION: Check for data loss. Restore from backup if available." >&2
        fi
        
        # Auto-check for backups
        if [[ -f "./scripts/backup-state.sh" ]]; then
            echo "  Checking for available backups..." >&2
            ./scripts/backup-state.sh list "$jsonl_file" 2>/dev/null || echo "  No backups found or backup script failed" >&2
        fi
        
        return 1
    fi
    
    echo "  Synchronization check: PASSED (no drift detected)" >&2
    return 0
}

# MANDATORY: Call this when generating dashboard
dashboard_sync_check || {
    echo "  Dashboard sync check failed. Include recovery banner in dashboard." >&2
}
```

#### Data Consistency Check

If the number of runs in `autoresearch.jsonl` doesn't match the number of entries in `experiments/worklog.md`:

1. **Check for backups**: `scripts/backup-state.sh list autoresearch.jsonl`
2. **If backups exist**: Restore with `scripts/backup-state.sh restore-auto`
3. **If no backups**: Manually recreate missing runs from worklog notes
4. **Note the discrepancy** in the dashboard header

Add this warning banner to the dashboard when inconsistency is detected:

```markdown
 **DATA INCONSISTENCY DETECTED**

- **Worklog documents**: <WORKLOG_RUN_COUNT> experiments
- **JSONL contains**: <JSONL_RUN_COUNT> runs
- **Missing**: <DIFF> runs **LOST!**

**Recovery steps:**
1. Check backups: `scripts/backup-state.sh list autoresearch.jsonl`
2. Restore if available: `scripts/backup-state.sh restore-auto`
3. Otherwise, manually recreate missing runs from worklog
```

---

## Pre-flight Validation

Before running each experiment, check that autoresearch.md is current:

**Quick check:** Count runs in autoresearch.jsonl and compare to the "Last updated" marker in autoresearch.md. If they don't match, the update protocol was violated - manually update before continuing.

**Verification step:**
```bash
grep -oP '\*Last updated: Run #\d+ on [0-9-]+\*' autoresearch.md | tail -1
```
This should show a marker with the current run count. If it's missing or shows an older run number, update autoresearch.md before proceeding.

**If drift detected:** Don't skip updating autoresearch.md. A fresh agent resuming this session depends on having complete context of all runs, not just the JSONL data.

---

=======
>>>>>>> autoresearch/bogo-sort-runtime-2026-03-16
## Running Experiments (equivalent of `run_experiment`)

Run the benchmark command, capturing timing and output:

```bash
START_TIME=$(date +%s%N)
bash -c "./autoresearch.sh" 2>&1 | tee /tmp/autoresearch-output.txt
EXIT_CODE=$?
END_TIME=$(date +%s%N)
DURATION=$(echo "scale=3; ($END_TIME - $START_TIME) / 1000000000" | bc)
echo "Duration: ${DURATION}s, Exit code: ${EXIT_CODE}"
```

After running:
- Parse `METRIC name=number` lines from the output to extract metric values
- If exit code != 0 → this is a crash
- Read the output to understand what happened

---

## Logging Results (equivalent of `log_experiment`)

After each experiment run, follow this exact protocol:

### 1. Determine status

- **keep**: primary metric improved (lower if `bestDirection=lower`, higher if `bestDirection=higher`)
- **discard**: primary metric worse or equal to best kept result
- **crash**: command failed (non-zero exit code)

Secondary metrics are for monitoring only — they almost never affect keep/discard decisions. Only discard a primary improvement if a secondary metric degraded catastrophically, and explain why in the description.

### 2. Git operations

**If keep:**
```bash
git add -A
git diff --cached --quiet && echo "nothing to commit" || git commit -m "$DESCRIPTION"
```

Then get the new commit hash:
```bash
git rev-parse --short=7 HEAD
```

**If discard or crash:**
```bash
git checkout -- .
git clean -fd
```

Use the current HEAD hash (before revert) as the commit field.

### 3. Append result to JSONL

**Use the enforcement script:**
```bash
bash ./scripts/enforce-autoresearch-state.sh log-result "$RUN" "$HASH" "$METRIC" "$STATUS" "$DESCRIPTION"
```

**Alternative manual method (if script unavailable):**
```bash
echo '{"run":<N>,"commit":"<hash>","metric":<value>,"metrics":{<secondaries>},"status":"<status>","description":"<desc>","timestamp":'$(date +%s)',"segment":<seg>}' >> autoresearch.jsonl
```

### 4. Update autoresearch.md "What's Been Tried" section

**REQUIRED after every experiment. Do not skip this step.**

Append a summary of the latest result to the "What's Been Tried" section. Use this format:

```markdown
### Run #{RUN_NUMBER} ({STATUS}) {EMOJI}
- **Timestamp:** YYYY-MM-DD HH:MM
- **Description:** {BRIEF DESCRIPTION OF WHAT WAS TRIED}
- **Result:** runtime={METRIC_VALUE}s

*Last updated: Run #{RUN_NUMBER} on YYYY-MM-DD*
```

**Example entry:**
```markdown
### Run #4 (KEEP) ⭐
- **Timestamp:** 2026-03-14 11:23
- **Description:** Approach 6: Bisect-based binary search detection
- **Result:** runtime=0.002s

*Last updated: Run #7 on 2026-03-14*
```

<<<<<<< HEAD
**MANDATORY requirements (NON-NEGOTIABLE):**
1. Include ALL runs (KEEP, DISCARD, CRASH) - do not filter any out
2. Use emoji markers: ⭐ for KEEP, 💥 for CRASH, none for DISCARD
3. **ALWAYS include the "Last updated" marker at end of section - this is MANDATORY for drift detection**
4. The "Last updated" marker **MUST** show the current run number and date - do not skip this
5. If the section doesn't exist yet, create it with header `## What's Been Tried`

**CRITICAL: The "Last updated" marker is non-negotiable. Every experiment log MUST include this marker at the end of the "What's Been Tried" section. This enables:**
- Pre-flight validation to detect drift between JSONL and markdown
- Resuming agents to verify they have complete context
- Automated checks to ensure no experiments were skipped

**If you omit the "Last updated" marker, the pre-flight validation will FAIL and the next experiment cannot proceed.**

**Implementation tip:** Read the latest entry from autoresearch.jsonl to get the run number, status, description, and metric value, then append formatted text to autoresearch.md. **ALWAYS append the "Last updated" marker as the final line.**
=======
**Key requirements:**
1. Include ALL runs (KEEP, DISCARD, CRASH) - do not filter any out
2. Use emoji markers: ⭐ for KEEP, 💥 for CRASH, none for DISCARD
3. Always update the "Last updated" marker at end of section
4. If the section doesn't exist yet, create it with header `## What's Been Tried`

**Implementation tip:** Read the latest entry from autoresearch.jsonl to get the run number, status, description, and metric value, then append formatted text to autoresearch.md.
>>>>>>> autoresearch/bogo-sort-runtime-2026-03-16

### 5. Update dashboard

After every log, regenerate `autoresearch-dashboard.md` (see Dashboard section below).

### 6. Append to worklog

After every experiment, append a concise entry to `experiments/worklog.md`. This file survives context compactions and crashes, giving any resuming agent (or the user) a complete narrative of the session. Format:

```markdown
### Run N: <short description> — <primary_metric>=<value> (<STATUS>)
- Timestamp: YYYY-MM-DD HH:MM
- What changed: <1-2 sentences describing the code/config change>
- Result: <metric values>, <delta vs best>
- Insight: <what was learned, why it worked/failed>
- Next: <what to try next based on this result>
```

Also update the "Key Insights" and "Next Ideas" sections at the bottom of the worklog when you learn something new.

**On setup**, create `experiments/worklog.md` with the session header, data summary, and baseline result. **On resume**, read `experiments/worklog.md` to recover context.

### 7. Secondary metric consistency

Once you start tracking a secondary metric, you MUST include it in every subsequent result. Parse the JSONL to discover which secondary metrics have been tracked and ensure all are present.

If you want to add a new secondary metric mid-session, that's fine — but from that point forward, always include it.

### 8. Update Next Steps / Optimization Strategies (MANDATORY)

**AFTER EVERY experiment, you MUST update the "Next Steps" or "Optimization Strategies" section in autoresearch.md.**

This is NON-NEGOTIABLE. The "Next Steps" section guides future experiments and ensures the loop doesn't repeat failed approaches or miss promising paths.

**Protocol:**

1. **Read the latest experiment result** from autoresearch.jsonl
2. **Analyze what was learned** - why it worked or failed
3. **Update "Next Steps" section** with actionable follow-up ideas
4. **Prune exhausted paths** - remove ideas that have been tried
5. **Add new promising directions** based on insights from the latest run

**Format for "Next Steps" section:**

```markdown
## Next Steps / Optimization Strategies

**Last updated: After Run #{RUN_NUMBER} on YYYY-MM-DD**

### Promising Directions (based on latest insights)
- **Idea 1**: {Brief description of approach inspired by recent results}
- **Idea 2**: {Another promising direction to explore}

### Paths to Avoid (already tried, did not work)
- {Approach that was tried and failed - include run number reference}

### Current Best Insight
{Key learning from the latest experiment that should guide future work}
```

**Example:**

```markdown
## Next Steps / Optimization Strategies

**Last updated: After Run #7 on 2026-03-14**

### Promising Directions (based on latest insights)
- **Idea 1**: The bisect-based approach (#4) showed 99.9% improvement. Try adapting it to handle edge cases in the data.
- **Idea 2**: Approach #6 failed but the profiling showed a different hot path. Optimize that section instead.

### Paths to Avoid (already tried, did not work)
- itertools pairwise check (#3) - slower than baseline
- Built-in sorted() comparison (#2) - marginally worse performance

### Current Best Insight
Binary search detection is the winning pattern. Focus on variations of that approach rather than trying completely different algorithms.
```

**MANDATORY checklist for every experiment:**
- [ ] Analyze the latest result and extract key insights
- [ ] Update "Promising Directions" with new ideas
- [ ] Add failed approaches to "Paths to Avoid"
- [ ] Update "Current Best Insight" with the most important learning
- [ ] Update the "Last updated" marker at the top of the section

**CRITICAL: If you skip updating "Next Steps", the next agent (or you on resume) will lack guidance on what to try next. This wastes computational resources and time.**

---

## Example "What's Been Tried" Section Format

After several experiments, the "What's Been Tried" section should look like:

```markdown
## What's Been Tried

### Run #1 (KEEP) ⭐
- **Timestamp:** 2026-03-14 10:30
- **Description:** baseline
- **Result:** runtime=15.605s

### Run #2 (KEEP) ⭐
- **Timestamp:** 2026-03-14 10:35
- **Description:** Approach 1: Built-in sorted() comparison
- **Result:** runtime=16.524s

### Run #3 (DISCARD)
- **Timestamp:** 2026-03-14 10:50
- **Description:** Approach 2: itertools pairwise check
- **Result:** runtime=17.654s

### Run #4 (KEEP) ⭐
- **Timestamp:** 2026-03-14 11:23
- **Description:** Approach 6: Bisect-based binary search detection
- **Result:** runtime=0.002s

*Last updated: Run #9 on 2026-03-14*
```

**Key formatting rules:**
- Include ALL runs (KEEP, DISCARD, CRASH) - don't filter any out
- Use emoji to quickly identify status: ⭐ = KEEP, 💥 = CRASH
- Always end with the "Last updated" marker for drift detection
- Keep descriptions concise but informative

---

## Example "What's Been Tried" Section Format

After several experiments, the "What's Been Tried" section should look like:

```markdown
## What's Been Tried

### Run #1 (KEEP) ⭐
- **Timestamp:** 2026-03-14 10:30
- **Description:** baseline
- **Result:** runtime=15.605s

### Run #2 (KEEP) ⭐
- **Timestamp:** 2026-03-14 10:35
- **Description:** Approach 1: Built-in sorted() comparison
- **Result:** runtime=16.524s

### Run #3 (DISCARD)
- **Timestamp:** 2026-03-14 10:50
- **Description:** Approach 2: itertools pairwise check
- **Result:** runtime=17.654s

### Run #4 (KEEP) ⭐
- **Timestamp:** 2026-03-14 11:23
- **Description:** Approach 6: Bisect-based binary search detection
- **Result:** runtime=0.002s

*Last updated: Run #9 on 2026-03-14*
```

**Key formatting rules:**
- Include ALL runs (KEEP, DISCARD, CRASH) - don't filter any out
- Use emoji to quickly identify status: ⭐ = KEEP, 💥 = CRASH
- Always end with the "Last updated" marker for drift detection
- Keep descriptions concise but informative

---

## Dashboard

After each experiment, regenerate `autoresearch-dashboard.md`:

```markdown
# Autoresearch Dashboard: <name>

**Runs:** 12 | **Kept:** 8 | **Discarded:** 3 | **Crashed:** 1
**Baseline:** <metric_name>: <value><unit> (#1)
**Best:** <metric_name>: <value><unit> (#8, -26.2%)

| # | commit | <metric_name> | status | description |
|---|--------|---------------|--------|-------------|
| 1 | abc1234 | 42.3s | keep | baseline |
| 2 | def5678 | 40.1s (-5.2%) | keep | optimize hot loop |
| 3 | abc1234 | 43.0s (+1.7%) | discard | try vectorization |
...
```

Include delta percentages vs baseline for each metric value. Show ALL runs in the current segment (not just recent ones).

---

## Backup & Recovery

**Critical: Protect your experiment state. Always backup before major operations and recover immediately from data loss.**

### User-Confirmable Actions

Before any operation requiring user confirmation (manual intervention, discarding multiple experiments, major changes), create a backup:

```bash
# Before any user-confirmable action
bash ./scripts/backup-state.sh backup autoresearch.jsonl
```

**Always call the backup script before any operation that requires user approval.**

### State File Backup

**BEFORE user-confirmable actions**, create backups:

```bash
# Before any major operation requiring user confirmation
bash ./scripts/backup-state.sh backup autoresearch.jsonl
```

**Best practices:**
- Always backup before major changes or user confirmations
- Keep the last 5 backups (delete older ones)
- Restore from backup if experiment crashes or state becomes corrupted

**Automated cleanup:**
```bash
# Keep only last 5 backups
bash ./scripts/backup-state.sh cleanup
```

### Data Loss Detection and Recovery

**If you detect data loss** (e.g., dashboard shows inconsistency, JSONL count doesn't match worklog):

1. **Immediate actions:**
   ```bash
   # Check for data loss
   JSONL_COUNT=$(grep -c '"run":' autoresearch.jsonl 2>/dev/null || echo 0)
   WORKLOG_COUNT=$(grep -c "^### Run" experiments/worklog.md 2>/dev/null || echo 0)
   
   if [[ "$JSONL_COUNT" -ne "$WORKLOG_COUNT" ]]; then
       echo "  DATA LOSS DETECTED: JSONL has $JSONL_COUNT runs, worklog has $WORKLOG_COUNT runs" >&2
   fi
   ```

2. **Check backups:**
   ```bash
   ./scripts/backup-state.sh list autoresearch.jsonl
   ```

3. **Recovery options:**
   - **Best**: Restore from backup if recent enough
   - **Alternative**: Manually recreate missing runs from worklog notes
   - **Last resort**: Start new segment with new config header

4. **Prevention**: Always backup before user-confirmable actions (see "User-Confirmable Actions" above)

**Automated recovery:** `bash ./scripts/enforce-autoresearch-state.sh recovery`

### Backup Usage Documentation

For comprehensive backup documentation, see [`BACKUP-USAGE.md`](./BACKUP-USAGE.md).

This guide covers:
- Installation and setup
- Command reference table  
- Usage examples
- Integration with workflow
- Best practices and troubleshooting

---

### Dashboard Data Consistency Check

When generating the dashboard, check for data consistency:

#### Data Consistency Check

If the number of runs in `autoresearch.jsonl` doesn't match the number of entries in `experiments/worklog.md`:

1. **Check for backups**: `./scripts/backup-state.sh list autoresearch.jsonl`
2. **If backups exist**: Restore with `./scripts/backup-state.sh restore-auto`
3. **If no backups**: Manually recreate missing runs from worklog notes
4. **Note the discrepancy** in the dashboard header

Add this warning banner to the dashboard when inconsistency is detected:

```markdown
 **DATA INCONSISTENCY DETECTED**

- **Worklog documents**: <WORKLOG_RUN_COUNT> experiments
- **JSONL contains**: <JSONL_RUN_COUNT> runs
- **Missing**: <DIFF> runs **LOST!**

**Recovery steps:**
1. Check backups: `./scripts/backup-state.sh list autoresearch.jsonl`
2. Restore if available: `./scripts/backup-state.sh restore-auto`
3. Otherwise, manually recreate missing runs from worklog
```

---

## Loop Rules

**LOOP FOREVER.** Never ask "should I continue?" — the user expects autonomous work.

- **Primary metric is king.** Improved → `keep`. Worse/equal → `discard`. Secondary metrics rarely affect this.
- **Simpler is better.** Removing code for equal perf = keep. Ugly complexity for tiny gain = probably discard.
- **Don't thrash.** Repeatedly reverting the same idea? Try something structurally different.
- **Crashes:** fix if trivial, otherwise log and move on. Don't over-invest.
- **Think longer when stuck.** Re-read source files, study the profiling data, reason about what the CPU is actually doing. The best ideas come from deep understanding, not from trying random variations.
- **Resuming:** if `autoresearch.md` exists, first check if `autoresearch.jsonl` exists:
  - If it exists: read it + `experiments/worklog.md` + git log, continue looping
  - If it doesn't exist: see "Missing State File" section below (fallback behavior)

**NEVER STOP.** The user may be away for hours. Keep going until interrupted.

## Missing State File

If `autoresearch.jsonl` is missing when resuming:

1. **Preserve context from `autoresearch.md`** - Read the objective, metrics, and files in scope
2. **Ask for user confirmation** - "State file missing. Options:
   - A) Create new state (fresh start)
   - B) Continue with autoresearch.md context only
   - C) Restore from backup (if available)
 "
3. **If fresh start**: initialize new JSONL with config header
4. **If continuing with context only**: proceed with autoresearch.md data but note the limitation

## Ideas Backlog

When you discover complex but promising optimizations that you decide not to pursue right now, **append them as bullet points to `autoresearch.ideas.md`**. Don't let good ideas get lost.

If the loop stops (context limit, crash, etc.) and `autoresearch.ideas.md` exists, you'll be asked to:
1. Read the ideas file and use it as inspiration for new experiment paths
2. Prune ideas that are duplicated, already tried, or clearly bad
3. Create experiments based on the remaining ideas
4. If nothing is left, try to come up with your own new ideas
5. If all paths are exhausted, delete `autoresearch.ideas.md` and write a final summary report

When there is no `autoresearch.ideas.md` file and the loop ends, the research is complete.

## User Steers

User messages sent while an experiment is running should be noted and incorporated into the NEXT experiment. Finish your current experiment first — **Do not stop or ask for confirmation**. Incorporate the user's idea in the next experiment.

## Updating autoresearch.md

**MANDATORY PROTOCOL:** Update `autoresearch.md` after **EVERY** experiment, not periodically. 

See the Logging Results section (step 4) for the format to use. This ensures:
1. Zero drift between autoresearch.jsonl and the markdown summary
2. Any resuming agent has complete context on all runs
3. No reliance on memory or judgment about "significant breakthroughs"

**NEVER SKIP THIS STEP.** If you skip updating after an experiment, the next agent may repeat failed approaches or miss key insights, wasting computational resources and time.
<<<<<<< HEAD
=======

---

## Protocol Validation

The enforcement script automatically detects common violations including:

- **Missing fields:** description, metrics, or timestamp in runs
- **Invalid values:** status must be one of {kept, replaced, crashed}
- **Orphan results:** run numbers must match count and be > 0

Run validation anytime:
```bash
bash ./scripts/enforce-autoresearch-state.sh detect-violations
```

See all available checks: `bash ./scripts/enforce-autoresearch-state.sh --help`

---

## Quick Reference Card

**Copy-paste these commands during autoresearch sessions.**

### Session Validation

Use the enforcement script for state validation and logging:

```bash
# Validate complete state
bash ./scripts/enforce-autoresearch-state.sh validate

# Pre-experiment validation (run before each experiment)
bash ./scripts/enforce-autoresearch-state.sh pre-experiment

# Log experiment result after completion
bash ./scripts/enforce-autoresearch-state.sh log-result "$RUN" "$HASH" "$METRIC" "$STATUS" "$DESCRIPTION"
```

See `bash ./scripts/enforce-autoresearch-state.sh help` for all options.

### JSONL Debugging

```bash
# Find invalid JSON lines
tail -n 20 autoresearch.jsonl | python3 -c "
import sys, json
for i, line in enumerate(sys.stdin, start=-19):
    try: json.loads(line)
    except: print(f'Line {i}: INVALID - {line[:80]}')"

# Show run summary by status
python3 -c "
import json
from collections import Counter
with open('autoresearch.jsonl') as f:
    statuses = [json.loads(l)['status'] for l in f if 'status' in json.loads(l)]
    print('Status distribution:', Counter(statuses))"

# Find best run
python3 -c "
import json
with open('autoresearch.jsonl') as f:
    entries = [json.loads(l) for l in f if 'run' in json.loads(l)]
    best = min(entries, key=lambda e: e['metric']) if all(e.get('metric') for e in entries) else entries[0]
    print(f'Best: Run #{best[\"run\"]} = {best[\"metric\"]} ({best[\"status\"]})')"

# Show last 5 runs
tail -n 5 autoresearch.jsonl | python3 -m json.tool --no-ensure-ascii
```

### State Recovery

Use the backup-state script for managing experiment state backups:

```bash
# List available backups
./scripts/backup-state.sh list autoresearch.jsonl

# Restore from most recent backup
./scripts/backup-state.sh restore-auto autoresearch.jsonl

# Create manual backup before major operation
./scripts/backup-state.sh backup autoresearch.jsonl

# Recovery from data loss
./scripts/backup-state.sh recover autoresearch.jsonl
```

See `./scripts/backup-state.sh help` for all options.

### Data Loss Detection

```bash
# Check JSONL vs worklog consistency
JSONL_COUNT=$(grep -c '"run":' autoresearch.jsonl || echo 0)
WORKLOG_COUNT=$(grep -c "^### Run" experiments/worklog.md || echo 0)
[[ "$JSONL_COUNT" -eq "$WORKLOG_COUNT" ]] && echo "✓ Data consistent: $JSONL_COUNT runs" || echo "✗ DATA LOSS: JSONL=$JSONL_COUNT, worklog=$WORKLOG_COUNT"

# Find missing runs
python3 -c "
import json
import re
with open('autoresearch.jsonl') as f:
    jsonl_runs = set(int(json.loads(l)['run']) for l in f if 'run' in json.loads(l))
with open('experiments/worklog.md') as f:
    worklog_runs = set(int(m.group(1)) for m in re.finditer(r'^### Run (\d+)', f.read(), re.MULTILINE))
missing = worklog_runs - jsonl_runs
extra = jsonl_runs - worklog_runs
if missing: print(f'✗ Missing from JSONL: {sorted(missing)}')
if extra: print(f'✗ Extra in JSONL: {sorted(extra)}')
if not missing and not extra: print('✓ No discrepancies')"
```

### Emergency Commands

```bash
# Force re-initialize (creates new segment)
echo '{"type":"config","name":"new_segment","metricName":"'"$(head -n 1 autoresearch.jsonl | python3 -c 'import sys,json; print(json.load(sys.stdin)["metricName"])')"'","metricUnit":"'"$(head -n 1 autoresearch.jsonl | python3 -c 'import sys,json; print(json.load(sys.stdin)["metricUnit"])')"'","bestDirection":"'"$(head -n 1 autoresearch.jsonl | python3 -c 'import sys,json; print(json.load(sys.stdin)["bestDirection"])')"'"}' >> autoresearch.jsonl

# Reset to baseline (delete all but first run)
python3 -c "
import json
with open('autoresearch.jsonl') as f:
    lines = f.readlines()
with open('autoresearch.jsonl.bak', 'w') as f:
    f.write(lines[0])  # Keep header
    f.write(lines[1])  # Keep baseline
"
mv autoresearch.jsonl.bak autoresearch.jsonl

# Generate fresh dashboard
python3 -c "
import json
from datetime import datetime
with open('autoresearch.jsonl') as f:
    entries = [json.loads(l) for l in f if 'run' in json.loads(l)]
print(f'# Autoresearch Dashboard: {entries[0].get("segment", 0)}')
print(f'\\n**Runs:** {len(entries)} | **Kept:** {sum(1 for e in entries if e[\"status\"]==\"keep\")} | **Discarded:** {sum(1 for e in entries if e[\"status\"]==\"discard\")} | **Crashed:** {sum(1 for e in entries if e[\"status\"]==\"crash\")}')
" > autoresearch-dashboard.md
```

### Quick Checklist Before Each Loop Iteration

```bash
# Run this before starting each new experiment:
echo "=== Pre-experiment Checklist ===" && \
[[ -f autoresearch.md ]] && echo "✓ autoresearch.md" || echo "✗ autoresearch.md" && \
[[ -f autoresearch.sh ]] && echo "✓ autoresearch.sh" || echo "✗ autoresearch.sh" && \
[[ -f autoresearch.jsonl ]] && echo "✓ autoresearch.jsonl" || echo "✗ autoresearch.jsonl" && \
head -n 1 autoresearch.jsonl | python3 -c "import sys,json; exit(0 if json.load(sys.stdin)['type']=='config' else 1)" && echo "✓ JSONL header" || echo "✗ JSONL header" && \
TOTAL=$(grep -c '"run":' autoresearch.jsonl || echo 0) && \
MARKER=$(grep -oP 'Last updated: Run #\K\d+' autoresearch.md | tail -1 || echo "0") && \
[[ "$TOTAL" -eq "$MARKER" ]] && echo "✓ Marker sync: $TOTAL" || echo "✗ Drift: $MARKER vs $TOTAL"
```
>>>>>>> autoresearch/bogo-sort-runtime-2026-03-16
