#!/bin/bash
#
# autoresearch-state-backup.sh
# 
# Auto-backup functionality for autoresearch state files.
# Designed to be called before experiment runs.
#
# Usage:
#   ./backup-state.sh <command> [options]
#
# Commands:
#   backup          Create timestamped backups of all state files
#   cleanup         Remove old backups, keeping only the last 5 per file
#   restore         Restore from the most recent backup
#   list            List available backups for a specific file
#   restore-auto    Restore from most recent backup without confirmation
#   all             Run backup, cleanup, and list in sequence
#
# State files backed up:
#   - autoresearch.jsonl
#   - autoresearch-dashboard.md
#   - experiments/worklog.md
#
# Backup format: filename.bak.YYYYMMDD_HHMMSS
#
# Examples:
#   ./backup-state.sh backup          # Create backups
#   ./backup-state.sh cleanup         # Clean old backups
#   ./backup-state.sh backup cleanup  # Chain commands
#   ./backup-state.sh restore         # Interactive restore
#
# This script is safe to run multiple times.

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"  # Parent of scripts/ directory
BACKUP_DIR="${PROJECT_ROOT}"
MAX_BACKUPS=5
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# State files to backup (relative to BACKUP_DIR)
declare -a STATE_FILES=(
    "autoresearch.jsonl"
    "autoresearch-dashboard.md"
    "experiments/worklog.md"
)

# Print usage information
usage() {
    cat << EOF
Usage: $(basename "$0") <command> [options]

Commands:
  backup          Create timestamped backups of all state files
  cleanup         Remove old backups, keeping only the last 5 per file
  restore         Restore from the most recent backup (interactive)
  list [file]     List available backups for a specific file
  restore-auto    Restore from most recent backup without confirmation
  all             Run backup, cleanup, and list in sequence
  help            Show this help message

Examples:
  $(basename "$0") backup
  $(basename "$0") cleanup
  $(basename "$0") backup cleanup
  $(basename "$0") restore
  $(basename "$0") list autoresearch.jsonl

EOF
    exit 0
}

# Check if a file exists
file_exists() {
    local file="$1"
    local full_path="${BACKUP_DIR}/${file}"
    [[ -f "$full_path" ]]
}

# Get all backups for a specific file, sorted by date (newest first)
get_backups() {
    local base_file="$1"
    local pattern="${base_file}.bak.*"
    local backups=()
    
    # Find backups in the backup directory
    while IFS= read -r -d '' backup; do
        backups+=("$backup")
    done < <(find "$BACKUP_DIR" -maxdepth 1 -name "$pattern" -type f -print0 2>/dev/null | sort -z -r)
    
    printf '%s\n' "${backups[@]}"
}

# Create a backup of a single file
backup_file() {
    local file="$1"
    local full_path="${BACKUP_DIR}/${file}"
    local base_name=$(basename "$file")
    local backup_name="${base_name}.bak.${TIMESTAMP}"
    local backup_path="${BACKUP_DIR}/${backup_name}"
    
    if file_exists "$file"; then
        cp -p "$full_path" "$backup_path"
        echo "✓ Backed up: ${file} -> ${backup_name}"
        return 0
    else
        echo "⚠ Skipping: ${file} (not found)"
        return 1
    fi
}

