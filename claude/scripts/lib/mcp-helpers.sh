#!/bin/bash

# =============================================================================
# MCP Helper Functions
# =============================================================================
# Common utilities for working with Model Context Protocol (MCP) tools.
# Provides error handling, retries, and response formatting.
#
# Author: Claude Code
# Version: 1.0.0
# =============================================================================

# Enable strict error handling
set -euo pipefail

# Source error handling and retry libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/jira-errors.sh"
source "${SCRIPT_DIR}/jira-retry.sh"

# =============================================================================
# Configuration
# =============================================================================

# MCP tool execution timeout (seconds)
MCP_TIMEOUT=30

# Log file for MCP operations (separate from error log)
MCP_LOG_FILE="${TMPDIR:-/tmp}/mcp-operations.log"

# =============================================================================
# Core MCP Functions
# =============================================================================

#' Invoke an MCP tool with advanced error handling and retries
#' Usage: invoke_mcp_tool TOOL_NAME PARAMS_JSON
#' Returns: Tool output on success
#' Example: invoke_mcp_tool "mcp__atlassian__getJiraIssue" '{"cloudId":"123","issueIdOrKey":"PROJ-1"}'
invoke_mcp_tool() {
    local tool_name="${1:-}"
    local params_json="${2:-{}}"
    
    if [[ -z "$tool_name" ]]; then
        echo "Error: Tool name is required" >&2
        return 1
    fi
    
    # Validate JSON parameters
    if ! echo "$params_json" | jq . >/dev/null 2>&1; then
        display_jira_error "MCP Tool Invocation" "$tool_name" "Invalid JSON parameters: $params_json" "false"
        return 1
    fi
    
    # Log the operation start
    log_mcp_operation "INFO" "$tool_name" "$params_json" "Starting MCP tool invocation"
    
    # Use the new retry system to execute the MCP call
    local result
    if result=$(retry_mcp_call "$tool_name" "$params_json" "mcp_$tool_name"); then
        log_mcp_operation "SUCCESS" "$tool_name" "$params_json" "MCP tool completed successfully"
        echo "$result"
        return 0
    else
        local exit_code=$?
        # Error handling is already done by retry_mcp_call
        return "$exit_code"
    fi
}


#' Log MCP operations to file
log_mcp_operation() {
    local level="$1"
    local tool="$2"
    local params="$3"
    local message="$4"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$MCP_LOG_FILE")"
    
    # Write log entry
    echo "[$timestamp] [$level] $tool: $message" >> "$MCP_LOG_FILE"
    
    # Also echo to stderr for debugging (only for errors)
    if [[ "$level" == "ERROR" ]]; then
        echo "[$timestamp] [$level] $tool: $message" >&2
    fi
}

# =============================================================================
# Response Processing Functions
# =============================================================================

#' Parse JSON response and extract specific field
#' Usage: extract_json_field JSON_STRING FIELD_PATH
#' Example: extract_json_field "$response" ".key"
extract_json_field() {
    local json_string="$1"
    local field_path="$2"
    
    if [[ -z "$json_string" || -z "$field_path" ]]; then
        echo "Error: JSON string and field path are required" >&2
        return 1
    fi
    
    echo "$json_string" | jq -r "$field_path // empty" 2>/dev/null || {
        echo "Error: Failed to extract field '$field_path' from JSON" >&2
        return 1
    }
}

#' Format JSON response for human-readable output
#' Usage: format_json_output JSON_STRING
format_json_output() {
    local json_string="$1"
    
    if [[ -z "$json_string" ]]; then
        echo "No data"
        return 0
    fi
    
    echo "$json_string" | jq . 2>/dev/null || {
        echo "Raw output: $json_string"
    }
}

#' Check if JSON response indicates success
#' Usage: is_json_success JSON_STRING
is_json_success() {
    local json_string="$1"
    
    # Check for common error indicators in JSON
    if echo "$json_string" | jq -e '.error // .errors // .errorMessages' >/dev/null 2>&1; then
        return 1
    fi
    
    # If we have valid JSON without error fields, consider it success
    if echo "$json_string" | jq . >/dev/null 2>&1; then
        return 0
    fi
    
    # If not valid JSON, check exit status from caller
    return 1
}

# =============================================================================
# Error Handling Functions
# =============================================================================

#' Handle MCP tool errors with appropriate user messaging (legacy wrapper)
#' Usage: handle_mcp_error OPERATION_NAME EXIT_CODE ERROR_MESSAGE
handle_mcp_error() {
    local operation="$1"
    local exit_code="$2"
    local error_message="$3"
    
    # Use the new comprehensive error display system
    display_jira_error "$operation" "mcp-tool" "$error_message" "true"
}

#' Display recent MCP operation logs
#' Usage: show_mcp_logs [NUM_LINES]
show_mcp_logs() {
    local num_lines="${1:-20}"
    
    if [[ -f "$MCP_LOG_FILE" ]]; then
        echo "Recent MCP operations:"
        tail -n "$num_lines" "$MCP_LOG_FILE"
    else
        echo "No MCP log file found at $MCP_LOG_FILE"
    fi
}

#' Clear MCP operation logs
clear_mcp_logs() {
    if [[ -f "$MCP_LOG_FILE" ]]; then
        > "$MCP_LOG_FILE"
        echo "MCP logs cleared"
    else
        echo "No MCP log file to clear"
    fi
}

# =============================================================================
# Utility Functions
# =============================================================================

#' Check if jq is available for JSON processing
check_json_support() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: jq is required for JSON processing but not found" >&2
        echo "Please install jq: https://jqlang.github.io/jq/download/" >&2
        return 1
    fi
    return 0
}

#' Validate that required environment is set up
validate_mcp_environment() {
    # Check for jq
    check_json_support || return 1
    
    # Check if MCP tools are available (this is a placeholder check)
    # In practice, you might want to test a simple MCP call
    
    return 0
}

# =============================================================================
# Integration Helper Functions
# =============================================================================

#' Enhanced wrapper for MCP calls with full error handling, retry, and degradation
#' Usage: invoke_mcp_with_fallback OPERATION_NAME TOOL_NAME PARAMS_JSON [FALLBACK_COMMAND] [FALLBACK_MESSAGE]
invoke_mcp_with_fallback() {
    local operation_name="${1:-unknown}"
    local tool_name="${2:-}"
    local params_json="${3:-{}}"
    local fallback_command="${4:-}"
    local fallback_message="${5:-Using simplified fallback}"
    
    if [[ -z "$tool_name" ]]; then
        display_jira_error "$operation_name" "mcp-wrapper" "Tool name is required" "false"
        return 1
    fi
    
    # Create primary command
    local primary_cmd="invoke_mcp_tool '$tool_name' '$params_json'"
    
    # Execute with graceful degradation
    if [[ -n "$fallback_command" ]]; then
        execute_with_degradation "$operation_name" "$primary_cmd" "$fallback_command" "$fallback_message"
    else
        execute_with_retry "$operation_name" bash -c "$primary_cmd"
    fi
}

#' Wrapper for common Jira operations with contextual error handling
#' Usage: execute_jira_operation OPERATION_TYPE TOOL_NAME PARAMS_JSON [CONTEXT_PARAMS...]
execute_jira_operation() {
    local operation_type="${1:-}"
    local tool_name="${2:-}"
    local params_json="${3:-}"
    shift 3 || true
    local context_params=("$@")
    
    if [[ -z "$operation_type" || -z "$tool_name" ]]; then
        echo "Error: Operation type and tool name are required" >&2
        return 1
    fi
    
    # Add context to error messages
    local enhanced_operation
    enhanced_operation=$(add_error_context "" "$operation_type" "${context_params[@]}")
    local operation_name="${operation_type}_operation"
    
    # Log operation start with context
    log_jira_error "INFO" "$operation_name" "$tool_name" "Starting $operation_type${enhanced_operation:+ with context: $enhanced_operation}"
    
    # Execute with retry and full error handling
    local result
    if result=$(invoke_mcp_tool "$tool_name" "$params_json"); then
        log_jira_error "INFO" "$operation_name" "$tool_name" "$operation_type completed successfully"
        echo "$result"
        return 0
    else
        local exit_code=$?
        # Enhanced error message with context
        local error_msg="$operation_type failed"
        if [[ -n "$enhanced_operation" ]]; then
            error_msg="$error_msg $enhanced_operation"
        fi
        
        display_jira_error "$operation_name" "$tool_name" "$error_msg" "true"
        return "$exit_code"
    fi
}

#' Batch execute multiple MCP operations with consistent error handling
#' Usage: batch_mcp_operations OPERATION_NAME "TOOL1:PARAMS1" "TOOL2:PARAMS2" ...
batch_mcp_operations() {
    local operation_name="${1:-batch_operation}"
    shift
    local operations=("$@")
    
    if [[ ${#operations[@]} -eq 0 ]]; then
        echo "Error: No operations provided for batch execution" >&2
        return 1
    fi
    
    local success_count=0
    local failure_count=0
    local results=()
    
    log_jira_error "INFO" "$operation_name" "batch-executor" "Starting batch execution of ${#operations[@]} operations"
    
    for operation in "${operations[@]}"; do
        if [[ "$operation" =~ ^([^:]+):(.+)$ ]]; then
            local tool_name="${BASH_REMATCH[1]}"
            local params_json="${BASH_REMATCH[2]}"
            
            echo "Executing: $tool_name..."
            if result=$(invoke_mcp_tool "$tool_name" "$params_json"); then
                results+=("SUCCESS:$tool_name:$result")
                success_count=$((success_count + 1))
                echo "✅ $tool_name completed"
            else
                results+=("FAILED:$tool_name:Operation failed")
                failure_count=$((failure_count + 1))
                echo "❌ $tool_name failed"
            fi
        else
            echo "⚠️  Invalid operation format: $operation (expected TOOL:PARAMS)"
            failure_count=$((failure_count + 1))
        fi
    done
    
    # Summary
    log_jira_error "INFO" "$operation_name" "batch-executor" "Batch completed: $success_count successes, $failure_count failures"
    echo ""
    echo "Batch Operation Summary:"
    echo "  Successful: $success_count"
    echo "  Failed: $failure_count"
    echo "  Total: ${#operations[@]}"
    
    # Return results
    printf '%s\n' "${results[@]}"
    
    # Return appropriate exit code
    if [[ $failure_count -eq 0 ]]; then
        return 0
    elif [[ $success_count -gt 0 ]]; then
        return 2  # Partial success
    else
        return 1  # Total failure
    fi
}

# =============================================================================
# Health Check and Diagnostics
# =============================================================================

#' Comprehensive health check for MCP integration
check_mcp_integration_health() {
    local issues=0
    
    echo "=== MCP Integration Health Check ==="
    echo ""
    
    # Check error handling system
    echo "Checking error handling system..."
    if check_error_system_health; then
        echo "✅ Error handling system is healthy"
    else
        echo "❌ Error handling system has issues"
        issues=$((issues + 1))
    fi
    echo ""
    
    # Check retry system
    echo "Checking retry system..."
    if [[ -f "$RETRY_STATS_FILE" ]]; then
        echo "✅ Retry statistics available"
        get_retry_stats | head -5
    else
        echo "ℹ️  No retry statistics available yet"
    fi
    echo ""
    
    # Check circuit breaker system
    echo "Checking circuit breaker system..."
    if [[ -f "$CIRCUIT_BREAKER_STATE_FILE" ]]; then
        echo "✅ Circuit breaker system active"
        show_circuit_breaker_status | head -5
    else
        echo "ℹ️  No circuit breaker state yet"
    fi
    echo ""
    
    # Check basic MCP environment
    echo "Checking MCP environment..."
    if validate_mcp_environment; then
        echo "✅ MCP environment is valid"
    else
        echo "❌ MCP environment validation failed"
        issues=$((issues + 1))
    fi
    echo ""
    
    # Summary
    if [[ $issues -eq 0 ]]; then
        echo "✅ MCP integration is healthy"
        return 0
    else
        echo "❌ Found $issues issues with MCP integration"
        echo "Run individual health checks for more details"
        return 1
    fi
}

# =============================================================================
# Initialization
# =============================================================================

# Validate environment on load
if ! validate_mcp_environment; then
    echo "MCP environment validation failed" >&2
    exit 1
fi

# Ensure log directory exists
mkdir -p "$(dirname "$MCP_LOG_FILE")"

# Export integration helper functions
export -f invoke_mcp_with_fallback
export -f execute_jira_operation
export -f batch_mcp_operations
export -f check_mcp_integration_health