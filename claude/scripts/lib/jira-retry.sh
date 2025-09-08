#!/bin/bash

# =============================================================================
# Jira MCP Retry Logic Library
# =============================================================================
# Implements exponential backoff retry logic, circuit breaker pattern,
# and graceful degradation for Jira MCP operations.
#
# Author: Claude Code
# Version: 1.0.0
# =============================================================================

# Enable strict error handling
set -euo pipefail

# Source error handling library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/jira-errors.sh"

# =============================================================================
# Configuration
# =============================================================================

# Default retry settings
DEFAULT_MAX_RETRIES=3
DEFAULT_BASE_DELAY=1
DEFAULT_MAX_DELAY=30
DEFAULT_BACKOFF_MULTIPLIER=2
DEFAULT_JITTER_ENABLED=true

# Circuit breaker settings
CIRCUIT_BREAKER_FAILURE_THRESHOLD=5
CIRCUIT_BREAKER_RESET_TIMEOUT=300  # 5 minutes
CIRCUIT_BREAKER_STATE_FILE="${TMPDIR:-/tmp}/jira-circuit-breaker.state"

# Circuit breaker states
readonly CB_STATE_CLOSED="closed"
readonly CB_STATE_OPEN="open"
readonly CB_STATE_HALF_OPEN="half-open"

# Retry statistics file
RETRY_STATS_FILE="${TMPDIR:-/tmp}/jira-retry-stats.json"

# =============================================================================
# Retry Configuration Functions
# =============================================================================

#' Set retry configuration for an operation
#' Usage: set_retry_config MAX_RETRIES BASE_DELAY MAX_DELAY BACKOFF_MULTIPLIER JITTER_ENABLED
set_retry_config() {
    export JIRA_MAX_RETRIES="${1:-$DEFAULT_MAX_RETRIES}"
    export JIRA_BASE_DELAY="${2:-$DEFAULT_BASE_DELAY}"
    export JIRA_MAX_DELAY="${3:-$DEFAULT_MAX_DELAY}"
    export JIRA_BACKOFF_MULTIPLIER="${4:-$DEFAULT_BACKOFF_MULTIPLIER}"
    export JIRA_JITTER_ENABLED="${5:-$DEFAULT_JITTER_ENABLED}"
}

#' Get current retry configuration
get_retry_config() {
    echo "Max Retries: ${JIRA_MAX_RETRIES:-$DEFAULT_MAX_RETRIES}"
    echo "Base Delay: ${JIRA_BASE_DELAY:-$DEFAULT_BASE_DELAY}s"
    echo "Max Delay: ${JIRA_MAX_DELAY:-$DEFAULT_MAX_DELAY}s"
    echo "Backoff Multiplier: ${JIRA_BACKOFF_MULTIPLIER:-$DEFAULT_BACKOFF_MULTIPLIER}"
    echo "Jitter Enabled: ${JIRA_JITTER_ENABLED:-$DEFAULT_JITTER_ENABLED}"
}

#' Reset retry configuration to defaults
reset_retry_config() {
    unset JIRA_MAX_RETRIES JIRA_BASE_DELAY JIRA_MAX_DELAY 
    unset JIRA_BACKOFF_MULTIPLIER JIRA_JITTER_ENABLED
}

# =============================================================================
# Circuit Breaker Functions
# =============================================================================

#' Get current circuit breaker state
#' Usage: get_circuit_breaker_state OPERATION_NAME
get_circuit_breaker_state() {
    local operation="${1:-default}"
    local state_key="$operation"
    
    if [[ ! -f "$CIRCUIT_BREAKER_STATE_FILE" ]]; then
        echo "$CB_STATE_CLOSED"
        return 0
    fi
    
    local current_time
    current_time=$(date +%s)
    
    # Read circuit breaker data
    local cb_data
    if cb_data=$(jq -r ".\"$state_key\" // empty" "$CIRCUIT_BREAKER_STATE_FILE" 2>/dev/null); then
        if [[ -n "$cb_data" && "$cb_data" != "null" ]]; then
            local state
            state=$(echo "$cb_data" | jq -r '.state')
            local failure_count
            failure_count=$(echo "$cb_data" | jq -r '.failure_count')
            local last_failure_time
            last_failure_time=$(echo "$cb_data" | jq -r '.last_failure_time')
            
            # Check if circuit breaker should reset
            if [[ "$state" == "$CB_STATE_OPEN" ]]; then
                local time_since_failure=$((current_time - last_failure_time))
                if [[ $time_since_failure -gt $CIRCUIT_BREAKER_RESET_TIMEOUT ]]; then
                    set_circuit_breaker_state "$operation" "$CB_STATE_HALF_OPEN" "$failure_count" "$last_failure_time"
                    echo "$CB_STATE_HALF_OPEN"
                else
                    echo "$CB_STATE_OPEN"
                fi
            else
                echo "$state"
            fi
        else
            echo "$CB_STATE_CLOSED"
        fi
    else
        echo "$CB_STATE_CLOSED"
    fi
}

