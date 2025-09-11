#!/bin/bash

# Parse command line options
while [[ $# -gt 0 ]]; do
  case $1 in
    --status=*)
      filter_status="${1#*=}"
      shift
      ;;
    --assignee=*)
      filter_assignee="${1#*=}"
      shift
      ;;
    --help|-h)
      echo "Usage: epic-list.sh [--status=STATUS] [--assignee=USER]"
      echo ""
      echo "Options:"
      echo "  --status=STATUS    Filter by status (planning, in-progress, completed)"
      echo "  --assignee=USER    Filter by assignee (Jira mode only)"
      echo "  --help, -h         Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

echo "Getting epics..."
echo ""
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

echo "📋 List mode: $([ "$jira_mode" = true ] && echo "Jira" || echo "Local")"
echo ""

# Delegate to appropriate implementation
if [ "$jira_mode" = true ]; then
  # Use Jira list implementation
  if [ -f "claude/lib/epic-list-jira.sh" ]; then
    source "claude/lib/epic-list-jira.sh"
    list_epics_from_jira "$filter_status" "$filter_assignee"
    exit $?
  else
    echo "❌ Jira list module not found: claude/lib/epic-list-jira.sh"
    echo "Falling back to local listing..."
    jira_mode=false
  fi
fi

if [ "$jira_mode" = false ]; then
  # Local epic listing (existing implementation)
  [ ! -d ".claude/epics" ] && echo "📁 No epics directory found. Create your first epic with: /pm:prd-parse <feature-name>" && exit 0
  [ -z "$(ls -d .claude/epics/*/ 2>/dev/null)" ] && echo "📁 No epics found. Create your first epic with: /pm:prd-parse <feature-name>" && exit 0
fi

echo "📚 Project Epics"
echo "================"
echo ""

# Initialize arrays to store epics by status
planning_epics=""
in_progress_epics=""
completed_epics=""

# Process all epics
for dir in .claude/epics/*/; do
  [ -d "$dir" ] || continue
  [ -f "$dir/epic.md" ] || continue

  # Extract metadata
  n=$(grep "^name:" "$dir/epic.md" | head -1 | sed 's/^name: *//')
  s=$(grep "^status:" "$dir/epic.md" | head -1 | sed 's/^status: *//' | tr '[:upper:]' '[:lower:]')
  p=$(grep "^progress:" "$dir/epic.md" | head -1 | sed 's/^progress: *//')

  # Defaults
  [ -z "$n" ] && n=$(basename "$dir")
  [ -z "$p" ] && p="0%"

  # Count tasks
  t=$(ls "$dir"[0-9]*.md 2>/dev/null | wc -l)

  # Format output
  entry="   📋 ${dir}epic.md - $p complete ($t tasks)"

  # Apply status filter if specified
  if [ -n "$filter_status" ]; then
    case "$filter_status" in
      planning)
        if [[ "$s" != "planning" && "$s" != "draft" && -n "$s" ]]; then
          continue
        fi
        ;;
      in-progress)
        if [[ "$s" != "in-progress" && "$s" != "in_progress" && "$s" != "active" && "$s" != "started" ]]; then
          continue
        fi
        ;;
      completed)
        if [[ "$s" != "completed" && "$s" != "complete" && "$s" != "done" && "$s" != "closed" && "$s" != "finished" ]]; then
          continue
        fi
        ;;
    esac
  fi

  # Categorize by status (handle various status values)
  case "$s" in
    planning|draft|"")
      planning_epics="${planning_epics}${entry}\n"
      ;;
    in-progress|in_progress|active|started)
      in_progress_epics="${in_progress_epics}${entry}\n"
      ;;
    completed|complete|done|closed|finished)
      completed_epics="${completed_epics}${entry}\n"
      ;;
    *)
      # Default to planning for unknown statuses
      planning_epics="${planning_epics}${entry}\n"
      ;;
  esac
done

# Display categorized epics
echo "📝 Planning:"
if [ -n "$planning_epics" ]; then
  echo -e "$planning_epics" | sed '/^$/d'
else
  echo "   (none)"
fi

echo ""
echo "🚀 In Progress:"
if [ -n "$in_progress_epics" ]; then
  echo -e "$in_progress_epics" | sed '/^$/d'
else
  echo "   (none)"
fi

echo ""
echo "✅ Completed:"
if [ -n "$completed_epics" ]; then
  echo -e "$completed_epics" | sed '/^$/d'
else
  echo "   (none)"
fi

# Summary
echo ""
echo "📊 Summary"
total=$(ls -d .claude/epics/*/ 2>/dev/null | wc -l)
tasks=$(find .claude/epics -name "[0-9]*.md" 2>/dev/null | wc -l)
echo "   Total epics: $total"
echo "   Total tasks: $tasks"

exit 0
