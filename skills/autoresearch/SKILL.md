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

Update `autoresearch.md` periodically — especially the "What's Been Tried" section — so resuming agents have full context.

### `autoresearch.sh`

Bash script (`set -euo pipefail`) that: pre-checks fast (syntax errors in <1s), runs the benchmark, outputs `METRIC name=number` lines. Keep it fast — every second is multiplied by hundreds of runs. Update it during the loop as needed.

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

## Data Integrity Protocol

**CRITICAL: JSONL data must never be corrupted or lost.**

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

### Atomic Write Pattern

Never append directly to JSONL. Use atomic write pattern:

```bash
write_jsonl_entry() {
    local entry="$1"
    local jsonl_file="autoresearch.jsonl"
    local temp_file="${jsonl_file}.tmp.$$"
    
    # Create temp file
    cat "$jsonl_file" > "$temp_file" 2>/dev/null || touch "$temp_file"
    
    # Append entry
    echo "$entry" >> "$temp_file"
    
    # Validate the new entry
    if ! echo "$entry" | python3 -m json.tool >/dev/null 2>&1; then
        rm -f "$temp_file"
        echo "  WARNING: Invalid JSON entry, not writing" >&2
        return 1
    fi
    
    # Atomic move (guaranteed all-or-nothing)
    mv "$temp_file" "$jsonl_file"
    
    # Verify write succeeded
    local new_count=$(grep -c '"run":' "$jsonl_file" 2>/dev/null || echo 0)
    echo "Write verification: $new_count runs in JSONL" >&2
    
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
git diff --cached --quiet && echo "nothing to commit" || git commit -m "<description>

Result: {\"status\":\"keep\",\"<metricName>\":<value>,<secondary metrics>}"
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

```bash
echo '{"run":<N>,"commit":"<hash>","metric":<value>,"metrics":{<secondaries>},"status":"<status>","description":"<desc>","timestamp":'$(date +%s)',"segment":<seg>}' >> autoresearch.jsonl
```

### 4. Update dashboard

After every log, regenerate `autoresearch-dashboard.md` (see Dashboard section below).

### 5. Append to worklog

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

### 6. Secondary metric consistency

Once you start tracking a secondary metric, you MUST include it in every subsequent result. Parse the JSONL to discover which secondary metrics have been tracked and ensure all are present.

If you want to add a new secondary metric mid-session, that's fine — but from that point forward, always include it.

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

## State File Backup (Enhanced)

**BEFORE user-confirmable actions**, create backups:

```bash
# Before any major operation requiring user confirmation
if [[ -f "./scripts/backup-state.sh" ]]; then
    ./scripts/backup-state.sh backup autoresearch.jsonl 2>/dev/null || true
else
    cp autoresearch.jsonl "autoresearch.jsonl.backup.$(date +%s)" 2>/dev/null || true
fi
```

**Best practices**:
- Always backup before major changes or user confirmations
- Keep the last 5 backups (delete older ones)
- Restore from backup if experiment crashes or state becomes corrupted

**Automated cleanup**:
```bash
# Keep only last 5 backups
ls -t autoresearch.jsonl.bak.* 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true
```

**Warning**: If JSONL data loss is detected, check backups immediately before continuing.

---

## Data Loss Detection and Recovery

**If you detect data loss** (e.g., dashboard shows inconsistency, JSONL count doesn't match worklog):

1. **Immediate actions**:
   ```bash
   # Check for data loss
   JSONL_COUNT=$(grep -c '"run":' autoresearch.jsonl 2>/dev/null || echo 0)
   WORKLOG_COUNT=$(grep -c "^### Run" experiments/worklog.md 2>/dev/null || echo 0)
   
   if [[ "$JSONL_COUNT" -ne "$WORKLOG_COUNT" ]]; then
       echo "  DATA LOSS DETECTED: JSONL has $JSONL_COUNT runs, worklog has $WORKLOG_COUNT runs" >&2
   fi
   ```

2. **Check backups**:
   ```bash
   ./scripts/backup-state.sh list autoresearch.jsonl
   ```

3. **Recovery options**:
   - **Best**: Restore from backup if recent enough
   - **Alternative**: Manually recreate missing runs from worklog notes
   - **Last resort**: Start new segment with new config header

4. **Prevention**: Always backup before user-confirmable actions (see "User-Confirmable Actions" above)

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

User messages sent while an experiment is running should be noted and incorporated into the NEXT experiment. Finish your current experiment first — don't stop or ask for confirmation. Incorporate the user's idea in the next experiment.

## Updating autoresearch.md

Periodically update `autoresearch.md` — especially the "What's Been Tried" section — so that a fresh agent resuming the loop has full context on what worked, what didn't, and what architectural insights have been gained. Do this every 5-10 experiments or after any significant breakthrough.
