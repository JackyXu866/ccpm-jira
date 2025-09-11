#!/bin/bash

epic_name="$1"

echo "Syncing with Jira..."
echo ""
echo ""

# Check Jira configuration
if [ ! -f "claude/settings.local.json" ] || ! grep -q '"jira"' claude/settings.local.json || ! grep -q '"enabled": *true' claude/settings.local.json; then
  echo "❌ Jira integration not configured"
  echo ""
  echo "To configure Jira:"
  echo "1. Run: /pm:jira-init"
  echo "2. Connect MCP: /mcp atlassian"
  exit 1
fi

if [ -n "$epic_name" ]; then
  # Sync specific epic
  echo "🔄 Syncing epic: $epic_name"
  
  if [ ! -d ".claude/epics/$epic_name" ]; then
    echo "❌ Epic not found: $epic_name"
    exit 1
  fi
  
  echo ""
  echo "This will sync the epic and all its tasks with Jira."
  echo "Any changes in Jira will be pulled to local files."
  echo "Any local changes will be pushed to Jira."
else
  # Sync all epics
  echo "🔄 Full sync with Jira"
  echo ""
  echo "This will:"
  echo "1. Pull updates from Jira for all linked issues"
  echo "2. Push local changes to Jira"
  echo "3. Create any missing issues in Jira"
  echo "4. Handle any conflicts"
fi

echo ""
echo "Delegating to Claude for bidirectional sync..."

exit 0