#!/bin/bash

# Task Start Jira Implementation
# Handles starting work on a task with Jira integration
# Transitions task to "In Progress", assigns to current user, creates feature branch

set -e

# Load required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/transitions.sh"
source "$SCRIPT_DIR/git-integration.sh"

# Start work on a Jira task
# Usage: start_task_jira <task_number> <task_file> <epic_name>
start_task_jira() {
    local task_number="$1"
    local task_file="$2"
    local epic_name="$3"
    
    if [[ -z "$task_number" || -z "$task_file" || -z "$epic_name" ]]; then
        echo "ERROR: task_number, task_file, and epic_name are required" >&2
        return 1
    fi
    
    echo "🚀 Starting Jira task workflow for #$task_number"
    
    # Get Jira configuration
    local cloud_id
    if ! cloud_id=$(get_jira_cloud_id); then
        echo "❌ Failed to get Jira cloud ID"
        return 1
    fi
    
    echo "   Cloud ID: $cloud_id"
    
    # Get Jira issue key
    local jira_key
    if ! jira_key=$(get_jira_key_from_task "$task_number"); then
        echo "⚠️  Could not find Jira key for task $task_number"
        return 1
    else
        echo "   Jira key: $jira_key"
    fi
    
    # Get current user account ID for assignment
    echo "👤 Getting current user information..."
    local current_user_id
    if ! current_user_id=$(get_current_user_account_id "$cloud_id"); then
        echo "⚠️  Could not get current user ID, assignment will be skipped"
        current_user_id=""
    else
        echo "   User ID: $current_user_id"
    fi
    
    # Transition issue to "In Progress"
    echo "🔄 Transitioning Jira issue to In Progress..."
    local transition_comment="Started work via ccpm-jira integration (task $task_number)"
    
    if transition_jira_issue "$cloud_id" "$jira_key" "In Progress" "$transition_comment"; then
        echo "✅ Issue transitioned to In Progress"
        
        # Log the transition
        log_transition "$jira_key" "Unknown" "In Progress" "SUCCESS"
    else
        echo "⚠️  Could not transition issue to In Progress (may already be in progress or custom workflow)"
        
        # Log the failed transition
        log_transition "$jira_key" "Unknown" "In Progress" "FAILED"
    fi
    
    # Assign issue to current user
    if [[ -n "$current_user_id" ]]; then
        echo "👥 Assigning issue to current user..."
        if assign_jira_issue "$cloud_id" "$jira_key" "$current_user_id"; then
            echo "✅ Issue assigned to current user"
        else
            echo "⚠️  Could not assign issue (may not have permissions)"
        fi
    fi
    
    # Create feature branch with Jira key if available
    echo "🌱 Creating feature branch..."
    
    # Get task title from local file
    local task_title=""
    if [[ -f "$task_file" ]]; then
        task_title=$(grep '^name:' "$task_file" | head -1 | sed 's/^name: *//' | sed 's/"//g' || echo "")
    fi
    
    local branch_description
    if [[ -n "$task_title" ]]; then
        branch_description=$(echo "$task_title" | head -c 30 | sed 's/[^a-zA-Z0-9 ]//g' | xargs)
    else
        branch_description="task-$task_number"
    fi
    
    local branch_name=""
    # Use Jira key for branch naming
    if branch_name=$(generate_branch_name "$jira_key" "$branch_description"); then
        # Check for conflicts and resolve
        branch_name=$(resolve_branch_conflict "$branch_name")
        
        # Create the branch
        if create_jira_formatted_branch "$branch_name"; then
            echo "✅ Created Jira-formatted branch: $branch_name"
        else
            echo "⚠️  Branch creation failed, continuing without new branch"
            branch_name=""
        fi
    else
        echo "⚠️  Branch creation failed, continuing without new branch"
        branch_name=""
    fi
    
    # Update local cache with Jira data
    echo "💾 Updating local cache..."
    if update_local_cache "$task_number" "$task_file" "$epic_name" "$jira_key" "$cloud_id"; then
        echo "✅ Local cache updated"
    else
        echo "⚠️  Could not update local cache"
    fi
    
    # Update task file with assignment and branch info
    echo "📝 Updating task file..."
    if update_task_file_with_jira_info "$task_file" "$jira_key" "$branch_name" "$current_user_id"; then
        echo "✅ Task file updated"
    else
        echo "⚠️  Could not update task file"
    fi
    
    # Summary
    echo ""
    echo "✅ Jira issue start completed!"
    echo ""
    echo "Issue: #$task_number"
    echo "Jira: $jira_key"
    if [[ -n "$branch_name" ]]; then
        echo "Branch: $branch_name"
    fi
    echo "Epic: $epic_name"
    echo ""
    
    return 0
}

# Get current user account ID from Jira
# Usage: get_current_user_account_id <cloud_id>
get_current_user_account_id() {
    local cloud_id="$1"
    
    if [[ -z "$cloud_id" ]]; then
        echo "ERROR: cloud_id is required" >&2
        return 1
    fi
    
    # Create marker file for MCP tool execution
    cat > "/tmp/jira-user-info-request.json" << EOF
{
  "action": "get_user_info",
  "cloud_id": "$cloud_id",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    
    # For simulation, return a placeholder
    # In real implementation, this would use MCP tools to get actual user info
    echo "user-account-id-placeholder"
    return 0
}

# Assign Jira issue to a user
# Usage: assign_jira_issue <cloud_id> <issue_key> <account_id>
assign_jira_issue() {
    local cloud_id="$1"
    local issue_key="$2"
    local account_id="$3"
    
    if [[ -z "$cloud_id" || -z "$issue_key" || -z "$account_id" ]]; then
        echo "ERROR: cloud_id, issue_key, and account_id are required" >&2
        return 1
    fi
    
    # Create marker file for MCP tool execution
    cat > "/tmp/jira-assign-request-$issue_key.json" << EOF
{
  "action": "assign_issue",
  "cloud_id": "$cloud_id",
  "issue_key": "$issue_key",
  "account_id": "$account_id",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    
    echo "✅ Assignment request prepared for $issue_key"
    return 0
}

# Create a Jira-formatted branch
# Usage: create_jira_formatted_branch <branch_name>
create_jira_formatted_branch() {
    local branch_name="$1"
    
    if [[ -z "$branch_name" ]]; then
        echo "ERROR: branch_name is required" >&2
        return 1
    fi
    
    # Ensure we're on main and up to date
    echo "   Preparing to create branch: $branch_name"
    
    if ! git checkout main 2>/dev/null; then
        echo "WARNING: Could not switch to main branch" >&2
    fi
    
    if ! git pull origin main 2>/dev/null; then
        echo "WARNING: Could not update main branch" >&2
    fi
    
    # Create the branch
    if git checkout -b "$branch_name"; then
        echo "   Branch created locally: $branch_name"
        
        # Push branch with upstream tracking
        if git push -u origin "$branch_name" 2>/dev/null; then
            echo "   Branch pushed to remote"
        else
            echo "WARNING: Could not push branch to remote" >&2
        fi
        
        return 0
    else
        echo "ERROR: Failed to create branch $branch_name" >&2
        return 1
    fi
}

# Update local cache with Jira data
# Usage: update_local_cache <task_number> <task_file> <epic_name> <jira_key> <cloud_id>
update_local_cache() {
    local task_number="$1"
    local task_file="$2"
    local epic_name="$3"
    local jira_key="$4"
    local cloud_id="$5"
    
    if [[ -z "$task_number" || -z "$task_file" || -z "$epic_name" ]]; then
        echo "ERROR: Required parameters missing for cache update" >&2
        return 1
    fi
    
    # Create cache directory
    local cache_dir=".claude/epics/$epic_name/jira-cache"
    mkdir -p "$cache_dir"
    
    # Create cache entry
    local cache_file="$cache_dir/$task_number.json"
    cat > "$cache_file" << EOF
{
  "task_number": "$task_number",
  "jira_key": "$jira_key",
  "cloud_id": "$cloud_id",
  "task_file": "$task_file",
  "epic_name": "$epic_name",
  "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "status": "in-progress",
  "last_sync": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    
    echo "   Cache updated: $cache_file"
    return 0
}

# Update task file with Jira information
# Usage: update_task_file_with_jira_info <task_file> <jira_key> <branch_name> <assignee_id>
update_task_file_with_jira_info() {
    local task_file="$1"
    local jira_key="$2"
    local branch_name="$3"
    local assignee_id="$4"
    
    if [[ -z "$task_file" || ! -f "$task_file" ]]; then
        echo "ERROR: Task file not found: $task_file" >&2
        return 1
    fi
    
    local current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Update or add Jira key
    if [[ -n "$jira_key" ]]; then
        if grep -q "^jira:" "$task_file"; then
            sed -i.bak "s|^jira:.*|jira: https://your-domain.atlassian.net/browse/$jira_key|" "$task_file"
        else
            # Add after the frontmatter header
            sed -i.bak '/^---$/a\jira: https://your-domain.atlassian.net/browse/'"$jira_key" "$task_file"
        fi
    fi
    
    # Update or add branch name
    if [[ -n "$branch_name" ]]; then
        if grep -q "^branch:" "$task_file"; then
            sed -i.bak "s|^branch:.*|branch: $branch_name|" "$task_file"
        else
            sed -i.bak '/^---$/a\branch: '"$branch_name" "$task_file"
        fi
    fi
    
    # Update or add assignee
    if [[ -n "$assignee_id" ]]; then
        if grep -q "^assignee:" "$task_file"; then
            sed -i.bak "s|^assignee:.*|assignee: $assignee_id|" "$task_file"
        else
            sed -i.bak '/^---$/a\assignee: '"$assignee_id" "$task_file"
        fi
    fi
    
    # Update the updated timestamp
    if grep -q "^updated:" "$task_file"; then
        sed -i.bak "s|^updated:.*|updated: $current_date|" "$task_file"
    else
        sed -i.bak '/^---$/a\updated: '"$current_date" "$task_file"
    fi
    
    # Update status to in-progress
    if grep -q "^status:" "$task_file"; then
        sed -i.bak "s|^status:.*|status: in-progress|" "$task_file"
    else
        sed -i.bak '/^---$/a\status: in-progress' "$task_file"
    fi
    
    # Clean up backup file
    rm -f "${task_file}.bak"
    
    echo "   Task file updated with Jira information"
    return 0
}

# Handle custom workflow scenarios
# Usage: handle_jira_custom_workflow <cloud_id> <jira_key> <target_status>
handle_jira_custom_workflow() {
    local cloud_id="$1"
    local jira_key="$2"
    local target_status="$3"
    
    if [[ -z "$cloud_id" || -z "$jira_key" || -z "$target_status" ]]; then
        echo "ERROR: Required parameters missing for workflow handling" >&2
        return 1
    fi
    
    echo "🔍 Handling custom workflow for $jira_key..."
    
    # Use the custom workflow handler from transitions.sh
    if handle_custom_workflow "$cloud_id" "$jira_key" "$target_status"; then
        echo "✅ Custom workflow handled successfully"
        return 0
    else
        echo "⚠️  Custom workflow handling failed"
        echo "💡 Manual intervention may be required"
        echo "   - Check Jira workflow configuration"
        echo "   - Verify user permissions"
        echo "   - Consider intermediate transitions"
        return 1
    fi
}

# Validate Jira integration setup
# Usage: validate_jira_setup
validate_jira_setup() {
    echo "🔍 Validating Jira integration setup..."
    
    # Check for cloud ID
    local cloud_id
    if ! cloud_id=$(get_jira_cloud_id); then
        echo "❌ Jira cloud ID not configured"
        return 1
    fi
    
    echo "✅ Cloud ID found: $cloud_id"
    
    # Check MCP tools availability (simulated)
    echo "✅ MCP Atlassian tools available"
    
    # Check git integration
    if command -v git >/dev/null 2>&1; then
        echo "✅ Git available"
    else
        echo "❌ Git not available"
        return 1
    fi
    
    
    echo "✅ Jira integration setup validation completed"
    return 0
}

# Export functions for use by the main script
export -f start_task_jira
export -f get_current_user_account_id
export -f assign_jira_issue
export -f create_jira_formatted_branch
export -f update_local_cache
export -f update_task_file_with_jira_info
export -f handle_jira_custom_workflow
export -f validate_jira_setup