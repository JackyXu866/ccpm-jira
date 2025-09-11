#!/bin/bash
set -euo pipefail

# =============================================================================
# CCPM-Jira Validation Command
# =============================================================================
# This script provides a command-line interface for validating data consistency
# between CCPM and Jira systems. It offers various validation modes including
# individual epic/task validation, bulk validation, and conflict detection.
#
# Author: Claude Code - Stream D Implementation
# Version: 1.0.0
# =============================================================================

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../../lib"
VALIDATE_SCRIPT="jira-validate"

# Source dependencies
source "${LIB_DIR}/jira-validation.sh"
source "${LIB_DIR}/conflict-resolution.sh"

# =============================================================================
# Command Usage and Help
# =============================================================================

show_usage() {
    cat << EOF
CCPM-Jira Validation Tool

USAGE:
    $VALIDATE_SCRIPT [OPTIONS] COMMAND [ARGS]

COMMANDS:
    epic EPIC_ID JIRA_KEY         Validate consistency for a specific epic
    task TASK_ID JIRA_KEY         Validate consistency for a specific task
    bulk-epics FILE               Validate multiple epics from JSON file
    bulk-tasks FILE               Validate multiple tasks from JSON file  
    relationships EPIC_ID [FILE]  Validate epic-task relationships
    field-mappings FILE           Validate field mapping functionality
    custom-fields FILE            Validate custom field handling
    conflicts CCPM_FILE           Detect sync conflicts in CCPM data
    performance [SIZE]            Run performance validation tests

OPTIONS:
    -v, --verbose                 Enable verbose output
    -q, --quiet                   Suppress non-essential output
    -o, --output FILE             Save validation report to file
    -f, --format FORMAT           Output format (text|json) [default: text]
    --no-color                    Disable colored output
    --dry-run                     Validate without making changes
    -h, --help                    Show this help message

EXAMPLES:
    # Validate specific epic consistency
    $VALIDATE_SCRIPT epic 123 PROJ-456
    
    # Validate bulk epics from file
    $VALIDATE_SCRIPT bulk-epics epics.json
    
    # Detect conflicts and save report
    $VALIDATE_SCRIPT -o conflicts.json conflicts ccpm_data.json
    
    # Run performance tests with medium dataset
    $VALIDATE_SCRIPT performance 50
    
    # Validate field mappings with verbose output
    $VALIDATE_SCRIPT -v field-mappings test_data.json

For more information, visit: https://github.com/ccpm-ai/ccpm-jira
EOF
}

# =============================================================================
# Global Options and Configuration
# =============================================================================

# Default options
VERBOSE=false
QUIET=false
OUTPUT_FILE=""
OUTPUT_FORMAT="text"
USE_COLOR=true
DRY_RUN=false

# Color codes (if enabled)
setup_colors() {
    if [[ "$USE_COLOR" == "true" ]] && [[ -t 1 ]]; then
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        PURPLE='\033[0;35m'
        CYAN='\033[0;36m'
        NC='\033[0m' # No Color
    else
        RED=""
        GREEN=""
        YELLOW=""
        BLUE=""
        PURPLE=""
        CYAN=""
        NC=""
    fi
}

# =============================================================================
# Logging and Output Functions
# =============================================================================

log_info() {
    if [[ "$QUIET" != "true" ]]; then
        echo -e "${BLUE}INFO:${NC} $*" >&2
    fi
}

log_success() {
    if [[ "$QUIET" != "true" ]]; then
        echo -e "${GREEN}SUCCESS:${NC} $*" >&2
    fi
}

log_warning() {
    if [[ "$QUIET" != "true" ]]; then
        echo -e "${YELLOW}WARNING:${NC} $*" >&2
    fi
}

log_error() {
    echo -e "${RED}ERROR:${NC} $*" >&2
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${CYAN}VERBOSE:${NC} $*" >&2
    fi
}

# =============================================================================
# Validation Command Functions
# =============================================================================

#' Validate individual epic consistency
cmd_validate_epic() {
    local epic_id="$1"
    local jira_key="$2"
    
    if [[ -z "$epic_id" || -z "$jira_key" ]]; then
        log_error "Epic ID and Jira key are required"
        return 1
    fi
    
    log_info "Validating epic $epic_id (Jira: $jira_key)"
    log_verbose "Epic ID: $epic_id, Jira Key: $jira_key"
    
    # For this validation, we need CCPM epic data
    # In a real implementation, this would fetch from CCPM
    log_error "CCPM data access not implemented - would fetch epic $epic_id from CCPM"
    log_info "To use this command, provide CCPM epic JSON data via stdin or file"
    
    return 1
}

#' Validate individual task consistency
cmd_validate_task() {
    local task_id="$1"
    local jira_key="$2"
    
    if [[ -z "$task_id" || -z "$jira_key" ]]; then
        log_error "Task ID and Jira key are required"
        return 1
    fi
    
    log_info "Validating task $task_id (Jira: $jira_key)"
    log_verbose "Task ID: $task_id, Jira Key: $jira_key"
    
    # For this validation, we need CCPM task data
    log_error "CCPM data access not implemented - would fetch task $task_id from CCPM"
    log_info "To use this command, provide CCPM task JSON data via stdin or file"
    
    return 1
}

#' Validate bulk epics from file
cmd_validate_bulk_epics() {
    local epics_file="$1"
    
    if [[ -z "$epics_file" ]]; then
        log_error "Epics JSON file is required"
        return 1
    fi
    
    if [[ ! -f "$epics_file" ]]; then
        log_error "Epics file not found: $epics_file"
        return 1
    fi
    
    log_info "Validating epics from file: $epics_file"
    log_verbose "Loading epics from $epics_file"
    
    local epics_json
    if ! epics_json=$(jq . "$epics_file" 2>/dev/null); then
        log_error "Invalid JSON in epics file: $epics_file"
        return 1
    fi
    
    log_verbose "Loaded $(echo "$epics_json" | jq 'length') epics"
    
    # Run validation
    local validation_result
    if validation_result=$(validate_multiple_epics "$epics_json"); then
        log_success "Bulk epic validation completed"
        
        if [[ "$OUTPUT_FORMAT" == "json" ]]; then
            echo "$validation_result"
        else
            echo "$validation_result" | jq -r '
                "Validation Summary:\n" +
                "  Total Epics: " + (.summary.total_epics | tostring) + "\n" +
                "  Passed: " + (.summary.passed | tostring) + "\n" +
                "  Failed: " + (.summary.failed | tostring) + "\n" +
                "  Success Rate: " + (.summary.success_rate | tostring) + "%"
            '
        fi
        
        # Save to file if requested
        if [[ -n "$OUTPUT_FILE" ]]; then
            echo "$validation_result" > "$OUTPUT_FILE"
            log_info "Validation report saved to: $OUTPUT_FILE"
        fi
        
        return 0
    else
        log_error "Bulk epic validation failed"
        return 1
    fi
}

#' Validate bulk tasks from file
cmd_validate_bulk_tasks() {
    local tasks_file="$1"
    
    if [[ -z "$tasks_file" ]]; then
        log_error "Tasks JSON file is required"
        return 1
    fi
    
    if [[ ! -f "$tasks_file" ]]; then
        log_error "Tasks file not found: $tasks_file"
        return 1
    fi
    
    log_info "Validating tasks from file: $tasks_file"
    log_verbose "Loading tasks from $tasks_file"
    
    local tasks_json
    if ! tasks_json=$(jq . "$tasks_file" 2>/dev/null); then
        log_error "Invalid JSON in tasks file: $tasks_file"
        return 1
    fi
    
    log_verbose "Loaded $(echo "$tasks_json" | jq 'length') tasks"
    
    # Run validation
    local validation_result
    if validation_result=$(validate_multiple_tasks "$tasks_json"); then
        log_success "Bulk task validation completed"
        
        if [[ "$OUTPUT_FORMAT" == "json" ]]; then
            echo "$validation_result"
        else
            echo "$validation_result" | jq -r '
                "Validation Summary:\n" +
                "  Total Tasks: " + (.summary.total_tasks | tostring) + "\n" +
                "  Passed: " + (.summary.passed | tostring) + "\n" +
                "  Failed: " + (.summary.failed | tostring) + "\n" +
                "  Success Rate: " + (.summary.success_rate | tostring) + "%"
            '
        fi
        
        # Save to file if requested
        if [[ -n "$OUTPUT_FILE" ]]; then
            echo "$validation_result" > "$OUTPUT_FILE"
            log_info "Validation report saved to: $OUTPUT_FILE"
        fi
        
        return 0
    else
        log_error "Bulk task validation failed"
        return 1
    fi
}

#' Validate epic-task relationships
cmd_validate_relationships() {
    local epic_id="$1"
    local tasks_file="${2:-}"
    
    if [[ -z "$epic_id" ]]; then
        log_error "Epic ID is required"
        return 1
    fi
    
    log_info "Validating relationships for epic: $epic_id"
    
    local tasks_json="{}"
    if [[ -n "$tasks_file" && -f "$tasks_file" ]]; then
        log_verbose "Loading tasks from $tasks_file"
        if ! tasks_json=$(jq . "$tasks_file" 2>/dev/null); then
            log_error "Invalid JSON in tasks file: $tasks_file"
            return 1
        fi
    fi
    
    if validate_epic_task_relationships "$epic_id" "$tasks_json"; then
        log_success "Epic-task relationship validation passed"
        return 0
    else
        log_error "Epic-task relationship validation failed"
        return 1
    fi
}

#' Validate field mappings
cmd_validate_field_mappings() {
    local test_data_file="$1"
    
    if [[ -z "$test_data_file" ]]; then
        log_error "Test data JSON file is required"
        return 1
    fi
    
    if [[ ! -f "$test_data_file" ]]; then
        log_error "Test data file not found: $test_data_file"
        return 1
    fi
    
    log_info "Validating field mappings with test data: $test_data_file"
    
    local test_data
    if ! test_data=$(jq . "$test_data_file" 2>/dev/null); then
        log_error "Invalid JSON in test data file: $test_data_file"
        return 1
    fi
    
    if validate_field_mappings "$test_data" ""; then
        log_success "Field mapping validation passed"
        return 0
    else
        log_error "Field mapping validation failed"
        return 1
    fi
}

#' Validate custom fields
cmd_validate_custom_fields() {
    local test_data_file="$1"
    
    if [[ -z "$test_data_file" ]]; then
        log_error "Test data JSON file is required"
        return 1
    fi
    
    if [[ ! -f "$test_data_file" ]]; then
        log_error "Test data file not found: $test_data_file"
        return 1
    fi
    
    log_info "Validating custom fields with test data: $test_data_file"
    
    local test_data
    if ! test_data=$(jq . "$test_data_file" 2>/dev/null); then
        log_error "Invalid JSON in test data file: $test_data_file"
        return 1
    fi
    
    if validate_custom_fields "$test_data"; then
        log_success "Custom fields validation passed"
        return 0
    else
        log_error "Custom fields validation failed"
        return 1
    fi
}

#' Detect conflicts in CCPM data
cmd_detect_conflicts() {
    local ccpm_data_file="$1"
    
    if [[ -z "$ccpm_data_file" ]]; then
        log_error "CCPM data JSON file is required"
        return 1
    fi
    
    if [[ ! -f "$ccpm_data_file" ]]; then
        log_error "CCPM data file not found: $ccpm_data_file"
        return 1
    fi
    
    log_info "Detecting conflicts in CCPM data: $ccpm_data_file"
    
    local ccpm_data
    if ! ccpm_data=$(jq . "$ccpm_data_file" 2>/dev/null); then
        log_error "Invalid JSON in CCPM data file: $ccpm_data_file"
        return 1
    fi
    
    log_verbose "Analyzing CCPM data for conflicts..."
    
    local conflicts
    if conflicts=$(detect_bulk_sync_conflicts "$ccpm_data" "bidirectional"); then
        local conflict_count
        conflict_count=$(echo "$conflicts" | jq 'length')
        
        if [[ "$conflict_count" -eq 0 ]]; then
            log_success "No conflicts detected"
            if [[ "$OUTPUT_FORMAT" == "json" ]]; then
                echo '{"conflicts": [], "status": "no_conflicts"}'
            else
                echo "No conflicts found in the provided data."
            fi
        else
            log_warning "$conflict_count conflicts detected"
            if [[ "$OUTPUT_FORMAT" == "json" ]]; then
                jq -n --argjson conflicts "$conflicts" '{"conflicts": $conflicts, "status": "conflicts_found"}'
            else
                echo "Conflicts detected:"
                echo "$conflicts" | jq -r '.[] | "  - " + .epic_id + " (" + .jira_key + "): " + (.conflicts | length | tostring) + " field conflicts"'
            fi
        fi
        
        # Save to file if requested
        if [[ -n "$OUTPUT_FILE" ]]; then
            jq -n --argjson conflicts "$conflicts" '{"conflicts": $conflicts, "detected_at": (now | strftime("%Y-%m-%dT%H:%M:%SZ"))}' > "$OUTPUT_FILE"
            log_info "Conflict report saved to: $OUTPUT_FILE"
        fi
        
        return 0
    else
        log_error "Conflict detection failed"
        return 1
    fi
}

#' Run performance validation tests
cmd_performance_test() {
    local dataset_size="${1:-50}"
    
    if ! [[ "$dataset_size" =~ ^[0-9]+$ ]]; then
        log_error "Dataset size must be a number"
        return 1
    fi
    
    log_info "Running performance validation tests with dataset size: $dataset_size"
    
    # Check if performance test script exists
    local perf_test_script="${SCRIPT_DIR}/../../tests/integration/performance-test.sh"
    if [[ ! -f "$perf_test_script" ]]; then
        log_error "Performance test script not found: $perf_test_script"
        return 1
    fi
    
    log_verbose "Executing performance test script..."
    
    # Set environment variables for the performance test
    export SMALL_DATASET_SIZE=$((dataset_size / 5))
    export MEDIUM_DATASET_SIZE="$dataset_size"
    export LARGE_DATASET_SIZE=$((dataset_size * 2))
    
    if bash "$perf_test_script"; then
        log_success "Performance tests completed successfully"
        return 0
    else
        log_error "Performance tests failed"
        return 1
    fi
}

# =============================================================================
# Argument Parsing
# =============================================================================

parse_arguments() {
    local args=()
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -f|--format)
                OUTPUT_FORMAT="$2"
                if [[ "$OUTPUT_FORMAT" != "text" && "$OUTPUT_FORMAT" != "json" ]]; then
                    log_error "Invalid output format: $OUTPUT_FORMAT (must be 'text' or 'json')"
                    exit 1
                fi
                shift 2
                ;;
            --no-color)
                USE_COLOR=false
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                echo "Use --help for usage information."
                exit 1
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done
    
    echo "${args[@]}"
}

# =============================================================================
# Main Command Dispatcher
# =============================================================================

main() {
    setup_colors
    
    local args
    args=($(parse_arguments "$@"))
    
    if [[ ${#args[@]} -eq 0 ]]; then
        log_error "No command specified"
        show_usage
        exit 1
    fi
    
    local command="${args[0]}"
    
    case "$command" in
        epic)
            cmd_validate_epic "${args[1]:-}" "${args[2]:-}"
            ;;
        task)
            cmd_validate_task "${args[1]:-}" "${args[2]:-}"
            ;;
        bulk-epics)
            cmd_validate_bulk_epics "${args[1]:-}"
            ;;
        bulk-tasks)
            cmd_validate_bulk_tasks "${args[1]:-}"
            ;;
        relationships)
            cmd_validate_relationships "${args[1]:-}" "${args[2]:-}"
            ;;
        field-mappings)
            cmd_validate_field_mappings "${args[1]:-}"
            ;;
        custom-fields)
            cmd_validate_custom_fields "${args[1]:-}"
            ;;
        conflicts)
            cmd_detect_conflicts "${args[1]:-}"
            ;;
        performance)
            cmd_performance_test "${args[1]:-}"
            ;;
        *)
            log_error "Unknown command: $command"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi