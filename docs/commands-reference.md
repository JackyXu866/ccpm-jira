# Claude Code PM - Command Reference

This comprehensive reference covers all PM commands with detailed explanations, examples, and Jira integration features.

## Table of Contents

### Core Commands
- [init](#init) - Initialize project for PM workflow
- [help](#help) - Display command help

### PRD Management
- [prd-new](#prd-new) - Create new product requirement document
- [prd-parse](#prd-parse) - Convert PRD to implementation epic
- [prd-list](#prd-list) - List all PRDs
- [prd-edit](#prd-edit) - Edit existing PRD
- [prd-status](#prd-status) - Show PRD implementation status

### Epic Management
- [epic-decompose](#epic-decompose) - Break epic into tasks *(Jira integrated)*
- [epic-sync](#epic-sync) - Push epic to GitHub/Jira *(Jira integrated)*
- [epic-oneshot](#epic-oneshot) - Decompose and sync in one command
- [epic-list](#epic-list) - List all epics *(Jira integrated)*
- [epic-show](#epic-show) - Display epic details
- [epic-close](#epic-close) - Mark epic as complete
- [epic-edit](#epic-edit) - Edit epic details
- [epic-refresh](#epic-refresh) - Update epic progress
- [epic-status](#epic-status) - Show epic execution status
- [epic-start](#epic-start) - Begin parallel execution
- [epic-start-worktree](#epic-start-worktree) - Start with Git worktree
- [epic-merge](#epic-merge) - Merge completed epic

### Issue/Task Management
- [issue-start](#issue-start) - Begin work on issue *(Jira integrated)*
- [issue-sync](#issue-sync) - Sync progress to GitHub/Jira *(Jira integrated)*
- [issue-close](#issue-close) - Complete and close issue *(Jira integrated)*
- [issue-show](#issue-show) - Display issue details
- [issue-status](#issue-status) - Check issue status
- [issue-reopen](#issue-reopen) - Reopen closed issue
- [issue-edit](#issue-edit) - Edit issue details
- [issue-analyze](#issue-analyze) - Analyze for parallel work

### Workflow Commands
- [next](#next) - Show next priority task
- [status](#status) - Overall project dashboard
- [standup](#standup) - Daily standup report
- [blocked](#blocked) - Show blocked tasks
- [in-progress](#in-progress) - List work in progress
- [search](#search) - Search across all content *(Jira integrated)*

### Sync & Maintenance
- [sync](#sync) - Full bidirectional sync
- [import](#import) - Import existing GitHub issues
- [validate](#validate) - Check system integrity
- [clean](#clean) - Archive completed work

---

## Core Commands

### init

Initialize a project for PM workflow integration.

```bash
/pm:init
```

**What it does:**
- Installs GitHub CLI if not present
- Configures authentication
- Sets up directory structure
- Creates initial configuration
- Optionally configures Jira integration

**Jira Integration:**
During setup, you'll be prompted to configure Jira:
- API token
- User email
- Site URL
- Project key
- Custom field mappings

### help

Display available commands and their descriptions.

```bash
/pm:help
```

Shows a concise list of all PM commands with brief descriptions.

---

## PRD Management

### prd-new

Launch guided brainstorming to create a comprehensive product requirement document.

```bash
/pm:prd-new <feature_name>
```

**Interactive Process:**
1. Problem definition
2. User stories and personas
3. Success metrics
4. Technical requirements
5. Scope and constraints

**Output:** Creates `.claude/prds/{feature_name}.md`

### prd-parse

Convert a PRD into an actionable implementation epic.

```bash
/pm:prd-parse <feature_name>
```

**Process:**
1. Reads PRD from `.claude/prds/{feature_name}.md`
2. Analyzes technical requirements
3. Creates implementation approach
4. Generates epic with task preview
5. Saves to `.claude/epics/{feature_name}/epic.md`

### prd-list

Display all PRDs with their implementation status.

```bash
/pm:prd-list
```

**Output Format:**
```
📋 my-feature
   Status: epic-created
   Created: 2024-01-15
   Epic: .claude/epics/my-feature/
```

### prd-edit

Edit an existing PRD interactively.

```bash
/pm:prd-edit <feature_name>
```

Opens PRD for editing and updates metadata.

### prd-status

Show implementation progress for a PRD.

```bash
/pm:prd-status <feature_name>
```

Displays:
- PRD creation date
- Epic status
- Task breakdown
- Overall progress

---

## Epic Management

### epic-decompose

Break an epic into concrete, actionable tasks.

```bash
/pm:epic-decompose <epic_name> [--with-jira]
```

**Options:**
- `--with-jira`: Create Jira tasks immediately (requires Jira mode)

**Jira Integration:**
When `--with-jira` is used:
- Creates local task files first
- Creates corresponding Jira issues
- Links tasks to Jira epic
- Maintains bidirectional mapping

**Output:**
- Task files in `.claude/epics/{epic_name}/`
- Numbered sequentially (001.md, 002.md, etc.)
- Jira mapping in `jira-mapping.json`

### epic-sync

Push epic and all tasks to GitHub as issues. Optionally syncs with Jira.

```bash
/pm:epic-sync <epic_name> [--skip-jira]
```

**Options:**
- `--skip-jira`: Skip Jira sync even if enabled

**Process:**
1. Creates GitHub epic issue
2. Creates sub-issues for each task
3. Updates local files with issue numbers
4. Creates Jira epic and stories if enabled
5. Establishes bidirectional links

**Jira Mode Features:**
- Creates Jira epic with same structure
- Maps all GitHub issues to Jira issues
- Syncs metadata (priority, labels, estimates)
- Maintains relationship hierarchy

### epic-oneshot

Convenience command that runs decompose and sync sequentially.

```bash
/pm:epic-oneshot <epic_name>
```

Equivalent to:
```bash
/pm:epic-decompose <epic_name>
/pm:epic-sync <epic_name>
```

### epic-list

Display all epics with status and progress information.

```bash
/pm:epic-list [--jira-sync]
```

**Options:**
- `--jira-sync`: Fetch latest status from Jira

**Jira Integration:**
- Shows both local and Jira status
- Highlights status mismatches
- Updates local status from Jira if requested
- Displays Jira assignees and versions

### epic-show

Display detailed information about an epic and its tasks.

```bash
/pm:epic-show <epic_name>
```

Shows:
- Epic metadata
- Task list with status
- Dependency graph
- Progress summary

### epic-close

Mark an epic as complete after all tasks are done.

```bash
/pm:epic-close <epic_name>
```

**Validations:**
- Checks all tasks are closed
- Updates epic status
- Archives if requested
- Syncs closure to Jira if enabled

### epic-edit

Edit epic details and metadata.

```bash
/pm:epic-edit <epic_name>
```

Allows editing:
- Epic description
- Technical approach
- Task breakdown preview

### epic-refresh

Update epic progress based on task completion.

```bash
/pm:epic-refresh <epic_name>
```

Recalculates:
- Task completion percentage
- Updates progress in frontmatter
- Syncs with GitHub/Jira

### epic-status

Show detailed execution status for an epic.

```bash
/pm:epic-status <epic_name>
```

**Real-time Monitoring:**
- Task completion status
- Parallel execution progress
- Agent activity
- Blockers and dependencies

### epic-start

Begin parallel execution of epic tasks using multiple agents.

```bash
/pm:epic-start <epic_name>
```

**Process:**
1. Analyzes all tasks for parallelization
2. Launches specialized agents for each stream
3. Monitors progress in real-time
4. Handles coordination between agents

### epic-start-worktree

Start epic with dedicated Git worktree.

```bash
/pm:epic-start-worktree <epic_name>
```

Creates isolated development environment:
- Separate worktree at `../epic-{name}/`
- Clean workspace for parallel development
- No conflicts with main branch

### epic-merge

Merge completed epic work back to main branch.

```bash
/pm:epic-merge <epic_name>
```

**Process:**
1. Validates all tasks complete
2. Merges worktree changes
3. Cleans up worktree
4. Updates epic status

---

## Issue/Task Management

### issue-start

Begin work on a specific issue with intelligent workflow integration.

```bash
/pm:issue-start <issue_number> [--analyze]
```

**Options:**
- `--analyze`: Run analysis first if not done

**Jira Integration:**
When Jira mode is enabled:
- Finds linked Jira issue in GitHub body
- Updates Jira status to "In Progress"
- Creates Jira-formatted branch (PROJ-123-description)
- Syncs assignee information

**Workflow:**
1. Validates issue access
2. Checks for analysis
3. Creates feature branch
4. Sets up progress tracking
5. Launches parallel agents
6. Updates issue status

### issue-sync

Synchronize local progress to GitHub and Jira.

```bash
/pm:issue-sync <issue_number> [--force]
```

**Options:**
- `--force`: Force sync even if recently synced

**Jira Integration:**
- Posts progress updates to both systems
- Syncs completion percentage
- Updates custom fields
- Maintains comment history

**Features:**
- Incremental updates only
- Formats progress professionally
- Includes acceptance criteria status
- Links commits and changes

### issue-close

Complete and close an issue with proper resolution tracking.

```bash
/pm:issue-close <issue_number> [resolution] [--create-pr]
```

**Arguments:**
- `resolution`: Fixed, Won't Fix, Duplicate, Cannot Reproduce
- `--create-pr`: Create pull request if on feature branch

**Jira Integration:**
- Maps resolution to Jira values
- Transitions issue to Done/Closed
- Updates time tracking
- Links PR if created

**Process:**
1. Updates local task status
2. Closes GitHub issue
3. Transitions Jira issue
4. Creates PR if requested
5. Updates epic progress

### issue-show

Display comprehensive issue information.

```bash
/pm:issue-show <issue_number>
```

Shows:
- Issue metadata
- Description and acceptance criteria
- Current status and progress
- Related commits
- Jira link if available

### issue-status

Quick status check for an issue.

```bash
/pm:issue-status <issue_number>
```

Returns:
- Current state
- Assignee
- Progress percentage
- Last update time

### issue-reopen

Reopen a previously closed issue.

```bash
/pm:issue-reopen <issue_number>
```

**Features:**
- Reopens on GitHub
- Updates local status
- Resets progress tracking
- Syncs with Jira if enabled

### issue-edit

Edit issue details and metadata.

```bash
/pm:issue-edit <issue_number>
```

Allows editing:
- Title and description
- Acceptance criteria
- Labels and assignees

### issue-analyze

Analyze an issue for parallel work streams.

```bash
/pm:issue-analyze <issue_number>
```

**Analysis Produces:**
- Work stream breakdown
- Parallelization opportunities
- Dependencies between streams
- Agent type recommendations

Creates: `.claude/epics/{epic}/{issue}-analysis.md`

---

## Workflow Commands

### next

Show the next priority task to work on.

```bash
/pm:next
```

**Smart Prioritization:**
- Unblocked tasks first
- Respects dependencies
- Considers work in progress
- Balances across epics

**Jira Integration:**
- Considers Jira priority field
- Checks sprint assignment
- Validates assignee

### status

Display comprehensive project dashboard.

```bash
/pm:status
```

**Dashboard Shows:**
- Active epics and progress
- Tasks in progress
- Blocked items
- Recent completions
- Team velocity

### standup

Generate daily standup report.

```bash
/pm:standup
```

**Report Includes:**
- Yesterday's completed work
- Today's planned tasks
- Current blockers
- Progress metrics

**Jira Integration:**
- Pulls updates from both systems
- Shows Jira ticket numbers
- Includes sprint information

### blocked

List all blocked tasks with reasons.

```bash
/pm:blocked
```

**Shows:**
- Task details
- Blocking reason
- Dependencies waiting on
- Suggested actions

### in-progress

Show all work currently in progress.

```bash
/pm:in-progress
```

**Details:**
- Active tasks by assignee
- Progress percentages
- Time in progress
- Recent updates

### search

Unified search across local files and Jira.

```bash
/pm:search [OPTIONS] <query>
```

**Options:**
- `--local`: Search only local files
- `--jira`: Search only Jira
- `--jql`: Use JQL syntax
- `--format`: Output format (table, json, csv, markdown)
- `--limit`: Max results
- `--save-as`: Save search
- `--interactive`: Interactive mode

**Smart Query Routing:**
- Natural language processing
- Automatic JQL conversion
- Unified result ranking
- Source attribution

**Examples:**
```bash
# Natural language
/pm:search "my open tasks"
/pm:search "authentication bugs"

# JQL
/pm:search --jql "assignee = currentUser() AND status = 'In Progress'"

# Save frequent search
/pm:search --save-as "my-sprint" "sprint in openSprints() AND assignee = me"
```

---

## Sync & Maintenance Commands

### sync

Perform full bidirectional sync with GitHub.

```bash
/pm:sync
```

**Syncs:**
- All epics and tasks
- Progress updates
- Status changes
- Issue assignments

### import

Import existing GitHub issues into PM system.

```bash
/pm:import [--epic <name>]
```

**Options:**
- `--epic`: Import into specific epic

**Process:**
- Fetches GitHub issues
- Creates local task files
- Preserves metadata
- Sets up tracking

### validate

Check system integrity and consistency.

```bash
/pm:validate
```

**Validates:**
- File structure
- Frontmatter format
- GitHub issue links
- Progress calculations
- Jira mappings

### clean

Archive completed work and maintain system.

```bash
/pm:clean [--force]
```

**Options:**
- `--force`: Archive without confirmation

**Actions:**
- Archives completed epics
- Removes old cache files
- Compresses worktrees
- Updates indexes

---

## Jira Integration Configuration

### Environment Variables

Required for Jira integration:
```bash
export JIRA_API_TOKEN="your-api-token"
export JIRA_USER_EMAIL="you@company.com"
export JIRA_SITE_URL="https://company.atlassian.net"
```

### Settings File

Configure in `claude/settings.local.json`:
```json
{
  "jira": {
    "enabled": true,
    "project_key": "PROJ",
    "epic_issue_type": "Epic",
    "task_issue_type": "Story",
    "default_priority": "Medium",
    "custom_fields": {
      "github_url": "customfield_10100",
      "story_points": "customfield_10001",
      "acceptance_criteria": "customfield_10002"
    },
    "transitions": {
      "start": "Start Progress",
      "done": "Done",
      "wont_do": "Won't Do"
    }
  }
}
```

### Mode Detection

Commands automatically detect Jira mode when:
1. `settings.local.json` exists
2. Contains `jira.enabled: true`
3. Required environment variables are set

### Fallback Behavior

If Jira integration fails:
- Commands continue in GitHub-only mode
- Error is logged but not fatal
- User is notified of degraded functionality
- Local work is preserved

---

## Best Practices

### 1. Start with PRDs
Always begin with a well-defined PRD for clarity and alignment.

### 2. Decompose Thoughtfully
Break epics into 1-3 day tasks for optimal parallelization.

### 3. Sync Regularly
Run `issue-sync` 2-3 times daily during active development.

### 4. Use Search Effectively
Save common searches for quick access to relevant work.

### 5. Monitor Progress
Use `epic-status` and `status` commands to track team velocity.

### 6. Leverage Jira When Available
The integration provides rich project management capabilities.

---

## Troubleshooting

### Command Not Found
Ensure you've run `/pm:init` to set up the environment.

### GitHub Authentication
Run `gh auth login` if you see authentication errors.

### Jira Connection Issues
1. Verify API token is valid
2. Check site URL is correct
3. Ensure user has project access
4. Test with simple search first

### Sync Conflicts
Use `--force` flags when you're certain local state is correct.

### Performance Issues
1. Use specific searches
2. Enable caching
3. Limit result counts
4. Check network connectivity

---

## Command Aliases

For frequently used commands, consider shell aliases:

```bash
alias pms="/pm:status"
alias pmn="/pm:next"
alias pmsync="/pm:issue-sync"
alias pmsearch="/pm:search"
```

---

This reference is comprehensive but not exhaustive. Each command has additional options and edge cases documented in its individual help file. For command-specific details, see `/claude/commands/pm/{command}.md`.