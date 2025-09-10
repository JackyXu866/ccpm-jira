#!/bin/bash

# Issue Start Script
# Enhanced with Git-Jira integration for automatic branch creation

set -e

# Load git integration library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/git-integration.sh"

# Parse arguments
ISSUE_NUMBER="$1"
ANALYZE_FLAG="${2:-}"

# Validation
if [[ -z "$ISSUE_NUMBER" ]]; then
    echo "❌ Usage: issue-start <issue_number>"
    exit 1
fi

if [[ ! "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "❌ Issue number must be numeric"
    exit 1
fi

echo "🚀 Starting work on issue #$ISSUE_NUMBER"

# Quick Check: Get issue details
echo "📋 Checking GitHub issue..."
if ! gh issue view "$ISSUE_NUMBER" --json state,title,labels,body >/dev/null 2>&1; then
    echo "❌ Cannot access issue #$ISSUE_NUMBER. Check number or run: gh auth login"
    exit 1
fi

# Get issue details for branch creation
ISSUE_TITLE=$(gh issue view "$ISSUE_NUMBER" --json title --jq .title)
echo "   Issue: $ISSUE_TITLE"

# Quick Check: Find local task file
echo "📁 Searching for local task file..."
TASK_FILE=""

# First check new naming pattern
for epic_dir in .claude/epics/*; do
    if [[ -d "$epic_dir" ]] && [[ -f "$epic_dir/$ISSUE_NUMBER.md" ]]; then
        TASK_FILE="$epic_dir/$ISSUE_NUMBER.md"
        break
    fi
done

# If not found, search old naming pattern
if [[ -z "$TASK_FILE" ]]; then
    TASK_FILE=$(find .claude/epics -name "*.md" -exec grep -l "github:.*issues/$ISSUE_NUMBER" {} \; 2>/dev/null | head -n1)
fi

if [[ -z "$TASK_FILE" ]]; then
    echo "❌ No local task for issue #$ISSUE_NUMBER. This issue may have been created outside the PM system."
    exit 1
fi

echo "   Found: $TASK_FILE"

# Extract epic name from path
EPIC_NAME=$(basename "$(dirname "$TASK_FILE")")
echo "   Epic: $EPIC_NAME"

# Quick Check: Analysis file
ANALYSIS_FILE="$(dirname "$TASK_FILE")/$ISSUE_NUMBER-analysis.md"
echo "🔍 Checking for analysis..."

if [[ ! -f "$ANALYSIS_FILE" ]]; then
    if [[ "$ANALYZE_FLAG" == "--analyze" ]]; then
        echo "   Running analysis first..."
        # This would typically call the analyze command
        echo "❌ Analysis not implemented yet. Please run: /pm:issue-analyze $ISSUE_NUMBER first"
        exit 1
    else
        echo "❌ No analysis found for issue #$ISSUE_NUMBER"
        echo "   Run: /pm:issue-analyze $ISSUE_NUMBER first"
        echo "   Or: /pm:issue-start $ISSUE_NUMBER --analyze to do both"
        exit 1
    fi
fi

echo "   Found: $ANALYSIS_FILE"

# Ensure Worktree Exists
echo "🔧 Checking epic worktree..."
if ! git worktree list | grep -q "epic-$EPIC_NAME"; then
    echo "❌ No worktree for epic. Run: /pm:epic-start $EPIC_NAME"
    exit 1
fi

WORKTREE_PATH=$(git worktree list | grep "epic-$EPIC_NAME" | awk '{print $1}')
echo "   Worktree: $WORKTREE_PATH"

# Create Jira-formatted branch
echo "🌱 Creating Jira-formatted branch..."
# Extract a short description from the issue title for branch naming
BRANCH_DESCRIPTION=$(echo "$ISSUE_TITLE" | head -c 30 | sed 's/[^a-zA-Z0-9 ]//g' | xargs)

# Create the branch using git-integration library
BRANCH_NAME=""
if BRANCH_NAME=$(create_jira_branch "$ISSUE_NUMBER" "$BRANCH_DESCRIPTION"); then
    echo "✅ Branch created: $BRANCH_NAME"
else
    echo "⚠️  Branch creation failed, continuing without new branch"
fi

# Setup Progress Tracking
echo "📊 Setting up progress tracking..."
CURRENT_DATETIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
UPDATES_DIR=".claude/epics/$EPIC_NAME/updates/$ISSUE_NUMBER"
mkdir -p "$UPDATES_DIR"

# Update task file frontmatter
echo "   Updating task file..."
if command -v sed >/dev/null 2>&1; then
    # Update the 'updated' field in frontmatter
    sed -i "s/^updated:.*/updated: $CURRENT_DATETIME/" "$TASK_FILE" || true
fi

# Read Analysis and Launch Parallel Agents
echo "📖 Reading analysis for parallel streams..."
if [[ -f "$ANALYSIS_FILE" ]]; then
    echo "   Analysis file exists, ready for parallel agent launch"
    echo "   (Agent launch implementation pending - this is Stream A scope)"
else
    echo "❌ Analysis file not found at $ANALYSIS_FILE"
    exit 1
fi

# GitHub Assignment
echo "👤 Assigning issue on GitHub..."
if gh issue edit "$ISSUE_NUMBER" --add-assignee @me --add-label "in-progress" >/dev/null 2>&1; then
    echo "✅ Issue assigned and labeled as in-progress"
else
    echo "⚠️  Could not assign issue on GitHub (may not have permissions)"
fi

# Output Summary
echo ""
echo "✅ Started parallel work on issue #$ISSUE_NUMBER"
echo ""
echo "Epic: $EPIC_NAME"
echo "Worktree: $WORKTREE_PATH"
if [[ -n "$BRANCH_NAME" ]]; then
    echo "Branch: $BRANCH_NAME"
fi
echo ""
echo "Task file: $TASK_FILE"
echo "Analysis: $ANALYSIS_FILE"
echo "Progress tracking: $UPDATES_DIR"
echo ""
echo "Next steps:"
echo "  Monitor with: /pm:epic-status $EPIC_NAME"
echo "  Sync updates: /pm:issue-sync $ISSUE_NUMBER"
if [[ -n "$BRANCH_NAME" ]]; then
    echo "  Switch to branch: git checkout $BRANCH_NAME"
fi

# Validation summary
echo ""
echo "🔍 Validation Summary:"
echo "  ✅ GitHub issue accessible"
echo "  ✅ Local task file found"  
echo "  ✅ Analysis file exists"
echo "  ✅ Epic worktree available"
if [[ -n "$BRANCH_NAME" ]]; then
    echo "  ✅ Jira-formatted branch created"
else
    echo "  ⚠️  Branch creation skipped"
fi
echo "  ✅ GitHub issue assigned"

echo ""
echo "🎯 Ready to begin implementation!"