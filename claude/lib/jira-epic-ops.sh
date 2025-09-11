#!/bin/bash
set -euo pipefail

# =============================================================================
# Jira Epic Operations Library
# =============================================================================
# This library provides comprehensive CRUD operations for epics, implementing
# the business logic layer for Stream A. It combines field mapping functions
# from Stream C with MCP adapter calls to provide high-level epic operations.
#
# Author: Claude Code - Stream A Implementation
# Version: 1.0.0
# =============================================================================

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/jira-fields.sh"
source "${SCRIPT_DIR}/../scripts/adapters/jira-adapter.sh"

# =============================================================================
# Core Epic CRUD Operations
# =============================================================================

#' Create a new epic in Jira from CCPM data
#' Usage: create_jira_epic_from_ccpm EPIC_NAME EPIC_DATA_JSON [PROJECT_KEY]
#' Returns: Jira epic key on success
create_jira_epic_from_ccpm() {
    local epic_name="$1"
    local epic_data_json="$2"
    local project_key="${3:-}"
    
    if [[ -z "$epic_name" || -z "$epic_data_json" ]]; then
        echo "Error: Epic name and data JSON are required" >&2
        return 1
    fi
    
    echo "Creating epic '$epic_name' in Jira..." >&2
    
    # Validate CCPM epic data
    if ! validate_ccpm_epic "$epic_data_json"; then
        echo "Error: Invalid CCPM epic data" >&2
        return 1
    fi
    
    # Prepare epic data for Jira using Stream C functions
    local jira_request
    if ! jira_request=$(prepare_epic_for_jira "$epic_name" "$epic_data_json"); then
        echo "Error: Failed to prepare epic data for Jira" >&2
        return 1
    fi
    
    # Extract fields and build creation parameters
    local summary
    summary=$(echo "$jira_request" | jq -r '.summary')
    
    local description
    description=$(echo "$jira_request" | jq -r '.fields.description // ""')
    
    # Create the epic using the adapter
    local epic_key
    if epic_key=$(create_jira_epic "$project_key" "$epic_name" "$summary" "$description"); then
        echo "✅ Epic created successfully: $epic_key" >&2
        
        # Apply additional fields if any
        local additional_fields
        additional_fields=$(echo "$jira_request" | jq -r '.fields // {}' | jq 'del(.description)')
        
        if [[ "$additional_fields" != "{}" ]]; then
            echo "Applying additional fields..." >&2
            update_jira_issue "$epic_key" "$additional_fields" || {
                echo "Warning: Epic created but some fields could not be updated" >&2
            }
        fi
        
        echo "$epic_key"
        return 0
    else
        echo "Error: Failed to create epic in Jira" >&2
        return 1
    fi
}

#' Read an epic from Jira and convert to CCPM format
#' Usage: read_jira_epic_to_ccpm EPIC_KEY
#' Returns: CCPM-formatted epic JSON
read_jira_epic_to_ccpm() {
    local epic_key="$1"
    
    if [[ -z "$epic_key" ]]; then
        echo "Error: Epic key is required" >&2
        return 1
    fi
    
    echo "Reading epic '$epic_key' from Jira..." >&2
    
    # Get epic data from Jira
    local jira_response
    if ! jira_response=$(get_jira_issue "$epic_key"); then
        echo "Error: Failed to read epic from Jira" >&2
        return 1
    fi
    
    # Convert to CCPM format using Stream C functions
    local ccpm_epic
    if ! ccmp_epic=$(process_jira_epic_response "$jira_response"); then
        echo "Error: Failed to convert Jira epic to CCPM format" >&2
        return 1
    fi
    
    echo "✅ Epic read successfully from Jira" >&2
    echo "$ccmp_epic"
}

