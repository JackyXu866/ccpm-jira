# Claude Code PM Workflows & Best Practices

This guide presents battle-tested workflows for maximizing productivity with Claude Code PM and Jira integration. Learn from real-world patterns that help teams ship faster and better.

## Table of Contents

1. [Core Workflow Principles](#core-workflow-principles)
2. [Solo Developer Workflows](#solo-developer-workflows)
3. [Team Collaboration Workflows](#team-collaboration-workflows)
4. [Sprint-Based Development](#sprint-based-development)
5. [Advanced Parallel Development](#advanced-parallel-development)
6. [Integration Patterns](#integration-patterns)
7. [Automation Recipes](#automation-recipes)
8. [Best Practices](#best-practices)
9. [Anti-Patterns to Avoid](#anti-patterns-to-avoid)

## Core Workflow Principles

### 1. Specification-Driven Development

**Principle**: Every line of code traces back to a specification.

```bash
# ❌ Bad: Jump straight to coding
/pm:issue-start 123

# ✅ Good: Full specification flow
/pm:prd-new feature
/pm:prd-parse feature
/pm:epic-decompose feature
/pm:epic-sync feature
/pm:issue-start 123
```

### 2. Context Preservation

**Principle**: Never lose project state between sessions.

```bash
# Start of session
/context:prime
/pm:status

# Before context switch
/pm:issue-sync 123

# Return to work
/context:prime
/pm:epic-show current-epic
```

### 3. Incremental Synchronization

**Principle**: Sync early, sync often, but intentionally.

```bash
# ❌ Bad: Work for days without syncing
# ✅ Good: Sync at logical checkpoints
/pm:issue-sync 123  # After completing a module
/pm:issue-sync 123  # Before switching tasks
/pm:issue-sync 123  # End of day
```

## Solo Developer Workflows

### Morning Routine

Start your day with context and priorities:

```bash
# 1. Check overall status
/pm:standup

# 2. Review blocked items
/pm:blocked

# 3. Get your next task
/pm:next

# 4. Load context and begin
/context:prime
/pm:issue-start {suggested-issue}
```

### Feature Development Flow

Complete workflow for building a feature:

```bash
# 1. Brainstorm thoroughly
/pm:prd-new payment-integration
# Be detailed about:
# - User stories
# - Success criteria  
# - Technical constraints
# - Security requirements

# 2. Create technical plan
/pm:prd-parse payment-integration
# Review and refine the epic

# 3. Break down and sync
/pm:epic-oneshot payment-integration
# Creates: Epic + tasks in both systems

# 4. Systematic execution
while task=$(pm:next); do
  /pm:issue-start $task
  # Implement...
  /pm:issue-sync $task
  /pm:issue-close $task --create-pr
done
```

### Quick Fix Workflow

For urgent bugs or small changes:

```bash
# 1. Create minimal task
echo "Fix: Login timeout issue" > .claude/epics/hotfix/001.md

# 2. Sync to both systems
/pm:epic-sync hotfix

# 3. Fast execution
/pm:issue-start {issue-number}
# Fix the bug
/pm:issue-close {issue-number} Fixed --create-pr
```

## Team Collaboration Workflows

### Distributed Team Coordination

Multiple developers working on the same epic:

```bash
# Team Lead: Set up epic
/pm:prd-new api-v2
/pm:prd-parse api-v2
/pm:epic-decompose api-v2

# Mark parallel tasks
# Edit .claude/epics/api-v2/*.md
# Set: parallel: true

# Sync with assignments
/pm:epic-sync api-v2

# Each developer
/pm:search "assignee = me AND status = 'To Do'"
/pm:issue-start {their-task}
```

### Code Review Integration

Integrate PR reviews with issue tracking:

```bash
# Developer: Submit work
/pm:issue-close 123 --create-pr

# Reviewer: Check context
/pm:issue-show 123
# Review PR with full context

# If changes needed
/pm:issue-reopen 123
# Comment: "See PR feedback"

# Developer: Address feedback
/pm:issue-sync 123
# Update: "Addressed review comments"
/pm:issue-close 123
```

### Cross-Team Dependencies

Managing work that spans teams:

```bash
# 1. Identify dependencies
/pm:search "project in (TEAM1, TEAM2) AND labels = 'dependency'"

# 2. Create linking epic
/pm:prd-new cross-team-integration

# 3. Reference dependencies
# In epic.md:
depends_on:
  - "TEAM1-123"  # Auth service
  - "TEAM2-456"  # Data pipeline

# 4. Monitor progress
/pm:search --jql "issue in linkedIssues('PROJ-100')"
```

## Sprint-Based Development

### Sprint Planning

Prepare for sprint planning meeting:

```bash
# 1. Review backlog
/pm:search --jql "project = PROJ AND status = 'To Do' ORDER BY priority"

# 2. Check velocity
last_sprint=$(jira sprint list --state closed | head -1)
/pm:search --jql "sprint = '$last_sprint' AND status = Done"

# 3. Identify sprint candidates
/pm:search --jql "'Story Points' is not EMPTY AND status = 'To Do'"

# 4. Create sprint epic
/pm:prd-new sprint-24
# Include selected stories
```

### Mid-Sprint Check-In

Track sprint progress:

```bash
# Daily standup
/pm:standup

# Sprint burndown
/pm:search --jql "sprint in openSprints() AND assignee = currentUser()" \
  --format json | jq '.results | group_by(.status) | map({status: .[0].status, count: length})'

# Identify risks
/pm:blocked
/pm:search "due < 2d AND status != Done"
```

### Sprint Retrospective

Gather data for retrospective:

```bash
# Completed work
/pm:search --jql "sprint = 'Sprint 23' AND status = Done"

# Velocity analysis
/pm:epic-status all --sprint 23

# Process improvements
/pm:search "labels = 'tech-debt' AND created >= -14d"
```

## Advanced Parallel Development

### Multi-Agent Orchestration

Run multiple AI agents on one issue:

```bash
# 1. Analyze issue complexity
/pm:issue-show 1234

# 2. Create parallel work streams
cd ../epic-feature
mkdir -p streams/{backend,frontend,tests,docs}

# 3. Launch specialized agents
# Terminal 1: Backend
/agent:backend --task "Implement API from 1234.md"

# Terminal 2: Frontend  
/agent:frontend --task "Create UI from 1234.md"

# Terminal 3: Tests
/agent:test --task "Write tests for 1234.md"

# 4. Coordinate through commits
git add -A && git commit -m "Backend: Add user service"
git add -A && git commit -m "Frontend: Add user form"
git add -A && git commit -m "Tests: Add user service tests"

# 5. Merge work
/pm:issue-sync 1234
```

### Swarm Development

Multiple agents on multiple issues:

```bash
# 1. Prepare epic for swarm
/pm:epic-show payment-integration
# Ensure all tasks have parallel: true

# 2. Launch the swarm
for issue in $(pm:epic-show payment-integration | grep "^#" | cut -d' ' -f1); do
  tmux new-window -n "issue-$issue" "/pm:issue-start $issue"
done

# 3. Monitor progress
watch -n 30 '/pm:epic-status payment-integration'

# 4. Coordinate merges
/pm:epic-status payment-integration --format json | \
  jq '.tasks[] | select(.status == "ready-to-merge")'
```

## Integration Patterns

### GitHub-Jira Sync Patterns

**Pattern 1: GitHub-First**
```bash
# Work primarily in GitHub
gh issue create --title "Feature"
/pm:import
/pm:issue-sync {number}
```

**Pattern 2: Jira-First**
```bash
# Create in Jira UI
# Then import
/pm:search --jql "created >= -1h"
/pm:import --jira PROJ-123
```

**Pattern 3: Dual Creation**
```bash
# Our recommended approach
/pm:epic-oneshot feature
# Creates in both simultaneously
```

### Custom Field Mapping

Sync custom Jira fields:

```json
// claude/settings.local.json
{
  "jira": {
    "custom_fields": {
      "acceptance_criteria": "customfield_10001",
      "story_points": "customfield_10002",
      "qa_notes": "customfield_10003"
    }
  }
}
```

Usage:
```bash
# In task file
---
story_points: 5
acceptance_criteria: |
  - User can login
  - Session persists
qa_notes: "Test with SSO enabled"
---

/pm:issue-sync 123
```

### Webhook Integration

Auto-sync with webhooks:

```bash
# 1. Set up GitHub webhook
gh webhook create \
  --repo owner/repo \
  --url https://your-sync-service.com \
  --event issues

# 2. Set up Jira webhook
# In Jira: Settings → Webhooks → Create

# 3. Sync service updates both
```

## Automation Recipes

### Daily Automation

```bash
#!/bin/bash
# daily-sync.sh

# 1. Update all in-progress work
for issue in $(pm:in-progress | awk '{print $1}'); do
  /pm:issue-sync $issue
done

# 2. Check for Jira updates
/pm:search --jql "updated >= -1d" --sync-back

# 3. Generate standup
/pm:standup > standup-$(date +%Y%m%d).md

# 4. Validate system
/pm:validate --fix
```

### Sprint Automation

```bash
#!/bin/bash
# sprint-setup.sh

sprint_name="Sprint $1"
sprint_goal="$2"

# 1. Create sprint epic
cat > .claude/prds/sprint-$1.md << EOF
# $sprint_name
Goal: $sprint_goal

## Stories
$(pm:search --jql "sprint = '$sprint_name'" --format markdown)
EOF

# 2. Parse and sync
/pm:prd-parse sprint-$1
/pm:epic-sync sprint-$1

# 3. Assign work
/pm:search --jql "sprint = '$sprint_name'" | while read issue; do
  /pm:issue-start $issue --assign
done
```

### Release Automation

```bash
#!/bin/bash
# release.sh

version=$1

# 1. Find completed work
/pm:search --jql "fixVersion = '$version' AND status = Done" > release-notes.md

# 2. Close related tasks
for epic in $(pm:epic-list | grep -A1 "version: $version" | grep "📁" | awk '{print $2}'); do
  /pm:epic-close $epic
done

# 3. Update documentation
/pm:search "type = Documentation AND fixVersion = '$version'" | while read doc; do
  /pm:issue-sync $doc --tag "Released in $version"
done
```

## Best Practices

### 1. Specification Quality

**Do:**
- Write PRDs as if the implementer knows nothing
- Include acceptance criteria for every task
- Document non-functional requirements
- Add security and performance constraints

**Don't:**
- Leave requirements vague
- Skip the PRD phase
- Assume context will be remembered

### 2. Commit Hygiene

**Do:**
```bash
# Include issue references
git commit -m "PROJ-101: Add user authentication

- Implement JWT tokens
- Add refresh mechanism  
- Include rate limiting"

# Atomic commits
git add auth/jwt.js && git commit -m "PROJ-101: Add JWT service"
git add auth/refresh.js && git commit -m "PROJ-101: Add token refresh"
```

**Don't:**
```bash
# Vague commits
git commit -m "updates"

# Monster commits
git add -A && git commit -m "finish feature"
```

### 3. Context Management

**Do:**
```bash
# Regular context updates
/context:update  # After major changes
/context:prime   # Before starting work

# Document decisions
echo "Chose PostgreSQL for transaction support" >> .claude/context/decisions.md
```

**Don't:**
- Work across multiple epics without context switches
- Lose track of why decisions were made
- Skip context priming after breaks

### 4. Progress Tracking

**Do:**
```bash
# Granular updates
/pm:issue-sync 123
# "Completed: API endpoint (2h)
#  In Progress: Frontend integration
#  Next: Add tests"

# Time tracking
/pm:issue-sync 123 --time-spent 2h --time-remaining 4h
```

**Don't:**
- Work for days without updates
- Use vague status messages
- Forget to update time estimates

### 5. Parallel Work

**Do:**
```bash
# Clear task boundaries
Task 1: Database schema only
Task 2: API endpoints only
Task 3: UI components only

# Explicit interfaces
Create shared/interfaces.ts first
```

**Don't:**
- Have overlapping file modifications
- Create circular dependencies
- Skip coordination commits

## Anti-Patterns to Avoid

### 1. The Context Crusher

❌ **Problem**: Loading entire codebase into context
```bash
/read **/*.js  # Don't do this!
```

✅ **Solution**: Focused context loading
```bash
/context:prime
/read auth/*.js  # Just what you need
```

### 2. The Silent Worker

❌ **Problem**: Working without updates
```bash
/pm:issue-start 123
# ... 3 days later ...
/pm:issue-close 123
```

✅ **Solution**: Regular synchronization
```bash
/pm:issue-start 123
# After each module
/pm:issue-sync 123
# End of day
/pm:issue-sync 123
```

### 3. The Scope Creeper

❌ **Problem**: Adding features during implementation
```bash
# Task: Add login
# Actual: Add login, SSO, 2FA, social auth...
```

✅ **Solution**: Stick to specifications
```bash
# See extra need?
/pm:issue-sync 123
# "Note: SSO would be valuable, creating follow-up task"
/pm:epic-add-task feature-epic "Add SSO support"
```

### 4. The Solo Hero

❌ **Problem**: Not leveraging parallel agents
```bash
# One agent doing everything sequentially
```

✅ **Solution**: Orchestrate multiple agents
```bash
# Agent 1: Backend
# Agent 2: Frontend  
# Agent 3: Tests
# All working simultaneously
```

### 5. The Manual Syncer

❌ **Problem**: Updating Jira and GitHub separately
```bash
gh issue comment 123 "Done"
# Then manually update Jira
```

✅ **Solution**: Use integrated commands
```bash
/pm:issue-sync 123
# Updates both automatically
```

## Conclusion

These workflows represent patterns that have proven successful across many teams. The key is to:

1. **Start with clear specifications** - PRDs drive everything
2. **Maintain context religiously** - Never lose state
3. **Sync incrementally** - Little and often
4. **Leverage parallelism** - Multiple agents multiply velocity
5. **Automate repetitive tasks** - Scripts save time

Remember: The best workflow is one your team actually follows. Start with basics, then gradually adopt advanced patterns as your team grows comfortable with the system.

For specific scenarios not covered here, see:
- [Jira Examples](jira-examples.md) - Detailed command examples
- [Troubleshooting](troubleshooting.md) - When things go wrong
- [Technical Guide](technical-guide.md) - Deep implementation details