#!/bin/bash

# Parse arguments
PROJECT=""
EPIC=""
JQL=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --project)
      PROJECT="$2"
      shift 2
      ;;
    --epic)
      EPIC="$2"
      shift 2
      ;;
    --jql)
      JQL="$2"
      shift 2
      ;;
    *)
      echo "❌ Unknown option: $1"
      echo "Usage: /pm:import [--project KEY] [--epic name] [--jql query]"
      exit 1
      ;;
  esac
done

echo "Importing from Jira..."
echo ""
echo ""

# Check Jira configuration
if [ ! -f "claude/settings.local.json" ] || ! grep -q '"jira"' claude/settings.local.json || ! grep -q '"enabled": *true' claude/settings.local.json; then
  echo "❌ Jira integration not configured"
  echo ""
  echo "To configure Jira:"
  echo "1. Run: /pm:jira-init"
  echo "2. Connect MCP: /mcp atlassian"
  exit 1
fi

echo "📥 Import from Jira"
echo "=================="
echo ""

if [ -n "$PROJECT" ]; then
  echo "Project: $PROJECT"
fi

if [ -n "$EPIC" ]; then
  echo "Target epic: $EPIC"
  
  # Check epic exists
  if [ ! -d ".claude/epics/$EPIC" ]; then
    echo "❌ Epic not found: $EPIC"
    echo "Create it first with: /pm:prd-parse $EPIC"
    exit 1
  fi
fi

if [ -n "$JQL" ]; then
  echo "JQL Query: $JQL"
else
  # Default JQL if none provided
  if [ -n "$PROJECT" ]; then
    JQL="project = $PROJECT AND updated >= -7d"
    echo "JQL Query: $JQL (default: updated in last 7 days)"
  else
    echo "❌ Please provide either --project or --jql"
    exit 1
  fi
fi

echo ""
echo "This will:"
echo "1. Search Jira using the query"
echo "2. Import issues not already tracked locally"
echo "3. Create local task files"
echo "4. Organize into epic structure"
echo ""
echo "Delegating to Claude for import..."

exit 0