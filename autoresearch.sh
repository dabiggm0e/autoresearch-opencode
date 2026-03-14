#!/bin/bash
set -euo pipefail

# Bogo Sort Benchmark Script
# Runs bogo_sort_optimized.py 10 times and aggregates metrics

NUM_ITERATIONS=10
TOTAL_RUNTIME=0
TOTAL_SHUFFLES=0
TIMEOUT_PER_ITERATION=2  # seconds per iteration to ensure <30s total

for ((i = 1; i <= NUM_ITERATIONS; i++)); do
    # Run the script with timeout and capture output
    if OUTPUT=$(timeout ${TIMEOUT_PER_ITERATION}s python3 bogo_sort_optimized.py 2>&1); then
        # Extract runtime and shuffle_count from output
        RUNTIME=$(echo "$OUTPUT" | grep "METRIC runtime=" | sed 's/METRIC runtime=\([0-9.]*\)s/\1/')
        SHUFFLES=$(echo "$OUTPUT" | grep "METRIC shuffle_count=" | sed 's/METRIC shuffle_count=\([0-9]*\)/\1/')
        echo "Iteration $i: runtime=${RUNTIME}s, shuffle_count=${SHUFFLES}"
    else
        # Timeout occurred - record as timeout
        RUNTIME=$TIMEOUT_PER_ITERATION
        SHUFFLES=0
        echo "Iteration $i: TIMEOUT (>${TIMEOUT_PER_ITERATION}s)"
    fi
    
    # Add to totals (using awk for floating-point arithmetic)
    TOTAL_RUNTIME=$(awk "BEGIN {printf \"%.3f\", $TOTAL_RUNTIME + $RUNTIME}")
    TOTAL_SHUFFLES=$((TOTAL_SHUFFLES + SHUFFLES))
done

# Output aggregate metrics
echo "METRIC runtime=${TOTAL_RUNTIME}s"
echo "METRIC shuffle_count=${TOTAL_SHUFFLES}"

exit 0