# Cleanup old backups for a single file
cleanup_file() {
    local file="$1"
    local base_name=$(basename "$file")
    local pattern="${base_name}.bak.*"
    local count=0
    
    # Get all backups sorted by date (newest first)
    local backups=()
    while IFS= read -r backup; do
        [[ -n "$backup" ]] && backups+=("$backup")
    done < <(find "$BACKUP_DIR" -maxdepth 1 -name "$pattern" -type f 2>/dev/null | sort -r)
    
    count=${#backups[@]}
    
    if [[ $count -eq 0 ]]; then
        echo "  No backups found for ${file}"
        return 0
    fi
    
    if [[ $count -le $MAX_BACKUPS ]]; then
        echo "  ${file}: ${count} backup(s) (within limit of ${MAX_BACKUPS})"
        return 0
    fi
    
    # Delete old backups beyond the limit
    local deleted=0
    for ((i=MAX_BACKUPS; i<count; i++)); do
        local backup="${backups[$i]}"
        rm -f "$backup"
        echo "  🗑 Deleted old backup: $(basename "$backup")"
        ((deleted++)) || true
    done
    
    echo "  ${file}: Cleaned up ${deleted} old backup(s), kept ${MAX_BACKUPS}"
}

# Perform backup of all state files
do_backup() {
    echo "=== Creating backups (timestamp: ${TIMESTAMP}) ==="
    local success=0
    local total=0
    
    for file in "${STATE_FILES[@]}"; do
        ((total++)) || true
        if backup_file "$file"; then
            ((success++)) || true
        fi
    done
    
    echo ""
    echo "Backup complete: ${success}/${total} files backed up"
    echo ""
}

# Perform cleanup of old backups
do_cleanup() {
    echo "=== Cleaning up old backups (keeping last ${MAX_BACKUPS}) ==="
    echo ""
    
    for file in "${STATE_FILES[@]}"; do
        cleanup_file "$file"
    done
    
    echo ""
    echo "Cleanup complete"
    echo ""
}

# List available backups for a file
list_backups() {
    local file="$1"
    local base_name=$(basename "$file")
    local pattern="${base_name}.bak.*"
    
    echo "=== Available backups for: ${file} ==="
    
    local backups=()
    while IFS= read -r backup; do
        [[ -n "$backup" ]] && backups+=("$backup")
    done < <(find "$BACKUP_DIR" -maxdepth 1 -name "$pattern" -type f 2>/dev/null | sort -r)
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        echo "  No backups found"
        return 0
    fi
    
    echo "  Total: ${#backups[@]} backup(s)"
    echo ""
    
    local idx=0
    for backup in "${backups[@]}"; do
        local size=$(stat -c%s "$backup" 2>/dev/null || echo "0")
        local date=$(stat -c%y "$backup" 2>/dev/null | cut -d. -f1)
        echo "  [${idx}] $(basename "$backup") (${size} bytes, ${date})"
        ((idx++))
    done
    
    echo ""
}

# Interactive restore
do_restore() {
    echo "=== Restore from backup ==="
    echo ""
    
    # Check if there are any backups
    local has_backups=false
    for file in "${STATE_FILES[@]}"; do
        if [[ -n "$(get_backups "$file")" ]]; then
            has_backups=true
            break
        fi
    done
    
    if [[ "$has_backups" == "false" ]]; then
        echo "❌ No backups found. Run 'backup' first."
        return 1
    fi
    
    echo "Available state files to restore:"
    for file in "${STATE_FILES[@]}"; do
        local backups=$(get_backups "$file")
        if [[ -n "$backups" ]]; then
            echo "  ✓ ${file}"
        fi
    done
    echo ""
    
    # List all files that have backups
    local files_with_backups=()
    for file in "${STATE_FILES[@]}"; do
        if [[ -n "$(get_backups "$file")" ]]; then
            files_with_backups+=("$file")
        fi
    done
    
    # Interactive selection
    local num_files=${#files_with_backups[@]}
    if [[ $num_files -eq 0 ]]; then
        echo "No backups available to restore."
        return 1
    fi
    
    if [[ $num_files -eq 1 ]]; then
        # Only one file with backups, ask for confirmation
        local file="${files_with_backups[0]}"
        local backup=$(get_backups "$file" | head -n 1)
        local base_name=$(basename "$file")
        local backup_name=$(basename "$backup")
        local backup_path="${BACKUP_DIR}/${backup_name}"
        
        echo "Found most recent backup: ${backup_name}"
        echo ""
        read -p "Restore ${file} from this backup? (y/N): " -r
        echo ""
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cp -p "$backup_path" "${BACKUP_DIR}/${file}"
            echo "✓ Restored: ${file}"
        else
            echo "Restore cancelled."
        fi
    else
        # Multiple files, show all backups and let user select
        echo "Select a file to restore (or 'all' to restore all, 'cancel' to abort):"
        echo ""
        
        local idx=0
        declare -A file_map
        for file in "${files_with_backups[@]}"; do
            local backups=$(get_backups "$file")
            local backup=$(echo "$backups" | head -n 1)
            local backup_name=$(basename "$backup")
            
            echo "  [${idx}] ${file} (latest: ${backup_name})"
            file_map[$idx]="$file"
            ((idx++))
        done
        
        echo "  [all] Restore all files to their latest backup"
        echo "  [cancel] Abort"
        echo ""
        
        read -p "Enter selection: " -r
        echo ""
        
        if [[ $REPLY == "all" ]]; then
            echo "Restoring all files..."
            for file in "${files_with_backups[@]}"; do
                local backup=$(get_backups "$file" | head -n 1)
                local backup_path="${BACKUP_DIR}/$(basename "$backup")"
                cp -p "$backup_path" "${BACKUP_DIR}/${file}"
                echo "✓ Restored: ${file}"
            done
        elif [[ $REPLY == "cancel" ]]; then
            echo "Restore cancelled."
        elif [[ $REPLY =~ ^[0-9]+$ ]]; then
            local idx=$REPLY
            if [[ $idx -lt $num_files ]]; then
                local file="${file_map[$idx]}"
                local backup=$(get_backups "$file" | head -n 1)
                local backup_path="${BACKUP_DIR}/$(basename "$backup")"
                cp -p "$backup_path" "${BACKUP_DIR}/${file}"
                echo "✓ Restored: ${file}"
            else
                echo "Invalid selection."
            fi
        else
            echo "Invalid selection."
        fi
    fi
    
    echo ""
}

# Auto-restore without confirmation
do_restore_auto() {
    echo "=== Auto-restore from most recent backups ==="
    echo ""
    
    local restored=0
    local total=0
    
    for file in "${STATE_FILES[@]}"; do
        ((total++)) || true
        local backup
        backup=$(get_backups "$file" | head -n 1)
        
        if [[ -n "$backup" ]]; then
            local backup_path="${BACKUP_DIR}/$(basename "$backup")"
            cp -p "$backup_path" "${BACKUP_DIR}/${file}"
            echo "✓ Restored: ${file} from $(basename "$backup")"
            ((restored++)) || true
        else
            echo "⚠ No backup available for: ${file}"
        fi
    done
    
    echo ""
    echo "Restore complete: ${restored}/${total} files restored"
    echo ""
}

# Main entry point
main() {
    if [[ $# -eq 0 ]]; then
        echo "Error: No command specified."
        echo ""
        usage
    fi
    
    # Allow chaining of commands
    for cmd in "$@"; do
        case "$cmd" in
            backup)
                do_backup
                ;;
            cleanup)
                do_cleanup
                ;;
            restore)
                do_restore
                ;;
            restore-auto)
                do_restore_auto
                ;;
            list)
                if [[ $# -gt 1 ]]; then
                    list_backups "$2"
                else
                    echo "Usage: $(basename "$0") list <file>"
                    echo ""
                    echo "Available files:"
                    for file in "${STATE_FILES[@]}"; do
                        echo "  - ${file}"
                    done
                fi
                ;;
            all)
                do_backup
                do_cleanup
                list
                ;;
            help|--help|-h)
                usage
                ;;
            *)
                echo "Error: Unknown command '${cmd}'"
                echo ""
                usage
                ;;
        esac
    done
}

# Run main function
main "$@"
