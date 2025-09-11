#!/bin/bash

epic_name="$1"

if [ -z "$epic_name" ]; then
  echo "❌ Please provide an epic name"
  echo "Usage: /pm:epic-sync <epic-name>"
  exit 1
fi

echo "Syncing epic to Jira..."
echo ""
echo ""

epic_dir=".claude/epics/$epic_name"
epic_file="$epic_dir/epic.md"

if [ ! -f "$epic_file" ]; then
  echo "❌ Epic not found: $epic_name"
  echo ""
  echo "Available epics:"
  for dir in .claude/epics/*/; do
    [ -d "$dir" ] && echo "  • $(basename "$dir")"
  done
  exit 1
fi

# Check for Jira configuration
if [ ! -f "claude/settings.local.json" ] || ! grep -q '"jira"' claude/settings.local.json || ! grep -q '"enabled": *true' claude/settings.local.json; then
  echo "❌ Jira integration not configured"
  echo ""
  echo "To configure Jira:"
  echo "1. Run: /pm:jira-init"
  echo "2. Connect MCP: /mcp atlassian"
  exit 1
fi

# Extract epic metadata
status=$(grep "^status:" "$epic_file" | head -1 | sed 's/^status: *//')
progress=$(grep "^progress:" "$epic_file" | head -1 | sed 's/^progress: *//')
jira_key=$(grep "^jira:" "$epic_file" | head -1 | sed 's/^jira: *//')

echo "📚 Epic: $epic_name"
echo "  Status: ${status:-planning}"
echo "  Progress: ${progress:-0%}"
[ -n "$jira_key" ] && echo "  Jira: $jira_key"
echo ""

# Count tasks
task_count=0
for task_file in "$epic_dir"/[0-9]*.md; do
  [ -f "$task_file" ] || continue
  ((task_count++))
done

if [ $task_count -eq 0 ]; then
  echo "❌ No tasks found in epic"
  echo "Run: /pm:epic-decompose $epic_name"
  exit 1
fi

echo "📝 Found $task_count tasks to sync"
echo ""

# Check if epic already exists in Jira
if [ -n "$jira_key" ]; then
  echo "✓ Epic already linked to Jira: $jira_key"
  echo "  Syncing updates..."
else
  echo "🆕 Creating new epic in Jira..."
  echo "  This will create an Epic and $task_count Story/Task issues"
fi

echo ""
echo "🔄 Delegating to Claude for Jira sync..."
echo ""
echo "Please use the MCP Atlassian tools to:"
echo "1. Create/update the Epic in Jira"
echo "2. Create Story/Task issues for each task"
echo "3. Link tasks to the Epic"
echo "4. Update local files with Jira keys"
echo ""
echo "Epic details:"
echo "- Name: $epic_name"
echo "- Local path: $epic_dir"
echo "- Tasks: $task_count"

exit 0