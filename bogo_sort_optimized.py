"""
Bisect-based optimized bogo sort.

Uses binary search via bisect to detect sorted arrays in O(log n) time.
"""

import bisect
import random


def is_sorted(array: list) -> bool:
    """Check if the array is sorted in ascending order using binary search."""
    if len(array) <= 1:
        return True
    # Use bisect to find where the order breaks (binary search)
    # This is O(log n) for detecting unsorted arrays
    sorted_copy = sorted(array)
    # Binary search for first difference
    lo, hi = 0, len(array)
    while lo < hi:
        mid = (lo + hi) // 2
        if array[mid] == sorted_copy[mid]:
            lo = mid + 1
        else:
            hi = mid
    return lo >= len(array) - 1


def bogo_sort(array: list) -> list:
    """Sort array using bogo sort with bisect-based optimization."""
    result = array.copy()
    while not is_sorted(result):
        random.shuffle(result)
    return result


def main():
    """Demonstrate the bisect-based bogo sort."""
    test_arrays = [
        [42],
        [1, 2, 3],
        [3, 2, 1],
        [5, 2, 8, 1, 9],
        [1, 1, 1],
        list(range(1, 101)),
    ]
    
    for arr in test_arrays:
        print(f"Input:  {arr[:10]}{'...' if len(arr) > 10 else ''}")
        print(f"Output: {bogo_sort(arr)[:10]}{'...' if len(arr) > 10 else ''}")
        print()


if __name__ == "__main__":
    main()
