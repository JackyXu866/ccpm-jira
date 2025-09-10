#!/bin/bash

echo "Initializing..."
echo ""
echo ""

echo " ██████╗ ██████╗██████╗ ███╗   ███╗"
echo "██╔════╝██╔════╝██╔══██╗████╗ ████║"
echo "██║     ██║     ██████╔╝██╔████╔██║"
echo "╚██████╗╚██████╗██║     ██║ ╚═╝ ██║"
echo " ╚═════╝ ╚═════╝╚═╝     ╚═╝     ╚═╝"

echo "┌─────────────────────────────────┐"
echo "│ Claude Code Project Management  │"
echo "│ by https://x.com/aroussi        │"
echo "└─────────────────────────────────┘"
echo "https://github.com/automazeio/ccpm"
echo ""
echo ""

echo "🚀 Initializing Claude Code PM System"
echo "======================================"
echo ""

# Check for required tools
echo "🔍 Checking dependencies..."

# Check gh CLI
if command -v gh &> /dev/null; then
  echo "  ✅ GitHub CLI (gh) installed"
else
  echo "  ❌ GitHub CLI (gh) not found"
  echo ""
  echo "  Installing gh..."
  if command -v brew &> /dev/null; then
    brew install gh
  elif command -v apt-get &> /dev/null; then
    sudo apt-get update && sudo apt-get install gh
  else
    echo "  Please install GitHub CLI manually: https://cli.github.com/"
    exit 1
  fi
fi

# Check jq for JSON processing (required for Jira)
if command -v jq &> /dev/null; then
  echo "  ✅ jq (JSON processor) installed"
else
  echo "  ❌ jq not found"
  echo ""
  echo "  Installing jq..."
  if command -v brew &> /dev/null; then
    brew install jq
  elif command -v apt-get &> /dev/null; then
    sudo apt-get update && sudo apt-get install jq
  else
    echo "  Please install jq manually: https://stedolan.github.io/jq/"
    exit 1
  fi
fi

# Check gh auth status
echo ""
echo "🔐 Checking GitHub authentication..."
if gh auth status &> /dev/null; then
  echo "  ✅ GitHub authenticated"
else
  echo "  ⚠️ GitHub not authenticated"
  echo "  Running: gh auth login"
  gh auth login
fi

# Check for gh-sub-issue extension
echo ""
echo "📦 Checking gh extensions..."
if gh extension list | grep -q "yahsan2/gh-sub-issue"; then
  echo "  ✅ gh-sub-issue extension installed"
else
  echo "  📥 Installing gh-sub-issue extension..."
  gh extension install yahsan2/gh-sub-issue
fi

# Create directory structure
echo ""
echo "📁 Creating directory structure..."
mkdir -p .claude/prds
mkdir -p .claude/epics
mkdir -p .claude/rules
mkdir -p .claude/agents
mkdir -p .claude/scripts/pm
mkdir -p claude/templates
mkdir -p claude/config
echo "  ✅ Directories created"

