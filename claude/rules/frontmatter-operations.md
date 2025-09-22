# Frontmatter Operations Rule

Standard patterns for working with YAML frontmatter in markdown files.

## Reading Frontmatter

Extract frontmatter from any markdown file:
1. Look for content between `---` markers at start of file
2. Parse as YAML
3. If invalid or missing, use sensible defaults

## Updating Frontmatter

When updating existing files:
1. Preserve all existing fields
2. Only update specified fields
3. Always update `updated` field with current datetime (see `/rules/datetime.md`)

## Task File Format

```yaml
---
name: Implement user authentication
status: open
created: 2024-01-15T10:30:00Z
updated: 2024-01-15T10:30:00Z
jira: PROJ-101
jira_url: https://company.atlassian.net/browse/PROJ-101
epic: PROJ-100
assignee: user@company.com
depends_on: [001]
parallel: false
conflicts_with: []
effort: M
hours: 10
priority: High
components: [backend, security]
---
```

## Epic File Format

```yaml
---
name: user-authentication
status: backlog
created: 2024-01-15T10:30:00Z
updated: 2024-01-15T10:30:00Z
jira: EPIC-123
progress: 0%
---
```

## Field Definitions

### Status Values
- Epics: `backlog`, `in-progress`, `completed`  
- Tasks: `open`, `in-progress`, `done`

### Effort Mapping
- `effort`: XS/S/M/L/XL
- `hours`: Estimated hours WITH Claude Code assistance
  - XS: 2-4 hours
  - S: 4-8 hours
  - M: 8-16 hours
  - L: 16-32 hours
  - XL: 32+ hours

## Jira Key Format
- Pattern: `{PROJECT}-{NUMBER}` (e.g., PROJ-123)
- Always uppercase project key
- No leading zeros

## Important Notes
- Never modify `created` field after initial creation
- Always use real datetime from system
- Update `jira` field only after successful Jira sync
- All tasks must have effort estimation
- All tasks must specify dependencies (even if empty array)
- `hours` field represents time WITH Claude Code assistance (not raw developer time)