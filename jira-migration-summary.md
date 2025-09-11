# Jira Migration Summary

This document summarizes the migration from GitHub Issues to Jira integration for CCPM.

## Key Concept
The workflow remains the same: **PRD → Epic → Tasks/Issues**
But now syncs with Jira instead of GitHub Issues.

## Commands Restored and Updated

### Epic Commands
1. **`/pm:epic-sync`** - Now pushes epics and tasks to Jira (not GitHub)
2. **`/pm:epic-oneshot`** - Still combines decompose + sync, but syncs to Jira
3. **`/pm:sync`** - Full bidirectional sync, now with Jira
4. **`/pm:import`** - Import issues, now from Jira projects

### Workflow Changes
- **Before**: `prd-parse → epic-decompose → epic-sync (GitHub)`
- **After**: `prd-parse → epic-decompose → epic-sync (Jira)`

## What Changed

### Removed GitHub Issue Integration
- No more `github:` fields in frontmatter
- No GitHub issue creation or updates
- No GitHub labels or assignees

### Added Jira Integration
- `jira:` field stores Jira issue keys (e.g., PROJ-123)
- Direct integration via MCP Atlassian tools
- Supports Jira workflows, custom fields, and issue types

### Updated Commands
All commands now work with Jira instead of GitHub:
- `issue-start` - Updates Jira status, creates Jira-formatted branches
- `issue-close` - Transitions Jira issues to Done
- `issue-sync` - Bidirectional sync with Jira
- `epic-sync` - Creates Epic and Story/Task issues in Jira
- `sync` - Full project sync with Jira
- `import` - Import from Jira using JQL queries

## Benefits
1. **Enterprise Features** - Leverage Jira's advanced project management
2. **Better Integration** - Direct API access via MCP, no CLI tools needed
3. **Workflow Support** - Respects Jira workflows and transitions
4. **Custom Fields** - Support for story points, sprints, etc.
5. **JQL Search** - Powerful query language for finding issues

## Migration Path
For existing projects:
1. Remove `github:` fields from all task files (already done)
2. Run `/pm:sync` to create Jira issues for existing epics/tasks
3. Use `/pm:import` to bring in any existing Jira issues

## Workflow Remains the Same
The core PM workflow is unchanged:
1. `/pm:prd-new` - Create PRD through brainstorming
2. `/pm:prd-parse` - Convert to epic
3. `/pm:epic-decompose` - Break into tasks
4. `/pm:epic-sync` - Push to Jira (previously GitHub)
5. `/pm:issue-start` - Begin work with agents

The only difference is that issue tracking now happens in Jira instead of GitHub Issues.