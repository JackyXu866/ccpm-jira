#!/bin/bash

# Issue Start Script - Jira Integration Only
# Starts work on a Jira issue with automatic branch creation

set -e

# Load libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/git-integration.sh"

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
ANALYZE_FLAG="${2:-}"

# Validation
if [[ -z "$ISSUE_NUMBER" ]]; then
    echo "❌ Usage: issue-start <issue_number>"
    echo ""
    echo "Example: issue-start 42"
    exit 1
fi

if [[ ! "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "❌ Issue number must be numeric"
    exit 1
fi

echo "🚀 Starting work on task $ISSUE_NUMBER"
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
    echo "❌ No local task for $ISSUE_NUMBER"
    echo ""
    echo "This issue may have been created outside the PM system."
    echo "To import: /pm:import $ISSUE_NUMBER"
    exit 1
fi

echo "📁 Found task: $TASK_FILE"

# Check for analysis
EPIC_NAME=$(basename "$(dirname "$TASK_FILE")")
ANALYSIS_FILE=".claude/epics/${EPIC_NAME}/${ISSUE_NUMBER}-analysis.md"

if [[ ! -f "$ANALYSIS_FILE" ]]; then
    if [[ "$ANALYZE_FLAG" == "--analyze" ]]; then
        echo "🔍 Running analysis first..."
        # In a real implementation, this would call the analyze command
        echo "❌ Auto-analysis not yet implemented. Run: /pm:task-analyze $ISSUE_NUMBER"
        exit 1
    else
        echo "❌ No analysis found for task $ISSUE_NUMBER"
        echo ""
        echo "Run: /pm:task-analyze $ISSUE_NUMBER first"
        echo "Or: /pm:task-start $ISSUE_NUMBER --analyze to do both"
        exit 1
    fi
fi

# Check worktree exists
if ! git worktree list | grep -q "epic-$EPIC_NAME"; then
    echo "❌ No worktree for epic. Run: /pm:epic-start $EPIC_NAME"
    exit 1
fi

echo "✅ Worktree exists: ../epic-$EPIC_NAME"

# Delegate to Jira-specific implementation
if [ -f "$SCRIPT_DIR/../../lib/task-start-jira.sh" ]; then
    source "$SCRIPT_DIR/../../lib/task-start-jira.sh"
    start_task_jira "$ISSUE_NUMBER" "$TASK_FILE" "$EPIC_NAME"
else
    echo "❌ Jira implementation library not found"
    exit 1
fi