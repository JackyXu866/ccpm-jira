#!/bin/bash

# =============================================================================
# Jira Configuration Management
# =============================================================================
# Functions for managing JIRA MCP integration configuration including
# loading, saving, validating, and manipulating configuration settings.
#
# Author: Claude Code
# Version: 1.0.0
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration Constants
# =============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration file paths
CONFIG_DIR="${SCRIPT_DIR}/../../config"
CONFIG_FILE="${CONFIG_DIR}/jira-settings.json"
CONFIG_BACKUP_DIR="${CONFIG_DIR}/backups"

# Default configuration template
DEFAULT_CONFIG_TEMPLATE='{
  "version": "1.0.0",
  "description": "JIRA MCP Integration Configuration",
  "cloudId": "",
  "defaultProjectKey": "",
  "authentication": {
    "method": "mcp",
    "lastValidated": null,
    "validationExpiry": null
  },
  "userPreferences": {
    "defaultIssueType": "Task",
    "defaultAssignee": "me",
    "maxResults": 50,
    "dateFormat": "YYYY-MM-DD",
    "timezone": "UTC"
  },
  "cache": {
    "enabled": true,
    "ttl": 300,
    "maxEntries": 100,
    "clearOnStartup": false
  },
  "operations": {
    "timeouts": {
      "default": 30,
      "search": 60,
      "bulk": 120
    },
    "retries": {
      "maxAttempts": 3,
      "baseDelay": 1,
      "maxDelay": 30
    }
  },
  "projects": {
    "favorites": [],
    "recent": [],
    "maxRecent": 10
  },
  "logging": {
    "level": "info",
    "enabled": true,
    "maxLogFiles": 5,
    "maxLogSize": "10MB"
  },
  "advanced": {
    "customFields": {},
    "workflows": {},
    "templates": {}
  }
}'

# =============================================================================
# Core Configuration Functions
# =============================================================================

#' Load Jira configuration from file
#' Usage: load_jira_config
#' Returns: 0 on success, 1 on failure
#' Sets global variable JIRA_CONFIG with parsed JSON
load_jira_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "Warning: Configuration file not found at $CONFIG_FILE" >&2
        echo "Use 'jira-init.sh' to create initial configuration" >&2
        return 1
    fi
    
    # Validate JSON format
    if ! jq . "$CONFIG_FILE" >/dev/null 2>&1; then
        echo "Error: Configuration file contains invalid JSON" >&2
        echo "File: $CONFIG_FILE" >&2
        return 1
    fi
    
    # Load configuration into global variable
    JIRA_CONFIG=$(cat "$CONFIG_FILE")
    
    # Validate required fields
    local cloud_id
    cloud_id=$(echo "$JIRA_CONFIG" | jq -r '.cloudId // empty')
    
    if [[ -z "$cloud_id" ]]; then
        echo "Warning: No cloud ID configured" >&2
        echo "Run 'jira-init.sh' to complete setup" >&2
    fi
    
    return 0
}

#' Save Jira configuration to file
#' Usage: save_jira_config CONFIG_JSON
#' Returns: 0 on success, 1 on failure
save_jira_config() {
    local config_json="${1:-}"
    
    if [[ -z "$config_json" ]]; then
        echo "Error: Configuration JSON is required" >&2
        return 1
    fi
    
    # Validate JSON format
    if ! echo "$config_json" | jq . >/dev/null 2>&1; then
        echo "Error: Invalid JSON configuration" >&2
        return 1
    fi
    
    # Create configuration directory if it doesn't exist
    mkdir -p "$CONFIG_DIR"
    
    # Create backup if config file already exists
    if [[ -f "$CONFIG_FILE" ]]; then
        backup_config || {
            echo "Warning: Failed to create backup, proceeding anyway" >&2
        }
    fi
    
    # Write configuration to file with pretty formatting
    if echo "$config_json" | jq . > "$CONFIG_FILE"; then
        echo "Configuration saved to $CONFIG_FILE" >&2
        
        # Update global variable
        JIRA_CONFIG="$config_json"
        return 0
    else
        echo "Error: Failed to write configuration file" >&2
        return 1
    fi
}

