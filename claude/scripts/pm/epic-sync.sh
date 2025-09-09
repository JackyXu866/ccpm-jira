#!/bin/bash
set -euo pipefail

# =============================================================================
# Epic Synchronization Script for CCPM-Jira Integration
# =============================================================================
# This script provides bidirectional synchronization between CCPM epics and
# Jira epics. It handles both push (CCPM -> Jira) and pull (Jira -> CCPM)
# operations with conflict detection and resolution strategies.
#
# Author: Claude Code - Stream A Implementation
# Version: 1.0.0
# =============================================================================

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/jira-epic-ops.sh"
source "${SCRIPT_DIR}/../lib/settings-manager.sh"

# Default values
SYNC_DIRECTION="auto"
PROJECT_KEY=""
VERBOSE_MODE=false
DRY_RUN=false
FORCE_SYNC=false
CONFLICT_RESOLUTION="prompt"

# =============================================================================
# CLI Functions
# =============================================================================

#' Display usage information
show_usage() {
    cat << 'EOF'
Epic Synchronization Script for CCPM-Jira Integration

USAGE:
    epic-sync.sh [OPTIONS] [EPIC_IDENTIFIER]

DESCRIPTION:
    Synchronizes epics between CCPM and Jira in either direction. Handles
    conflict detection, field mapping, and provides detailed sync reports.

ARGUMENTS:
    EPIC_IDENTIFIER     Epic name (for push) or Jira key (for pull)
                       If omitted, syncs all epics in project

OPTIONS:
    -d, --direction DIR Sync direction: push|pull|auto (default: auto)
    -p, --project KEY   Jira project key for filtering
    -f, --file FILE     CCPM epic data file (for push operations)
    -j, --json JSON     CCPM epic data as JSON (for push operations)
    -r, --resolve MODE  Conflict resolution: prompt|ccmp|jira|skip (default: prompt)
    -F, --force         Force sync, overriding conflict checks
    -D, --dry-run       Show what would be synced without making changes
    -v, --verbose       Enable verbose output
    -h, --help          Show this help message

SYNC DIRECTIONS:
    push                Sync from CCPM to Jira (create/update in Jira)
    pull                Sync from Jira to CCPM (read from Jira)
    auto                Auto-detect based on identifier format

CONFLICT RESOLUTION:
    prompt              Prompt user for resolution (default)
    ccpm                Always use CCPM data (force push)
    jira                Always use Jira data (force pull) 
    skip                Skip conflicting items

EXAMPLES:
    # Auto-sync specific epic (detects direction)
    epic-sync.sh "User Authentication System"

    # Push CCMP epic to Jira
    epic-sync.sh --direction push "Payment Gateway"

    # Pull Jira epic to CCPM
    epic-sync.sh --direction pull PROJ-123

    # Sync from file
    epic-sync.sh --direction push --file epic-data.json "Mobile App"

    # Bulk sync all epics in project
    epic-sync.sh --project MYPROJ

    # Dry run with force resolution
    epic-sync.sh --dry-run --resolve jira --project MYPROJ

    # Force sync ignoring conflicts
    epic-sync.sh --force --direction push "Feature Epic"

SYNC REPORT FORMAT:
    The sync operation returns a JSON report with:
    - Sync direction and timestamp
    - Items processed and their outcomes
    - Conflicts detected and resolutions
    - Errors and warnings
    - Summary statistics

EXIT CODES:
    0    Success - all items synced
    1    Invalid arguments or options
    2    Sync failed - critical errors
    3    Partial success - some items failed
    4    Configuration or connectivity error
    5    User cancelled sync

EOF
}

#' Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--direction)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --direction requires a value (push|pull|auto)" >&2
                    exit 1
                fi
                case "$2" in
                    push|pull|auto)
                        SYNC_DIRECTION="$2"
                        ;;
                    *)
                        echo "Error: Invalid sync direction: $2" >&2
                        echo "Valid options: push, pull, auto" >&2
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            -p|--project)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --project requires a project key" >&2
                    exit 1
                fi
                PROJECT_KEY="$2"
                shift 2
                ;;
            -f|--file)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --file requires a file path" >&2
                    exit 1
                fi
                if [[ ! -f "$2" ]]; then
                    echo "Error: File not found: $2" >&2
                    exit 1
                fi
                EPIC_DATA_FILE="$2"
                shift 2
                ;;
            -j|--json)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --json requires JSON data" >&2
                    exit 1
                fi
                EPIC_DATA_JSON="$2"
                shift 2
                ;;
            -r|--resolve)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --resolve requires a value" >&2
                    exit 1
                fi
                case "$2" in
                    prompt|ccpm|jira|skip)
                        CONFLICT_RESOLUTION="$2"
                        ;;
                    *)
                        echo "Error: Invalid conflict resolution: $2" >&2
                        echo "Valid options: prompt, ccpm, jira, skip" >&2
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            -F|--force)
                FORCE_SYNC=true
                shift
                ;;
            -D|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE_MODE=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                echo "Error: Unknown option $1" >&2
                echo "Use -h or --help for usage information" >&2
                exit 1
                ;;
            *)
                if [[ -z "${EPIC_IDENTIFIER:-}" ]]; then
                    EPIC_IDENTIFIER="$1"
                else
                    echo "Error: Unexpected argument: $1" >&2
                    exit 1
                fi
                shift
                ;;
        esac
    done
}

# =============================================================================
# Sync Detection and Planning
# =============================================================================

#' Auto-detect sync direction based on identifier format
auto_detect_sync_direction() {
    local identifier="${1:-}"
    
    if [[ -z "$identifier" ]]; then
        # No identifier = bulk sync, default to pull
        echo "pull"
        return
    fi
    
    # Check if identifier looks like a Jira key (PROJECT-123)
    if [[ "$identifier" =~ ^[A-Z][A-Z0-9]+-[0-9]+$ ]]; then
        echo "pull"
    else
        # Assume it's an epic name for push
        echo "push"
    fi
}

#' Plan sync operation
plan_sync() {
    local identifier="${1:-}"
    
    # Detect sync direction if auto
    if [[ "$SYNC_DIRECTION" == "auto" ]]; then
        SYNC_DIRECTION=$(auto_detect_sync_direction "$identifier")
        [[ "$VERBOSE_MODE" == "true" ]] && echo "Auto-detected sync direction: $SYNC_DIRECTION" >&2
    fi
    
    # Build sync plan
    local sync_plan
    
    if [[ "$SYNC_DIRECTION" == "push" ]]; then
        sync_plan=$(plan_push_sync "$identifier")
    elif [[ "$SYNC_DIRECTION" == "pull" ]]; then
        sync_plan=$(plan_pull_sync "$identifier")
    else
        echo "Error: Invalid sync direction: $SYNC_DIRECTION" >&2
        return 1
    fi
    
    echo "$sync_plan"
}

#' Plan push (CCPM -> Jira) sync operation
plan_push_sync() {
    local epic_name="${1:-}"
    
    if [[ -z "$epic_name" ]]; then
        echo "Error: Epic name required for push sync" >&2
        return 1
    fi
    
    # Load epic data
    local epic_data=""
    if [[ -n "${EPIC_DATA_JSON:-}" ]]; then
        epic_data="$EPIC_DATA_JSON"
    elif [[ -n "${EPIC_DATA_FILE:-}" ]]; then
        epic_data=$(cat "$EPIC_DATA_FILE")
    else
        echo "Error: Epic data required for push sync (use --file or --json)" >&2
        return 1
    fi
    
    # Validate epic data
    if ! echo "$epic_data" | jq . >/dev/null 2>&1; then
        echo "Error: Invalid JSON in epic data" >&2
        return 1
    fi
    
    # Check if epic already exists in Jira
    local existing_key=""
    existing_key=$(find_epic_by_name "$epic_name" "$PROJECT_KEY" 2>/dev/null || echo "")
    
    local operation="create"
    if [[ -n "$existing_key" ]]; then
        operation="update"
    fi
    
    # Build plan
    local plan
    plan=$(jq -n \
        --arg direction "push" \
        --arg epic_name "$epic_name" \
        --arg operation "$operation" \
        --arg existing_key "$existing_key" \
        --arg project_key "$PROJECT_KEY" \
        --argjson epic_data "$epic_data" \
        '{
            direction: $direction,
            epic_name: $epic_name,
            operation: $operation,
            existing_key: $existing_key,
            project_key: $project_key,
            epic_data: $epic_data
        }')
    
    echo "$plan"
}

