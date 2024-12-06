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
    echo "Handles npm/pnpm environment switching and package creation"
    echo
    echo -e "${GREEN}Commands:${NC}"
    echo "  package          Create a VSIX package for the extension (automatic process)"
    echo "  status           Show project status"
    echo "  switch-to-npm    Switch to npm environment"
    echo "  switch-to-pnpm   Switch to pnpm environment"
    echo "  npm-install      Run npm install (creates fresh npm-node_modules)"
    echo "  npm-compile      Run npm compile command"
    echo "  create-vsix      Create VSIX package"
    echo
    echo -e "${BLUE}Options:${NC}"
    echo "  -h, --help       Show this help message"
    echo "  --no-color       Disable color output"
    echo "  -v, --verbose    Enable verbose output (default: false)"
    echo "  --debug          Enable debug output (default: false)"
    echo
    echo -e "${BOLD}Examples:${NC}"
    echo
    echo -e "  # Automatic packaging process"
    echo -e "  $(basename "$0") ${GREEN}package${NC}"
    echo -e "  $(basename "$0") ${BLUE}--no-color${NC} ${GREEN}package${NC}"
    echo
    echo -e "  # Manual packaging process"
    echo -e "  $(basename "$0") ${GREEN}switch-to-npm${NC}"
    echo -e "  $(basename "$0") ${GREEN}npm-install${NC}"
    echo -e "  $(basename "$0") ${GREEN}npm-compile${NC}"
    echo -e "  $(basename "$0") ${GREEN}create-vsix${NC}"
    echo -e "  $(basename "$0") ${GREEN}switch-to-pnpm${NC}"
    echo
    echo -e "  # Check status"
    echo -e "  $(basename "$0") ${BLUE}--debug${NC} ${GREEN}status${NC}"
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

# Initialize backup file mappings
init_backup_files() {
    declare -gA BACKUP_FILES
    BACKUP_FILES=(
        ["node_modules"]="node_modules"
        ["package.json"]="package.json"
        ["npm_node_modules"]="npm-node_modules"
        ["npm_package_json"]="npm-package.json"
        ["pnpm_node_modules"]="pnpm-node_modules"
        ["pnpm_package_json"]="pnpm-package.json"
    )
    log_debug "Backup files initialized"
}

# Detect and normalize the current project state
detect_and_normalize_state() {
    log "Detecting current project state..."
    local current_state="unknown"
    local is_npm=false
    local is_pnpm=false

    # Check for npm indicators
    if [ -f "npm-package.json" ] || [ -d "npm-node_modules" ]; then
        is_npm=true
    fi

    # Check for pnpm indicators
    if [ -f "pnpm-package.json" ] || [ -d "pnpm-node_modules" ]; then
        is_pnpm=true
    fi

    # Regular package.json is treated as pnpm
    if [ -f "package.json" ] && [ ! -L "package.json" ]; then
        is_pnpm=true
    fi

    # Determine current state
    if [ "$is_npm" = true ] && [ "$is_pnpm" = false ]; then
        current_state="npm"
    elif [ "$is_npm" = false ] && [ "$is_pnpm" = true ]; then
        current_state="pnpm"
    elif [ "$is_npm" = true ] && [ "$is_pnpm" = true ]; then
        current_state="mixed"
    fi

    log_debug "Detected state: $current_state"

    # Handle node_modules directory
    if [ -d "node_modules" ] && [ ! -L "node_modules" ]; then
        log_warning "Found non-symlink node_modules directory"

        case $current_state in
        "npm")
            if [ ! -d "npm-node_modules" ]; then
                log_debug "Moving node_modules to npm-node_modules"
                mv "node_modules" "npm-node_modules" || handle_error "Failed to move node_modules to npm-node_modules"
                create_symlink "npm-node_modules" "node_modules"
            else
                if ask_user "Both node_modules directory and npm-node_modules exist. Remove node_modules?" "n"; then
                    rm -rf "node_modules" || handle_error "Failed to remove node_modules"
                    create_symlink "npm-node_modules" "node_modules"
                else
                    handle_error "Cannot proceed with both node_modules directory and npm-node_modules"
                fi
            fi
            ;;
        "pnpm" | "unknown")
            if [ ! -d "pnpm-node_modules" ]; then
                log_debug "Moving node_modules to pnpm-node_modules"
                mv "node_modules" "pnpm-node_modules" || handle_error "Failed to move node_modules to pnpm-node_modules"
                create_symlink "pnpm-node_modules" "node_modules"
            else
                if ask_user "Both node_modules directory and pnpm-node_modules exist. Remove node_modules?" "n"; then
                    rm -rf "node_modules" || handle_error "Failed to remove node_modules"
                    create_symlink "pnpm-node_modules" "node_modules"
                else
                    handle_error "Cannot proceed with both node_modules directory and pnpm-node_modules"
                fi
            fi
            ;;
        *)
            # Default to pnpm for mixed state
            if [ ! -d "pnpm-node_modules" ]; then
                log_debug "Moving node_modules to pnpm-node_modules (default choice)"
                mv "node_modules" "pnpm-node_modules" || handle_error "Failed to move node_modules to pnpm-node_modules"
                create_symlink "pnpm-node_modules" "node_modules"
            fi
            ;;
        esac
    fi

    # Handle package.json
    if [ -f "package.json" ] && [ ! -L "package.json" ]; then
        log_warning "Found non-symlink package.json"
        case $current_state in
        "npm")
            if [ ! -f "npm-package.json" ]; then
                log_debug "Moving package.json to npm-package.json"
                mv "package.json" "npm-package.json" || handle_error "Failed to move package.json to npm-package.json"
                create_symlink "npm-package.json" "package.json"
            else
                if ask_user "Both package.json and npm-package.json exist. Remove package.json?" "n"; then
                    rm -f "package.json" || handle_error "Failed to remove package.json"
                    create_symlink "npm-package.json" "package.json"
                else
                    handle_error "Cannot proceed with both package.json and npm-package.json"
                fi
            fi
            ;;
        "pnpm" | "unknown" | "mixed")
            # For unknown or mixed state, default to pnpm
            if [ ! -f "pnpm-package.json" ]; then
                log_debug "Moving package.json to pnpm-package.json"
                mv "package.json" "pnpm-package.json" || handle_error "Failed to move package.json to pnpm-package.json"
                create_symlink "pnpm-package.json" "package.json"
            else
                if ask_user "Both package.json and pnpm-package.json exist. Remove package.json?" "n"; then
                    rm -f "package.json" || handle_error "Failed to remove package.json"
                    create_symlink "pnpm-package.json" "package.json"
                else
                    handle_error "Cannot proceed with both package.json and pnpm-package.json"
                fi
            fi
            ;;
        esac
    fi

    # If state is still unknown but we moved files to pnpm, set it to pnpm
    if [ "$current_state" = "unknown" ] && [ -f "pnpm-package.json" ]; then
        current_state="pnpm"
    fi

    log_success "Project state normalized to: $current_state"
    echo "$current_state"
}

# Initialize state tracking
init_state() {
    ORIGINAL_STATE["has_node_modules"]=$([ -d "node_modules" ] && echo "true" || echo "false")
    ORIGINAL_STATE["has_package_json"]=$([ -f "package.json" ] && echo "true" || echo "false")
    ORIGINAL_STATE["current_dir"]=$(pwd)
    ORIGINAL_STATE["project_state"]=$(detect_and_normalize_state)
    ORIGINAL_STATE["is_packaging"]="false"

    init_backup_files
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
        log_verbose "User agreed to remove existing target"
        if ! rm -ri "$link_name"; then
            handle_error "Failed to remove $link_name"
        fi
        log_debug "Successfully removed existing target $link_name"
    fi

    log_debug "Backing up $source to $target"
    if ln -s "$target" "$link_name"; then
        log_success "Created symlink: $link_name -> $target"
    else
        handle_error "Failed to create symlink $link_name -> $target"
    fi
}

remove_symlink() {
    local link_name="$1"
    if [ -L "$link_name" ]; then
        log_debug "Removing symlink: $link_name"
        rm "$link_name" || handle_error "Failed to remove symlink: $link_name"
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
    log_info "Switching to npm environment..."
    log_debug "Entering switch_to_npm function"

    # First ensure we're in a normalized state
    local current_state="${ORIGINAL_STATE["project_state"]}"
    log_debug "Current state before switch: $current_state"

    # Remove any existing symlinks
    log_verbose "Removing any existing symlinks"
    remove_symlink "node_modules"
    remove_symlink "package.json"

    # Handle package.json
    if [ -f "package.json" ] && [ ! -L "package.json" ]; then
        # Regular package.json exists, save it as pnpm version
        log_debug "Saving regular package.json as pnpm version"
        if [ -s "package.json" ]; then
            # Only copy if file is not empty
            cp "package.json" "pnpm-package.json" || handle_error "Failed to save pnpm-package.json"
            rm "package.json" || handle_error "Failed to remove package.json"
        else
            # If empty, just remove it
            log_debug "Removing empty package.json"
            rm "package.json" || handle_error "Failed to remove empty package.json"
        fi
    fi

    # Create npm-package.json from source
    log_debug "Creating fresh npm-package.json"
    if [ -f "pnpm-package.json" ]; then
        log_debug "Creating npm-package.json from pnpm-package.json"
        cp "pnpm-package.json" "npm-package.json" || handle_error "Failed to create npm-package.json from pnpm-package.json"
    else
        handle_error "No package.json source found to create npm version"
    fi

    # Modify the npm version and create symlink
    modify_npm_package_json
    create_symlink "npm-package.json" "package.json"

    # Handle node_modules
    if [ -d "npm-node_modules" ]; then
        log_debug "Found npm-node_modules, creating symlink"
        create_symlink "npm-node_modules" "node_modules"
    elif [ -d "node_modules" ] && [ ! -L "node_modules" ]; then
        # If we have a regular node_modules directory, treat it as pnpm's
        log_debug "Found regular node_modules, treating as pnpm directory"
        mv "node_modules" "pnpm-node_modules" || handle_error "Failed to move node_modules to pnpm-node_modules"
        # Create empty npm-node_modules, npm install will populate it
        mkdir "npm-node_modules" || handle_error "Failed to create npm-node_modules"
        create_symlink "npm-node_modules" "node_modules"
    fi

    log_debug "Exiting switch_to_npm function"
    log_success "Successfully switched to npm environment"
}

switch_to_pnpm() {
    log "Switching back to pnpm environment..."
    log_debug "Entering switch_to_pnpm function"

    # First handle existing node_modules if it's a directory
    if [ -d "node_modules" ] && [ ! -L "node_modules" ]; then
        log_warning "node_modules exists as directory"
        # During package process, we know this is from npm install
        if [ "${ORIGINAL_STATE["is_packaging"]}" = "true" ]; then
            if [ -d "npm-node_modules" ]; then
                log_debug "npm-node_modules already exists, checking if we should update it"
                local npm_size pnpm_size
                npm_size=$(du -s "npm-node_modules" 2>/dev/null | cut -f1)
                pnpm_size=$(du -s "node_modules" 2>/dev/null | cut -f1)

                # If the new node_modules is significantly different in size, ask what to do
                if [ $((npm_size - pnpm_size)) -gt 1000 ] || [ $((pnpm_size - npm_size)) -gt 1000 ]; then
                    if ask_user "Existing npm-node_modules seems different. Replace it with new node_modules?" "n"; then
                        log_debug "Replacing npm-node_modules with new node_modules"
                        rm -rf "npm-node_modules"
                        mv "node_modules" "npm-node_modules" || handle_error "Failed to move node_modules to npm-node_modules"
                    else
                        log_debug "Keeping existing npm-node_modules, removing node_modules"
                        rm -rf "node_modules"
                    fi
                else
                    log_debug "Keeping existing npm-node_modules, removing node_modules"
                    rm -rf "node_modules"
                fi
            else
                log_debug "Moving node_modules to npm-node_modules"
                mv "node_modules" "npm-node_modules" || handle_error "Failed to move node_modules to npm-node_modules"
            fi
        else
            # In other cases, we still ask to be safe
            if [ ! -d "pnpm-node_modules" ]; then
                log_debug "Moving node_modules to pnpm-node_modules"
                mv "node_modules" "pnpm-node_modules" || handle_error "Failed to move node_modules to pnpm-node_modules"
            else
                if ask_user "node_modules exists but is not a symlink. Remove it?" "n"; then
                    rm -rf "node_modules" || handle_error "Failed to remove node_modules"
                else
                    handle_error "Cannot proceed with existing node_modules directory"
                fi
            fi
        fi
    fi

    # Remove any existing symlinks
    log_verbose "Removing any existing symlinks"
    remove_symlink "node_modules"
    remove_symlink "package.json"

    # Create symlinks to pnpm files
    if [ -d "pnpm-node_modules" ]; then
        log_debug "Creating symlink to pnpm-node_modules"
        create_symlink "pnpm-node_modules" "node_modules"
    else
        log_error "pnpm-node_modules not found!"
        handle_error "Cannot switch to pnpm environment"
    fi

    if [ -f "pnpm-package.json" ]; then
        log_debug "Creating symlink to pnpm-package.json"
        create_symlink "pnpm-package.json" "package.json"
    else
        log_error "pnpm-package.json not found!"
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

check_node_modules_status() {
    log_debug "Checking node_modules status:"
    if [ -L "node_modules" ]; then
        log_debug "node_modules is a symlink pointing to: $(readlink node_modules)"
    elif [ -d "node_modules" ]; then
        log_debug "node_modules is a regular directory"
    else
        log_debug "node_modules does not exist"
    fi
}

get_formatted_size() {
    local size_kb=$(du -sk "$1" 2>/dev/null | cut -f1)
    if [ -n "$size_kb" ]; then
        if [ "$size_kb" -gt 1048576 ]; then # > 1GB
            echo "$(echo "scale=1; $size_kb/1048576" | bc)G"
        elif [ "$size_kb" -gt 1024 ]; then # > 1MB
            echo "$(echo "scale=1; $size_kb/1024" | bc)M"
        else
            echo "${size_kb}K"
        fi
    else
        echo "unknown"
    fi
}

do_package() {
    log_debug "Starting package process"
    check_node_modules_status

    # Switch to npm environment
    switch_to_npm

    log_debug "After switch_to_npm:"
    check_node_modules_status

    # Run npm install and package
    log_info "Running npm install and package"
    npm install || handle_error "npm install failed"

    log_debug "After npm install:"
    check_node_modules_status

    # npm removes our symlink, so let's save the new modules and restore the symlink
    if [ -d "node_modules" ] && [ ! -L "node_modules" ]; then
        log_debug "npm replaced our symlink with a directory, saving changes"
        # Remove old npm-node_modules if it exists
        if [ -d "npm-node_modules" ]; then
            rm -rf "npm-node_modules"
        fi
        # Move the new node_modules to npm-node_modules
        mv "node_modules" "npm-node_modules"
        # Recreate the symlink
        create_symlink "npm-node_modules" "node_modules"
    fi

    npm run package || handle_error "npm run package failed"

    log_debug "After npm run package:"
    check_node_modules_status

    # Create VSIX package
    log_info "Creating VSIX package"
    vsce package || handle_error "vsce package failed"

    log_debug "After vsce package:"
    check_node_modules_status

    # Switch back to pnpm environment
    log_verbose "Step 3: Switching back to pnpm environment"
    switch_to_pnpm

    log_success "VSIX package created successfully"
    log_debug "VSIX package creation completed"
}

# Manual packaging commands
do_npm_install() {
    log_debug "Running npm install"
    check_node_modules_status

    # Run npm install
    log_info "Running npm install"
    npm install || handle_error "npm install failed"

    log_debug "After npm install:"
    check_node_modules_status

    # npm removes our symlink, so let's save the new modules and restore the symlink
    if [ -d "node_modules" ] && [ ! -L "node_modules" ]; then
        log_debug "npm replaced our symlink with a directory, saving changes"
        # Remove old npm-node_modules if it exists
        if [ -d "npm-node_modules" ]; then
            rm -rf "npm-node_modules"
        fi
        # Move the new node_modules to npm-node_modules
        mv "node_modules" "npm-node_modules"
        # Recreate the symlink
        create_symlink "npm-node_modules" "node_modules"
    fi

    log_success "npm install completed"
}

do_npm_compile() {
    log_debug "Running npm compile"
    npm run package || handle_error "npm run package failed"
    log_success "npm compile completed"
}

do_create_vsix() {
    log_debug "Creating VSIX package"
    vsce package || handle_error "vsce package failed"
    log_success "VSIX package created"
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
        echo "${BLUE}directory${NC} ($(get_formatted_size "$item"))"
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
    echo -e "  pnpm-node_modules:   $(get_file_type "pnpm-node_modules")"
    echo -e "  pnpm-package.json:   $(get_file_type "pnpm-package.json")"
    echo -e "  npm-node_modules:    $(get_file_type "npm-node_modules")"
    echo -e "  npm-package.json:    $(get_file_type "npm-package.json")"

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

    # Show VSIX package status
    echo -e "\n${BOLD}VSIX Package Status:${NC}"
    local vsix_file=$(ls *.vsix 2>/dev/null | head -n 1)
    if [ -n "$vsix_file" ]; then
        echo -e "  $vsix_file: $(get_formatted_size "$vsix_file")"
    else
        echo -e "  ${GRAY}No VSIX packages found${NC}"
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
        case "$1" in
        -v | --verbose)
            VERBOSE=true
            shift
            ;;
        -d | --debug)
            DEBUG=true
            VERBOSE=true
            shift
            ;;
        *)
            # Store the command
            if [ -z "$COMMAND" ]; then
                COMMAND="$1"
                shift
            else
                log_error "Unknown option: $1"
                usage
                exit 1
            fi
            ;;
        esac
    done

    # Execute the command
    case "${COMMAND:-help}" in
    "status")
        do_status
        ;;
    "package")
        do_package
        ;;
    "switch-to-npm")
        switch_to_npm
        ;;
    "switch-to-pnpm")
        switch_to_pnpm
        ;;
    "npm-install")
        do_npm_install
        ;;
    "npm-compile")
        do_npm_compile
        ;;
    "create-vsix")
        do_create_vsix
        ;;
    "help")
        usage
        ;;
    *)
        log_error "Unknown command: ${COMMAND:-none}"
        usage
        exit 1
        ;;
    esac
}

# Execute main function with all arguments
main "$@"
