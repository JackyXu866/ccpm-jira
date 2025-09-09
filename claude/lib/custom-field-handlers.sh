#!/bin/bash
set -euo pipefail

# =============================================================================
# Jira Custom Field Handlers
# =============================================================================
# This library provides specialized handlers for CCPM-specific custom fields
# that require special processing when mapping to/from Jira.
#
# Author: Claude Code - Stream C Implementation
# Version: 1.0.0
# =============================================================================

# Source core field mapping library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/jira-fields.sh"

# =============================================================================
# Epic Custom Field Handlers
# =============================================================================

#' Handle epic progress field mapping
#' Usage: handle_epic_progress_field PROGRESS_VALUE DIRECTION
#' DIRECTION: "to_jira" or "from_jira"
#' Returns: Transformed progress value
handle_epic_progress_field() {
    local progress_value="$1"
    local direction="$2"
    
    case "$direction" in
        "to_jira")
            # CCPM: "75%" -> Jira: 75 (numeric)
            progress_value=${progress_value%\%}
            if [[ "$progress_value" =~ ^[0-9]+$ ]] && (( progress_value >= 0 && progress_value <= 100 )); then
                echo "$progress_value"
            else
                echo "0"
            fi
            ;;
        "from_jira")
            # Jira: 75 (numeric) -> CCPM: "75%"
            if [[ "$progress_value" =~ ^[0-9]+$ ]]; then
                echo "${progress_value}%"
            else
                echo "0%"
            fi
            ;;
        *)
            echo "Error: Invalid direction: $direction" >&2
            return 1
            ;;
    esac
}

#' Handle epic PRD link field mapping
#' Usage: handle_epic_prd_field PRD_VALUE DIRECTION
#' Returns: Transformed PRD value
handle_epic_prd_field() {
    local prd_value="$1"
    local direction="$2"
    
    case "$direction" in
        "to_jira"|"from_jira")
            # PRD links are preserved as-is, but we validate the format
            if [[ -n "$prd_value" ]]; then
                # Check if it's a relative path to .claude/prds/
                if [[ "$prd_value" =~ ^\.claude/prds/.+\.md$ ]]; then
                    echo "$prd_value"
                elif [[ "$prd_value" =~ ^https?:// ]]; then
                    echo "$prd_value"
                else
                    echo "Warning: Invalid PRD link format: $prd_value" >&2
                    echo "$prd_value"
                fi
            else
                echo ""
            fi
            ;;
        *)
            echo "Error: Invalid direction: $direction" >&2
            return 1
            ;;
    esac
}

#' Handle GitHub issue link field
#' Usage: handle_github_field GITHUB_VALUE DIRECTION
#' Returns: Transformed GitHub value
handle_github_field() {
    local github_value="$1"
    local direction="$2"
    
    case "$direction" in
        "to_jira"|"from_jira")
            # GitHub URLs should be preserved, but validated
            if [[ -n "$github_value" ]]; then
                if [[ "$github_value" =~ ^https://github\.com/.+/issues/[0-9]+$ ]]; then
                    echo "$github_value"
                else
                    echo "Warning: Invalid GitHub issue URL: $github_value" >&2
                    echo "$github_value"
                fi
            else
                echo ""
            fi
            ;;
        *)
            echo "Error: Invalid direction: $direction" >&2
            return 1
            ;;
    esac
}

# =============================================================================
# Task Custom Field Handlers  
# =============================================================================

#' Handle task dependencies field mapping
#' Usage: handle_task_dependencies_field DEPS_VALUE DIRECTION
#' Returns: Transformed dependencies value
handle_task_dependencies_field() {
    local deps_value="$1"
    local direction="$2"
    
    case "$direction" in
        "to_jira")
            # CCPM: [2, 3] -> Jira: ["PROJ-2", "PROJ-3"] (assuming task IDs map to issue keys)
            if echo "$deps_value" | jq -e . >/dev/null 2>&1; then
                # Convert numeric task IDs to issue keys
                local converted_deps
                converted_deps=$(echo "$deps_value" | jq -r '.[] | "TASK-" + (. | tostring)' | jq -n '[inputs]')
                echo "$converted_deps"
            else
                echo "[]"
            fi
            ;;
        "from_jira")
            # Jira: ["PROJ-2", "PROJ-3"] -> CCPM: [2, 3]
            if echo "$deps_value" | jq -e . >/dev/null 2>&1; then
                # Extract numeric IDs from issue keys
                local converted_deps
                converted_deps=$(echo "$deps_value" | jq -r '.[] | split("-")[1] | tonumber' | jq -n '[inputs]')
                echo "$converted_deps"
            else
                echo "[]"
            fi
            ;;
        *)
            echo "Error: Invalid direction: $direction" >&2
            return 1
            ;;
    esac
}

#' Handle task parallel execution field
#' Usage: handle_task_parallel_field PARALLEL_VALUE DIRECTION
#' Returns: Transformed parallel value
handle_task_parallel_field() {
    local parallel_value="$1"
    local direction="$2"
    
    case "$direction" in
        "to_jira")
            # CCPM: true/false -> Jira: true/false (boolean)
            case "$parallel_value" in
                "true"|"True"|"TRUE"|"1"|"yes"|"Yes"|"YES")
                    echo "true"
                    ;;
                *)
                    echo "false"
                    ;;
            esac
            ;;
        "from_jira")
            # Jira: true/false -> CCPM: true/false
            case "$parallel_value" in
                "true"|"True"|"TRUE")
                    echo "true"
                    ;;
                *)
                    echo "false"
                    ;;
            esac
            ;;
        *)
            echo "Error: Invalid direction: $direction" >&2
            return 1
            ;;
    esac
}

#' Handle task conflicts field mapping
#' Usage: handle_task_conflicts_field CONFLICTS_VALUE DIRECTION
#' Returns: Transformed conflicts value
handle_task_conflicts_field() {
    local conflicts_value="$1"
    local direction="$2"
    
    case "$direction" in
        "to_jira")
            # CCPM: [4, 5] -> Jira: ["TASK-4", "TASK-5"]
            if echo "$conflicts_value" | jq -e . >/dev/null 2>&1; then
                local converted_conflicts
                converted_conflicts=$(echo "$conflicts_value" | jq -r '.[] | "TASK-" + (. | tostring)' | jq -n '[inputs]')
                echo "$converted_conflicts"
            else
                echo "[]"
            fi
            ;;
        "from_jira")
            # Jira: ["TASK-4", "TASK-5"] -> CCPM: [4, 5]
            if echo "$conflicts_value" | jq -e . >/dev/null 2>&1; then
                local converted_conflicts
                converted_conflicts=$(echo "$conflicts_value" | jq -r '.[] | split("-")[1] | tonumber' | jq -n '[inputs]')
                echo "$converted_conflicts"
            else
                echo "[]"
            fi
            ;;
        *)
            echo "Error: Invalid direction: $direction" >&2
            return 1
            ;;
    esac
}

# =============================================================================
# CCPM-Specific Data Handlers
# =============================================================================

#' Handle CCPM start_date field (custom CCPM field not in frontmatter)
#' Usage: handle_start_date_field DATE_VALUE DIRECTION
#' Returns: Transformed date value
handle_start_date_field() {
    local date_value="$1"
    local direction="$2"
    
    case "$direction" in
        "to_jira")
            # CCPM: "2025-09-09" -> Jira: "2025-09-09T00:00:00.000Z"
            if [[ "$date_value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
                echo "${date_value}T00:00:00.000Z"
            elif [[ "$date_value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T.+Z?$ ]]; then
                echo "$date_value"
            else
                echo "Warning: Invalid start date format: $date_value" >&2
                echo ""
            fi
            ;;
        "from_jira")
            # Jira: "2025-09-09T00:00:00.000Z" -> CCPM: "2025-09-09"
            if [[ "$date_value" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}).* ]]; then
                echo "${BASH_REMATCH[1]}"
            else
                echo "$date_value"
            fi
            ;;
        *)
            echo "Error: Invalid direction: $direction" >&2
            return 1
            ;;
    esac
}

#' Handle CCPM due_date field
#' Usage: handle_due_date_field DATE_VALUE DIRECTION  
#' Returns: Transformed date value
handle_due_date_field() {
    local date_value="$1"
    local direction="$2"
    
    # Due date handling is similar to start date
    handle_start_date_field "$date_value" "$direction"
}

#' Handle CCPM effort estimation fields
#' Usage: handle_effort_field EFFORT_VALUE DIRECTION EFFORT_TYPE
#' EFFORT_TYPE: "hours", "story_points", "size"
#' Returns: Transformed effort value
handle_effort_field() {
    local effort_value="$1"
    local direction="$2"
    local effort_type="$3"
    
    case "$effort_type" in
        "hours")
            case "$direction" in
                "to_jira")
                    # CCPM: "12" -> Jira: 12 (numeric)
                    if [[ "$effort_value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                        echo "$effort_value"
                    else
                        echo "0"
                    fi
                    ;;
                "from_jira")
                    # Jira: 12 -> CCPM: "12"
                    echo "$effort_value"
                    ;;
            esac
            ;;
        "size")
            case "$direction" in
                "to_jira")
                    # CCPM: "L" -> Jira story points mapping
                    case "$effort_value" in
                        "XS") echo "1" ;;
                        "S") echo "3" ;;
                        "M") echo "5" ;;
                        "L") echo "8" ;;
                        "XL") echo "13" ;;
                        "XXL") echo "21" ;;
                        *) echo "5" ;; # Default to Medium
                    esac
                    ;;
                "from_jira")
                    # Jira story points -> CCPM size
                    case "$effort_value" in
                        1) echo "XS" ;;
                        2|3) echo "S" ;;
                        4|5) echo "M" ;;
                        6|7|8) echo "L" ;;
                        9|10|11|12|13) echo "XL" ;;
                        *) echo "XXL" ;;
                    esac
                    ;;
            esac
            ;;
        "story_points")
            case "$direction" in
                "to_jira"|"from_jira")
                    # Story points are numeric in both systems
                    if [[ "$effort_value" =~ ^[0-9]+$ ]]; then
                        echo "$effort_value"
                    else
                        echo "0"
                    fi
                    ;;
            esac
            ;;
        *)
            echo "Error: Unknown effort type: $effort_type" >&2
            return 1
            ;;
    esac
}

# =============================================================================
# Custom Field Mapping Functions
# =============================================================================

#' Get custom field mapping for a specific field
#' Usage: get_custom_field_mapping ENTITY_TYPE FIELD_NAME
#' ENTITY_TYPE: "epic" or "task"
#' Returns: Jira custom field key
get_custom_field_mapping() {
    local entity_type="$1"
    local field_name="$2"
    
    if [[ -z "$entity_type" || -z "$field_name" ]]; then
        echo "Error: Entity type and field name are required" >&2
        return 1
    fi
    
    local field_key
    field_key=$(jq -r --arg type "${entity_type}_fields" --arg field "$field_name" '.custom_field_definitions[$type][$field].jira_key // empty' "$FIELD_MAPPING_CONFIG")
    
    if [[ -n "$field_key" && "$field_key" != "null" ]]; then
        echo "$field_key"
    else
        echo "Warning: No custom field mapping found for $entity_type.$field_name" >&2
        echo ""
    fi
}

