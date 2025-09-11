---
allowed-tools: Bash, Read, Write, LS, Task
---

# Import

Import existing Jira issues into the PM system.

## Usage
```
/pm:import [--project KEY] [--epic name] [--jql query]
```

Options:
- `--project` - Import from specific Jira project
- `--epic` - Import into specific local epic
- `--jql` - Custom JQL query for import

## Instructions

### 1. Execute Jira Search

Use the provided JQL query to search Jira:
```
# Example queries:
project = PROJ AND issuetype = Story AND sprint in openSprints()
project = PROJ AND assignee = currentUser() AND status != Done
```

### 2. Check for Existing Local Files

For each Jira issue found:
- Search local files for matching `jira:` field
- If found, skip (already tracked)
- If not found, mark for import

### 3. Organize by Epic

Based on issue type and parent:
- **Epic type** → Create new epic structure
- **Has Epic parent** → Import into that epic
- **Specified --epic** → Import into specified epic
- **No epic** → Create in "imported" epic

### 4. Create Local Structure

For each issue to import:

**If Epic:**
```bash
mkdir -p .claude/epics/{epic-name}
# Create epic.md with Jira data
```

**If Task/Story:**
```bash
# Find next available task number
# Create task file with Jira data
```

### 5. Create File Content

Convert Jira fields to local format:
```yaml
---
name: [Summary from Jira]
status: [Map Jira status to local]
jira: [Issue key]
assignee: [Jira assignee]
created: [From Jira]
updated: [From Jira]
imported: [Current timestamp]
---

# Task: [Summary]

## Description
[Description from Jira]

## Acceptance Criteria
[Converted from Jira]
```

### 6. Status Mapping

Map Jira statuses to local:
- To Do, Open, Backlog → `open`
- In Progress, In Review → `in-progress`
- Done, Closed, Resolved → `closed`

### 7. Output Summary

```
📥 Import Complete

Imported from Jira:
  Query: project = PROJ AND updated >= -7d
  Found: 15 issues
  
Created locally:
  ✅ 2 epics imported
  ✅ 10 tasks imported
  ⏭️ 3 already tracked (skipped)
  
Organization:
  📁 feature-auth: 5 tasks
  📁 feature-api: 4 tasks
  📁 imported: 1 task
  
Next steps:
  • Review imported tasks
  • Run /pm:sync to push any updates back
  • Start work with /pm:issue-start
```

## Import Strategies

### Full Project Import
```
/pm:import --project PROJ
```
Imports all recent issues from a project.

### Targeted Import
```
/pm:import --jql "labels = needs-import"
```
Import specific labeled issues.

### Into Existing Epic
```
/pm:import --epic feature-auth --jql "parent = PROJ-100"
```
Import child issues into local epic.

## Error Handling

- Invalid JQL: Show error and example queries
- No results: Confirm query is correct
- Duplicate detection: Skip already imported
- Missing epic: Create "imported" epic automatically