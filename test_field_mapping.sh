#!/bin/bash

# Source the libraries
source claude/lib/jira-fields.sh

echo "=== Testing Field Mapping Functions ==="
echo

# Test CCPM epic data
CCPM_EPIC='{"name":"jira-implementation","status":"in-progress","progress":"25%","prd":".claude/prds/jira-implementation.md","github":"https://github.com/JackyXu866/ccpm-jira/issues/1"}'

echo "1. Testing CCPM Epic to Jira mapping:"
echo "Input: $CCPM_EPIC"
echo "Output:"
map_ccpm_epic_to_jira "$CCPM_EPIC" | jq .
echo

# Test status transformation
echo "2. Testing status transformation:"
echo "CCPM 'in-progress' -> Jira:"
transform_status_ccpm_to_jira "in-progress"
echo "Jira 'In Progress' -> CCPM:"
transform_status_jira_to_ccpm "In Progress"
echo

# Test CCPM task data
CCPM_TASK='{"name":"Implement core CRUD operations","status":"open","depends_on":[2],"parallel":false,"conflicts_with":[]}'

echo "3. Testing CCPM Task to Jira mapping:"
echo "Input: $CCPM_TASK"
echo "Output:"
map_ccpm_task_to_jira "$CCPM_TASK" | jq .
echo

# Test validation
echo "4. Testing validation:"
echo "Validating CCPM epic:"
if validate_ccpm_epic "$CCPM_EPIC"; then
    echo "✅ Epic validation passed"
else
    echo "❌ Epic validation failed"
fi

echo "Validating CCPM task:"
if validate_ccpm_task "$CCPM_TASK"; then
    echo "✅ Task validation passed"
else
    echo "❌ Task validation failed"
fi
echo

echo "=== Field Mapping Test Complete ==="