#!/bin/bash

# Git-Jira Integration Configuration Management
# Provides functions for managing Git-Jira integration settings

# Set script directory and config paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")/config"
GIT_INTEGRATION_CONFIG="$CONFIG_DIR/git-integration.json"

# Source required dependencies
source "$SCRIPT_DIR/../scripts/lib/settings-manager.sh" 2>/dev/null || {
  echo "Warning: settings-manager.sh not found, some functions may not work"
}

#######################################
# Load Git integration configuration
# Globals:
#   GIT_INTEGRATION_CONFIG
# Returns:
#   0 if successful, 1 if config not found
#######################################
load_git_integration_config() {
  if [ ! -f "$GIT_INTEGRATION_CONFIG" ]; then
    echo "Git integration config not found: $GIT_INTEGRATION_CONFIG" >&2
    return 1
  fi
  
  if ! command -v jq &> /dev/null; then
    echo "jq is required for Git integration configuration" >&2
    return 1
  fi
  
  return 0
}

#######################################
# Check if Git integration is enabled
# Returns:
#   0 if enabled, 1 if disabled or not configured
#######################################
is_git_integration_enabled() {
  if ! load_git_integration_config; then
    return 1
  fi
  
  local enabled
  enabled=$(jq -r '.enabled // false' "$GIT_INTEGRATION_CONFIG" 2>/dev/null)
  [ "$enabled" = "true" ]
}

#######################################
# Check if branch integration is enabled
# Returns:
#   0 if enabled, 1 if disabled
#######################################
is_branch_integration_enabled() {
  if ! is_git_integration_enabled; then
    return 1
  fi
  
  local enabled
  enabled=$(jq -r '.integration.branch.enabled // false' "$GIT_INTEGRATION_CONFIG" 2>/dev/null)
  [ "$enabled" = "true" ]
}

#######################################
# Check if commit integration is enabled
# Returns:
#   0 if enabled, 1 if disabled
#######################################
is_commit_integration_enabled() {
  if ! is_git_integration_enabled; then
    return 1
  fi
  
  local enabled
  enabled=$(jq -r '.integration.commit.enabled // false' "$GIT_INTEGRATION_CONFIG" 2>/dev/null)
  [ "$enabled" = "true" ]
}

#######################################
# Check if PR integration is enabled
# Returns:
#   0 if enabled, 1 if disabled
#######################################
is_pr_integration_enabled() {
  if ! is_git_integration_enabled; then
    return 1
  fi
  
  local enabled
  enabled=$(jq -r '.integration.pull_request.enabled // false' "$GIT_INTEGRATION_CONFIG" 2>/dev/null)
  [ "$enabled" = "true" ]
}

#######################################
# Check if backwards compatibility is enabled
# Returns:
#   0 if enabled, 1 if disabled
#######################################
is_backwards_compatibility_enabled() {
  if ! load_git_integration_config; then
    return 0  # Default to enabled for safety
  fi
  
  local enabled
  enabled=$(jq -r '.backwards_compatibility.enabled // true' "$GIT_INTEGRATION_CONFIG" 2>/dev/null)
  [ "$enabled" = "true" ]
}

#######################################
# Get branch naming format
# Outputs:
#   Branch naming format string
#######################################
get_branch_naming_format() {
  if ! load_git_integration_config; then
    echo "JIRA-{issue_key}"
    return
  fi
  
  jq -r '.integration.branch.naming_convention.format // "JIRA-{issue_key}"' "$GIT_INTEGRATION_CONFIG" 2>/dev/null
}

#######################################
# Get commit message format
# Outputs:
#   Commit message format string
#######################################
get_commit_message_format() {
  if ! load_git_integration_config; then
    echo "{issue_key}: {message}"
    return
  fi
  
  jq -r '.integration.commit.message_format.format // "{issue_key}: {message}"' "$GIT_INTEGRATION_CONFIG" 2>/dev/null
}

#######################################
# Get PR title format
# Outputs:
#   PR title format string
#######################################
get_pr_title_format() {
  if ! load_git_integration_config; then
    echo "[{issue_key}] {summary}"
    return
  fi
  
  jq -r '.integration.pull_request.title_format.format // "[{issue_key}] {summary}"' "$GIT_INTEGRATION_CONFIG" 2>/dev/null
}

