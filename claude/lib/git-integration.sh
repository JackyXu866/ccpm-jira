#!/bin/bash

# Git-Jira Integration Library
# Provides functions for branch naming, validation, and conflict resolution

set -e

# Configuration defaults
DEFAULT_BRANCH_PREFIX="JIRA"
DEFAULT_MAX_BRANCH_LENGTH=50

# Load configuration if available
if [[ -f "claude/config/git-integration.json" ]]; then
    # Parse JSON config (basic parsing)
    BRANCH_PREFIX=$(grep -o '"branch_prefix":\s*"[^"]*"' claude/config/git-integration.json | cut -d'"' -f4 || echo "$DEFAULT_BRANCH_PREFIX")
    MAX_BRANCH_LENGTH=$(grep -o '"max_branch_length":\s*[0-9]*' claude/config/git-integration.json | grep -o '[0-9]*' || echo "$DEFAULT_MAX_BRANCH_LENGTH")
else
    BRANCH_PREFIX="$DEFAULT_BRANCH_PREFIX"
    MAX_BRANCH_LENGTH="$DEFAULT_MAX_BRANCH_LENGTH"
fi

# Get Jira issue key from issue number
# Usage: get_jira_key <issue_number>
get_jira_key() {
    local issue_number="$1"
    
    # Check local task files for Jira key
    local task_file=""
    for epic_dir in .claude/epics/*; do
        if [[ -d "$epic_dir" ]] && [[ -f "$epic_dir/$issue_number.md" ]]; then
            task_file="$epic_dir/$issue_number.md"
            break
        fi
    done
    
    if [[ -n "$task_file" ]]; then
        local jira_key
        jira_key=$(grep '^jira_key:' "$task_file" | head -1 | sed 's/^jira_key: *//' | sed 's/"//g' || echo "")
        
        if [[ -n "$jira_key" ]]; then
            echo "$jira_key"
            return 0
        fi
    fi
    
    # Fallback: Use configured prefix with issue number
    echo "${BRANCH_PREFIX}-${issue_number}"
}

# Generate branch name from Jira key
# Usage: generate_branch_name <jira_key> [description]
generate_branch_name() {
    local jira_key="$1"
    local description="${2:-}"
    
    local branch_name="$jira_key"
    
    # Add description if provided
    if [[ -n "$description" ]]; then
        # Clean description: lowercase, replace spaces with hyphens, remove special chars
        local clean_desc
        clean_desc=$(echo "$description" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 ]//g' | tr ' ' '-' | sed 's/-\+/-/g' | sed 's/^-\|-$//g')
        
        # Truncate if too long
        local max_desc_length=$((MAX_BRANCH_LENGTH - ${#jira_key} - 1))
        if [[ ${#clean_desc} -gt $max_desc_length ]]; then
            clean_desc="${clean_desc:0:$max_desc_length}"
            clean_desc="${clean_desc%-}" # Remove trailing hyphen
        fi
        
        if [[ -n "$clean_desc" ]]; then
            branch_name="${jira_key}-${clean_desc}"
        fi
    fi
    
    echo "$branch_name"
}

# Check if branch name follows Jira convention
# Usage: is_valid_jira_branch <branch_name>
is_valid_jira_branch() {
    local branch_name="$1"
    
    # Must start with Jira key pattern (e.g., PROJ-123 or ABC-456)
    if [[ "$branch_name" =~ ^[A-Z]+-[0-9]+(-.*)?$ ]]; then
        return 0
    fi
    
    return 1
}

# Check if branch exists locally or remotely
# Usage: branch_exists <branch_name>
branch_exists() {
    local branch_name="$1"
    
    # Check local branches
    if git branch --list | grep -q "\\b${branch_name}\\b"; then
        return 0
    fi
    
    # Check remote branches
    if git ls-remote --heads origin "$branch_name" | grep -q "$branch_name"; then
        return 0
    fi
    
    return 1
}

# Create unique branch name if conflicts exist
# Usage: resolve_branch_conflict <base_branch_name>
resolve_branch_conflict() {
    local base_name="$1"
    local counter=1
    local candidate="$base_name"
    
    while branch_exists "$candidate"; do
        candidate="${base_name}-${counter}"
        counter=$((counter + 1))
        
        # Safety check to prevent infinite loop
        if [[ $counter -gt 99 ]]; then
            echo "ERROR: Too many branch conflicts for $base_name" >&2
            return 1
        fi
    done
    
    echo "$candidate"
}

# Create a new Jira-formatted branch
# Usage: create_jira_branch <issue_number> [description]
create_jira_branch() {
    local issue_number="$1"
    local description="${2:-}"
    
    # Get Jira key
    local jira_key
    jira_key=$(get_jira_key "$issue_number")
    
    # Generate branch name
    local branch_name
    branch_name=$(generate_branch_name "$jira_key" "$description")
    
    # Check for conflicts and resolve
    local final_branch_name
    final_branch_name=$(resolve_branch_conflict "$branch_name")
    
    # Ensure we're on main and up to date
    echo "Preparing to create branch: $final_branch_name"
    
    if ! git checkout main 2>/dev/null; then
        echo "WARNING: Could not switch to main branch" >&2
    fi
    
    if ! git pull origin main 2>/dev/null; then
        echo "WARNING: Could not update main branch" >&2
    fi
    
    # Create the branch
    if git checkout -b "$final_branch_name"; then
        echo "✅ Created branch: $final_branch_name"
        
        # Push branch with upstream tracking
        if git push -u origin "$final_branch_name" 2>/dev/null; then
            echo "✅ Pushed branch to remote"
        else
            echo "WARNING: Could not push branch to remote" >&2
        fi
        
        echo "$final_branch_name"
        return 0
    else
        echo "ERROR: Failed to create branch $final_branch_name" >&2
        return 1
    fi
}

# Validate current branch name
# Usage: validate_current_branch
validate_current_branch() {
    local current_branch
    current_branch=$(git branch --show-current)
    
    # Skip validation for main/master branches
    if [[ "$current_branch" == "main" || "$current_branch" == "master" ]]; then
        return 0
    fi
    
    if is_valid_jira_branch "$current_branch"; then
        echo "✅ Branch '$current_branch' follows Jira naming convention"
        return 0
    else
        echo "⚠️  Branch '$current_branch' does not follow Jira naming convention"
        echo "   Expected format: JIRA-123 or PROJ-456-description"
        return 1
    fi
}

# Extract Jira key from branch name
# Usage: extract_jira_key_from_branch [branch_name]
extract_jira_key_from_branch() {
    local branch_name="${1:-$(git branch --show-current)}"
    
    if [[ "$branch_name" =~ ^([A-Z]+-[0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        return 1
    fi
}

# Get Jira issue URL from branch
# Usage: get_jira_url_from_branch [branch_name]
get_jira_url_from_branch() {
    local branch_name="${1:-$(git branch --show-current)}"
    local jira_key
    
    if jira_key=$(extract_jira_key_from_branch "$branch_name"); then
        # Try to get Jira base URL from config
        local jira_base_url=""
        if [[ -f "claude/config/git-integration.json" ]]; then
            jira_base_url=$(grep -o '"jira_base_url":\s*"[^"]*"' claude/config/git-integration.json | cut -d'"' -f4 || echo "")
        fi
        
        if [[ -n "$jira_base_url" ]]; then
            echo "${jira_base_url}/browse/${jira_key}"
        else
            echo "https://your-domain.atlassian.net/browse/${jira_key}"
        fi
    else
        return 1
    fi
}