---
allowed-tools: Bash, Read, Write, LS, Task
---

# Task Start

Begin work on a task with parallel agents based on work stream analysis.

## Usage
```
/pm:task-start <task_number> [--analyze]
```

## Prerequisites
- Jira must be configured in `claude/settings.local.json` with `jira.enabled: true`
- MCP Atlassian connection must be active

## Quick Check

1. **Find local task file:**
   - Check if `.claude/epics/*/$ARGUMENTS.md` exists
   - If not found: "❌ No local task for $ARGUMENTS. This task may have been created outside the PM system."

3. **Check for analysis:**
   ```bash
   test -f .claude/epics/*/$ARGUMENTS-analysis.md || echo "❌ No analysis found for task $ARGUMENTS
   
   Run: /pm:task-analyze $ARGUMENTS first
   Or: /pm:task-start $ARGUMENTS --analyze to do both"
   ```
   If no analysis exists and no --analyze flag, stop execution.

## Instructions

### 1. Ensure Worktree Exists

Check if epic worktree exists:
```bash
# Find epic name from task file
epic_name={extracted_from_path}

# Check worktree
if ! git worktree list | grep -q "epic-$epic_name"; then
  echo "❌ No worktree for epic. Run: /pm:epic-start $epic_name"
  exit 1
fi
```

### 2. Read Analysis

Read `.claude/epics/{epic_name}/$ARGUMENTS-analysis.md`:
- Parse parallel streams
- Identify which can start immediately
- Note dependencies between streams

### 3. Create Branch and Update Jira

- Validates Jira configuration (API key, user email, site URL)
- Updates Jira issue status to "In Progress"
- Creates Jira-formatted branch: `PROJ-123-description`
- Handles branch naming conflicts automatically
- Switches to new branch and pushes with upstream tracking

```bash
# The script handles both modes automatically
./claude/scripts/pm/task-start.sh $ARGUMENTS
```

### 4. Setup Progress Tracking

Get current datetime: `date -u +"%Y-%m-%dT%H:%M:%SZ"`

Create workspace structure:
```bash
mkdir -p .claude/epics/{epic_name}/updates/$ARGUMENTS
```

Update task file frontmatter `updated` field with current datetime.

### 5. Launch Parallel Agents

For each stream that can start immediately:

Create `.claude/epics/{epic_name}/updates/$ARGUMENTS/stream-{X}.md`:
```markdown
---
issue: $ARGUMENTS
stream: {stream_name}
agent: {agent_type}
started: {current_datetime}
status: in_progress
---

# Stream {X}: {stream_name}

## Scope
{stream_description}

## Files
{file_patterns}

## Progress
- Starting implementation
```

Launch agent using Task tool:
```yaml
Task:
  description: "Task $ARGUMENTS Stream {X}"
  subagent_type: "{agent_type}"
  prompt: |
    You are working on task $ARGUMENTS in the epic worktree.
    
    Worktree location: ../epic-{epic_name}/
    Your stream: {stream_name}
    
    Your scope:
    - Files to modify: {file_patterns}
    - Work to complete: {stream_description}
    
    Requirements:
    1. Read full task from: .claude/epics/{epic_name}/{task_file}
    2. Work ONLY in your assigned files
    3. Commit frequently with format: "{JIRA-KEY}: {specific change}"
    4. Update progress in: .claude/epics/{epic_name}/updates/$ARGUMENTS/stream-{X}.md
    5. Follow coordination rules in /rules/agent-coordination.md
    
    If you need to modify files outside your scope:
    - Check if another stream owns them
    - Wait if necessary
    - Update your progress file with coordination notes
    
    Complete your stream's work and mark as completed when done.
```

### 6. Output

```
✅ Started parallel work on task $ARGUMENTS

Epic: {epic_name}
Worktree: ../epic-{epic_name}/
Branch: {jira_branch_name} (Jira-formatted)

Launching {count} parallel agents:
  Stream A: {name} (Agent-1) ✓ Started
  Stream B: {name} (Agent-2) ✓ Started
  Stream C: {name} - Waiting (depends on A)

Progress tracking:
  .claude/epics/{epic_name}/updates/$ARGUMENTS/

Monitor with: /pm:epic-status {epic_name}
Sync updates: /pm:task-sync $ARGUMENTS
```

## Error Handling

If any step fails, report clearly:
- "❌ {What failed}: {How to fix}"
- Continue with what's possible
- Never leave partial state

## Important Notes

Follow `/rules/datetime.md` for timestamps.
Keep it simple - trust that file system works.

## Jira Integration Details

1. **Validates Setup**: Checks for required configuration
   - Jira enabled in settings
   - MCP connection active

2. **Updates Status**: Transitions Jira issue to "In Progress"
   - Uses available transitions for the issue
   - Reports clear errors if transition fails

## Example Output

```
🚀 Starting work on task 123
🔄 Mode: Jira
📋 Checking task file...
   Task: Implement user authentication
🔄 Delegating to Jira implementation...
🔍 Found Jira issue: PROJ-456
📊 Updating Jira issue status to In Progress...
✅ Jira status updated successfully
🌱 Creating Jira-formatted branch...
✅ Branch created: PROJ-456-implement-user-authentication
✅ Jira issue start completed successfully!
```