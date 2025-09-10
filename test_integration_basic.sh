#!/bin/bash
set -euo pipefail

echo "Testing basic integration of Stream D components..."

# Test 1: Load jira-fields.sh (Stream C)
echo "Testing jira-fields.sh loading..."
if source claude/lib/jira-fields.sh 2>/dev/null; then
    echo "✅ jira-fields.sh loaded successfully"
else
    echo "❌ Failed to load jira-fields.sh"
fi

# Test 2: Load jira-epic-ops.sh (Stream A)
echo "Testing jira-epic-ops.sh loading..."
if source claude/lib/jira-epic-ops.sh 2>/dev/null; then
    echo "✅ jira-epic-ops.sh loaded successfully"
else
    echo "❌ Failed to load jira-epic-ops.sh"
fi

# Test 3: Load jira-task-ops.sh (Stream B)
echo "Testing jira-task-ops.sh loading..."
if source claude/lib/jira-task-ops.sh 2>/dev/null; then
    echo "✅ jira-task-ops.sh loaded successfully"
else
    echo "❌ Failed to load jira-task-ops.sh"
fi

# Test 4: Test validation functions exist
echo "Testing validation functions availability..."
if source claude/lib/jira-validation.sh 2>/dev/null; then
    echo "✅ jira-validation.sh loaded successfully"
    
    # Test if key functions are available
    if declare -f validate_epic_consistency >/dev/null 2>&1; then
        echo "✅ validate_epic_consistency function available"
    else
        echo "❌ validate_epic_consistency function not available"
    fi
else
    echo "❌ Failed to load jira-validation.sh"
fi

# Test 5: Test conflict resolution functions exist
echo "Testing conflict resolution functions availability..."
if source claude/lib/conflict-resolution.sh 2>/dev/null; then
    echo "✅ conflict-resolution.sh loaded successfully"
    
    # Test if key functions are available
    if declare -f detect_epic_conflicts >/dev/null 2>&1; then
        echo "✅ detect_epic_conflicts function available"
    else
        echo "❌ detect_epic_conflicts function not available"
    fi
else
    echo "❌ Failed to load conflict-resolution.sh"
fi

echo "Basic integration test completed."