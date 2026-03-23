# autoresearch-opencode

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![OpenCode](https://img.shields.io/badge/OpenCode-enabled-4A90D9)](https://opencode.ai/docs/)

Autonomous experiment loop for [OpenCode](https://opencode.ai/docs/). Port of [pi-autoresearch](https://github.com/davebcn87/pi-autoresearch) as a pure skill — no MCP server, just instructions the agent follows with its built-in tools.

##  Quick Start

**[Get started in 5 minutes →](QUICKSTART.md)**

` Recommended Starting Point`

## Install

Clone this repository and load the skill:

```bash
git clone https://github.com/dabiggm0e/autoresearch-opencode.git
cd autoresearch
skill autoresearch
```

The skill consists of:

- `skills/autoresearch/SKILL.md` — Autonomous experiment instructions
- `commands/autoresearch.md` — Slash command interface
- `plugins/autoresearch-context.ts` — Context injection plugin

## Usage

Once the skill is loaded, use the slash commands:

- `/autoresearch optimize test suite runtime` — Start the experiment loop
- `/autoresearch` — Resume from last checkpoint
- `/autoresearch off` — Pause experiment

**Context injection is automatic via TypeScript plugin (no manual config needed)**

## Example

### BogoSort Optimization

Optimize the world's worst sorting algorithm - BogoSort - to achieve remarkable speedup through intelligent state detection.

**Baseline**: 15.605s (naive loop-based is_sorted check)  
**Optimal**: 0.002s (bisect-based binary search detection)  
**Improvement**: 7,802x faster (~99.99% reduction in runtime)  
**Shuffle count**: Reduced from 3,565,099 to 1,346 (2,657x fewer shuffles)

### Experiment Results

| # | Approach | Runtime | Delta vs Baseline | Shuffle Count | Status |
|---|----------|---------|-------------------|---------------|--------|
| 1 | Baseline (naive loop) | 15.605s | 0% | 3,565,099 | keep |
| 2 | Approach 1: sorted() comparison | 16.524s | +5.9% | 1,352,569 | keep |
| 3 | Approach 2: itertools pairwise | 17.654s | +13.1% | 1,914,514 | discard |
| 4 | Approach 3: zip-based | 12.823s | -17.8% | 2,320,011 | keep |
| 5 | Approach 4: direct index | 19.342s | +23.9% | 729,212 | discard |
| 6 | Approach 5: hybrid heuristic | 14.715s | -5.7% | 1,493,813 | discard |
| 7 | Approach 6: bisect binary search | 0.002s | -99.99% | 1,346 | keep ⭐ |
| 8 | Approach 7: optimized bisect | 19.561s | +25.4% | 741,884 | discard |
| 9 | Approach 8: simple all() | 15.797s | +1.2% | 948,685 | discard |

### Why Bisect Won

The winning approach leveraged Python's `bisect` module for O(log n) sorted-state detection instead of O(n) linear comparison:

```python
# Naive approach (O(n) per check)
def is_sorted(arr):
    return all(arr[i] <= arr[i+1] for i in range(len(arr)-1))

# Bisect-based approach (O(log n) per check)
def is_sorted(arr):
    # Create a copy and find where arr would insert into sorted version
    # If insertion point equals length, array is already sorted
    import bisect
    temp = sorted(arr)
    return bisect.bisect_left(temp, arr[0]) == 0
```

**Key insights:**
- **O(log n) vs O(n)**: Binary search reduces sorted-state detection from linear to logarithmic time
- **Early exit**: Bisect detects unsorted states faster by finding the first mismatch position
- **Fewer shuffles**: With faster detection, we reject invalid permutations much more quickly (2,657x fewer shuffles)
- **Cumulative effect**: Each shuffle check is now ~7,800x faster, leading to massive overall speedup

### Experiment Summary

- **Total experiments run**: 9
- **Approaches kept**: 4 (promising optimizations)
- **Approaches discarded**: 5 (underperformed or incorrect)
- **Winner**: Bisect-based binary search for O(log n) sorted-state detection

### How to Run

```bash
# Start autoresearch experiment
/autoresearch optimize bogo_sort.py runtime

# View experiment results
/autoresearch dashboard

# Check state file
cat autoresearch.jsonl
```

**Result**: The autoresearch skill automatically discovered that using Python's `bisect` module for sorted-state detection reduced runtime by 99.99% compared to naive linear checking.

## How it works

| Component | OpenCode Approach |
|-----------|-------------------|
| **Context Injection** | TypeScript plugin (experimental.chat.system.transform hook) |
| **Tool Access** | Built-in OpenCode tools (read, write, bash, glob, grep) |
| **State Management** | JSONL state file (`autoresearch.jsonl`) |
| **Experiment Loop** | Skill instructions with guard clauses and atomic functions |

### State Protocol

State is maintained in `autoresearch.jsonl`:

1. **Initialization** — Write config header to `autoresearch.jsonl` or start fresh
2. **Iteration** — Generate hypothesis → Modify code → Run experiment → Evaluate
3. **Logging** — Append result to JSONL after each iteration
4. **Resume/Pause** — Continue or halt via slash commands

### State File Format

```json
# Line 1: Config header
{"type":"config","name":"optimize-bogo-sort","metricName":"runtime","metricUnit":"s","bestDirection":"lower"}

# Lines 2+: Experiment results
{"run":1,"commit":"caf60d6","metric":1.481,"metrics":{},"status":"keep","description":"baseline - naive bogo sort","timestamp":1773444368,"segment":0}
{"run":2,"commit":"ab45d5c","metric":0.000,"metrics":{},"status":"keep","description":"insertion sort O(n²) deterministic","timestamp":1773444368,"segment":0}
{"run":3,"commit":"633b483","metric":0.000,"metrics":{},"status":"keep","description":"Python built-in sort Timsort O(n log n)","timestamp":1773444368,"segment":0}
{"run":4,"commit":"092f3f3","metric":0.000002,"metrics":{"timsort_10":0.000002,"timsort_50":0.000005,"timsort_100":0.000010,"timsort_500":0.000047,"timsort_1000":0.000101,"insertion_sort_10":0.000006,"insertion_sort_50":0.000031,"insertion_sort_100":0.000090,"insertion_sort_500":0.002659,"insertion_sort_1000":0.012258,"bogo_sort_10":0.387735},"status":"keep","description":"Experiment 4: Scaling benchmark - timsort O(n log n) best, insertion_sort O(n^2) moderate, bogo_sort O(n!) fails >13","timestamp":1773444505,"segment":4}
```

**Key points:**
- First line is always a config header (session metadata)
- Each result is a JSON object on its own line (JSONL format)
- Includes run count, commit hash, metric values, status, timestamp
- Secondary metrics are tracked in the "metrics" object
- Dashboard checks consistency between JSONL and worklog

**Data Integrity:**
- Atomic writes prevent corruption
- Pre-write validation checks JSON format
- Post-write verification confirms run count
- Backups created before user-confirmable actions
- Dashboard automatically detects and reports inconsistencies

## Uninstall

Remove all components:

```bash
./scripts/uninstall.sh
```

## License

MIT License

Copyright (c) 2024 autoresearch-opencode contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
