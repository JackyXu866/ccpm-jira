#!/bin/bash
set -euo pipefail

# =============================================================================
# Jira Validation Library
# =============================================================================
# This library provides comprehensive validation functions for data integrity
# between CCPM and Jira systems. It includes validation for epic-task 
# relationships, field mappings, custom fields, and sync consistency.
#
# Author: Claude Code - Stream D Implementation
# Version: 1.0.0
# =============================================================================

# Source dependencies
VALIDATION_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${VALIDATION_SCRIPT_DIR}/jira-fields.sh"
source "${VALIDATION_SCRIPT_DIR}/jira-epic-ops.sh"
source "${VALIDATION_SCRIPT_DIR}/jira-task-ops.sh"
source "${VALIDATION_SCRIPT_DIR}/../scripts/adapters/jira-adapter.sh"

# Ensure required tools are available
if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required for validation operations" >&2
    exit 1
fi

# =============================================================================
# Data Integrity Validation Functions
# =============================================================================

#' Validate CCPM-Jira data consistency for an epic
#' Usage: validate_epic_consistency EPIC_CCPM_JSON JIRA_KEY
#' Returns: Success/failure status with detailed report
validate_epic_consistency() {
    local ccpm_epic="$1"
    local jira_key="$2"
    
    if [[ -z "$ccpm_epic" || -z "$jira_key" ]]; then
        echo "Error: CCPM epic data and Jira key are required" >&2
        return 1
    fi
    
    echo "Validating epic consistency: $jira_key"
    
    # Fetch current Jira epic
    local jira_epic
    if ! jira_epic=$(get_jira_epic "$jira_key"); then
        echo "FAIL: Unable to fetch Jira epic $jira_key" >&2
        return 1
    fi
    
    # Convert Jira epic to CCPM format for comparison
    local jira_ccpm_format
    if ! jira_ccpm_format=$(process_jira_epic_response "$jira_epic"); then
        echo "FAIL: Unable to process Jira epic response" >&2
        return 1
    fi
    
    # Validate core field consistency
    local validation_report=""
    local validation_passed=true
    
    # Check title/summary consistency
    local ccpm_name jira_name
    ccpm_name=$(echo "$ccpm_epic" | jq -r '.name // "Unknown"')
    jira_name=$(echo "$jira_ccpm_format" | jq -r '.name // "Unknown"')
    
    if [[ "$ccpm_name" != "$jira_name" ]]; then
        validation_report+="INCONSISTENCY: Epic name differs - CCPM: '$ccpm_name' vs Jira: '$jira_name'\n"
        validation_passed=false
    fi
    
    # Check status consistency
    local ccpm_status jira_status
    ccpm_status=$(echo "$ccpm_epic" | jq -r '.status // "unknown"')
    jira_status=$(echo "$jira_ccpm_format" | jq -r '.status // "unknown"')
    
    if [[ "$ccpm_status" != "$jira_status" ]]; then
        validation_report+="INCONSISTENCY: Epic status differs - CCPM: '$ccpm_status' vs Jira: '$jira_status'\n"
        validation_passed=false
    fi
    
    # Check custom fields if present
    local ccpm_start_date jira_start_date
    ccpm_start_date=$(echo "$ccpm_epic" | jq -r '.start_date // ""')
    jira_start_date=$(echo "$jira_ccpm_format" | jq -r '.start_date // ""')
    
    if [[ -n "$ccpm_start_date" && -n "$jira_start_date" && "$ccpm_start_date" != "$jira_start_date" ]]; then
        validation_report+="INCONSISTENCY: Epic start date differs - CCPM: '$ccpm_start_date' vs Jira: '$jira_start_date'\n"
        validation_passed=false
    fi
    
    # Output results
    if [[ "$validation_passed" == "true" ]]; then
        echo "PASS: Epic $jira_key is consistent between CCPM and Jira"
        return 0
    else
        echo "FAIL: Epic $jira_key has inconsistencies:"
        echo -e "$validation_report"
        return 1
    fi
}

#' Validate CCPM-Jira data consistency for a task
#' Usage: validate_task_consistency TASK_CCPM_JSON JIRA_KEY
#' Returns: Success/failure status with detailed report
validate_task_consistency() {
    local ccpm_task="$1"
    local jira_key="$2"
    
    if [[ -z "$ccpm_task" || -z "$jira_key" ]]; then
        echo "Error: CCPM task data and Jira key are required" >&2
        return 1
    fi
    
    echo "Validating task consistency: $jira_key"
    
    # Fetch current Jira task
    local jira_task
    if ! jira_task=$(get_jira_task "$jira_key"); then
        echo "FAIL: Unable to fetch Jira task $jira_key" >&2
        return 1
    fi
    
    # Validate core field consistency
    local validation_report=""
    local validation_passed=true
    
    # Check title/summary consistency
    local ccpm_name jira_name
    ccpm_name=$(echo "$ccpm_task" | jq -r '.name // "Unknown"')
    jira_name=$(echo "$jira_task" | jq -r '.name // "Unknown"')
    
    if [[ "$ccpm_name" != "$jira_name" ]]; then
        validation_report+="INCONSISTENCY: Task name differs - CCPM: '$ccpm_name' vs Jira: '$jira_name'\n"
        validation_passed=false
    fi
    
    # Check status consistency
    local ccpm_status jira_status
    ccpm_status=$(echo "$ccpm_task" | jq -r '.status // "unknown"')
    jira_status=$(echo "$jira_task" | jq -r '.status // "unknown"')
    
    if [[ "$ccpm_status" != "$jira_status" ]]; then
        validation_report+="INCONSISTENCY: Task status differs - CCPM: '$ccpm_status' vs Jira: '$jira_status'\n"
        validation_passed=false
    fi
    
    # Check progress consistency
    local ccpm_progress jira_progress
    ccpm_progress=$(echo "$ccpm_task" | jq -r '.progress // "0"')
    jira_progress=$(echo "$jira_task" | jq -r '.progress // "0"')
    
    # Normalize progress values (remove % signs)
    ccpm_progress=${ccpm_progress%\%}
    jira_progress=${jira_progress%\%}
    
    if [[ "$ccpm_progress" != "$jira_progress" ]]; then
        validation_report+="INCONSISTENCY: Task progress differs - CCPM: '${ccpm_progress}%' vs Jira: '${jira_progress}%'\n"
        validation_passed=false
    fi
    
    # Output results
    if [[ "$validation_passed" == "true" ]]; then
        echo "PASS: Task $jira_key is consistent between CCPM and Jira"
        return 0
    else
        echo "FAIL: Task $jira_key has inconsistencies:"
        echo -e "$validation_report"
        return 1
    fi
}

#' Validate epic-task relationships between CCPM and Jira
#' Usage: validate_epic_task_relationships EPIC_ID CCPM_TASKS_JSON
#' Returns: Success/failure status with relationship report  
validate_epic_task_relationships() {
    local epic_id="$1"
    local ccpm_tasks="$2"
    
    if [[ -z "$epic_id" ]]; then
        echo "Error: Epic ID is required" >&2
        return 1
    fi
    
    echo "Validating epic-task relationships for epic: $epic_id"
    
    # Get CCPM task list for this epic
    local ccpm_task_ids
    if [[ -n "$ccpm_tasks" ]]; then
        ccpm_task_ids=$(echo "$ccpm_tasks" | jq -r '.[] | select(.epic_id == $epic_id) | .id // empty')
    else
        ccpm_task_ids=""
    fi
    
    # Get Jira issues linked to this epic
    local jira_linked_issues
    if ! jira_linked_issues=$(search_jira_tasks "\"Epic Link\" = \"$epic_id\""); then
        echo "Warning: Unable to search for tasks linked to epic $epic_id" >&2
        jira_linked_issues="[]"
    fi
    
    local jira_task_count
    jira_task_count=$(echo "$jira_linked_issues" | jq 'length')
    
    local ccpm_task_count
    ccpm_task_count=$(echo "$ccpm_task_ids" | wc -w)
    
    echo "Epic $epic_id has $ccpm_task_count CCPM tasks and $jira_task_count Jira issues"
    
    # Validate each CCPM task exists in Jira
    local missing_in_jira=0
    if [[ -n "$ccpm_task_ids" ]]; then
        while read -r task_id; do
            [[ -z "$task_id" ]] && continue
            
            # Check if task exists in Jira linked issues
            local found_in_jira
            found_in_jira=$(echo "$jira_linked_issues" | jq --arg id "$task_id" 'any(.[] ; .ccpm_id == $id)')
            
            if [[ "$found_in_jira" != "true" ]]; then
                echo "WARNING: CCPM task $task_id not found in Jira epic $epic_id"
                missing_in_jira=$((missing_in_jira + 1))
            fi
        done <<< "$ccpm_task_ids"
    fi
    
    if [[ $missing_in_jira -eq 0 ]]; then
        echo "PASS: All CCPM tasks are properly linked to epic in Jira"
        return 0
    else
        echo "FAIL: $missing_in_jira CCPM tasks are missing from Jira epic"
        return 1
    fi
}

#' Validate field mappings are working correctly
#' Usage: validate_field_mappings CCPM_DATA EXPECTED_JIRA_DATA
#' Returns: Success/failure status
validate_field_mappings() {
    local ccpm_data="$1"
    local expected_jira_data="$2"
    
    if [[ -z "$ccpm_data" ]]; then
        echo "Error: CCPM data is required" >&2
        return 1
    fi
    
    echo "Validating field mappings..."
    
    # Test epic mapping if epic data provided
    if echo "$ccpm_data" | jq -e '.epic_id // empty' >/dev/null 2>&1; then
        echo "Testing epic field mapping..."
        local jira_epic_request
        if ! jira_epic_request=$(prepare_epic_for_jira "Test Epic" "$ccpm_data"); then
            echo "FAIL: Epic field mapping failed" >&2
            return 1
        fi
        echo "PASS: Epic field mapping successful"
    fi
    
    # Test task mapping if task data provided  
    if echo "$ccpm_data" | jq -e '.task_id // .id // empty' >/dev/null 2>&1; then
        echo "Testing task field mapping..."
        local jira_task_request
        if ! jira_task_request=$(prepare_task_for_jira "Test Task" "$ccpm_data"); then
            echo "FAIL: Task field mapping failed" >&2
            return 1
        fi
        echo "PASS: Task field mapping successful"
    fi
    
    # Test specific field transformations
    echo "Testing field transformations..."
    
    # Test status transformation
    local test_status="in-progress"
    local transformed_status
    if transformed_status=$(transform_status_ccpm_to_jira "$test_status"); then
        echo "PASS: Status transformation: '$test_status' -> '$transformed_status'"
    else
        echo "FAIL: Status transformation failed for '$test_status'" >&2
        return 1
    fi
    
    # Test percentage transformation
    local test_percentage="50%"
    local transformed_percentage
    if transformed_percentage=$(transform_percentage_ccpm_to_jira "$test_percentage"); then
        echo "PASS: Percentage transformation: '$test_percentage' -> '$transformed_percentage'"
    else
        echo "FAIL: Percentage transformation failed for '$test_percentage'" >&2
        return 1
    fi
    
    echo "PASS: All field mappings validated successfully"
    return 0
}

#' Validate custom field handling
#' Usage: validate_custom_fields CCPM_DATA
#' Returns: Success/failure status
validate_custom_fields() {
    local ccpm_data="$1"
    
    if [[ -z "$ccpm_data" ]]; then
        echo "Error: CCPM data is required" >&2
        return 1
    fi
    
    echo "Validating custom field handling..."
    
    # Test start date custom field
    local start_date
    start_date=$(echo "$ccpm_data" | jq -r '.start_date // empty')
    if [[ -n "$start_date" ]]; then
        if transform_datetime_ccpm_to_jira "$start_date" >/dev/null; then
            echo "PASS: Start date custom field validation"
        else
            echo "FAIL: Start date custom field validation failed" >&2
            return 1
        fi
    fi
    
    # Test dependencies custom field
    local dependencies
    dependencies=$(echo "$ccpm_data" | jq -r '.depends_on // empty')
    if [[ -n "$dependencies" ]]; then
        if transform_dependency_array_ccpm_to_jira "$dependencies" >/dev/null; then
            echo "PASS: Dependencies custom field validation"
        else
            echo "FAIL: Dependencies custom field validation failed" >&2
            return 1
        fi
    fi
    
    # Test progress tracking
    local progress
    progress=$(echo "$ccpm_data" | jq -r '.progress // empty')
    if [[ -n "$progress" ]]; then
        if transform_percentage_ccpm_to_jira "$progress" >/dev/null; then
            echo "PASS: Progress custom field validation"
        else
            echo "FAIL: Progress custom field validation failed" >&2
            return 1
        fi
    fi
    
    echo "PASS: All custom fields validated successfully"
    return 0
}

# =============================================================================
# Bulk Validation Functions
# =============================================================================

