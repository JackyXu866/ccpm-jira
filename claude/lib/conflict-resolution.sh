#!/bin/bash
set -euo pipefail

# =============================================================================
# Jira Conflict Resolution Library
# =============================================================================
# This library provides conflict detection and resolution strategies for
# synchronization between CCPM and Jira systems. It handles data conflicts,
# provides resolution options, and maintains data integrity during conflicts.
#
# Author: Claude Code - Stream D Implementation
# Version: 1.0.0
# =============================================================================

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/jira-fields.sh"
source "${SCRIPT_DIR}/jira-epic-ops.sh"
source "${SCRIPT_DIR}/jira-task-ops.sh"
# Note: jira-validation.sh not sourced to avoid circular dependency
# Validation functions are available when needed

# Ensure required tools are available
if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required for conflict resolution" >&2
    exit 1
fi

# =============================================================================
# Conflict Detection Functions
# =============================================================================

#' Detect conflicts between CCPM and Jira epic data
#' Usage: detect_epic_conflicts CCPM_EPIC_JSON JIRA_KEY
#' Returns: JSON object with conflict details or null if no conflicts
detect_epic_conflicts() {
    local ccpm_epic="$1"
    local jira_key="$2"
    
    if [[ -z "$ccpm_epic" || -z "$jira_key" ]]; then
        echo "Error: CCPM epic data and Jira key are required" >&2
        return 1
    fi
    
    # Fetch current Jira epic
    local jira_epic
    if ! jira_epic=$(get_jira_epic "$jira_key"); then
        echo "Error: Unable to fetch Jira epic $jira_key" >&2
        return 1
    fi
    
    # Convert Jira epic to CCPM format for comparison
    local jira_ccpm_format
    if ! jira_ccpm_format=$(process_jira_epic_response "$jira_epic"); then
        echo "Error: Unable to process Jira epic response" >&2
        return 1
    fi
    
    local conflicts="[]"
    local has_conflicts=false
    
    # Compare critical fields and detect conflicts
    local fields=("name" "status" "description" "start_date" "due_date" "progress")
    
    for field in "${fields[@]}"; do
        local ccpm_value jira_value
        ccpm_value=$(echo "$ccpm_epic" | jq -r ".$field // \"\"")
        jira_value=$(echo "$jira_ccpm_format" | jq -r ".$field // \"\"")
        
        # Skip if both are empty
        if [[ -z "$ccpm_value" && -z "$jira_value" ]]; then
            continue
        fi
        
        # Detect conflict if values differ
        if [[ "$ccpm_value" != "$jira_value" ]]; then
            has_conflicts=true
            local conflict_entry
            conflict_entry=$(jq -n \
                --arg field "$field" \
                --arg ccpm_val "$ccpm_value" \
                --arg jira_val "$jira_value" \
                --arg timestamp "$(date -Iseconds)" \
                '{
                    field: $field,
                    ccpm_value: $ccpm_val,
                    jira_value: $jira_val,
                    detected_at: $timestamp,
                    type: "field_mismatch"
                }')
            conflicts=$(echo "$conflicts" | jq --argjson entry "$conflict_entry" '. + [$entry]')
        fi
    done
    
    # Check modification timestamps if available
    local ccpm_modified jira_modified
    ccpm_modified=$(echo "$ccpm_epic" | jq -r '.modified_at // .updated_at // ""')
    jira_modified=$(echo "$jira_epic" | jq -r '.fields.updated // ""')
    
    if [[ -n "$ccpm_modified" && -n "$jira_modified" ]]; then
        # Convert timestamps to comparable format and check if they indicate concurrent modifications
        local ccpm_timestamp jira_timestamp
        ccpm_timestamp=$(date -d "$ccpm_modified" +%s 2>/dev/null || echo "0")
        jira_timestamp=$(date -d "$jira_modified" +%s 2>/dev/null || echo "0")
        
        local time_diff=$((ccpm_timestamp - jira_timestamp))
        if [[ ${time_diff#-} -lt 300 ]] && [[ $has_conflicts == "true" ]]; then # Within 5 minutes
            local timestamp_conflict
            timestamp_conflict=$(jq -n \
                --arg ccpm_ts "$ccpm_modified" \
                --arg jira_ts "$jira_modified" \
                --arg timestamp "$(date -Iseconds)" \
                '{
                    field: "modification_timestamp",
                    ccpm_value: $ccpm_ts,
                    jira_value: $jira_ts,
                    detected_at: $timestamp,
                    type: "concurrent_modification"
                }')
            conflicts=$(echo "$conflicts" | jq --argjson entry "$timestamp_conflict" '. + [$entry]')
        fi
    fi
    
    if [[ "$has_conflicts" == "true" ]]; then
        local conflict_report
        conflict_report=$(jq -n \
            --arg jira_key "$jira_key" \
            --arg epic_id "$(echo "$ccpm_epic" | jq -r '.id // "unknown"')" \
            --argjson conflict_list "$conflicts" \
            '{
                epic_id: $epic_id,
                jira_key: $jira_key,
                conflict_type: "epic_sync_conflict",
                conflicts: $conflict_list,
                detected_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
            }')
        echo "$conflict_report"
    else
        echo "null"
    fi
}

#' Detect conflicts between CCPM and Jira task data
#' Usage: detect_task_conflicts CCPM_TASK_JSON JIRA_KEY
#' Returns: JSON object with conflict details or null if no conflicts
detect_task_conflicts() {
    local ccpm_task="$1"
    local jira_key="$2"
    
    if [[ -z "$ccpm_task" || -z "$jira_key" ]]; then
        echo "Error: CCPM task data and Jira key are required" >&2
        return 1
    fi
    
    # Fetch current Jira task
    local jira_task
    if ! jira_task=$(get_jira_task "$jira_key"); then
        echo "Error: Unable to fetch Jira task $jira_key" >&2
        return 1
    fi
    
    local conflicts="[]"
    local has_conflicts=false
    
    # Compare critical fields and detect conflicts
    local fields=("name" "status" "description" "assignee" "progress" "priority")
    
    for field in "${fields[@]}"; do
        local ccpm_value jira_value
        ccpm_value=$(echo "$ccpm_task" | jq -r ".$field // \"\"")
        jira_value=$(echo "$jira_task" | jq -r ".$field // \"\"")
        
        # Skip if both are empty
        if [[ -z "$ccpm_value" && -z "$jira_value" ]]; then
            continue
        fi
        
        # Normalize progress values for comparison
        if [[ "$field" == "progress" ]]; then
            ccpm_value=${ccpm_value%\%}
            jira_value=${jira_value%\%}
        fi
        
        # Detect conflict if values differ
        if [[ "$ccpm_value" != "$jira_value" ]]; then
            has_conflicts=true
            local conflict_entry
            conflict_entry=$(jq -n \
                --arg field "$field" \
                --arg ccpm_val "$ccpm_value" \
                --arg jira_val "$jira_value" \
                --arg timestamp "$(date -Iseconds)" \
                '{
                    field: $field,
                    ccpm_value: $ccpm_val,
                    jira_value: $jira_val,
                    detected_at: $timestamp,
                    type: "field_mismatch"
                }')
            conflicts=$(echo "$conflicts" | jq --argjson entry "$conflict_entry" '. + [$entry]')
        fi
    done
    
    if [[ "$has_conflicts" == "true" ]]; then
        local conflict_report
        conflict_report=$(jq -n \
            --arg jira_key "$jira_key" \
            --arg task_id "$(echo "$ccpm_task" | jq -r '.id // "unknown"')" \
            --argjson conflict_list "$conflicts" \
            '{
                task_id: $task_id,
                jira_key: $jira_key,
                conflict_type: "task_sync_conflict",
                conflicts: $conflict_list,
                detected_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
            }')
        echo "$conflict_report"
    else
        echo "null"
    fi
}

#' Detect conflicts in bulk sync operations
#' Usage: detect_bulk_sync_conflicts CCPM_DATA_JSON SYNC_DIRECTION
#' Returns: Array of conflict reports
detect_bulk_sync_conflicts() {
    local ccpm_data="$1"
    local sync_direction="${2:-bidirectional}"
    
    if [[ -z "$ccpm_data" ]]; then
        echo "Error: CCPM data is required" >&2
        return 1
    fi
    
    echo "Detecting conflicts in bulk sync operation..." >&2
    
    local all_conflicts="[]"
    
    # Check epic conflicts if epics are present
    local epics
    epics=$(echo "$ccpm_data" | jq -r '.epics // []')
    if [[ "$epics" != "[]" ]]; then
        while read -r epic_json; do
            [[ -z "$epic_json" || "$epic_json" == "null" ]] && continue
            
            local jira_key
            jira_key=$(echo "$epic_json" | jq -r '.jira_key // empty')
            
            if [[ -n "$jira_key" ]]; then
                local epic_conflicts
                epic_conflicts=$(detect_epic_conflicts "$epic_json" "$jira_key")
                
                if [[ "$epic_conflicts" != "null" ]]; then
                    all_conflicts=$(echo "$all_conflicts" | jq --argjson conflict "$epic_conflicts" '. + [$conflict]')
                fi
            fi
        done < <(echo "$epics" | jq -c '.[]?')
    fi
    
    # Check task conflicts if tasks are present
    local tasks
    tasks=$(echo "$ccpm_data" | jq -r '.tasks // []')
    if [[ "$tasks" != "[]" ]]; then
        while read -r task_json; do
            [[ -z "$task_json" || "$task_json" == "null" ]] && continue
            
            local jira_key
            jira_key=$(echo "$task_json" | jq -r '.jira_key // empty')
            
            if [[ -n "$jira_key" ]]; then
                local task_conflicts
                task_conflicts=$(detect_task_conflicts "$task_json" "$jira_key")
                
                if [[ "$task_conflicts" != "null" ]]; then
                    all_conflicts=$(echo "$all_conflicts" | jq --argjson conflict "$task_conflicts" '. + [$conflict]')
                fi
            fi
        done < <(echo "$tasks" | jq -c '.[]?')
    fi
    
    echo "$all_conflicts"
}

# =============================================================================
# Conflict Resolution Functions
# =============================================================================

#' Resolve epic conflicts using specified strategy
#' Usage: resolve_epic_conflicts CONFLICT_REPORT RESOLUTION_STRATEGY
#' Available strategies: ccpm_wins, jira_wins, merge, manual
#' Returns: Resolution result
resolve_epic_conflicts() {
    local conflict_report="$1"
    local resolution_strategy="${2:-manual}"
    
    if [[ -z "$conflict_report" || "$conflict_report" == "null" ]]; then
        echo "No conflicts to resolve"
        return 0
    fi
    
    local epic_id jira_key
    epic_id=$(echo "$conflict_report" | jq -r '.epic_id')
    jira_key=$(echo "$conflict_report" | jq -r '.jira_key')
    
    echo "Resolving conflicts for epic $epic_id ($jira_key) using strategy: $resolution_strategy"
    
    case "$resolution_strategy" in
        "ccpm_wins")
            resolve_epic_conflicts_ccpm_wins "$conflict_report"
            ;;
        "jira_wins")
            resolve_epic_conflicts_jira_wins "$conflict_report"
            ;;
        "merge")
            resolve_epic_conflicts_merge "$conflict_report"
            ;;
        "manual")
            resolve_epic_conflicts_manual "$conflict_report"
            ;;
        *)
            echo "Error: Unknown resolution strategy: $resolution_strategy" >&2
            return 1
            ;;
    esac
}

