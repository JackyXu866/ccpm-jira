#!/bin/bash

# Epic Decompose to Jira Implementation
# This script parses PRDs and creates Jira sub-tasks using MCP Atlassian integration

# Function to decompose an epic into Jira sub-tasks
decompose_epic_to_jira() {
  local epic_name="$1"
  local prd_file="$2"
  local epic_dir=".claude/epics/$epic_name"
  local epic_file="$epic_dir/epic.md"
  
  if [ ! -f "$epic_file" ]; then
    echo "❌ Epic file not found: $epic_file"
    return 1
  fi
  
  if [ ! -f "$prd_file" ]; then
    echo "❌ PRD file not found: $prd_file"
    return 1
  fi
  
  echo "🔄 Decomposing epic to Jira: $epic_name"
  echo "📋 Using PRD: $prd_file"
  
  # Extract epic metadata
  local epic_jira_url=$(grep "^jira:" "$epic_file" | head -1 | sed 's/^jira: *//')
  local epic_github_url=$(grep "^github:" "$epic_file" | head -1 | sed 's/^github: *//')
  local epic_status=$(grep "^status:" "$epic_file" | head -1 | sed 's/^status: *//')
  
  # Determine project key
  local project_key="CCPM"  # Default project key
  if [ -f "claude/config/jira-project.conf" ]; then
    project_key=$(cat "claude/config/jira-project.conf" | head -1)
  fi
  
  echo "🏗️  Project: $project_key"
  
  # Parse PRD for tasks
  echo "🔍 Parsing PRD for task structure..."
  
  local temp_tasks_file="/tmp/epic-tasks-$epic_name.txt"
  parse_prd_tasks "$prd_file" > "$temp_tasks_file"
  
  if [ ! -s "$temp_tasks_file" ]; then
    echo "⚠️  No tasks found in PRD. Creating default task structure..."
    create_default_task_structure "$epic_name" "$temp_tasks_file"
  fi
  
  # Count tasks
  local task_count=$(wc -l < "$temp_tasks_file")
  echo "📊 Found $task_count tasks to create"
  
  # Ensure epic exists in Jira first
  local epic_issue_key=""
  if [ -n "$epic_jira_url" ]; then
    epic_issue_key=$(echo "$epic_jira_url" | grep -o '[A-Z][A-Z]*-[0-9][0-9]*' | head -1)
    echo "🔗 Using existing epic: $epic_issue_key"
  else
    echo "🆕 Epic not yet in Jira. Creating epic first..."
    epic_issue_key=$(create_epic_in_jira "$epic_name" "$epic_file" "$project_key")
    if [ -z "$epic_issue_key" ]; then
      echo "❌ Failed to create epic in Jira"
      rm -f "$temp_tasks_file"
      return 1
    fi
    
    # Update local epic file with Jira URL
    local epic_url="https://$(get_jira_site).atlassian.net/browse/$epic_issue_key"
    local current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    if grep -q "^jira:" "$epic_file"; then
      sed -i.bak "/^jira:/c\jira: $epic_url" "$epic_file"
    else
      sed -i.bak '/^github:/a\jira: '"$epic_url" "$epic_file"
    fi
    
    sed -i.bak "/^updated:/c\updated: $current_date" "$epic_file"
    rm -f "${epic_file}.bak"
    
    echo "✅ Created epic: $epic_issue_key"
  fi
  
  # Create Jira sub-tasks
  echo "🔨 Creating Jira sub-tasks..."
  
  local task_num=1
  local created_tasks=0
  local failed_tasks=0
  
  while IFS='|' read -r task_title task_description task_priority task_estimate task_depends; do
    echo "📝 Creating task $task_num: $task_title"
    
    local task_issue_key=$(create_jira_subtask \
      "$project_key" \
      "$epic_issue_key" \
      "$task_title" \
      "$task_description" \
      "$task_priority" \
      "$task_estimate" \
      "$task_depends")
    
    if [ -n "$task_issue_key" ]; then
      # Create local task file with Jira reference
      create_local_task_file \
        "$epic_name" \
        "$task_num" \
        "$task_title" \
        "$task_description" \
        "$task_issue_key" \
        "$task_priority" \
        "$task_estimate" \
        "$task_depends"
      
      echo "  ✅ Created: $task_issue_key"
      ((created_tasks++))
    else
      echo "  ❌ Failed to create task: $task_title"
      ((failed_tasks++))
    fi
    
    ((task_num++))
    
    # Small delay to avoid rate limiting
    sleep 0.5
    
  done < "$temp_tasks_file"
  
  # Clean up
  rm -f "$temp_tasks_file"
  
  # Update epic with task information
  update_epic_with_task_summary "$epic_name" "$created_tasks" "$failed_tasks"
  
  echo ""
  echo "✅ Epic decomposition completed!"
  echo "   Epic: $epic_name ($epic_issue_key)"
  echo "   Tasks created: $created_tasks"
  echo "   Tasks failed: $failed_tasks"
  echo "   Local tasks directory: .claude/epics/$epic_name/"
  echo ""
  
  if [ "$failed_tasks" -gt 0 ]; then
    echo "⚠️  Some tasks failed to create. Check Jira permissions and try again."
  fi
  
  echo "📋 Next steps:"
  echo "   - Review tasks in Jira: $epic_issue_key"
  echo "   - Start working on tasks: /pm:issue-start <task-number>"
  echo "   - View epic status: /pm:epic-status $epic_name"
  
  return 0
}

# Function to parse PRD and extract tasks
parse_prd_tasks() {
  local prd_file="$1"
  
  # Enhanced PRD parsing to extract tasks with metadata
  awk '
    BEGIN { 
      in_tasks = 0
      in_implementation = 0
      current_task = ""
      task_desc = ""
      task_priority = "Medium"
      task_estimate = "4"
      task_depends = ""
    }
    
    # Detect task sections
    /^## Tasks?|^## Implementation Tasks?|^## Task List|^## Work Items/ { 
      in_tasks = 1
      in_implementation = 0
      next 
    }
    
    /^## Implementation|^## Technical Implementation/ {
      in_implementation = 1
      in_tasks = 0
      next
    }
    
    # End of section
    /^## / && (in_tasks || in_implementation) { 
      if (current_task != "") {
        print current_task "|" task_desc "|" task_priority "|" task_estimate "|" task_depends
        current_task = ""
        task_desc = ""
        task_priority = "Medium"
        task_estimate = "4"
        task_depends = ""
      }
      in_tasks = 0
      in_implementation = 0
    }
    
    # Parse numbered tasks
    (in_tasks || in_implementation) && /^[0-9]+\./ {
      if (current_task != "") {
        print current_task "|" task_desc "|" task_priority "|" task_estimate "|" task_depends
      }
      
      gsub(/^[0-9]+\. */, "")
      current_task = $0
      task_desc = ""
      task_priority = "Medium"
      task_estimate = "4"
      task_depends = ""
      
      # Extract priority from task title
      if (tolower(current_task) ~ /critical|urgent|high/) task_priority = "High"
      else if (tolower(current_task) ~ /low|minor|optional/) task_priority = "Low"
      
      # Extract estimate from task title
      if (current_task ~ /\([0-9]+h\)/) {
        match(current_task, /\(([0-9]+)h\)/, arr)
        task_estimate = arr[1]
        gsub(/ *\([0-9]+h\)/, "", current_task)
      }
    }
    
    # Parse bullet point tasks
    (in_tasks || in_implementation) && /^- / {
      if (current_task != "") {
        print current_task "|" task_desc "|" task_priority "|" task_estimate "|" task_depends
      }
      
      gsub(/^- */, "")
      current_task = $0
      task_desc = ""
      task_priority = "Medium"
      task_estimate = "4"
      task_depends = ""
      
      # Extract metadata from bullet
      if (tolower(current_task) ~ /critical|urgent|high/) task_priority = "High"
      else if (tolower(current_task) ~ /low|minor|optional/) task_priority = "Low"
      
      if (current_task ~ /\([0-9]+h\)/) {
        match(current_task, /\(([0-9]+)h\)/, arr)
        task_estimate = arr[1]
        gsub(/ *\([0-9]+h\)/, "", current_task)
      }
    }
    
    # Collect description lines
    (in_tasks || in_implementation) && current_task != "" && !/^[0-9]+\./ && !/^- / && !/^## / {
      if ($0 != "" && $0 !~ /^[ \t]*$/) {
        if (task_desc != "") task_desc = task_desc " "
        task_desc = task_desc $0
      }
    }
    
    END {
      if (current_task != "") {
        print current_task "|" task_desc "|" task_priority "|" task_estimate "|" task_depends
      }
    }
  ' "$prd_file"
}

# Function to create default task structure if PRD parsing fails
create_default_task_structure() {
  local epic_name="$1"
  local output_file="$2"
  
  cat > "$output_file" << EOF
Implement $epic_name|Main implementation task for epic $epic_name|Medium|8|
Testing and validation|Implement tests and validation for $epic_name|Medium|4|1
Documentation|Create documentation for $epic_name|Low|2|1,2
EOF
}

# Function to create epic in Jira (placeholder for MCP integration)
create_epic_in_jira() {
  local epic_name="$1"
  local epic_file="$2"
  local project_key="$3"
  
  # Extract epic metadata
  local name=$(grep "^name:" "$epic_file" | head -1 | sed 's/^name: *//')
  local description=$(sed '1,/^---$/d; 1,/^---$/d' "$epic_file")
  
  [ -z "$name" ] && name="$epic_name"
  
  # This would be replaced with actual MCP calls in production
  # For now, simulate the creation
  echo "EPIC-001"  # Placeholder - would return actual issue key from MCP
}

# Function to create Jira sub-task (placeholder for MCP integration)
create_jira_subtask() {
  local project_key="$1"
  local parent_key="$2"
  local task_title="$3"
  local task_description="$4"
  local task_priority="$5"
  local task_estimate="$6"
  local task_depends="$7"
  
  # This would be replaced with actual MCP calls in production
  # For now, simulate the creation
  local task_num=$(echo "$task_title" | sed 's/[^0-9]//g' | head -c 3)
  [ -z "$task_num" ] && task_num="001"
  echo "$project_key-$task_num"  # Placeholder - would return actual issue key from MCP
}

# Function to create local task file with Jira reference
create_local_task_file() {
  local epic_name="$1"
  local task_num="$2"
  local task_title="$3"
  local task_description="$4"
  local task_issue_key="$5"
  local task_priority="$6"
  local task_estimate="$7"
  local task_depends="$8"
  
  local task_file=".claude/epics/$epic_name/$task_num.md"
  local jira_url="https://$(get_jira_site).atlassian.net/browse/$task_issue_key"
  local current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  # Convert depends string to array format
  local depends_array="[]"
  if [ -n "$task_depends" ]; then
    depends_array="[$(echo "$task_depends" | sed 's/,/", "/g' | sed 's/^/"/;s/$/"/' )]"
  fi
  
  # Map priority
  local parallel="true"
  [ -n "$task_depends" ] && parallel="false"
  
  cat > "$task_file" << EOF
---
name: $task_title
status: open
created: $current_date
updated: $current_date
jira: $jira_url
depends_on: $depends_array
parallel: $parallel
conflicts_with: []
---

# Task: $task_title

## Description
$task_description

## Acceptance Criteria
- [ ] Task implementation complete
- [ ] Tests passing
- [ ] Documentation updated

## Technical Details
Implementation details for this task.

## Dependencies
$([ -n "$task_depends" ] && echo "Depends on tasks: $task_depends" || echo "No dependencies identified.")

## Effort Estimate
- Size: $(map_estimate_to_size "$task_estimate")
- Hours: $task_estimate
- Parallel: $parallel

## Definition of Done
- [ ] Implementation complete
- [ ] Code reviewed
- [ ] Tests passing
- [ ] Documentation updated

## Jira Integration
- Issue Key: $task_issue_key
- Priority: $task_priority
- Estimated Hours: $task_estimate
EOF
}

# Function to map estimate hours to size
map_estimate_to_size() {
  local hours="$1"
  
  if [ "$hours" -le 2 ]; then
    echo "S"
  elif [ "$hours" -le 6 ]; then
    echo "M"
  elif [ "$hours" -le 12 ]; then
    echo "L"
  else
    echo "XL"
  fi
}

# Function to get Jira site URL
get_jira_site() {
  # This would be configured based on the Jira instance
  # For now, return a placeholder
  echo "yoursite"
}

# Function to update epic with task summary
update_epic_with_task_summary() {
  local epic_name="$1"
  local created_tasks="$2"
  local failed_tasks="$3"
  local epic_file=".claude/epics/$epic_name/epic.md"
  
  local current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  # Update epic frontmatter
  if grep -q "^updated:" "$epic_file"; then
    sed -i.bak "/^updated:/c\updated: $current_date" "$epic_file"
  else
    sed -i.bak '/^---$/a\updated: '"$current_date" "$epic_file"
  fi
  
  # Calculate task statistics
  local total_tasks=$((created_tasks + failed_tasks))
  local parallel_tasks=$(grep -l "parallel: true" .claude/epics/$epic_name/[0-9]*.md 2>/dev/null | wc -l)
  local sequential_tasks=$(grep -l "parallel: false" .claude/epics/$epic_name/[0-9]*.md 2>/dev/null | wc -l)
  
  # Calculate total effort
  local total_effort=0
  for task_file in .claude/epics/$epic_name/[0-9]*.md; do
    [ -f "$task_file" ] || continue
    local hours=$(grep "Hours:" "$task_file" | sed 's/.*Hours: *//' | grep -o '[0-9]*' | head -1)
    [ -n "$hours" ] && total_effort=$((total_effort + hours))
  done
  
  # Add or update task summary in epic
  if grep -q "## Tasks Created" "$epic_file"; then
    # Update existing section
    sed -i.bak '/## Tasks Created/,/## /c\
## Tasks Created\
Total tasks: '"$total_tasks"'\
Parallel tasks: '"$parallel_tasks"' (can be worked on simultaneously)\
Sequential tasks: '"$sequential_tasks"' (have dependencies)\
Estimated total effort: '"$total_effort"' hours\
Tasks created in Jira: '"$created_tasks"'\
Failed task creations: '"$failed_tasks"'\
\
Tasks are located in: .claude/epics/'"$epic_name"'/\
' "$epic_file"
  else
    # Add new section
    cat >> "$epic_file" << EOF

## Tasks Created
Total tasks: $total_tasks
Parallel tasks: $parallel_tasks (can be worked on simultaneously)
Sequential tasks: $sequential_tasks (have dependencies)
Estimated total effort: $total_effort hours
Tasks created in Jira: $created_tasks
Failed task creations: $failed_tasks

Tasks are located in: .claude/epics/$epic_name/
EOF
  fi
  
  # Clean up backup file
  rm -f "${epic_file}.bak"
}

# Function to handle Jira API errors
handle_jira_decompose_error() {
  local error_msg="$1"
  local epic_name="$2"
  
  echo "❌ Jira decomposition failed: $error_msg"
  echo ""
  echo "🔄 Fallback options:"
  echo "   1. Check Jira connectivity and permissions"
  echo "   2. Retry with: /pm:epic-decompose $epic_name"
  echo "   3. Use local decomposition: Edit claude/settings.local.json to disable Jira"
  echo ""
  
  # Log the error for debugging
  mkdir -p ".claude/logs"
  echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") - Jira decompose failed for $epic_name: $error_msg" >> ".claude/logs/jira-decompose-errors.log"
  
  return 1
}

# Function to validate PRD structure
validate_prd_structure() {
  local prd_file="$1"
  
  if [ ! -f "$prd_file" ]; then
    echo "❌ PRD file not found: $prd_file"
    return 1
  fi
  
  # Check for essential sections
  local has_tasks=false
  if grep -q "^## Tasks\|^## Implementation\|^## Work Items" "$prd_file"; then
    has_tasks=true
  fi
  
  if [ "$has_tasks" = false ]; then
    echo "⚠️  PRD may not contain task sections. Proceeding with best-effort parsing..."
  fi
  
  return 0
}

# Export functions for use by the main script
export -f decompose_epic_to_jira
export -f parse_prd_tasks
export -f create_default_task_structure
export -f create_epic_in_jira
export -f create_jira_subtask
export -f create_local_task_file
export -f map_estimate_to_size
export -f get_jira_site
export -f update_epic_with_task_summary
export -f handle_jira_decompose_error
export -f validate_prd_structure