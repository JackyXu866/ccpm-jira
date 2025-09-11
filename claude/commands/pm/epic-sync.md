---
allowed-tools: Bash, Read, Write, LS, Task
---

# Epic Sync

Push epic and tasks to Jira, creating Epic and Story/Task issues.

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
- If not, create new Story/Task in Jira:
  - Set Epic as parent
  - Use task name as summary
  - Copy acceptance criteria to description
  - Set appropriate issue type (Story/Task/Bug)
- If exists, update existing issue

### 4. Update Local Files

For each created/updated item:
- Add/update `jira:` field with issue key
- Add `last_sync:` timestamp
- Update `updated:` timestamp

Format:
```yaml
---
[existing fields]
jira: PROJ-123
last_sync: 2024-01-15T10:30:00Z
updated: 2024-01-15T10:30:00Z
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
- Dependencies are added as issue links
- Local files remain source of truth for detailed content
- Jira holds status and workflow state