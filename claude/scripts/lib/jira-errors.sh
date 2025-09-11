#!/bin/bash

# =============================================================================
# Jira MCP Error Handling Library
# =============================================================================
# Comprehensive error handling for Jira MCP operations including error code
# mapping, categorization, logging, and recovery suggestions.
#
# Author: Claude Code
# Version: 1.0.0
# =============================================================================

# Prevent multiple sourcing
if [ -n "${JIRA_ERRORS_SOURCED:-}" ]; then
    return 0
fi
export JIRA_ERRORS_SOURCED=1

# Enable strict error handling
set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

# Error log file
JIRA_ERROR_LOG="${TMPDIR:-/tmp}/jira-errors.log"

# Maximum log file size (in lines)
MAX_LOG_LINES=1000

# Error categories
readonly ERROR_CATEGORY_TRANSIENT="transient"
readonly ERROR_CATEGORY_PERMANENT="permanent"
readonly ERROR_CATEGORY_CONFIG="configuration"
readonly ERROR_CATEGORY_PERMISSION="permission"
readonly ERROR_CATEGORY_NETWORK="network"

# =============================================================================
# Error Code Mappings
# =============================================================================

#' Map HTTP status codes to user-friendly messages and categories
#' Usage: map_http_error HTTP_CODE
map_http_error() {
    local http_code="${1:-}"
    local category=""
    local message=""
    local suggestions=""
    
    case "$http_code" in
        400)
            category="$ERROR_CATEGORY_PERMANENT"
            message="Bad Request - Invalid parameters or request format"
            suggestions="Check your input parameters and ensure they match the required format"
            ;;
        401)
            category="$ERROR_CATEGORY_CONFIG"
            message="Unauthorized - Authentication failed"
            suggestions="Verify your Atlassian credentials and run 'jira-init.sh' to reconfigure authentication"
            ;;
        403)
            category="$ERROR_CATEGORY_PERMISSION"
            message="Forbidden - Insufficient permissions"
            suggestions="Contact your Jira administrator to request appropriate permissions for this operation"
            ;;
        404)
            category="$ERROR_CATEGORY_PERMANENT"
            message="Not Found - Resource does not exist"
            suggestions="Check the issue key, project key, or resource ID and verify it exists in your Jira instance"
            ;;
        409)
            category="$ERROR_CATEGORY_PERMANENT"
            message="Conflict - Resource state conflict"
            suggestions="The resource may have been modified by another user. Refresh and try again"
            ;;
        429)
            category="$ERROR_CATEGORY_TRANSIENT"
            message="Rate Limited - Too many requests"
            suggestions="Wait before retrying. Consider reducing the frequency of your requests"
            ;;
        500)
            category="$ERROR_CATEGORY_TRANSIENT"
            message="Internal Server Error - Jira server error"
            suggestions="This is a temporary server issue. Try again in a few minutes"
            ;;
        502)
            category="$ERROR_CATEGORY_TRANSIENT"
            message="Bad Gateway - Network infrastructure issue"
            suggestions="Check your internet connection and try again"
            ;;
        503)
            category="$ERROR_CATEGORY_TRANSIENT"
            message="Service Unavailable - Jira temporarily unavailable"
            suggestions="Jira may be under maintenance. Check Atlassian Status page and try again later"
            ;;
        504)
            category="$ERROR_CATEGORY_TRANSIENT"
            message="Gateway Timeout - Request timeout"
            suggestions="The request took too long. Try again or contact your administrator if the issue persists"
            ;;
        *)
            category="$ERROR_CATEGORY_PERMANENT"
            message="HTTP Error $http_code"
            suggestions="Check the Atlassian API documentation for details about this error code"
            ;;
    esac
    
    echo "$category|$message|$suggestions"
}

