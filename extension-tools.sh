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
    echo "  status     Show project status"
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

# Symlink management functions
create_symlink() {
    local target=$1
    local link_name=$2

    log_debug "Creating symlink: $link_name -> $target"

    if [ -L "$link_name" ]; then
        log_verbose "Removing existing symlink $link_name"
        rm "$link_name"
    elif [ -e "$link_name" ]; then
        log_warning "$link_name exists but is not a symlink"
        if ! ask_user "$link_name exists. Remove it?"; then
            handle_error "Cannot proceed without creating symlink $link_name"
        fi
        rm -ri "$link_name"
    fi

    if ln -s "$target" "$link_name"; then
        log_success "Created symlink: $link_name -> $target"
    else
        handle_error "Failed to create symlink $link_name -> $target"
    fi
}

remove_symlink() {
    local link_name=$1

    if [ -L "$link_name" ]; then
        log_debug "Removing symlink: $link_name"
        if ! rm "$link_name"; then
            handle_error "Failed to remove symlink $link_name"
        fi
        log_verbose "Removed symlink: $link_name"
    fi
}

check_and_handle_existing_backup() {
    local backup_path=$1
    local original_path=$2
    local type=$3 # "directory" or "file"

    log_debug "Checking existing backup: $backup_path for $original_path"

    if [ -e "$backup_path" ]; then
        log_warning "Backup $backup_path already exists"
        if ! ask_user "Previous backup $backup_path exists. Remove it?"; then
            handle_error "Cannot proceed without removing existing backup"
        fi
        log_verbose "Removing existing backup $backup_path"
        rm -rf "$backup_path" || handle_error "Failed to remove existing backup"
        log_debug "Successfully removed existing backup"
    fi
}

prepare_environment() {
    local item=$1 # "node_modules" or "package.json"
    local pnpm_backup="${BACKUP_FILES[$item]}"
    local npm_backup="${BACKUP_FILES[npm_$item]}"
    local type=$([ "$item" = "node_modules" ] && echo "directory" || echo "file")

    log_debug "Preparing environment for $item"

    # Check if the item exists and is not a symlink
    if [ -e "$item" ]; then
        if [ ! -L "$item" ]; then
            log_verbose "Found regular $type: $item"

            # Check and handle existing pnpm backup
            check_and_handle_existing_backup "$pnpm_backup" "$item" "$type"

            # Move the original to pnpm backup
            log_debug "Moving $item to $pnpm_backup"
            mv "$item" "$pnpm_backup" || handle_error "Failed to create backup of $item"
            log_success "Moved: $item → $pnpm_backup"
        else
            log_debug "$item is already a symlink"
        fi
    else
        log_debug "$item does not exist"
    fi
}

backup_file() {
    local source=$1
    local target=$2

    log_debug "Attempting to backup file: source=$source, target=$target"

    if [ ! -e "$source" ]; then
        log_debug "Source $source doesn't exist, skipping backup"
        return 0
    fi

    log_verbose "Source $source exists, proceeding with backup"

    if [ -e "$target" ]; then
        log_debug "Target $target already exists"
        if ! ask_user "$target already exists. Remove it?"; then
            handle_error "Cannot proceed without backing up $source"
        fi
        log_verbose "User agreed to remove existing target"
        if ! rm -ri "$target"; then
            handle_error "Failed to remove $target"
        fi
        log_debug "Successfully removed existing target $target"
    else
        log_debug "Target $target does not exist, no need for removal"
    fi

    log_debug "Backing up $source to $target"
    if [ -d "$source" ]; then
        log_verbose "Source is a directory"
        if [ -L "$source" ]; then
            log_debug "Source is a symlink, copying the directory it points to"
            cp -R "$(readlink "$source")" "$target" || handle_error "Failed to backup directory $source"
        else
            log_debug "Source is a regular directory, moving it"
            mv "$source" "$target" || handle_error "Failed to backup directory $source"
        fi
    else
        log_verbose "Source is a file, performing simple copy"
        cp "$source" "$target" || handle_error "Failed to backup file $source"
    fi
    log_success "Backed up $source → $target"
    log_debug "Backup operation completed successfully"
}

