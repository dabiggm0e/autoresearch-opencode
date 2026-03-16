# Experiments Worklog: bogo_sort runtime optimization

**Session Started:** 2026-03-16
**Objective:** Optimize bogo_sort.py runtime by creating optimized sidecar file

## Data Summary

| Metric | Unit | Direction |
|--------|------|-----------|
| runtime | seconds | lower is better |

## Baseline Result

### Run 1: baseline — runtime=4.707548s (KEEP)
- Timestamp: 2026-03-16 16:45
- What changed: Initial baseline measurement
- Result: runtime=4.707548s
- Insight: Baseline established for comparison - runtime is higher than expected due to random seed
- Next: Create optimized version and test various approaches

### Run 2: Approach 1: Built-in sorted() comparison — runtime=5.855910s (DISCARD)
- Timestamp: 2026-03-16 16:50
- What changed: Replaced manual loop with array == sorted(array) comparison
- Result: runtime=5.855910s (+24.4% slower)
- Insight: Built-in sorted() creates a new list, adding overhead. Manual loop is faster.
- Next: Try binary search or bisect-based detection

## Key Insights

- Baseline runtime is very fast due to small input size (10 elements)
- Need to focus on algorithmic improvements for the is_sorted function
- Optimization opportunities: early exit, binary search detection, bisect module

## Next Ideas

1. Use built-in sorted() comparison for is_sorted
2. Implement binary search-based detection
3. Use bisect module for sorted detection
4. Early exit optimization in is_sorted loop