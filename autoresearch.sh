#!/usr/bin/env bash
# Autoresearch benchmark script for bogo_sort runtime optimization
set -euo pipefail

# Run the optimized version and measure runtime
python3 -c "
import time
import random

# Seed for reproducibility in benchmark
random.seed(42)

# Import the optimized version
import bogo_sort_optimized

# Generate test data
numbers = [random.randint(1, 1000) for _ in range(10)]

# Measure runtime
start = time.perf_counter()
sorted_numbers = bogo_sort_optimized.bogo_sort(numbers)
end = time.perf_counter()

runtime = end - start
print(f'METRIC runtime={runtime:.6f}')
"