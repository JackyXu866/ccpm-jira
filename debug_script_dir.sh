#!/bin/bash
set -euo pipefail

echo "Debugging SCRIPT_DIR resolution..."

# Test from jira-validation.sh context
echo "Testing SCRIPT_DIR from jira-validation.sh..."
SCRIPT_DIR="$(cd "$(dirname "claude/lib/jira-validation.sh")" && pwd)"
echo "SCRIPT_DIR: $SCRIPT_DIR"
echo "Looking for: ${SCRIPT_DIR}/jira-task-ops.sh"
if [[ -f "${SCRIPT_DIR}/jira-task-ops.sh" ]]; then
    echo "✅ File exists at calculated path"
else
    echo "❌ File does NOT exist at calculated path"
    echo "Let's check what's actually in that directory:"
    ls -la "${SCRIPT_DIR}/"
fi

echo
echo "Now let's test with the actual BASH_SOURCE simulation..."
# Simulate being inside jira-validation.sh
cd claude/lib
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "From inside claude/lib:"
echo "SCRIPT_DIR: $SCRIPT_DIR"
echo "PWD: $(pwd)"
echo "Looking for: ${SCRIPT_DIR}/jira-task-ops.sh"
if [[ -f "${SCRIPT_DIR}/jira-task-ops.sh" ]]; then
    echo "✅ File exists"
else
    echo "❌ File does NOT exist"
fi