---
allowed-tools: Bash, Read, LS
---

# Task Status

Check task status (open/closed) and current state.

## Usage
```
/pm:task-status <task_number>
```

## Instructions

You are checking the current status of a task and providing a quick status report for: **Task $ARGUMENTS**

### 1. Fetch Task Status
- Find local task file in `.claude/epics/*/$ARGUMENTS.md`
- If jira_key exists, use MCP Atlassian tools to get Jira issue status
- Otherwise check local status field

### 2. Status Display
Show concise status information:
```
🎫 Task $ARGUMENTS: {Title}
   
📊 Status: {OPEN/CLOSED}
   Last update: {timestamp}
   Assignee: {assignee or "Unassigned"}
   
🏷️ Labels: {label1}, {label2}, {label3}
```

### 3. Epic Context
If task is part of an epic:
```
📚 Epic Context:
   Epic: {epic_name}
   Epic progress: {completed_tasks}/{total_tasks} tasks complete
   This task: {task_position} of {total_tasks}
```

### 4. Local Sync Status
Check if local files are in sync:
```
💾 Local Sync:
   Local file: {exists/missing}
   Last local update: {timestamp}
   Sync status: {in_sync/needs_sync/local_ahead/remote_ahead}
```

### 5. Quick Status Indicators
Use clear visual indicators:
- 🟢 Open and ready
- 🟡 Open with blockers  
- 🔴 Open and overdue
- ✅ Closed and complete
- ❌ Closed without completion

### 6. Actionable Next Steps
Based on status, suggest actions:
```
🚀 Suggested Actions:
   - Start work: /pm:task-start $ARGUMENTS
   - Sync updates: /pm:task-sync $ARGUMENTS
   - Close task: /pm:task-close $ARGUMENTS
   - Reopen task: /pm:task-reopen $ARGUMENTS
```

### 7. Batch Status
If checking multiple tasks, support comma-separated list:
```
/pm:task-status 123,124,125
```

Keep the output concise but informative, perfect for quick status checks during development of Task $ARGUMENTS.
