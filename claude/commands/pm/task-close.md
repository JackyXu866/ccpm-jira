---
allowed-tools: Bash, Read, Write, LS
---

# Task Close

Mark a task as complete and close it in Jira with proper resolution tracking.

## Usage
```
/pm:task-close <task_number> [resolution] [--create-pr]
```

## Arguments
- `task_number`: The local task number to close
- `resolution`: Resolution type (default: "Fixed")
  - Fixed - Issue was resolved
  - Won't Fix - Issue will not be addressed
  - Duplicate - Issue is a duplicate
  - Cannot Reproduce - Issue could not be reproduced

## Prerequisites
- Jira must be configured in `claude/settings.local.json` with `jira.enabled: true`
- MCP Atlassian connection must be active

## Instructions

### 1. Find Local Task File

Check if `.claude/epics/*/$ARGUMENTS.md` exists.
If not found: "❌ No local task for issue #$ARGUMENTS"

### 2. Update Local Status

Get current datetime: `date -u +"%Y-%m-%dT%H:%M:%SZ"`

Update task file frontmatter:
```yaml
status: closed
updated: {current_datetime}
```

### 3. Update Progress File

If progress file exists at `.claude/epics/{epic}/updates/$ARGUMENTS/progress.md`:
- Set completion: 100%
- Add completion note with timestamp
- Update last_sync with current datetime

### 4. Close in Jira

Use Jira MCP tools to:
- Transition issue to Done/Closed status
- Set resolution field based on provided resolution type
- Add completion comment with timestamp

### 5. Update Epic Progress

- Count total tasks in epic
- Count closed tasks
- Calculate new progress percentage
- Update epic.md frontmatter progress field

### 6. Output

```
✅ Closed issue #$ARGUMENTS
  Local: Task marked complete
  Jira: Issue transitioned to Done
  Epic progress: {new_progress}% ({closed}/{total} tasks complete)
  
Next: Run /pm:next for next priority task
```

## Important Notes

Follow `/rules/frontmatter-operations.md` for updates.
Always sync local state before Jira.

## Jira Integration Details

1. **Validates Setup**: Checks for required configuration
   - Jira enabled in settings
   - MCP connection active

2. **Maps Resolution**: Converts resolution to Jira format
   - Fixed → Done
   - Won't Fix → Won't Do
   - Duplicate → Duplicate
   - Cannot Reproduce → Cannot Reproduce

3. **Updates Jira Status**: Transitions issue to Done/Closed
   - Finds available transitions
   - Sets resolution field
   - Adds completion comment

## Example Output

```
🎯 Closing issue #123 with resolution: Fixed
🔄 Mode: Jira
📋 Checking local task file...
   Task: Implement user authentication
🔄 Delegating to Jira implementation...
🔍 Found Jira issue: PROJ-456
📊 Transitioning Jira issue to Done...
✅ Jira issue closed with resolution: Done
✅ Issue #123 closed successfully
```