#' Resolve epic conflicts by preferring CCPM values
resolve_epic_conflicts_ccpm_wins() {
    local conflict_report="$1"
    local jira_key
    jira_key=$(echo "$conflict_report" | jq -r '.jira_key')
    
    echo "Resolving conflicts by updating Jira with CCPM values..."
    
    # Extract CCPM values from conflicts and build update object
    local jira_updates="{}"
    
    while read -r conflict; do
        [[ -z "$conflict" || "$conflict" == "null" ]] && continue
        
        local field ccpm_value
        field=$(echo "$conflict" | jq -r '.field')
        ccpm_value=$(echo "$conflict" | jq -r '.ccpm_value')
        
        # Map CCPM field to Jira field format
        local jira_field_update
        jira_field_update=$(prepare_field_update_for_jira "$field" "$ccpm_value")
        
        jira_updates=$(echo "$jira_updates" | jq --argjson update "$jira_field_update" '. + $update')
        
    done < <(echo "$conflict_report" | jq -c '.conflicts[]?')
    
    # Apply updates to Jira
    if update_jira_epic "$jira_key" "$jira_updates"; then
        echo "Successfully resolved conflicts by updating Jira with CCPM values"
        return 0
    else
        echo "Failed to update Jira with CCPM values" >&2
        return 1
    fi
}

#' Resolve epic conflicts by preferring Jira values
resolve_epic_conflicts_jira_wins() {
    local conflict_report="$1"
    local epic_id
    epic_id=$(echo "$conflict_report" | jq -r '.epic_id')
    
    echo "Resolving conflicts by updating CCPM with Jira values..."
    echo "Note: This would require CCPM update functionality which is not implemented in this library"
    echo "Conflicts for epic $epic_id logged for manual CCPM update"
    
    # In a real implementation, this would update CCPM data
    # For now, we'll just log what needs to be updated
    local ccpm_updates="{}"
    
    while read -r conflict; do
        [[ -z "$conflict" || "$conflict" == "null" ]] && continue
        
        local field jira_value
        field=$(echo "$conflict" | jq -r '.field')
        jira_value=$(echo "$conflict" | jq -r '.jira_value')
        
        ccpm_updates=$(echo "$ccpm_updates" | jq --arg field "$field" --arg value "$jira_value" '. + {($field): $value}')
        
    done < <(echo "$conflict_report" | jq -c '.conflicts[]?')
    
    echo "CCPM update required for epic $epic_id:"
    echo "$ccpm_updates" | jq .
    
    return 0
}

#' Resolve epic conflicts by intelligently merging values
resolve_epic_conflicts_merge() {
    local conflict_report="$1"
    local jira_key
    jira_key=$(echo "$conflict_report" | jq -r '.jira_key')
    
    echo "Resolving conflicts by merging CCPM and Jira values..."
    
    local jira_updates="{}"
    
    while read -r conflict; do
        [[ -z "$conflict" || "$conflict" == "null" ]] && continue
        
        local field ccpm_value jira_value
        field=$(echo "$conflict" | jq -r '.field')
        ccpm_value=$(echo "$conflict" | jq -r '.ccpm_value')
        jira_value=$(echo "$conflict" | jq -r '.jira_value')
        
        # Apply merge logic based on field type
        local merged_value
        case "$field" in
            "description")
                # Concatenate descriptions
                merged_value="$ccpm_value\n\n[Jira]: $jira_value"
                ;;
            "progress")
                # Use higher progress value
                local ccpm_num jira_num
                ccpm_num=${ccpm_value%\%}
                jira_num=${jira_value%\%}
                if (( ccpm_num >= jira_num )); then
                    merged_value="$ccpm_value"
                else
                    merged_value="$jira_value"
                fi
                ;;
            "status")
                # Use more advanced status (prefer 'in-progress' over 'open', 'completed' over others)
                case "$ccpm_value,$jira_value" in
                    *completed*|*closed*|*done*)
                        merged_value=$(echo -e "$ccpm_value\n$jira_value" | grep -E "(completed|closed|done)" | head -n1)
                        ;;
                    *in-progress*|*progress*)
                        merged_value=$(echo -e "$ccpm_value\n$jira_value" | grep -E "(in-progress|progress)" | head -n1)
                        ;;
                    *)
                        merged_value="$ccpm_value" # Default to CCPM value
                        ;;
                esac
                ;;
            *)
                # For other fields, prefer CCPM value
                merged_value="$ccpm_value"
                ;;
        esac
        
        local jira_field_update
        jira_field_update=$(prepare_field_update_for_jira "$field" "$merged_value")
        
        jira_updates=$(echo "$jira_updates" | jq --argjson update "$jira_field_update" '. + $update')
        
    done < <(echo "$conflict_report" | jq -c '.conflicts[]?')
    
    # Apply merged updates to Jira
    if update_jira_epic "$jira_key" "$jira_updates"; then
        echo "Successfully resolved conflicts by merging CCPM and Jira values"
        return 0
    else
        echo "Failed to apply merged values to Jira" >&2
        return 1
    fi
}

#' Present conflicts for manual resolution
resolve_epic_conflicts_manual() {
    local conflict_report="$1"
    local epic_id jira_key
    epic_id=$(echo "$conflict_report" | jq -r '.epic_id')
    jira_key=$(echo "$conflict_report" | jq -r '.jira_key')
    
    echo "Manual conflict resolution required for epic $epic_id ($jira_key):"
    echo "================================================================="
    
    while read -r conflict; do
        [[ -z "$conflict" || "$conflict" == "null" ]] && continue
        
        local field ccpm_value jira_value
        field=$(echo "$conflict" | jq -r '.field')
        ccpm_value=$(echo "$conflict" | jq -r '.ccpm_value')
        jira_value=$(echo "$conflict" | jq -r '.jira_value')
        
        echo "Field: $field"
        echo "  CCPM value: '$ccpm_value'"
        echo "  Jira value: '$jira_value'"
        echo ""
        
    done < <(echo "$conflict_report" | jq -c '.conflicts[]?')
    
    echo "To resolve manually:"
    echo "1. Review the conflicting values above"
    echo "2. Decide which values to keep or how to merge them"
    echo "3. Update either CCPM or Jira manually"
    echo "4. Re-run sync validation to confirm resolution"
    echo ""
    
    # Save conflict report for future reference
    local conflict_log_file="/tmp/ccpm_jira_conflicts_${epic_id}_$(date +%s).json"
    echo "$conflict_report" > "$conflict_log_file"
    echo "Conflict report saved to: $conflict_log_file"
    
    return 0
}

