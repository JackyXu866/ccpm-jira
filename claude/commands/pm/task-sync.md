# Task Sync

Synchronize local task data with Jira. Handles bidirectional sync between local task files and Jira tasks.

## Usage
```
/pm:task-sync <task_number> [--force]
```

## Arguments
- `task_number`: The local task number to sync
- `--force`: Force sync even if recently synced (within 5 minutes)

## Quick Check
1. **Task File Exists:**
   - If `.claude/epics/*/$ARGUMENTS.md` not found, tell user: "❌ Task #$ARGUMENTS not found"
   
2. **Jira Configuration:**
   - Check if Jira is enabled in settings
   - If not configured: "❌ Jira integration not configured. Run: /pm:jira-init"

## Instructions

You are synchronizing local development progress with Jira for: **Task #$ARGUMENTS**

### 1. Check Jira Configuration
- Verify Jira is enabled in claude/settings.local.json
- Ensure MCP Atlassian is connected

### 2. Find Local Task File
- Check `.claude/epics/*/$ARGUMENTS.md`
- Extract epic name, status, progress information

### 3. Sync with Jira
- Fetch latest data from Jira
- Detect conflicts between local and remote
- Apply conflict resolution (local wins by default)
- Update both local and Jira states

### 4. Update Local Task File
Update frontmatter with current timestamp:
```yaml
---
[existing fields]
updated: [current datetime]
last_sync: [current datetime]
---
```

### 5. Output Summary
```
🔄 Synced task #$ARGUMENTS with Jira

📝 Update summary:
   Status: {status}
   Progress: {progress}%
   Assignee: {assignee}
   
✅ Local and Jira are now in sync
```

## Error Handling
- Network failures: Show clear error message
- Auth issues: Guide user to reconnect MCP
- Conflicts: Show what differs and how it was resolved

## Jira Integration Features
1. **Bidirectional Sync**: Updates flow both ways
2. **Conflict Detection**: Identifies differences
3. **Smart Resolution**: Handles conflicts intelligently
4. **Progress Tracking**: Syncs completion percentage

## Output Examples

**Successful Sync:**
```
🔄 Syncing task #123
📁 Found task: .claude/epics/feature-auth/123.md
🔄 Mode: Jira
📊 Fetching from Jira...
✅ Updated local cache
✅ Pushed changes to Jira
✅ Task #123 synchronized successfully
```

## Common Issues

1. **Jira Not Configured**
   - Run: /pm:jira-init
   - Connect MCP: /mcp atlassian

2. **Task Not Found in Jira**
   - Verify task exists in Jira
   - Check project key is correct
   - Ensure you have access permissions

3. **Sync Conflicts**
   - Use --force to override with local version
   - Review differences before forcing