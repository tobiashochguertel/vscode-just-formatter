#!/usr/bin/env bash

# Color support flag (default to auto-detect)
USE_COLOR="auto"

# Debug flag (default to false)
DEBUG=false

# Verbose flag (default to false)
VERBOSE=false

# Process color options first
for arg in "$@"; do
    case "$arg" in
    --no-color)
        USE_COLOR="no"
        ;;
    esac
done

# Color definitions
setup_colors() {
    if [ "$USE_COLOR" = "no" ] || { [ "$USE_COLOR" = "auto" ] && [ ! -t 1 ]; }; then
        RED=''
        GREEN=''
        YELLOW=''
        BLUE=''
        GRAY=''
        CYAN=''
        MAGENTA=''
        BOLD=''
        NC=''
    else
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        GRAY='\033[0;90m'
        CYAN='\033[0;36m'
        MAGENTA='\033[0;35m'
        BOLD='\033[1m'
        NC='\033[0m' # No Color
    fi
}

# Initialize colors
setup_colors

# Logger functions to print colored messages
log() { log_info "$1" >&2; }
log_info() { echo -e "${BLUE}INFO${NC} $1" >&2; }
log_success() { echo -e "${GREEN}SUCCESS${NC} $1" >&2; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}ERROR${NC} $1" >&2; }
log_verbose() { [ "$VERBOSE" = true ] && echo -e "${GRAY}VERBOSE${NC} $1" >&2; }
log_debug() { [ "$DEBUG" = true ] && echo -e "${MAGENTA}DEBUG${NC} $1" >&2; }

# Usage information
usage() {
    echo -e "${CYAN}Usage:${NC} $(basename "$0") ${BLUE}[OPTIONS]${NC} ${GREEN}COMMAND${NC}"
    echo
    echo -e "${CYAN}Description:${NC}"
    echo "A tool for managing VSCode extension development workflow"
    echo
    echo -e "${GREEN}Commands:${NC}"
    echo "  package    Create a VSIX package for the extension"
    echo
    echo -e "${BLUE}Options:${NC}"
    echo "  -h, --help      Show this help message"
    echo "  --no-color      Disable color output"
    echo "  -v, --verbose   Enable verbose output (default: false)"
    echo "  --debug         Enable debug output (default: false)"
    echo
    echo -e "${BOLD}Examples:${NC}"
    echo
    echo -e "   $(basename "$0") ${GREEN}package${NC}"
    echo -e "   $(basename "$0") ${BLUE}--no-color${NC} ${GREEN}package${NC}"
    echo
    echo -e "${GRAY}For more information, visit: https://github.com/yourusername/extension-tools${NC}"
}

# Check if jq is installed
check_dependencies() {
    if ! command -v jq &>/dev/null; then
        log_error "jq is not installed. Please install it first."
        exit 1
    fi
}

# State management
# Check the Bash version
case ${BASH_VERSION%%.*} in
4 | 5 | 6)
    # Bash 4.0 or later, declare associative arrays
    declare -A ORIGINAL_STATE
    declare -A BACKUP_FILES
    ;;
*)
    # Bash 3.x or earlier, use a workaround
    ORIGINAL_STATE=()
    BACKUP_FILES=()
    echo "Warning: Bash version is too old, using a workaround for associative arrays."
    ;;
esac

# Initialize state tracking
init_state() {
    ORIGINAL_STATE["has_node_modules"]=$([ -d "node_modules" ] && echo "true" || echo "false")
    ORIGINAL_STATE["has_package_json"]=$([ -f "package.json" ] && echo "true" || echo "false")
    ORIGINAL_STATE["current_dir"]=$(pwd)

    BACKUP_FILES["node_modules"]="pnpm-node_modules"
    BACKUP_FILES["package.json"]="pnpm-package.json"
    BACKUP_FILES["npm_node_modules"]="npm-node_modules"
    BACKUP_FILES["npm_package_json"]="npm-package.json"
}

# User interaction functions
ask_user() {
    local question=$1
    local default=${2:-"n"}

    while true; do
        read -p "$(echo -e "${YELLOW}${question} (y/n) [${default}]:${NC} ")" answer
        case ${answer:-${default}} in
        [Yy]*) return 0 ;;
        [Nn]*) return 1 ;;
        *) echo "Please answer yes or no." ;;
        esac
    done
}

handle_error() {
    local error_msg=$1
    log_error "$error_msg"

    if ask_user "Would you like to restore the original state?"; then
        restore_original_state
        log "Original state restored"
        exit 1
    else
        log_warning "Keeping current state. You may need to manually fix things."
        exit 1
    fi
}

# Backup functions
backup_file() {
    local source=$1
    local target=$2

    if [ ! -e "$source" ]; then
        debug "Source $source doesn't exist, skipping backup"
        return 0
    fi

    if [ -e "$target" ]; then
        if ! ask_user "$target already exists. Remove it?"; then
            handle_error "Cannot proceed without backing up $source"
        fi
        if ! rm -ri "$target"; then
            handle_error "Failed to remove $target"
        fi
    fi

    debug "Backing up $source to $target"
    if [ -d "$source" ]; then
        mv "$source" "$target" || handle_error "Failed to backup directory $source"
    else
        cp "$source" "$target" || handle_error "Failed to backup file $source"
    fi
    log "Backed up $source → $target"
}

restore_original_state() {
    log "Attempting to restore original state..."

    # Restore node_modules if it existed
    if [ "${ORIGINAL_STATE["has_node_modules"]}" = "true" ]; then
        if [ -d "${BACKUP_FILES["node_modules"]}" ]; then
            mv "${BACKUP_FILES["node_modules"]}" "node_modules"
            log "Restored original node_modules"
        fi
    fi

    # Restore package.json if it existed
    if [ "${ORIGINAL_STATE["has_package_json"]}" = "true" ]; then
        if [ -f "${BACKUP_FILES["package.json"]}" ]; then
            mv "${BACKUP_FILES["package.json"]}" "package.json"
            log "Restored original package.json"
        fi
    fi

    # Clean up any temporary files
    rm -f temp.json
}

# Package management functions
modify_package_json() {
    debug "Modifying package.json scripts to use npm"
    local temp_file="temp.json"

    if ! jq '.scripts |= with_entries(.value |= gsub("pnpm"; "npm"))' package.json >"$temp_file"; then
        handle_error "Failed to modify package.json"
    fi

    mv "$temp_file" package.json || handle_error "Failed to update package.json"
    log "Updated package.json to use npm commands"
}

run_npm_install() {
    log "Running npm install..."
    if ! npm install; then
        handle_error "npm install failed"
    fi
    log "npm install completed successfully"
}

create_vsix_package() {
    log "Creating VSIX package..."
    if ! npm exec vsce package; then
        handle_error "VSIX package creation failed"
    fi
    log "VSIX package created successfully"
}

verify_pnpm_state() {
    log "Verifying pnpm state..."
    if ! pnpm install; then
        handle_error "Final pnpm install verification failed"
    fi
    log "pnpm state verified successfully"
}

# Main package function
do_package() {
    log "Starting package process..."
    init_state

    # Step 1: Backup current state
    backup_file "node_modules" "${BACKUP_FILES["node_modules"]}"
    backup_file "package.json" "${BACKUP_FILES["package.json"]}"

    # Step 2: Modify package.json
    modify_package_json

    # Step 3: Handle npm node_modules
    if [ -d "${BACKUP_FILES["npm_node_modules"]}" ]; then
        debug "Found existing npm node_modules"
        backup_file "${BACKUP_FILES["npm_node_modules"]}" "node_modules"
    fi

    # Step 4: Run npm commands
    run_npm_install
    create_vsix_package

    # Step 5: Backup npm state
    backup_file "node_modules" "${BACKUP_FILES["npm_node_modules"]}"
    backup_file "package.json" "${BACKUP_FILES["npm_package_json"]}"

    # Step 6: Restore pnpm state
    backup_file "${BACKUP_FILES["node_modules"]}" "node_modules"
    backup_file "${BACKUP_FILES["package.json"]}" "package.json"

    # Step 7: Verify final state
    verify_pnpm_state

    # Show success message and list the generated vsix file
    log "Package command completed successfully!"
    echo -e "${GREEN}Generated VSIX package:${NC}"
    ls -l *.vsix
}

# Main script logic
main() {
    # Show help if no arguments
    if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        usage
        exit 0
    fi

    check_dependencies

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
        -v | --verbose)
            VERBOSE=true
            shift
            ;;
        -d | --debug)
            DEBUG=true
            VERBOSE=true
            shift
            ;;
        package)
            do_package
            exit 0
            ;;
        *)
            log_error "Unknown command or option: $1"
            usage
            exit 1
            ;;
        esac
    done
}

# Execute main function with all arguments
main "$@"
