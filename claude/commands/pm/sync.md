---
allowed-tools: Bash, Read, Write, LS, Task
---

# Sync

Full bidirectional sync between local files and Jira.

## Usage
```
/pm:sync [epic_name]
```

If epic_name provided, sync only that epic. Otherwise sync all.

## Instructions

### 1. Find All Synced Items

Search for all files with `jira:` field:
```bash
find .claude/epics -name "*.md" -exec grep -l "^jira:" {} \;
```

Group by epic and identify:
- Epics with Jira keys
- Tasks with Jira keys
- Items without Jira keys (need creation)

### 2. Pull from Jira

For each item with a Jira key:
- Fetch current state from Jira
- Compare with local state:
  - Check `updated` timestamps
  - Compare status, assignee, description
- If Jira newer, update local:
  - Status changes
  - Assignee changes
  - Progress updates

### 3. Push to Jira

For each local change (local newer than Jira):
- Update Jira issue with local content
- Sync status transitions if needed
- Update description/acceptance criteria

For items without Jira keys:
- Create new issues in Jira
- Add Jira key to local file
- Set appropriate issue type and parent

### 4. Handle Conflicts

If both changed since last sync:
- Local changes to content → Local wins
- Jira workflow state changes → Jira wins
- Show conflict summary to user

### 5. Update Sync Timestamps

For all synced items:
```yaml
last_sync: [current_timestamp]
```

### 6. Output Summary

```
🔄 Sync Complete

📥 Pulled from Jira:
   Updated: 3 issues
   Status changes: 2
   New assignments: 1

📤 Pushed to Jira:
   Updated: 5 issues
   Created: 2 new issues
   
⚠️ Conflicts resolved:
   Task #3: Used local content, kept Jira status
   
✅ All items synced successfully
   Total synced: 12 items
   Sync time: 2024-01-20T10:30:00Z
```

## Sync Rules

1. **Content**: Local files are source of truth
2. **Status**: Jira workflow is source of truth
3. **Progress**: Calculated from task completion
4. **Assignee**: Jira is source of truth
5. **New items**: Created in Jira during sync

## Error Handling

- Network issues: Retry failed items
- Permission errors: Skip and report
- Invalid transitions: Keep current state
- Missing projects: Guide user to create

## Performance

For large syncs:
- Batch API calls where possible
- Show progress indicator
- Allow partial sync on failure