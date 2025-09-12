#!/bin/bash
set -euo pipefail

# =============================================================================
# Issue Update Script
# =============================================================================
# This script provides a command-line interface for updating Jira issues/tasks
# with CCPM data. It supports field updates, status transitions, assignments,
# and bulk operations.
#
# Author: Claude Code - Stream B Implementation  
# Version: 1.0.0
# =============================================================================

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/jira-task-ops.sh"

# =============================================================================
# Input Validation Functions
# =============================================================================

#' Validate issue key format
validate_issue_key() {
    local issue_key="$1"
    
    if [[ -z "$issue_key" ]]; then
        echo "Error: Issue key is required" >&2
        return 1
    fi
    
    # Basic format validation (PROJECT-123 or numeric ID)
    if [[ ! "$issue_key" =~ ^[A-Z]+-[0-9]+$ && ! "$issue_key" =~ ^[0-9]+$ ]]; then
        echo "Warning: Issue key '$issue_key' may not be in expected format (PROJECT-123)" >&2
    fi
    
    return 0
}

#' Validate update data JSON
validate_update_data() {
    local update_data="$1"
    
    if [[ -z "$update_data" ]]; then
        echo "Error: Update data is required" >&2
        return 1
    fi
    
    # JSON validation
    if ! echo "$update_data" | jq . >/dev/null 2>&1; then
        echo "Error: Update data must be valid JSON" >&2
        return 1
    fi
    
    return 0
}

# =============================================================================
# Update Operation Functions
# =============================================================================

#' Update all fields of a task
update_task_complete() {
    local issue_key="$1"
    local update_data="$2"
    
    if ! validate_issue_key "$issue_key" || ! validate_update_data "$update_data"; then
        return 1
    fi
    
    echo "Updating task $issue_key with complete data..." >&2
    
    if update_jira_task "$issue_key" "$update_data"; then
        echo "Task updated successfully: $issue_key" >&2
        echo "$issue_key"
        return 0
    else
        echo "Error: Failed to update task" >&2
        return 1
    fi
}

#' Update specific fields of a task
update_task_fields() {
    local issue_key="$1"
    local field_updates="$2"
    
    if ! validate_issue_key "$issue_key" || ! validate_update_data "$field_updates"; then
        return 1
    fi
    
    echo "Updating specific fields for task $issue_key..." >&2
    
    if update_jira_task_fields "$issue_key" "$field_updates"; then
        echo "Task fields updated successfully: $issue_key" >&2
        echo "$issue_key"
        return 0
    else
        echo "Error: Failed to update task fields" >&2
        return 1
    fi
}

#' Update task status with transition
update_task_status() {
    local issue_key="$1"
    local new_status="$2"
    local additional_fields="${3:-{}}"
    
    if ! validate_issue_key "$issue_key"; then
        return 1
    fi
    
    if [[ -z "$new_status" ]]; then
        echo "Error: New status is required" >&2
        return 1
    fi
    
    echo "Transitioning task $issue_key to status '$new_status'..." >&2
    
    if transition_jira_task_status "$issue_key" "$new_status" "$additional_fields"; then
        echo "Task status updated successfully: $issue_key -> $new_status" >&2
        echo "$issue_key"
        return 0
    else
        echo "Error: Failed to update task status" >&2
        return 1
    fi
}

#' Update task assignment
update_task_assignee() {
    local issue_key="$1"
    local assignee="$2"
    
    if ! validate_issue_key "$issue_key"; then
        return 1
    fi
    
    if [[ -z "$assignee" ]]; then
        echo "Error: Assignee is required" >&2
        return 1
    fi
    
    echo "Assigning task $issue_key to $assignee..." >&2
    
    if assign_jira_task "$issue_key" "$assignee"; then
        echo "Task assigned successfully: $issue_key -> $assignee" >&2
        echo "$issue_key"
        return 0
    else
        echo "Error: Failed to assign task" >&2
        return 1
    fi
}

