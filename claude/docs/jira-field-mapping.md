# Jira Field Mapping Guide

This guide explains how CCPM-Jira maps local task fields to Jira fields when creating and updating work items.

## Required Jira Fields

### Epic Creation
When creating an epic in Jira, these fields are set:

| Local Field | Jira Field | Description | Example |
|------------|------------|-------------|---------|
| `name` | Summary | Epic title | "User Authentication System" |
| `description` | Description | Full epic description with objectives | Markdown content |
| `status` | Status | Workflow state | "To Do", "In Progress" |
| `created` | Created Date | Auto-set by Jira | 2024-01-15T10:30:00Z |
| `fix_version` | Fix Version | Target release | "v1.2.0" |
| `epic_name` | Epic Name | Custom field for epic | "auth-system" |
| `progress` | Progress | Calculated from sub-tasks | 25% |

### Task/Story Creation
When creating tasks or stories in Jira:

| Local Field | Jira Field | Description | Example |
|------------|------------|-------------|---------|
| `name` | Summary | Task title | "Implement login endpoint" |
| Full content | Description | Complete task details | Acceptance criteria, approach |
| `status` | Status | Workflow state | "To Do" |
| `assignee` | Assignee | User assignment | "john.doe@company.com" |
| `effort` | Story Points | Size estimate | 3 (from M effort) |
| `estimated_hours` | Original Estimate | Dev hours without AI | 24h |
| `claude_hours` | Remaining Estimate | Hours with Claude Code | 10h |
| `priority` | Priority | Task priority | "High", "Medium", "Low" |
| `components` | Components | System components | ["backend", "security"] |
| `fix_version` | Fix Version | Target release | "v1.2.0" |
| `depends_on` | Issue Links | Blocks/Blocked By | Links to other issues |
| Parent epic | Epic Link | Parent epic reference | PROJ-100 |

## Field Mapping Details

### Effort to Story Points Conversion
```
XS (Extra Small) = 1 point  (2-4 hours)
S  (Small)       = 2 points (4-8 hours)
M  (Medium)      = 3 points (1-3 days)
L  (Large)       = 5 points (3-5 days)
XL (Extra Large) = 8 points (1-2 weeks)
```

### Time Estimation Fields
- **Original Estimate**: Developer time without AI assistance
- **Remaining Estimate**: Time with Claude Code (40-60% of original)
- **Time Spent**: Logged as work progresses

### Priority Calculation
Priority is determined by:
1. Dependencies - Tasks blocking others get higher priority
2. Critical path - Tasks on critical path get "High"
3. Risk level - High-risk tasks get elevated priority
4. Business value - From epic priority

### Component Mapping
Tasks are tagged with components based on content:
- `frontend` - UI components, pages, styling
- `backend` - APIs, services, business logic
- `database` - Schema, migrations, queries
- `security` - Auth, permissions, encryption
- `testing` - Test suites, test infrastructure
- `devops` - CI/CD, deployment, monitoring
- `documentation` - Docs, README, API specs

### Labels Convention
Every task gets these labels:
- `ccpm-task` - Identifies CCPM-managed tasks
- `epic-{name}` - Links to parent epic
- `parallel` or `sequential` - Execution type
- `ai-assisted` - Indicates Claude Code usage
- Additional custom labels from task

## Dependency Management

### Creating Dependencies
Dependencies are created as Jira issue links:
- **Blocks** - This issue blocks another
- **Is Blocked By** - This issue is blocked by another
- **Relates To** - General relationship

### Dependency Rules
1. Circular dependencies are prevented
2. Dependencies must exist before linking
3. Cross-epic dependencies are allowed but flagged

## Custom Fields

If your Jira instance has custom fields, map them in `claude/config/field-mapping.json`:

```json
{
  "custom_fields": {
    "customfield_10016": "story_points",
    "customfield_10017": "epic_link",
    "customfield_10018": "sprint",
    "customfield_10019": "team",
    "customfield_10020": "claude_estimate"
  }
}
```

## Time Tracking with Claude Code

### Estimation Formula
```
Claude Time = Original Time × Reduction Factor

Reduction Factors:
- Boilerplate: 0.2-0.3 (70-80% faster)
- Complex Logic: 0.5-0.6 (40-50% faster)
- Testing: 0.3-0.4 (60-70% faster)
- Documentation: 0.2-0.3 (70-80% faster)
```

### Example Task Breakdown
For a 24-hour task:
```yaml
time_breakdown:
  boilerplate: 40%   # 9.6h → 2.9h with Claude
  logic: 40%         # 9.6h → 5.8h with Claude
  testing: 20%       # 4.8h → 1.9h with Claude
  
original_estimate: 24h
claude_estimate: 10.6h  # 56% reduction
```

## Assignee Management

### Assignment Priority
1. Explicit `assignee` field in task
2. Current user (from MCP connection)
3. Epic default assignee
4. Unassigned (for later triage)

### Getting User Account IDs
Use MCP Atlassian tools:
```bash
# Get current user
mcp__atlassian__atlassianUserInfo

# Search for user
mcp__atlassian__lookupJiraAccountId "john.doe@company.com"
```

## Sprint Assignment

Tasks can be auto-assigned to sprints:
1. Current active sprint (default)
2. Next sprint if current is >80% complete
3. Backlog if no active sprint

## Version Management

Fix versions are inherited from epic unless overridden:
1. Epic fix version applies to all tasks
2. Critical path tasks may target earlier version
3. Optional tasks may target later version

## Best Practices

1. **Always set assignee** - Improves accountability
2. **Use realistic estimates** - Claude reduces time, not complexity
3. **Set dependencies early** - Helps with scheduling
4. **Tag components accurately** - Helps with team allocation
5. **Priority reflects business value** - Not just technical complexity
6. **Update estimates as you learn** - Refine Claude estimates with experience

## Troubleshooting

### Missing Required Fields
If Jira requires fields not in local tasks:
1. Check `claude/config/field-mapping.json`
2. Add defaults for required fields
3. Update epic-decompose template

### Permission Issues
Common permission problems:
- Can't assign users - Need "Assign Issues" permission
- Can't set fix version - Need "Schedule Issues" permission
- Can't link issues - Need "Link Issues" permission

### Field Not Found
If custom fields fail:
1. Verify field IDs with Jira admin
2. Update field-mapping.json
3. Check field context (project-specific fields)