#' Set circuit breaker state
#' Usage: set_circuit_breaker_state OPERATION_NAME STATE [FAILURE_COUNT] [LAST_FAILURE_TIME]
set_circuit_breaker_state() {
    local operation="${1:-default}"
    local state="${2:-$CB_STATE_CLOSED}"
    local failure_count="${3:-0}"
    local last_failure_time="${4:-$(date +%s)}"
    
    # Create state directory if needed
    mkdir -p "$(dirname "$CIRCUIT_BREAKER_STATE_FILE")"
    
    # Initialize state file if it doesn't exist
    if [[ ! -f "$CIRCUIT_BREAKER_STATE_FILE" ]]; then
        echo '{}' > "$CIRCUIT_BREAKER_STATE_FILE"
    fi
    
    # Update circuit breaker state
    local updated_state
    updated_state=$(jq \
        --arg op "$operation" \
        --arg state "$state" \
        --argjson count "$failure_count" \
        --argjson time "$last_failure_time" \
        '.[$op] = {
            "state": $state,
            "failure_count": $count,
            "last_failure_time": $time,
            "updated_at": now
        }' \
        "$CIRCUIT_BREAKER_STATE_FILE")
    
    echo "$updated_state" > "$CIRCUIT_BREAKER_STATE_FILE"
}

#' Record circuit breaker failure
#' Usage: record_circuit_breaker_failure OPERATION_NAME
record_circuit_breaker_failure() {
    local operation="${1:-default}"
    local current_state
    current_state=$(get_circuit_breaker_state "$operation")
    
    local current_time
    current_time=$(date +%s)
    
    if [[ ! -f "$CIRCUIT_BREAKER_STATE_FILE" ]]; then
        echo '{}' > "$CIRCUIT_BREAKER_STATE_FILE"
    fi
    
    # Get current failure count
    local failure_count=0
    local cb_data
    if cb_data=$(jq -r ".\"$operation\" // empty" "$CIRCUIT_BREAKER_STATE_FILE" 2>/dev/null); then
        if [[ -n "$cb_data" && "$cb_data" != "null" ]]; then
            failure_count=$(echo "$cb_data" | jq -r '.failure_count // 0')
        fi
    fi
    
    failure_count=$((failure_count + 1))
    
    # Determine new state
    local new_state="$CB_STATE_CLOSED"
    if [[ $failure_count -ge $CIRCUIT_BREAKER_FAILURE_THRESHOLD ]]; then
        new_state="$CB_STATE_OPEN"
        log_jira_error "WARN" "circuit-breaker" "$operation" "Circuit breaker opened due to $failure_count failures"
    fi
    
    set_circuit_breaker_state "$operation" "$new_state" "$failure_count" "$current_time"
}

#' Record circuit breaker success
#' Usage: record_circuit_breaker_success OPERATION_NAME
record_circuit_breaker_success() {
    local operation="${1:-default}"
    local current_state
    current_state=$(get_circuit_breaker_state "$operation")
    
    if [[ "$current_state" == "$CB_STATE_HALF_OPEN" ]]; then
        set_circuit_breaker_state "$operation" "$CB_STATE_CLOSED" 0 0
        log_jira_error "INFO" "circuit-breaker" "$operation" "Circuit breaker closed after successful operation"
    elif [[ "$current_state" == "$CB_STATE_CLOSED" ]]; then
        # Reset failure count on success
        set_circuit_breaker_state "$operation" "$CB_STATE_CLOSED" 0 0
    fi
}

#' Check if circuit breaker allows operation
#' Usage: is_circuit_breaker_open OPERATION_NAME
is_circuit_breaker_open() {
    local operation="${1:-default}"
    local state
    state=$(get_circuit_breaker_state "$operation")
    
    [[ "$state" == "$CB_STATE_OPEN" ]]
}

