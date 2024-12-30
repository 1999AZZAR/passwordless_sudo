#!/bin/bash

# configure-passwordless-sudo.sh
# Script to safely configure passwordless sudo access for the current user or specified user

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${2:-$GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
    if [ -n "$LOG_FILE" ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    fi
}

# Error handling function
error_exit() {
    log "ERROR: $1" "$RED" >&2
    exit 1
}

# Check if script is run with root privileges
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error_exit "This script must be run as root or with sudo"
    fi
}

# Get the real username when script is run with sudo
get_real_user() {
    if [ -n "$SUDO_USER" ]; then
        echo "$SUDO_USER"
    else
        whoami
    fi
}

# Validate username
validate_username() {
    local username=$1
    if ! id "$username" >/dev/null 2>&1; then
        error_exit "User $username does not exist"
    fi
}

# Check if user already has passwordless sudo
check_existing_config() {
    local username=$1
    if grep -r "^$username.*NOPASSWD: ALL" /etc/sudoers /etc/sudoers.d/ >/dev/null 2>&1; then
        log "User $username already has passwordless sudo configured" "$YELLOW"
        read -p "Do you want to continue and update the configuration? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi
}

# Backup existing configuration
backup_config() {
    local backup_dir="/root/sudo_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    cp -r /etc/sudoers "$backup_dir/"
    cp -r /etc/sudoers.d "$backup_dir/"
    log "Backup created in $backup_dir"
}

# Configure passwordless sudo
configure_sudo() {
    local username=$1
    local sudoers_file="/etc/sudoers.d/nopasswd-$username"
    local temp_file=$(mktemp)

    # Create configuration
    cat > "$temp_file" << EOF
# Passwordless sudo configuration for $username
# Created on $(date)
$username ALL=(ALL) NOPASSWD: ALL

# Security settings
Defaults:$username timestamp_timeout=30
Defaults:$username logfile="/var/log/sudo_$username.log"
EOF

    # Check syntax
    visudo -c -f "$temp_file" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        rm "$temp_file"
        error_exit "Invalid sudoers syntax"
    fi

    # Move file to proper location
    mv "$temp_file" "$sudoers_file"
    chmod 440 "$sudoers_file"
    chown root:root "$sudoers_file"

    log "Passwordless sudo configured for user $username"
}

# Test the configuration
test_configuration() {
    local username=$1
    log "Testing sudo configuration..." "$YELLOW"

    # Test as the specified user
    su - "$username" -c "sudo -n true" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        log "Configuration test successful"
    else
        error_exit "Configuration test failed"
    fi
}

# Print usage
print_usage() {
    echo "Usage: $0 [username]"
    echo "If username is not provided, configures passwordless sudo for the current user"
}

# Main script
main() {
    # Initialize logging
    LOG_FILE="/var/log/passwordless_sudo_setup.log"
    touch "$LOG_FILE" || error_exit "Cannot create log file"

    log "Starting passwordless sudo configuration script"

    # Check if help is requested
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        print_usage
        exit 0
    fi

    # Get username (either from parameter or current user)
    local username
    if [ -n "$1" ]; then
        username="$1"
    else
        username=$(get_real_user)
    fi

    log "Configuring passwordless sudo for user: $username"

    # Run checks
    check_root
    validate_username "$username"
    check_existing_config "$username"

    # Create backup
    backup_config

    # Configure and test
    configure_sudo "$username"
    test_configuration "$username"

    log "Configuration completed successfully"
    log "Logs available at: $LOG_FILE"
}

# Run main function with all arguments
main "$@"
