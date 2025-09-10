#!/bin/bash

# PR Templates Library for Jira Integration
# Generates PR titles and descriptions with Jira context

# Configuration
JIRA_CONFIG_FILE="${JIRA_CONFIG_FILE:-.claude/config/jira.json}"
GIT_CONFIG_FILE="${GIT_CONFIG_FILE:-.claude/config/git-integration.json}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Extract Jira issue key from branch name
extract_jira_key_from_branch() {
    local branch_name
    branch_name=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    
    if [[ -z "$branch_name" ]]; then
        return 1
    fi
    
    # Match patterns like: JIRA-123, feature/JIRA-123, PROJ-456-feature
    if [[ "$branch_name" =~ ([A-Z]{2,10}-[0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    
    return 1
}

# Extract Jira issue key from commit messages
extract_jira_key_from_commits() {
    local base_branch="${1:-main}"
    
    # Get commits since base branch
    local commits
    commits=$(git log --oneline "$base_branch"..HEAD 2>/dev/null)
    
    if [[ -z "$commits" ]]; then
        return 1
    fi
    
    # Look for Jira keys in commit messages
    if [[ "$commits" =~ ([A-Z]{2,10}-[0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    
    return 1
}

# Get Jira issue information (stub - to be implemented with actual API)
get_jira_issue_info() {
    local issue_key="$1"
    
    if [[ -z "$issue_key" ]]; then
        return 1
    fi
    
    # TODO: Implement actual Jira API call when Stream C provides config
    # For now, return mock data structure
    cat <<EOF
{
    "key": "$issue_key",
    "summary": "Sample issue summary for $issue_key",
    "description": "Sample description",
    "status": "In Progress",
    "assignee": "developer@example.com",
    "type": "Story",
    "priority": "Medium",
    "url": "https://yourjira.atlassian.net/browse/$issue_key"
}
EOF
}

# Generate PR title with Jira information
generate_pr_title() {
    local jira_key="$1"
    local custom_title="$2"
    
    # If no Jira key, use custom title or generate from commits
    if [[ -z "$jira_key" ]]; then
        if [[ -n "$custom_title" ]]; then
            echo "$custom_title"
        else
            # Generate title from recent commits
            local recent_commit
            recent_commit=$(git log --oneline -1 --pretty=format:"%s" HEAD 2>/dev/null)
            echo "${recent_commit:-"Update branch"}"
        fi
        return 0
    fi
    
    # Get Jira issue info
    local jira_info
    jira_info=$(get_jira_issue_info "$jira_key")
    
    if [[ $? -eq 0 ]]; then
        local summary
        summary=$(echo "$jira_info" | grep -o '"summary":[^,]*' | cut -d'"' -f4)
        
        if [[ -n "$custom_title" ]]; then
            echo "[$jira_key] $custom_title"
        else
            echo "[$jira_key] $summary"
        fi
    else
        # Fallback if Jira API fails
        if [[ -n "$custom_title" ]]; then
            echo "[$jira_key] $custom_title"
        else
            echo "[$jira_key] Update"
        fi
    fi
}

# Generate PR description with Jira context
generate_pr_description() {
    local jira_key="$1"
    local custom_description="$2"
    local base_branch="${3:-main}"
    
    local description=""
    
    # Add Jira section if we have a key
    if [[ -n "$jira_key" ]]; then
        local jira_info
        jira_info=$(get_jira_issue_info "$jira_key")
        
        if [[ $? -eq 0 ]]; then
            local summary type status url
            summary=$(echo "$jira_info" | grep -o '"summary":[^,]*' | cut -d'"' -f4)
            type=$(echo "$jira_info" | grep -o '"type":[^,]*' | cut -d'"' -f4)
            status=$(echo "$jira_info" | grep -o '"status":[^,]*' | cut -d'"' -f4)
            url=$(echo "$jira_info" | grep -o '"url":[^,]*' | cut -d'"' -f4)
            
            description+="## 🎯 Jira Issue\n\n"
            description+="**[$jira_key]($url)** - $summary\n\n"
            description+="- **Type**: $type\n"
            description+="- **Status**: $status\n\n"
        else
            description+="## 🎯 Related Issue\n\n"
            description+="**$jira_key** - _Issue details unavailable_\n\n"
        fi
    fi
    
    # Add custom description if provided
    if [[ -n "$custom_description" ]]; then
        description+="## 📝 Description\n\n"
        description+="$custom_description\n\n"
    fi
    
    # Add changes summary
    description+="## 📊 Changes\n\n"
    
    # Get commit summary
    local commits
    commits=$(git log --oneline "$base_branch"..HEAD 2>/dev/null)
    
    if [[ -n "$commits" ]]; then
        description+="### Commits in this PR:\n"
        while IFS= read -r commit; do
            description+="- $commit\n"
        done <<< "$commits"
        description+="\n"
    fi
    
    # Get file changes summary
    local files_changed
    files_changed=$(git diff --name-only "$base_branch"..HEAD 2>/dev/null | wc -l)
    
    if [[ "$files_changed" -gt 0 ]]; then
        description+="### Files changed: $files_changed\n\n"
        
        # Show file categories
        local file_types
        file_types=$(git diff --name-only "$base_branch"..HEAD 2>/dev/null | sed 's/.*\.//' | sort | uniq -c | sort -nr)
        
        if [[ -n "$file_types" ]]; then
            description+="**File types:**\n"
            while IFS= read -r line; do
                local count type
                count=$(echo "$line" | awk '{print $1}')
                type=$(echo "$line" | awk '{print $2}')
                description+="- $type files: $count\n"
            done <<< "$file_types"
            description+="\n"
        fi
    fi
    
    # Add testing section
    description+="## 🧪 Testing\n\n"
    description+="- [ ] Unit tests pass\n"
    description+="- [ ] Integration tests pass\n"
    description+="- [ ] Manual testing completed\n\n"
    
    # Add checklist
    description+="## ✅ Checklist\n\n"
    description+="- [ ] Code follows project style guidelines\n"
    description+="- [ ] Self-review completed\n"
    description+="- [ ] Documentation updated if needed\n"
    
    if [[ -n "$jira_key" ]]; then
        description+="- [ ] Jira issue updated with progress\n"
    fi
    
    echo -e "$description"
}

# Get current git context for PR
get_git_context() {
    local base_branch="${1:-main}"
    
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    
    if [[ -z "$current_branch" || "$current_branch" == "HEAD" ]]; then
        log_error "Not on a valid git branch"
        return 1
    fi
    
    if [[ "$current_branch" == "$base_branch" ]]; then
        log_error "Cannot create PR from base branch ($base_branch)"
        return 1
    fi
    
    # Check if there are changes to commit
    if ! git diff --quiet HEAD "$base_branch" 2>/dev/null; then
        local commits_ahead
        commits_ahead=$(git rev-list --count "$base_branch"..HEAD 2>/dev/null)
        
        if [[ "$commits_ahead" -eq 0 ]]; then
            log_error "No commits ahead of $base_branch"
            return 1
        fi
    fi
    
    cat <<EOF
{
    "current_branch": "$current_branch",
    "base_branch": "$base_branch",
    "commits_ahead": $(git rev-list --count "$base_branch"..HEAD 2>/dev/null || echo 0),
    "files_changed": $(git diff --name-only "$base_branch"..HEAD 2>/dev/null | wc -l)
}
EOF
}

# Main function to generate complete PR data
generate_pr_data() {
    local custom_title="$1"
    local custom_description="$2"
    local base_branch="${3:-main}"
    
    log_info "Generating PR data..."
    
    # Get git context
    local git_context
    git_context=$(get_git_context "$base_branch")
    
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    # Extract Jira key from branch or commits
    local jira_key
    jira_key=$(extract_jira_key_from_branch)
    
    if [[ -z "$jira_key" ]]; then
        jira_key=$(extract_jira_key_from_commits "$base_branch")
    fi
    
    if [[ -n "$jira_key" ]]; then
        log_success "Found Jira issue: $jira_key"
    else
        log_warning "No Jira issue key found in branch name or commits"
    fi
    
    # Generate title and description
    local pr_title pr_description
    pr_title=$(generate_pr_title "$jira_key" "$custom_title")
    pr_description=$(generate_pr_description "$jira_key" "$custom_description" "$base_branch")
    
    # Output structured data
    cat <<EOF
{
    "title": "$pr_title",
    "description": "$pr_description",
    "jira_key": "$jira_key",
    "git_context": $git_context
}
EOF
}

# Utility function to format PR for GitHub CLI
format_pr_for_gh() {
    local pr_data="$1"
    
    if [[ -z "$pr_data" ]]; then
        log_error "No PR data provided"
        return 1
    fi
    
    local title description
    title=$(echo "$pr_data" | grep -o '"title":[^,]*' | cut -d'"' -f4)
    description=$(echo "$pr_data" | grep -A 1000 '"description":' | sed '1d' | sed '$d' | sed 's/^[[:space:]]*//')
    
    echo "Title: $title"
    echo ""
    echo "Description:"
    echo "$description"
}

# Help function
show_help() {
    cat <<EOF
PR Templates Library for Jira Integration

Functions:
  generate_pr_data [title] [description] [base_branch]
    Generate complete PR data with Jira context
  
  generate_pr_title [jira_key] [custom_title]
    Generate PR title with Jira information
  
  generate_pr_description [jira_key] [custom_description] [base_branch]
    Generate PR description with Jira context
  
  extract_jira_key_from_branch
    Extract Jira issue key from current branch name
  
  get_git_context [base_branch]
    Get current git context for PR creation

Examples:
  # Generate PR data with auto-detected Jira key
  generate_pr_data "Fix user authentication" "Resolves login issues"
  
  # Generate PR data for specific base branch
  generate_pr_data "" "" "develop"

Environment Variables:
  JIRA_CONFIG_FILE    Path to Jira configuration (default: .claude/config/jira.json)
  GIT_CONFIG_FILE     Path to Git integration config (default: .claude/config/git-integration.json)
EOF
}

# If script is run directly, show help
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    show_help
fi