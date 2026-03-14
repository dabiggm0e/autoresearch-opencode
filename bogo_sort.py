#!/usr/bin/env python3
"""
Bogo Sort Implementation

A randomized sorting algorithm that repeatedly shuffles the list until
it happens to be sorted. Also known as stupid sort or permutation sort.

Usage:
    python3 bogo_sort.py
"""

import random


def is_sorted(array: list) -> bool:
    """Check if the array is sorted in ascending order."""
    for i in range(len(array) - 1):
        if array[i] > array[i + 1]:
            return False
    return True


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

    return result


def main():
    """Main entry point for the bogo sort script."""
    # Generate exactly 10 random integers (Hardcoded requirement)
    numbers = [random.randint(1, 1000) for _ in range(10)]

    # Sort using bogo sort (Atomic Predictability)
    sorted_numbers = bogo_sort(numbers)

    # Print the sorted array (Intentional Naming - clear output)
    print(sorted_numbers)


if __name__ == "__main__":
    main()