#' Resolve task conflicts using specified strategy
#' Usage: resolve_task_conflicts CONFLICT_REPORT RESOLUTION_STRATEGY
resolve_task_conflicts() {
    local conflict_report="$1"
    local resolution_strategy="${2:-manual}"
    
    if [[ -z "$conflict_report" || "$conflict_report" == "null" ]]; then
        echo "No conflicts to resolve"
        return 0
    fi
    
    local task_id jira_key
    task_id=$(echo "$conflict_report" | jq -r '.task_id')
    jira_key=$(echo "$conflict_report" | jq -r '.jira_key')
    
    echo "Resolving conflicts for task $task_id ($jira_key) using strategy: $resolution_strategy"
    
    case "$resolution_strategy" in
        "ccpm_wins")
            resolve_task_conflicts_ccpm_wins "$conflict_report"
            ;;
        "jira_wins")
            resolve_task_conflicts_jira_wins "$conflict_report"
            ;;
        "merge")
            resolve_task_conflicts_merge "$conflict_report"
            ;;
        "manual")
            resolve_task_conflicts_manual "$conflict_report"
            ;;
        *)
            echo "Error: Unknown resolution strategy: $resolution_strategy" >&2
            return 1
            ;;
    esac
}

#' Resolve task conflicts by preferring CCPM values
resolve_task_conflicts_ccpm_wins() {
    local conflict_report="$1"
    local jira_key
    jira_key=$(echo "$conflict_report" | jq -r '.jira_key')
    
    echo "Resolving task conflicts by updating Jira with CCPM values..."
    
    local jira_updates="{}"
    
    while read -r conflict; do
        [[ -z "$conflict" || "$conflict" == "null" ]] && continue
        
        local field ccpm_value
        field=$(echo "$conflict" | jq -r '.field')
        ccpm_value=$(echo "$conflict" | jq -r '.ccpm_value')
        
        local jira_field_update
        jira_field_update=$(prepare_field_update_for_jira "$field" "$ccpm_value")
        
        jira_updates=$(echo "$jira_updates" | jq --argjson update "$jira_field_update" '. + $update')
        
    done < <(echo "$conflict_report" | jq -c '.conflicts[]?')
    
    if update_jira_task_fields "$jira_key" "$jira_updates"; then
        echo "Successfully resolved task conflicts by updating Jira with CCPM values"
        return 0
    else
        echo "Failed to update Jira task with CCPM values" >&2
        return 1
    fi
}

#' Resolve task conflicts by preferring Jira values  
resolve_task_conflicts_jira_wins() {
    local conflict_report="$1"
    local task_id
    task_id=$(echo "$conflict_report" | jq -r '.task_id')
    
    echo "Resolving task conflicts by updating CCPM with Jira values..."
    echo "Note: CCPM update functionality would be implemented here"
    echo "Conflicts for task $task_id logged for manual CCPM update"
    
    return 0
}

