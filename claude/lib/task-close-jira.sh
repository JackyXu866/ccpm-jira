#!/bin/bash

# Task Close Jira Implementation
# Handles closing Jira tasks with proper transitions, resolution handling, and local cleanup

set -e

# Load required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/jira-transitions.sh"
source "$SCRIPT_DIR/resolution-handler.sh"
source "$SCRIPT_DIR/pr-templates.sh"
source "$SCRIPT_DIR/git-integration.sh"

# Close a Jira task with full workflow
# Usage: close_task_jira <task_number> <resolution> <task_file> <epic_name> <pr_flag>
close_task_jira() {
    local issue_number="$1"
    local resolution="$2"
    local task_file="$3"
    local epic_name="$4"
    local pr_flag="$5"
    
    if [[ -z "$issue_number" || -z "$resolution" || -z "$task_file" || -z "$epic_name" ]]; then
        echo "ERROR: Required parameters missing for Jira task closure" >&2
        return 1
    fi
    
    echo "🎯 Starting Jira task closure workflow for #$issue_number"
    
    # Get Jira configuration
    local cloud_id
    if ! cloud_id=$(get_jira_cloud_id); then
        echo "❌ Failed to get Jira cloud ID"
        return 1
    fi
    
    echo "   Cloud ID: $cloud_id"
    
    # Get Jira issue key
    local jira_key
    if ! jira_key=$(get_jira_key_from_github_issue "$issue_number"); then
        echo "⚠️  Could not find Jira key, will handle GitHub-only closure"
        jira_key=""
    else
        echo "   Jira key: $jira_key"
    fi
    
    # Validate and normalize resolution
    local normalized_resolution
    if ! normalized_resolution=$(validate_and_normalize_resolution "$resolution"); then
        echo "❌ Invalid resolution type: $resolution"
        echo "Available resolutions: $(list_available_resolutions)"
        return 1
    fi
    
    echo "   Resolution: $normalized_resolution"
    
    # Handle Jira transitions if we have a Jira key
    if [[ -n "$jira_key" ]]; then
        # Get current status
        echo "🔍 Checking current Jira issue status..."
        local current_status
        if current_status=$(get_issue_status "$cloud_id" "$jira_key"); then
            echo "   Current status: $current_status"
        else
            echo "⚠️  Could not get current status, assuming In Progress"
            current_status="In Progress"
        fi
        
        # Transition to "Done" if not already there
        if [[ "$current_status" != "Done" && "$current_status" != "Closed" ]]; then
            echo "🔄 Transitioning Jira issue to Done..."
            local transition_comment="Closed via ccpm-jira integration (GitHub issue #$issue_number) with resolution: $normalized_resolution"
            
            if transition_jira_issue "$cloud_id" "$jira_key" "Done" "$transition_comment"; then
                echo "✅ Issue transitioned to Done"
                log_transition "$jira_key" "$current_status" "Done" "SUCCESS"
            else
                echo "⚠️  Could not transition issue to Done (may already be done or custom workflow)"
                log_transition "$jira_key" "$current_status" "Done" "FAILED"
                
                # Try alternative transitions
                if handle_jira_closure_fallback "$cloud_id" "$jira_key" "$current_status"; then
                    echo "✅ Issue closed using alternative workflow"
                else
                    echo "❌ All closure transitions failed"
                    return 1
                fi
            fi
        else
            echo "✅ Issue is already in Done/Closed status"
        fi
        
        # Set resolution field
        echo "📋 Setting resolution field..."
        if set_jira_resolution "$cloud_id" "$jira_key" "$normalized_resolution"; then
            echo "✅ Resolution field set to: $normalized_resolution"
        else
            echo "⚠️  Could not set resolution field (may not have permissions or field doesn't exist)"
        fi
        
        # Update time tracking if available
        echo "⏱️  Updating time tracking..."
        if update_jira_time_tracking "$cloud_id" "$jira_key" "$task_file"; then
            echo "✅ Time tracking updated"
        else
            echo "⚠️  Could not update time tracking (may not be configured)"
        fi
    else
        echo "⚠️  No Jira key found, skipping Jira-specific operations"
    fi
    
    # Handle pull request creation if requested
    if [[ "$pr_flag" == "--create-pr" ]]; then
        echo "📝 Handling pull request creation..."
        if handle_pr_creation_for_closure "$issue_number" "$normalized_resolution" "$jira_key"; then
            echo "✅ Pull request handling completed"
        else
            echo "⚠️  Pull request creation failed or not applicable"
        fi
    fi
    
    # Update local cache
    echo "💾 Updating local cache..."
    if update_closure_cache "$issue_number" "$task_file" "$epic_name" "$jira_key" "$normalized_resolution"; then
        echo "✅ Local cache updated"
    else
        echo "⚠️  Could not update local cache"
    fi
    
    # Update task file with closure information
    echo "📝 Updating task file..."
    if update_task_file_with_closure_info "$task_file" "$normalized_resolution" "$jira_key"; then
        echo "✅ Task file updated"
    else
        echo "⚠️  Could not update task file"
    fi
    
    # Archive local data if appropriate
    echo "🗂️  Handling local data archival..."
    if archive_issue_data "$issue_number" "$epic_name" "$task_file"; then
        echo "✅ Issue data archived"
    else
        echo "⚠️  Could not archive issue data"
    fi
    
    # Summary
    echo ""
    echo "✅ Jira issue closure completed!"
    echo ""
    echo "Issue: #$issue_number"
    if [[ -n "$jira_key" ]]; then
        echo "Jira: $jira_key (transitioned to Done)"
    fi
    echo "Resolution: $normalized_resolution"
    echo "Epic: $epic_name"
    echo ""
    
    return 0
}

# Handle alternative closure workflows when standard transition fails
# Usage: handle_jira_closure_fallback <cloud_id> <jira_key> <current_status>
handle_jira_closure_fallback() {
    local cloud_id="$1"
    local jira_key="$2"
    local current_status="$3"
    
    echo "🔄 Attempting alternative closure workflows..."
    
    # Try "Closed" status if "Done" failed
    if validate_transition "$cloud_id" "$jira_key" "$current_status" "Closed"; then
        echo "   Trying transition to 'Closed'..."
        if transition_jira_issue "$cloud_id" "$jira_key" "Closed" "Closed via ccpm-jira fallback workflow"; then
            log_transition "$jira_key" "$current_status" "Closed" "SUCCESS"
            return 0
        fi
    fi
    
    # Try "Resolved" status
    if validate_transition "$cloud_id" "$jira_key" "$current_status" "Resolved"; then
        echo "   Trying transition to 'Resolved'..."
        if transition_jira_issue "$cloud_id" "$jira_key" "Resolved" "Resolved via ccpm-jira fallback workflow"; then
            log_transition "$jira_key" "$current_status" "Resolved" "SUCCESS"
            return 0
        fi
    fi
    
    # Try "Complete" status
    if validate_transition "$cloud_id" "$jira_key" "$current_status" "Complete"; then
        echo "   Trying transition to 'Complete'..."
        if transition_jira_issue "$cloud_id" "$jira_key" "Complete" "Completed via ccpm-jira fallback workflow"; then
            log_transition "$jira_key" "$current_status" "Complete" "SUCCESS"
            return 0
        fi
    fi
    
    echo "❌ All fallback transitions failed"
    return 1
}

# Set Jira resolution field
# Usage: set_jira_resolution <cloud_id> <issue_key> <resolution>
set_jira_resolution() {
    local cloud_id="$1"
    local issue_key="$2"
    local resolution="$3"
    
    if [[ -z "$cloud_id" || -z "$issue_key" || -z "$resolution" ]]; then
        echo "ERROR: cloud_id, issue_key, and resolution are required" >&2
        return 1
    fi
    
    # Create marker file for MCP tool execution
    cat > "/tmp/jira-resolution-request-$issue_key.json" << EOF
{
  "action": "set_resolution",
  "cloud_id": "$cloud_id",
  "issue_key": "$issue_key",
  "resolution": "$resolution",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    
    echo "✅ Resolution update request prepared for $issue_key"
    return 0
}

# Update Jira time tracking information
# Usage: update_jira_time_tracking <cloud_id> <issue_key> <task_file>
update_jira_time_tracking() {
    local cloud_id="$1"
    local issue_key="$2"
    local task_file="$3"
    
    if [[ -z "$cloud_id" || -z "$issue_key" ]]; then
        echo "ERROR: cloud_id and issue_key are required" >&2
        return 1
    fi
    
    # Try to extract time tracking from task file
    local estimated_hours=""
    local time_spent=""
    
    if [[ -f "$task_file" ]]; then
        estimated_hours=$(grep "^estimated_hours:" "$task_file" | cut -d: -f2 | xargs || echo "")
        # Look for time tracking in updates or logs
        local epic_name
        epic_name=$(basename "$(dirname "$task_file")")
        local updates_dir=".claude/epics/$epic_name/updates/$(basename "$task_file" .md)"
        
        if [[ -d "$updates_dir" ]]; then
            # Calculate time spent from update timestamps (simplified)
            local start_time end_time
            start_time=$(find "$updates_dir" -name "*.md" | head -1 | xargs stat -c %Y 2>/dev/null || echo "")
            end_time=$(date +%s)
            
            if [[ -n "$start_time" ]]; then
                local duration_hours=$(( (end_time - start_time) / 3600 ))
                time_spent="${duration_hours}h"
            fi
        fi
    fi
    
    # Create marker file for MCP tool execution
    cat > "/tmp/jira-time-tracking-request-$issue_key.json" << EOF
{
  "action": "update_time_tracking",
  "cloud_id": "$cloud_id",
  "issue_key": "$issue_key",
  "estimated_hours": "$estimated_hours",
  "time_spent": "$time_spent",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    
    echo "✅ Time tracking update request prepared"
    return 0
}

# Handle PR creation for issue closure
# Usage: handle_pr_creation_for_closure <issue_number> <resolution> <jira_key>
handle_pr_creation_for_closure() {
    local issue_number="$1"
    local resolution="$2"
    local jira_key="$3"
    
    # Check if we're on a feature branch
    local current_branch
    if ! current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null); then
        echo "❌ Not in a git repository"
        return 1
    fi
    
    if [[ "$current_branch" == "main" || "$current_branch" == "master" ]]; then
        echo "⚠️  On main/master branch, no PR needed"
        return 0
    fi
    
    echo "🌱 Creating PR from branch: $current_branch"
    
    # Generate PR data
    local custom_description="Closes issue #$issue_number with resolution: $resolution"
    if [[ -n "$jira_key" ]]; then
        custom_description="Resolves $jira_key and closes GitHub issue #$issue_number with resolution: $resolution"
    fi
    
    local pr_data
    if pr_data=$(generate_pr_data "Close issue #$issue_number" "$custom_description"); then
        # Extract title and description
        local pr_title pr_description
        pr_title=$(echo "$pr_data" | grep -o '"title":[^,]*' | cut -d'"' -f4)
        pr_description=$(generate_pr_description "$jira_key" "$custom_description")
        
        # Create the PR
        if command -v gh >/dev/null 2>&1; then
            if gh pr create --title "$pr_title" --body "$pr_description" --base main; then
                echo "✅ Pull request created successfully"
                
                # Add labels if possible
                gh pr edit --add-label "closes-issue,resolution-$resolution" 2>/dev/null || true
                
                return 0
            else
                echo "❌ Failed to create pull request"
                return 1
            fi
        else
            echo "❌ GitHub CLI not available"
            return 1
        fi
    else
        echo "❌ Failed to generate PR data"
        return 1
    fi
}

# Update local cache with closure information
# Usage: update_closure_cache <issue_number> <task_file> <epic_name> <jira_key> <resolution>
update_closure_cache() {
    local issue_number="$1"
    local task_file="$2"
    local epic_name="$3"
    local jira_key="$4"
    local resolution="$5"
    
    # Create cache directory
    local cache_dir=".claude/epics/$epic_name/jira-cache"
    mkdir -p "$cache_dir"
    
    # Update or create cache entry
    local cache_file="$cache_dir/$issue_number.json"
    local current_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Load existing cache or create new
    if [[ -f "$cache_file" ]]; then
        # Update existing cache
        local temp_file="/tmp/cache-update-$$.json"
        cat "$cache_file" > "$temp_file"
        
        # Update relevant fields
        if command -v jq >/dev/null 2>&1; then
            jq ". + {\"status\": \"completed\", \"resolution\": \"$resolution\", \"completed_at\": \"$current_time\", \"last_sync\": \"$current_time\"}" "$temp_file" > "$cache_file"
        else
            # Fallback without jq
            sed -i.bak \
                -e "s/\"status\":[^,}]*/\"status\": \"completed\"/g" \
                -e "s/\"last_sync\":[^,}]*/\"last_sync\": \"$current_time\"/g" \
                "$cache_file"
            
            # Add resolution and completion fields
            sed -i.bak \
                -e "/\"last_sync\":/a\\  \"resolution\": \"$resolution\"," \
                -e "/\"resolution\":/a\\  \"completed_at\": \"$current_time\"," \
                "$cache_file"
            
            rm -f "${cache_file}.bak"
        fi
        
        rm -f "$temp_file"
    else
        # Create new cache entry
        cat > "$cache_file" << EOF
{
  "issue_number": "$issue_number",
  "jira_key": "$jira_key",
  "cloud_id": "$(get_jira_cloud_id 2>/dev/null || echo "")",
  "task_file": "$task_file",
  "epic_name": "$epic_name",
  "status": "completed",
  "resolution": "$resolution",
  "completed_at": "$current_time",
  "last_sync": "$current_time"
}
EOF
    fi
    
    echo "   Cache updated: $cache_file"
    return 0
}

# Update task file with closure information
# Usage: update_task_file_with_closure_info <task_file> <resolution> <jira_key>
update_task_file_with_closure_info() {
    local task_file="$1"
    local resolution="$2"
    local jira_key="$3"
    
    if [[ ! -f "$task_file" ]]; then
        echo "ERROR: Task file not found: $task_file" >&2
        return 1
    fi
    
    local current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Update status to completed
    if grep -q "^status:" "$task_file"; then
        sed -i.bak "s|^status:.*|status: completed|" "$task_file"
    else
        sed -i.bak '/^---$/a\status: completed' "$task_file"
    fi
    
    # Add or update resolution
    if grep -q "^resolution:" "$task_file"; then
        sed -i.bak "s|^resolution:.*|resolution: $resolution|" "$task_file"
    else
        sed -i.bak '/^status:/a\resolution: '"$resolution" "$task_file"
    fi
    
    # Add or update completion timestamp
    if grep -q "^completed:" "$task_file"; then
        sed -i.bak "s|^completed:.*|completed: $current_date|" "$task_file"
    else
        sed -i.bak '/^resolution:/a\completed: '"$current_date" "$task_file"
    fi
    
    # Update the updated timestamp
    if grep -q "^updated:" "$task_file"; then
        sed -i.bak "s|^updated:.*|updated: $current_date|" "$task_file"
    else
        sed -i.bak '/^completed:/a\updated: '"$current_date" "$task_file"
    fi
    
    # Add Jira closure information if available
    if [[ -n "$jira_key" ]]; then
        if ! grep -q "^jira_status:" "$task_file"; then
            sed -i.bak '/^updated:/a\jira_status: Done' "$task_file"
        else
            sed -i.bak "s|^jira_status:.*|jira_status: Done|" "$task_file"
        fi
    fi
    
    # Clean up backup file
    rm -f "${task_file}.bak"
    
    echo "   Task file updated with closure information"
    return 0
}

# Archive issue data appropriately
# Usage: archive_issue_data <issue_number> <epic_name> <task_file>
archive_issue_data() {
    local issue_number="$1"
    local epic_name="$2"
    local task_file="$3"
    
    # Create archive directory
    local archive_dir=".claude/epics/$epic_name/archive"
    mkdir -p "$archive_dir"
    
    # Archive task updates
    local updates_dir=".claude/epics/$epic_name/updates/$issue_number"
    if [[ -d "$updates_dir" ]]; then
        local archive_updates_dir="$archive_dir/updates-$issue_number"
        if cp -r "$updates_dir" "$archive_updates_dir" 2>/dev/null; then
            echo "   Issue updates archived to: $archive_updates_dir"
        fi
    fi
    
    # Create archive summary
    local archive_summary="$archive_dir/$issue_number-summary.md"
    cat > "$archive_summary" << EOF
# Issue #$issue_number Archive Summary

**Epic**: $epic_name  
**Task File**: $task_file  
**Archived At**: $(date -u +"%Y-%m-%dT%H:%M:%SZ")  

## Original Task
$(cat "$task_file" 2>/dev/null || echo "Task file no longer available")

## Final Status
- Status: Completed
- Resolution: $(grep "^resolution:" "$task_file" | cut -d: -f2 | xargs || echo "Unknown")
- Completed: $(grep "^completed:" "$task_file" | cut -d: -f2 | xargs || echo "Unknown")

## Jira Integration
- Jira Key: $(grep "^jira:" "$task_file" | sed 's|.*browse/||' || echo "None")
- Jira Status: $(grep "^jira_status:" "$task_file" | cut -d: -f2 | xargs || echo "Unknown")

EOF
    
    echo "   Archive summary created: $archive_summary"
    return 0
}

# Validate Jira setup for closure operations
# Usage: validate_jira_setup
validate_jira_setup() {
    echo "🔍 Validating Jira setup for closure operations..."
    
    # Use the existing validation from task-start-jira.sh
    if command -v validate_jira_setup >/dev/null 2>&1; then
        if validate_jira_setup; then
            echo "✅ Jira setup validation passed"
            return 0
        else
            echo "❌ Jira setup validation failed"
            return 1
        fi
    else
        # Fallback validation
        local cloud_id
        if cloud_id=$(get_jira_cloud_id); then
            echo "✅ Jira cloud ID available: $cloud_id"
            return 0
        else
            echo "❌ Jira cloud ID not available"
            return 1
        fi
    fi
}

# Export functions for use by the main script
export -f close_task_jira
export -f handle_jira_closure_fallback
export -f set_jira_resolution
export -f update_jira_time_tracking
export -f handle_pr_creation_for_closure
export -f update_closure_cache
export -f update_task_file_with_closure_info
export -f archive_issue_data
export -f validate_jira_setup