#' Map MCP tool errors to user-friendly messages
#' Usage: map_mcp_error TOOL_NAME ERROR_MESSAGE
map_mcp_error() {
    local tool_name="${1:-unknown}"
    local error_message="${2:-}"
    local category=""
    local message=""
    local suggestions=""
    
    # Extract HTTP status code if present
    local http_code=""
    if [[ "$error_message" =~ ([0-9]{3}) ]]; then
        http_code="${BASH_REMATCH[1]}"
    fi
    
    # Map based on error message patterns
    if [[ -n "$http_code" ]]; then
        map_http_error "$http_code"
        return 0
    elif echo "$error_message" | grep -iq "timeout\|timed out"; then
        category="$ERROR_CATEGORY_TRANSIENT"
        message="Operation timed out"
        suggestions="Check your internet connection and try again. If the issue persists, the Jira server may be slow"
    elif echo "$error_message" | grep -iq "connection\|network\|unreachable"; then
        category="$ERROR_CATEGORY_NETWORK"
        message="Network connection error"
        suggestions="Check your internet connection and firewall settings. Verify Jira server URL is accessible"
    elif echo "$error_message" | grep -iq "authentication\|unauthorized\|credential"; then
        category="$ERROR_CATEGORY_CONFIG"
        message="Authentication failed"
        suggestions="Run 'jira-init.sh' to reconfigure your Atlassian credentials"
    elif echo "$error_message" | grep -iq "cloud.*id\|cloudid"; then
        category="$ERROR_CATEGORY_CONFIG"
        message="Invalid Cloud ID configuration"
        suggestions="Update your Cloud ID in the configuration file or run 'jira-init.sh' to set it up"
    elif echo "$error_message" | grep -iq "project.*not.*found\|invalid.*project"; then
        category="$ERROR_CATEGORY_CONFIG"
        message="Project not found or inaccessible"
        suggestions="Verify the project key exists and you have access to it. Use 'get-projects' to list available projects"
    elif echo "$error_message" | grep -iq "issue.*type\|issuetype"; then
        category="$ERROR_CATEGORY_CONFIG"
        message="Invalid issue type"
        suggestions="Check available issue types for your project using the MCP tools or Jira web interface"
    elif echo "$error_message" | grep -iq "transition\|workflow"; then
        category="$ERROR_CATEGORY_CONFIG"
        message="Invalid workflow transition"
        suggestions="Check available transitions for the issue using 'get-transitions' command"
    elif echo "$error_message" | grep -iq "json\|parse\|format"; then
        category="$ERROR_CATEGORY_PERMANENT"
        message="Data format error"
        suggestions="Check that all parameters are properly formatted and valid JSON where required"
    elif echo "$error_message" | grep -iq "rate.limit\|too.many"; then
        category="$ERROR_CATEGORY_TRANSIENT"
        message="Rate limit exceeded"
        suggestions="Wait before retrying. Consider implementing delays between requests"
    else
        category="$ERROR_CATEGORY_PERMANENT"
        message="Unknown error in $tool_name"
        suggestions="Check the full error message and Atlassian documentation for details"
    fi
    
    echo "$category|$message|$suggestions"
}

# =============================================================================
# Error Classification Functions
# =============================================================================

#' Determine if an error is transient (retryable)
#' Usage: is_transient_error CATEGORY
is_transient_error() {
    local category="${1:-}"
    case "$category" in
        "$ERROR_CATEGORY_TRANSIENT"|"$ERROR_CATEGORY_NETWORK")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

#' Determine if an error requires configuration changes
#' Usage: is_config_error CATEGORY
is_config_error() {
    local category="${1:-}"
    case "$category" in
        "$ERROR_CATEGORY_CONFIG")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

#' Determine if an error is permission-related
#' Usage: is_permission_error CATEGORY
is_permission_error() {
    local category="${1:-}"
    case "$category" in
        "$ERROR_CATEGORY_PERMISSION")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# =============================================================================
# Error Logging Functions
# =============================================================================

#' Log error with structured format
#' Usage: log_jira_error LEVEL OPERATION TOOL_NAME ERROR_MESSAGE [CONTEXT]
log_jira_error() {
    local level="${1:-ERROR}"
    local operation="${2:-unknown}"
    local tool_name="${3:-unknown}"
    local error_message="${4:-}"
    local context="${5:-}"
    
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$JIRA_ERROR_LOG")"
    
    # Create structured log entry
    local log_entry="[$timestamp] [$level] [$operation] $tool_name"
    if [[ -n "$context" ]]; then
        log_entry="$log_entry [$context]"
    fi
    log_entry="$log_entry: $error_message"
    
    # Write to log file
    echo "$log_entry" >> "$JIRA_ERROR_LOG"
    
    # Rotate log if it gets too large
    rotate_log_if_needed
}

#' Rotate error log if it exceeds maximum size
rotate_log_if_needed() {
    if [[ -f "$JIRA_ERROR_LOG" ]]; then
        local line_count
        line_count=$(wc -l < "$JIRA_ERROR_LOG" 2>/dev/null || echo "0")
        
        if [[ "$line_count" -gt "$MAX_LOG_LINES" ]]; then
            # Keep the last half of the log
            local keep_lines=$((MAX_LOG_LINES / 2))
            local temp_log
            temp_log=$(mktemp)
            
            tail -n "$keep_lines" "$JIRA_ERROR_LOG" > "$temp_log"
            mv "$temp_log" "$JIRA_ERROR_LOG"
            
            # Log the rotation
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] [log-rotation] Log rotated, kept last $keep_lines entries" >> "$JIRA_ERROR_LOG"
        fi
    fi
}

