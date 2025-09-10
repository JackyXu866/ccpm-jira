#!/bin/bash

# Epic Sync to Jira Implementation
# This script syncs local epic.md files to Jira Epics using MCP Atlassian integration

# Function to sync an epic to Jira
sync_epic_to_jira() {
  local epic_name="$1"
  local epic_dir=".claude/epics/$epic_name"
  local epic_file="$epic_dir/epic.md"
  
  if [ ! -f "$epic_file" ]; then
    echo "❌ Epic file not found: $epic_file"
    return 1
  fi
  
  echo "🔄 Syncing epic to Jira: $epic_name"
  
  # Extract epic metadata
  local name=$(grep "^name:" "$epic_file" | head -1 | sed 's/^name: *//')
  local status=$(grep "^status:" "$epic_file" | head -1 | sed 's/^status: *//')
  local progress=$(grep "^progress:" "$epic_file" | head -1 | sed 's/^progress: *//')
  local github=$(grep "^github:" "$epic_file" | head -1 | sed 's/^github: *//')
  local created=$(grep "^created:" "$epic_file" | head -1 | sed 's/^created: *//')
  local updated=$(grep "^updated:" "$epic_file" | head -1 | sed 's/^updated: *//')
  local jira_url=$(grep "^jira:" "$epic_file" | head -1 | sed 's/^jira: *//')
  
  # Use epic name as title if name field is empty
  [ -z "$name" ] && name="$epic_name"
  [ -z "$status" ] && status="planning"
  [ -z "$progress" ] && progress="0%"
  
  # Extract epic description (content without frontmatter)
  local description=""
  if [ -f "$epic_file" ]; then
    description=$(sed '1,/^---$/d; 1,/^---$/d' "$epic_file")
  fi
  
  # Prepare Jira description with additional metadata
  local jira_description="$description"
  
  # Add metadata to description
  jira_description="$jira_description

## Epic Metadata
- **Status**: $status
- **Progress**: $progress
- **Local Epic**: $epic_name"
  
  # Add GitHub link if available
  [ -n "$github" ] && jira_description="$jira_description
- **GitHub**: $github"
  
  # Add creation/update timestamps
  [ -n "$created" ] && jira_description="$jira_description
- **Created**: $created"
  [ -n "$updated" ] && jira_description="$jira_description
- **Updated**: $updated"
  
  # Check if this is an update or creation
  local is_update=false
  local jira_issue_key=""
  
  if [ -n "$jira_url" ]; then
    # Extract issue key from Jira URL
    jira_issue_key=$(echo "$jira_url" | grep -o '[A-Z][A-Z]*-[0-9][0-9]*' | head -1)
    if [ -n "$jira_issue_key" ]; then
      is_update=true
      echo "📝 Updating existing Jira epic: $jira_issue_key"
    fi
  fi
  
  # Map local status to Jira status
  local jira_status="To Do"
  case "$status" in
    "planning"|"draft"|"") jira_status="To Do" ;;
    "in-progress"|"in_progress"|"active"|"started") jira_status="In Progress" ;;
    "completed"|"complete"|"done"|"closed"|"finished") jira_status="Done" ;;
    *) jira_status="To Do" ;;
  esac
  
  if [ "$is_update" = true ] && [ -n "$jira_issue_key" ]; then
    # Update existing epic
    echo "🔄 Updating Jira epic $jira_issue_key..."
    
    # Use Claude's MCP integration to update the epic
    # Note: This would typically call the MCP tools, but since we're in a script,
    # we'll create a marker file that can be processed by the calling script
    cat > "/tmp/jira-epic-update-$epic_name.json" << EOF
{
  "action": "update",
  "issue_key": "$jira_issue_key",
  "summary": "$name",
  "description": $(echo "$jira_description" | jq -R -s .),
  "status": "$jira_status",
  "epic_name": "$epic_name"
}
EOF
    
    echo "✅ Prepared update for epic: $jira_issue_key"
    
  else
    # Create new epic
    echo "🆕 Creating new Jira epic..."
    
    # For creation, we need to determine the project
    # This should be configurable, but for now we'll use a default approach
    local project_key="CCPM"  # Default project key
    
    # Check if there's a project configuration
    if [ -f "claude/config/jira-project.conf" ]; then
      project_key=$(cat "claude/config/jira-project.conf" | head -1)
    fi
    
    # Create marker file for epic creation
    cat > "/tmp/jira-epic-create-$epic_name.json" << EOF
{
  "action": "create",
  "project_key": "$project_key",
  "summary": "$name",
  "description": $(echo "$jira_description" | jq -R -s .),
  "issue_type": "Epic",
  "epic_name": "$epic_name"
}
EOF
    
    echo "✅ Prepared creation of new epic in project: $project_key"
  fi
  
  # Count and prepare task sync information
  local task_files=(.claude/epics/$epic_name/[0-9]*.md)
  local task_count=0
  
  for task_file in "${task_files[@]}"; do
    [ -f "$task_file" ] && ((task_count++))
  done
  
  if [ "$task_count" -gt 0 ]; then
    echo "📋 Found $task_count tasks to sync"
    
    # Prepare task sync data
    cat > "/tmp/jira-tasks-sync-$epic_name.json" << EOF
{
  "epic_name": "$epic_name",
  "task_count": $task_count,
  "tasks": [
EOF
    
    local first_task=true
    for task_file in "${task_files[@]}"; do
      [ -f "$task_file" ] || continue
      
      local task_name=$(grep "^name:" "$task_file" | head -1 | sed 's/^name: *//')
      local task_status=$(grep "^status:" "$task_file" | head -1 | sed 's/^status: *//')
      local task_jira=$(grep "^jira:" "$task_file" | head -1 | sed 's/^jira: *//')
      local task_description=$(sed '1,/^---$/d; 1,/^---$/d' "$task_file")
      
      [ -z "$task_name" ] && task_name="Task $(basename "$task_file" .md)"
      [ -z "$task_status" ] && task_status="open"
      
      # Map task status
      local jira_task_status="To Do"
      case "$task_status" in
        "open"|"") jira_task_status="To Do" ;;
        "in-progress"|"in_progress"|"active"|"started") jira_task_status="In Progress" ;;
        "closed"|"completed"|"complete"|"done") jira_task_status="Done" ;;
        *) jira_task_status="To Do" ;;
      esac
      
      # Add comma for subsequent tasks
      [ "$first_task" = false ] && echo "    ," >> "/tmp/jira-tasks-sync-$epic_name.json"
      first_task=false
      
      cat >> "/tmp/jira-tasks-sync-$epic_name.json" << EOF
    {
      "file": "$task_file",
      "name": "$task_name",
      "status": "$jira_task_status",
      "description": $(echo "$task_description" | jq -R -s .),
      "jira_url": "$task_jira"
    }
EOF
    done
    
    cat >> "/tmp/jira-tasks-sync-$epic_name.json" << EOF
  ]
}
EOF
    
    echo "✅ Prepared task sync data"
  fi
  
  # Update local epic file with sync metadata
  local current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  # Update the updated timestamp
  if grep -q "^updated:" "$epic_file"; then
    sed -i.bak "/^updated:/c\updated: $current_date" "$epic_file"
  else
    # Add updated field after the frontmatter header
    sed -i.bak '/^---$/a\updated: '"$current_date" "$epic_file"
  fi
  
  # Clean up backup file
  rm -f "${epic_file}.bak"
  
  echo ""
  echo "✅ Epic sync preparation completed!"
  echo "   Epic: $name"
  echo "   Status: $status → $jira_status"
  echo "   Tasks: $task_count"
  echo ""
  echo "📋 Next steps:"
  echo "   - Epic data prepared for Jira sync"
  if [ "$task_count" -gt 0 ]; then
    echo "   - Task data prepared for sub-issue creation"
  fi
  
  return 0
}

# Function to handle network failures gracefully
handle_jira_error() {
  local error_msg="$1"
  local epic_name="$2"
  
  echo "❌ Jira sync failed: $error_msg"
  echo ""
  echo "🔄 Fallback options:"
  echo "   1. Retry later when network is available"
  echo "   2. Sync to GitHub instead: /pm:epic-sync $epic_name"
  echo "   3. Work locally and sync later"
  echo ""
  
  # Log the error for debugging
  echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") - Jira sync failed for $epic_name: $error_msg" >> ".claude/logs/jira-sync-errors.log"
  
  return 1
}

# Function to map epic fields from local to Jira
map_epic_fields() {
  local epic_file="$1"
  local output_file="$2"
  
  # Field mapping:
  # name → Summary
  # status → Status (with workflow mapping)
  # progress → Custom field or description
  # github → Link in description
  # created/updated → System fields
  # description content → Description
  
  local name=$(grep "^name:" "$epic_file" | head -1 | sed 's/^name: *//')
  local status=$(grep "^status:" "$epic_file" | head -1 | sed 's/^status: *//')
  local progress=$(grep "^progress:" "$epic_file" | head -1 | sed 's/^progress: *//')
  local github=$(grep "^github:" "$epic_file" | head -1 | sed 's/^github: *//')
  
  cat > "$output_file" << EOF
{
  "summary": "$name",
  "status_mapping": {
    "local": "$status",
    "jira": "$(map_status_to_jira "$status")"
  },
  "progress": "$progress",
  "github_link": "$github"
}
EOF
}

# Function to map status values
map_status_to_jira() {
  local local_status="$1"
  
  case "$local_status" in
    "planning"|"draft"|"") echo "To Do" ;;
    "in-progress"|"in_progress"|"active"|"started") echo "In Progress" ;;
    "completed"|"complete"|"done"|"closed"|"finished") echo "Done" ;;
    *) echo "To Do" ;;
  esac
}

# Export functions for use by the main script
export -f sync_epic_to_jira
export -f handle_jira_error
export -f map_epic_fields
export -f map_status_to_jira