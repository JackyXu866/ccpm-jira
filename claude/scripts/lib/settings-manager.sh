#!/bin/bash
# Settings Manager - Unified settings management for CCPM

# Settings file location
SETTINGS_FILE="claude/config/settings.json"
OLD_JIRA_SETTINGS="claude/config/jira-settings.json"

# Get a setting value
# Usage: settings_get "path.to.setting"
settings_get() {
  local path="$1"
  
  if [ ! -f "$SETTINGS_FILE" ]; then
    echo ""
    return 1
  fi
  
  # Convert dot notation to jq path
  local jq_path=".${path//./\\.}"
  
  jq -r "$jq_path // \"\"" "$SETTINGS_FILE" 2>/dev/null
}

# Set a setting value
# Usage: settings_set "path.to.setting" "value"
settings_set() {
  local path="$1"
  local value="$2"
  
  # Ensure settings file exists
  if [ ! -f "$SETTINGS_FILE" ]; then
    mkdir -p "$(dirname "$SETTINGS_FILE")"
    echo '{}' > "$SETTINGS_FILE"
  fi
  
  # Convert dot notation to jq path
  local jq_path=".${path//./\\.}"
  
  # Update the setting
  local temp_file=$(mktemp)
  jq "$jq_path = \"$value\"" "$SETTINGS_FILE" > "$temp_file" && mv "$temp_file" "$SETTINGS_FILE"
}

# Validate settings structure
settings_validate() {
  if [ ! -f "$SETTINGS_FILE" ]; then
    return 1
  fi
  
  # Check for required fields
  local version=$(settings_get "version")
  if [ -z "$version" ]; then
    echo "❌ Missing version field in settings"
    return 1
  fi
  
  # Validate JSON structure
  if ! jq empty "$SETTINGS_FILE" 2>/dev/null; then
    echo "❌ Invalid JSON in settings file"
    return 1
  fi
  
  return 0
}

# Migrate from old settings format
settings_migrate() {
  # Check if migration is needed
  if [ -f "$OLD_JIRA_SETTINGS" ] && [ -s "$OLD_JIRA_SETTINGS" ]; then
    echo "🔄 Migrating Jira settings to unified format..."
    
    # Ensure base settings exists
    if [ ! -f "$SETTINGS_FILE" ]; then
      mkdir -p "$(dirname "$SETTINGS_FILE")"
      cp "$(dirname "$0")/../../config/settings.json" "$SETTINGS_FILE" 2>/dev/null || echo '{}' > "$SETTINGS_FILE"
    fi
    
    # Migrate Jira settings
    local cloud_id=$(jq -r '.cloud_id // ""' "$OLD_JIRA_SETTINGS" 2>/dev/null)
    local project_key=$(jq -r '.project_key // ""' "$OLD_JIRA_SETTINGS" 2>/dev/null)
    local project_id=$(jq -r '.project_id // ""' "$OLD_JIRA_SETTINGS" 2>/dev/null)
    
    if [ -n "$cloud_id" ]; then
      settings_set "jira.enabled" "true"
      settings_set "jira.cloud_id" "$cloud_id"
      settings_set "jira.project_key" "$project_key"
      settings_set "jira.project_id" "$project_id"
    fi
    
    # Try to detect GitHub settings from git remote
    if command -v git &> /dev/null && git remote -v | grep -q origin; then
      local remote_url=$(git remote get-url origin 2>/dev/null)
      if [[ "$remote_url" =~ github\.com[:/]([^/]+)/([^/]+)(\.git)?$ ]]; then
        local owner="${BASH_REMATCH[1]}"
        local repo="${BASH_REMATCH[2]}"
        repo="${repo%.git}"  # Remove .git suffix if present
        
        settings_set "github.owner" "$owner"
        settings_set "github.repo" "$repo"
      fi
    fi
    
    echo "✅ Settings migrated successfully"
  fi
}

# Initialize settings if needed
settings_init() {
  if [ ! -f "$SETTINGS_FILE" ]; then
    echo "📝 Creating default settings..."
    mkdir -p "$(dirname "$SETTINGS_FILE")"
    cat > "$SETTINGS_FILE" << 'EOF'
{
  "version": "2.0.0",
  "github": {
    "owner": "",
    "repo": "",
    "default_branch": "main"
  },
  "jira": {
    "enabled": false,
    "cloud_id": "",
    "project_key": "",
    "project_id": "",
    "api_version": "3",
    "field_mapping": {
      "epic_link": "customfield_10001",
      "story_points": "customfield_10002"
    }
  },
  "preferences": {
    "auto_sync": true,
    "verbose_output": false,
    "default_issue_type": "Task"
  }
}
EOF
    echo "✅ Default settings created"
  fi
  
  # Always attempt migration
  settings_migrate
}

# Export functions for use by other scripts
export -f settings_get
export -f settings_set
export -f settings_validate
export -f settings_migrate
export -f settings_init