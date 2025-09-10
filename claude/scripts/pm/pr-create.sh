#!/bin/bash

# Jira-aware PR Creation Script
# Creates Pull Requests with automatic Jira integration

# Script directory for relative imports
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../../lib" && pwd)"

# Source the PR templates library
if [[ -f "$LIB_DIR/pr-templates.sh" ]]; then
    source "$LIB_DIR/pr-templates.sh"
else
    echo "❌ Error: PR templates library not found at $LIB_DIR/pr-templates.sh"
    exit 1
fi

# Default configuration
DEFAULT_BASE_BRANCH="main"
DEFAULT_REMOTE="origin"

# Usage information
show_usage() {
    cat <<EOF
🔄 Jira-aware PR Creation

Usage: $0 [options]

Options:
    -t, --title TITLE           Custom PR title (auto-generated if not provided)
    -d, --description DESC      Custom PR description
    -b, --base BRANCH          Base branch for PR (default: $DEFAULT_BASE_BRANCH)
    -r, --remote REMOTE        Remote repository (default: $DEFAULT_REMOTE)
    -j, --jira-key KEY         Force specific Jira issue key
    --draft                    Create as draft PR
    --dry-run                  Show what would be done without creating PR
    -h, --help                 Show this help message

Examples:
    # Create PR with auto-detected Jira info
    $0

    # Create PR with custom title
    $0 -t "Fix authentication bug"

    # Create draft PR for feature branch
    $0 --draft -b develop

    # Dry run to preview PR content
    $0 --dry-run

The script will:
1. Auto-detect Jira issue key from branch name or commits
2. Generate PR title with Jira issue information
3. Create comprehensive PR description with Jira context
4. Link the PR to the Jira issue
5. Create the PR using GitHub CLI

EOF
}

# Parse command line arguments
parse_args() {
    CUSTOM_TITLE=""
    CUSTOM_DESCRIPTION=""
    BASE_BRANCH="$DEFAULT_BASE_BRANCH"
    REMOTE="$DEFAULT_REMOTE"
    FORCE_JIRA_KEY=""
    DRAFT_FLAG=""
    DRY_RUN=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--title)
                CUSTOM_TITLE="$2"
                shift 2
                ;;
            -d|--description)
                CUSTOM_DESCRIPTION="$2"
                shift 2
                ;;
            -b|--base)
                BASE_BRANCH="$2"
                shift 2
                ;;
            -r|--remote)
                REMOTE="$2"
                shift 2
                ;;
            -j|--jira-key)
                FORCE_JIRA_KEY="$2"
                shift 2
                ;;
            --draft)
                DRAFT_FLAG="--draft"
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "Not in a git repository"
        return 1
    fi
    
    # Check if GitHub CLI is installed and authenticated
    if ! command -v gh &> /dev/null; then
        log_error "GitHub CLI (gh) is not installed"
        log_info "Install with: brew install gh (Mac) or visit https://cli.github.com/"
        return 1
    fi
    
    # Check GitHub authentication
    if ! gh auth status &> /dev/null; then
        log_error "GitHub CLI is not authenticated"
        log_info "Run: gh auth login"
        return 1
    fi
    
    log_success "Prerequisites validated"
    return 0
}

# Check if current branch is ahead of base
validate_branch_state() {
    local base_branch="$1"
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    
    log_info "Validating branch state..."
    
    # Check if we're on the base branch
    if [[ "$current_branch" == "$base_branch" ]]; then
        log_error "Cannot create PR from base branch ($base_branch)"
        log_info "Please switch to a feature branch first"
        return 1
    fi
    
    # Check if base branch exists
    if ! git show-ref --verify --quiet "refs/heads/$base_branch"; then
        log_error "Base branch '$base_branch' does not exist locally"
        log_info "Try: git fetch $REMOTE $base_branch"
        return 1
    fi
    
    # Check if we have commits ahead of base
    local commits_ahead
    commits_ahead=$(git rev-list --count "$base_branch"..HEAD 2>/dev/null)
    
    if [[ "$commits_ahead" -eq 0 ]]; then
        log_error "No commits ahead of $base_branch"
        log_info "Make some changes and commit them first"
        return 1
    fi
    
    log_success "Branch state validated ($commits_ahead commits ahead of $base_branch)"
    return 0
}

