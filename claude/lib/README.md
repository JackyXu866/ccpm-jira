# Git-Jira Integration Library

This library provides functions for integrating Git branch operations with Jira issue tracking.

## Files

- `git-integration.sh` - Core library with branch naming and validation functions

## Key Functions

### Branch Creation
- `get_jira_key <issue_number>` - Extract Jira key from GitHub issue
- `generate_branch_name <jira_key> [description]` - Create formatted branch name
- `create_jira_branch <issue_number> [description]` - Full branch creation workflow

### Validation
- `is_valid_jira_branch <branch_name>` - Check if branch follows Jira convention
- `validate_current_branch` - Validate the current Git branch

### Utilities
- `branch_exists <branch_name>` - Check for local/remote branch conflicts
- `resolve_branch_conflict <base_name>` - Generate unique branch name
- `extract_jira_key_from_branch [branch_name]` - Get Jira key from branch
- `get_jira_url_from_branch [branch_name]` - Generate Jira issue URL

## Branch Naming Convention

Branches follow the pattern: `JIRA-123-description`

Examples:
- `PROJ-456` (minimal)
- `ABC-123-fix-login-bug` (with description)
- `TASK-789-implement-user-auth` (longer description)

## Configuration

The library supports configuration via `claude/config/git-integration.json`:

```json
{
  "enabled": true,
  "branch_prefix": "JIRA",
  "max_branch_length": 50,
  "jira_base_url": "https://your-domain.atlassian.net"
}
```

## Git Hooks

- `.claude/hooks/pre-push` - Validates branch names before pushing
- `.claude/hooks/install-hooks.sh` - Installs hooks into `.git/hooks/`

## Usage in Scripts

```bash
# Source the library
source claude/lib/git-integration.sh

# Create a Jira branch for issue #123
create_jira_branch 123 "fix authentication bug"

# Validate current branch
validate_current_branch

# Check if a branch name is valid
if is_valid_jira_branch "PROJ-456-test"; then
    echo "Valid branch name"
fi
```

## Integration with PM Commands

The `issue-start.sh` script automatically creates Jira-formatted branches when starting work on issues, providing seamless integration with the project management workflow.