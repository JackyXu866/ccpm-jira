# Worktree Operations

Git worktrees enable parallel development by allowing multiple working directories for the same repository.

## Worktree Strategy

We use a **task-based worktree strategy** where each Jira task gets its own worktree:
- Pattern: `{task-id}-{epic-name}` (e.g., `PROJ-1234-user-auth`)
- Branch pattern: `task/{task-id}` (e.g., `task/PROJ-1234`)
- This allows true parallel development without file conflicts

## Creating Worktrees

### For Individual Tasks
Always create worktrees from a clean main branch:
```bash
# Ensure main is up to date
git checkout main
git pull origin main

# Create worktree for a specific task
task_id="PROJ-1234"
epic_name="user-auth"
worktree_name="${task_id}-${epic_name}"
branch_name="task/${task_id}"

git worktree add ../$worktree_name -b $branch_name
```

### For Epic-Level Work (Legacy)
```bash
# Create shared worktree for epic (not recommended)
git worktree add ../epic-{name} -b epic/{name}
```

The worktree will be created as a sibling directory to maintain clean separation.

## Working in Worktrees

### Agent Commits
- Agents commit directly to the worktree
- Use small, focused commits
- Commit message format: `{JIRA-KEY}: {description}`
- Example: `PROJ-1234: Add user authentication schema`

### File Operations
```bash
# Working directory is the task worktree
cd ../PROJ-1234-user-auth

# Normal git operations work
git add {files}
git commit -m "{JIRA-KEY}: {change}"

# View worktree status
git status
```

## Parallel Work Strategy

### Task-Level Isolation (Recommended)
Each task gets its own worktree, eliminating conflicts:
```bash
# Task PROJ-1234 works in its own worktree
cd ../PROJ-1234-user-auth
git add src/auth/*
git commit -m "PROJ-1234: Add authentication service"

# Task PROJ-1235 works in separate worktree (no conflicts!)
cd ../PROJ-1235-user-auth
git add src/ui/*
git commit -m "PROJ-1235: Add login component"
```

### Stream-Level Parallelism
Multiple agents can work on different streams within the same task worktree:
```bash
# Agent A works on backend stream
cd ../PROJ-1234-user-auth
git add src/api/*
git commit -m "PROJ-1234: Add user API endpoints"

# Agent B works on frontend stream
git add src/components/*
git commit -m "PROJ-1234: Add user profile component"
```

## Merging Worktrees

### Merging Individual Tasks
When a task is complete, merge it back to main:
```bash
# From main repository (not worktree)
cd {main-repo}
git checkout main
git pull origin main

# Merge task branch
git merge task/PROJ-1234

# If successful, clean up
git worktree remove ../PROJ-1234-user-auth
git branch -d task/PROJ-1234
```

### Merging Complete Epic
When all tasks in an epic are complete:
```bash
# Merge all task branches in order
for task in PROJ-1234 PROJ-1235 PROJ-1236; do
  git merge task/$task
done

# Clean up all task worktrees for the epic
for worktree in $(git worktree list --porcelain | grep "worktree.*-user-auth" | cut -d' ' -f2); do
  git worktree remove "$worktree"
done

# Delete task branches
for task in PROJ-1234 PROJ-1235 PROJ-1236; do
  git branch -d task/$task
done
```

## Handling Conflicts

If merge conflicts occur:
```bash
# Conflicts will be shown
git status

# Human resolves conflicts
# Then continue merge
git add {resolved-files}
git commit
```

## Worktree Management

### List Active Worktrees
```bash
git worktree list
```

### Remove Stale Worktree
```bash
# If worktree directory was deleted
git worktree prune

# Force remove worktree
git worktree remove --force ../epic-{name}
```

### Check Worktree Status
```bash
# From main repo
cd ../epic-{name} && git status && cd -
```

## Best Practices

1. **One worktree per task** - Better isolation than per-epic
2. **Clean before create** - Always start from updated main
3. **Commit frequently** - Small commits are easier to merge
4. **Delete after merge** - Don't leave stale worktrees
5. **Use descriptive branches** - `task/PROJ-1234` not just `feature`
6. **Name worktrees clearly** - `PROJ-1234-epic-name` shows both task and context

## Common Issues

### Worktree Already Exists
```bash
# Remove old worktree first
git worktree remove ../epic-{name}
# Then create new one
```

### Branch Already Exists
```bash
# Delete old branch
git branch -D epic/{name}
# Or use existing branch
git worktree add ../epic-{name} epic/{name}
```

### Cannot Remove Worktree
```bash
# Force removal
git worktree remove --force ../epic-{name}
# Clean up references
git worktree prune
```