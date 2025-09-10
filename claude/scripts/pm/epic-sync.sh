#!/bin/bash

epic_name="$1"

if [ -z "$epic_name" ]; then
  echo "❌ Please provide an epic name"
  echo "Usage: /pm:epic-sync <epic-name>"
  exit 1
fi

echo "Syncing epic..."
echo ""
echo ""

# Check if epic exists
if [ ! -f ".claude/epics/$epic_name/epic.md" ]; then
  echo "❌ Epic not found: $epic_name"
  echo "Run: /pm:prd-parse $epic_name"
  exit 1
fi

# Count task files
task_count=$(ls .claude/epics/$epic_name/[0-9]*.md 2>/dev/null | grep -v epic.md | wc -l)
if [ "$task_count" -eq 0 ]; then
  echo "❌ No tasks to sync. Run: /pm:epic-decompose $epic_name"
  exit 1
fi

# Check for Jira configuration
jira_mode=false
if [ -f "claude/settings.local.json" ]; then
  if grep -q '"jira"' claude/settings.local.json && grep -q '"enabled": *true' claude/settings.local.json; then
    jira_mode=true
  fi
fi

echo "🔄 Sync mode: $([ "$jira_mode" = true ] && echo "Jira" || echo "GitHub")"
echo ""

# Delegate to appropriate implementation
if [ "$jira_mode" = true ]; then
  # Use Jira sync implementation
  if [ -f "claude/lib/epic-sync-jira.sh" ]; then
    source "claude/lib/epic-sync-jira.sh"
    sync_epic_to_jira "$epic_name"
  else
    echo "❌ Jira sync module not found: claude/lib/epic-sync-jira.sh"
    echo "Falling back to GitHub sync..."
    jira_mode=false
  fi
fi

if [ "$jira_mode" = false ]; then
  # Fallback to GitHub sync (existing implementation)
  echo "📋 Syncing to GitHub..."
  
  # GitHub sync implementation (from original command documentation)
  # Check remote repository
  remote_url=$(git remote get-url origin 2>/dev/null || echo "")
  if [[ "$remote_url" == *"automazeio/ccpm"* ]] || [[ "$remote_url" == *"automazeio/ccpm.git"* ]]; then
    echo "❌ ERROR: You're trying to sync with the CCPM template repository!"
    echo ""
    echo "This repository (automazeio/ccpm) is a template for others to use."
    echo "You should NOT create issues or PRs here."
    echo ""
    echo "To fix this:"
    echo "1. Fork this repository to your own GitHub account"
    echo "2. Update your remote origin:"
    echo "   git remote set-url origin https://github.com/YOUR_USERNAME/YOUR_REPO.git"
    echo ""
    echo "Current remote: $remote_url"
    exit 1
  fi
  
  # Create Epic Issue
  sed '1,/^---$/d; 1,/^---$/d' ".claude/epics/$epic_name/epic.md" > /tmp/epic-body-raw.md
  
  # Process epic content
  awk '
    /^## Tasks Created/ {
      in_tasks=1
      next
    }
    /^## / && in_tasks {
      in_tasks=0
      if (total_tasks) {
        print "## Stats\n"
        print "Total tasks: " total_tasks
        print "Parallel tasks: " parallel_tasks " (can be worked on simultaneously)"
        print "Sequential tasks: " sequential_tasks " (have dependencies)"
        if (total_effort) print "Estimated total effort: " total_effort " hours"
        print ""
      }
    }
    /^Total tasks:/ && in_tasks { total_tasks = $3; next }
    /^Parallel tasks:/ && in_tasks { parallel_tasks = $3; next }
    /^Sequential tasks:/ && in_tasks { sequential_tasks = $3; next }
    /^Estimated total effort:/ && in_tasks {
      gsub(/^Estimated total effort: /, "")
      total_effort = $0
      next
    }
    !in_tasks { print }
    END {
      if (in_tasks && total_tasks) {
        print "## Stats\n"
        print "Total tasks: " total_tasks
        print "Parallel tasks: " parallel_tasks " (can be worked on simultaneously)"
        print "Sequential tasks: " sequential_tasks " (have dependencies)"
        if (total_effort) print "Estimated total effort: " total_effort
      }
    }
  ' /tmp/epic-body-raw.md > /tmp/epic-body.md
  
  # Determine epic type
  if grep -qi "bug\|fix\|issue\|problem\|error" /tmp/epic-body.md; then
    epic_type="bug"
  else
    epic_type="feature"
  fi
  
  # Create epic issue
  epic_number=$(gh issue create \
    --title "Epic: $epic_name" \
    --body-file /tmp/epic-body.md \
    --label "epic,epic:$epic_name,$epic_type" \
    --json number -q .number)
  
  echo "✅ Created GitHub epic: #$epic_number"
  
  # Update epic frontmatter
  repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
  epic_url="https://github.com/$repo/issues/$epic_number"
  current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  sed -i.bak "/^github:/c\github: $epic_url" ".claude/epics/$epic_name/epic.md"
  sed -i.bak "/^updated:/c\updated: $current_date" ".claude/epics/$epic_name/epic.md"
  rm ".claude/epics/$epic_name/epic.md.bak"
  
  echo "✅ Updated epic frontmatter"
  
  # Cleanup
  rm -f /tmp/epic-body*.md
fi

exit 0