#' Plan pull (Jira -> CCPM) sync operation
plan_pull_sync() {
    local identifier="${1:-}"
    
    local epics_to_sync=()
    
    if [[ -n "$identifier" ]]; then
        # Single epic sync
        if [[ "$identifier" =~ ^[A-Z][A-Z0-9]+-[0-9]+$ ]]; then
            # Identifier is a Jira key
            epics_to_sync=("$identifier")
        else
            # Identifier is an epic name, find the key
            local epic_key
            epic_key=$(find_epic_by_name "$identifier" "$PROJECT_KEY" 2>/dev/null || echo "")
            if [[ -n "$epic_key" ]]; then
                epics_to_sync=("$epic_key")
            else
                echo "Error: Epic not found in Jira: $identifier" >&2
                return 1
            fi
        fi
    else
        # Bulk sync - find all epics in project
        local jql_query="type = Epic"
        if [[ -n "$PROJECT_KEY" ]]; then
            jql_query="$jql_query AND project = $PROJECT_KEY"
        fi
        
        local search_result
        if search_result=$(search_jira_issues "$jql_query" 100); then
            while IFS= read -r key; do
                [[ -n "$key" && "$key" != "null" ]] && epics_to_sync+=("$key")
            done < <(echo "$search_result" | jq -r '.issues[]?.key // empty')
        else
            echo "Error: Failed to search for epics in Jira" >&2
            return 1
        fi
    fi
    
    if [[ ${#epics_to_sync[@]} -eq 0 ]]; then
        echo "Warning: No epics found to sync" >&2
        epics_to_sync=()
    fi
    
    # Build plan
    local plan
    plan=$(jq -n \
        --arg direction "pull" \
        --arg project_key "$PROJECT_KEY" \
        --argjson epic_keys "$(printf '%s\n' "${epics_to_sync[@]}" | jq -R . | jq -s .)" \
        '{
            direction: $direction,
            project_key: $project_key,
            epic_keys: $epic_keys,
            count: ($epic_keys | length)
        }')
    
    echo "$plan"
}

# =============================================================================
# Sync Execution
# =============================================================================

#' Execute sync operation
execute_sync() {
    local sync_plan="$1"
    
    local direction
    direction=$(echo "$sync_plan" | jq -r '.direction')
    
    case "$direction" in
        "push")
            execute_push_sync "$sync_plan"
            ;;
        "pull")
            execute_pull_sync "$sync_plan"
            ;;
        *)
            echo "Error: Invalid sync direction in plan: $direction" >&2
            return 1
            ;;
    esac
}

#' Execute push sync (CCPM -> Jira)
execute_push_sync() {
    local sync_plan="$1"
    
    local epic_name
    epic_name=$(echo "$sync_plan" | jq -r '.epic_name')
    
    local operation
    operation=$(echo "$sync_plan" | jq -r '.operation')
    
    local existing_key
    existing_key=$(echo "$sync_plan" | jq -r '.existing_key // ""')
    
    local epic_data
    epic_data=$(echo "$sync_plan" | jq -c '.epic_data')
    
    local project_key
    project_key=$(echo "$sync_plan" | jq -r '.project_key // ""')
    
    echo "=== Push Sync: $epic_name ===" >&2
    echo "Operation: $operation" >&2
    [[ -n "$existing_key" ]] && echo "Existing Epic: $existing_key" >&2
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "🔍 DRY RUN: Would $operation epic with data:" >&2
        echo "$epic_data" | jq '.' >&2
        
        local result
        result=$(jq -n \
            --arg epic_name "$epic_name" \
            --arg operation "$operation" \
            --arg existing_key "$existing_key" \
            --arg status "dry-run" \
            '{
                epic_name: $epic_name,
                operation: $operation,
                existing_key: $existing_key,
                status: $status,
                dry_run: true
            }')
        echo "$result"
        return 0
    fi
    
    # Check for conflicts unless forced
    if [[ "$FORCE_SYNC" != "true" && "$operation" == "update" ]]; then
        if ! handle_sync_conflicts "$existing_key" "$epic_data"; then
            local result
            result=$(jq -n \
                --arg epic_name "$epic_name" \
                --arg operation "$operation" \
                --arg existing_key "$existing_key" \
                --arg status "conflict-cancelled" \
                '{
                    epic_name: $epic_name,
                    operation: $operation,
                    existing_key: $existing_key,
                    status: $status,
                    error: "Sync cancelled due to conflicts"
                }')
            echo "$result"
            return 1
        fi
    fi
    
    # Execute the sync
    local sync_result
    if sync_result=$(sync_epic_to_jira "$epic_name" "$epic_data" "$project_key" "$operation"); then
        echo "✅ Push sync completed successfully" >&2
        echo "$sync_result"
        return 0
    else
        echo "❌ Push sync failed" >&2
        local result
        result=$(jq -n \
            --arg epic_name "$epic_name" \
            --arg operation "$operation" \
            --arg status "failed" \
            '{
                epic_name: $epic_name,
                operation: $operation,
                status: $status,
                error: "Sync operation failed"
            }')
        echo "$result"
        return 1
    fi
}

#' Execute pull sync (Jira -> CCPM)
execute_pull_sync() {
    local sync_plan="$1"
    
    local epic_keys_json
    epic_keys_json=$(echo "$sync_plan" | jq -c '.epic_keys')
    
    local count
    count=$(echo "$sync_plan" | jq -r '.count')
    
    echo "=== Pull Sync: $count epics ===" >&2
    
    local results=()
    local success_count=0
    local error_count=0
    
    while IFS= read -r epic_key; do
        [[ -z "$epic_key" ]] && continue
        
        echo "Syncing epic: $epic_key" >&2
        
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "🔍 DRY RUN: Would pull epic $epic_key" >&2
            
            local result
            result=$(jq -n \
                --arg epic_key "$epic_key" \
                --arg status "dry-run" \
                '{
                    epic_key: $epic_key,
                    status: $status,
                    dry_run: true
                }')
            results+=("$result")
            ((success_count++))
        else
            # Execute pull sync
            local sync_result
            if sync_result=$(sync_epic_from_jira "$epic_key"); then
                echo "✅ Pulled epic: $epic_key" >&2
                results+=("$sync_result")
                ((success_count++))
            else
                echo "❌ Failed to pull epic: $epic_key" >&2
                local error_result
                error_result=$(jq -n \
                    --arg epic_key "$epic_key" \
                    --arg status "failed" \
                    '{
                        epic_key: $epic_key,
                        status: $status,
                        error: "Failed to sync from Jira"
                    }')
                results+=("$error_result")
                ((error_count++))
            fi
        fi
        
    done < <(echo "$epic_keys_json" | jq -r '.[]')
    
    # Build final result
    local final_result
    final_result=$(jq -n \
        --arg direction "pull" \
        --arg total "$count" \
        --arg success "$success_count" \
        --arg errors "$error_count" \
        --argjson results "$(printf '%s\n' "${results[@]}" | jq -s '.')" \
        '{
            direction: $direction,
            total: ($total | tonumber),
            success: ($success | tonumber),
            errors: ($errors | tonumber),
            results: $results
        }')
    
    echo "$final_result"
    
    if [[ "$error_count" -gt 0 ]]; then
        return 3  # Partial success
    else
        return 0
    fi
}

