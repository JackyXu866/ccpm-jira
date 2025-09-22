---
allowed-tools: Bash, Read, Write, LS, Task
---

# Epic Start

Launch parallel agents to work on epic tasks, each in their own worktree.

## Usage
```
/pm:epic-start <epic_name>
```

## Quick Check

1. **Verify epic exists:**
   ```bash
   test -f .claude/epics/$ARGUMENTS/epic.md || echo "❌ Epic not found. Run: /pm:prd-parse $ARGUMENTS"
   ```

2. **Check Jira sync:**
   Look for `jira:` field in epic frontmatter.
   If missing: "❌ Epic not synced. Run: /pm:epic-sync $ARGUMENTS first"

3. **Check for worktrees:**
   ```bash
   # Check for task-specific worktrees
   git worktree list | grep -E "PROJ-[0-9]+-$ARGUMENTS"
   ```

## Instructions

### 1. Create Task-Specific Worktrees

Follow `/rules/worktree-operations.md`:

```bash
# For each task, create a dedicated worktree
# Pattern: {task-id}-{epic-name}
# Example: PROJ-1234-user-auth

task_id="PROJ-1234"  # From Jira
epic_name="$ARGUMENTS"

worktree_name="${task_id}-${epic_name}"
branch_name="task/${task_id}"

if ! git worktree list | grep -q "$worktree_name"; then
  git checkout main
  git pull origin main
  git worktree add ../$worktree_name -b $branch_name
  echo "✅ Created worktree: ../$worktree_name"
else
  echo "✅ Using existing worktree: ../$worktree_name"
fi
```

### 2. Identify Ready Issues

Read all task files in `.claude/epics/$ARGUMENTS/`:
- Parse frontmatter for `status`, `depends_on`, `parallel` fields
- Check Jira task status if needed
- Build dependency graph

Categorize issues:
- **Ready**: No unmet dependencies, not started
- **Blocked**: Has unmet dependencies
- **In Progress**: Already being worked on
- **Complete**: Finished

### 3. Analyze Ready Issues

For each ready issue without analysis:
```bash
# Check for analysis
if ! test -f .claude/epics/$ARGUMENTS/{issue}-analysis.md; then
  echo "Analyzing task #{issue}..."
  # Run analysis (inline or via Task tool)
fi
```

### 4. Launch Parallel Agents

For each ready issue with analysis:

```markdown
## Starting Task {task_id}: {title}

Reading analysis...
Found {count} parallel streams:
  - Stream A: {description} (Agent-{id})
  - Stream B: {description} (Agent-{id})

Creating worktree: ../{task_id}-{epic_name}/
```

Use Task tool to launch each stream:
```yaml
Task:
  description: "Task {task_id} Stream {X}"
  subagent_type: "{agent_type}"
  prompt: |
    Working in worktree: ../{task_id}-{epic_name}/
    Task: {task_id} - {title}
    Stream: {stream_name}

    Your scope:
    - Files: {file_patterns}
    - Work: {stream_description}

    Read full requirements from:
    - .claude/epics/$ARGUMENTS/{task_file}
    - .claude/epics/$ARGUMENTS/{issue}-analysis.md

    Follow coordination rules in /rules/agent-coordination.md

    Commit frequently with message format:
    "{task_id}: {specific change}"

    Update progress in:
    .claude/epics/$ARGUMENTS/updates/{task_id}/stream-{X}.md
```

### 5. Track Active Agents

Create/update `.claude/epics/$ARGUMENTS/execution-status.md`:

```markdown
---
started: {datetime}
epic: $ARGUMENTS
---

# Execution Status

## Active Worktrees
- PROJ-1234-{epic_name}: Database Task
  - Agent-1: Stream A (Schema creation) - Started {time}
  - Agent-2: Stream B (Migrations) - Started {time}
  - Branch: task/PROJ-1234

- PROJ-1235-{epic_name}: API Task
  - Agent-3: Stream A (User endpoints) - Started {time}
  - Agent-4: Stream B (Auth endpoints) - Started {time}
  - Branch: task/PROJ-1235

## Queued Tasks
- PROJ-1236 - Waiting for PROJ-1234
- PROJ-1237 - Waiting for PROJ-1235

## Completed Tasks
- {None yet}
```

### 6. Monitor and Coordinate

Set up monitoring:
```bash
echo "
Agents launched successfully!

Monitor progress:
  /pm:epic-status $ARGUMENTS

View worktree changes:
  # List all task worktrees for this epic
  git worktree list | grep "$ARGUMENTS"
  
  # Check specific task worktree
  cd ../PROJ-1234-$ARGUMENTS && git status

Stop all agents:
  /pm:epic-stop $ARGUMENTS

Merge when complete:
  /pm:epic-merge $ARGUMENTS
"
```

### 7. Handle Dependencies

As agents complete streams:
- Check if any blocked issues are now ready
- Launch new agents for newly-ready work
- Update execution-status.md

## Output Format

```
🚀 Epic Execution Started: $ARGUMENTS

Creating task-specific worktrees...

Launching {total} agents across {task_count} tasks:

Task PROJ-1234: Database Schema
  Worktree: ../PROJ-1234-$ARGUMENTS
  Branch: task/PROJ-1234
  ├─ Stream A: Schema creation (Agent-1) ✓ Started
  └─ Stream B: Migrations (Agent-2) ✓ Started

Task PROJ-1235: API Endpoints
  Worktree: ../PROJ-1235-$ARGUMENTS
  Branch: task/PROJ-1235
  ├─ Stream A: User endpoints (Agent-3) ✓ Started
  ├─ Stream B: Post endpoints (Agent-4) ✓ Started
  └─ Stream C: Tests (Agent-5) ⏸ Waiting for A & B

Blocked Tasks (2):
  - PROJ-1236: UI Components (depends on PROJ-1234)
  - PROJ-1237: Integration (depends on PROJ-1235, PROJ-1236)

Monitor with: /pm:epic-status $ARGUMENTS
```

## Error Handling

If agent launch fails:
```
❌ Failed to start Agent-{id}
  Issue: #{issue}
  Stream: {stream}
  Error: {reason}

Continue with other agents? (yes/no)
```

If worktree creation fails:
```
❌ Cannot create worktree
  {git error message}

Try: git worktree prune
Or: Check existing worktrees with: git worktree list
```

## Important Notes

- Follow `/rules/worktree-operations.md` for git operations
- Follow `/rules/agent-coordination.md` for parallel work
- Each task gets its own worktree following pattern: {task-id}-{epic-name}
- Multiple agents can work on different streams within the same task worktree
- Maximum parallel agents should be reasonable (e.g., 5-10)
- Monitor system resources if launching many agents
