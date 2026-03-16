# Autoresearch: Optimize bogo sort runtime

## Objective
Optimize the runtime of bogo sort algorithm in `bogo_sort.py`. The goal is to reduce the time spent in the hot loop (shuffle + sorted check) by optimizing the `is_sorted()` function. **Do not modify the original `bogo_sort.py`** - create a sidecar file `bogo_sort_optimized.py` instead.

## Metrics
- **Primary**: runtime (seconds, lower is better)
- **Secondary**: memory usage (MB, lower is better)

## How to Run
```bash
python3 bogo_sort_optimized.py
```

The script should use a fixed random seed for reproducibility and sort 10 random integers.

## Files in Scope
- `bogo_sort_optimized.py` - New optimized version of bogo sort (create this)
- `experiments/worklog.md` - Experiment log

## Off Limits
- `bogo_sort.py` - Original file must remain untouched

## Constraints
1. Do not modify the original `bogo_sort.py`
2. Use fixed random seed (e.g., `random.seed(42)`) for reproducibility
3. Benchmark with exactly 10 random integers (1-1000 range)
4. Optimize for runtime only, not code simplicity
5. Must produce correct sorted output

## What's Been Tried

*Last updated: Run #0 on 2026-03-16*