# =============================================================================
# Conflict Resolution
# =============================================================================

#' Handle sync conflicts
handle_sync_conflicts() {
    local epic_key="$1"
    local epic_data="$2"
    
    if [[ "$FORCE_SYNC" == "true" ]]; then
        return 0
    fi
    
    echo "Checking for conflicts on epic: $epic_key" >&2
    
    if check_epic_update_conflicts "$epic_key" "$epic_data"; then
        echo "No conflicts detected" >&2
        return 0
    fi
    
    echo "⚠️ Sync conflicts detected!" >&2
    
    case "$CONFLICT_RESOLUTION" in
        "prompt")
            prompt_conflict_resolution
            ;;
        "ccmp")
            echo "Resolving conflicts: Using CCPM data (force push)" >&2
            return 0
            ;;
        "jira")
            echo "Resolving conflicts: Using Jira data (skip update)" >&2
            return 1
            ;;
        "skip")
            echo "Resolving conflicts: Skipping conflicted epic" >&2
            return 1
            ;;
        *)
            echo "Unknown conflict resolution mode: $CONFLICT_RESOLUTION" >&2
            return 1
            ;;
    esac
}

#' Prompt user for conflict resolution
prompt_conflict_resolution() {
    echo "Choose conflict resolution:" >&2
    echo "  1) Use CCPM data (overwrite Jira)" >&2
    echo "  2) Use Jira data (skip update)" >&2
    echo "  3) Skip this epic" >&2
    echo "  4) Cancel sync" >&2
    
    while true; do
        read -p "Enter choice (1-4): " -n 1 -r
        echo
        
        case $REPLY in
            1)
                echo "Using CCPM data (force push)" >&2
                return 0
                ;;
            2)
                echo "Using Jira data (skip update)" >&2
                return 1
                ;;
            3)
                echo "Skipping epic" >&2
                return 1
                ;;
            4)
                echo "Sync cancelled by user" >&2
                exit 5
                ;;
            *)
                echo "Invalid choice. Please enter 1-4" >&2
                ;;
        esac
    done
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    # Initialize variables
    EPIC_IDENTIFIER=""
    EPIC_DATA_FILE=""
    EPIC_DATA_JSON=""
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Load settings
    if command -v load_settings >/dev/null 2>&1; then
        load_settings >/dev/null 2>&1 || true
    fi
    
    # Get default project key if not specified
    if [[ -z "$PROJECT_KEY" ]]; then
        PROJECT_KEY=$(get_default_project_key 2>/dev/null || echo "")
    fi
    
    [[ "$VERBOSE_MODE" == "true" ]] && echo "Starting epic synchronization..." >&2
    
    # Validate Jira connectivity
    if ! validate_jira_config >/dev/null 2>&1; then
        echo "Error: Jira connection validation failed" >&2
        exit 4
    fi
    
    # Plan sync operation
    local sync_plan
    if ! sync_plan=$(plan_sync "${EPIC_IDENTIFIER:-}"); then
        echo "Error: Failed to plan sync operation" >&2
        exit 1
    fi
    
    # Show sync plan if verbose
    if [[ "$VERBOSE_MODE" == "true" ]]; then
        echo "Sync plan:" >&2
        echo "$sync_plan" | jq '.' >&2
    fi
    
    # Execute sync
    local sync_result
    if sync_result=$(execute_sync "$sync_plan"); then
        # Display results
        echo
        echo "=== Sync Results ==="
        echo "$sync_result" | jq '.'
        
        # Check for partial success
        local error_count
        error_count=$(echo "$sync_result" | jq -r '.errors // 0')
        
        if [[ "$error_count" -gt 0 ]]; then
            echo "⚠️ Sync completed with $error_count errors" >&2
            exit 3
        else
            echo "✅ Sync completed successfully" >&2
            exit 0
        fi
    else
        echo "❌ Sync failed" >&2
        exit 2
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi