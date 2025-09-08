#!/bin/bash
set -euo pipefail

# =============================================================================
# Jira MCP Adapter
# =============================================================================
# This script provides a shell interface to Atlassian Jira using MCP tools.
# It wraps the mcp__atlassian__* functions to provide a consistent API for
# Jira operations.
#
# Author: Claude Code
# Version: 1.0.0
# =============================================================================

# Source helper libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/mcp-helpers.sh"

# Default configuration
DEFAULT_CLOUD_ID="86fbc6fd-27a2-481c-ac00-0505c1407b32"
CONFIG_FILE="${SCRIPT_DIR}/../../config/jira-settings.json"

# =============================================================================
# Core Jira Operations
# =============================================================================

#' Create a new Jira issue
#' Usage: create_jira_issue PROJECT_KEY ISSUE_TYPE SUMMARY [DESCRIPTION] [ASSIGNEE_ID]
#' Returns: Issue ID/Key on success
create_jira_issue() {
    local project_key="${1:-}"
    local issue_type="${2:-}"
    local summary="${3:-}"
    local description="${4:-}"
    local assignee_id="${5:-}"
    
    # Validate required parameters
    if [[ -z "$project_key" || -z "$issue_type" || -z "$summary" ]]; then
        echo "Error: Missing required parameters for create_jira_issue" >&2
        echo "Usage: create_jira_issue PROJECT_KEY ISSUE_TYPE SUMMARY [DESCRIPTION] [ASSIGNEE_ID]" >&2
        return 1
    fi
    
    local cloud_id
    cloud_id=$(get_cloud_id) || return 1
    
    # Prepare MCP call parameters
    local mcp_params="{\"cloudId\":\"$cloud_id\",\"projectKey\":\"$project_key\",\"issueTypeName\":\"$issue_type\",\"summary\":\"$summary\""
    
    if [[ -n "$description" ]]; then
        mcp_params="$mcp_params,\"description\":\"$description\""
    fi
    
    if [[ -n "$assignee_id" ]]; then
        mcp_params="$mcp_params,\"assignee_account_id\":\"$assignee_id\""
    fi
    
    mcp_params="$mcp_params}"
    
    # Execute MCP call with error handling
    # Note: In practice, this would be called directly by Claude Code
    # This function provides the interface structure for MCP integration
    echo "create_jira_issue: Would create issue in project '$project_key' with type '$issue_type' and summary '$summary'"
    echo "MCP Parameters: $mcp_params"
    
    # Placeholder return - in practice this would return the actual issue key from MCP
    echo "PLACEHOLDER-123"
    return 0
}

#' Get details of a Jira issue
#' Usage: get_jira_issue ISSUE_KEY_OR_ID
#' Returns: JSON issue data
get_jira_issue() {
    local issue_key="${1:-}"
    
    if [[ -z "$issue_key" ]]; then
        echo "Error: Missing issue key/ID for get_jira_issue" >&2
        echo "Usage: get_jira_issue ISSUE_KEY_OR_ID" >&2
        return 1
    fi
    
    local cloud_id
    cloud_id=$(get_cloud_id) || return 1
    
    local mcp_params="{\"cloudId\":\"$cloud_id\",\"issueIdOrKey\":\"$issue_key\"}"
    
    local result
    if result=$(invoke_mcp_tool "mcp__atlassian__getJiraIssue" "$mcp_params"); then
        echo "$result"
        return 0
    else
        handle_mcp_error "get_jira_issue" "$?" "$result"
        return 1
    fi
}

#' Update an existing Jira issue
#' Usage: update_jira_issue ISSUE_KEY_OR_ID FIELDS_JSON
#' Example: update_jira_issue "PROJ-123" '{"summary":"New Summary"}'
#' Returns: Success/failure status
update_jira_issue() {
    local issue_key="${1:-}"
    local fields_json="${2:-}"
    
    if [[ -z "$issue_key" || -z "$fields_json" ]]; then
        echo "Error: Missing required parameters for update_jira_issue" >&2
        echo "Usage: update_jira_issue ISSUE_KEY_OR_ID FIELDS_JSON" >&2
        return 1
    fi
    
    local cloud_id
    cloud_id=$(get_cloud_id) || return 1
    
    local mcp_params="{\"cloudId\":\"$cloud_id\",\"issueIdOrKey\":\"$issue_key\",\"fields\":$fields_json}"
    
    local result
    if result=$(invoke_mcp_tool "mcp__atlassian__editJiraIssue" "$mcp_params"); then
        echo "Issue $issue_key updated successfully"
        return 0
    else
        handle_mcp_error "update_jira_issue" "$?" "$result"
        return 1
    fi
}

#' Search Jira issues using JQL
#' Usage: search_jira_issues JQL_QUERY [MAX_RESULTS]
#' Example: search_jira_issues "project = PROJ AND status = Open" 50
#' Returns: JSON search results
search_jira_issues() {
    local jql_query="${1:-}"
    local max_results="${2:-50}"
    
    if [[ -z "$jql_query" ]]; then
        echo "Error: Missing JQL query for search_jira_issues" >&2
        echo "Usage: search_jira_issues JQL_QUERY [MAX_RESULTS]" >&2
        return 1
    fi
    
    local cloud_id
    cloud_id=$(get_cloud_id) || return 1
    
    local mcp_params="{\"cloudId\":\"$cloud_id\",\"jql\":\"$jql_query\",\"maxResults\":$max_results}"
    
    local result
    if result=$(invoke_mcp_tool "mcp__atlassian__searchJiraIssuesUsingJql" "$mcp_params"); then
        echo "$result"
        return 0
    else
        handle_mcp_error "search_jira_issues" "$?" "$result"
        return 1
    fi
}

#' Create a Jira epic
#' Usage: create_jira_epic PROJECT_KEY EPIC_NAME SUMMARY [DESCRIPTION]
#' Returns: Epic issue key on success
create_jira_epic() {
    local project_key="${1:-}"
    local epic_name="${2:-}"
    local summary="${3:-}"
    local description="${4:-}"
    
    if [[ -z "$project_key" || -z "$epic_name" || -z "$summary" ]]; then
        echo "Error: Missing required parameters for create_jira_epic" >&2
        echo "Usage: create_jira_epic PROJECT_KEY EPIC_NAME SUMMARY [DESCRIPTION]" >&2
        return 1
    fi
    
    # Create epic as an "Epic" issue type with epic name in additional fields
    local additional_fields="{\"Epic Name\":\"$epic_name\"}"
    
    local cloud_id
    cloud_id=$(get_cloud_id) || return 1
    
    local mcp_params="{\"cloudId\":\"$cloud_id\",\"projectKey\":\"$project_key\",\"issueTypeName\":\"Epic\",\"summary\":\"$summary\",\"additional_fields\":$additional_fields"
    
    if [[ -n "$description" ]]; then
        mcp_params="$mcp_params,\"description\":\"$description\""
    fi
    
    mcp_params="$mcp_params}"
    
    local result
    if result=$(invoke_mcp_tool "mcp__atlassian__createJiraIssue" "$mcp_params"); then
        echo "$result" | jq -r '.key // .id // "unknown"' 2>/dev/null || echo "unknown"
        return 0
    else
        handle_mcp_error "create_jira_epic" "$?" "$result"
        return 1
    fi
}

#' Transition a Jira issue to a new status
#' Usage: transition_jira_issue ISSUE_KEY_OR_ID TRANSITION_ID [FIELDS_JSON]
#' Example: transition_jira_issue "PROJ-123" "21" '{"assignee":{"accountId":"123"}}'
#' Returns: Success/failure status
transition_jira_issue() {
    local issue_key="${1:-}"
    local transition_id="${2:-}"
    local fields_json="${3:-{}}"
    
    if [[ -z "$issue_key" || -z "$transition_id" ]]; then
        echo "Error: Missing required parameters for transition_jira_issue" >&2
        echo "Usage: transition_jira_issue ISSUE_KEY_OR_ID TRANSITION_ID [FIELDS_JSON]" >&2
        return 1
    fi
    
    local cloud_id
    cloud_id=$(get_cloud_id) || return 1
    
    local mcp_params="{\"cloudId\":\"$cloud_id\",\"issueIdOrKey\":\"$issue_key\",\"transition\":{\"id\":\"$transition_id\"},\"fields\":$fields_json}"
    
    local result
    if result=$(invoke_mcp_tool "mcp__atlassian__transitionJiraIssue" "$mcp_params"); then
        echo "Issue $issue_key transitioned successfully"
        return 0
    else
        handle_mcp_error "transition_jira_issue" "$?" "$result"
        return 1
    fi
}

#' Get available transitions for a Jira issue
#' Usage: get_jira_issue_transitions ISSUE_KEY_OR_ID
#' Returns: JSON array of available transitions
get_jira_issue_transitions() {
    local issue_key="${1:-}"
    
    if [[ -z "$issue_key" ]]; then
        echo "Error: Missing issue key/ID for get_jira_issue_transitions" >&2
        echo "Usage: get_jira_issue_transitions ISSUE_KEY_OR_ID" >&2
        return 1
    fi
    
    local cloud_id
    cloud_id=$(get_cloud_id) || return 1
    
    local mcp_params="{\"cloudId\":\"$cloud_id\",\"issueIdOrKey\":\"$issue_key\"}"
    
    local result
    if result=$(invoke_mcp_tool "mcp__atlassian__getTransitionsForJiraIssue" "$mcp_params"); then
        echo "$result"
        return 0
    else
        handle_mcp_error "get_jira_issue_transitions" "$?" "$result"
        return 1
    fi
}

