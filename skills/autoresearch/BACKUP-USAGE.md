# Backup Usage Guide

## Overview

The autoresearch backup utility creates timestamped backups of critical state files to protect against data loss.

## State Files Backed Up

| File | Purpose |
|------|---------|
| `autoresearch.jsonl` | Main experiment state and results data |
| `autoresearch-dashboard.md` | Dashboard/markdown report of experiment progress |
| `experiments/worklog.md` | Detailed worklog of experiment activities |

## Installation

Verify the backup script is installed and executable:

```bash
ls -la ./scripts/backup-state.sh
chmod +x ./scripts/backup-state.sh
```

## Basic Commands

| Command | Description |
|---------|-------------|
| `backup` | Create timestamped backups of all state files |
| `cleanup` | Remove old backups, keeping only the last 5 per file |
| `restore` | Restore from the most recent backup (interactive) |
| `restore-auto` | Restore from most recent backup without confirmation |
| `list [file]` | List available backups for a specific file |
| `all` | Run backup, cleanup, and list in sequence |

## Usage Examples

Create a backup:
```bash
./scripts/backup-state.sh backup
```

Clean up old backups:
```bash
./scripts/backup-state.sh cleanup
```

Restore from backup:
```bash
./scripts/backup-state.sh restore
```

Backup and cleanup in one command:
```bash
./scripts/backup-state.sh backup cleanup
```

## Integration with Workflow

### Pre-Experiment Backup

Run before starting any new experiment:
```bash
./scripts/backup-state.sh backup
```

### In Experiment Scripts

Include backup commands in your scripts:
```bash
#!/bin/bash
./scripts/backup-state.sh backup
# Run your experiment
./scripts/backup-state.sh cleanup
```

### Shell Aliases

Add to your shell configuration:
```bash
alias ar-backup="./scripts/backup-state.sh backup"
alias ar-cleanup="./scripts/backup-state.sh cleanup"
alias ar-all="./scripts/backup-state.sh all"
```

## Backup Format

Backups follow the naming convention: `<filename>.bak.<YYYYMMDD_HHMMSS>`

Example: `autoresearch.jsonl.bak.20260313_142530`

## Best Practices

1. **Backup before experiments** - Always create a backup before starting new experiments
2. **Regular cleanup** - Run cleanup weekly to prevent disk space issues
3. **Verify backups** - List backups periodically to ensure they're working
4. **External copies** - For critical experiments, copy important backups externally

## Troubleshooting

**Backup command not found:**
```bash
chmod +x ./scripts/backup-state.sh
```

**No backups available:**
```bash
./scripts/backup-state.sh backup
```

**Disk space concerns:**
```bash
./scripts/backup-state.sh cleanup
```

---

*For full documentation, see the backup-state.sh script help: `./scripts/backup-state.sh help`*