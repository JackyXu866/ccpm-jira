#!/bin/bash

# Task Sync Script - Jira Integration Only
# Synchronizes task data between local files and Jira

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
TASK_NUMBER="$1"
FORCE_FLAG=""

# Check for --force flag
if [[ "$2" == "--force" ]]; then
    FORCE_FLAG="--force"
fi

# Validation
if [[ -z "$TASK_NUMBER" ]]; then
    echo "❌ Usage: task-sync <task_number> [--force]"
    echo ""
    echo "Example: task-sync 42"
    echo "Example: task-sync 42 --force  # Override conflicts with local version"
    exit 1
fi

if [[ ! "$TASK_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "❌ Task number must be numeric"
    exit 1
fi

echo "🔄 Syncing task $TASK_NUMBER"
echo "🔄 Mode: Jira"

# Find local task file
TASK_FILE=""
for epic_dir in .claude/epics/*/; do
    [ -d "$epic_dir" ] || continue
    
    if [ -f "${epic_dir}${TASK_NUMBER}.md" ]; then
        TASK_FILE="${epic_dir}${TASK_NUMBER}.md"
        break
    fi
done

if [[ -z "$TASK_FILE" ]]; then
    echo "❌ No local task for $TASK_NUMBER"
    echo ""
    echo "This task may have been created outside the PM system."
    echo "To import: /pm:import $TASK_NUMBER"
    exit 1
fi

echo "📁 Found task: $TASK_FILE"

# Delegate to Jira-specific implementation
if [ -f "$SCRIPT_DIR/../lib/task-sync.sh" ]; then
    source "$SCRIPT_DIR/../lib/task-sync.sh"
    # Need to extract epic name from task file path
    EPIC_NAME=$(basename "$(dirname "$TASK_FILE")")
    sync_task_jira "$TASK_NUMBER" "$TASK_FILE" "$EPIC_NAME" "$FORCE_FLAG"
else
    echo "❌ Jira implementation library not found"
    exit 1
fi