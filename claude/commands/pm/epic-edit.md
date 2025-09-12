---
allowed-tools: Read, Write, LS
---

# Epic Edit

Edit epic details after creation.

## Usage
```
/pm:epic-edit <epic_name>
```

## Instructions

### 1. Read Current Epic

Read `.claude/epics/$ARGUMENTS/epic.md`:
- Parse frontmatter
- Read content sections

### 2. Interactive Edit

Ask user what to edit:
- Name/Title
- Description/Overview
- Architecture decisions
- Technical approach
- Dependencies
- Success criteria

### 3. Update Epic File

Get current datetime: `date -u +"%Y-%m-%dT%H:%M:%SZ"`

Update epic.md:
- Preserve all frontmatter except `updated`
- Apply user's edits to content
- Update `updated` field with current datetime

### 4. Option to Update Jira

If epic has jira_key in frontmatter:
Ask: "Update Jira epic? (yes/no)"

If yes:
- Use MCP Atlassian tools to update epic summary and description
- Update any custom fields that have changed

### 5. Output

```
✅ Updated epic: $ARGUMENTS
  Changes made to: {sections_edited}
  
{If Jira updated}: Jira epic updated ✅

View epic: /pm:epic-show $ARGUMENTS
```

## Important Notes

Preserve frontmatter history (created, jira_key, etc.).
Don't change task files when editing epic.
Follow `/rules/frontmatter-operations.md`.