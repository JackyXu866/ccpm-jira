#!/bin/bash

# Task Close Script - Jira Integration Only
# Closes a Jira task with resolution and optional PR creation

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

# Parse command line arguments
TASK_NUMBER="$1"
RESOLUTION="${2:-Fixed}"
CREATE_PR=""

# Check for --create-pr flag
for arg in "$@"; do
    if [[ "$arg" == "--create-pr" ]]; then
        CREATE_PR="true"
        # Remove flag from resolution if it was passed as second argument
        if [[ "$RESOLUTION" == "--create-pr" ]]; then
            RESOLUTION="Fixed"
        fi
    fi
done

# Validation
if [[ -z "$TASK_NUMBER" ]]; then
    echo "❌ Usage: task-close <task_number> [resolution] [--create-pr]"
    echo ""
    echo "Example: task-close 42"
    echo "Example: task-close 42 \"Won't Fix\""
    echo "Example: task-close 42 Fixed --create-pr"
    echo ""
    echo "Valid resolutions: Fixed, Won't Fix, Duplicate, Incomplete, Cannot Reproduce"
    exit 1
fi

if [[ ! "$TASK_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "❌ Task number must be numeric"
    exit 1
fi

echo "🎯 Closing task $TASK_NUMBER"
echo "📝 Resolution: $RESOLUTION"
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
    echo "❌ No local task for $TASK_NUMBER"
    echo ""
    echo "This issue may not be managed by the PM system."
    exit 1
fi

echo "📁 Found task: $TASK_FILE"

# Delegate to Jira-specific implementation
if [ -f "$SCRIPT_DIR/../lib/task-close.sh" ]; then
    source "$SCRIPT_DIR/../lib/task-close.sh"
    close_task_jira "$TASK_NUMBER" "$RESOLUTION" "$TASK_FILE" "$CREATE_PR"
else
    echo "❌ Jira implementation library not found"
    exit 1
fi