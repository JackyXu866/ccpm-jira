# Frequently Asked Questions (FAQ)

This document answers common questions about Claude Code PM and its Jira integration.

## Table of Contents

- [General Questions](#general-questions)
- [Setup & Configuration](#setup--configuration)
- [Jira Integration](#jira-integration)
- [Workflow Questions](#workflow-questions)
- [Troubleshooting](#troubleshooting)
- [Advanced Usage](#advanced-usage)
- [Team Collaboration](#team-collaboration)
- [Performance & Limits](#performance--limits)

## General Questions

### Q: What is Claude Code PM?

**A:** Claude Code PM is a project management system designed specifically for AI-assisted development. It helps you:
- Transform ideas into structured specifications (PRDs)
- Break down work into manageable tasks
- Coordinate multiple AI agents working in parallel
- Track progress in GitHub and Jira
- Maintain context across development sessions

### Q: Do I need Jira to use Claude Code PM?

**A:** No! Jira integration is completely optional. Claude Code PM works great with just GitHub Issues. Jira integration adds:
- Enterprise project management features
- Sprint planning capabilities
- Better cross-team visibility
- Advanced reporting

### Q: How does this differ from regular project management tools?

**A:** Claude Code PM is designed for AI-first development:
- **Context preservation**: Never lose state between AI sessions
- **Parallel execution**: Multiple agents work simultaneously
- **Specification-driven**: Every line of code traces to requirements
- **Git-native**: Uses worktrees for conflict-free parallel work

### Q: Can I use this with other AI assistants?

**A:** While optimized for Claude, the system works with any AI that can:
- Read and write files
- Execute shell commands
- Understand markdown specifications
- Follow structured instructions

## Setup & Configuration

### Q: How do I install Claude Code PM?

**A:** Quick install:
```bash
cd your-project/
curl -sSL https://raw.githubusercontent.com/automazeio/ccpm/main/ccpm.sh | bash
/pm:init
```

### Q: Where should I store my Jira API token?

**A:** Never commit tokens! Options:
1. **Environment variables** (recommended):
   ```bash
   export JIRA_API_TOKEN="your-token"
   ```
2. **Password manager integration**
3. **Secure credential store**
4. **.env file** (add to .gitignore!)

### Q: Can I use this in an existing project?

**A:** Yes! Claude Code PM is designed to integrate into existing projects:
1. Install in your project root
2. Run `/pm:import` to import existing GitHub issues
3. Start creating new epics with `/pm:prd-new`

### Q: How do I configure custom Jira fields?

**A:** Edit `claude/settings.local.json`:
```json
{
  "jira": {
    "custom_fields": {
      "story_points": "customfield_10001",
      "epic_link": "customfield_10002"
    }
  }
}
```

Find field IDs using:
```bash
/pm:search --jql "key = PROJ-1" --format json | jq '.results[0]'
```

## Jira Integration

### Q: Why does search sometimes show duplicates?

**A:** This happens when an issue exists in both systems. The search command deduplicates based on:
- Title similarity
- Cross-references in descriptions
- Linked issue IDs

To see all results: `/pm:search "query" --no-dedup`

### Q: How do I map Jira statuses to GitHub?

**A:** Configure status mapping in settings:
```json
{
  "jira": {
    "status_mapping": {
      "github_to_jira": {
        "open": "To Do",
        "in_progress": "In Progress",
        "closed": "Done"
      },
      "jira_to_github": {
        "To Do": "open",
        "In Progress": "open",
        "Done": "closed",
        "Won't Do": "closed"
      }
    }
  }
}
```

### Q: Can I use different Jira projects?

**A:** Yes! Methods:
1. **Default project**:
   ```bash
   export JIRA_PROJECT_KEY="PROJ"
   ```
2. **Per-epic override**:
   ```yaml
   # In epic.md frontmatter
   jira_project: "DIFFERENT"
   ```
3. **Command override**:
   ```bash
   /pm:epic-sync feature --project OTHER
   ```

### Q: What Jira permissions do I need?

**A:** Minimum permissions:
- Browse projects
- Create issues
- Edit issues
- Add comments
- Transition issues

For full features:
- Manage sprints
- Edit custom fields
- Create epics

## Workflow Questions

### Q: Should I create tasks in Jira or GitHub first?

**A:** Use Claude Code PM commands:
```bash
# Best approach - creates in both
/pm:epic-oneshot feature

# Not recommended
# Creating manually in either system
```

This ensures proper linking and consistency.

### Q: How do I handle tasks that span multiple epics?

**A:** Options:
1. **Create a cross-cutting epic**:
   ```bash
   /pm:prd-new infrastructure-upgrade
   # Reference multiple epics in the PRD
   ```

2. **Use labels**:
   ```yaml
   labels: ["cross-team", "infrastructure"]
   ```

3. **Link issues**:
   ```bash
   /pm:issue-link 123 456
   ```

### Q: Can multiple people work on the same epic?

**A:** Yes! Best practices:
1. **Use parallel tasks**:
   ```yaml
   parallel: true
   ```
2. **Assign different files**:
   ```yaml
   assignee: "@developer1"
   files: ["src/api/*"]
   ```
3. **Coordinate through commits**:
   ```bash
   git commit -m "API: Add user endpoint"
   ```

### Q: How often should I sync?

**A:** Recommended sync points:
- After completing a module/component
- Before switching tasks
- End of each work session
- Before requesting review
- After addressing feedback

## Troubleshooting

### Q: "Command not found: /pm:*"

**A:** Ensure you:
1. Ran the installation script
2. Are in a project with `.claude/` directory
3. Have sourced the commands:
   ```bash
   /init include rules
   ```

### Q: "Jira API rate limit exceeded"

**A:** Solutions:
1. Wait 60 seconds (rate limit window)
2. Reduce search result limits:
   ```bash
   /pm:search "query" --limit 10
   ```
3. Use cached results:
   ```bash
   /pm:epic-show feature --cached
   ```

### Q: "Cannot create worktree"

**A:** Common causes:
1. **Uncommitted changes**: Commit or stash first
2. **Existing worktree**: Remove with:
   ```bash
   git worktree remove ../epic-feature
   ```
3. **Permission issues**: Check directory permissions

### Q: Sync shows "conflicts detected"

**A:** Resolution steps:
1. Check both systems:
   ```bash
   /pm:issue-show 123 --compare
   ```
2. Choose source of truth:
   ```bash
   /pm:issue-sync 123 --force-github
   # or
   /pm:issue-sync 123 --force-jira
   ```
3. Validate after:
   ```bash
   /pm:validate
   ```

## Advanced Usage

### Q: Can I customize agent behavior?

**A:** Yes! Create custom agents:
```bash
# .claude/agents/backend-specialist.md
You are a backend specialist focusing on:
- API design
- Database optimization
- Security best practices

When given a task, analyze it from a backend perspective...
```

### Q: How do I automate daily tasks?

**A:** Create scripts in `.claude/scripts/`:
```bash
#!/bin/bash
# .claude/scripts/daily.sh
/pm:standup
/pm:blocked
/pm:validate --fix
```

Add to cron:
```bash
0 9 * * * cd /project && .claude/scripts/daily.sh
```

### Q: Can I integrate with CI/CD?

**A:** Yes! Examples:
```yaml
# .github/workflows/pm-sync.yml
on:
  issues:
    types: [opened, closed, reopened]
jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: |
          /pm:import
          /pm:validate
```

### Q: How do I migrate from another system?

**A:** Migration strategies:
1. **Gradual migration**:
   ```bash
   # Import existing issues
   /pm:import --all
   # New work uses Claude Code PM
   ```

2. **Big bang**:
   ```bash
   # Export from old system
   # Transform to PRDs
   # Bulk create
   ```

## Team Collaboration

### Q: How do we coordinate across time zones?

**A:** Async-friendly features:
1. **Detailed sync messages**:
   ```bash
   /pm:issue-sync 123 --message "Completed API, blocked on auth service"
   ```
2. **Status dashboards**:
   ```bash
   /pm:status --export markdown > daily-status.md
   ```
3. **Async reviews**:
   ```bash
   /pm:issue-close 123 --create-pr --assign @reviewer
   ```

### Q: Can we use this with external contractors?

**A:** Yes! Security considerations:
1. Use separate GitHub repo permissions
2. Limit Jira project access
3. Create contractor-specific epics
4. Use filtered views:
   ```bash
   /pm:search "labels = contractor-visible"
   ```

### Q: How do we handle code reviews?

**A:** Integrated review workflow:
1. **Developer completes work**:
   ```bash
   /pm:issue-close 123 --create-pr
   ```
2. **Reviewer checks context**:
   ```bash
   /pm:issue-show 123
   ```
3. **Feedback tracked**:
   - PR comments for code
   - Issue comments for requirements

## Performance & Limits

### Q: How many parallel agents can I run?

**A:** Practical limits:
- **CPU**: 1 agent per 2 cores recommended
- **Memory**: 4GB RAM per agent (with full context)
- **Git**: 10-15 parallel worktrees works well
- **API**: Respect rate limits (see docs/api-limits.md)

### Q: How large can epics be?

**A:** Guidelines:
- **Tasks per epic**: 5-20 optimal, 50 maximum
- **File size**: Keep task files under 10KB
- **Total epic size**: Under 1MB for performance

### Q: What about large codebases?

**A:** Optimization strategies:
1. **Selective context**:
   ```bash
   /context:create --filter "src/module/*"
   ```
2. **Modular epics**: Break large features into multiple epics
3. **Sparse checkouts**: For massive repos
4. **Incremental sync**: Sync only changed issues

### Q: API rate limits?

**A:** Limits and mitigation:
- **GitHub**: 5000/hour (authenticated)
- **Jira Cloud**: 50,000/hour (varies by plan)
- **Mitigation**:
  - Batch operations
  - Cache results
  - Use webhooks for real-time sync

---

## Still Have Questions?

1. **Check documentation**:
   - [Getting Started](getting-started-jira.md)
   - [Command Reference](commands-reference.md)
   - [Troubleshooting Guide](troubleshooting.md)

2. **Get help**:
   - Run `/pm:help [command]`
   - Check GitHub Issues
   - Ask in discussions

3. **Report issues**:
   - Include output of `/pm:validate`
   - Share relevant logs
   - Provide reproduction steps

Remember: Most "issues" are configuration mismatches. Run `/pm:validate` first!