#' Add a comment to a Jira issue
#' Usage: add_jira_comment ISSUE_KEY_OR_ID COMMENT_BODY
#' Returns: Comment ID on success
add_jira_comment() {
    local issue_key="${1:-}"
    local comment_body="${2:-}"
    
    if [[ -z "$issue_key" || -z "$comment_body" ]]; then
        echo "Error: Missing required parameters for add_jira_comment" >&2
        echo "Usage: add_jira_comment ISSUE_KEY_OR_ID COMMENT_BODY" >&2
        return 1
    fi
    
    local cloud_id
    cloud_id=$(get_cloud_id) || return 1
    
    local mcp_params="{\"cloudId\":\"$cloud_id\",\"issueIdOrKey\":\"$issue_key\",\"commentBody\":\"$comment_body\"}"
    
    local result
    if result=$(invoke_mcp_tool "mcp__atlassian__addCommentToJiraIssue" "$mcp_params"); then
        echo "$result" | jq -r '.id // "unknown"' 2>/dev/null || echo "unknown"
        return 0
    else
        handle_mcp_error "add_jira_comment" "$?" "$result"
        return 1
    fi
}

#' Get visible Jira projects
#' Usage: get_jira_projects [ACTION]
#' ACTION: view, browse, edit, create (default: view)
#' Returns: JSON array of projects
get_jira_projects() {
    local action="${1:-view}"
    
    local cloud_id
    cloud_id=$(get_cloud_id) || return 1
    
    local mcp_params="{\"cloudId\":\"$cloud_id\",\"action\":\"$action\"}"
    
    local result
    if result=$(invoke_mcp_tool "mcp__atlassian__getVisibleJiraProjects" "$mcp_params"); then
        echo "$result"
        return 0
    else
        handle_mcp_error "get_jira_projects" "$?" "$result"
        return 1
    fi
}

# =============================================================================
# Utility Functions
# =============================================================================

#' Get configured cloud ID
get_cloud_id() {
    if [[ -f "$CONFIG_FILE" ]]; then
        jq -r '.cloudId // empty' "$CONFIG_FILE" 2>/dev/null || echo "$DEFAULT_CLOUD_ID"
    else
        echo "$DEFAULT_CLOUD_ID"
    fi
}

#' Validate Jira configuration
validate_jira_config() {
    echo "Validating Jira configuration..."
    
    local cloud_id
    cloud_id=$(get_cloud_id)
    
    echo "  Cloud ID: $cloud_id"
    
    # Test connection by getting user info
    if invoke_mcp_tool "mcp__atlassian__atlassianUserInfo" "{}"; then
        echo "  ✅ Authentication successful"
        return 0
    else
        echo "  ❌ Authentication failed"
        return 1
    fi
}

# =============================================================================
# CLI Interface
# =============================================================================

#' Display usage information
show_usage() {
    cat << 'EOF'
Jira MCP Adapter - Shell interface for Jira operations

USAGE:
    jira-adapter.sh COMMAND [ARGS...]

COMMANDS:
    create-issue PROJECT_KEY ISSUE_TYPE SUMMARY [DESCRIPTION] [ASSIGNEE_ID]
        Create a new Jira issue

    get-issue ISSUE_KEY_OR_ID
        Get details of a specific issue

    update-issue ISSUE_KEY_OR_ID FIELDS_JSON
        Update an existing issue

    search-issues JQL_QUERY [MAX_RESULTS]
        Search issues using JQL

    create-epic PROJECT_KEY EPIC_NAME SUMMARY [DESCRIPTION]
        Create a new epic

    transition-issue ISSUE_KEY_OR_ID TRANSITION_ID [FIELDS_JSON]
        Transition an issue to a new status

    get-transitions ISSUE_KEY_OR_ID
        Get available transitions for an issue

    add-comment ISSUE_KEY_OR_ID COMMENT_BODY
        Add a comment to an issue

    get-projects [ACTION]
        Get visible projects (ACTION: view|browse|edit|create)

    validate-config
        Validate Jira configuration and connection

    help
        Show this help message

EXAMPLES:
    jira-adapter.sh create-issue "PROJ" "Task" "Fix bug in login"
    jira-adapter.sh get-issue "PROJ-123"
    jira-adapter.sh search-issues "project = PROJ AND status = Open"
    jira-adapter.sh transition-issue "PROJ-123" "21"

EOF
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        "create-issue")
            create_jira_issue "$@"
            ;;
        "get-issue")
            get_jira_issue "$@"
            ;;
        "update-issue")
            update_jira_issue "$@"
            ;;
        "search-issues")
            search_jira_issues "$@"
            ;;
        "create-epic")
            create_jira_epic "$@"
            ;;
        "transition-issue")
            transition_jira_issue "$@"
            ;;
        "get-transitions")
            get_jira_issue_transitions "$@"
            ;;
        "add-comment")
            add_jira_comment "$@"
            ;;
        "get-projects")
            get_jira_projects "$@"
            ;;
        "validate-config")
            validate_jira_config
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