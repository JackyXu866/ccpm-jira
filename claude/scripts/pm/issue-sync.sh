#!/bin/bash

# Issue Sync Script - Jira Integration Only
# Synchronizes issue data between local files and Jira

set -e

# Load libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if Jira is configured
if [ ! -f "claude/settings.local.json" ] || ! grep -q '"jira"' claude/settings.local.json || ! grep -q '"enabled": *true' claude/settings.local.json; then
    echo "❌ Jira integration not configured"
    echo ""
    echo "To configure Jira:"
    echo "1. Run: /pm:jira-init"
    echo "2. Connect MCP: /mcp atlassian"
    exit 1
fi

# Parse arguments
ISSUE_NUMBER="$1"
FORCE_FLAG=""

# Check for --force flag
if [[ "$2" == "--force" ]]; then
    FORCE_FLAG="--force"
fi

# Validation
if [[ -z "$ISSUE_NUMBER" ]]; then
    echo "❌ Usage: issue-sync <issue_number> [--force]"
    echo ""
    echo "Example: issue-sync 42"
    echo "Example: issue-sync 42 --force  # Override conflicts with local version"
    exit 1
fi

if [[ ! "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "❌ Issue number must be numeric"
    exit 1
fi

echo "🔄 Syncing issue #$ISSUE_NUMBER"
echo "🔄 Mode: Jira"

# Find local task file
TASK_FILE=""
for epic_dir in .claude/epics/*/; do
    [ -d "$epic_dir" ] || continue
    
    if [ -f "${epic_dir}${ISSUE_NUMBER}.md" ]; then
        TASK_FILE="${epic_dir}${ISSUE_NUMBER}.md"
        break
    fi
done

if [[ -z "$TASK_FILE" ]]; then
    echo "❌ No local task for issue #$ISSUE_NUMBER"
    echo ""
    echo "This issue may have been created outside the PM system."
    echo "To import: /pm:import $ISSUE_NUMBER"
    exit 1
fi

echo "📁 Found task: $TASK_FILE"

# Delegate to Jira-specific implementation
if [ -f "$SCRIPT_DIR/../../lib/issue-sync-jira.sh" ]; then
    source "$SCRIPT_DIR/../../lib/issue-sync-jira.sh"
    sync_issue_jira "$ISSUE_NUMBER" "$TASK_FILE" "$FORCE_FLAG"
else
    echo "❌ Jira implementation library not found"
    exit 1
fi