#' Validate Jira configuration structure and values
#' Usage: validate_jira_config [CONFIG_JSON]
#' Returns: 0 if valid, 1 if invalid
validate_jira_config() {
    local config_json="${1:-$JIRA_CONFIG}"
    
    if [[ -z "$config_json" ]]; then
        echo "Error: No configuration to validate" >&2
        return 1
    fi
    
    # Parse JSON and validate structure
    if ! echo "$config_json" | jq . >/dev/null 2>&1; then
        echo "❌ Invalid JSON format" >&2
        return 1
    fi
    
    local validation_errors=0
    
    # Check required fields
    local cloud_id
    cloud_id=$(echo "$config_json" | jq -r '.cloudId // empty')
    if [[ -z "$cloud_id" ]]; then
        echo "❌ Missing required field: cloudId" >&2
        validation_errors=$((validation_errors + 1))
    elif ! validate_cloud_id "$cloud_id"; then
        echo "❌ Invalid cloudId format: $cloud_id" >&2
        validation_errors=$((validation_errors + 1))
    fi
    
    # Check version field
    local version
    version=$(echo "$config_json" | jq -r '.version // empty')
    if [[ -z "$version" ]]; then
        echo "⚠️  Missing version field (non-critical)" >&2
    fi
    
    # Validate timeout values
    local default_timeout
    default_timeout=$(echo "$config_json" | jq -r '.operations.timeouts.default // empty')
    if [[ -n "$default_timeout" && "$default_timeout" -le 0 ]]; then
        echo "❌ Invalid default timeout: $default_timeout" >&2
        validation_errors=$((validation_errors + 1))
    fi
    
    # Validate retry configuration
    local max_attempts
    max_attempts=$(echo "$config_json" | jq -r '.operations.retries.maxAttempts // empty')
    if [[ -n "$max_attempts" && "$max_attempts" -le 0 ]]; then
        echo "❌ Invalid max retry attempts: $max_attempts" >&2
        validation_errors=$((validation_errors + 1))
    fi
    
    # Validate cache TTL
    local cache_ttl
    cache_ttl=$(echo "$config_json" | jq -r '.cache.ttl // empty')
    if [[ -n "$cache_ttl" && "$cache_ttl" -le 0 ]]; then
        echo "❌ Invalid cache TTL: $cache_ttl" >&2
        validation_errors=$((validation_errors + 1))
    fi
    
    if [[ $validation_errors -eq 0 ]]; then
        echo "✅ Configuration validation passed" >&2
        return 0
    else
        echo "❌ Configuration validation failed with $validation_errors errors" >&2
        return 1
    fi
}

#' Get a configuration value by JSON path
#' Usage: get_config_value JSON_PATH [DEFAULT_VALUE]
#' Example: get_config_value ".cloudId"
#' Returns: Configuration value or default
get_config_value() {
    local json_path="${1:-}"
    local default_value="${2:-}"
    
    if [[ -z "$json_path" ]]; then
        echo "Error: JSON path is required" >&2
        return 1
    fi
    
    # Load config if not already loaded
    if [[ -z "${JIRA_CONFIG:-}" ]]; then
        load_jira_config || return 1
    fi
    
    local value
    value=$(echo "$JIRA_CONFIG" | jq -r "$json_path // empty" 2>/dev/null)
    
    if [[ -n "$value" && "$value" != "null" ]]; then
        echo "$value"
    elif [[ -n "$default_value" ]]; then
        echo "$default_value"
    else
        return 1
    fi
}

