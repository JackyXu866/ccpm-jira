#!/bin/bash
set -euo pipefail

# =============================================================================
# Jira Task Operations Library
# =============================================================================
# This library provides high-level CRUD operations for Jira issues/tasks.
# It builds upon the MCP adapter and field mapping layers to provide
# a complete task lifecycle management interface.
#
# Author: Claude Code - Stream B Implementation  
# Version: 1.0.0
# =============================================================================

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/jira-fields.sh"
source "${SCRIPT_DIR}/../scripts/adapters/jira-adapter.sh"

# Ensure required tools are available
if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required for task operations" >&2
    exit 1
fi

# =============================================================================
# Task Creation Operations
# =============================================================================

#' Create a new task/issue in Jira from CCPM data
#' Usage: create_jira_task TASK_NAME TASK_DATA_JSON [ISSUE_TYPE] [PROJECT_KEY]
#' Returns: Jira issue key on success
create_jira_task() {
    local task_name="$1"
    local task_data="$2"
    local issue_type="${3:-Task}"
    local project_key="${4:-}"
    
    if [[ -z "$task_name" || -z "$task_data" ]]; then
        echo "Error: Task name and data are required for create_jira_task" >&2
        return 1
    fi
    
    # Validate CCPM task data using Stream C validation
    if ! validate_ccpm_task "$task_data"; then
        echo "Error: Invalid CCPM task data" >&2
        return 1
    fi
    
    # Prepare task for Jira using Stream C mapping
    local jira_request
    if ! jira_request=$(prepare_task_for_jira "$task_name" "$task_data" "$issue_type"); then
        echo "Error: Failed to prepare task for Jira" >&2
        return 1
    fi
    
    # Extract fields and metadata from the prepared request
    local summary
    summary=$(echo "$jira_request" | jq -r '.summary')
    
    local description
    description=$(echo "$jira_request" | jq -r '.fields.description // ""')
    
    local issue_type_name
    issue_type_name=$(echo "$jira_request" | jq -r '.issueTypeName')
    
    # Create the issue using MCP adapter
    local result
    if [[ -n "$project_key" ]]; then
        result=$(create_jira_issue "$project_key" "$issue_type_name" "$summary" "$description")
    else
        result=$(create_jira_issue "$issue_type_name" "$summary" "$description")
    fi
    
    if [[ $? -eq 0 && -n "$result" ]]; then
        echo "Task created successfully: $result"
        echo "$result"
        return 0
    else
        echo "Error: Failed to create task in Jira" >&2
        return 1
    fi
}

#' Create a task with custom fields and additional metadata
#' Usage: create_jira_task_with_metadata TASK_NAME TASK_DATA_JSON METADATA_JSON [ISSUE_TYPE] [PROJECT_KEY]
#' Returns: Jira issue key on success
create_jira_task_with_metadata() {
    local task_name="$1"
    local task_data="$2" 
    local metadata_json="${3:-{}}"
    local issue_type="${4:-Task}"
    local project_key="${5:-}"
    
    # Merge task data with metadata
    local enhanced_data
    enhanced_data=$(echo "$task_data" | jq --argjson meta "$metadata_json" '. + $meta')
    
    # Use standard creation function
    create_jira_task "$task_name" "$enhanced_data" "$issue_type" "$project_key"
}

# =============================================================================
# Task Reading Operations
# =============================================================================

