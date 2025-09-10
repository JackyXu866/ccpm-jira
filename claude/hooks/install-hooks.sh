#!/bin/bash

# Install Git hooks for Jira integration
# This script should be run after cloning or setting up the repository

echo "🔧 Installing Git hooks for Jira integration..."

# Check if we're in a git repository
if [[ ! -d ".git" ]]; then
    echo "❌ Not in a Git repository root. Please run from repository root."
    exit 1
fi

# Install pre-push hook
if [[ -f ".claude/hooks/pre-push" ]]; then
    cp .claude/hooks/pre-push .git/hooks/pre-push
    chmod +x .git/hooks/pre-push
    echo "✅ Installed pre-push hook"
else
    echo "❌ Pre-push hook source not found at .claude/hooks/pre-push"
    exit 1
fi

# Verify installation
if [[ -x ".git/hooks/pre-push" ]]; then
    echo "✅ Pre-push hook installed and executable"
else
    echo "❌ Pre-push hook installation failed"
    exit 1
fi

echo ""
echo "🎯 Git hooks installed successfully!"
echo ""
echo "The pre-push hook will now:"
echo "  - Validate branch names follow JIRA-123 format"
echo "  - Skip validation for main/master branches"  
echo "  - Skip validation for special branches (release/, hotfix/, etc.)"
echo "  - Show helpful error messages for invalid names"
echo ""
echo "To bypass validation (not recommended):"
echo "  git push --no-verify"
echo ""
echo "To disable Jira integration:"
echo "  Add '\"enabled\": false' to claude/config/git-integration.json"