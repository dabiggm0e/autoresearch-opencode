#!/bin/bash

# Autoresearch Install Script for OpenCode
# This script copies files to install autoresearch components globally

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
OPENCODE_CONFIG="${HOME}/.config/opencode"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Track if user confirmed
USER_CONFIRMED=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force|-f)
            USER_CONFIRMED=true
            shift
            ;;
        --help|-h)
            echo "Usage: ${BASH_SOURCE[0]} [--force|-f] [--help|-h]"
            echo ""
            echo "Options:"
            echo "  --force, -f    Skip user confirmation and install directly"
            echo "  --help, -h     Show this help message"
            echo ""
            echo "This script installs autoresearch components to OpenCode global"
            echo "directories by copying files (not symlinks)."
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Helper function for colored output
print_header() {
    echo -e "${BLUE}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${NC}  $1${NC}"
}

# Check if the script is being run from the correct location
if [[ ! -d "${PROJECT_ROOT}/plugins" || ! -d "${PROJECT_ROOT}/skills" || ! -d "${PROJECT_ROOT}/commands" ]]; then
    print_error "This script must be run from the autoresearch project root."
    print_error "Expected directories: plugins/, skills/, commands/"
    print_error "Current directory: ${PROJECT_ROOT}"
    exit 1
fi

# Verify required files exist
print_header "Verifying required files..."

REQUIRED_FILES=(
    "plugins/autoresearch-context.ts"
    "skills/autoresearch/SKILL.md"
    "commands/autoresearch.md"
)

FILES_OK=true
for file in "${REQUIRED_FILES[@]}"; do
    if [[ -f "${PROJECT_ROOT}/${file}" ]]; then
        print_success "Found: ${file}"
    else
        print_error "Missing: ${file}"
        FILES_OK=false
    fi
done

if [[ "${FILES_OK}" != "true" ]]; then
    print_error "Some required files are missing. Installation cannot proceed."
    exit 1
fi

echo ""

# Check if ~/.config/opencode exists and is writable
print_header "Checking OpenCode config directory..."

if [[ ! -d "${OPENCODE_CONFIG}" ]]; then
    print_warning "OpenCode config directory does not exist: ${OPENCODE_CONFIG}"
    print_error "Cannot proceed: directory not found and cannot be auto-created"
    print_error ""
    print_error "Please create it manually:"
    echo "  mkdir -p ${OPENCODE_CONFIG}"
    exit 1
fi

# Test if we can write to the directory
if [[ ! -w "${OPENCODE_CONFIG}" ]]; then
    print_error "Cannot write to ${OPENCODE_CONFIG}"
    print_error ""
    print_error "Please ensure you have write permissions:"
    echo "  chown -R $(whoami) ${OPENCODE_CONFIG}"
    exit 1
fi

print_success "Config directory is writable: ${OPENCODE_CONFIG}"

# Create required subdirectories
print_header "Creating required directories..."

SUBDIRS=(
    "plugins"
    "skills/autoresearch"
    "commands"
    "scripts"
)

for subdir in "${SUBDIRS[@]}"; do
    target_dir="${OPENCODE_CONFIG}/${subdir}"
    if [[ ! -d "${target_dir}" ]]; then
        if mkdir -p "${target_dir}"; then
            print_success "Created: ${target_dir}"
        else
            print_error "Failed to create: ${target_dir}"
            exit 1
        fi
    else
        print_info "Exists: ${target_dir}"
    fi
done

echo ""

# Define files to copy
print_header "Components to install:"

declare -A INSTALL_MAP
INSTALL_MAP=(
    ["plugins/autoresearch-context.ts"]="${OPENCODE_CONFIG}/plugins/autoresearch-context.ts"
    ["skills/autoresearch/SKILL.md"]="${OPENCODE_CONFIG}/skills/autoresearch/SKILL.md"
    ["commands/autoresearch.md"]="${OPENCODE_CONFIG}/commands/autoresearch.md"
)

for src_file in "${!INSTALL_MAP[@]}"; do
    dst_file="${INSTALL_MAP[${src_file}]}"
    echo "  ${GREEN}→${NC} ${src_file}"
    echo "    → ${dst_file}"
    echo ""
done

# User confirmation
if [[ "${USER_CONFIRMED}" != "true" ]]; then
    echo -n "Proceed with installation? [y/N] "
    read -r response
    
    case "${response}" in
        y|Y|yes|Yes|YES)
            USER_CONFIRMED=true
            ;;
        *)
            print_info "Installation cancelled."
            exit 0
            ;;
    esac
fi

echo ""
print_header "Installing files..."

INSTALL_FAILED=false
COPIED_FILES=()