# Push current branch to remote if needed
push_branch_if_needed() {
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    
    log_info "Checking if branch needs to be pushed..."
    
    # Check if remote branch exists
    if git ls-remote --exit-code --heads "$REMOTE" "$current_branch" &>/dev/null; then
        log_info "Remote branch exists, checking if push needed..."
        
        # Check if local is ahead of remote
        local commits_ahead
        commits_ahead=$(git rev-list --count "$REMOTE/$current_branch"..HEAD 2>/dev/null)
        
        if [[ "$commits_ahead" -gt 0 ]]; then
            log_info "Pushing $commits_ahead new commits to remote..."
            if ! git push "$REMOTE" "$current_branch"; then
                log_error "Failed to push branch"
                return 1
            fi
            log_success "Branch pushed to remote"
        else
            log_info "Branch is up to date with remote"
        fi
    else
        log_info "Remote branch doesn't exist, pushing for first time..."
        if ! git push -u "$REMOTE" "$current_branch"; then
            log_error "Failed to push branch"
            return 1
        fi
        log_success "Branch pushed to remote with upstream tracking"
    fi
    
    return 0
}

# Create the PR using GitHub CLI
create_github_pr() {
    local title="$1"
    local description="$2"
    local base_branch="$3"
    local draft_flag="$4"
    
    log_info "Creating GitHub PR..."
    
    # Create temporary file for description
    local desc_file
    desc_file=$(mktemp)
    echo -e "$description" > "$desc_file"
    
    # Build gh pr create command
    local gh_cmd=(gh pr create --title "$title" --base "$base_branch" --body-file "$desc_file")
    
    if [[ -n "$draft_flag" ]]; then
        gh_cmd+=(--draft)
    fi
    
    # Execute command
    local pr_url
    if pr_url=$("${gh_cmd[@]}" 2>&1); then
        log_success "PR created successfully!"
        echo ""
        echo "📎 PR URL: $pr_url"
        
        # Clean up temp file
        rm -f "$desc_file"
        
        return 0
    else
        log_error "Failed to create PR"
        echo "Error: $pr_url"
        
        # Clean up temp file
        rm -f "$desc_file"
        
        return 1
    fi
}

# Main execution function
main() {
    echo "🔄 Jira-aware PR Creation"
    echo "========================"
    echo ""
    
    # Parse arguments
    parse_args "$@"
    
    # Validate prerequisites
    if ! validate_prerequisites; then
        exit 1
    fi
    
    # Validate branch state
    if ! validate_branch_state "$BASE_BRANCH"; then
        exit 1
    fi
    
    # Generate PR data using the library
    log_info "Generating PR content with Jira integration..."
    local pr_data
    
    # Override Jira key if forced
    if [[ -n "$FORCE_JIRA_KEY" ]]; then
        # Temporarily override the function to return forced key
        extract_jira_key_from_branch() { echo "$FORCE_JIRA_KEY"; }
    fi
    
    pr_data=$(generate_pr_data "$CUSTOM_TITLE" "$CUSTOM_DESCRIPTION" "$BASE_BRANCH")
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to generate PR data"
        exit 1
    fi
    
    # Extract title and description from JSON-like output
    local pr_title pr_description jira_key
    pr_title=$(echo "$pr_data" | grep -o '"title":[^,]*' | cut -d'"' -f4)
    jira_key=$(echo "$pr_data" | grep -o '"jira_key":[^,]*' | cut -d'"' -f4)
    
    # Extract description (multi-line, more complex parsing)
    pr_description=$(echo "$pr_data" | sed -n '/"description":/,/"jira_key":/p' | sed '1d;$d' | sed 's/^[[:space:]]*//' | sed 's/\\n/\n/g')
    
    # Show preview
    echo ""
    echo "📋 PR Preview:"
    echo "=============="
    echo ""
    echo "📌 Title: $pr_title"
    if [[ -n "$jira_key" ]]; then
        echo "🎯 Jira Issue: $jira_key"
    fi
    echo ""
    echo "📝 Description:"
    echo "$pr_description"
    echo ""
    
    # Handle dry run
    if [[ "$DRY_RUN" == true ]]; then
        log_info "Dry run complete - no PR created"
        echo ""
        echo "To create this PR, run without --dry-run flag"
        exit 0
    fi
    
    # Confirm creation (optional - can be made automatic)
    echo -n "Create this PR? [Y/n] "
    read -r confirm
    
    if [[ "$confirm" =~ ^[Nn] ]]; then
        log_info "PR creation cancelled"
        exit 0
    fi
    
    # Push branch if needed
    if ! push_branch_if_needed; then
        exit 1
    fi
    
    # Create the PR
    if create_github_pr "$pr_title" "$pr_description" "$BASE_BRANCH" "$DRAFT_FLAG"; then
        echo ""
        log_success "🎉 PR created with Jira integration!"
        
        if [[ -n "$jira_key" ]]; then
            echo ""
            log_info "💡 Don't forget to update the Jira issue with PR link"
        fi
    else
        exit 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi