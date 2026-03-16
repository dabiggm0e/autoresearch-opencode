# Autoresearch: bogo_sort runtime optimization

## Objective
Optimize the runtime of bogo_sort.py by creating an optimized sidecar file (bogo_sort_optimized.py). The goal is to reduce execution time while maintaining the same algorithmic structure and functionality.

## Metrics
- **Primary**: runtime (seconds, lower is better)

## How to Run
`./autoresearch.sh` — outputs `METRIC runtime=number` lines.

## Files in Scope
- `bogo_sort_optimized.py` - Sidecar optimized version (created, may modify)
- `autoresearch.sh` - Benchmark script (created, may update)

## Off Limits
- `bogo_sort.py` - Original implementation (read-only, must NOT be modified)

## Constraints
- No new dependencies
- Must work with existing algorithm structure
- Original bogo_sort.py must remain unchanged

## What's Been Tried

### Run #1 (KEEP) ⭐
- **Timestamp:** 2026-03-16 12:00
- **Description:** baseline
- **Result:** runtime=0.001s

*Last updated: Run #1 on 2026-03-16*