#' Set a configuration value by JSON path
#' Usage: set_config_value JSON_PATH VALUE [SAVE_IMMEDIATELY]
#' Example: set_config_value ".defaultProjectKey" "MYPROJ" true
#' Returns: 0 on success, 1 on failure
set_config_value() {
    local json_path="${1:-}"
    local value="${2:-}"
    local save_immediately="${3:-true}"
    
    if [[ -z "$json_path" || -z "$value" ]]; then
        echo "Error: JSON path and value are required" >&2
        return 1
    fi
    
    # Load config if not already loaded
    if [[ -z "${JIRA_CONFIG:-}" ]]; then
        load_jira_config || return 1
    fi
    
    # Update the configuration
    local updated_config
    if updated_config=$(echo "$JIRA_CONFIG" | jq "$json_path = \"$value\"" 2>/dev/null); then
        JIRA_CONFIG="$updated_config"
        
        # Save immediately if requested
        if [[ "$save_immediately" == "true" ]]; then
            save_jira_config "$JIRA_CONFIG"
        fi
        
        return 0
    else
        echo "Error: Failed to update configuration value at path: $json_path" >&2
        return 1
    fi
}

# =============================================================================
# Validation Helper Functions
# =============================================================================

#' Validate cloud ID format (UUID)
#' Usage: validate_cloud_id CLOUD_ID
validate_cloud_id() {
    local cloud_id="$1"
    
    # Check if it's a valid UUID format
    if [[ "$cloud_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        return 0
    fi
    
    # Check if it's a valid Atlassian site URL
    if [[ "$cloud_id" =~ ^https?://[a-zA-Z0-9-]+\.atlassian\.net/?$ ]]; then
        return 0
    fi
    
    return 1
}

#' Validate project key format
#' Usage: validate_project_key PROJECT_KEY
validate_project_key() {
    local project_key="$1"
    
    # Project keys should be 2-10 uppercase characters, numbers, or underscores
    if [[ "$project_key" =~ ^[A-Z0-9_]{2,10}$ ]]; then
        return 0
    fi
    
    return 1
}

# =============================================================================
# Configuration Management Functions
# =============================================================================

#' Create a backup of the current configuration
#' Usage: backup_config
backup_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        return 0  # Nothing to backup
    fi
    
    mkdir -p "$CONFIG_BACKUP_DIR"
    
    local timestamp
    timestamp=$(date '+%Y%m%d-%H%M%S')
    local backup_file="${CONFIG_BACKUP_DIR}/jira-settings-${timestamp}.json"
    
    if cp "$CONFIG_FILE" "$backup_file"; then
        echo "Configuration backed up to: $backup_file" >&2
        
        # Keep only the last 10 backups
        cleanup_old_backups
        return 0
    else
        echo "Error: Failed to create configuration backup" >&2
        return 1
    fi
}

#' Clean up old configuration backups
cleanup_old_backups() {
    if [[ -d "$CONFIG_BACKUP_DIR" ]]; then
        # Keep only the 10 most recent backups
        find "$CONFIG_BACKUP_DIR" -name "jira-settings-*.json" -type f | sort -r | tail -n +11 | xargs -r rm -f
    fi
}

#' Reset configuration to default values
#' Usage: reset_config [BACKUP_FIRST]
reset_config() {
    local backup_first="${1:-true}"
    
    if [[ "$backup_first" == "true" && -f "$CONFIG_FILE" ]]; then
        backup_config
    fi
    
    echo "$DEFAULT_CONFIG_TEMPLATE" | jq . > "$CONFIG_FILE"
    JIRA_CONFIG="$DEFAULT_CONFIG_TEMPLATE"
    
    echo "Configuration reset to default values" >&2
}

#' List configuration backups
list_config_backups() {
    if [[ -d "$CONFIG_BACKUP_DIR" ]]; then
        echo "Available configuration backups:"
        find "$CONFIG_BACKUP_DIR" -name "jira-settings-*.json" -type f | sort -r | while read -r backup_file; do
            local timestamp
            timestamp=$(stat -c "%Y" "$backup_file" 2>/dev/null || echo "0")
            local human_time
            human_time=$(date -d "@$timestamp" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
            echo "  $(basename "$backup_file") ($human_time)"
        done
    else
        echo "No configuration backups found"
    fi
}

#' Restore configuration from backup
#' Usage: restore_config BACKUP_FILENAME
restore_config() {
    local backup_filename="${1:-}"
    
    if [[ -z "$backup_filename" ]]; then
        echo "Error: Backup filename is required" >&2
        list_config_backups
        return 1
    fi
    
    local backup_file="${CONFIG_BACKUP_DIR}/${backup_filename}"
    
    if [[ ! -f "$backup_file" ]]; then
        echo "Error: Backup file not found: $backup_file" >&2
        list_config_backups
        return 1
    fi
    
    # Validate backup before restoring
    if ! jq . "$backup_file" >/dev/null 2>&1; then
        echo "Error: Backup file contains invalid JSON: $backup_file" >&2
        return 1
    fi
    
    # Create backup of current config before restoring
    backup_config
    
    # Restore from backup
    if cp "$backup_file" "$CONFIG_FILE"; then
        JIRA_CONFIG=$(cat "$CONFIG_FILE")
        echo "Configuration restored from: $backup_file" >&2
        return 0
    else
        echo "Error: Failed to restore configuration from backup" >&2
        return 1
    fi
}

# =============================================================================
# Configuration Display Functions
# =============================================================================

#' Display current configuration in human-readable format
show_config() {
    if ! load_jira_config; then
        return 1
    fi
    
    echo "Current JIRA Configuration:"
    echo "========================="
    
    echo
    echo "Basic Settings:"
    echo "  Cloud ID: $(get_config_value '.cloudId' 'Not configured')"
    echo "  Default Project: $(get_config_value '.defaultProjectKey' 'Not configured')"
    echo "  Version: $(get_config_value '.version' 'Unknown')"
    
    echo
    echo "User Preferences:"
    echo "  Default Issue Type: $(get_config_value '.userPreferences.defaultIssueType')"
    echo "  Default Assignee: $(get_config_value '.userPreferences.defaultAssignee')"
    echo "  Max Results: $(get_config_value '.userPreferences.maxResults')"
    echo "  Date Format: $(get_config_value '.userPreferences.dateFormat')"
    echo "  Timezone: $(get_config_value '.userPreferences.timezone')"
    
    echo
    echo "Cache Settings:"
    echo "  Enabled: $(get_config_value '.cache.enabled')"
    echo "  TTL: $(get_config_value '.cache.ttl') seconds"
    echo "  Max Entries: $(get_config_value '.cache.maxEntries')"
    
    echo
    echo "Operation Settings:"
    echo "  Default Timeout: $(get_config_value '.operations.timeouts.default') seconds"
    echo "  Max Retries: $(get_config_value '.operations.retries.maxAttempts')"
    
    echo
    echo "Authentication:"
    echo "  Method: $(get_config_value '.authentication.method')"
    echo "  Last Validated: $(get_config_value '.authentication.lastValidated' 'Never')"
}

# =============================================================================
# Authentication Functions
# =============================================================================

#' Verify MCP authentication by testing user info call
#' Usage: verify_mcp_authentication [CLOUD_ID]
#' Returns: 0 if authenticated, 1 if not
verify_mcp_authentication() {
    local cloud_id="${1:-}"
    
    # Get cloud_id from config if not provided
    if [[ -z "$cloud_id" ]]; then
        if ! load_jira_config; then
            echo "Error: No configuration available for authentication test" >&2
            return 1
        fi
        cloud_id=$(get_config_value '.cloudId')
    fi
    
    if [[ -z "$cloud_id" ]]; then
        echo "Error: No cloud ID available for authentication test" >&2
        return 1
    fi
    
    # Test authentication with a simple user info call
    local auth_params="{}"
    local result
    
    echo "Testing authentication for cloud ID: $cloud_id" >&2
    
    # Use MCP helper function to test connection
    if command -v invoke_mcp_tool >/dev/null 2>&1; then
        if result=$(invoke_mcp_tool "mcp__atlassian__atlassianUserInfo" "$auth_params" 2>/dev/null); then
            echo "✅ Authentication successful" >&2
            
            # Update last validated timestamp
            update_auth_timestamp
            return 0
        else
            echo "❌ Authentication failed" >&2
            return 1
        fi
    else
        echo "⚠️  MCP helper not available, skipping auth test" >&2
        return 0  # Don't fail if we can't test
    fi
}

#' Test connection to Atlassian cloud instance
#' Usage: test_cloud_connection CLOUD_ID
#' Returns: 0 if connection successful, 1 if failed
test_cloud_connection() {
    local cloud_id="$1"
    
    if [[ -z "$cloud_id" ]]; then
        echo "Error: Cloud ID is required for connection test" >&2
        return 1
    fi
    
    echo "Testing connection to cloud instance: $cloud_id" >&2
    
    # Test getting accessible resources
    local test_params="{}"
    
    if command -v invoke_mcp_tool >/dev/null 2>&1; then
        if invoke_mcp_tool "mcp__atlassian__getAccessibleAtlassianResources" "$test_params" >/dev/null 2>&1; then
            echo "✅ Cloud connection successful" >&2
            return 0
        else
            echo "❌ Cloud connection failed" >&2
            echo "   Please verify your cloud ID and network connectivity" >&2
            return 1
        fi
    else
        echo "⚠️  Cannot test connection - MCP tools not available" >&2
        return 0
    fi
}

#' Update authentication timestamp in configuration
#' Usage: update_auth_timestamp [SUCCESS]
update_auth_timestamp() {
    local success="${1:-true}"
    local timestamp
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    
    if [[ "$success" == "true" ]]; then
        # Set validation timestamp and expiry (24 hours)
        local expiry
        expiry=$(date -u -d '+1 day' '+%Y-%m-%dT%H:%M:%SZ')
        
        set_config_value '.authentication.lastValidated' "$timestamp" false
        set_config_value '.authentication.validationExpiry' "$expiry" true
    else
        # Clear validation on failure
        set_config_value '.authentication.lastValidated' "null" false
        set_config_value '.authentication.validationExpiry' "null" true
    fi
}

#' Check if authentication is still valid (not expired)
#' Usage: is_auth_valid
#' Returns: 0 if valid, 1 if expired or never validated
is_auth_valid() {
    if ! load_jira_config; then
        return 1
    fi
    
    local expiry
    expiry=$(get_config_value '.authentication.validationExpiry' '')
    
    if [[ -z "$expiry" || "$expiry" == "null" ]]; then
        return 1  # Never validated
    fi
    
    # Check if current time is before expiry
    local current_time
    current_time=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    
    if [[ "$current_time" < "$expiry" ]]; then
        return 0  # Still valid
    else
        return 1  # Expired
    fi
}

#' Validate project access for a given project key
#' Usage: validate_project_access PROJECT_KEY [CLOUD_ID]
#' Returns: 0 if accessible, 1 if not
validate_project_access() {
    local project_key="$1"
    local cloud_id="${2:-}"
    
    if [[ -z "$project_key" ]]; then
        echo "Error: Project key is required" >&2
        return 1
    fi
    
    # Get cloud_id from config if not provided
    if [[ -z "$cloud_id" ]]; then
        if ! load_jira_config; then
            echo "Error: No configuration available" >&2
            return 1
        fi
        cloud_id=$(get_config_value '.cloudId')
    fi
    
    if [[ -z "$cloud_id" ]]; then
        echo "Error: No cloud ID available" >&2
        return 1
    fi
    
    echo "Validating access to project: $project_key" >&2
    
    # Try to get visible projects and check if our project is in the list
    local projects_params="{\"cloudId\":\"$cloud_id\",\"action\":\"view\"}"
    
    if command -v invoke_mcp_tool >/dev/null 2>&1; then
        local result
        if result=$(invoke_mcp_tool "mcp__atlassian__getVisibleJiraProjects" "$projects_params" 2>/dev/null); then
            # Check if project key exists in the response
            if echo "$result" | jq -e ".values[] | select(.key == \"$project_key\")" >/dev/null 2>&1; then
                echo "✅ Project access confirmed: $project_key" >&2
                
                # Add to recent projects list
                add_recent_project "$project_key"
                return 0
            else
                echo "❌ Project not accessible: $project_key" >&2
                echo "   You may not have permission or the project doesn't exist" >&2
                return 1
            fi
        else
            echo "❌ Failed to validate project access" >&2
            return 1
        fi
    else
        echo "⚠️  Cannot validate project access - MCP tools not available" >&2
        return 0
    fi
}

#' Add project to recent projects list
#' Usage: add_recent_project PROJECT_KEY
add_recent_project() {
    local project_key="$1"
    
    if [[ -z "$project_key" ]]; then
        return 1
    fi
    
    if ! load_jira_config; then
        return 1
    fi
    
    # Get current recent projects
    local recent_projects
    recent_projects=$(get_config_value '.projects.recent' '[]')
    
    # Remove project if it already exists, then add to front
    local updated_recent
    updated_recent=$(echo "$recent_projects" | jq --arg key "$project_key" \
        'map(select(. != $key)) | [$key] + . | .[0:10]')
    
    set_config_value '.projects.recent' "$updated_recent" true
}

#' Comprehensive authentication and access validation
#' Usage: full_authentication_check [PROJECT_KEY]
#' Returns: 0 if all checks pass, 1 if any fail
full_authentication_check() {
    local project_key="${1:-}"
    local validation_passed=true
    
    echo "Performing comprehensive authentication check..." >&2
    echo >&2
    
    # Load configuration
    if ! load_jira_config; then
        echo "❌ Configuration check failed" >&2
        validation_passed=false
    else
        echo "✅ Configuration loaded successfully" >&2
    fi
    
    # Get cloud ID
    local cloud_id
    cloud_id=$(get_config_value '.cloudId' '')
    
    if [[ -z "$cloud_id" ]]; then
        echo "❌ No cloud ID configured" >&2
        validation_passed=false
    else
        echo "✅ Cloud ID found: $cloud_id" >&2
        
        # Test cloud connection
        if test_cloud_connection "$cloud_id"; then
            echo "✅ Cloud connection verified" >&2
        else
            echo "❌ Cloud connection failed" >&2
            validation_passed=false
        fi
        
        # Test MCP authentication
        if verify_mcp_authentication "$cloud_id"; then
            echo "✅ MCP authentication verified" >&2
        else
            echo "❌ MCP authentication failed" >&2
            validation_passed=false
        fi
    fi
    
    # Test project access if project key provided
    if [[ -n "$project_key" ]]; then
        if validate_project_access "$project_key" "$cloud_id"; then
            echo "✅ Project access verified: $project_key" >&2
        else
            echo "❌ Project access failed: $project_key" >&2
            validation_passed=false
        fi
    fi
    
    # Check auth validity
    if is_auth_valid; then
        echo "✅ Authentication is current and valid" >&2
    else
        echo "⚠️  Authentication may be expired or not validated" >&2
    fi
    
    echo >&2
    if [[ "$validation_passed" == "true" ]]; then
        echo "🎉 All authentication checks passed!" >&2
        return 0
    else
        echo "💥 Some authentication checks failed. Please review the errors above." >&2
        return 1
    fi
}

# =============================================================================
# Initialization
# =============================================================================

# Initialize global configuration variable
JIRA_CONFIG=""

# Check for jq dependency
if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required for configuration management but not found" >&2
    echo "Please install jq: https://jqlang.github.io/jq/download/" >&2
    exit 1
fi