# =============================================================================
# Interactive Update Functions
# =============================================================================

#' Interactive update wizard
interactive_task_update() {
    echo "=== Jira Task Update Wizard ===" >&2
    echo >&2
    
    # Get issue key
    local issue_key=""
    while [[ -z "$issue_key" ]]; do
        echo -n "Issue key (PROJ-123): " >&2
        read -r issue_key
        if ! validate_issue_key "$issue_key"; then
            issue_key=""
        fi
    done
    
    # Get current task info
    echo "Fetching current task details..." >&2
    local current_task
    if ! current_task=$(get_jira_task "$issue_key"); then
        echo "Error: Failed to fetch current task details" >&2
        return 1
    fi
    
    local current_name
    current_name=$(echo "$current_task" | jq -r '.name // "Unknown"')
    
    local current_status
    current_status=$(echo "$current_task" | jq -r '.status // "unknown"')
    
    echo >&2
    echo "Current task: $current_name" >&2
    echo "Current status: $current_status" >&2
    echo >&2
    
    # Choose update type
    echo "What would you like to update?" >&2
    echo "1) Status transition" >&2
    echo "2) Task assignment" >&2  
    echo "3) Specific fields" >&2
    echo "4) Complete task data" >&2
    echo -n "Choice [1-4]: " >&2
    read -r choice
    
    case "$choice" in
        "1")
            interactive_status_update "$issue_key" "$current_status"
            ;;
        "2")
            interactive_assignment_update "$issue_key"
            ;;
        "3")
            interactive_fields_update "$issue_key"
            ;;
        "4")
            interactive_complete_update "$issue_key" "$current_task"
            ;;
        *)
            echo "Invalid choice" >&2
            return 1
            ;;
    esac
}

#' Interactive status update
interactive_status_update() {
    local issue_key="$1"
    local current_status="$2"
    
    echo "=== Status Update ===" >&2
    
    # Get available status options
    local status_options
    if status_options=$(get_jira_task_status_options "$issue_key"); then
        echo "Available status transitions:" >&2
        echo "$status_options" | jq -r '.[] | "  - " + .' >&2
    fi
    
    echo -n "New status: " >&2
    read -r new_status
    
    if [[ -z "$new_status" ]]; then
        echo "Status update cancelled" >&2
        return 1
    fi
    
    echo -n "Update status from '$current_status' to '$new_status'? [y/N]: " >&2
    read -r confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        update_task_status "$issue_key" "$new_status"
    else
        echo "Status update cancelled" >&2
        return 1
    fi
}

#' Interactive assignment update
interactive_assignment_update() {
    local issue_key="$1"
    
    echo "=== Assignment Update ===" >&2
    echo -n "Assignee email or account ID: " >&2
    read -r assignee
    
    if [[ -z "$assignee" ]]; then
        echo "Assignment update cancelled" >&2
        return 1
    fi
    
    echo -n "Assign task to '$assignee'? [y/N]: " >&2
    read -r confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        update_task_assignee "$issue_key" "$assignee"
    else
        echo "Assignment update cancelled" >&2
        return 1
    fi
}

#' Interactive fields update
interactive_fields_update() {
    local issue_key="$1"
    
    echo "=== Field Update ===" >&2
    echo "Enter field updates as JSON (e.g., {\"description\":\"New description\",\"priority\":\"High\"})" >&2
    echo -n "Field updates: " >&2
    read -r field_updates
    
    if [[ -z "$field_updates" ]]; then
        echo "Field update cancelled" >&2
        return 1
    fi
    
    echo "Field updates:" >&2
    echo "$field_updates" | jq -C . >&2
    echo -n "Apply these updates? [y/N]: " >&2
    read -r confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        update_task_fields "$issue_key" "$field_updates"
    else
        echo "Field update cancelled" >&2
        return 1
    fi
}