#' Validate multiple epics in batch
#' Usage: validate_multiple_epics EPICS_JSON
#' Returns: Validation summary report
validate_multiple_epics() {
    local epics_json="$1"
    
    if [[ -z "$epics_json" ]]; then
        echo "Error: Epics JSON array is required" >&2
        return 1
    fi
    
    echo "Starting bulk epic validation..."
    
    local total_epics passed_epics failed_epics
    total_epics=$(echo "$epics_json" | jq 'length')
    passed_epics=0
    failed_epics=0
    
    local validation_results="[]"
    
    while read -r epic_json; do
        [[ -z "$epic_json" || "$epic_json" == "null" ]] && continue
        
        local epic_id jira_key
        epic_id=$(echo "$epic_json" | jq -r '.id // "unknown"')
        jira_key=$(echo "$epic_json" | jq -r '.jira_key // empty')
        
        if [[ -z "$jira_key" ]]; then
            echo "WARNING: Epic $epic_id has no Jira key, skipping validation"
            continue
        fi
        
        echo "Validating epic $epic_id ($jira_key)..."
        
        local result_entry
        if validate_epic_consistency "$epic_json" "$jira_key"; then
            passed_epics=$((passed_epics + 1))
            result_entry=$(jq -n --arg id "$epic_id" --arg key "$jira_key" \
                '{"epic_id": $id, "jira_key": $key, "status": "passed"}')
        else
            failed_epics=$((failed_epics + 1))
            result_entry=$(jq -n --arg id "$epic_id" --arg key "$jira_key" \
                '{"epic_id": $id, "jira_key": $key, "status": "failed"}')
        fi
        
        validation_results=$(echo "$validation_results" | jq --argjson entry "$result_entry" '. + [$entry]')
        
    done < <(echo "$epics_json" | jq -c '.[]?')
    
    # Create summary report
    local summary_report
    summary_report=$(jq -n \
        --arg total "$total_epics" \
        --arg passed "$passed_epics" \
        --arg failed "$failed_epics" \
        --argjson results "$validation_results" \
        '{
            "summary": {
                "total_epics": ($total | tonumber),
                "passed": ($passed | tonumber),
                "failed": ($failed | tonumber),
                "success_rate": (($passed | tonumber) / ($total | tonumber) * 100 | floor)
            },
            "details": $results
        }')
    
    echo "Epic validation complete: $passed_epics/$total_epics passed"
    echo "$summary_report"
    
    if [[ $failed_epics -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}

#' Validate multiple tasks in batch
#' Usage: validate_multiple_tasks TASKS_JSON
#' Returns: Validation summary report
validate_multiple_tasks() {
    local tasks_json="$1"
    
    if [[ -z "$tasks_json" ]]; then
        echo "Error: Tasks JSON array is required" >&2
        return 1
    fi
    
    echo "Starting bulk task validation..."
    
    local total_tasks passed_tasks failed_tasks
    total_tasks=$(echo "$tasks_json" | jq 'length')
    passed_tasks=0
    failed_tasks=0
    
    local validation_results="[]"
    
    while read -r task_json; do
        [[ -z "$task_json" || "$task_json" == "null" ]] && continue
        
        local task_id jira_key
        task_id=$(echo "$task_json" | jq -r '.id // "unknown"')
        jira_key=$(echo "$task_json" | jq -r '.jira_key // empty')
        
        if [[ -z "$jira_key" ]]; then
            echo "WARNING: Task $task_id has no Jira key, skipping validation"
            continue
        fi
        
        echo "Validating task $task_id ($jira_key)..."
        
        local result_entry
        if validate_task_consistency "$task_json" "$jira_key"; then
            passed_tasks=$((passed_tasks + 1))
            result_entry=$(jq -n --arg id "$task_id" --arg key "$jira_key" \
                '{"task_id": $id, "jira_key": $key, "status": "passed"}')
        else
            failed_tasks=$((failed_tasks + 1))
            result_entry=$(jq -n --arg id "$task_id" --arg key "$jira_key" \
                '{"task_id": $id, "jira_key": $key, "status": "failed"}')
        fi
        
        validation_results=$(echo "$validation_results" | jq --argjson entry "$result_entry" '. + [$entry]')
        
    done < <(echo "$tasks_json" | jq -c '.[]?')
    
    # Create summary report
    local summary_report
    summary_report=$(jq -n \
        --arg total "$total_tasks" \
        --arg passed "$passed_tasks" \
        --arg failed "$failed_tasks" \
        --argjson results "$validation_results" \
        '{
            "summary": {
                "total_tasks": ($total | tonumber),
                "passed": ($passed | tonumber), 
                "failed": ($failed | tonumber),
                "success_rate": (($passed | tonumber) / ($total | tonumber) * 100 | floor)
            },
            "details": $results
        }')
    
    echo "Task validation complete: $passed_tasks/$total_tasks passed"
    echo "$summary_report"
    
    if [[ $failed_tasks -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# Export Functions
# =============================================================================

# Export validation functions for use by test scripts and validation commands
export -f validate_epic_consistency
export -f validate_task_consistency
export -f validate_epic_task_relationships
export -f validate_field_mappings
export -f validate_custom_fields
export -f validate_multiple_epics
export -f validate_multiple_tasks

echo "Jira Validation Library loaded successfully" >&2