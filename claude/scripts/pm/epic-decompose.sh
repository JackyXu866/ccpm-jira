#!/bin/bash

epic_name="$1"

if [ -z "$epic_name" ]; then
  echo "❌ Please provide an epic name"
  echo "Usage: /pm:epic-decompose <epic-name>"
  exit 1
fi

echo "Decomposing epic into tasks..."
echo ""

# Check if epic exists
if [ ! -f ".claude/epics/$epic_name/epic.md" ]; then
  echo "❌ Epic not found: $epic_name"
  echo "Run: /pm:prd-parse $epic_name"
  exit 1
fi

# Check if PRD exists
prd_file=""
if [ -f ".claude/prds/$epic_name.md" ]; then
  prd_file=".claude/prds/$epic_name.md"
elif [ -f ".claude/epics/$epic_name/prd.md" ]; then
  prd_file=".claude/epics/$epic_name/prd.md"
else
  echo "❌ PRD not found for epic: $epic_name"
  echo "Expected locations:"
  echo "  - .claude/prds/$epic_name.md"
  echo "  - .claude/epics/$epic_name/prd.md"
  exit 1
fi

echo "📋 Using PRD: $prd_file"
echo ""

# Check for Jira configuration
jira_mode=false
if [ -f "claude/settings.local.json" ]; then
  if grep -q '"jira"' claude/settings.local.json && grep -q '"enabled": *true' claude/settings.local.json; then
    jira_mode=true
  fi
fi

# Check for MCP Atlassian capabilities
if command -v claude-mcp > /dev/null 2>&1; then
  jira_mode=true
elif [ -f ".claude/mcp-config.json" ] && grep -q "atlassian" ".claude/mcp-config.json"; then
  jira_mode=true
fi

echo "🔄 Decompose mode: $([ "$jira_mode" = true ] && echo "Jira" || echo "Local")"
echo ""

# Delegate to appropriate implementation
if [ "$jira_mode" = true ]; then
  # Use Jira decompose implementation
  if [ -f "claude/lib/epic-decompose-jira.sh" ]; then
    source "claude/lib/epic-decompose-jira.sh"
    decompose_epic_to_jira "$epic_name" "$prd_file"
  else
    echo "❌ Jira decompose module not found: claude/lib/epic-decompose-jira.sh"
    echo "Falling back to local decomposition..."
    jira_mode=false
  fi
fi

if [ "$jira_mode" = false ]; then
  # Fallback to local decomposition (existing implementation)
  echo "📋 Decomposing locally..."
  
  # Parse PRD and extract tasks
  echo "🔍 Parsing PRD for tasks..."
  
  # Create epic directory if it doesn't exist
  mkdir -p ".claude/epics/$epic_name"
  
  # Simple PRD parsing - look for task sections
  task_counter=1
  
  # Extract tasks from PRD (looking for ## Task patterns or numbered lists)
  awk '
    BEGIN { 
      in_tasks = 0
      task_num = 1
    }
    /^## Tasks?|^## Implementation Tasks?|^## Task List/ { 
      in_tasks = 1
      next 
    }
    /^## / && in_tasks { 
      in_tasks = 0 
    }
    in_tasks && /^[0-9]+\./ {
      # Extract task from numbered list
      gsub(/^[0-9]+\. */, "")
      if (length($0) > 0) {
        print task_num "|" $0
        task_num++
      }
    }
    in_tasks && /^- / {
      # Extract task from bullet list
      gsub(/^- */, "")
      if (length($0) > 0) {
        print task_num "|" $0
        task_num++
      }
    }
  ' "$prd_file" > /tmp/extracted-tasks.txt
  
  # Create task files
  if [ -s /tmp/extracted-tasks.txt ]; then
    while IFS='|' read -r task_num task_title; do
      task_file=".claude/epics/$epic_name/$task_num.md"
      
      # Generate task content
      cat > "$task_file" << EOF
---
name: $task_title
status: open
created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
updated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
depends_on: []
parallel: true
conflicts_with: []
---

# Task: $task_title

## Description
Task extracted from PRD: $epic_name

## Acceptance Criteria
- [ ] Task implementation complete
- [ ] Tests passing
- [ ] Documentation updated

## Technical Details
To be defined during implementation.

## Dependencies
None identified.

## Effort Estimate
- Size: M
- Hours: 4
- Parallel: true

## Definition of Done
- [ ] Implementation complete
- [ ] Code reviewed
- [ ] Tests passing
- [ ] Documentation updated
EOF
      
      echo "✅ Created task: $task_num - $task_title"
      
    done < /tmp/extracted-tasks.txt
  else
    echo "⚠️  No tasks found in PRD. Creating default task structure..."
    
    # Create a default task if no tasks were found
    cat > ".claude/epics/$epic_name/1.md" << EOF
---
name: Implement $epic_name
status: open
created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
updated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
depends_on: []
parallel: true
conflicts_with: []
---

# Task: Implement $epic_name

## Description
Main implementation task for epic: $epic_name

## Acceptance Criteria
- [ ] Epic requirements implemented
- [ ] Tests passing
- [ ] Documentation updated

## Technical Details
Refer to PRD: $prd_file

## Dependencies
None identified.

## Effort Estimate
- Size: L
- Hours: 8
- Parallel: true

## Definition of Done
- [ ] All epic requirements met
- [ ] Code reviewed
- [ ] Tests passing
- [ ] Documentation updated
EOF
    
    echo "✅ Created default task: 1 - Implement $epic_name"
  fi
  
  # Update epic with task information
  task_count=$(ls .claude/epics/$epic_name/[0-9]*.md 2>/dev/null | wc -l)
  current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  # Update epic frontmatter
  epic_file=".claude/epics/$epic_name/epic.md"
  if grep -q "^updated:" "$epic_file"; then
    sed -i.bak "/^updated:/c\updated: $current_date" "$epic_file"
  else
    sed -i.bak '/^---$/a\updated: '"$current_date" "$epic_file"
  fi
  
  # Add task summary to epic
  if ! grep -q "## Tasks Created" "$epic_file"; then
    cat >> "$epic_file" << EOF

## Tasks Created
Total tasks: $task_count
Parallel tasks: $task_count (can be worked on simultaneously)
Sequential tasks: 0 (have dependencies)
Estimated total effort: $((task_count * 4)) hours

Tasks are located in: .claude/epics/$epic_name/
EOF
  fi
  
  # Clean up backup file
  rm -f "${epic_file}.bak"
  rm -f /tmp/extracted-tasks.txt
  
  echo ""
  echo "✅ Epic decomposition completed!"
  echo "   Epic: $epic_name"
  echo "   Tasks created: $task_count"
  echo "   Tasks directory: .claude/epics/$epic_name/"
  echo ""
  echo "📋 Next steps:"
  echo "   - Review and refine task details"
  echo "   - Start working on tasks: /pm:issue-start <task-number>"
  echo "   - Sync to remote: /pm:epic-sync $epic_name"
fi

exit 0