#' Interactive complete update
interactive_complete_update() {
    local issue_key="$1"
    local current_task="$2"
    
    echo "=== Complete Task Update ===" >&2
    echo "Current task data:" >&2
    echo "$current_task" | jq -C . >&2
    echo >&2
    echo "Enter complete updated task data as JSON:" >&2
    echo -n "Updated task data: " >&2
    read -r updated_data
    
    if [[ -z "$updated_data" ]]; then
        echo "Complete update cancelled" >&2
        return 1
    fi
    
    echo "Updated task data:" >&2
    echo "$updated_data" | jq -C . >&2
    echo -n "Apply this complete update? [y/N]: " >&2
    read -r confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        update_task_complete "$issue_key" "$updated_data"
    else
        echo "Complete update cancelled" >&2
        return 1
    fi
}

# =============================================================================
# Bulk Update Functions
# =============================================================================

#' Bulk status update from file
bulk_status_update_from_file() {
    local update_file="$1"
    local new_status="$2"
    
    if [[ ! -f "$update_file" ]]; then
        echo "Error: Update file not found: $update_file" >&2
        return 1
    fi
    
    if [[ -z "$new_status" ]]; then
        echo "Error: New status is required for bulk update" >&2
        return 1
    fi
    
    # Read issue keys from file (one per line or JSON array)
    local issue_keys
    if echo "$(<"$update_file")" | jq . >/dev/null 2>&1; then
        # JSON array format
        issue_keys=$(cat "$update_file")
    else
        # Plain text format, convert to JSON array
        issue_keys=$(cat "$update_file" | jq -R . | jq -s .)
    fi
    
    echo "Starting bulk status update to '$new_status'..." >&2
    
    local results
    if results=$(bulk_update_task_status "$issue_keys" "$new_status"); then
        echo "Bulk status update completed:" >&2
        echo "$results" | jq -C . >&2
        
        # Output updated issue keys for automation
        echo "$results" | jq -r '.[] | select(.status == "updated") | .jira_key'
        
        return 0
    else
        echo "Error: Bulk status update failed" >&2
        return 1
    fi
}

#' Sync task from CCPM file
sync_task_from_file() {
    local issue_key="$1"
    local ccpm_file="$2"
    
    if ! validate_issue_key "$issue_key"; then
        return 1
    fi
    
    if [[ ! -f "$ccpm_file" ]]; then
        echo "Error: CCPM file not found: $ccpm_file" >&2
        return 1
    fi
    
    # Parse CCPM file
    local task_data
    if [[ "$ccpm_file" == *.json ]]; then
        task_data=$(cat "$ccpm_file")
    elif [[ "$ccmp_file" == *.md ]]; then
        # Extract front matter as JSON
        task_data=$(awk '/^---$/{flag++; next} flag==1' "$ccpm_file" | head -n -1)
    else
        echo "Error: Unsupported file format. Use .json or .md files" >&2
        return 1
    fi
    
    echo "Syncing task $issue_key from $ccpm_file..." >&2
    
    if update_task_complete "$issue_key" "$task_data"; then
        echo "Task synced successfully" >&2
        return 0
    else
        echo "Error: Failed to sync task" >&2
        return 1
    fi
}

# =============================================================================
# CLI Interface
# =============================================================================

