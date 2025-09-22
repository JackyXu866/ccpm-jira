---
allowed-tools: Bash, Read, Write, LS, Task
---

# Epic Sync

Push epic and tasks to Jira, creating Epic and Story/Task items.

## Usage
```
/pm:epic-sync <epic_name>
```

## Quick Check
1. **Epic exists:**
   - If `.claude/epics/$ARGUMENTS/epic.md` not found: "❌ Epic not found"
   
2. **Tasks exist:**
   - If no `[0-9]*.md` files in epic dir: "❌ No tasks found. Run: /pm:epic-decompose $ARGUMENTS"

3. **Jira configured:**
   - Check if Jira is enabled in settings
   - If not configured: "❌ Jira integration not configured. Run: /pm:jira-init"

## Instructions

You are syncing an epic and its tasks to Jira: **Epic: $ARGUMENTS**

### 1. Read Epic and Tasks

Read `.claude/epics/$ARGUMENTS/epic.md`:
- Extract name, status, progress
- Check if `jira:` field exists (means already synced)

Count and read all task files in the epic directory.

### 2. Create/Update Epic in Jira

**If no `jira:` field (first sync):**
- Create new Epic in Jira
- Use epic name as summary
- Set description from epic content
- Add custom fields as needed

**If `jira:` field exists (update):**
- Update existing Epic
- Sync progress percentage
- Update description if changed

### 3. Create/Update Tasks

For each task file:
- Check if task has `jira:` field
- If not, create new Story/Task in Jira with:
  - **Epic Link**: Set as parent epic
  - **Summary**: Task name
  - **Description**: Full task details including acceptance criteria
  - **Issue Type**: Story/Task based on size
  - **Assignee**: From task file or current user
  - **Story Points**: From effort estimate
  - **Original Estimate**: Hours from effort size
  - **Remaining Estimate**: Claude-adjusted estimate (50% typical reduction)
  - **Priority**: Based on dependencies and critical path
  - **Labels**: ccpm-task, epic name, parallel/sequential
  - **Sprint**: Current active sprint if available
  - **Components**: Based on task type (frontend/backend/etc)
  - **Fix Version**: From epic target version
  - **Dependencies**: Create "blocks/blocked by" links
- If exists, update existing task with any changes

### 4. Update Local Files

For each created/updated item:
- Add/update `jira:` field with task key
- Add `last_sync:` timestamp
- Update `updated:` timestamp

Format:
```yaml
---
[existing fields]
jira: PROJ-123
jira_url: https://company.atlassian.net/browse/PROJ-123
assignee_id: 557058:12345678-1234-1234-1234-123456789012
last_sync: 2024-01-15T10:30:00Z
updated: 2024-01-15T10:30:00Z
story_points: 3
original_estimate: 24h
claude_estimate: 12h
---
```

### 5. Output Summary

```
✅ Epic synced to Jira

📚 Epic: $ARGUMENTS (PROJ-100)
   Status: in-progress
   Progress: 25%

📝 Tasks synced:
   ✅ PROJ-101 - Task 1 (created)
   ✅ PROJ-102 - Task 2 (created)
   ✅ PROJ-103 - Task 3 (updated)

🔗 Jira links:
   Epic: https://company.atlassian.net/browse/PROJ-100
   Board: https://company.atlassian.net/jira/software/projects/PROJ/boards/1

Next steps:
   • Start work: /pm:epic-start $ARGUMENTS
   • View in Jira: Open links above
```

## Error Handling

- If Jira project not found: Guide user to create project
- If permissions denied: Check user has create permissions
- If custom fields missing: Use defaults and note in output

## Important Notes

- Epic becomes Jira Epic type
- Tasks become Story or Task type based on size
- Dependencies are added as task links
- Local files remain source of truth for detailed content
- Jira holds status and workflow state

## MCP Tool Usage for Field Setting

When creating/updating Jira issues, use these MCP Atlassian tool parameters:

### Creating Tasks
```javascript
{
  "summary": "Task name from file",
  "description": "Full task description with acceptance criteria",
  "issuetype": "Story" or "Task",
  "parent": { "key": "EPIC-KEY" },
  "assignee": { "accountId": "user-account-id" },
  "priority": { "name": "High/Medium/Low" },
  "labels": ["ccpm-task", "epic-name", "parallel"],
  "customfield_10016": storyPoints, // Story points field
  "timetracking": {
    "originalEstimate": "24h",
    "remainingEstimate": "12h" // Claude-adjusted
  },
  "components": [{ "name": "Backend" }],
  "fixVersions": [{ "name": "v1.2.0" }]
}
```

### Creating Dependencies
After creating tasks, create task links:
```javascript
{
  "type": { "name": "Blocks" },
  "inwardIssue": { "key": "PROJ-101" },
  "outwardIssue": { "key": "PROJ-102" }
}
```

### Time Estimation with Claude Code
- Original estimate: Developer time without AI assistance
- Claude estimate: Typically 40-60% of original
- Factors:
  - Boilerplate generation: 80% reduction
  - Complex logic: 40% reduction
  - Debugging: 50% reduction
  - Documentation: 70% reduction