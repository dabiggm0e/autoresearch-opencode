#!/bin/bash

# Autoresearch Uninstall Script for OpenCode
# This script removes autoresearch components from OpenCode global config directories

set -e

# Global config base directory
OPENCODE_BASE="${HOME}/.config/opencode"

# Files to remove from global locations
PLUGIN_FILE="${OPENCODE_BASE}/plugins/autoresearch-context.ts"
SKILL_FILE="${OPENCODE_BASE}/skills/autoresearch/SKILL.md"
COMMAND_FILE="${OPENCODE_BASE}/commands/autoresearch.md"
BACKUP_FILE="${OPENCODE_BASE}/scripts/backup-state.sh"

# Directories to potentially clean up (if empty)
PLUGIN_DIR="${OPENCODE_BASE}/plugins"
SKILL_DIR="${OPENCODE_BASE}/skills/autoresearch"
COMMAND_DIR="${OPENCODE_BASE}/commands"

# Print usage and exit
usage() {
    echo "Usage: $0 [--force]"
    echo ""
    echo "Remove autoresearch from OpenCode global config directories."
    echo ""
    echo "Options:"
    echo "  --force    Skip user confirmation"
    echo "  -h, --help Show this help message"
    exit 0
}

# Parse command line arguments
FORCE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

echo "🔧 Uninstalling Autoresearch from OpenCode..."
echo "   Config Base: ${OPENCODE_BASE}"
echo ""

# Check if OpenCode base directory exists
if [[ ! -d "${OPENCODE_BASE}" ]]; then
    echo "⚠ OpenCode config directory does not exist: ${OPENCODE_BASE}"
    echo "   This suggests OpenCode is not installed or configured differently."
    echo "   Exiting cleanly."
    exit 0
fi

# Check if any files exist in global locations
declare -a EXISTING_FILES=()

if [[ -f "${PLUGIN_FILE}" ]]; then
    EXISTING_FILES+=("${PLUGIN_FILE}")
fi

if [[ -f "${SKILL_FILE}" ]]; then
    EXISTING_FILES+=("${SKILL_FILE}")
fi

if [[ -f "${COMMAND_FILE}" ]]; then
    EXISTING_FILES+=("${COMMAND_FILE}")
fi

if [[ -f "${BACKUP_FILE}" ]]; then
    EXISTING_FILES+=("${BACKUP_FILE}")
fi