#' Apply custom field transformations to a JSON object
#' Usage: apply_custom_field_transformations JSON_DATA ENTITY_TYPE DIRECTION
#' Returns: JSON with custom fields transformed
apply_custom_field_transformations() {
    local json_data="$1"
    local entity_type="$2" 
    local direction="$3"
    
    if [[ -z "$json_data" || -z "$entity_type" || -z "$direction" ]]; then
        echo "Error: All parameters are required" >&2
        return 1
    fi
    
    local result="$json_data"
    
    # Apply transformations based on entity type
    case "$entity_type" in
        "epic")
            # Handle epic-specific custom fields
            local progress_value
            progress_value=$(echo "$result" | jq -r '.progress // empty')
            if [[ -n "$progress_value" && "$progress_value" != "null" ]]; then
                local transformed_progress
                transformed_progress=$(handle_epic_progress_field "$progress_value" "$direction")
                result=$(echo "$result" | jq --arg prog "$transformed_progress" '.progress = $prog')
            fi
            
            local prd_value
            prd_value=$(echo "$result" | jq -r '.prd // empty')
            if [[ -n "$prd_value" && "$prd_value" != "null" ]]; then
                local transformed_prd
                transformed_prd=$(handle_epic_prd_field "$prd_value" "$direction")
                result=$(echo "$result" | jq --arg prd "$transformed_prd" '.prd = $prd')
            fi
            ;;
        "task")
            # Handle task-specific custom fields
            local deps_value
            deps_value=$(echo "$result" | jq -r '.depends_on // empty')
            if [[ -n "$deps_value" && "$deps_value" != "null" && "$deps_value" != "[]" ]]; then
                local transformed_deps
                transformed_deps=$(handle_task_dependencies_field "$deps_value" "$direction")
                result=$(echo "$result" | jq --argjson deps "$transformed_deps" '.depends_on = $deps')
            fi
            
            local parallel_value
            parallel_value=$(echo "$result" | jq -r '.parallel // empty')
            if [[ -n "$parallel_value" && "$parallel_value" != "null" ]]; then
                local transformed_parallel
                transformed_parallel=$(handle_task_parallel_field "$parallel_value" "$direction")
                result=$(echo "$result" | jq --arg par "$transformed_parallel" '.parallel = ($par == "true")')
            fi
            
            local conflicts_value  
            conflicts_value=$(echo "$result" | jq -r '.conflicts_with // empty')
            if [[ -n "$conflicts_value" && "$conflicts_value" != "null" && "$conflicts_value" != "[]" ]]; then
                local transformed_conflicts
                transformed_conflicts=$(handle_task_conflicts_field "$conflicts_value" "$direction")
                result=$(echo "$result" | jq --argjson conf "$transformed_conflicts" '.conflicts_with = $conf')
            fi
            ;;
        *)
            echo "Warning: Unknown entity type for custom field transformation: $entity_type" >&2
            ;;
    esac
    
    # Handle common fields (GitHub, dates)
    local github_value
    github_value=$(echo "$result" | jq -r '.github // empty')
    if [[ -n "$github_value" && "$github_value" != "null" ]]; then
        local transformed_github
        transformed_github=$(handle_github_field "$github_value" "$direction")
        result=$(echo "$result" | jq --arg gh "$transformed_github" '.github = $gh')
    fi
    
    echo "$result"
}

# =============================================================================
# Validation Functions for Custom Fields
# =============================================================================

#' Validate custom field values before transformation
#' Usage: validate_custom_fields JSON_DATA ENTITY_TYPE
#' Returns: Success/failure status
validate_custom_fields() {
    local json_data="$1"
    local entity_type="$2"
    
    if [[ -z "$json_data" || -z "$entity_type" ]]; then
        echo "Error: JSON data and entity type are required" >&2
        return 1
    fi
    
    local validation_errors=0
    
    case "$entity_type" in
        "epic")
            # Validate epic progress
            local progress
            progress=$(echo "$json_data" | jq -r '.progress // empty')
            if [[ -n "$progress" ]]; then
                progress=${progress%\%}
                if ! [[ "$progress" =~ ^[0-9]+$ ]] || (( progress < 0 || progress > 100 )); then
                    echo "Error: Invalid epic progress value: $progress" >&2
                    validation_errors=$((validation_errors + 1))
                fi
            fi
            ;;
        "task")
            # Validate task dependencies array
            local deps
            deps=$(echo "$json_data" | jq -r '.depends_on // empty')
            if [[ -n "$deps" && "$deps" != "[]" ]]; then
                if ! echo "$deps" | jq -e '. | type == "array"' >/dev/null 2>&1; then
                    echo "Error: Task dependencies must be an array" >&2
                    validation_errors=$((validation_errors + 1))
                fi
            fi
            ;;
    esac
    
    return $validation_errors
}

# =============================================================================
# Export Functions
# =============================================================================

# Export custom field handler functions
export -f handle_epic_progress_field
export -f handle_epic_prd_field
export -f handle_github_field
export -f handle_task_dependencies_field
export -f handle_task_parallel_field
export -f handle_task_conflicts_field
export -f handle_start_date_field
export -f handle_due_date_field
export -f handle_effort_field
export -f get_custom_field_mapping
export -f apply_custom_field_transformations
export -f validate_custom_fields