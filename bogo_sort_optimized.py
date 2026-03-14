#!/usr/bin/env python3
"""
Bogo Sort Implementation

A randomized sorting algorithm that repeatedly shuffles the list until
it happens to be sorted. Also known as stupid sort or permutation sort.

Usage:
    python3 bogo_sort.py
"""

import random
import time


# Global counter to track shuffle operations
_shuffle_count = 0


def is_sorted(array: list) -> bool:
    """Check if the array is sorted in ascending order."""
    return all(a <= b for a, b in zip(array, array[1:]))


def bogo_sort(array: list) -> list:
    """
    Sort an array using the bogo sort algorithm.

    This randomized algorithm repeatedly shuffles the list until
    it happens to be sorted. Time complexity is O((n+1)!) on average.

    Args:
        array: List of comparable elements to sort

    Returns:
        The sorted list
    """
    # Create a copy to avoid mutating the input (Atomic Predictability)
    result = array.copy()

    while not is_sorted(result):
        random.shuffle(result)
        global _shuffle_count
        _shuffle_count += 1

    return result


def main():
    """Main entry point for the bogo sort script."""
    global _shuffle_count

    # Reset shuffle counter before sorting
    _shuffle_count = 0

    # Start timing
    start_time = time.perf_counter()

    # Generate exactly 10 random integers (Hardcoded requirement)
    numbers = [random.randint(1, 1000) for _ in range(10)]

    # Sort using bogo sort (Atomic Predictability)
    sorted_numbers = bogo_sort(numbers)

    # Stop timing
    end_time = time.perf_counter()
    runtime = end_time - start_time

    # Print the sorted array (Intentional Naming - clear output)
    print(sorted_numbers)

    # Output metrics in parseable format
    print(f"METRIC runtime={runtime:.3f}s")
    print(f"METRIC shuffle_count={_shuffle_count}")


if __name__ == "__main__":
    main()