#' Display usage information
show_usage() {
    cat << 'EOF'
Task Update Script - Update Jira tasks with CCPM data

USAGE:
    task-update.sh COMMAND [OPTIONS]

COMMANDS:
    update ISSUE_KEY UPDATE_DATA_JSON
        Update task with complete new data
        
    fields ISSUE_KEY FIELD_UPDATES_JSON
        Update specific fields only
        
    status ISSUE_KEY NEW_STATUS [ADDITIONAL_FIELDS_JSON]
        Transition task to new status
        
    assign ISSUE_KEY ASSIGNEE_EMAIL_OR_ID
        Assign task to user
        
    interactive
        Launch interactive update wizard
        
    sync-file ISSUE_KEY CCPM_FILE
        Sync task from CCPM JSON/Markdown file
        
    bulk-status UPDATE_FILE NEW_STATUS
        Bulk status update from file with issue keys
        
    help
        Show this help message

OPTIONS:
    ISSUE_KEY              Jira issue key (e.g., PROJ-123)
    UPDATE_DATA_JSON       Complete task data as JSON
    FIELD_UPDATES_JSON     Specific field updates as JSON
    NEW_STATUS             New status (open|in-progress|blocked|completed)
    ADDITIONAL_FIELDS_JSON Optional fields to set during transition
    ASSIGNEE_EMAIL_OR_ID   User email or Jira account ID
    CCPM_FILE             Path to CCPM JSON or Markdown file
    UPDATE_FILE           File containing issue keys (JSON array or line-separated)

EXAMPLES:
    # Update complete task
    task-update.sh update "PROJ-123" '{"name":"Updated task","status":"in-progress"}'
    
    # Update specific fields
    task-update.sh fields "PROJ-123" '{"description":"New description","priority":"High"}'
    
    # Change status
    task-update.sh status "PROJ-123" "in-progress"
    
    # Assign task
    task-update.sh assign "PROJ-123" "user@company.com"
    
    # Interactive mode
    task-update.sh interactive
    
    # Sync from file
    task-update.sh sync-file "PROJ-123" ./tasks/updated-task.json
    
    # Bulk status update
    task-update.sh bulk-status ./issue-keys.txt "completed"

FIELD UPDATE FORMAT:
    {
        "name": "Updated task name",
        "status": "in-progress",
        "description": "Updated description",
        "github": "https://github.com/user/repo/issues/124",
        "priority": "High"
    }

EOF
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        "update")
            local issue_key="$1"
            local update_data="$2"
            
            if [[ -z "$issue_key" || -z "$update_data" ]]; then
                echo "Error: Issue key and update data are required" >&2
                exit 1
            fi
            
            update_task_complete "$issue_key" "$update_data"
            ;;
        "fields")
            local issue_key="$1"
            local field_updates="$2"
            
            if [[ -z "$issue_key" || -z "$field_updates" ]]; then
                echo "Error: Issue key and field updates are required" >&2
                exit 1
            fi
            
            update_task_fields "$issue_key" "$field_updates"
            ;;
        "status")
            local issue_key="$1"
            local new_status="$2"
            local additional_fields="${3:-{}}"
            
            if [[ -z "$issue_key" || -z "$new_status" ]]; then
                echo "Error: Issue key and new status are required" >&2
                exit 1
            fi
            
            update_task_status "$issue_key" "$new_status" "$additional_fields"
            ;;
        "assign")
            local issue_key="$1"
            local assignee="$2"
            
            if [[ -z "$issue_key" || -z "$assignee" ]]; then
                echo "Error: Issue key and assignee are required" >&2
                exit 1
            fi
            
            update_task_assignee "$issue_key" "$assignee"
            ;;
        "interactive")
            interactive_task_update
            ;;
        "sync-file")
            local issue_key="$1"
            local ccpm_file="$2"
            
            if [[ -z "$issue_key" || -z "$ccpm_file" ]]; then
                echo "Error: Issue key and CCPM file are required" >&2
                exit 1
            fi
            
            sync_task_from_file "$issue_key" "$ccpm_file"
            ;;
        "bulk-status")
            local update_file="$1"
            local new_status="$2"
            
            if [[ -z "$update_file" || -z "$new_status" ]]; then
                echo "Error: Update file and new status are required" >&2
                exit 1
            fi
            
            bulk_status_update_from_file "$update_file" "$new_status"
            ;;
        "help"|"-h"|"--help")
            show_usage
            ;;
        *)
            echo "Error: Unknown command '$command'" >&2
            echo "Use 'help' to see available commands" >&2
            exit 1
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi