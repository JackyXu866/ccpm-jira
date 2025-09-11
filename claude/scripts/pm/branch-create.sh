#!/bin/bash

# Validate arguments
if [ $# -lt 2 ]; then
  echo "Usage: branch-create <type> <jira-key> [description]"
  echo "Types: feature, bugfix, hotfix, epic"
  echo "Example: branch-create feature PROJ-123 user-auth"
  exit 1
fi

# Validate branch type
case "$1" in
  feature|bugfix|hotfix|epic)
    TYPE="$1"
    ;;
  *)
    echo "❌ Invalid branch type: $1"
    echo "Valid types: feature, bugfix, hotfix, epic"
    exit 1
    ;;
esac

# Validate Jira key format
JIRA_KEY="$2"
if ! [[ "$JIRA_KEY" =~ ^[A-Z]+-[0-9]+$ ]]; then
  echo "❌ Invalid Jira key format: $JIRA_KEY"
  echo "Expected format: PROJ-123"
  exit 1
fi

# Check if Jira issue exists (if configured)
if [ -f "claude/config/jira-settings.json" ] && [ -f "claude/scripts/adapters/jira-adapter.sh" ]; then
  source claude/scripts/adapters/jira-adapter.sh
  
  echo "🔍 Checking Jira issue $JIRA_KEY..."
  if ! jira_get_issue "$JIRA_KEY" &>/dev/null; then
    echo "⚠️  Warning: Jira issue $JIRA_KEY not found"
    echo -n "Continue anyway? (y/n) "
    read -r confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
      exit 1
    fi
  else
    echo "✅ Jira issue found"
  fi
fi

# Build branch name
DESCRIPTION="${3:-}"
if [ -n "$DESCRIPTION" ]; then
  # Sanitize description: lowercase, replace spaces/underscores with hyphens, remove special chars
  DESCRIPTION=$(echo "$DESCRIPTION" | tr '[:upper:]' '[:lower:]' | tr ' _' '-' | sed 's/[^a-z0-9-]//g')
  BRANCH_NAME="${TYPE}/${JIRA_KEY}-${DESCRIPTION}"
else
  BRANCH_NAME="${TYPE}/${JIRA_KEY}"
fi

# Check for existing branch
if git branch -a | grep -qE "(^|\s)${BRANCH_NAME}($|\s)"; then
  echo "❌ Branch already exists: $BRANCH_NAME"
  echo ""
  echo "💡 Suggestions:"
  
  # Suggest numbered alternatives
  for i in {2..5}; do
    alt="${BRANCH_NAME}-v${i}"
    if ! git branch -a | grep -qE "(^|\s)${alt}($|\s)"; then
      echo "  - $alt"
    fi
  done
  exit 1
fi

# Check for uncommitted changes
if [ -n "$(git status --porcelain)" ]; then
  echo "⚠️  You have uncommitted changes"
  echo -n "Stash changes and continue? (y/n) "
  read -r stash_confirm
  if [ "$stash_confirm" = "y" ] || [ "$stash_confirm" = "Y" ]; then
    git stash push -m "Auto-stash before creating branch $BRANCH_NAME"
    echo "✅ Changes stashed"
  else
    echo "❌ Aborted: Please commit or stash your changes first"
    exit 1
  fi
fi

# Create the branch
echo "🌿 Creating branch: $BRANCH_NAME"

# Ensure we're on latest main
git checkout main || git checkout master
git pull origin main 2>/dev/null || git pull origin master

# Create and switch to new branch
git checkout -b "$BRANCH_NAME"

if [ $? -eq 0 ]; then
  echo ""
  echo "✅ Branch created and checked out: $BRANCH_NAME"
  echo ""
  echo "📝 Next steps:"
  echo "  1. Make your changes"
  echo "  2. Commit with: git commit -m \"$JIRA_KEY: Your message\""
  echo "  3. Push with: git push -u origin $BRANCH_NAME"
  echo "  4. Create PR with: gh pr create"
else
  echo "❌ Failed to create branch"
  exit 1
fi