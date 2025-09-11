---
allowed-tools: Bash
---

# Search

Unified search across local files and Jira issues using natural language queries or JQL. Intelligently routes queries to the appropriate search backend.

## Usage
```
/pm:search [OPTIONS] <query>
```

## Options
- `--local`: Search only in local files (.claude/)
- `--jira`: Search only in Jira issues
- `--jql`: Force query to be treated as JQL (Jira Query Language)
- `--format <type>`: Output format (table, json, csv, markdown)
- `--limit <n>`: Maximum results to return (default: 25)
- `--no-cache`: Bypass cache for fresh results
- `--save-as <name>`: Save search as a named query
- `--saved <name>`: Run a previously saved search
- `--list-saved`: Show all saved searches
- `--interactive`: Interactive search with result navigation

## Mode Detection

The command automatically determines the best search approach:

1. **Local Mode** (`--local` or no Jira config)
   - Searches in .claude/ directory
   - Uses ripgrep for fast text search
   - Searches epic files, task files, PRDs

2. **Jira Mode** (`--jira` or Jira detected in query)
   - Routes to MCP Jira search
   - Supports natural language queries
   - Automatically converts to JQL when needed

3. **Unified Mode** (default with Jira enabled)
   - Searches both local and Jira
   - Merges and ranks results
   - Shows source indicators

## Query Router Intelligence

The query router automatically detects query intent:

### Jira Indicators
- Contains Jira project keys (PROJ-123)
- Includes Jira fields (assignee, reporter, status)
- Uses Jira operators (AND, OR, NOT)
- Contains Jira-specific terms (sprint, epic link)

### Local Indicators
- File paths or extensions (.md, .yaml)
- Directory references (epics/, prds/)
- Code-specific terms (function, class, TODO)
- Git references (commit, branch)

## Natural Language Examples

### Basic Searches
```bash
# Find all authentication-related items
/pm:search authentication

# Find high-priority bugs
/pm:search "high priority bugs"

# Find work assigned to me
/pm:search "my tasks" 

# Find recently updated items
/pm:search "updated this week"
```

### Advanced Natural Language
```bash
# Complex status queries
/pm:search "open issues in sprint 23 assigned to john"

# Time-based searches
/pm:search "issues created last month still in progress"

# Combined criteria
/pm:search "critical bugs in production reported by customers"
```

## JQL Support

When `--jql` flag is used or JQL syntax is detected:

```bash
# Direct JQL
/pm:search --jql "project = PROJ AND status = 'In Progress'"

# JQL with custom fields
/pm:search --jql "cf[10001] = 'High' AND created >= -7d"

# Complex JQL
/pm:search --jql "assignee = currentUser() AND sprint in openSprints()"
```

## Output Formats

### Table Format (default)
```
ID        Type    Title                           Status      Updated
--------  ------  ------------------------------  ----------  ----------
PROJ-123  Story   Implement user authentication   In Progress 2024-01-15
#45       Task    Add password reset              Open        2024-01-14
epic-001  Epic    Authentication System           Planning    2024-01-10
```

### JSON Format
```json
{
  "results": [
    {
      "id": "PROJ-123",
      "type": "Story",
      "title": "Implement user authentication",
      "status": "In Progress",
      "source": "jira"
    }
  ],
  "total": 15,
  "query": "authentication"
}
```

### Markdown Format
Perfect for documentation:
```markdown
## Search Results: authentication

### Jira Issues (3)
- **PROJ-123**: Implement user authentication (In Progress)
- **PROJ-124**: Setup OAuth2 integration (To Do)

### Local Tasks (2)
- **#45**: Add password reset (Open)
- **#46**: Implement 2FA (Planning)
```

## Saved Searches

Save frequently used queries:

```bash
# Save a search
/pm:search --save-as "my-open-tasks" "assignee = me AND status != Done"

# Run saved search
/pm:search --saved my-open-tasks

# List all saved searches
/pm:search --list-saved
```

Saved searches are stored in `.claude/searches/` with metadata:
- Query string
- Creation date
- Last used date
- Usage count
- Description

## Interactive Mode

Launch interactive search interface:

```bash
/pm:search --interactive "authentication"
```

Features:
- Navigate results with arrow keys
- Preview item details
- Open in browser (Jira) or editor (local)
- Refine search without exiting
- Export selected results

## Caching

Results are cached for performance:
- Cache duration: 15 minutes
- Separate caches for different query types
- Smart invalidation on file changes
- Use `--no-cache` for fresh results

## Examples by Use Case

### Daily Standup
```bash
# What did I work on yesterday?
/pm:search "updated yesterday by me"

# What am I working on today?
/pm:search "status = 'In Progress' AND assignee = me"

# Any blockers?
/pm:search "blocked OR impediment"
```

### Sprint Planning
```bash
# Unestimated stories
/pm:search "type = Story AND 'Story Points' is EMPTY"

# High-priority backlog
/pm:search "status = Backlog AND priority = High"

# Technical debt
/pm:search "label = technical-debt"
```

### Code Review
```bash
# Find related PRs
/pm:search "pull request authentication"

# Implementation tasks
/pm:search --local "implement OR add OR create"

# Test coverage
/pm:search "test" --local
```

## Performance Tips

1. **Use Specific Queries**
   - More specific = faster results
   - Include type, status, or project

2. **Leverage Saved Searches**
   - Pre-validated queries
   - Instant execution
   - Consistent results

3. **Smart Caching**
   - First search primes cache
   - Subsequent searches are instant
   - Clear cache when data changes significantly

## Troubleshooting

### No Results Found
- Check query spelling
- Broaden search terms
- Verify Jira connection
- Check permissions

### Slow Performance
- Use more specific queries
- Enable caching
- Check network connection
- Reduce result limit

### Authentication Issues
- Verify Jira API token
- Check token permissions
- Ensure site URL is correct
- Test with simple query first

## Implementation

```bash
bash ./claude/scripts/pm/search.sh "$@"
```

The script orchestrates:
1. Query parsing and routing
2. Parallel search execution
3. Result merging and ranking
4. Format conversion
5. Cache management