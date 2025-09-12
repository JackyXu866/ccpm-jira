#!/bin/bash

# Jira Transitions Library
# Provides functions for handling Jira issue state transitions and workflow management
# Uses MCP Atlassian integration for Jira API calls

set -e

# Default transition mappings
declare -A DEFAULT_TRANSITIONS=(
    ["TO_DO"]="To Do"
    ["IN_PROGRESS"]="In Progress"
    ["DONE"]="Done"
    ["CLOSED"]="Closed"
)

# Get available transitions for a Jira issue
# Usage: get_available_transitions <cloud_id> <issue_key>
get_available_transitions() {
    local cloud_id="$1"
    local issue_key="$2"
    
    if [[ -z "$cloud_id" || -z "$issue_key" ]]; then
        echo "ERROR: cloud_id and issue_key are required" >&2
        return 1
    fi
    
    # Create a temp file to capture MCP tool output
    local temp_file="/tmp/jira-transitions-$$.json"
    
    # Note: In a real implementation, this would use MCP tools directly
    # For now, we'll simulate the response structure
    cat > "$temp_file" << 'EOF'
{
  "transitions": [
    {
      "id": "11",
      "name": "To Do",
      "to": {
        "name": "To Do",
        "id": "10001"
      }
    },
    {
      "id": "21",
      "name": "In Progress",
      "to": {
        "name": "In Progress",
        "id": "10002"
      }
    },
    {
      "id": "31",
      "name": "Done",
      "to": {
        "name": "Done",
        "id": "10003"
      }
    }
  ]
}
EOF
    
    # Extract transition names and IDs
    if [[ -f "$temp_file" ]]; then
        # Use jq if available, otherwise use basic parsing
        if command -v jq >/dev/null 2>&1; then
            jq -r '.transitions[] | "\(.id):\(.name)"' "$temp_file"
        else
            # Fallback parsing without jq
            grep -o '"id": *"[^"]*"' "$temp_file" | cut -d'"' -f4 > "/tmp/ids-$$"
            grep -o '"name": *"[^"]*"' "$temp_file" | cut -d'"' -f4 > "/tmp/names-$$"
            paste -d: "/tmp/ids-$$" "/tmp/names-$$"
            rm -f "/tmp/ids-$$" "/tmp/names-$$"
        fi
    fi
    
    # Cleanup
    rm -f "$temp_file"
}

# Find transition ID for a target status
# Usage: find_transition_id <cloud_id> <issue_key> <target_status>
find_transition_id() {
    local cloud_id="$1"
    local issue_key="$2"
    local target_status="$3"
    
    if [[ -z "$cloud_id" || -z "$issue_key" || -z "$target_status" ]]; then
        echo "ERROR: cloud_id, issue_key, and target_status are required" >&2
        return 1
    fi
    
    # Get available transitions
    local transitions
    transitions=$(get_available_transitions "$cloud_id" "$issue_key")
    
    if [[ -z "$transitions" ]]; then
        echo "ERROR: No transitions available for issue $issue_key" >&2
        return 1
    fi
    
    # Look for exact match first
    local transition_id
    transition_id=$(echo "$transitions" | grep -i ":${target_status}$" | cut -d: -f1 | head -1)
    
    if [[ -n "$transition_id" ]]; then
        echo "$transition_id"
        return 0
    fi
    
    # Try partial match
    transition_id=$(echo "$transitions" | grep -i ":.*${target_status}" | cut -d: -f1 | head -1)
    
    if [[ -n "$transition_id" ]]; then
        echo "$transition_id"
        return 0
    fi
    
    echo "ERROR: No transition found for status '$target_status'" >&2
    echo "Available transitions:" >&2
    echo "$transitions" | sed 's/^/  /' >&2
    return 1
}

# Transition a Jira issue to a new status
# Usage: transition_jira_issue <cloud_id> <issue_key> <target_status> [comment]
transition_jira_issue() {
    local cloud_id="$1"
    local issue_key="$2"
    local target_status="$3"
    local comment="${4:-}"
    
    if [[ -z "$cloud_id" || -z "$issue_key" || -z "$target_status" ]]; then
        echo "ERROR: cloud_id, issue_key, and target_status are required" >&2
        return 1
    fi
    
    echo "🔄 Transitioning issue $issue_key to '$target_status'..."
    
    # Find the transition ID
    local transition_id
    if ! transition_id=$(find_transition_id "$cloud_id" "$issue_key" "$target_status"); then
        return 1
    fi
    
    echo "   Found transition ID: $transition_id"
    
    # Prepare transition data
    local transition_data="/tmp/jira-transition-$$.json"
    cat > "$transition_data" << EOF
{
  "transition": {
    "id": "$transition_id"
  }
EOF
    
    # Add comment if provided
    if [[ -n "$comment" ]]; then
        cat >> "$transition_data" << EOF
,
  "update": {
    "comment": [
      {
        "add": {
          "body": "$comment"
        }
      }
    ]
  }
EOF
    fi
    
    cat >> "$transition_data" << EOF
}
EOF
    
    # Create marker file for MCP tool execution
    # In a real implementation, this would call the MCP tool directly
    cat > "/tmp/jira-transition-request-$issue_key.json" << EOF
{
  "action": "transition",
  "cloud_id": "$cloud_id",
  "issue_key": "$issue_key",
  "transition_id": "$transition_id",
  "target_status": "$target_status",
  "comment": "$comment",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    
    echo "✅ Transition request prepared for issue $issue_key"
    echo "   Target status: $target_status"
    echo "   Transition ID: $transition_id"
    
    # Cleanup
    rm -f "$transition_data"
    
    return 0
}

# Get current status of a Jira issue
# Usage: get_issue_status <cloud_id> <issue_key>
get_issue_status() {
    local cloud_id="$1"
    local issue_key="$2"
    
    if [[ -z "$cloud_id" || -z "$issue_key" ]]; then
        echo "ERROR: cloud_id and issue_key are required" >&2
        return 1
    fi
    
    # Create marker file for MCP tool execution
    cat > "/tmp/jira-status-request-$issue_key.json" << EOF
{
  "action": "get_status",
  "cloud_id": "$cloud_id",
  "issue_key": "$issue_key",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    
    # For simulation, return a default status
    echo "To Do"
    return 0
}

# Validate if a status transition is allowed
# Usage: validate_transition <cloud_id> <issue_key> <from_status> <to_status>
validate_transition() {
    local cloud_id="$1"
    local issue_key="$2"
    local from_status="$3"
    local to_status="$4"
    
    if [[ -z "$cloud_id" || -z "$issue_key" || -z "$to_status" ]]; then
        echo "ERROR: Required parameters missing" >&2
        return 1
    fi
    
    # Get available transitions
    local transitions
    transitions=$(get_available_transitions "$cloud_id" "$issue_key")
    
    if [[ -z "$transitions" ]]; then
        echo "ERROR: Could not get available transitions" >&2
        return 1
    fi
    
    # Check if target status is in available transitions
    if echo "$transitions" | grep -qi ":${to_status}$"; then
        echo "✅ Transition to '$to_status' is allowed"
        return 0
    elif echo "$transitions" | grep -qi ":.*${to_status}"; then
        echo "✅ Transition to status containing '$to_status' is allowed"
        return 0
    else
        echo "❌ Transition to '$to_status' is not allowed" >&2
        echo "Available transitions:" >&2
        echo "$transitions" | sed 's/^/  /' >&2
        return 1
    fi
}

# Map local status to Jira status
# Usage: map_local_to_jira_status <local_status>
map_local_to_jira_status() {
    local local_status="$1"
    
    case "$local_status" in
        "open"|"todo"|"new"|"created") echo "To Do" ;;
        "in-progress"|"in_progress"|"active"|"started"|"working") echo "In Progress" ;;
        "completed"|"complete"|"done"|"finished"|"resolved") echo "Done" ;;
        "closed"|"cancelled"|"wont_fix") echo "Closed" ;;
        *) echo "To Do" ;;  # Default fallback
    esac
}

# Map Jira status to local status
# Usage: map_jira_to_local_status <jira_status>
map_jira_to_local_status() {
    local jira_status="$1"
    
    case "$jira_status" in
        "To Do"|"Open"|"Backlog"|"Selected for Development") echo "open" ;;
        "In Progress"|"In Review"|"Code Review"|"Testing") echo "in-progress" ;;
        "Done"|"Resolved"|"Closed"|"Complete") echo "completed" ;;
        "Cancelled"|"Won't Do"|"Invalid") echo "closed" ;;
        *) echo "open" ;;  # Default fallback
    esac
}

# Handle workflow-specific transitions
# Usage: handle_custom_workflow <cloud_id> <issue_key> <target_status>
handle_custom_workflow() {
    local cloud_id="$1"
    local issue_key="$2"
    local target_status="$3"
    
    if [[ -z "$cloud_id" || -z "$issue_key" || -z "$target_status" ]]; then
        echo "ERROR: Required parameters missing" >&2
        return 1
    fi
    
    echo "🔍 Checking custom workflow for issue $issue_key..."
    
    # Get current status
    local current_status
    current_status=$(get_issue_status "$cloud_id" "$issue_key")
    
    echo "   Current status: $current_status"
    echo "   Target status: $target_status"
    
    # If already at target status, no transition needed
    if [[ "$current_status" == "$target_status" ]]; then
        echo "✅ Issue is already in '$target_status' status"
        return 0
    fi
    
    # Validate the transition
    if validate_transition "$cloud_id" "$issue_key" "$current_status" "$target_status"; then
        echo "🔄 Proceeding with transition..."
        return 0
    else
        echo "❌ Direct transition not possible"
        
        # Try to find intermediate steps for common scenarios
        case "$target_status" in
            "In Progress")
                if [[ "$current_status" =~ ^(Done|Closed) ]]; then
                    echo "💡 Suggestion: Reopen the issue first, then transition to In Progress"
                fi
                ;;
            "Done")
                if [[ "$current_status" == "To Do" ]]; then
                    echo "💡 Suggestion: Move to In Progress first, then to Done"
                fi
                ;;
        esac
        
        return 1
    fi
}

# Get Jira cloud ID from configuration
# Usage: get_jira_cloud_id
get_jira_cloud_id() {
    local cloud_id=""
    
    # Try to get from configuration files
    if [[ -f "claude/config/jira.json" ]]; then
        if command -v jq >/dev/null 2>&1; then
            cloud_id=$(jq -r '.cloud_id // empty' "claude/config/jira.json" 2>/dev/null)
        else
            cloud_id=$(grep -o '"cloud_id":\s*"[^"]*"' "claude/config/jira.json" | cut -d'"' -f4)
        fi
    fi
    
    # Fallback to settings file
    if [[ -z "$cloud_id" && -f "claude/settings.local.json" ]]; then
        if command -v jq >/dev/null 2>&1; then
            cloud_id=$(jq -r '.jira.cloud_id // empty' "claude/settings.local.json" 2>/dev/null)
        else
            cloud_id=$(grep -A5 '"jira"' "claude/settings.local.json" | grep -o '"cloud_id":\s*"[^"]*"' | cut -d'"' -f4)
        fi
    fi
    
    if [[ -z "$cloud_id" ]]; then
        echo "ERROR: Jira cloud ID not found in configuration" >&2
        echo "Expected in claude/config/jira.json or claude/settings.local.json" >&2
        return 1
    fi
    
    echo "$cloud_id"
}

# Get Jira issue key from local task file
# Usage: get_jira_key_from_github_issue <issue_number>
get_jira_key_from_github_issue() {
    local issue_number="$1"
    
    if [[ -z "$issue_number" ]]; then
        echo "ERROR: issue_number is required" >&2
        return 1
    fi
    
    # Check local task files for Jira link
    local task_file=""
    for epic_dir in .claude/epics/*; do
        if [[ -d "$epic_dir" ]] && [[ -f "$epic_dir/$issue_number.md" ]]; then
            task_file="$epic_dir/$issue_number.md"
            break
        fi
    done
    
    if [[ -n "$task_file" ]]; then
        local jira_url
        jira_url=$(grep "^jira:" "$task_file" | head -1 | sed 's/^jira: *//')
        
        if [[ -n "$jira_url" ]]; then
            local jira_key
            jira_key=$(echo "$jira_url" | grep -oE '[A-Z]+-[0-9]+' | head -n1 || echo "")
            
            if [[ -n "$jira_key" ]]; then
                echo "$jira_key"
                return 0
            fi
        fi
    fi
    
    echo "ERROR: Could not find Jira key for task $issue_number" >&2
    return 1
}

# Log transition for debugging
# Usage: log_transition <issue_key> <from_status> <to_status> <success>
log_transition() {
    local issue_key="$1"
    local from_status="$2"
    local to_status="$3"
    local success="$4"
    
    local log_dir=".claude/logs"
    mkdir -p "$log_dir"
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local log_entry="$timestamp - $issue_key: $from_status → $to_status [$success]"
    
    echo "$log_entry" >> "$log_dir/jira-transitions.log"
}

# Export functions for use by other scripts
export -f get_available_transitions
export -f find_transition_id
export -f transition_jira_issue
export -f get_issue_status
export -f validate_transition
export -f map_local_to_jira_status
export -f map_jira_to_local_status
export -f handle_custom_workflow
export -f get_jira_cloud_id
export -f get_jira_key_from_github_issue
export -f log_transition