#' Update an existing epic in Jira from CCPM data
#' Usage: update_jira_epic_from_ccpm EPIC_KEY EPIC_DATA_JSON [FORCE_UPDATE]
#' Returns: Success/failure status
update_jira_epic_from_ccpm() {
    local epic_key="$1"
    local epic_data_json="$2"
    local force_update="${3:-false}"
    
    if [[ -z "$epic_key" || -z "$epic_data_json" ]]; then
        echo "Error: Epic key and data JSON are required" >&2
        return 1
    fi
    
    echo "Updating epic '$epic_key' in Jira..." >&2
    
    # Validate CCPM epic data
    if ! validate_ccpm_epic "$epic_data_json"; then
        echo "Error: Invalid CCPM epic data" >&2
        return 1
    fi
    
    # If not forcing update, check for conflicts
    if [[ "$force_update" != "true" ]]; then
        if ! check_epic_update_conflicts "$epic_key" "$epic_data_json"; then
            echo "Error: Update conflicts detected. Use FORCE_UPDATE=true to override" >&2
            return 1
        fi
    fi
    
    # Get epic name from data
    local epic_name
    epic_name=$(echo "$epic_data_json" | jq -r '.name // .title // ""')
    
    # Prepare update data for Jira
    local jira_request
    if ! jira_request=$(prepare_epic_for_jira "$epic_name" "$epic_data_json"); then
        echo "Error: Failed to prepare epic data for Jira" >&2
        return 1
    fi
    
    # Extract fields for update
    local update_fields
    update_fields=$(echo "$jira_request" | jq '.fields')
    
    # Update the epic
    if update_jira_issue "$epic_key" "$update_fields"; then
        echo "✅ Epic updated successfully: $epic_key" >&2
        return 0
    else
        echo "Error: Failed to update epic in Jira" >&2
        return 1
    fi
}

#' Delete (archive) an epic in Jira
#' Usage: delete_jira_epic EPIC_KEY [ARCHIVE_ONLY]
#' Returns: Success/failure status
delete_jira_epic() {
    local epic_key="$1"
    local archive_only="${2:-true}"
    
    if [[ -z "$epic_key" ]]; then
        echo "Error: Epic key is required" >&2
        return 1
    fi
    
    echo "Deleting epic '$epic_key' from Jira..." >&2
    
    # Check if epic has active issues
    local linked_issues
    if linked_issues=$(get_epic_linked_issues "$epic_key"); then
        local issue_count
        issue_count=$(echo "$linked_issues" | jq '.total // 0')
        
        if [[ "$issue_count" -gt 0 ]]; then
            echo "Warning: Epic has $issue_count linked issues" >&2
            if [[ "$archive_only" != "false" ]]; then
                echo "Archiving epic instead of deleting..." >&2
                return archive_epic "$epic_key"
            fi
        fi
    fi
    
    # For now, we'll archive epics instead of deleting them
    # Real deletion would require MCP tool support
    if [[ "$archive_only" == "true" ]]; then
        archive_epic "$epic_key"
    else
        echo "Error: Hard epic deletion not supported yet" >&2
        echo "Use archive functionality instead" >&2
        return 1
    fi
}

# =============================================================================
# Epic-Specific Operations
# =============================================================================

#' Get epic progress (percentage of completed issues)
#' Usage: get_epic_progress EPIC_KEY
#' Returns: Progress percentage and details
get_epic_progress() {
    local epic_key="$1"
    
    if [[ -z "$epic_key" ]]; then
        echo "Error: Epic key is required" >&2
        return 1
    fi
    
    echo "Calculating progress for epic '$epic_key'..." >&2
    
    # Search for issues in this epic
    local jql_query="\"Epic Link\" = $epic_key"
    local issues_result
    
    if ! issues_result=$(search_jira_issues "$jql_query" 100); then
        echo "Error: Failed to search epic issues" >&2
        return 1
    fi
    
    local total_issues
    total_issues=$(echo "$issues_result" | jq '.total // 0')
    
    if [[ "$total_issues" -eq 0 ]]; then
        echo "Epic has no linked issues" >&2
        echo '{"total": 0, "completed": 0, "progress": 0, "status": "No Issues"}'
        return 0
    fi
    
    # Count completed issues (Done, Closed, Resolved statuses)
    local completed_count=0
    local issues
    issues=$(echo "$issues_result" | jq -r '.issues[]')
    
    while IFS= read -r issue; do
        [[ -z "$issue" ]] && continue
        local status
        status=$(echo "$issue" | jq -r '.fields.status.name // ""')
        case "$status" in
            "Done"|"Closed"|"Resolved"|"Complete")
                ((completed_count++))
                ;;
        esac
    done < <(echo "$issues")
    
    # Calculate progress percentage
    local progress_pct
    if [[ "$total_issues" -gt 0 ]]; then
        progress_pct=$((completed_count * 100 / total_issues))
    else
        progress_pct=0
    fi
    
    # Determine overall status
    local epic_status="In Progress"
    if [[ "$completed_count" -eq "$total_issues" ]]; then
        epic_status="Complete"
    elif [[ "$completed_count" -eq 0 ]]; then
        epic_status="Not Started"
    fi
    
    local progress_json
    progress_json=$(jq -n \
        --arg total "$total_issues" \
        --arg completed "$completed_count" \
        --arg progress "$progress_pct" \
        --arg status "$epic_status" \
        '{
            total: ($total | tonumber),
            completed: ($completed | tonumber),
            progress: ($progress | tonumber),
            status: $status
        }')
    
    echo "✅ Epic progress calculated: $progress_pct%" >&2
    echo "$progress_json"
}

