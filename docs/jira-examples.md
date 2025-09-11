# Jira Integration Examples

This guide provides practical examples of using Claude Code PM with Jira integration enabled. Each example shows both the command and expected output.

## Table of Contents

- [Initial Setup](#initial-setup)
- [Epic Workflow](#epic-workflow)
- [Issue Management](#issue-management)
- [Search Scenarios](#search-scenarios)
- [Daily Workflows](#daily-workflows)
- [Team Collaboration](#team-collaboration)
- [Troubleshooting](#troubleshooting)

---

## Initial Setup

### Configure Jira Integration

```bash
# Set environment variables
export JIRA_API_TOKEN="your-api-token-here"
export JIRA_USER_EMAIL="john.doe@company.com"
export JIRA_SITE_URL="https://company.atlassian.net"

# Initialize project with Jira
/pm:init
```

**Output:**
```
🚀 Initializing Claude Code PM...
✅ GitHub CLI authenticated
🔧 Configuring Jira integration...
   Site: https://company.atlassian.net
   User: john.doe@company.com
   Testing connection...
✅ Jira connection successful!
   Available projects: PROJ, TEAM, INFRA
   
Enter default project key [PROJ]: PROJ
✅ Configuration saved to claude/settings.local.json

Ready to use PM commands with Jira integration!
```

### Verify Integration

```bash
/pm:search --jira "test connection"
```

**Output:**
```
🔍 Searching Jira...
✅ Connection successful
Found 3 results in PROJ project
```

---

## Epic Workflow

### Create and Sync Epic with Jira

```bash
# Create PRD
/pm:prd-new user-authentication

# Parse to epic
/pm:prd-parse user-authentication

# Decompose with immediate Jira creation
/pm:epic-decompose user-authentication --with-jira
```

**Output:**
```
📋 Decomposing epic: user-authentication
✅ Created 6 task files locally

🎫 Creating Jira tasks...
   Creating PROJ-101: Setup authentication schema
   Creating PROJ-102: Implement JWT service
   Creating PROJ-103: Create login endpoints
   Creating PROJ-104: Add OAuth2 integration
   Creating PROJ-105: Implement session management
   Creating PROJ-106: Add security middleware

✅ Decomposition complete!
   Local tasks: 6 files created
   Jira tasks: 6 stories created
   Epic: PROJ-100 (not yet created)

Next: Run /pm:epic-sync to create epic and GitHub issues
```

### Sync Epic to Both Systems

```bash
/pm:epic-sync user-authentication
```

**Output:**
```
✅ Creating GitHub epic issue...
   Epic: #1234 - User Authentication Implementation

🎫 Creating Jira epic...
   Epic: PROJ-100 - User Authentication Implementation
   Linking to GitHub: #1234

📋 Creating GitHub sub-issues...
   #1235 ↔ PROJ-101: Setup authentication schema
   #1236 ↔ PROJ-102: Implement JWT service
   #1237 ↔ PROJ-103: Create login endpoints
   #1238 ↔ PROJ-104: Add OAuth2 integration
   #1239 ↔ PROJ-105: Implement session management
   #1240 ↔ PROJ-106: Add security middleware

✅ Sync complete!
   GitHub: Epic + 6 issues created
   Jira: Epic + 6 stories linked
   Worktree: ../epic-user-authentication

View in Jira: https://company.atlassian.net/browse/PROJ-100
```

### Check Epic Status Across Systems

```bash
/pm:epic-list --jira-sync
```

**Output:**
```
📚 Syncing with Jira...
✅ Updated 2 epics from Jira

📁 user-authentication
   Status: in-progress (Jira: In Progress ✅)
   Progress: 33% → 50% (3/6 tasks)
   GitHub: #1234 | Jira: PROJ-100
   Assignee: john.doe@company.com
   Sprint: Sprint 23
   
📁 payment-integration  
   Status: planning (Jira: To Do ✅)
   Progress: 0% (0/4 tasks)
   GitHub: #1250 | Jira: PROJ-110
   Assignee: Unassigned
   Target: v2.1.0
```

---

## Issue Management

### Start Work with Jira Update

```bash
/pm:issue-start 1235
```

**Output:**
```
🚀 Starting work on issue #1235
🔄 Mode: Jira
📋 Checking GitHub issue...
   Issue: Setup authentication schema
🔄 Delegating to Jira implementation...
🔍 Found Jira issue: PROJ-101
📊 Updating Jira issue status...
   Current: To Do → In Progress
✅ Jira status updated successfully
🌱 Creating Jira-formatted branch...
✅ Branch created: PROJ-101-setup-authentication-schema

✅ Jira issue start completed successfully!

Epic: user-authentication
Task file: .claude/epics/user-authentication/1235.md
Analysis: .claude/epics/user-authentication/1235-analysis.md

Next steps:
  Monitor with: /pm:epic-status user-authentication
  Sync updates: /pm:issue-sync 1235
```

### Sync Progress to Both Systems

```bash
/pm:issue-sync 1235
```

**Output:**
```
☁️ Syncing updates to GitHub Issue #1235 and Jira PROJ-101

📝 Gathering local updates...
   Progress: 75%
   Completed: Database schema, migration scripts
   In Progress: Model implementation
   
📤 Posting to GitHub...
✅ GitHub comment posted

🔄 Updating Jira...
   Adding comment with progress
   Updating story points: 3 → 2 (remaining)
   Custom field 'Progress': 75%
✅ Jira updated successfully

📊 Sync complete:
   GitHub: Comment #3 added
   Jira: Progress updated, comment added
   Systems in sync: ✅
```

### Close Issue with Resolution

```bash
/pm:issue-close 1235 Fixed --create-pr
```

**Output:**
```
🎯 Closing issue #1235 with resolution: Fixed
🔄 Mode: Jira

📝 Creating pull request...
✅ PR created: #145 - PROJ-101: Setup authentication schema

🔄 Updating Jira...
   Transitioning: In Progress → Done
   Setting resolution: Done
   Adding completion comment
✅ Jira issue closed successfully

🔒 Closing GitHub issue...
✅ GitHub issue closed with PR reference

✅ Issue closure complete!
   GitHub: #1235 closed
   Jira: PROJ-101 resolved
   PR: #145 ready for review
```

---

## Search Scenarios

### Natural Language Search

```bash
/pm:search "my tasks in current sprint"
```

**Output:**
```
🔍 Searching locally and in Jira...

📊 Results (8 total):

Source  ID        Title                          Status       Sprint
------  --------  -----------------------------  -----------  ----------
Jira    PROJ-101  Setup authentication schema    In Progress  Sprint 23
Jira    PROJ-102  Implement JWT service         To Do        Sprint 23
Local   #1237     Create login endpoints        open         -
Jira    PROJ-105  Implement session management  In Review    Sprint 23

Showing 4 of 8 results. Use --limit to see more.
```

### JQL Search

```bash
/pm:search --jql "project = PROJ AND fixVersion = 'v2.0' AND status != Done"
```

**Output:**
```
🔍 Executing JQL query...

ID        Type   Title                      Assignee    Priority  Status
--------  -----  -------------------------  ----------  --------  -----------
PROJ-101  Story  Setup authentication       john.doe    High      In Progress
PROJ-102  Story  Implement JWT service      jane.smith  High      To Do
PROJ-110  Bug    Fix login timeout         unassigned  Medium    Open
PROJ-115  Task   Update security docs       mike.chen   Low       In Progress

4 issues found
```

### Saved Search for Daily Standup

```bash
# Save a search
/pm:search --save-as "my-standup" "assignee = me AND updated >= -1d"

# Use it daily
/pm:search --saved my-standup
```

**Output:**
```
📎 Running saved search: my-standup

Yesterday's Activity:
- PROJ-101: Added 3 comments, moved to In Progress
- PROJ-103: Updated description, added acceptance criteria
- #1238: Synced progress (50% complete)

3 items updated in the last 24 hours
```

---

## Daily Workflows

### Morning Standup

```bash
/pm:standup
```

**Output:**
```
📅 Daily Standup Report - 2024-01-15

👤 Your Activity:

Yesterday:
  ✅ Completed:
    - PROJ-101: Setup authentication schema (Done)
    - #1236: Code review feedback addressed
    
  🔄 Progressed:
    - PROJ-102: JWT service implementation (75%)
    - Started OAuth2 integration research

Today's Plan:
  🎯 Priority:
    - Complete PROJ-102: JWT service
    - Start PROJ-103: Login endpoints
    
  📋 Backlog:
    - Review PR #145
    - Update authentication docs

Blockers:
  ⚠️ PROJ-102: Waiting on security team approval for JWT library

Team Velocity: 12 points completed this sprint (target: 15)
```

### Check Next Priority

```bash
/pm:next
```

**Output:**
```
🎯 Next Priority Task:

📋 PROJ-103: Create login endpoints
   Epic: User Authentication (PROJ-100)
   GitHub: #1237
   Status: To Do → Ready to Start
   
Why this task?
  ✅ Unblocked (PROJ-101 completed)
  ✅ High priority in current sprint
  ✅ You have capacity (1 task in progress)
  ✅ Required for sprint goal

Dependencies satisfied:
  - PROJ-101: Authentication schema ✅
  - PROJ-102: JWT service (in progress, but not blocking)

Start with: /pm:issue-start 1237
```

---

## Team Collaboration

### Share Epic Status

```bash
/pm:epic-status user-authentication
```

**Output:**
```
📊 Epic Status: User Authentication

Progress: ████████░░░░░░░ 55% (3.3/6 tasks)

Completed (2):
  ✅ PROJ-101: Setup authentication schema (john.doe)
  ✅ PROJ-104: OAuth2 integration (jane.smith)

In Progress (2):
  🔄 PROJ-102: JWT service - 75% (john.doe)
  🔄 PROJ-105: Session management - 30% (mike.chen)

Blocked (1):
  ⚠️ PROJ-103: Login endpoints - Waiting on API design approval

To Do (1):
  ⏸️ PROJ-106: Security middleware

Velocity: 8 points completed, 12 points remaining
Sprint ends in: 4 days

GitHub: https://github.com/company/project/issues/1234
Jira: https://company.atlassian.net/browse/PROJ-100
```

### Cross-Reference Issues

```bash
# Find all authentication-related work across teams
/pm:search "authentication" --format markdown
```

**Output:**
```markdown
## Search Results: authentication

### Your Team (PROJ)
- **PROJ-100**: User Authentication Epic (In Progress)
- **PROJ-101**: Setup authentication schema (Done)
- **PROJ-102**: Implement JWT service (In Progress)

### Platform Team (PLAT)
- **PLAT-89**: SSO Integration (In Progress)
- **PLAT-90**: Authentication Microservice (Planning)

### Mobile Team (MOB)
- **MOB-234**: iOS Authentication Flow (To Do)
- **MOB-235**: Android Biometric Support (In Progress)

### Related Documentation
- `docs/authentication-api.md` - Updated 2 days ago
- `specs/oauth2-integration.md` - Updated 1 week ago
```

---

## Troubleshooting

### Debug Jira Connection

```bash
# Check configuration
cat claude/settings.local.json | grep -A10 jira

# Test connection
/pm:search --jira "test" --limit 1
```

### Fix Status Mismatch

```bash
# When GitHub and Jira are out of sync
/pm:epic-refresh user-authentication
```

**Output:**
```
🔄 Refreshing epic: user-authentication

⚠️ Status mismatches found:
  - #1235 (closed) ↔ PROJ-101 (In Progress)
  - #1237 (open) ↔ PROJ-103 (Done)

Fix mismatches? (yes/no): yes

✅ Syncing status...
  - PROJ-101 → Done (matching GitHub)
  - GitHub #1237 → closed (matching Jira)
  
✅ Epic refreshed successfully
  Progress: 55% → 67% (4/6 tasks)
```

### Recover from Partial Sync

```bash
# If sync was interrupted
/pm:validate
```

**Output:**
```
🔍 Validating system integrity...

⚠️ Issues found:
  1. Task 1236.md missing Jira link
  2. Jira PROJ-102 not linked to GitHub
  3. Epic progress mismatch (calculated: 50%, stored: 33%)

Fixes available:
  1. Run: /pm:issue-sync 1236 --force
  2. Manual fix required - check PROJ-102 in Jira
  3. Run: /pm:epic-refresh user-authentication

3 issues found, 2 can be auto-fixed
```

---

## Advanced Scenarios

### Sprint Planning

```bash
# Find unestimated stories
/pm:search --jql "project = PROJ AND 'Story Points' is EMPTY AND type = Story"

# Get sprint velocity
/pm:search --jql "project = PROJ AND sprint = 'Sprint 23' AND status = Done" --format json | jq '.results | map(.story_points) | add'
```

### Bulk Operations

```bash
# Close multiple issues after release
for issue in 1235 1236 1237; do
  /pm:issue-close $issue Fixed
done

# Sync all in-progress work
/pm:search "status = 'In Progress' AND assignee = me" | while read id _; do
  /pm:issue-sync ${id#PROJ-}
done
```

### Custom Reports

```bash
# Generate weekly report
/pm:search --jql "updated >= -7d AND assignee in (currentUser())" --format csv > weekly-report.csv

# Track epic progress over time
for epic in $(pm:epic-list | grep "📁" | awk '{print $2}'); do
  echo -n "$epic: "
  /pm:epic-show $epic | grep "Progress:"
done
```

---

## Best Practices

1. **Always sync after major changes** - Keep both systems aligned
2. **Use saved searches** - Consistency in reporting
3. **Set up webhooks** - Real-time sync (advanced)
4. **Regular validation** - Run `/pm:validate` weekly
5. **Clear commit messages** - Include Jira keys for automatic linking

---

## Configuration Reference

### Minimal Configuration
```json
{
  "jira": {
    "enabled": true,
    "project_key": "PROJ"
  }
}
```

### Full Configuration
```json
{
  "jira": {
    "enabled": true,
    "project_key": "PROJ",
    "epic_issue_type": "Epic",
    "task_issue_type": "Story",
    "default_priority": "Medium",
    "default_components": ["Backend"],
    "custom_fields": {
      "github_url": "customfield_10100",
      "story_points": "customfield_10001",
      "acceptance_criteria": "customfield_10002",
      "progress_percentage": "customfield_10003"
    },
    "transitions": {
      "start": "Start Progress",
      "done": "Done",
      "wont_do": "Won't Do",
      "review": "In Review"
    },
    "search": {
      "default_jql": "project = PROJ ORDER BY priority DESC",
      "max_results": 50,
      "include_subtasks": false
    }
  }
}
```

---

This guide covers common Jira integration scenarios. For more specific use cases, consult the command reference or run individual command help (e.g., `/pm:help issue-sync`).