for src_file in "${!INSTALL_MAP[@]}"; do
    dst_file="${INSTALL_MAP[${src_file}]}"
    src_path="${PROJECT_ROOT}/${src_file}"
    dst_path="${dst_file}"
    filename="$(basename "${src_file}")"
    
    # Ensure destination directory exists
    dst_dir="$(dirname "${dst_path}")"
    if [[ ! -d "${dst_dir}" ]]; then
        if ! mkdir -p "${dst_dir}"; then
            print_error "Failed to create directory: ${dst_dir}"
            print_error "  Skipping: ${filename}"
            INSTALL_FAILED=true
            continue
        fi
    fi
    
    # Remove existing symlink or file before copying
    if [[ -e "${dst_path}" || -L "${dst_path}" ]]; then
        if ! rm -f "${dst_path}"; then
            print_error "Failed to remove existing file: ${filename}"
            print_error "  Destination: ${dst_path}"
            INSTALL_FAILED=true
            continue
        fi
    fi
    
    # Copy file with force overwrite
    if cp "${src_path}" "${dst_path}"; then
        print_success "${filename}: Copied"
        COPIED_FILES+=("${src_file}")
        
        # Verify the copy was successful
        if [[ -f "${dst_path}" ]]; then
            src_size=$(stat -c%s "${src_path}" 2>/dev/null || stat -f%z "${src_path}" 2>/dev/null)
            dst_size=$(stat -c%s "${dst_path}" 2>/dev/null || stat -f%z "${dst_path}" 2>/dev/null)
            
            if [[ "${src_size}" == "${dst_size}" ]]; then
                print_info "  Verified: ${src_size} bytes"
            else
                print_warning "  Size mismatch: source=${src_size}, dest=${dst_size}"
                INSTALL_FAILED=true
            fi
        else
            print_error "  Verification failed: file not found at destination"
            INSTALL_FAILED=true
        fi
    else
        print_error "Failed to copy: ${filename}"
        print_error "  Source: ${src_path}"
        print_error "  Destination: ${dst_path}"
        
        # Try to diagnose the issue
        if [[ ! -r "${src_path}" ]]; then
            print_error "  Reason: Source file is not readable"
        elif [[ ! -w "${dst_dir}" ]]; then
            print_error "  Reason: Destination directory is not writable"
        else
            print_error "  Reason: Unknown (check disk space and permissions)"
        fi
        INSTALL_FAILED=true
    fi
    echo ""
done

# Install backup utility
print_header "Installing backup utility..."

BACKUP_SCRIPT="${SCRIPT_DIR}/backup-state.sh"
BACKUP_DEST="${OPENCODE_CONFIG}/scripts/backup-state.sh"

if [[ -f "${BACKUP_SCRIPT}" ]]; then
    mkdir -p "${OPENCODE_CONFIG}/scripts"
    if cp "${BACKUP_SCRIPT}" "${BACKUP_DEST}"; then
        chmod +x "${BACKUP_DEST}"
        print_success "backup-state.sh: Installed to ${BACKUP_DEST}"
    else
        print_error "Failed to copy backup-state.sh"
        INSTALL_FAILED=true
    fi
else
    print_warning "backup-state.sh not found in project root, skipping backup utility installation"
fi

echo ""

# Final verification
print_header "Final verification..."

ALL_VALID=true
for src_file in "${COPIED_FILES[@]}"; do
    dst_file="${INSTALL_MAP[${src_file}]}"
    filename="$(basename "${src_file}")"
    src_path="${PROJECT_ROOT}/${src_file}"
    dst_path="${dst_file}"
    
    if [[ -f "${dst_path}" ]]; then
        src_size=$(stat -c%s "${src_path}" 2>/dev/null || stat -f%z "${src_path}" 2>/dev/null)
        dst_size=$(stat -c%s "${dst_path}" 2>/dev/null || stat -f%z "${dst_path}" 2>/dev/null)
        
        if [[ "${src_size}" == "${dst_size}" ]]; then
            print_success "${filename}: Installed and verified"
            print_info "    Location: ${dst_path}"
        else
            print_error "${filename}: Size mismatch"
            print_info "    Source: ${src_size} bytes"
            print_info "    Destination: ${dst_size} bytes"
            ALL_VALID=false
        fi
    else
        print_error "${filename}: File missing at destination"
        print_info "    Expected: ${dst_path}"
        ALL_VALID=false
    fi
done

echo ""

# Summary
if [[ "${INSTALL_FAILED}" == "true" || "${ALL_VALID}" != "true" || "${#COPIED_FILES[@]}" -eq 0 ]]; then
    if [[ "${#COPIED_FILES[@]}" -eq 0 ]]; then
        print_error "No files were installed."
    else
        print_warning "Installation completed with errors."
    fi
    exit 1
fi

print_success "Installation completed successfully!"
echo ""
echo "📦 Installation summary:"
echo ""
echo "Installed to OpenCode global directories:"
echo "  ${OPENCODE_CONFIG}/"
echo ""
echo "Components:"
for src_file in "${COPIED_FILES[@]}"; do
    dst_file="${INSTALL_MAP[${src_file}]}"
    filename="$(basename "${src_file}")"
    echo ""
    echo "  ${GREEN}✓${NC} ${filename}"
    echo "    Installed to: ${dst_file}"
done
echo ""
echo "  ${GREEN}✓${NC} backup-state.sh"
echo "    Installed to: ${BACKUP_DEST}"

echo ""
echo " Next steps:"
echo "   1. Load the skill: skill autoresearch"
echo "   2. The plugin will automatically inject context before prompts"
echo "   3. Use 'autoresearch off' to temporarily disable context"
echo "   4. Use 'autoresearch on' to re-enable context"
echo ""

exit 0