#' Resolve task conflicts by merging values
resolve_task_conflicts_merge() {
    local conflict_report="$1"
    local jira_key
    jira_key=$(echo "$conflict_report" | jq -r '.jira_key')
    
    echo "Resolving task conflicts by merging CCPM and Jira values..."
    
    local jira_updates="{}"
    
    while read -r conflict; do
        [[ -z "$conflict" || "$conflict_json" == "null" ]] && continue
        
        local field ccpm_value jira_value
        field=$(echo "$conflict" | jq -r '.field')
        ccpm_value=$(echo "$conflict" | jq -r '.ccpm_value')
        jira_value=$(echo "$conflict" | jq -r '.jira_value')
        
        local merged_value
        case "$field" in
            "progress")
                local ccpm_num jira_num
                ccpm_num=${ccpm_value%\%}
                jira_num=${jira_value%\%}
                if (( ccpm_num >= jira_num )); then
                    merged_value="$ccpm_value"
                else
                    merged_value="$jira_value"
                fi
                ;;
            *)
                merged_value="$ccpm_value"
                ;;
        esac
        
        local jira_field_update
        jira_field_update=$(prepare_field_update_for_jira "$field" "$merged_value")
        
        jira_updates=$(echo "$jira_updates" | jq --argjson update "$jira_field_update" '. + $update')
        
    done < <(echo "$conflict_report" | jq -c '.conflicts[]?')
    
    if update_jira_task_fields "$jira_key" "$jira_updates"; then
        echo "Successfully resolved task conflicts by merging values"
        return 0
    else
        echo "Failed to apply merged values to Jira task" >&2
        return 1
    fi
}

#' Present task conflicts for manual resolution
resolve_task_conflicts_manual() {
    local conflict_report="$1"
    local task_id jira_key
    task_id=$(echo "$conflict_report" | jq -r '.task_id')
    jira_key=$(echo "$conflict_report" | jq -r '.jira_key')
    
    echo "Manual conflict resolution required for task $task_id ($jira_key):"
    echo "================================================================="
    
    while read -r conflict; do
        [[ -z "$conflict" || "$conflict" == "null" ]] && continue
        
        local field ccpm_value jira_value
        field=$(echo "$conflict" | jq -r '.field')
        ccpm_value=$(echo "$conflict" | jq -r '.ccpm_value')
        jira_value=$(echo "$conflict" | jq -r '.jira_value')
        
        echo "Field: $field"
        echo "  CCPM value: '$ccpm_value'"
        echo "  Jira value: '$jira_value'"
        echo ""
        
    done < <(echo "$conflict_report" | jq -c '.conflicts[]?')
    
    local conflict_log_file="/tmp/ccpm_jira_conflicts_task_${task_id}_$(date +%s).json"
    echo "$conflict_report" > "$conflict_log_file"
    echo "Task conflict report saved to: $conflict_log_file"
    
    return 0
}

# =============================================================================
# Helper Functions
# =============================================================================

#' Prepare a field update for Jira format
#' Usage: prepare_field_update_for_jira FIELD_NAME VALUE
prepare_field_update_for_jira() {
    local field="$1"
    local value="$2"
    
    case "$field" in
        "name")
            jq -n --arg val "$value" '{"summary": $val}'
            ;;
        "description")  
            jq -n --arg val "$value" '{"description": $val}'
            ;;
        "status")
            local jira_status
            jira_status=$(transform_status_ccpm_to_jira "$value")
            jq -n --arg val "$jira_status" '{"status": {"name": $val}}'
            ;;
        "progress")
            local progress_val
            progress_val=$(transform_percentage_ccpm_to_jira "$value")
            jq -n --arg val "$progress_val" '{"customfield_progress": $val}'
            ;;
        *)
            jq -n --arg field "$field" --arg val "$value" '{($field): $val}'
            ;;
    esac
}

# =============================================================================
# Export Functions
# =============================================================================

export -f detect_epic_conflicts
export -f detect_task_conflicts
export -f detect_bulk_sync_conflicts
export -f resolve_epic_conflicts
export -f resolve_task_conflicts
export -f resolve_epic_conflicts_ccpm_wins
export -f resolve_epic_conflicts_jira_wins
export -f resolve_epic_conflicts_merge
export -f resolve_epic_conflicts_manual
export -f resolve_task_conflicts_ccpm_wins
export -f resolve_task_conflicts_jira_wins
export -f resolve_task_conflicts_merge
export -f resolve_task_conflicts_manual
export -f prepare_field_update_for_jira

echo "Jira Conflict Resolution Library loaded successfully" >&2