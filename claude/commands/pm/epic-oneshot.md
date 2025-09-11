---
allowed-tools: Read, LS
---

# Epic Oneshot

Decompose epic into tasks and sync to Jira in one operation.

## Usage
```
/pm:epic-oneshot <epic_name>
```

## Prerequisites
- Epic must exist and not have tasks yet
- Epic must not be synced to Jira already
- Jira must be configured

## Instructions

### 1. Validate Prerequisites

The script already checked that:
- Epic exists at `.claude/epics/$ARGUMENTS/epic.md`
- No task files exist yet
- Epic hasn't been synced to Jira
- Jira is configured

### 2. Execute Decompose

Run the decompose command:
```
/pm:epic-decompose $ARGUMENTS
```

This will:
- Read the epic
- Create task files
- Update epic with task summary

### 3. Execute Sync

After decompose completes successfully, run:
```
/pm:epic-sync $ARGUMENTS
```

This will:
- Create Epic in Jira
- Create all tasks as Stories/Tasks
- Link tasks to Epic
- Update local files with Jira keys

### 4. Output

Show combined results from both operations:
```
✅ Epic oneshot complete!

📋 Decomposition:
   Created 5 tasks from epic

🔄 Jira sync:
   Epic: PROJ-100
   Tasks: PROJ-101 through PROJ-105

Ready to start work:
   /pm:epic-start $ARGUMENTS
```

## Error Handling

If decompose fails:
- Show error and stop
- Don't attempt sync

If sync fails:
- Tasks remain local only
- Can retry with `/pm:epic-sync`

## Why Use This?

Combines two commands for new epics:
1. `epic-decompose` - Creates tasks locally
2. `epic-sync` - Pushes to Jira

Saves time and ensures consistency when starting new features.