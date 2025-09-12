---
allowed-tools: Bash, Read, Write, LS
---

# Task Edit

Edit task details locally and in Jira.

## Usage
```
/pm:task-edit <task_number>
```

## Instructions

### 1. Get Current Task State

```bash
# Find local task file
# Search in .claude/epics/*/$ARGUMENTS.md
# Get Jira task details using MCP tools
```

### 2. Interactive Edit

Ask user what to edit:
- Title
- Description/Body
- Labels
- Acceptance criteria (local only)
- Priority/Size (local only)

### 3. Update Local File

Get current datetime: `date -u +"%Y-%m-%dT%H:%M:%SZ"`

Update task file with changes:
- Update frontmatter `name` if title changed
- Update body content if description changed
- Update `updated` field with current datetime

### 4. Update Jira

Use MCP Atlassian tools to:
- Update task summary if title changed
- Update task description if body changed
- Update task labels if changed
- Update custom fields as needed

### 5. Output

```
✅ Updated task #$ARGUMENTS
  Changes:
    {list_of_changes_made}
  
Synced to Jira: ✅
```

## Important Notes

Always update local first, then Jira.
Preserve frontmatter fields not being edited.
Follow `/rules/frontmatter-operations.md`.