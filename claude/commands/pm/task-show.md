---
allowed-tools: Bash, Read, LS
---

# Task Show

Display task and sub-tasks with detailed information.

## Usage
```
/pm:task-show <task_number>
```

## Instructions

You are displaying comprehensive information about a task and related sub-tasks for: **Task $ARGUMENTS**

### 1. Fetch Task Data
- Look for local task file in `.claude/epics/*/$ARGUMENTS.md`
- Use MCP Atlassian tools to get Jira task details if jira_key is present
- Check for related tasks and sub-tasks

### 2. Task Overview
Display task header:
```
🎫 Task $ARGUMENTS: {Title}
   Status: {open/closed}
   Labels: {labels}
   Assignee: {assignee}
   Created: {creation_date}
   Updated: {last_update}
   
📝 Description:
{issue_description}
```

### 3. Local File Mapping
If local task file exists:
```
📁 Local Files:
   Task file: .claude/epics/{epic_name}/{task_file}
   Updates: .claude/epics/{epic_name}/updates/$ARGUMENTS/
   Last local update: {timestamp}
```

### 4. Sub-Tasks and Dependencies
Show related tasks:
```
🔗 Related Tasks:
   Parent Epic: #{epic_issue_number}
   Dependencies: #{dep1}, #{dep2}
   Blocking: #{blocked1}, #{blocked2}
   Sub-tasks: #{sub1}, #{sub2}
```

### 5. Recent Activity
Display recent comments and updates:
```
💬 Recent Activity:
   {timestamp} - {author}: {comment_preview}
   {timestamp} - {author}: {comment_preview}
   
   View full thread: Use MCP tools to get Jira comments
```

### 6. Progress Tracking
If task file exists, show progress:
```
✅ Acceptance Criteria:
   ✅ Criterion 1 (completed)
   🔄 Criterion 2 (in progress)
   ⏸️ Criterion 3 (blocked)
   □ Criterion 4 (not started)
```

### 7. Quick Actions
```
🚀 Quick Actions:
   Start work: /pm:task-start $ARGUMENTS
   Sync updates: /pm:task-sync $ARGUMENTS
   Add comment: Use MCP tools to add Jira comment
   View in Jira: Open Jira in browser with issue key
```

### 8. Error Handling
- Handle invalid issue numbers gracefully
- Check for network/authentication issues
- Provide helpful error messages and alternatives

Provide comprehensive task information to help developers understand context and current status for Task $ARGUMENTS.