#######################################
# Get PR description template
# Outputs:
#   PR description template string
#######################################
get_pr_description_template() {
  if ! load_git_integration_config; then
    echo "## Summary\\n{summary}\\n\\n## Jira Issue\\n{issue_link}"
    return
  fi
  
  jq -r '.integration.pull_request.description.template // "## Summary\\n{summary}\\n\\n## Jira Issue\\n{issue_link}"' "$GIT_INTEGRATION_CONFIG" 2>/dev/null
}

#######################################
# Check if branch name is valid according to naming convention
# Arguments:
#   branch_name - Branch name to validate
# Returns:
#   0 if valid, 1 if invalid
#######################################
is_valid_branch_name() {
  local branch_name="$1"
  
  if ! is_branch_integration_enabled; then
    return 0  # Always valid if integration disabled
  fi
  
  # Check for exception patterns
  local exceptions
  exceptions=$(jq -r '.integration.branch.validation.allow_exceptions[]? // empty' "$GIT_INTEGRATION_CONFIG" 2>/dev/null)
  
  while IFS= read -r exception; do
    if [[ "$branch_name" == $exception ]]; then
      return 0
    fi
  done <<< "$exceptions"
  
  # Check backwards compatibility patterns
  if is_backwards_compatibility_enabled; then
    local legacy_patterns
    legacy_patterns=$(jq -r '.backwards_compatibility.legacy_branch_patterns[]? // empty' "$GIT_INTEGRATION_CONFIG" 2>/dev/null)
    
    while IFS= read -r pattern; do
      if [[ "$branch_name" == $pattern ]]; then
        return 0
      fi
    done <<< "$legacy_patterns"
  fi
  
  # Check if enforcement is enabled
  local enforce
  enforce=$(jq -r '.integration.branch.validation.enforce_convention // true' "$GIT_INTEGRATION_CONFIG" 2>/dev/null)
  
  if [ "$enforce" != "true" ]; then
    return 0  # Valid if enforcement disabled
  fi
  
  # Check if branch follows Jira naming convention
  if [[ "$branch_name" =~ ^[A-Z]+-[0-9]+(-.*)?$ ]]; then
    return 0
  fi
  
  return 1
}

#######################################
# Generate branch name from Jira issue key
# Arguments:
#   issue_key - Jira issue key (e.g., PROJ-123)
#   description - Optional description for branch name
# Outputs:
#   Generated branch name
#######################################
generate_branch_name() {
  local issue_key="$1"
  local description="$2"
  
  if ! is_branch_integration_enabled; then
    echo "$issue_key"
    return
  fi
  
  local format
  format=$(get_branch_naming_format)
  
  local branch_name
  branch_name=$(echo "$format" | sed "s/{issue_key}/$issue_key/g")
  
  # Add description if enabled and provided
  local include_desc
  include_desc=$(jq -r '.integration.branch.naming_convention.include_description // false' "$GIT_INTEGRATION_CONFIG" 2>/dev/null)
  
  if [ "$include_desc" = "true" ] && [ -n "$description" ]; then
    local max_length
    max_length=$(jq -r '.integration.branch.naming_convention.max_description_length // 30' "$GIT_INTEGRATION_CONFIG" 2>/dev/null)
    
    local separator
    separator=$(jq -r '.integration.branch.naming_convention.separator // "-"' "$GIT_INTEGRATION_CONFIG" 2>/dev/null)
    
    # Sanitize and truncate description
    local clean_desc
    clean_desc=$(echo "$description" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
    clean_desc="${clean_desc:0:$max_length}"
    
    branch_name="${branch_name}${separator}${clean_desc}"
  fi
  
  echo "$branch_name"
}

#######################################
# Generate commit message from Jira issue data
# Arguments:
#   issue_key - Jira issue key
#   message - Commit message
#   type - Optional commit type (feat, fix, etc.)
# Outputs:
#   Generated commit message
#######################################
generate_commit_message() {
  local issue_key="$1"
  local message="$2"
  local type="$3"
  
  if ! is_commit_integration_enabled; then
    echo "$message"
    return
  fi
  
  local include_key
  include_key=$(jq -r '.integration.commit.message_format.include_issue_key // true' "$GIT_INTEGRATION_CONFIG" 2>/dev/null)
  
  if [ "$include_key" != "true" ]; then
    echo "$message"
    return
  fi
  
  local format
  format=$(get_commit_message_format)
  
  local commit_msg
  commit_msg=$(echo "$format" | sed "s/{issue_key}/$issue_key/g" | sed "s/{message}/$message/g")
  
  if [ -n "$type" ]; then
    commit_msg=$(echo "$commit_msg" | sed "s/{type}/$type/g")
  else
    commit_msg=$(echo "$commit_msg" | sed "s/{type}: //g")
  fi
  
  echo "$commit_msg"
}

#######################################
# Update Git integration configuration
# Arguments:
#   key - Configuration key (dot notation)
#   value - New value
# Returns:
#   0 if successful, 1 if failed
#######################################
update_git_integration_config() {
  local key="$1"
  local value="$2"
  
  if ! load_git_integration_config; then
    return 1
  fi
  
  local temp_file
  temp_file=$(mktemp)
  
  if jq --arg key "$key" --arg value "$value" 'setpath($key | split("."); $value)' "$GIT_INTEGRATION_CONFIG" > "$temp_file"; then
    mv "$temp_file" "$GIT_INTEGRATION_CONFIG"
    return 0
  else
    rm -f "$temp_file"
    return 1
  fi
}

#######################################
# Enable or disable Git integration
# Arguments:
#   enabled - true or false
# Returns:
#   0 if successful, 1 if failed
#######################################
set_git_integration_enabled() {
  local enabled="$1"
  update_git_integration_config "enabled" "$enabled"
}

#######################################
# Initialize Git integration configuration
# Creates default config if it doesn't exist
# Returns:
#   0 if successful, 1 if failed
#######################################
init_git_integration_config() {
  if [ -f "$GIT_INTEGRATION_CONFIG" ]; then
    echo "Git integration configuration already exists"
    return 0
  fi
  
  echo "Initializing Git integration configuration..."
  
  # Create config directory if it doesn't exist
  mkdir -p "$CONFIG_DIR"
  
  # Copy from template or create default (this function would be called after the file is created)
  if [ ! -f "$GIT_INTEGRATION_CONFIG" ]; then
    echo "Error: Git integration configuration template not found" >&2
    return 1
  fi
  
  echo "Git integration configuration initialized at: $GIT_INTEGRATION_CONFIG"
  return 0
}

#######################################
# Validate Git integration configuration
# Returns:
#   0 if valid, 1 if invalid
#######################################
validate_git_integration_config() {
  if ! load_git_integration_config; then
    return 1
  fi
  
  # Check if config is valid JSON
  if ! jq . "$GIT_INTEGRATION_CONFIG" > /dev/null 2>&1; then
    echo "Invalid JSON in Git integration configuration" >&2
    return 1
  fi
  
  # Check required fields
  local required_fields=("version" "enabled" "integration")
  for field in "${required_fields[@]}"; do
    if ! jq -e ".$field" "$GIT_INTEGRATION_CONFIG" > /dev/null 2>&1; then
      echo "Missing required field in Git integration configuration: $field" >&2
      return 1
    fi
  done
  
  echo "Git integration configuration is valid"
  return 0
}

# Export functions for use in other scripts
export -f load_git_integration_config
export -f is_git_integration_enabled
export -f is_branch_integration_enabled
export -f is_commit_integration_enabled
export -f is_pr_integration_enabled
export -f is_backwards_compatibility_enabled
export -f get_branch_naming_format
export -f get_commit_message_format
export -f get_pr_title_format
export -f get_pr_description_template
export -f is_valid_branch_name
export -f generate_branch_name
export -f generate_commit_message
export -f update_git_integration_config
export -f set_git_integration_enabled
export -f init_git_integration_config
export -f validate_git_integration_config