#' Display recent error logs
#' Usage: show_jira_error_logs [NUM_LINES]
show_jira_error_logs() {
    local num_lines="${1:-20}"
    
    if [[ -f "$JIRA_ERROR_LOG" ]]; then
        echo "Recent Jira errors (last $num_lines entries):"
        echo "================================================"
        tail -n "$num_lines" "$JIRA_ERROR_LOG" | while IFS= read -r line; do
            # Color-code log levels
            if echo "$line" | grep -q "\[ERROR\]"; then
                echo -e "\033[31m$line\033[0m"  # Red
            elif echo "$line" | grep -q "\[WARN\]"; then
                echo -e "\033[33m$line\033[0m"  # Yellow
            else
                echo "$line"
            fi
        done
        echo "================================================"
        echo "Full log available at: $JIRA_ERROR_LOG"
    else
        echo "No error log found at $JIRA_ERROR_LOG"
    fi
}

#' Clear error log
clear_jira_error_log() {
    if [[ -f "$JIRA_ERROR_LOG" ]]; then
        > "$JIRA_ERROR_LOG"
        echo "Jira error log cleared"
    else
        echo "No error log to clear"
    fi
}

# =============================================================================
# User-Friendly Error Display Functions
# =============================================================================

#' Display a formatted error message to the user
#' Usage: display_jira_error OPERATION TOOL_NAME ERROR_MESSAGE [INTERACTIVE]
display_jira_error() {
    local operation="${1:-unknown operation}"
    local tool_name="${2:-unknown tool}"
    local error_message="${3:-}"
    local interactive="${4:-true}"
    
    # Map the error to get category and suggestions
    local error_info
    error_info=$(map_mcp_error "$tool_name" "$error_message")
    
    local category
    category=$(echo "$error_info" | cut -d'|' -f1)
    local user_message
    user_message=$(echo "$error_info" | cut -d'|' -f2)
    local suggestions
    suggestions=$(echo "$error_info" | cut -d'|' -f3)
    
    # Display error with appropriate formatting
    echo "" >&2
    echo "❌ $operation failed" >&2
    echo "   $user_message" >&2
    echo "" >&2
    
    # Show suggestions based on error category
    if [[ -n "$suggestions" ]]; then
        echo "💡 Suggestions:" >&2
        echo "   $suggestions" >&2
        echo "" >&2
    fi
    
    # Show category-specific help
    if is_config_error "$category"; then
        echo "🔧 Configuration Issue:" >&2
        echo "   This error typically requires updating your Jira configuration." >&2
        echo "   Run 'jira-init.sh' to reconfigure your settings." >&2
        echo "" >&2
    elif is_permission_error "$category"; then
        echo "🔒 Permission Issue:" >&2
        echo "   You may need additional permissions in Jira." >&2
        echo "   Contact your Jira administrator for assistance." >&2
        echo "" >&2
    elif is_transient_error "$category"; then
        echo "⏳ Temporary Issue:" >&2
        echo "   This error may resolve itself if you try again." >&2
        echo "   The system will automatically retry transient errors." >&2
        echo "" >&2
    fi
    
    # Show log location for debugging
    echo "📋 For detailed error information, check the log file:" >&2
    echo "   $JIRA_ERROR_LOG" >&2
    echo "" >&2
    
    # Interactive error handling options
    if [[ "$interactive" == "true" && -t 0 ]]; then
        show_error_recovery_options "$category" "$operation"
    fi
    
    # Log the error
    log_jira_error "ERROR" "$operation" "$tool_name" "$error_message"
}

#' Show interactive error recovery options
#' Usage: show_error_recovery_options CATEGORY OPERATION
show_error_recovery_options() {
    local category="${1:-}"
    local operation="${2:-}"
    
    echo "🛠️  Recovery Options:" >&2
    echo "   1) View recent error logs" >&2
    
    if is_config_error "$category"; then
        echo "   2) Run Jira initialization" >&2
        echo "   3) Validate configuration" >&2
    elif is_transient_error "$category"; then
        echo "   2) Retry the operation" >&2
        echo "   3) Check system status" >&2
    else
        echo "   2) Get help with this error" >&2
        echo "   3) Report an issue" >&2
    fi
    
    echo "   4) Continue without this operation" >&2
    echo "" >&2
    
    read -p "Select an option (1-4, or Enter to continue): " choice
    case "$choice" in
        1)
            show_jira_error_logs 10
            ;;
        2)
            if is_config_error "$category"; then
                echo "Run: jira-init.sh"
            elif is_transient_error "$category"; then
                echo "You can retry the operation that failed"
            else
                echo "Check the Atlassian documentation or community forums for help"
            fi
            ;;
        3)
            if is_config_error "$category"; then
                echo "Run: jira-adapter.sh validate-config"
            elif is_transient_error "$category"; then
                echo "Check https://status.atlassian.com/ for service status"
            else
                echo "Consider opening an issue in the project repository"
            fi
            ;;
        4|"")
            echo "Continuing..."
            ;;
        *)
            echo "Invalid option selected"
            ;;
    esac
    
    echo "" >&2
}

# =============================================================================
# Error Context Functions
# =============================================================================

#' Add contextual information to error messages
#' Usage: add_error_context ERROR_MESSAGE OPERATION [PARAMETERS...]
add_error_context() {
    local error_message="${1:-}"
    local operation="${2:-}"
    shift 2 || true
    local parameters=("$@")
    
    local context=""
    
    case "$operation" in
        "create_jira_issue")
            if [[ ${#parameters[@]} -gt 0 ]]; then
                context="Project: ${parameters[0]:-unknown}"
                if [[ ${#parameters[@]} -gt 1 ]]; then
                    context="$context, Type: ${parameters[1]:-unknown}"
                fi
            fi
            ;;
        "get_jira_issue"|"update_jira_issue"|"transition_jira_issue")
            if [[ ${#parameters[@]} -gt 0 ]]; then
                context="Issue: ${parameters[0]:-unknown}"
            fi
            ;;
        "search_jira_issues")
            if [[ ${#parameters[@]} -gt 0 ]]; then
                context="JQL: ${parameters[0]:-unknown}"
            fi
            ;;
        *)
            if [[ ${#parameters[@]} -gt 0 ]]; then
                context="Params: ${parameters[*]}"
            fi
            ;;
    esac
    
    if [[ -n "$context" ]]; then
        echo "$error_message [$context]"
    else
        echo "$error_message"
    fi
}

# =============================================================================
# Health Check Functions
# =============================================================================

#' Check if error logging system is healthy
check_error_system_health() {
    local issues=0
    
    echo "Checking Jira error handling system..."
    
    # Check log directory
    local log_dir
    log_dir=$(dirname "$JIRA_ERROR_LOG")
    if [[ ! -w "$log_dir" ]]; then
        echo "❌ Cannot write to log directory: $log_dir"
        issues=$((issues + 1))
    else
        echo "✅ Log directory is writable"
    fi
    
    # Check log file
    if [[ -f "$JIRA_ERROR_LOG" ]]; then
        if [[ ! -w "$JIRA_ERROR_LOG" ]]; then
            echo "❌ Cannot write to log file: $JIRA_ERROR_LOG"
            issues=$((issues + 1))
        else
            echo "✅ Log file is writable"
        fi
        
        # Check log file size
        local log_size
        log_size=$(stat -f%z "$JIRA_ERROR_LOG" 2>/dev/null || stat -c%s "$JIRA_ERROR_LOG" 2>/dev/null || echo "0")
        local log_size_mb=$((log_size / 1024 / 1024))
        
        if [[ $log_size_mb -gt 10 ]]; then
            echo "⚠️  Log file is large (${log_size_mb}MB). Consider rotating: $JIRA_ERROR_LOG"
        else
            echo "✅ Log file size is reasonable (${log_size_mb}MB)"
        fi
    else
        echo "ℹ️  No log file exists yet (will be created when needed)"
    fi
    
    if [[ $issues -eq 0 ]]; then
        echo "✅ Error handling system is healthy"
        return 0
    else
        echo "❌ Found $issues issues with error handling system"
        return 1
    fi
}

# =============================================================================
# Initialization
# =============================================================================

# Create log directory on load
mkdir -p "$(dirname "$JIRA_ERROR_LOG")"

# Export key functions for use by other modules
export -f map_http_error
export -f map_mcp_error
export -f is_transient_error
export -f is_config_error
export -f is_permission_error
export -f log_jira_error
export -f display_jira_error
export -f add_error_context