#' Reset circuit breaker for an operation
#' Usage: reset_circuit_breaker OPERATION_NAME
reset_circuit_breaker() {
    local operation="${1:-default}"
    set_circuit_breaker_state "$operation" "$CB_STATE_CLOSED" 0 0
    echo "Circuit breaker reset for operation: $operation"
}

# =============================================================================
# Retry Statistics Functions
# =============================================================================

#' Initialize retry statistics
init_retry_stats() {
    mkdir -p "$(dirname "$RETRY_STATS_FILE")"
    if [[ ! -f "$RETRY_STATS_FILE" ]]; then
        echo '{"operations":{}}' > "$RETRY_STATS_FILE"
    fi
}

#' Record retry attempt
#' Usage: record_retry_attempt OPERATION_NAME ATTEMPT_NUMBER SUCCESS
record_retry_attempt() {
    local operation="${1:-unknown}"
    local attempt="${2:-1}"
    local success="${3:-false}"
    local timestamp
    timestamp=$(date +%s)
    
    init_retry_stats
    
    # Update statistics
    local updated_stats
    updated_stats=$(jq \
        --arg op "$operation" \
        --argjson attempt "$attempt" \
        --arg success "$success" \
        --argjson timestamp "$timestamp" \
        '
        .operations[$op] = (.operations[$op] // {
            "total_attempts": 0,
            "total_operations": 0,
            "success_count": 0,
            "failure_count": 0,
            "retry_count": 0,
            "last_attempt": 0
        }) |
        .operations[$op].total_attempts += 1 |
        .operations[$op].last_attempt = $timestamp |
        if $attempt == 1 then
            .operations[$op].total_operations += 1
        else
            .operations[$op].retry_count += 1
        end |
        if $success == "true" then
            .operations[$op].success_count += 1
        else
            .operations[$op].failure_count += 1
        end
        ' \
        "$RETRY_STATS_FILE")
    
    echo "$updated_stats" > "$RETRY_STATS_FILE"
}

#' Get retry statistics for an operation
#' Usage: get_retry_stats [OPERATION_NAME]
get_retry_stats() {
    local operation="${1:-}"
    
    if [[ ! -f "$RETRY_STATS_FILE" ]]; then
        echo "No retry statistics available"
        return 0
    fi
    
    if [[ -n "$operation" ]]; then
        jq -r ".operations.\"$operation\" // empty" "$RETRY_STATS_FILE" | \
        jq -r 'if . == null or . == "" then
            "No statistics for operation: '$operation'"
        else
            "Operation: '$operation'",
            "Total Operations: \(.total_operations)",
            "Total Attempts: \(.total_attempts)",  
            "Retries: \(.retry_count)",
            "Success Rate: \((.success_count / .total_attempts * 100 | floor))%",
            "Last Attempt: \(.last_attempt | todate)"
        end'
    else
        echo "=== Retry Statistics Summary ==="
        jq -r '.operations | to_entries[] | 
            "\(.key): \(.value.total_operations) ops, \(.value.retry_count) retries, \((.value.success_count / .value.total_attempts * 100 | floor))% success"' \
            "$RETRY_STATS_FILE"
    fi
}

#' Clear retry statistics
clear_retry_stats() {
    echo '{"operations":{}}' > "$RETRY_STATS_FILE"
    echo "Retry statistics cleared"
}

# =============================================================================
# Delay Calculation Functions
# =============================================================================

#' Calculate exponential backoff delay with optional jitter
#' Usage: calculate_backoff_delay ATTEMPT_NUMBER [BASE_DELAY] [MULTIPLIER] [MAX_DELAY] [JITTER]
calculate_backoff_delay() {
    local attempt="${1:-1}"
    local base_delay="${2:-${JIRA_BASE_DELAY:-$DEFAULT_BASE_DELAY}}"
    local multiplier="${3:-${JIRA_BACKOFF_MULTIPLIER:-$DEFAULT_BACKOFF_MULTIPLIER}}"
    local max_delay="${4:-${JIRA_MAX_DELAY:-$DEFAULT_MAX_DELAY}}"
    local jitter="${5:-${JIRA_JITTER_ENABLED:-$DEFAULT_JITTER_ENABLED}}"
    
    # Calculate exponential backoff: base_delay * multiplier^(attempt-1)
    local delay="$base_delay"
    for ((i=1; i<attempt; i++)); do
        delay=$((delay * multiplier))
    done
    
    # Cap at maximum delay
    if [[ $delay -gt $max_delay ]]; then
        delay="$max_delay"
    fi
    
    # Add jitter if enabled (±25% of delay)
    if [[ "$jitter" == "true" ]]; then
        local jitter_amount=$((delay / 4))
        local random_jitter=$((RANDOM % (jitter_amount * 2) - jitter_amount))
        delay=$((delay + random_jitter))
        
        # Ensure delay is not negative
        if [[ $delay -lt 0 ]]; then
            delay=0
        fi
    fi
    
    echo "$delay"
}

# =============================================================================
# Retry Execution Functions
# =============================================================================

#' Execute an operation with retry logic
#' Usage: execute_with_retry OPERATION_NAME COMMAND [ARGS...]
#' Example: execute_with_retry "get_issue" "jira-adapter.sh" "get-issue" "PROJ-123"
execute_with_retry() {
    local operation_name="${1:-unknown}"
    shift
    local command=("$@")
    
    if [[ ${#command[@]} -eq 0 ]]; then
        echo "Error: No command provided for retry execution" >&2
        return 1
    fi
    
    local max_retries="${JIRA_MAX_RETRIES:-$DEFAULT_MAX_RETRIES}"
    local attempt=1
    local last_exit_code=0
    local last_error_output=""
    
    # Check circuit breaker
    if is_circuit_breaker_open "$operation_name"; then
        display_jira_error "$operation_name" "circuit-breaker" "Circuit breaker is open - operation blocked due to repeated failures" "false"
        return 1
    fi
    
    while [[ $attempt -le $((max_retries + 1)) ]]; do
        log_jira_error "INFO" "$operation_name" "retry-system" "Attempting operation (attempt $attempt/$((max_retries + 1)))"
        
        # Execute the command
        local start_time
        start_time=$(date +%s)
        
        # Capture both stdout and stderr
        local temp_out
        temp_out=$(mktemp)
        local temp_err
        temp_err=$(mktemp)
        
        if "${command[@]}" >"$temp_out" 2>"$temp_err"; then
            # Success
            local output
            output=$(cat "$temp_out")
            local end_time
            end_time=$(date +%s)
            local duration=$((end_time - start_time))
            
            # Cleanup
            rm -f "$temp_out" "$temp_err"
            
            # Record success
            record_retry_attempt "$operation_name" "$attempt" "true"
            record_circuit_breaker_success "$operation_name"
            
            log_jira_error "INFO" "$operation_name" "retry-system" "Operation succeeded on attempt $attempt (${duration}s)"
            
            # Return the output
            echo "$output"
            return 0
        else
            # Failure
            last_exit_code=$?
            last_error_output=$(cat "$temp_err" 2>/dev/null || echo "No error output")
            
            # Cleanup
            rm -f "$temp_out" "$temp_err"
            
            # Record failure
            record_retry_attempt "$operation_name" "$attempt" "false"
            
            # Check if we should retry
            if [[ $attempt -le $max_retries ]]; then
                # Determine if error is retryable
                local error_info
                error_info=$(map_mcp_error "${command[0]}" "$last_error_output")
                local category
                category=$(echo "$error_info" | cut -d'|' -f1)
                
                if is_transient_error "$category"; then
                    # Calculate delay
                    local delay
                    delay=$(calculate_backoff_delay "$attempt")
                    
                    log_jira_error "WARN" "$operation_name" "retry-system" "Attempt $attempt failed (transient error), retrying in ${delay}s. Error: $last_error_output"
                    
                    # Wait before retry
                    if [[ $delay -gt 0 ]]; then
                        sleep "$delay"
                    fi
                    
                    attempt=$((attempt + 1))
                    continue
                else
                    # Non-retryable error
                    log_jira_error "ERROR" "$operation_name" "retry-system" "Attempt $attempt failed with non-retryable error: $last_error_output"
                    record_circuit_breaker_failure "$operation_name"
                    break
                fi
            else
                # Max retries reached
                log_jira_error "ERROR" "$operation_name" "retry-system" "Operation failed after $max_retries retries: $last_error_output"
                record_circuit_breaker_failure "$operation_name"
                break
            fi
        fi
    done
    
    # Final failure
    display_jira_error "$operation_name" "retry-system" "Operation failed after $((attempt-1)) attempts: $last_error_output" "true"
    return "$last_exit_code"
}

#' Execute with simplified retry for common patterns
#' Usage: retry_mcp_call TOOL_NAME PARAMS_JSON [OPERATION_NAME]
retry_mcp_call() {
    local tool_name="${1:-}"
    local params_json="${2:-}"
    local operation_name="${3:-$tool_name}"
    
    if [[ -z "$tool_name" || -z "$params_json" ]]; then
        echo "Error: Tool name and parameters are required" >&2
        return 1
    fi
    
    # Create a temporary script to execute the MCP call
    local temp_script
    temp_script=$(mktemp)
    cat > "$temp_script" << 'EOF'
#!/bin/bash
# This is a placeholder for actual MCP tool execution
# In practice, this would invoke the MCP tool through Claude Code
echo "MCP call: $1 with params: $2"
# Simulate some potential failures for testing
if [[ $((RANDOM % 10)) -eq 0 ]]; then
    echo "Simulated network timeout" >&2
    exit 124
elif [[ $((RANDOM % 20)) -eq 0 ]]; then
    echo "Simulated rate limit: HTTP 429 Too Many Requests" >&2
    exit 1
fi
echo '{"status":"success","result":"placeholder"}'
EOF
    chmod +x "$temp_script"
    
    # Execute with retry
    local result
    if result=$(execute_with_retry "$operation_name" "$temp_script" "$tool_name" "$params_json"); then
        rm -f "$temp_script"
        echo "$result"
        return 0
    else
        local exit_code=$?
        rm -f "$temp_script"
        return "$exit_code"
    fi
}

# =============================================================================
# Graceful Degradation Functions
# =============================================================================

#' Execute operation with graceful degradation
#' Usage: execute_with_degradation OPERATION_NAME PRIMARY_COMMAND FALLBACK_COMMAND [FALLBACK_MESSAGE]
execute_with_degradation() {
    local operation_name="${1:-unknown}"
    local primary_command="${2:-}"
    local fallback_command="${3:-}"
    local fallback_message="${4:-Using fallback operation}"
    
    if [[ -z "$primary_command" ]]; then
        echo "Error: Primary command is required" >&2
        return 1
    fi
    
    # Try primary operation with retry
    if execute_with_retry "$operation_name" bash -c "$primary_command"; then
        return 0
    fi
    
    # If primary fails and fallback exists, try fallback
    if [[ -n "$fallback_command" ]]; then
        echo "⚠️  $fallback_message" >&2
        log_jira_error "WARN" "$operation_name" "degradation" "Primary operation failed, using fallback: $fallback_command"
        
        if bash -c "$fallback_command"; then
            return 0
        else
            echo "❌ Both primary and fallback operations failed" >&2
            return 1
        fi
    fi
    
    return 1
}

# =============================================================================
# Management Functions
# =============================================================================

#' Show circuit breaker status for all operations
show_circuit_breaker_status() {
    if [[ ! -f "$CIRCUIT_BREAKER_STATE_FILE" ]]; then
        echo "No circuit breaker data available"
        return 0
    fi
    
    echo "=== Circuit Breaker Status ==="
    jq -r 'to_entries[] | 
        "\(.key): \(.value.state) (failures: \(.value.failure_count), last: \(.value.last_failure_time | todate))"' \
        "$CIRCUIT_BREAKER_STATE_FILE" 2>/dev/null || echo "No circuit breaker data"
}

#' Reset all circuit breakers
reset_all_circuit_breakers() {
    if [[ -f "$CIRCUIT_BREAKER_STATE_FILE" ]]; then
        > "$CIRCUIT_BREAKER_STATE_FILE"
        echo "{}" > "$CIRCUIT_BREAKER_STATE_FILE"
        echo "All circuit breakers reset"
    else
        echo "No circuit breakers to reset"
    fi
}

#' Show comprehensive retry system status
show_retry_system_status() {
    echo "=== Retry System Status ==="
    echo ""
    
    echo "Configuration:"
    get_retry_config
    echo ""
    
    echo "Circuit Breakers:"
    show_circuit_breaker_status
    echo ""
    
    echo "Statistics:"
    get_retry_stats
}

# =============================================================================
# Initialization
# =============================================================================

# Initialize statistics file
init_retry_stats

# Create circuit breaker directory
mkdir -p "$(dirname "$CIRCUIT_BREAKER_STATE_FILE")"

# Export key functions for use by other modules
export -f execute_with_retry
export -f retry_mcp_call
export -f execute_with_degradation
export -f set_retry_config
export -f reset_circuit_breaker
export -f get_circuit_breaker_state