# Copy scripts if in main repo
if [ -d "scripts/pm" ] && [ ! "$(pwd)" = *"/.claude"* ]; then
  echo ""
  echo "📝 Copying PM scripts..."
  cp -r scripts/pm/* .claude/scripts/pm/
  chmod +x .claude/scripts/pm/*.sh
  echo "  ✅ Scripts copied and made executable"
fi

# Check for git
echo ""
echo "🔗 Checking Git configuration..."
if git rev-parse --git-dir > /dev/null 2>&1; then
  echo "  ✅ Git repository detected"

  # Check remote
  if git remote -v | grep -q origin; then
    remote_url=$(git remote get-url origin)
    echo "  ✅ Remote configured: $remote_url"
    
    # Check if remote is the CCPM template repository
    if [[ "$remote_url" == *"automazeio/ccpm"* ]] || [[ "$remote_url" == *"automazeio/ccpm.git"* ]]; then
      echo ""
      echo "  ⚠️ WARNING: Your remote origin points to the CCPM template repository!"
      echo "  This means any issues you create will go to the template repo, not your project."
      echo ""
      echo "  To fix this:"
      echo "  1. Fork the repository or create your own on GitHub"
      echo "  2. Update your remote:"
      echo "     git remote set-url origin https://github.com/YOUR_USERNAME/YOUR_REPO.git"
      echo ""
    fi
  else
    echo "  ⚠️ No remote configured"
    echo "  Add with: git remote add origin <url>"
  fi
else
  echo "  ⚠️ Not a git repository"
  echo "  Initialize with: git init"
fi

# Jira Configuration (Required)
echo ""
echo "🔧 Jira Configuration (Required)"
echo "================================"
echo ""

# Check if Atlassian MCP is available
if command -v mcp &> /dev/null || [ -f "claude/scripts/lib/mcp-helpers.sh" ]; then
  echo "  ✅ MCP integration available"
  
  # Check if jira-init.sh exists
  if [ -f "claude/scripts/pm/jira-init.sh" ]; then
    echo ""
    echo "  🚀 Configuring Jira integration..."
    bash claude/scripts/pm/jira-init.sh
    
    # Verify configuration was successful
    if [ ! -f "claude/config/jira-settings.json" ] || [ ! -s "claude/config/jira-settings.json" ]; then
      echo ""
      echo "  ❌ Jira configuration failed or was cancelled"
      echo "  CCPM requires Jira to be configured for issue tracking"
      echo "  Please run: bash claude/scripts/pm/jira-init.sh"
      exit 1
    fi
  else
    echo "  ❌ Jira initialization script not found"
    echo "  Please ensure claude/scripts/pm/jira-init.sh exists"
    exit 1
  fi
else
  echo "  ❌ Atlassian MCP not configured"
  echo "  CCPM requires Atlassian MCP for Jira integration"
  echo "  Please install and configure Atlassian MCP first"
  echo "  See: https://github.com/modelcontextprotocol/servers"
  exit 1
fi

# Git Integration Configuration
echo ""
echo "🔗 Git Integration Configuration"
echo "================================"
echo ""

# Check if Git integration config exists
if [ ! -f "claude/config/git-integration.json" ]; then
  echo "  📄 Git integration configuration not found"
  echo "  Creating default configuration..."
  
  # Create default git integration config if missing
  cat > claude/config/git-integration.json << 'EOF'
{
  "version": "1.0.0",
  "description": "Git-Jira Integration Configuration",
  "enabled": true,
  "integration": {
    "branch": {
      "enabled": true,
      "naming_convention": {
        "format": "JIRA-{issue_key}",
        "separator": "-",
        "prefix_style": "uppercase",
        "include_description": false,
        "max_description_length": 30,
        "fallback_prefix": "feature"
      },
      "validation": {
        "enforce_convention": false,
        "allow_exceptions": ["main", "develop", "master", "hotfix/*", "release/*"],
        "warn_on_violation": true,
        "block_on_violation": false
      }
    },
    "commit": {
      "enabled": true,
      "message_format": {
        "include_issue_key": true,
        "position": "prefix",
        "format": "Issue #{issue_key}: {message}",
        "enforce_format": false
      }
    },
    "pull_request": {
      "enabled": true,
      "title_format": {
        "include_issue_key": true,
        "include_summary": true,
        "format": "[{issue_key}] {summary}",
        "max_length": 100
      },
      "description": {
        "include_issue_link": true,
        "include_summary": true,
        "template": "## Summary\\n{summary}\\n\\n## Jira Issue\\n{issue_link}\\n\\n## Changes\\n- {changes}"
      }
    }
  },
  "backwards_compatibility": {
    "enabled": true,
    "allow_non_jira_branches": true,
    "fallback_behavior": "standard_git",
    "legacy_branch_patterns": ["feature/*", "bugfix/*", "hotfix/*"]
  },
  "preferences": {
    "auto_fetch_issue_data": true,
    "cache_issue_data": true,
    "cache_ttl": 3600,
    "prompt_for_confirmation": false,
    "verbose_output": false
  }
}
EOF
  echo "  ✅ Default Git integration configuration created"
else
  echo "  ✅ Git integration configuration found"
fi

# Validate Git integration configuration
if [ -f "claude/lib/git-config.sh" ]; then
  echo "  🔍 Validating Git integration configuration..."
  if bash claude/lib/git-config.sh -c "validate_git_integration_config" 2>/dev/null; then
    echo "  ✅ Git integration configuration is valid"
  else
    echo "  ⚠️ Git integration configuration may have issues"
  fi
else
  echo "  ⚠️ Git integration library not found (claude/lib/git-config.sh)"
fi

# Check if Git hooks directory exists and offer to set up hooks
if git rev-parse --git-dir > /dev/null 2>&1; then
  git_dir=$(git rev-parse --git-dir)
  hooks_dir="$git_dir/hooks"
  
  if [ -d "$hooks_dir" ]; then
    echo "  📂 Git hooks directory found: $hooks_dir"
    echo "  ℹ️ Git hooks can be configured later with Git integration commands"
  fi
fi

echo "  📋 Git Integration Features:"
echo "    • Smart branch naming with Jira issue keys"
echo "    • Automatic commit message formatting"
echo "    • Enhanced PR titles and descriptions"
echo "    • Backwards compatible with existing workflows"

# Create CLAUDE.md if it doesn't exist
if [ ! -f "CLAUDE.md" ]; then
  echo ""
  echo "📄 Creating CLAUDE.md..."
  cat > CLAUDE.md << 'EOF'
# CLAUDE.md

> Think carefully and implement the most concise solution that changes as little code as possible.

## Project-Specific Instructions

Add your project-specific instructions here.

## Testing

Always run tests before committing:
- `npm test` or equivalent for your stack

## Code Style

Follow existing patterns in the codebase.

## Directory Navigation Rules

- Always return to the root project directory after executing commands that change directories
- Never use `../` in commands to navigate out of the project directory
- Use absolute paths or ensure you're in the correct working directory before running commands
EOF
  echo "  ✅ CLAUDE.md created"
fi

# Summary
echo ""
echo "✅ Initialization Complete!"
echo "=========================="
echo ""
echo "📊 System Status:"
echo "  GitHub:"
gh --version | head -1 | sed 's/^/    /'
echo "    Extensions: $(gh extension list | wc -l) installed"
echo "    Auth: $(gh auth status 2>&1 | grep -o 'Logged in to [^ ]*' || echo 'Not authenticated')"

# Show Jira status (should always be configured at this point)
echo ""
echo "  Jira:"
if [ -f "claude/config/jira-settings.json" ] && [ -s "claude/config/jira-settings.json" ]; then
  if command -v jq &> /dev/null; then
    project_key=$(jq -r '.project_key // "Not configured"' claude/config/jira-settings.json 2>/dev/null)
    echo "    Project: $project_key"
    echo "    Status: Configured ✅"
  else
    echo "    Status: Configuration found"
  fi
else
  echo "    Status: ❌ Not configured (required)"
fi

# Show Git integration status
echo ""
echo "  Git Integration:"
if [ -f "claude/config/git-integration.json" ] && [ -s "claude/config/git-integration.json" ]; then
  if command -v jq &> /dev/null; then
    git_enabled=$(jq -r '.enabled // false' claude/config/git-integration.json 2>/dev/null)
    branch_enabled=$(jq -r '.integration.branch.enabled // false' claude/config/git-integration.json 2>/dev/null)
    commit_enabled=$(jq -r '.integration.commit.enabled // false' claude/config/git-integration.json 2>/dev/null)
    pr_enabled=$(jq -r '.integration.pull_request.enabled // false' claude/config/git-integration.json 2>/dev/null)
    
    if [ "$git_enabled" = "true" ]; then
      echo "    Status: Enabled ✅"
      echo "    Features: Branch($branch_enabled) Commit($commit_enabled) PR($pr_enabled)"
    else
      echo "    Status: Configured but disabled"
    fi
  else
    echo "    Status: Configuration found"
  fi
else
  echo "    Status: ❌ Not configured"
fi

echo ""
echo "🎯 Next Steps:"
echo "  1. Create your first PRD: /pm:prd-new <feature-name>"
echo "  2. View help: /pm:help"
echo "  3. Check status: /pm:status"
echo ""
echo "📚 Documentation: README.md"

exit 0
