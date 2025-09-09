#!/bin/bash

# Source the libraries
source claude/lib/jira-fields.sh

echo "=== Testing Interface Functions for Streams A and B ==="
echo

# Test epic preparation for Jira
EPIC_DATA='{"name":"jira-implementation","status":"in-progress","progress":"25%","prd":".claude/prds/jira-implementation.md","github":"https://github.com/JackyXu866/ccpm-jira/issues/1","description":"Complete CCPM to Jira integration"}'

echo "1. Testing prepare_epic_for_jira:"
echo "Input Epic Data: $EPIC_DATA"
echo "Jira-ready JSON:"
prepare_epic_for_jira "jira-implementation" "$EPIC_DATA" | jq .
echo

# Test task preparation for Jira
TASK_DATA='{"name":"Implement core CRUD operations","status":"open","depends_on":[2],"parallel":false,"conflicts_with":[],"description":"Create/read/update/delete operations for epics and issues"}'

echo "2. Testing prepare_task_for_jira:"
echo "Input Task Data: $TASK_DATA"
echo "Jira-ready JSON:"
prepare_task_for_jira "Implement core CRUD operations" "$TASK_DATA" | jq .
echo

# Test reverse mapping (Jira response to CCPM)
JIRA_EPIC_RESPONSE='{"key":"PROJ-123","fields":{"summary":"jira-implementation","status":{"name":"In Progress"},"customfield_10010":25,"customfield_10011":".claude/prds/jira-implementation.md","customfield_10012":"https://github.com/JackyXu866/ccpm-jira/issues/1"}}'

echo "3. Testing process_jira_epic_response:"
echo "Input Jira Response: $JIRA_EPIC_RESPONSE" 
echo "CCPM-formatted data:"
process_jira_epic_response "$JIRA_EPIC_RESPONSE" | jq .
echo

echo "=== Interface Functions Test Complete ==="