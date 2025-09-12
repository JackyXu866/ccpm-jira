#!/bin/bash
set -euo pipefail

# =============================================================================
# Issue Creation Script
# =============================================================================
# This script provides a command-line interface for creating Jira issues/tasks
# from CCPM data. It supports both interactive and batch creation modes.
#
# Author: Claude Code - Stream B Implementation
# Version: 1.0.0
# =============================================================================

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/jira-task-ops.sh"

# Default configuration
DEFAULT_ISSUE_TYPE="Task"
DEFAULT_PROJECT_KEY=""

# =============================================================================
# Input Validation Functions
# =============================================================================

#' Validate required parameters
validate_create_params() {
    local task_name="$1"
    local task_data="$2"
    
    if [[ -z "$task_name" ]]; then
        echo "Error: Task name is required" >&2
        return 1
    fi
    
    if [[ -z "$task_data" || "$task_data" == "{}" ]]; then
        echo "Error: Task data is required" >&2
        return 1
    fi
    
    # Basic JSON validation
    if ! echo "$task_data" | jq . >/dev/null 2>&1; then
        echo "Error: Task data must be valid JSON" >&2
        return 1
    fi
    
    return 0
}

#' Validate issue type against available options
validate_issue_type() {
    local issue_type="$1"
    
    case "$issue_type" in
        "Task"|"Story"|"Bug"|"Epic"|"Improvement")
            return 0
            ;;
        *)
            echo "Warning: Issue type '$issue_type' may not be supported" >&2
            echo "Supported types: Task, Story, Bug, Epic, Improvement" >&2
            return 0  # Allow custom types but warn
            ;;
    esac
}

# =============================================================================
# Interactive Creation Functions
# =============================================================================

#' Interactive task creation wizard
interactive_task_creation() {
    echo "=== Jira Task Creation Wizard ===" >&2
    echo >&2
    
    # Get task name
    local task_name=""
    while [[ -z "$task_name" ]]; do
        echo -n "Task name (required): " >&2
        read -r task_name
        if [[ -z "$task_name" ]]; then
            echo "Task name cannot be empty" >&2
        fi
    done
    
    # Get description
    echo -n "Description (optional): " >&2
    read -r description
    
    # Get issue type
    echo -n "Issue type [Task|Story|Bug|Epic|Improvement] (default: Task): " >&2
    read -r issue_type
    issue_type="${issue_type:-Task}"
    validate_issue_type "$issue_type"
    
    # Get project key
    echo -n "Project key (optional, uses default if empty): " >&2
    read -r project_key
    
    # Get status
    echo -n "Initial status (default: open): " >&2
    read -r status
    status="${status:-open}"
    
    # Get priority
    echo -n "Priority [Low|Medium|High] (optional): " >&2
    read -r priority
    
    # Get assignee
    echo -n "Assignee email (optional): " >&2
    read -r assignee
    
    # Get GitHub issue URL
    echo -n "GitHub issue URL (optional): " >&2
    read -r github_url
    
    # Build task data JSON
    local task_data
    task_data=$(jq -n \
        --arg name "$task_name" \
        --arg desc "$description" \
        --arg stat "$status" \
        --arg prio "$priority" \
        --arg github "$github_url" \
        '{
            name: $name,
            status: $stat,
            created: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
        } + 
        (if $desc != "" then {description: $desc} else {} end) +
        (if $prio != "" then {priority: $prio} else {} end) +
        (if $github != "" then {github: $github} else {} end)')
    
    echo >&2
    echo "=== Task Details ===" >&2
    echo "Name: $task_name" >&2
    echo "Type: $issue_type" >&2
    echo "Project: ${project_key:-<default>}" >&2
    echo "Data: $(echo "$task_data" | jq -C .)" >&2
    echo >&2
    
    echo -n "Create this task? [y/N]: " >&2
    read -r confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        create_task_with_params "$task_name" "$task_data" "$issue_type" "$project_key" "$assignee"
    else
        echo "Task creation cancelled" >&2
        return 1
    fi
}

# =============================================================================
# Creation Helper Functions
# =============================================================================

#' Create task with all parameters
create_task_with_params() {
    local task_name="$1"
    local task_data="$2" 
    local issue_type="$3"
    local project_key="$4"
    local assignee="$5"
    
    echo "Creating task '$task_name'..." >&2
    
    # Create the task
    local issue_key
    if [[ -n "$project_key" ]]; then
        issue_key=$(create_jira_task "$task_name" "$task_data" "$issue_type" "$project_key")
    else
        issue_key=$(create_jira_task "$task_name" "$task_data" "$issue_type")
    fi
    
    if [[ $? -ne 0 || -z "$issue_key" ]]; then
        echo "Error: Failed to create task" >&2
        return 1
    fi
    
    echo "Task created successfully: $issue_key" >&2
    
    # Assign task if assignee specified
    if [[ -n "$assignee" ]]; then
        echo "Assigning task to $assignee..." >&2
        if assign_jira_task "$issue_key" "$assignee"; then
            echo "Task assigned successfully" >&2
        else
            echo "Warning: Task created but assignment failed" >&2
        fi
    fi
    
    # Output the issue key for piping/automation
    echo "$issue_key"
    return 0
}

#' Create task from CCPM file format
create_from_ccpm_file() {
    local ccpm_file="$1"
    local issue_type="${2:-Task}"
    local project_key="$3"
    
    if [[ ! -f "$ccpm_file" ]]; then
        echo "Error: CCPM file not found: $ccpm_file" >&2
        return 1
    fi
    
    # Parse CCPM file (assuming it's JSON or YAML)
    local task_data
    if [[ "$ccpm_file" == *.json ]]; then
        task_data=$(cat "$ccmp_file")
    elif [[ "$ccpm_file" == *.md ]]; then
        # Extract front matter as JSON
        task_data=$(awk '/^---$/{flag++; next} flag==1' "$ccpm_file" | head -n -1)
    else
        echo "Error: Unsupported file format. Use .json or .md files" >&2
        return 1
    fi
    
    # Extract task name
    local task_name
    task_name=$(echo "$task_data" | jq -r '.name // .title // "Unnamed Task"')
    
    # Validate and create
    if validate_create_params "$task_name" "$task_data"; then
        create_task_with_params "$task_name" "$task_data" "$issue_type" "$project_key" ""
    else
        return 1
    fi
}

# =============================================================================
# Batch Operations
# =============================================================================

#' Create multiple tasks from JSON array file
batch_create_from_file() {
    local batch_file="$1"
    local issue_type="${2:-Task}"
    local project_key="$3"
    
    if [[ ! -f "$batch_file" ]]; then
        echo "Error: Batch file not found: $batch_file" >&2
        return 1
    fi
    
    local tasks_array
    tasks_array=$(cat "$batch_file")
    
    if ! echo "$tasks_array" | jq . >/dev/null 2>&1; then
        echo "Error: Batch file must contain valid JSON array" >&2
        return 1
    fi
    
    echo "Starting batch creation from $batch_file..." >&2
    
    local results
    if results=$(bulk_create_jira_tasks "$tasks_array" "$issue_type" "$project_key"); then
        echo "Batch creation completed:" >&2
        echo "$results" | jq -C . >&2
        
        # Output just the issue keys for automation
        echo "$results" | jq -r '.[] | select(.status == "created") | .jira_key'
        
        return 0
    else
        echo "Error: Batch creation failed" >&2
        return 1
    fi
}

# =============================================================================
# CLI Interface
# =============================================================================

#' Display usage information
show_usage() {
    cat << 'EOF'
Task Creation Script - Create Jira tasks from CCPM data

USAGE:
    task-create.sh COMMAND [OPTIONS]

COMMANDS:
    create TASK_NAME TASK_DATA_JSON [ISSUE_TYPE] [PROJECT_KEY]
        Create a single task with specified parameters
        
    interactive
        Launch interactive task creation wizard
        
    from-file CCPM_FILE [ISSUE_TYPE] [PROJECT_KEY]
        Create task from CCPM JSON/Markdown file
        
    batch-file BATCH_JSON_FILE [ISSUE_TYPE] [PROJECT_KEY]  
        Create multiple tasks from JSON array file
        
    help
        Show this help message

OPTIONS:
    TASK_NAME           Name/summary of the task
    TASK_DATA_JSON      JSON object with task details
    ISSUE_TYPE          Jira issue type (default: Task)
    PROJECT_KEY         Jira project key (uses default if not specified)
    CCPM_FILE          Path to CCPM JSON or Markdown file
    BATCH_JSON_FILE    Path to JSON file containing array of tasks

EXAMPLES:
    # Create simple task
    task-create.sh create "Fix login bug" '{"status":"open","description":"Login fails on mobile"}'
    
    # Create with specific type and project
    task-create.sh create "New feature" '{"status":"open"}' "Story" "PROJ"
    
    # Interactive creation
    task-create.sh interactive
    
    # Create from file
    task-create.sh from-file ./tasks/new-feature.json "Story"
    
    # Batch creation
    task-create.sh batch-file ./tasks/sprint-backlog.json "Task" "PROJ"

TASK DATA FORMAT:
    {
        "name": "Task name (optional, can be provided as separate parameter)",
        "status": "open|in-progress|blocked|completed",
        "description": "Task description",
        "github": "https://github.com/user/repo/issues/123",
        "depends_on": [2, 3],
        "parallel": true,
        "conflicts_with": [4, 5],
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
        "create")
            local task_name="$1"
            local task_data="$2"
            local issue_type="${3:-$DEFAULT_ISSUE_TYPE}"
            local project_key="${4:-$DEFAULT_PROJECT_KEY}"
            
            if ! validate_create_params "$task_name" "$task_data"; then
                exit 1
            fi
            
            validate_issue_type "$issue_type"
            create_task_with_params "$task_name" "$task_data" "$issue_type" "$project_key" ""
            ;;
        "interactive")
            interactive_task_creation
            ;;
        "from-file")
            local ccpm_file="$1"
            local issue_type="${2:-$DEFAULT_ISSUE_TYPE}"
            local project_key="${3:-$DEFAULT_PROJECT_KEY}"
            
            if [[ -z "$ccpm_file" ]]; then
                echo "Error: CCPM file path is required" >&2
                exit 1
            fi
            
            create_from_ccpm_file "$ccpm_file" "$issue_type" "$project_key"
            ;;
        "batch-file")
            local batch_file="$1"
            local issue_type="${2:-$DEFAULT_ISSUE_TYPE}"
            local project_key="${3:-$DEFAULT_PROJECT_KEY}"
            
            if [[ -z "$batch_file" ]]; then
                echo "Error: Batch file path is required" >&2
                exit 1
            fi
            
            batch_create_from_file "$batch_file" "$issue_type" "$project_key"
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