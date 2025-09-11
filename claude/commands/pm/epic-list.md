---
allowed-tools: Bash
---

# Epic List

Display a list of all epics in the project with their status and progress. Supports integration with Jira for enhanced epic tracking.

## Usage
```
/pm:epic-list [--jira-sync]
```

## Arguments
- `--jira-sync`: Fetch and update epic status from Jira (when Jira mode is enabled)

## Mode Detection
The command automatically detects whether Jira integration is enabled:
- **Jira Mode**: When `claude/settings.local.json` exists with `jira.enabled: true`
- **GitHub Mode**: Default mode when Jira is not configured

## Output Format

### GitHub Mode
Shows local epic information:
```
📚 Epics:

📁 memory-system
   Status: in-progress
   Progress: 45% (4/9 tasks)
   PRD: .claude/prds/memory-system.md
   GitHub: #1234
   Created: 2024-01-15
   
📁 authentication
   Status: planning
   Progress: 0% (0/5 tasks)  
   PRD: .claude/prds/authentication.md
   GitHub: Not synced
   Created: 2024-01-20
```

### Jira Mode
Shows combined GitHub and Jira information:
```
📚 Epics (Jira Integrated):

📁 memory-system
   Status: in-progress (Jira: In Progress)
   Progress: 45% (4/9 tasks)
   PRD: .claude/prds/memory-system.md
   GitHub: #1234 | Jira: PROJ-100
   Created: 2024-01-15
   
📁 authentication
   Status: planning (Jira: To Do)
   Progress: 0% (0/5 tasks)
   PRD: .claude/prds/authentication.md
   GitHub: #1240 | Jira: PROJ-105
   Created: 2024-01-20
```

## Jira Integration Features

When Jira mode is enabled:

1. **Status Sync**: Shows both local and Jira status
   - Highlights mismatches for review
   - Updates local status from Jira if `--jira-sync` is used

2. **Progress Tracking**: Compares progress
   - Local: Based on task file status
   - Jira: Based on story completion
   - Shows discrepancies if they exist

3. **Epic Linking**: Displays connections
   - GitHub epic issue number
   - Jira epic key
   - Direct links to both systems

4. **Metadata Sync**: Additional information
   - Epic owner/assignee
   - Priority level
   - Target version/release
   - Custom field values

## Filtering and Sorting

The command supports various display options:
- Default: All epics sorted by creation date
- Active epics: Only in-progress epics
- By status: Group by planning/in-progress/completed
- By progress: Sort by completion percentage

## Example with Jira Sync

```bash
/pm:epic-list --jira-sync
```

Output:
```
📚 Syncing with Jira...
✅ Updated 3 epics from Jira

📁 memory-system
   Status: in-progress → review (updated from Jira)
   Progress: 45% → 67% (6/9 tasks)
   GitHub: #1234 | Jira: PROJ-100
   Jira Assignee: john.doe@company.com
   Target Release: v2.0.0
   
⚠️  Status mismatch detected:
    Local: in-progress
    Jira: In Review
    → Local status updated to match Jira
```

## Error Handling

Common issues and solutions:

1. **Jira Connection Failed**
   - Falls back to local-only display
   - Shows cached Jira data if available
   - Indicates connection error

2. **Missing Mappings**
   - Epics without Jira links shown normally
   - Suggests running `/pm:epic-sync` for unmapped epics

3. **Permission Errors**
   - Shows accessible epics only
   - Notes which epics couldn't be accessed

## Implementation

Run the epic list script:
```bash
bash ./claude/scripts/pm/epic-list.sh
```

The script will:
1. Scan `.claude/epics/` directory
2. Read epic.md files for metadata
3. Calculate progress from task files
4. Check Jira integration status
5. Fetch Jira data if enabled and requested
6. Format and display the results

## Notes

- Epic list is always based on local files
- Jira data enhances but doesn't replace local tracking
- Use `--jira-sync` sparingly to avoid rate limits
- Progress calculation includes all task types