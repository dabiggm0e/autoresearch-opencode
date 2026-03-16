#!/usr/bin/env bash
#
# autoresearch.sh
#
# Benchmarks the bogo sort runtime by running the script multiple times
# and calculating the average execution time.
#
# Usage:
#     ./autoresearch.sh
#

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PYTHON_SCRIPT="${SCRIPT_DIR}/bogo_sort_optimized.py"
readonly NUM_RUNS=5

# Check if the Python script exists (Fail Fast)
if [[ ! -f "${PYTHON_SCRIPT}" ]]; then
    echo "Error: ${PYTHON_SCRIPT} does not exist" >&2
    exit 1
fi

# Run the benchmark using Python for timing and calculation
average_runtime=$(python3 << 'PYTHON_EOF'
import subprocess
import time

NUM_RUNS = 5
runtimes = []

for _ in range(NUM_RUNS):
    start = time.perf_counter()
    subprocess.run(['python3', 'bogo_sort_optimized.py'], 
                   capture_output=True, check=True)
    end = time.perf_counter()
    runtimes.append(end - start)

average = sum(runtimes) / len(runtimes)
print(f"{average:.6f}")
PYTHON_EOF
)

# Output the metric in required format
echo "METRIC runtime=${average_runtime}"
