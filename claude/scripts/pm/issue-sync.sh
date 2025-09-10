#!/bin/bash

# Issue Sync Script
# Synchronizes issue data between local cache and Jira, handles bidirectional sync

set -e

# Load libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/git-integration.sh"

# Parse arguments
ISSUE_NUMBER="$1"
FORCE_FLAG="${2:-}"

# Validation
if [[ -z "$ISSUE_NUMBER" ]]; then
    echo "❌ Usage: issue-sync <issue_number> [--force]"
    echo ""
    echo "Options:"
    echo "  --force    Override conflicts with local changes"
    exit 1
fi

if [[ ! "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "❌ Issue number must be numeric"
    exit 1
fi

echo "🔄 Syncing issue #$ISSUE_NUMBER"

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
echo "   Issue: $ISSUE_TITLE"

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
    echo "❌ No local task for issue #$ISSUE_NUMBER. Cannot sync without local task file."
    exit 1
fi

echo "   Found: $TASK_FILE"

# Extract epic name from path
EPIC_NAME=$(basename "$(dirname "$TASK_FILE")")
echo "   Epic: $EPIC_NAME"

# Delegate to Jira implementation if enabled
if [ "$jira_mode" = true ]; then
    echo "🔄 Delegating to Jira sync implementation..."
    
    # Load Jira issue sync implementation
    if [ -f "claude/lib/issue-sync-jira.sh" ]; then
        source "claude/lib/issue-sync-jira.sh"
        
        # Validate Jira setup
        if ! validate_jira_sync_setup; then
            echo "❌ Jira sync setup validation failed"
            echo "   Falling back to GitHub mode..."
            jira_mode=false
        else
            # Run Jira-specific issue sync workflow
            if sync_jira_issue "$ISSUE_NUMBER" "$TASK_FILE" "$EPIC_NAME" "$FORCE_FLAG"; then
                echo ""
                echo "✅ Jira issue sync completed successfully!"
                echo ""
                echo "Epic: $EPIC_NAME"
                echo "Task file: $TASK_FILE"
                echo ""
                echo "Next steps:"
                echo "  Check status: /pm:epic-status $EPIC_NAME"
                echo "  Continue work: Continue your development"
                exit 0
            else
                echo "❌ Jira issue sync failed"
                echo "   Falling back to GitHub mode..."
                jira_mode=false
            fi
        fi
    else
        echo "❌ Jira sync implementation not found: claude/lib/issue-sync-jira.sh"
        echo "   Falling back to GitHub mode..."
        jira_mode=false
    fi
fi

# Continue with GitHub-only workflow if Jira mode is disabled or failed
if [ "$jira_mode" = false ]; then
    echo "🔄 Continuing with GitHub-only workflow..."
fi

# GitHub-only sync implementation
echo "📥 Fetching latest from GitHub..."
GITHUB_DATA=$(gh issue view "$ISSUE_NUMBER" --json state,title,labels,body,assignees,updatedAt)

if [[ -z "$GITHUB_DATA" ]]; then
    echo "❌ Failed to fetch GitHub issue data"
    exit 1
fi

# Extract GitHub issue information
GITHUB_STATE=$(echo "$GITHUB_DATA" | jq -r '.state // "open"')
GITHUB_UPDATED=$(echo "$GITHUB_DATA" | jq -r '.updatedAt // ""')
GITHUB_ASSIGNEES=$(echo "$GITHUB_DATA" | jq -r '.assignees[]?.login // ""' | head -1)

echo "   State: $GITHUB_STATE"
echo "   Updated: $GITHUB_UPDATED"
if [[ -n "$GITHUB_ASSIGNEES" ]]; then
    echo "   Assignee: $GITHUB_ASSIGNEES"
fi

# Check local task file last modified time
if [[ -f "$TASK_FILE" ]]; then
    LOCAL_MODIFIED=$(stat -c %Y "$TASK_FILE" 2>/dev/null || stat -f %m "$TASK_FILE" 2>/dev/null || echo "0")
    LOCAL_STATUS=$(grep "^status:" "$TASK_FILE" | head -1 | sed 's/^status: *//' || echo "open")
    LOCAL_ASSIGNEE=$(grep "^assignee:" "$TASK_FILE" | head -1 | sed 's/^assignee: *//' || echo "")
    
    echo "📋 Local task file info:"
    echo "   Status: $LOCAL_STATUS"
    if [[ -n "$LOCAL_ASSIGNEE" ]]; then
        echo "   Assignee: $LOCAL_ASSIGNEE"
    fi
else
    echo "❌ Local task file not found"
    exit 1
fi

# Simple conflict detection and resolution for GitHub mode
echo "🔍 Checking for conflicts..."
conflicts_found=false

# Map GitHub state to local status
case "$GITHUB_STATE" in
    "open") GITHUB_LOCAL_STATUS="open" ;;
    "closed") GITHUB_LOCAL_STATUS="completed" ;;
    *) GITHUB_LOCAL_STATUS="open" ;;
esac

# Check for status conflicts
if [[ "$LOCAL_STATUS" != "$GITHUB_LOCAL_STATUS" ]]; then
    echo "⚠️  Status conflict detected:"
    echo "   Local: $LOCAL_STATUS"
    echo "   GitHub: $GITHUB_LOCAL_STATUS"
    conflicts_found=true
fi

# Check for assignee conflicts
if [[ "$LOCAL_ASSIGNEE" != "$GITHUB_ASSIGNEES" ]] && [[ -n "$GITHUB_ASSIGNEES" ]]; then
    echo "⚠️  Assignee conflict detected:"
    echo "   Local: ${LOCAL_ASSIGNEE:-"unassigned"}"
    echo "   GitHub: $GITHUB_ASSIGNEES"
    conflicts_found=true
fi

# Handle conflicts
if [ "$conflicts_found" = true ]; then
    if [[ "$FORCE_FLAG" == "--force" ]]; then
        echo "🔧 Force flag detected, keeping local changes"
    else
        echo ""
        echo "❌ Conflicts detected between local and GitHub data"
        echo "   Use --force to override with local changes"
        echo "   Or manually resolve conflicts in: $TASK_FILE"
        exit 1
    fi
fi

# Update local task file with GitHub data (if no conflicts or force flag)
if [ "$conflicts_found" = false ] || [[ "$FORCE_FLAG" == "--force" ]]; then
    echo "📝 Updating local task file..."
    CURRENT_DATETIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Update the status if no conflict or we're not forcing local changes
    if [ "$conflicts_found" = false ]; then
        if grep -q "^status:" "$TASK_FILE"; then
            sed -i.bak "s/^status:.*/status: $GITHUB_LOCAL_STATUS/" "$TASK_FILE"
        else
            sed -i.bak '/^---$/a\status: '"$GITHUB_LOCAL_STATUS" "$TASK_FILE"
        fi
        
        # Update assignee if GitHub has one
        if [[ -n "$GITHUB_ASSIGNEES" ]]; then
            if grep -q "^assignee:" "$TASK_FILE"; then
                sed -i.bak "s/^assignee:.*/assignee: $GITHUB_ASSIGNEES/" "$TASK_FILE"
            else
                sed -i.bak '/^---$/a\assignee: '"$GITHUB_ASSIGNEES" "$TASK_FILE"
            fi
        fi
    fi
    
    # Always update the sync timestamp
    if grep -q "^updated:" "$TASK_FILE"; then
        sed -i.bak "s/^updated:.*/updated: $CURRENT_DATETIME/" "$TASK_FILE"
    else
        sed -i.bak '/^---$/a\updated: '"$CURRENT_DATETIME" "$TASK_FILE"
    fi
    
    # Add last sync timestamp
    if grep -q "^last_sync:" "$TASK_FILE"; then
        sed -i.bak "s/^last_sync:.*/last_sync: $CURRENT_DATETIME/" "$TASK_FILE"
    else
        sed -i.bak '/^---$/a\last_sync: '"$CURRENT_DATETIME" "$TASK_FILE"
    fi
    
    # Clean up backup file
    rm -f "${TASK_FILE}.bak"
    
    echo "✅ Local task file updated"
fi

# Update progress tracking
echo "📊 Updating progress tracking..."
UPDATES_DIR=".claude/epics/$EPIC_NAME/updates/$ISSUE_NUMBER"
mkdir -p "$UPDATES_DIR"

# Create sync log entry
SYNC_LOG="$UPDATES_DIR/sync-log.md"
cat >> "$SYNC_LOG" << EOF

## Sync $(date -u +"%Y-%m-%d %H:%M:%S UTC")

**Mode**: GitHub-only
**Status**: $([ "$conflicts_found" = true ] && echo "Conflicts resolved with --force" || echo "Success")
**Changes**: 
- Local status: $LOCAL_STATUS → $GITHUB_LOCAL_STATUS
- Assignee: ${LOCAL_ASSIGNEE:-"none"} → ${GITHUB_ASSIGNEES:-"none"}

EOF

# Output Summary
echo ""
echo "✅ Issue sync completed for #$ISSUE_NUMBER"
echo ""
echo "Epic: $EPIC_NAME"
echo "Task file: $TASK_FILE"
echo "Sync log: $SYNC_LOG"
echo ""

# Validation summary
echo "🔍 Sync Summary:"
echo "  ✅ GitHub issue accessible"
echo "  ✅ Local task file updated"
if [ "$conflicts_found" = true ]; then
    echo "  ⚠️  Conflicts resolved with --force"
else
    echo "  ✅ No conflicts detected"
fi
echo "  ✅ Progress tracking updated"

echo ""
echo "🔄 Sync completed successfully!"