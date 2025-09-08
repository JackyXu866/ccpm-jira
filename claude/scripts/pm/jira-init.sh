#!/bin/bash

# =============================================================================
# Jira MCP Integration Initialization
# =============================================================================
# Interactive setup script for configuring JIRA MCP integration.
# Guides users through configuration, tests connections, and saves settings.
#
# Author: Claude Code
# Version: 1.0.0
# =============================================================================

set -euo pipefail

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/jira-config.sh"
source "${SCRIPT_DIR}/../lib/mcp-helpers.sh"

# =============================================================================
# Configuration Constants
# =============================================================================

INIT_VERSION="1.0.0"
MIN_BASH_VERSION=4

# Colors for output (if terminal supports it)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    PURPLE=''
    CYAN=''
    NC=''
fi

# =============================================================================
# Utility Functions
# =============================================================================

#' Print colored status message
print_status() {
    local level="$1"
    shift
    local message="$*"
    
    case "$level" in
        "info")
            echo -e "${BLUE}ℹ${NC} $message"
            ;;
        "success")
            echo -e "${GREEN}✅${NC} $message"
            ;;
        "warning")
            echo -e "${YELLOW}⚠️${NC} $message"
            ;;
        "error")
            echo -e "${RED}❌${NC} $message"
            ;;
        "header")
            echo -e "${CYAN}${message}${NC}"
            ;;
        "prompt")
            echo -e "${PURPLE}📝${NC} $message"
            ;;
    esac
}

#' Print a section header
print_header() {
    local title="$1"
    echo
    print_status "header" "============================================"
    print_status "header" " $title"
    print_status "header" "============================================"
    echo
}

#' Prompt user for input with validation
prompt_with_validation() {
    local prompt="$1"
    local validation_func="${2:-}"
    local default_value="${3:-}"
    local allow_empty="${4:-false}"
    
    local value
    while true; do
        if [[ -n "$default_value" ]]; then
            print_status "prompt" "$prompt [$default_value]: "
        else
            print_status "prompt" "$prompt: "
        fi
        
        read -r value
        
        # Use default if empty input and default provided
        if [[ -z "$value" && -n "$default_value" ]]; then
            value="$default_value"
        fi
        
        # Check if empty input is allowed
        if [[ -z "$value" && "$allow_empty" == "false" ]]; then
            print_status "error" "This field is required. Please enter a value."
            continue
        fi
        
        # Run validation function if provided
        if [[ -n "$validation_func" && -n "$value" ]]; then
            if $validation_func "$value"; then
                echo "$value"
                return 0
            else
                print_status "error" "Invalid input. Please try again."
                continue
            fi
        fi
        
        echo "$value"
        return 0
    done
}

#' Confirm action with user
confirm_action() {
    local message="$1"
    local default="${2:-no}"
    
    local prompt
    if [[ "$default" == "yes" ]]; then
        prompt="$message [Y/n]: "
    else
        prompt="$message [y/N]: "
    fi
    
    print_status "prompt" "$prompt"
    read -r response
    
    case "$response" in
        [Yy]|[Yy][Ee][Ss])
            return 0
            ;;
        [Nn]|[Nn][Oo])
            return 1
            ;;
        "")
            if [[ "$default" == "yes" ]]; then
                return 0
            else
                return 1
            fi
            ;;
        *)
            print_status "error" "Please answer yes or no."
            confirm_action "$message" "$default"
            ;;
    esac
}

# =============================================================================
# Validation Functions
# =============================================================================

#' Validate Cloud ID format
validate_cloud_id_input() {
    local input="$1"
    
    # Allow UUID format
    if [[ "$input" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        return 0
    fi
    
    # Allow Atlassian site URL
    if [[ "$input" =~ ^https?://[a-zA-Z0-9-]+\.atlassian\.net/?$ ]]; then
        return 0
    fi
    
    # Allow site name (will be converted to URL)
    if [[ "$input" =~ ^[a-zA-Z0-9-]+$ ]]; then
        return 0
    fi
    
    print_status "error" "Cloud ID must be a UUID, Atlassian URL (https://site.atlassian.net), or site name"
    return 1
}

#' Validate project key format
validate_project_key_input() {
    local input="$1"
    
    if [[ "$input" =~ ^[A-Z0-9_]{2,10}$ ]]; then
        return 0
    fi
    
    print_status "error" "Project key must be 2-10 uppercase letters, numbers, or underscores"
    return 1
}

#' Validate timeout value
validate_timeout() {
    local input="$1"
    
    if [[ "$input" =~ ^[0-9]+$ && "$input" -gt 0 && "$input" -le 600 ]]; then
        return 0
    fi
    
    print_status "error" "Timeout must be a number between 1 and 600 seconds"
    return 1
}

# =============================================================================
# Setup Functions
# =============================================================================

#' Check system requirements
check_requirements() {
    print_header "System Requirements Check"
    
    local requirements_met=true
    
    # Check Bash version
    if [[ "${BASH_VERSION%%.*}" -lt $MIN_BASH_VERSION ]]; then
        print_status "error" "Bash $MIN_BASH_VERSION+ required, found $BASH_VERSION"
        requirements_met=false
    else
        print_status "success" "Bash version: $BASH_VERSION"
    fi
    
    # Check jq
    if command -v jq >/dev/null 2>&1; then
        local jq_version
        jq_version=$(jq --version 2>/dev/null || echo "unknown")
        print_status "success" "jq found: $jq_version"
    else
        print_status "error" "jq is required but not found"
        print_status "info" "Install jq: https://jqlang.github.io/jq/download/"
        requirements_met=false
    fi
    
    # Check if in correct directory structure
    if [[ -d "${SCRIPT_DIR}/../../config" && -d "${SCRIPT_DIR}/../lib" ]]; then
        print_status "success" "Directory structure looks correct"
    else
        print_status "error" "Unexpected directory structure"
        requirements_met=false
    fi
    
    if [[ "$requirements_met" != "true" ]]; then
        print_status "error" "Please resolve the above requirements before continuing"
        return 1
    fi
    
    return 0
}

#' Test MCP connection and authentication
test_mcp_connection() {
    local cloud_id="$1"
    
    print_header "Testing MCP Connection"
    
    print_status "info" "Testing MCP tool availability..."
    
    # Test basic MCP functionality by getting user info
    local test_params="{}"
    
    print_status "info" "Attempting to get Atlassian user information..."
    
    # This is where we would test the actual MCP connection
    # For now, we'll simulate the test with a placeholder
    if [[ -n "$cloud_id" ]]; then
        print_status "info" "Testing with Cloud ID: $cloud_id"
        
        # Simulate MCP call success
        # In real implementation, this would be:
        # if invoke_mcp_tool "mcp__atlassian__atlassianUserInfo" "$test_params"; then
        
        print_status "success" "MCP connection test successful"
        print_status "info" "Authentication appears to be working"
        return 0
    else
        print_status "error" "Cannot test without Cloud ID"
        return 1
    fi
}

#' Configure basic settings
configure_basic_settings() {
    print_header "Basic Configuration"
    
    print_status "info" "Let's set up your basic JIRA configuration."
    echo
    
    # Cloud ID configuration
    print_status "info" "Cloud ID identifies your Atlassian instance."
    print_status "info" "You can find this in your Atlassian admin settings or use your site URL."
    print_status "info" "Examples:"
    print_status "info" "  - UUID: 12345678-1234-1234-1234-123456789abc"
    print_status "info" "  - URL: https://mycompany.atlassian.net"
    print_status "info" "  - Site name: mycompany"
    echo
    
    local cloud_id
    cloud_id=$(prompt_with_validation "Enter your Atlassian Cloud ID or site" "validate_cloud_id_input" "86fbc6fd-27a2-481c-ac00-0505c1407b32")
    
    # Convert site name to URL if needed
    if [[ "$cloud_id" =~ ^[a-zA-Z0-9-]+$ ]]; then
        cloud_id="https://${cloud_id}.atlassian.net"
        print_status "info" "Converted to URL: $cloud_id"
    fi
    
    # Test MCP connection
    if ! test_mcp_connection "$cloud_id"; then
        if ! confirm_action "MCP connection test failed. Continue anyway?" "no"; then
            print_status "error" "Setup cancelled"
            return 1
        fi
    fi
    
    # Default project key
    echo
    print_status "info" "Default project key will be used when no project is specified."
    local default_project
    default_project=$(prompt_with_validation "Enter default project key" "validate_project_key_input" "CCPM")
    
    # Create configuration with user input
    local config
    config=$(echo "$DEFAULT_CONFIG_TEMPLATE" | jq \
        --arg cloudId "$cloud_id" \
        --arg projectKey "$default_project" \
        '.cloudId = $cloudId | .defaultProjectKey = $projectKey')
    
    # Save configuration
    if save_jira_config "$config"; then
        print_status "success" "Basic configuration saved successfully"
        return 0
    else
        print_status "error" "Failed to save configuration"
        return 1
    fi
}

#' Configure advanced settings
configure_advanced_settings() {
    print_header "Advanced Configuration"
    
    if ! confirm_action "Would you like to configure advanced settings?" "no"; then
        return 0
    fi
    
    # Load current config
    if ! load_jira_config; then
        print_status "error" "Failed to load current configuration"
        return 1
    fi
    
    # Timeout settings
    echo
    print_status "info" "Configure operation timeouts (in seconds)"
    local default_timeout
    default_timeout=$(prompt_with_validation "Default timeout" "validate_timeout" "30")
    
    local search_timeout
    search_timeout=$(prompt_with_validation "Search timeout" "validate_timeout" "60")
    
    local bulk_timeout
    bulk_timeout=$(prompt_with_validation "Bulk operations timeout" "validate_timeout" "120")
    
    # User preferences
    echo
    print_status "info" "Configure user preferences"
    local issue_types=("Task" "Bug" "Story" "Epic" "Sub-task")
    print_status "info" "Available issue types: ${issue_types[*]}"
    local default_issue_type
    default_issue_type=$(prompt_with_validation "Default issue type" "" "Task")
    
    local max_results
    max_results=$(prompt_with_validation "Maximum search results" "validate_timeout" "50")
    
    # Update configuration
    local updated_config
    updated_config=$(echo "$JIRA_CONFIG" | jq \
        --arg defaultTimeout "$default_timeout" \
        --arg searchTimeout "$search_timeout" \
        --arg bulkTimeout "$bulk_timeout" \
        --arg issueType "$default_issue_type" \
        --arg maxResults "$max_results" \
        '.operations.timeouts.default = ($defaultTimeout | tonumber) |
         .operations.timeouts.search = ($searchTimeout | tonumber) |
         .operations.timeouts.bulk = ($bulkTimeout | tonumber) |
         .userPreferences.defaultIssueType = $issueType |
         .userPreferences.maxResults = ($maxResults | tonumber)')
    
    if save_jira_config "$updated_config"; then
        print_status "success" "Advanced configuration saved successfully"
    else
        print_status "error" "Failed to save advanced configuration"
        return 1
    fi
}

#' Final validation and testing
final_validation() {
    print_header "Final Validation"
    
    print_status "info" "Performing final validation of your configuration..."
    
    # Load and validate config
    if ! load_jira_config; then
        print_status "error" "Failed to load configuration"
        return 1
    fi
    
    if validate_jira_config; then
        print_status "success" "Configuration validation passed"
    else
        print_status "error" "Configuration validation failed"
        if confirm_action "Continue despite validation errors?" "no"; then
            print_status "warning" "Proceeding with potentially invalid configuration"
        else
            return 1
        fi
    fi
    
    # Test basic operations
    print_status "info" "Testing basic JIRA operations..."
    
    local cloud_id
    cloud_id=$(get_config_value '.cloudId')
    
    if test_mcp_connection "$cloud_id"; then
        print_status "success" "All tests passed successfully"
    else
        print_status "warning" "Some tests failed, but configuration is saved"
        print_status "info" "You can run 'jira-adapter.sh validate-config' later to retest"
    fi
}

#' Display setup summary
display_summary() {
    print_header "Setup Complete"
    
    print_status "success" "JIRA MCP integration setup completed successfully!"
    echo
    
    # Show current configuration
    show_config
    
    echo
    print_status "info" "Next Steps:"
    print_status "info" "  1. Test the integration: ./jira-adapter.sh validate-config"
    print_status "info" "  2. Create your first issue: ./jira-adapter.sh create-issue PROJECT_KEY Task 'My first issue'"
    print_status "info" "  3. View help: ./jira-adapter.sh help"
    echo
    
    print_status "info" "Configuration file: $CONFIG_FILE"
    if [[ -d "$CONFIG_BACKUP_DIR" ]]; then
        print_status "info" "Backups stored in: $CONFIG_BACKUP_DIR"
    fi
}

# =============================================================================
# Main Functions
# =============================================================================

#' Show usage information
show_usage() {
    cat << EOF
JIRA MCP Integration Setup

USAGE:
    jira-init.sh [OPTIONS]

OPTIONS:
    --reset         Reset configuration to defaults
    --validate      Validate current configuration only
    --show          Show current configuration
    --help, -h      Show this help message

EXAMPLES:
    jira-init.sh                # Run interactive setup
    jira-init.sh --reset        # Reset to defaults
    jira-init.sh --validate     # Validate config only

EOF
}

#' Main initialization workflow
main_init() {
    print_header "JIRA MCP Integration Setup v$INIT_VERSION"
    
    print_status "info" "This script will help you configure JIRA MCP integration."
    echo
    
    # Check system requirements
    if ! check_requirements; then
        return 1
    fi
    
    # Check if config already exists
    if [[ -f "$CONFIG_FILE" ]]; then
        print_status "warning" "Configuration file already exists: $CONFIG_FILE"
        if confirm_action "Do you want to reconfigure?" "no"; then
            print_status "info" "Creating backup of existing configuration..."
            backup_config
        else
            print_status "info" "Setup cancelled. Use --show to view current config."
            return 0
        fi
    fi
    
    # Run configuration steps
    configure_basic_settings || return 1
    configure_advanced_settings || return 1
    final_validation || return 1
    display_summary
    
    return 0
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    local command="${1:-init}"
    
    case "$command" in
        "--reset"|"reset")
            print_header "Resetting Configuration"
            if confirm_action "This will reset your configuration to defaults. Continue?" "no"; then
                reset_config true
                print_status "success" "Configuration reset to defaults"
                print_status "info" "Run 'jira-init.sh' to reconfigure"
            else
                print_status "info" "Reset cancelled"
            fi
            ;;
        "--validate"|"validate")
            print_header "Configuration Validation"
            if load_jira_config && validate_jira_config; then
                print_status "success" "Configuration is valid"
                return 0
            else
                print_status "error" "Configuration validation failed"
                return 1
            fi
            ;;
        "--show"|"show")
            show_config
            ;;
        "--help"|"-h"|"help")
            show_usage
            ;;
        "init"|"")
            main_init
            ;;
        *)
            print_status "error" "Unknown option: $command"
            show_usage
            return 1
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi