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

**Key requirements:**
1. Include ALL runs (KEEP, DISCARD, CRASH) - do not filter any out
2. Use emoji markers: ⭐ for KEEP, 💥 for CRASH, none for DISCARD
3. Always update the "Last updated" marker at end of section
4. If the section doesn't exist yet, create it with header `## What's Been Tried`

**Implementation tip:** Read the latest entry from autoresearch.jsonl to get the run number, status, description, and metric value, then append formatted text to autoresearch.md.

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

User messages sent while an experiment is running should be noted and incorporated into the NEXT experiment. Finish your current experiment first — don't stop or ask for confirmation. Incorporate the user's idea in the next experiment.

## Updating autoresearch.md

**MANDATORY PROTOCOL:** Update `autoresearch.md` after **EVERY** experiment, not periodically. 

See the Logging Results section (step 4) for the format to use. This ensures:
1. Zero drift between autoresearch.jsonl and the markdown summary
2. Any resuming agent has complete context on all runs
3. No reliance on memory or judgment about "significant breakthroughs"

**NEVER SKIP THIS STEP.** If you skip updating after an experiment, the next agent may repeat failed approaches or miss key insights, wasting computational resources and time.

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
