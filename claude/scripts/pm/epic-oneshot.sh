#!/bin/bash

epic_name="$1"

if [ -z "$epic_name" ]; then
  echo "❌ Please provide an epic name"
  echo "Usage: /pm:epic-oneshot <epic-name>"
  exit 1
fi

echo "Running epic decompose and sync..."
echo ""
echo ""

epic_dir=".claude/epics/$epic_name"
epic_file="$epic_dir/epic.md"

# Check epic exists
if [ ! -f "$epic_file" ]; then
  echo "❌ Epic not found: $epic_name"
  echo "Run: /pm:prd-parse $epic_name"
  exit 1
fi

# Check for existing tasks
if ls "$epic_dir"/[0-9]*.md 2>/dev/null | grep -q .; then
  echo "⚠️ Tasks already exist for this epic"
  echo "This command is for new epics only"
  echo ""
  echo "Use these commands instead:"
  echo "  • Update existing: /pm:epic-sync $epic_name"
  echo "  • Start work: /pm:epic-start $epic_name"
  exit 1
fi

# Check if already synced
if grep -q "^jira:" "$epic_file"; then
  echo "⚠️ Epic already synced to Jira"
  echo "Use: /pm:epic-sync $epic_name to update"
  exit 1
fi

# Check Jira configuration
if [ ! -f "claude/settings.local.json" ] || ! grep -q '"jira"' claude/settings.local.json || ! grep -q '"enabled": *true' claude/settings.local.json; then
  echo "❌ Jira integration not configured"
  echo ""
  echo "To configure Jira:"
  echo "1. Run: /pm:jira-init"
  echo "2. Connect MCP: /mcp atlassian"
  exit 1
fi

echo "📋 Epic: $epic_name"
echo "========================"
echo ""
echo "This will:"
echo "1. Decompose epic into tasks"
echo "2. Create epic and tasks in Jira"
echo "3. Link everything together"
echo ""
echo "🚀 Starting oneshot workflow..."
echo ""
echo "Step 1: Decomposing epic into tasks"
echo "Step 2: Syncing to Jira"
echo ""
echo "Delegating to Claude..."

exit 0