#' Get issues linked to an epic
#' Usage: get_epic_linked_issues EPIC_KEY [MAX_RESULTS]
#' Returns: JSON array of linked issues
get_epic_linked_issues() {
    local epic_key="$1"
    local max_results="${2:-100}"
    
    if [[ -z "$epic_key" ]]; then
        echo "Error: Epic key is required" >&2
        return 1
    fi
    
    local jql_query="\"Epic Link\" = $epic_key ORDER BY created ASC"
    search_jira_issues "$jql_query" "$max_results"
}

#' Count sub-tasks and issues in an epic
#' Usage: count_epic_items EPIC_KEY
#' Returns: JSON with counts by issue type and status
count_epic_items() {
    local epic_key="$1"
    
    if [[ -z "$epic_key" ]]; then
        echo "Error: Epic key is required" >&2
        return 1
    fi
    
    echo "Counting items in epic '$epic_key'..." >&2
    
    local issues_result
    if ! issues_result=$(get_epic_linked_issues "$epic_key" 200); then
        echo "Error: Failed to get epic issues" >&2
        return 1
    fi
    
    local total_count
    total_count=$(echo "$issues_result" | jq '.total // 0')
    
    # Initialize counters
    local story_count=0 task_count=0 subtask_count=0 bug_count=0
    local todo_count=0 inprogress_count=0 done_count=0
    
    # Process each issue
    while IFS= read -r issue; do
        [[ -z "$issue" ]] && continue
        
        local issue_type
        issue_type=$(echo "$issue" | jq -r '.fields.issuetype.name // ""')
        
        local status
        status=$(echo "$issue" | jq -r '.fields.status.name // ""')
        
        # Count by issue type
        case "$issue_type" in
            "Story") ((story_count++)) ;;
            "Task") ((task_count++)) ;;
            "Sub-task"|"Subtask") ((subtask_count++)) ;;
            "Bug") ((bug_count++)) ;;
        esac
        
        # Count by status
        case "$status" in
            "To Do"|"Open"|"Backlog") ((todo_count++)) ;;
            "In Progress"|"Review"|"Testing") ((inprogress_count++)) ;;
            "Done"|"Closed"|"Resolved") ((done_count++)) ;;
        esac
        
    done < <(echo "$issues_result" | jq -c '.issues[]? // empty')
    
    # Build result JSON
    local count_json
    count_json=$(jq -n \
        --arg total "$total_count" \
        --arg stories "$story_count" \
        --arg tasks "$task_count" \
        --arg subtasks "$subtask_count" \
        --arg bugs "$bug_count" \
        --arg todo "$todo_count" \
        --arg inprogress "$inprogress_count" \
        --arg done "$done_count" \
        '{
            total: ($total | tonumber),
            by_type: {
                stories: ($stories | tonumber),
                tasks: ($tasks | tonumber), 
                subtasks: ($subtasks | tonumber),
                bugs: ($bugs | tonumber)
            },
            by_status: {
                todo: ($todo | tonumber),
                in_progress: ($inprogress | tonumber),
                done: ($done | tonumber)
            }
        }')
    
    echo "✅ Epic items counted" >&2
    echo "$count_json"
}

# =============================================================================
# Bidirectional Sync Operations
# =============================================================================

#' Sync epic from CCPM to Jira (push changes)
#' Usage: sync_epic_to_jira EPIC_NAME EPIC_DATA_JSON [PROJECT_KEY] [UPDATE_MODE]
#' UPDATE_MODE: create, update, or auto (default: auto)
#' Returns: Epic key and sync status
sync_epic_to_jira() {
    local epic_name="$1"
    local epic_data_json="$2"
    local project_key="${3:-}"
    local update_mode="${4:-auto}"
    
    if [[ -z "$epic_name" || -z "$epic_data_json" ]]; then
        echo "Error: Epic name and data are required for sync" >&2
        return 1
    fi
    
    echo "Syncing epic '$epic_name' to Jira..." >&2
    
    # Check if epic already exists in Jira
    local existing_epic_key=""
    if [[ "$update_mode" == "auto" || "$update_mode" == "update" ]]; then
        existing_epic_key=$(find_epic_by_name "$epic_name" "$project_key")
    fi
    
    local result_key=""
    
    if [[ -n "$existing_epic_key" && "$update_mode" != "create" ]]; then
        # Update existing epic
        echo "Found existing epic: $existing_epic_key" >&2
        if update_jira_epic_from_ccpm "$existing_epic_key" "$epic_data_json"; then
            result_key="$existing_epic_key"
            echo "✅ Epic updated in Jira: $result_key" >&2
        else
            echo "Error: Failed to update existing epic" >&2
            return 1
        fi
    else
        # Create new epic
        if result_key=$(create_jira_epic_from_ccpm "$epic_name" "$epic_data_json" "$project_key"); then
            echo "✅ Epic created in Jira: $result_key" >&2
        else
            echo "Error: Failed to create epic in Jira" >&2
            return 1
        fi
    fi
    
    # Return sync result
    local sync_result
    sync_result=$(jq -n \
        --arg key "$result_key" \
        --arg action "$([ -n "$existing_epic_key" ] && echo "updated" || echo "created")" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            epic_key: $key,
            action: $action,
            timestamp: $timestamp,
            success: true
        }')
    
    echo "$sync_result"
}

#' Sync epic from Jira to CCPM (pull changes)
#' Usage: sync_epic_from_jira EPIC_KEY
#' Returns: CCPM-formatted epic data with sync metadata
sync_epic_from_jira() {
    local epic_key="$1"
    
    if [[ -z "$epic_key" ]]; then
        echo "Error: Epic key is required for sync" >&2
        return 1
    fi
    
    echo "Syncing epic '$epic_key' from Jira..." >&2
    
    # Read epic data from Jira
    local ccpm_epic
    if ! ccpm_epic=$(read_jira_epic_to_ccpm "$epic_key"); then
        echo "Error: Failed to read epic from Jira" >&2
        return 1
    fi
    
    # Add sync metadata
    local sync_result
    sync_result=$(echo "$ccpm_epic" | jq \
        --arg key "$epic_key" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '. + {
            jira_key: $key,
            last_synced: $timestamp,
            sync_direction: "from_jira"
        }')
    
    echo "✅ Epic synced from Jira" >&2
    echo "$sync_result"
}

# =============================================================================
# Utility Functions
# =============================================================================

#' Find epic by name in a project
#' Usage: find_epic_by_name EPIC_NAME [PROJECT_KEY]
#' Returns: Epic key if found, empty if not found
find_epic_by_name() {
    local epic_name="$1"
    local project_key="${2:-}"
    
    local jql_query="type = Epic"
    if [[ -n "$project_key" ]]; then
        jql_query="$jql_query AND project = $project_key"
    fi
    jql_query="$jql_query AND summary ~ \"$epic_name\""
    
    local search_result
    if search_result=$(search_jira_issues "$jql_query" 10); then
        # Get the first matching epic key
        echo "$search_result" | jq -r '.issues[0].key // ""'
    else
        echo ""
    fi
}

#' Archive an epic by changing its status
#' Usage: archive_epic EPIC_KEY
#' Returns: Success/failure status
archive_epic() {
    local epic_key="$1"
    
    if [[ -z "$epic_key" ]]; then
        echo "Error: Epic key is required" >&2
        return 1
    fi
    
    echo "Archiving epic '$epic_key'..." >&2
    
    # Get available transitions
    local transitions
    if ! transitions=$(get_jira_issue_transitions "$epic_key"); then
        echo "Error: Failed to get epic transitions" >&2
        return 1
    fi
    
    # Look for Done, Closed, or Archive transition
    local transition_id
    transition_id=$(echo "$transitions" | jq -r '.transitions[] | select(.name | test("Done|Closed|Archive|Complete"; "i")) | .id' | head -1)
    
    if [[ -n "$transition_id" ]]; then
        if transition_jira_issue "$epic_key" "$transition_id"; then
            echo "✅ Epic archived successfully: $epic_key" >&2
            return 0
        else
            echo "Error: Failed to transition epic to archived state" >&2
            return 1
        fi
    else
        echo "Error: No archival transition found for epic" >&2
        echo "Available transitions:" >&2
        echo "$transitions" | jq -r '.transitions[].name' >&2
        return 1
    fi
}

