# Quick Start Guide

## What is autoresearch-opencode?

Autoresearch-opencode is an autonomous code optimization system that runs self-directed experiments to iteratively improve your code. It uses OpenCode's built-in tools to automatically discover optimal solutions with measurable performance gains.

## Prerequisites

- OpenCode installed and running
- Git available

## 3-Minute Setup

```bash
git clone https://github.com/dabiggm0e/autoresearch-opencode.git
cd autoresearch && ./scripts/install.sh
skill autoresearch
```

## Your First Experiment (2 minutes)

Try the included test project that optimizes the world's worst sorting algorithm - BogoSort:

```bash
/autoresearch optimize bogo_sort.py runtime
```

**Results you'll see:**
- Baseline: 1.481s (naive BogoSort O((n+1)!))
- After optimization: 0.000002s (Timsort O(n log n))
- **Speedup: 740,500x faster!**

## Other Examples

**Test suite optimization:**
```bash
/autoresearch optimize test-runner.ts runtime
```

**Memory reduction:**
```bash
/autoresearch optimize your-file.ts memory
```

## Essential Commands

| Command | Description |
|---------|-------------|
| `/autoresearch <goal>` | Start new experiment (e.g., `runtime`, `memory`) |
| `/autoresearch` | Resume from last state (autoresearch.jsonl) |
| `/autoresearch off/on` | Pause or resume experiment context |
| `/autoresearch dashboard` | View experiment results |

## Quick Troubleshooting

**Context not appearing?**
1. Check if plugin loaded: `skill autoresearch`
2. Reinstall: `./scripts/install.sh`

**State file not found?**
1. Fresh start: Run experiment command directly
2. Continue with context: Copy previous context manually
3. Restore backup: Run `./scripts/backup-state.sh list autoresearch.jsonl`

## Next Steps

- [README.md](README.md) — Full documentation
- [docs/BACKUP-USAGE.md](docs/BACKUP-USAGE.md) — Backup and restore guide

Happy optimizing!
