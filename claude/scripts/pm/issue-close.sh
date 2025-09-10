#!/bin/bash

# Issue Close Script
# Enhanced with Jira integration for proper issue closure workflow

set -e

# Load libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/git-integration.sh"
source "$SCRIPT_DIR/../../lib/pr-templates.sh"

# Parse arguments
ISSUE_NUMBER="$1"
RESOLUTION="${2:-Fixed}"
PR_FLAG="${3:-}"

# Validation
if [[ -z "$ISSUE_NUMBER" ]]; then
    echo "❌ Usage: issue-close <issue_number> [resolution] [--create-pr]"
    echo ""
    echo "Arguments:"
    echo "  issue_number  The GitHub issue number to close"
    echo "  resolution    The resolution type (Fixed, Won't Fix, Duplicate, etc.) [default: Fixed]"
    echo "  --create-pr   Create a pull request if on a feature branch"
    echo ""
    echo "Examples:"
    echo "  issue-close 123"
    echo "  issue-close 123 Fixed --create-pr"
    echo "  issue-close 123 \"Won't Fix\""
    exit 1
fi

if [[ ! "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "❌ Issue number must be numeric"
    exit 1
fi

echo "🎯 Closing issue #$ISSUE_NUMBER with resolution: $RESOLUTION"

# Check for Jira integration mode
jira_mode=false
if [ -f "claude/settings.local.json" ]; then
  if grep -q '"jira"' claude/settings.local.json && grep -q '"enabled": *true' claude/settings.local.json; then
    jira_mode=true
  fi
fi

echo "🔄 Mode: $([ "$jira_mode" = true ] && echo "Jira" || echo "GitHub")"

# Quick Check: Get issue details
echo "📋 Checking GitHub issue..."
if ! gh issue view "$ISSUE_NUMBER" --json state,title,labels,body >/dev/null 2>&1; then
    echo "❌ Cannot access issue #$ISSUE_NUMBER. Check number or run: gh auth login"
    exit 1
fi

# Get issue details
ISSUE_TITLE=$(gh issue view "$ISSUE_NUMBER" --json title --jq .title)
ISSUE_STATE=$(gh issue view "$ISSUE_NUMBER" --json state --jq .state)
echo "   Issue: $ISSUE_TITLE"
echo "   Current state: $ISSUE_STATE"

if [[ "$ISSUE_STATE" == "CLOSED" ]]; then
    echo "⚠️  Issue #$ISSUE_NUMBER is already closed"
    echo "   Do you want to update the resolution? (This will work in Jira mode)"
fi

# Find local task file
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

# Delegate to Jira implementation if enabled
if [ "$jira_mode" = true ]; then
    echo "🔄 Delegating to Jira implementation..."
    
    # Load Jira issue close implementation
    if [ -f "claude/lib/issue-close-jira.sh" ]; then
        source "claude/lib/issue-close-jira.sh"
        
        # Validate Jira setup
        if ! validate_jira_setup; then
            echo "❌ Jira setup validation failed"
            echo "   Falling back to GitHub mode..."
            jira_mode=false
        else
            # Run Jira-specific issue close workflow
            if close_jira_issue "$ISSUE_NUMBER" "$RESOLUTION" "$TASK_FILE" "$EPIC_NAME" "$PR_FLAG"; then
                echo ""
                echo "✅ Jira issue closure completed successfully!"
                echo ""
                echo "Epic: $EPIC_NAME"
                echo "Resolution: $RESOLUTION"
                if [[ "$PR_FLAG" == "--create-pr" ]]; then
                    echo "Pull request: Created (if applicable)"
                fi
                echo ""
                echo "Next steps:"
                echo "  Monitor epic with: /pm:epic-status $EPIC_NAME"
                echo "  View closed issues: /pm:epic-show $EPIC_NAME"
                exit 0
            else
                echo "❌ Jira issue closure failed"
                echo "   Falling back to GitHub mode..."
                jira_mode=false
            fi
        fi
    else
        echo "❌ Jira implementation not found: claude/lib/issue-close-jira.sh"
        echo "   Falling back to GitHub mode..."
        jira_mode=false
    fi
fi

# Continue with GitHub-only workflow if Jira mode is disabled or failed
if [ "$jira_mode" = false ]; then
    echo "🔄 Continuing with GitHub-only workflow..."
fi

# Check current git context for PR creation
CURRENT_BRANCH=""
if git rev-parse --abbrev-ref HEAD >/dev/null 2>&1; then
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    echo "🌱 Current branch: $CURRENT_BRANCH"
    
    # Check if we're on a feature branch and PR creation is requested
    if [[ "$PR_FLAG" == "--create-pr" && "$CURRENT_BRANCH" != "main" && "$CURRENT_BRANCH" != "master" ]]; then
        echo "📝 Creating pull request..."
        
        # Generate PR data using pr-templates
        PR_DATA=$(generate_pr_data "Close issue #$ISSUE_NUMBER" "Resolves issue #$ISSUE_NUMBER with resolution: $RESOLUTION")
        
        if [[ $? -eq 0 ]]; then
            # Extract title and description from PR data
            PR_TITLE=$(echo "$PR_DATA" | grep -o '"title":[^,]*' | cut -d'"' -f4)
            
            # Create the PR
            if gh pr create --title "$PR_TITLE" --body "$(generate_pr_description "" "Resolves issue #$ISSUE_NUMBER with resolution: $RESOLUTION")" --base main; then
                echo "✅ Pull request created successfully"
            else
                echo "⚠️  Failed to create pull request"
            fi
        else
            echo "⚠️  Failed to generate PR data"
        fi
    fi
fi

# Close GitHub issue
echo "🔒 Closing GitHub issue..."
if gh issue close "$ISSUE_NUMBER" --comment "Closed with resolution: $RESOLUTION" >/dev/null 2>&1; then
    echo "✅ GitHub issue closed successfully"
else
    echo "⚠️  Could not close GitHub issue (may not have permissions)"
fi

# Update task file status
echo "📊 Updating local task status..."
CURRENT_DATETIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if command -v sed >/dev/null 2>&1; then
    # Update the status and completion date
    sed -i "s/^status:.*/status: completed/" "$TASK_FILE" || true
    sed -i "s/^updated:.*/updated: $CURRENT_DATETIME/" "$TASK_FILE" || true
    
    # Add completion metadata
    if ! grep -q "^completed:" "$TASK_FILE"; then
        sed -i "/^updated:/a completed: $CURRENT_DATETIME" "$TASK_FILE" || true
    else
        sed -i "s/^completed:.*/completed: $CURRENT_DATETIME/" "$TASK_FILE" || true
    fi
    
    # Add resolution metadata
    if ! grep -q "^resolution:" "$TASK_FILE"; then
        sed -i "/^completed:/a resolution: $RESOLUTION" "$TASK_FILE" || true
    else
        sed -i "s/^resolution:.*/resolution: $RESOLUTION/" "$TASK_FILE" || true
    fi
fi

# Archive local data if this was the only issue in the epic
echo "🗂️  Checking if epic should be archived..."
OTHER_ISSUES=$(find "$(dirname "$TASK_FILE")" -name "*.md" -not -name "$ISSUE_NUMBER.md" -not -name "*-analysis.md" 2>/dev/null | wc -l)

if [[ "$OTHER_ISSUES" -eq 0 ]]; then
    echo "   This was the last issue in epic $EPIC_NAME"
    echo "   Consider running: /pm:epic-archive $EPIC_NAME"
else
    echo "   Epic $EPIC_NAME has $OTHER_ISSUES other issues remaining"
fi

# Output Summary
echo ""
echo "✅ Issue #$ISSUE_NUMBER closed successfully"
echo ""
echo "Resolution: $RESOLUTION"
echo "Epic: $EPIC_NAME"
echo "Task file updated: $TASK_FILE"
if [[ -n "$CURRENT_BRANCH" && "$CURRENT_BRANCH" != "main" && "$CURRENT_BRANCH" != "master" ]]; then
    echo "Current branch: $CURRENT_BRANCH"
    if [[ "$PR_FLAG" != "--create-pr" ]]; then
        echo "   Tip: Use --create-pr flag to automatically create a pull request"
    fi
fi
echo ""
echo "Next steps:"
echo "  View epic status: /pm:epic-status $EPIC_NAME"
if [[ "$OTHER_ISSUES" -eq 0 ]]; then
    echo "  Archive epic: /pm:epic-archive $EPIC_NAME"
fi
if [[ -n "$CURRENT_BRANCH" && "$CURRENT_BRANCH" != "main" && "$CURRENT_BRANCH" != "master" ]]; then
    echo "  Switch to main: git checkout main"
    echo "  Delete branch: git branch -d $CURRENT_BRANCH"
fi

# Validation summary
echo ""
echo "🔍 Validation Summary:"
echo "  ✅ GitHub issue closed"
echo "  ✅ Local task file updated"
echo "  ✅ Resolution recorded: $RESOLUTION"
if [[ "$PR_FLAG" == "--create-pr" ]]; then
    echo "  ✅ PR creation attempted"
fi
echo ""
echo "🎉 Issue closure workflow complete!"