# If no files found, report and exit cleanly (idempotent)
if [[ ${#EXISTING_FILES[@]} -eq 0 ]]; then
    echo " Nothing to remove."
    echo "   No autoresearch files found in global config directories."
    echo "   (The installation may not be present or may have already been uninstalled.)"
    echo ""
    echo " Notes:"
    echo "   - Project-level files (if any) remain untouched"
    echo "   - This script only affects global OpenCode config"
    exit 0
fi

# Report what will be removed
echo "  The following files will be removed:"
for file in "${EXISTING_FILES[@]}"; do
    echo "   - ${file}"
done
echo ""

# Require confirmation unless --force
if [[ "${FORCE}" == "false" ]]; then
    read -p "Continue? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# Track removal results
declare -a REMOVED_FILES=()
declare -a FAILED_REMOVALS=()

# Remove files from global locations
echo "🗑  Removing installed files..."

# Remove plugin file
if [[ -f "${PLUGIN_FILE}" ]]; then
    if rm -f "${PLUGIN_FILE}" 2>/dev/null; then
        REMOVED_FILES+=("${PLUGIN_FILE}")
        echo "   ✓ Removed: ${PLUGIN_FILE}"
    else
        FAILED_REMOVALS+=("${PLUGIN_FILE}")
        echo "   ✗ Failed to remove: ${PLUGIN_FILE}"
    fi
fi

# Remove skill file
if [[ -f "${SKILL_FILE}" ]]; then
    if rm -f "${SKILL_FILE}" 2>/dev/null; then
        REMOVED_FILES+=("${SKILL_FILE}")
        echo "   ✓ Removed: ${SKILL_FILE}"
    else
        FAILED_REMOVALS+=("${SKILL_FILE}")
        echo "   ✗ Failed to remove: ${SKILL_FILE}"
    fi
fi

# Remove command file
if [[ -f "${COMMAND_FILE}" ]]; then
    if rm -f "${COMMAND_FILE}" 2>/dev/null; then
        REMOVED_FILES+=("${COMMAND_FILE}")
        echo "   ✓ Removed: ${COMMAND_FILE}"
    else
        FAILED_REMOVALS+=("${COMMAND_FILE}")
        echo "   ✗ Failed to remove: ${COMMAND_FILE}"
    fi
fi

# Remove backup script
if [[ -f "${BACKUP_FILE}" ]]; then
    if rm -f "${BACKUP_FILE}" 2>/dev/null; then
        REMOVED_FILES+=("${BACKUP_FILE}")
        echo "   ✓ Removed: ${BACKUP_FILE}"
    else
        FAILED_REMOVALS+=("${BACKUP_FILE}")
        echo "   ✗ Failed to remove: ${BACKUP_FILE}"
    fi
fi

echo ""

# Clean up empty directories (non-destructive)
echo "🧹 Cleaning up empty directories..."

# Try to remove plugins directory if empty
if [[ -d "${PLUGIN_DIR}" ]]; then
    if [[ -z "$(ls -A "${PLUGIN_DIR}" 2>/dev/null)" ]]; then
        if rmdir "${PLUGIN_DIR}" 2>/dev/null; then
            echo "   ✓ Removed empty directory: ${PLUGIN_DIR}"
        else
            echo "   ⚠ Could not remove directory: ${PLUGIN_DIR} (may not be empty or no permissions)"
        fi
    fi
fi

# Try to remove skills/autoresearch directory if empty
if [[ -d "${SKILL_DIR}" ]]; then
    if [[ -z "$(ls -A "${SKILL_DIR}" 2>/dev/null)" ]]; then
        if rmdir "${SKILL_DIR}" 2>/dev/null; then
            echo "   ✓ Removed empty directory: ${SKILL_DIR}"
        else
            echo "   ⚠ Could not remove directory: ${SKILL_DIR} (may not be empty or no permissions)"
        fi
    fi
fi

# Try to remove commands directory if empty
if [[ -d "${COMMAND_DIR}" ]]; then
    if [[ -z "$(ls -A "${COMMAND_DIR}" 2>/dev/null)" ]]; then
        if rmdir "${COMMAND_DIR}" 2>/dev/null; then
            echo "   ✓ Removed empty directory: ${COMMAND_DIR}"
        else
            echo "   ⚠ Could not remove directory: ${COMMAND_DIR} (may not be empty or no permissions)"
        fi
    fi
fi

# Try to remove scripts directory if empty
SCRIPTS_DIR="${OPENCODE_BASE}/scripts"
if [[ -d "${SCRIPTS_DIR}" ]]; then
    if [[ -z "$(ls -A "${SCRIPTS_DIR}" 2>/dev/null)" ]]; then
        if rmdir "${SCRIPTS_DIR}" 2>/dev/null; then
            echo "   ✓ Removed empty directory: ${SCRIPTS_DIR}"
        else
            echo "   ⚠ Could not remove directory: ${SCRIPTS_DIR} (may not be empty or no permissions)"
        fi
    fi
fi

echo ""

# Summary
echo " Uninstallation complete!"
echo ""

if [[ ${#REMOVED_FILES[@]} -gt 0 ]]; then
    echo " Removed files:"
    for file in "${REMOVED_FILES[@]}"; do
        echo "   - ${file}"
    done
fi

if [[ ${#FAILED_REMOVALS[@]} -gt 0 ]]; then
    echo " Failed to remove:"
    for file in "${FAILED_REMOVALS[@]}"; do
        echo "   - ${file}"
    done
    echo "   Please check file permissions or try running with elevated privileges."
    echo ""
fi

echo ""
echo " Notes:"
echo "   - Project-level files (if any) remain untouched"
echo "   - Only OpenCode global config files were affected"
echo "   - Running this script again is safe (idempotent)"

exit 0
