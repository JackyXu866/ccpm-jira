---
allowed-tools: Bash, Read, Write, LS
---

# Task Reopen

Reopen a closed task.

## Usage
```
/pm:task-reopen <task_number> [reason]
```

## Instructions

### 1. Find Local Task File

Search for task file in `.claude/epics/*/$ARGUMENTS.md`.
If not found: "❌ No local task for task $ARGUMENTS"

### 2. Update Local Status

Get current datetime: `date -u +"%Y-%m-%dT%H:%M:%SZ"`

Update task file frontmatter:
```yaml
status: open
updated: {current_datetime}
```

### 3. Reset Progress

If progress file exists:
- Keep original started date
- Reset completion to previous value or 0%
- Add note about reopening with reason

### 4. Reopen in Jira

If jira_key exists in task file:
- Use MCP Atlassian tools to transition issue back to "To Do" or "Open" status
- Add comment explaining the reopening reason
- Update any custom fields as needed

### 5. Update Epic Progress

Recalculate epic progress with this task now open again.

### 6. Output

```
🔄 Reopened task $ARGUMENTS
  Reason: {reason_if_provided}
  Epic progress: {updated_progress}%
  
Start work with: /pm:task-start $ARGUMENTS
```

## Important Notes

Preserve work history in progress files.
Don't delete previous progress, just reset status.