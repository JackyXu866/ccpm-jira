#!/bin/bash

# Task Start Script - Jira Integration Only
# Starts work on a Jira task with automatic branch creation

set -e

# Load libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/git-integration.sh"

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
ANALYZE_FLAG="${2:-}"

# Validation
if [[ -z "$TASK_NUMBER" ]]; then
    echo "❌ Usage: task-start <task_number>"
    echo ""
    echo "Example: task-start 42"
    exit 1
fi

if [[ ! "$TASK_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "❌ Task number must be numeric"
    exit 1
fi

echo "🚀 Starting work on task $TASK_NUMBER"
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

# Check for analysis
EPIC_NAME=$(basename "$(dirname "$TASK_FILE")")
ANALYSIS_FILE=".claude/epics/${EPIC_NAME}/${TASK_NUMBER}-analysis.md"

if [[ ! -f "$ANALYSIS_FILE" ]]; then
    if [[ "$ANALYZE_FLAG" == "--analyze" ]]; then
        echo "🔍 Running analysis first..."
        # In a real implementation, this would call the analyze command
        echo "❌ Auto-analysis not yet implemented. Run: /pm:task-analyze $TASK_NUMBER"
        exit 1
    else
        echo "❌ No analysis found for task $TASK_NUMBER"
        echo ""
        echo "Run: /pm:task-analyze $TASK_NUMBER first"
        echo "Or: /pm:task-start $TASK_NUMBER --analyze to do both"
        exit 1
    fi
fi

# Get Jira key from task file
JIRA_KEY=$(grep -E "^jira: " "$TASK_FILE" | cut -d' ' -f2- | tr -d ' ')
if [ -z "$JIRA_KEY" ]; then
    # Fallback to PROJ-{task_number} format
    JIRA_KEY="PROJ-$TASK_NUMBER"
fi

# Create task-specific worktree
WORKTREE_NAME="${JIRA_KEY}-${EPIC_NAME}"
BRANCH_NAME="task/${JIRA_KEY}"

if ! git worktree list | grep -q "$WORKTREE_NAME"; then
    echo "🔄 Creating task worktree: ../$WORKTREE_NAME"
    git checkout main
    git pull origin main
    git worktree add "../$WORKTREE_NAME" -b "$BRANCH_NAME"
    echo "✅ Created worktree: ../$WORKTREE_NAME"
else
    echo "✅ Using existing worktree: ../$WORKTREE_NAME"
fi

# Delegate to Jira-specific implementation
if [ -f "$SCRIPT_DIR/../lib/task-start.sh" ]; then
    source "$SCRIPT_DIR/../lib/task-start.sh"
    start_task_jira "$TASK_NUMBER" "$TASK_FILE" "$EPIC_NAME"
else
    echo "❌ Jira implementation library not found"
    exit 1
fi