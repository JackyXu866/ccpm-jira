#!/bin/bash

echo "Getting status..."
echo ""
echo ""

# Check if Jira is configured
JIRA_CONFIGURED=false
if [ -f "claude/config/jira-settings.json" ] && [ -s "claude/config/jira-settings.json" ]; then
  # Source the Jira adapter
  if [ -f "claude/scripts/adapters/jira-adapter.sh" ]; then
    source claude/scripts/adapters/jira-adapter.sh
    JIRA_CONFIGURED=true
  fi
fi

echo "📊 Project Status"
echo "================"
echo ""

# Show data source
if [ "$JIRA_CONFIGURED" = true ]; then
  echo "🔌 Source: Jira"
  
  # Get project info
  PROJECT_KEY=$(jq -r '.project_key // ""' claude/config/jira-settings.json 2>/dev/null)
  if [ -n "$PROJECT_KEY" ]; then
    echo "📁 Project: $PROJECT_KEY"
    echo ""
    
    # Get Jira issues
    echo "📝 Issues:"
    
    # Use JQL to get all issues for the project
    JQL="project = $PROJECT_KEY ORDER BY key DESC"
    
    # Get issues using the adapter
    ISSUES=$(jira_search "$JQL" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$ISSUES" ]; then
      # Count by status
      todo_count=0
      in_progress_count=0
      done_count=0
      total_count=0
      
      # Parse the JSON response
      while IFS= read -r issue; do
        key=$(echo "$issue" | jq -r '.key // ""')
        status=$(echo "$issue" | jq -r '.fields.status.name // ""')
        summary=$(echo "$issue" | jq -r '.fields.summary // ""')
        issuetype=$(echo "$issue" | jq -r '.fields.issuetype.name // ""')
        
        if [ -n "$key" ]; then
          total_count=$((total_count + 1))
          
          # Map Jira status to our categories
          case "$status" in
            "To Do"|"Open"|"Backlog")
              todo_count=$((todo_count + 1))
              ;;
            "In Progress"|"In Development"|"In Review")
              in_progress_count=$((in_progress_count + 1))
              ;;
            "Done"|"Closed"|"Resolved")
              done_count=$((done_count + 1))
              ;;
            *)
              # Default to todo for unknown statuses
              todo_count=$((todo_count + 1))
              ;;
          esac
        fi
      done < <(echo "$ISSUES" | jq -c '.[]' 2>/dev/null)
      
      echo "  To Do: $todo_count"
      echo "  In Progress: $in_progress_count"
      echo "  Done: $done_count"
      echo "  Total: $total_count"
      
      # Show recent issues
      if [ $total_count -gt 0 ]; then
        echo ""
        echo "📋 Recent Issues:"
        echo "$ISSUES" | jq -r '.[] | "  \(.key): \(.fields.summary) [\(.fields.status.name)]"' 2>/dev/null | head -5
      fi
    else
      echo "  ⚠️ Could not fetch Jira issues"
      echo "  Check your Jira configuration with: /pm:jira-init"
    fi
  else
    echo "  ⚠️ No Jira project configured"
    echo "  Run: /pm:jira-init to configure"
  fi
else
  # Fall back to GitHub/local data
  echo "🔌 Source: Local/GitHub"
  echo ""
  
  echo "📄 PRDs:"
  if [ -d ".claude/prds" ]; then
    total=$(ls .claude/prds/*.md 2>/dev/null | wc -l)
    echo "  Total: $total"
  else
    echo "  No PRDs found"
  fi

  echo ""
  echo "📚 Epics:"
  if [ -d ".claude/epics" ]; then
    total=$(ls -d .claude/epics/*/ 2>/dev/null | wc -l)
    echo "  Total: $total"
  else
    echo "  No epics found"
  fi

  echo ""
  echo "📝 Tasks:"
  if [ -d ".claude/epics" ]; then
    total=$(find .claude/epics -name "[0-9]*.md" 2>/dev/null | wc -l)
    open=$(find .claude/epics -name "[0-9]*.md" -exec grep -l "^status: *open" {} \; 2>/dev/null | wc -l)
    closed=$(find .claude/epics -name "[0-9]*.md" -exec grep -l "^status: *closed" {} \; 2>/dev/null | wc -l)
    echo "  Open: $open"
    echo "  Closed: $closed"
    echo "  Total: $total"
  else
    echo "  No tasks found"
  fi
fi

echo ""
echo "💡 Tip: Use /pm:help for available commands"

exit 0