#' Check for conflicts before updating an epic
#' Usage: check_epic_update_conflicts EPIC_KEY EPIC_DATA_JSON
#' Returns: Success if no conflicts, failure if conflicts detected
check_epic_update_conflicts() {
    local epic_key="$1"
    local epic_data_json="$2"
    
    if [[ -z "$epic_key" || -z "$epic_data_json" ]]; then
        echo "Error: Epic key and data are required for conflict check" >&2
        return 1
    fi
    
    echo "Checking for update conflicts on epic '$epic_key'..." >&2
    
    # Get current epic state from Jira
    local current_epic
    if ! current_epic=$(read_jira_epic_to_ccpm "$epic_key"); then
        echo "Warning: Could not read current epic state, skipping conflict check" >&2
        return 0
    fi
    
    # Compare key fields for conflicts
    local fields_to_check=("status" "updated" "version")
    
    for field in "${fields_to_check[@]}"; do
        local current_value
        current_value=$(echo "$current_epic" | jq -r ".$field // \"\"")
        
        local new_value
        new_value=$(echo "$epic_data_json" | jq -r ".$field // \"\"")
        
        if [[ -n "$current_value" && -n "$new_value" && "$current_value" != "$new_value" ]]; then
            # Check if this represents a conflict (e.g., newer timestamp)
            if [[ "$field" == "updated" ]]; then
                # Simple timestamp comparison (assumes ISO format)
                if [[ "$current_value" > "$new_value" ]]; then
                    echo "Conflict detected: Epic was updated in Jira after CCPM data ($current_value > $new_value)" >&2
                    return 1
                fi
            fi
        fi
    done
    
    echo "No conflicts detected" >&2
    return 0
}

#' Get epic metadata including progress and counts
#' Usage: get_epic_metadata EPIC_KEY
#' Returns: JSON with comprehensive epic metadata
get_epic_metadata() {
    local epic_key="$1"
    
    if [[ -z "$epic_key" ]]; then
        echo "Error: Epic key is required" >&2
        return 1
    fi
    
    echo "Getting metadata for epic '$epic_key'..." >&2
    
    # Get basic epic info
    local epic_info
    if ! epic_info=$(get_jira_issue "$epic_key"); then
        echo "Error: Failed to get epic info" >&2
        return 1
    fi
    
    # Get progress
    local progress
    if ! progress=$(get_epic_progress "$epic_key"); then
        progress='{"total": 0, "completed": 0, "progress": 0, "status": "Unknown"}'
    fi
    
    # Get item counts
    local counts
    if ! counts=$(count_epic_items "$epic_key"); then
        counts='{"total": 0, "by_type": {}, "by_status": {}}'
    fi
    
    # Combine all metadata
    local metadata
    metadata=$(jq -n \
        --arg key "$epic_key" \
        --argjson epic "$epic_info" \
        --argjson progress "$progress" \
        --argjson counts "$counts" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            epic_key: $key,
            basic_info: {
                summary: $epic.fields.summary,
                status: $epic.fields.status.name,
                created: $epic.fields.created,
                updated: $epic.fields.updated
            },
            progress: $progress,
            item_counts: $counts,
            metadata_generated: $timestamp
        }')
    
    echo "✅ Epic metadata collected" >&2
    echo "$metadata"
}

# =============================================================================
# Export Functions
# =============================================================================

# Export all public functions for use by other scripts
export -f create_jira_epic_from_ccpm
export -f read_jira_epic_to_ccpm
export -f update_jira_epic_from_ccpm
export -f delete_jira_epic
export -f get_epic_progress
export -f get_epic_linked_issues
export -f count_epic_items
export -f sync_epic_to_jira
export -f sync_epic_from_jira
export -f find_epic_by_name
export -f archive_epic
export -f get_epic_metadata

# Validate dependencies on load
if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required for epic operations" >&2
    exit 1
fi

# Initialize field mapping
if ! load_field_mapping_config >/dev/null 2>&1; then
    echo "Warning: Field mapping configuration not loaded" >&2
fi

echo "Jira Epic Operations library loaded successfully" >&2