# Package management functions
modify_npm_package_json() {
    log_debug "Modifying npm-package.json scripts to use npm"
    local temp_file="temp.json"
    if [ -f "$temp_file" ]; then
        log_debug "Removing existing temporary file: $temp_file"
        rm "$temp_file" || handle_error "Failed to remove existing temporary file"
    fi

    if ! jq '.scripts |= with_entries(.value |= gsub("pnpm"; "npm"))' npm-package.json >"$temp_file"; then
        handle_error "Failed to modify npm-package.json"
    fi

    mv "$temp_file" "npm-package.json" || handle_error "Failed to update npm-package.json"
    log "Updated npm-package.json to use npm commands"
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

switch_to_npm() {
    log "Switching to npm environment..."
    log_debug "Entering switch_to_npm function"

    # Prepare both node_modules and package.json
    prepare_environment "node_modules"
    prepare_environment "package.json"

    # Remove any existing symlinks
    log_verbose "Removing any existing symlinks"
    remove_symlink "node_modules"
    remove_symlink "package.json"

    # Handle node_modules
    if [ -d "${BACKUP_FILES["npm_node_modules"]}" ]; then
        log_debug "Found existing npm node_modules, creating symlink"
        create_symlink "${BACKUP_FILES["npm_node_modules"]}" "node_modules"
    fi

    # Handle package.json
    if [ -f "${BACKUP_FILES["npm_package_json"]}" ]; then
        log_debug "Found existing npm package.json, creating symlink"
        create_symlink "${BACKUP_FILES["npm_package_json"]}" "package.json"
    else
        log_debug "No existing npm package.json, creating modified version"
        # Create npm version of package.json if it doesn't exist
        cp "${BACKUP_FILES["package.json"]}" "${BACKUP_FILES["npm_package_json"]}" || handle_error "Failed to create npm package.json"
        modify_npm_package_json
        create_symlink "${BACKUP_FILES["npm_package_json"]}" "package.json"
    fi

    log_debug "Exiting switch_to_npm function"
    log_success "Successfully switched to npm environment"
}

switch_to_pnpm() {
    log "Switching back to pnpm environment..."
    log_debug "Entering switch_to_pnpm function"

    # Remove npm symlinks
    log_verbose "Removing npm symlinks"
    remove_symlink "node_modules"
    remove_symlink "package.json"

    # Create symlinks to pnpm files
    if [ -d "${BACKUP_FILES["node_modules"]}" ]; then
        log_debug "Creating symlink to pnpm node_modules"
        create_symlink "${BACKUP_FILES["node_modules"]}" "node_modules"
    else
        log_error "pnpm node_modules backup not found!"
        handle_error "Cannot switch to pnpm environment"
    fi

    if [ -f "${BACKUP_FILES["package.json"]}" ]; then
        log_debug "Creating symlink to pnpm package.json"
        create_symlink "${BACKUP_FILES["package.json"]}" "package.json"
    else
        log_error "pnpm package.json backup not found!"
        handle_error "Cannot switch to pnpm environment"
    fi

    log_debug "Exiting switch_to_pnpm function"
    log_success "Successfully switched to pnpm environment"
}

restore_original_state() {
    log "Attempting to restore original state..."
    log_debug "Entering restore_original_state function"

    # First, remove any existing symlinks
    log_verbose "Removing any existing symlinks"
    remove_symlink "node_modules"
    remove_symlink "package.json"

    # Restore node_modules if it existed
    if [ "${ORIGINAL_STATE["has_node_modules"]}" = "true" ]; then
        log_verbose "Original state had node_modules"
        if [ -d "${BACKUP_FILES["node_modules"]}" ]; then
            log_debug "Found backup of node_modules, restoring"
            if [ -d "node_modules" ]; then
                log_debug "Removing existing node_modules directory"
                rm -rf "node_modules"
            fi
            mv "${BACKUP_FILES["node_modules"]}" "node_modules" || handle_error "Failed to restore node_modules"
            log_success "Restored original node_modules"
        else
            log_warning "Original node_modules backup not found"
        fi
    else
        log_debug "Original state did not have node_modules"
    fi

    # Restore package.json if it existed
    if [ "${ORIGINAL_STATE["has_package_json"]}" = "true" ]; then
        log_verbose "Original state had package.json"
        if [ -f "${BACKUP_FILES["package.json"]}" ]; then
            log_debug "Found backup of package.json, restoring"
            if [ -f "package.json" ]; then
                log_debug "Removing existing package.json"
                rm -f "package.json"
            fi
            mv "${BACKUP_FILES["package.json"]}" "package.json" || handle_error "Failed to restore package.json"
            log_success "Restored original package.json"
        else
            log_warning "Original package.json backup not found"
        fi
    else
        log_debug "Original state did not have package.json"
    fi

    # Clean up temporary files
    log_verbose "Cleaning up temporary files"
    for temp_file in temp.json; do
        if [ -f "$temp_file" ]; then
            log_debug "Removing temporary file: $temp_file"
            rm -f "$temp_file" || log_warning "Failed to remove temporary file: $temp_file"
        fi
    done

    # Clean up backup files if requested
    if ask_user "Would you like to clean up backup files?" "n"; then
        log_verbose "Cleaning up backup files"
        for backup_file in "${BACKUP_FILES[@]}"; do
            if [ -e "$backup_file" ]; then
                log_debug "Removing backup file: $backup_file"
                rm -rf "$backup_file" || log_warning "Failed to remove backup file: $backup_file"
            fi
        done
        log_success "Cleaned up all backup files"
    else
        log_debug "Keeping backup files as requested"
    fi

    log_debug "Exiting restore_original_state function"
    log_success "Original state restored"
}

do_package() {
    log "Starting package process..."
    log_verbose "Initializing state"
    init_state

    # Step 1: Switch to npm environment
    log_verbose "Step 1: Switching to npm environment"
    switch_to_npm
    log_debug "npm environment switch completed"

    # Step 2: Run npm commands
    log_verbose "Step 2: Running npm commands"
    log_debug "Starting npm install"
    run_npm_install
    log_debug "npm install completed"

    log_debug "Starting VSIX package creation"
    create_vsix_package
    log_debug "VSIX package creation completed"

    # Step 3: Switch back to pnpm environment
    log_verbose "Step 3: Switching back to pnpm environment"
    switch_to_pnpm
    log_debug "pnpm environment switch completed"

    # Step 4: Verify final state
    log_verbose "Step 4: Verifying final pnpm state"
    verify_pnpm_state
    log_debug "Final pnpm state verification completed"

    # Show success message and list the generated vsix file
    log_success "Package command completed successfully!"
    log_verbose "Listing generated VSIX package"
    echo -e "${GREEN}Generated VSIX package:${NC}"
    ls -l *.vsix
    log_debug "Package process finished"
}

# Status checking functions
get_symlink_target() {
    local item=$1
    if [ -L "$item" ]; then
        readlink "$item"
    else
        echo "not a symlink"
    fi
}

get_file_type() {
    local item=$1
    if [ ! -e "$item" ]; then
        echo "${GRAY}not found${NC}"
    elif [ -L "$item" ]; then
        echo "${CYAN}symlink${NC} → $(get_symlink_target "$item")"
    elif [ -d "$item" ]; then
        echo "${BLUE}directory${NC}"
    elif [ -f "$item" ]; then
        echo "${GREEN}file${NC}"
    else
        echo "${RED}unknown${NC}"
    fi
}

determine_environment() {
    if [ -L "node_modules" ]; then
        local target=$(get_symlink_target "node_modules")
        case "$target" in
        *pnpm-node_modules)
            echo "pnpm"
            ;;
        *npm-node_modules)
            echo "npm"
            ;;
        *)
            echo "unknown"
            ;;
        esac
    elif [ -d "node_modules" ]; then
        echo "regular"
    else
        echo "none"
    fi
}

format_size() {
    local size=$1
    if [ $size -ge 1073741824 ]; then
        echo "$(printf "%.1f" $(echo "scale=1; $size/1073741824" | bc))G"
    elif [ $size -ge 1048576 ]; then
        echo "$(printf "%.1f" $(echo "scale=1; $size/1048576" | bc))M"
    elif [ $size -ge 1024 ]; then
        echo "$(printf "%.1f" $(echo "scale=1; $size/1024" | bc))K"
    else
        echo "${size}B"
    fi
}

get_directory_size() {
    local dir=$1
    if [ -d "$dir" ]; then
        local size=$(du -s "$dir" 2>/dev/null | cut -f1)
        format_size $((size * 1024))
    else
        echo "N/A"
    fi
}

do_status() {
    log "Checking project status..."

    # Determine current environment
    local env=$(determine_environment)
    echo -e "\n${BOLD}Current Environment:${NC} ${MAGENTA}$env${NC}"

    # Show file statuses
    echo -e "\n${BOLD}File Status:${NC}"
    echo -e "  node_modules:        $(get_file_type "node_modules")"
    echo -e "  package.json:        $(get_file_type "package.json")"

    # Show backup status
    echo -e "\n${BOLD}Backup Status:${NC}"
    echo -e "  pnpm-node_modules:   $(get_file_type "${BACKUP_FILES["node_modules"]}") ($(get_directory_size "${BACKUP_FILES["node_modules"]}"))"
    echo -e "  pnpm-package.json:   $(get_file_type "${BACKUP_FILES["package.json"]}")"
    echo -e "  npm-node_modules:    $(get_file_type "${BACKUP_FILES["npm_node_modules"]}") ($(get_directory_size "${BACKUP_FILES["npm_node_modules"]}"))"
    echo -e "  npm-package.json:    $(get_file_type "${BACKUP_FILES["npm_package_json"]}")"

    # Show VSIX package status
    echo -e "\n${BOLD}VSIX Package Status:${NC}"
    if compgen -G "*.vsix" >/dev/null; then
        for vsix in *.vsix; do
            local size=$(stat -f%z "$vsix" 2>/dev/null)
            echo -e "  $vsix: $(format_size $size)"
        done
    else
        echo -e "  ${GRAY}No VSIX packages found${NC}"
    fi

    # Show package manager versions
    echo -e "\n${BOLD}Package Manager Versions:${NC}"
    if command -v npm >/dev/null; then
        echo -e "  npm:               $(npm --version 2>/dev/null || echo "${RED}error${NC}")"
    else
        echo -e "  npm:               ${RED}not installed${NC}"
    fi
    if command -v pnpm >/dev/null; then
        echo -e "  pnpm:              $(pnpm --version 2>/dev/null || echo "${RED}error${NC}")"
    else
        echo -e "  pnpm:              ${RED}not installed${NC}"
    fi
    if command -v node >/dev/null; then
        echo -e "  node:              $(node --version 2>/dev/null || echo "${RED}error${NC}")"
    else
        echo -e "  node:              ${RED}not installed${NC}"
    fi

    echo # Empty line at end
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
        status)
            do_status
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