#' Get a task from Jira and convert to CCPM format
#' Usage: get_jira_task ISSUE_KEY_OR_ID
#' Returns: CCPM-formatted task JSON
get_jira_task() {
    local issue_key="$1"
    
    if [[ -z "$issue_key" ]]; then
        echo "Error: Issue key/ID is required for get_jira_task" >&2
        return 1
    fi
    
    # Fetch issue from Jira using MCP adapter
    local jira_response
    if ! jira_response=$(get_jira_issue "$issue_key"); then
        echo "Error: Failed to fetch task from Jira" >&2
        return 1
    fi
    
    # Convert Jira response to CCPM format using Stream C processing
    local ccpm_task
    if ! ccmp_task=$(process_jira_task_response "$jira_response"); then
        echo "Error: Failed to process Jira task response" >&2
        return 1
    fi
    
    # Add issue key and metadata
    local enhanced_task
    enhanced_task=$(echo "$ccpm_task" | jq --arg key "$issue_key" \
        '. + {
            "jira_key": $key,
            "source": "jira",
            "synced_at": (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
        }')
    
    echo "$enhanced_task"
}

#' Get multiple tasks using JQL query
#' Usage: search_jira_tasks JQL_QUERY [MAX_RESULTS]
#' Returns: Array of CCPM-formatted tasks
search_jira_tasks() {
    local jql_query="$1"
    local max_results="${2:-50}"
    
    if [[ -z "$jql_query" ]]; then
        echo "Error: JQL query is required for search_jira_tasks" >&2
        return 1
    fi
    
    # Search issues using MCP adapter
    local search_results
    if ! search_results=$(search_jira_issues "$jql_query" "$max_results"); then
        echo "Error: Failed to search Jira tasks" >&2
        return 1
    fi
    
    # Process each issue in the results
    local ccpm_tasks="[]"
    local issues
    issues=$(echo "$search_results" | jq -r '.issues[]')
    
    while read -r issue_json; do
        [[ -z "$issue_json" || "$issue_json" == "null" ]] && continue
        
        # Process individual issue
        local ccpm_task
        if ccpm_task=$(process_jira_task_response "$issue_json"); then
            local issue_key
            issue_key=$(echo "$issue_json" | jq -r '.key // .id')
            
            # Add metadata
            local enhanced_task
            enhanced_task=$(echo "$ccpm_task" | jq --arg key "$issue_key" \
                '. + {
                    "jira_key": $key,
                    "source": "jira",
                    "synced_at": (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
                }')
            
            # Add to results array
            ccpm_tasks=$(echo "$ccpm_tasks" | jq --argjson task "$enhanced_task" '. + [$task]')
        fi
    done < <(echo "$search_results" | jq -c '.issues[]?')
    
    echo "$ccpm_tasks"
}

# =============================================================================
# Task Update Operations
# =============================================================================

#' Update a task in Jira with CCPM data
#' Usage: update_jira_task ISSUE_KEY UPDATED_TASK_DATA_JSON
#' Returns: Success/failure status
update_jira_task() {
    local issue_key="$1"
    local updated_data="$2"
    
    if [[ -z "$issue_key" || -z "$updated_data" ]]; then
        echo "Error: Issue key and updated data are required for update_jira_task" >&2
        return 1
    fi
    
    # Validate updated task data
    if ! validate_ccpm_task "$updated_data"; then
        echo "Error: Invalid updated task data" >&2
        return 1
    fi
    
    # Map CCPM data to Jira fields using Stream C
    local jira_fields
    if ! jira_fields=$(map_ccpm_task_to_jira "$updated_data"); then
        echo "Error: Failed to map task data to Jira fields" >&2
        return 1
    fi
    
    # Update issue using MCP adapter
    if update_jira_issue "$issue_key" "$jira_fields"; then
        echo "Task $issue_key updated successfully"
        return 0
    else
        echo "Error: Failed to update task in Jira" >&2
        return 1
    fi
}

#' Update specific fields of a task
#' Usage: update_jira_task_fields ISSUE_KEY FIELD_UPDATES_JSON
#' Example: update_jira_task_fields "PROJ-123" '{"status":"in-progress","progress":"50%"}'
#' Returns: Success/failure status
update_jira_task_fields() {
    local issue_key="$1"
    local field_updates="$2"
    
    if [[ -z "$issue_key" || -z "$field_updates" ]]; then
        echo "Error: Issue key and field updates are required" >&2
        return 1
    fi
    
    # Get current task data first
    local current_task
    if ! current_task=$(get_jira_task "$issue_key"); then
        echo "Error: Failed to fetch current task data" >&2
        return 1
    fi
    
    # Merge field updates with current data
    local updated_task
    updated_task=$(echo "$current_task" | jq --argjson updates "$field_updates" '. + $updates')
    
    # Update the task
    update_jira_task "$issue_key" "$updated_task"
}

# =============================================================================
# Task State Management Operations
# =============================================================================

#' Transition a task to a new status
#' Usage: transition_jira_task_status ISSUE_KEY NEW_STATUS [ADDITIONAL_FIELDS]
#' Returns: Success/failure status
transition_jira_task_status() {
    local issue_key="$1"
    local new_status="$2"
    local additional_fields="${3:-{}}"
    
    if [[ -z "$issue_key" || -z "$new_status" ]]; then
        echo "Error: Issue key and new status are required" >&2
        return 1
    fi
    
    # Transform CCPM status to Jira status
    local jira_status
    jira_status=$(transform_status_ccpm_to_jira "$new_status")
    
    # Get available transitions for the issue
    local transitions
    if ! transitions=$(get_jira_issue_transitions "$issue_key"); then
        echo "Error: Failed to get available transitions" >&2
        return 1
    fi
    
    # Find transition ID for target status
    local transition_id
    transition_id=$(echo "$transitions" | jq -r --arg status "$jira_status" \
        '.transitions[]? | select(.to.name == $status) | .id // empty' | head -n1)
    
    if [[ -z "$transition_id" ]]; then
        echo "Error: No transition available to status '$jira_status'" >&2
        echo "Available transitions:" >&2
        echo "$transitions" | jq -r '.transitions[]?.to.name' >&2
        return 1
    fi
    
    # Execute transition
    if transition_jira_issue "$issue_key" "$transition_id" "$additional_fields"; then
        echo "Task $issue_key transitioned to $new_status successfully"
        return 0
    else
        echo "Error: Failed to transition task to $new_status" >&2
        return 1
    fi
}

#' Get available status transitions for a task
#' Usage: get_jira_task_status_options ISSUE_KEY
#' Returns: JSON array of available status options in CCPM format
get_jira_task_status_options() {
    local issue_key="$1"
    
    if [[ -z "$issue_key" ]]; then
        echo "Error: Issue key is required" >&2
        return 1
    fi
    
    # Get transitions from Jira
    local transitions
    if ! transitions=$(get_jira_issue_transitions "$issue_key"); then
        echo "Error: Failed to get transitions" >&2
        return 1
    fi
    
    # Convert to CCPM status options
    local ccpm_options="[]"
    while read -r jira_status; do
        [[ -z "$jira_status" ]] && continue
        local ccpm_status
        ccpm_status=$(transform_status_jira_to_ccpm "$jira_status")
        ccpm_options=$(echo "$ccpm_options" | jq --arg status "$ccpm_status" '. + [$status]')
    done < <(echo "$transitions" | jq -r '.transitions[]?.to.name // empty')
    
    echo "$ccpm_options"
}

# =============================================================================
# Task Assignment Operations  
# =============================================================================

#' Assign a task to a user
#' Usage: assign_jira_task ISSUE_KEY ASSIGNEE_EMAIL_OR_ID
#' Returns: Success/failure status
assign_jira_task() {
    local issue_key="$1"
    local assignee="$2"
    
    if [[ -z "$issue_key" || -z "$assignee" ]]; then
        echo "Error: Issue key and assignee are required" >&2
        return 1
    fi
    
    # If assignee looks like email, look up account ID
    local account_id="$assignee"
    if [[ "$assignee" == *"@"* ]]; then
        local lookup_result
        if lookup_result=$(lookup_jira_account_id "$assignee"); then
            account_id=$(echo "$lookup_result" | jq -r '.accountId // empty' | head -n1)
            if [[ -z "$account_id" ]]; then
                echo "Error: Could not find account ID for $assignee" >&2
                return 1
            fi
        else
            echo "Error: Failed to lookup account ID for $assignee" >&2
            return 1
        fi
    fi
    
    # Update assignee field
    local assignee_update
    assignee_update=$(jq -n --arg id "$account_id" '{"assignee":{"accountId":$id}}')
    
    if update_jira_issue "$issue_key" "$assignee_update"; then
        echo "Task $issue_key assigned to $assignee successfully"
        return 0
    else
        echo "Error: Failed to assign task" >&2
        return 1
    fi
}

# =============================================================================
# Task Deletion/Archive Operations
# =============================================================================

#' Archive a task (transition to archived status or add archive label)
#' Usage: archive_jira_task ISSUE_KEY [ARCHIVE_REASON]
#' Returns: Success/failure status
archive_jira_task() {
    local issue_key="$1"
    local archive_reason="${2:-Archived via CCPM}"
    
    if [[ -z "$issue_key" ]]; then
        echo "Error: Issue key is required" >&2
        return 1
    fi
    
    # Try to transition to "Done" or "Closed" status
    if transition_jira_task_status "$issue_key" "completed"; then
        echo "Task $issue_key archived by transitioning to completed status"
    else
        echo "Could not transition to completed status, adding archive comment instead" >&2
    fi
    
    # Add archive comment
    if add_jira_comment "$issue_key" "**ARCHIVED**: $archive_reason"; then
        echo "Archive comment added to task $issue_key"
        return 0
    else
        echo "Warning: Failed to add archive comment" >&2
        return 1
    fi
}

# =============================================================================
# Bulk Task Operations
# =============================================================================

#' Create multiple tasks from CCPM data
#' Usage: bulk_create_jira_tasks TASKS_JSON_ARRAY [ISSUE_TYPE] [PROJECT_KEY]
#' Returns: JSON array of created issue keys
bulk_create_jira_tasks() {
    local tasks_array="$1"
    local issue_type="${2:-Task}"
    local project_key="${3:-}"
    
    if [[ -z "$tasks_array" ]]; then
        echo "Error: Tasks array is required" >&2
        return 1
    fi
    
    local results="[]"
    local task_count=0
    
    while read -r task_json; do
        [[ -z "$task_json" || "$task_json" == "null" ]] && continue
        
        task_count=$((task_count + 1))
        echo "Creating task $task_count..." >&2
        
        local task_name
        task_name=$(echo "$task_json" | jq -r '.name // "Unnamed Task"')
        
        local issue_key
        if issue_key=$(create_jira_task "$task_name" "$task_json" "$issue_type" "$project_key"); then
            local result_entry
            result_entry=$(jq -n --arg name "$task_name" --arg key "$issue_key" \
                '{"name": $name, "jira_key": $key, "status": "created"}')
            results=$(echo "$results" | jq --argjson entry "$result_entry" '. + [$entry]')
        else
            local error_entry
            error_entry=$(jq -n --arg name "$task_name" \
                '{"name": $name, "jira_key": null, "status": "error"}')
            results=$(echo "$results" | jq --argjson entry "$error_entry" '. + [$entry]')
        fi
    done < <(echo "$tasks_array" | jq -c '.[]?')
    
    echo "$results"
}

#' Update multiple tasks with status changes
#' Usage: bulk_update_task_status ISSUE_KEYS_ARRAY NEW_STATUS
#' Returns: JSON array of update results
bulk_update_task_status() {
    local issue_keys_array="$1"
    local new_status="$2"
    
    if [[ -z "$issue_keys_array" || -z "$new_status" ]]; then
        echo "Error: Issue keys array and new status are required" >&2
        return 1
    fi
    
    local results="[]"
    
    while read -r issue_key; do
        [[ -z "$issue_key" ]] && continue
        
        echo "Updating $issue_key to $new_status..." >&2
        
        local result_entry
        if transition_jira_task_status "$issue_key" "$new_status"; then
            result_entry=$(jq -n --arg key "$issue_key" \
                '{"jira_key": $key, "status": "updated"}')
        else
            result_entry=$(jq -n --arg key "$issue_key" \
                '{"jira_key": $key, "status": "error"}')
        fi
        
        results=$(echo "$results" | jq --argjson entry "$result_entry" '. + [$entry]')
        
    done < <(echo "$issue_keys_array" | jq -r '.[]?')
    
    echo "$results"
}

# =============================================================================
# Export Functions
# =============================================================================

# Export all main CRUD functions for use by other scripts
export -f create_jira_task
export -f create_jira_task_with_metadata
export -f get_jira_task
export -f search_jira_tasks
export -f update_jira_task
export -f update_jira_task_fields
export -f transition_jira_task_status
export -f get_jira_task_status_options
export -f assign_jira_task
export -f archive_jira_task
export -f bulk_create_jira_tasks
export -f bulk_update_task_status

# Validate dependencies on load
if ! load_field_mapping_config; then
    echo "Warning: Field mapping configuration not available" >&2
fi

echo "Jira Task Operations Library loaded successfully" >&2