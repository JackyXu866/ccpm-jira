#!/bin/bash
set -euo pipefail

# =============================================================================
# Epic Creation Script for CCPM-Jira Integration
# =============================================================================
# This script provides a command-line interface for creating epics in Jira
# from CCPM data. It handles the complete creation workflow including
# validation, field mapping, and Jira API calls.
#
# Author: Claude Code - Stream A Implementation
# Version: 1.0.0
# =============================================================================

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/jira-epic-ops.sh"
source "${SCRIPT_DIR}/../lib/settings-manager.sh"

# Default values
DEFAULT_PROJECT_KEY=""
DEFAULT_ISSUE_TYPE="Epic"
VERBOSE_MODE=false
DRY_RUN=false

# =============================================================================
# CLI Functions
# =============================================================================

#' Display usage information
show_usage() {
    cat << 'EOF'
Epic Creation Script for CCPM-Jira Integration

USAGE:
    epic-create.sh [OPTIONS] EPIC_NAME

DESCRIPTION:
    Creates a new epic in Jira from CCPM epic data. The script handles
    field mapping, validation, and provides detailed feedback on the 
    creation process.

ARGUMENTS:
    EPIC_NAME           Name of the epic to create (required)

OPTIONS:
    -p, --project KEY   Jira project key (defaults to configured project)
    -f, --file FILE     JSON file containing epic data (optional)
    -d, --data JSON     Epic data as JSON string (optional)
    -D, --dry-run       Show what would be created without making changes
    -v, --verbose       Enable verbose output
    -h, --help          Show this help message

EXAMPLES:
    # Create epic with minimal data
    epic-create.sh "User Authentication System"

    # Create epic with custom project
    epic-create.sh -p MYPROJ "Payment Gateway Integration"

    # Create epic from JSON file
    epic-create.sh -f epic-data.json "Mobile App Redesign"

    # Create epic with inline JSON data
    epic-create.sh -d '{"description":"New feature epic","priority":"High"}' "Feature Epic"

    # Dry run to preview creation
    epic-create.sh --dry-run "Test Epic"

EPIC DATA FORMAT:
    The epic data should be a JSON object with the following structure:
    {
        "description": "Epic description",
        "priority": "High|Medium|Low",
        "labels": ["label1", "label2"],
        "start_date": "2024-01-01T00:00:00Z",
        "target_date": "2024-03-31T23:59:59Z",
        "business_value": "High customer impact",
        "theme": "User Experience",
        "acceptance_criteria": ["Criteria 1", "Criteria 2"],
        "dependencies": [2, 3],
        "custom_fields": {
            "field_name": "field_value"
        }
    }

EXIT CODES:
    0    Success
    1    Invalid arguments or options
    2    Epic creation failed
    3    Configuration error
    4    Jira connection error

EOF
}

#' Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --project requires a project key" >&2
                    exit 1
                fi
                DEFAULT_PROJECT_KEY="$2"
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
            -d|--data)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --data requires JSON data" >&2
                    exit 1
                fi
                EPIC_DATA_JSON="$2"
                shift 2
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
                if [[ -z "${EPIC_NAME:-}" ]]; then
                    EPIC_NAME="$1"
                else
                    echo "Error: Unexpected argument: $1" >&2
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Validate required arguments
    if [[ -z "${EPIC_NAME:-}" ]]; then
        echo "Error: Epic name is required" >&2
        echo "Use -h or --help for usage information" >&2
        exit 1
    fi
}

#' Load epic data from file or argument
load_epic_data() {
    local epic_data_json=""
    
    # Priority: inline data > file data > minimal default
    if [[ -n "${EPIC_DATA_JSON:-}" ]]; then
        epic_data_json="$EPIC_DATA_JSON"
        [[ "$VERBOSE_MODE" == "true" ]] && echo "Using inline epic data" >&2
    elif [[ -n "${EPIC_DATA_FILE:-}" ]]; then
        if ! epic_data_json=$(cat "$EPIC_DATA_FILE"); then
            echo "Error: Failed to read epic data file: $EPIC_DATA_FILE" >&2
            exit 1
        fi
        [[ "$VERBOSE_MODE" == "true" ]] && echo "Using epic data from file: $EPIC_DATA_FILE" >&2
    else
        # Create minimal epic data
        epic_data_json=$(jq -n \
            --arg name "$EPIC_NAME" \
            --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '{
                name: $name,
                description: "Epic created via CCPM-Jira integration",
                priority: "Medium",
                status: "open",
                created: $created,
                labels: ["ccpm-generated"]
            }')
        [[ "$VERBOSE_MODE" == "true" ]] && echo "Using minimal epic data" >&2
    fi
    
    # Validate JSON format
    if ! echo "$epic_data_json" | jq . >/dev/null 2>&1; then
        echo "Error: Invalid JSON format in epic data" >&2
        exit 1
    fi
    
    echo "$epic_data_json"
}

#' Validate epic creation requirements
validate_requirements() {
    local epic_data_json="$1"
    
    [[ "$VERBOSE_MODE" == "true" ]] && echo "Validating epic creation requirements..." >&2
    
    # Check if epic name already exists in project
    if [[ -n "$DEFAULT_PROJECT_KEY" ]]; then
        local existing_key
        existing_key=$(find_epic_by_name "$EPIC_NAME" "$DEFAULT_PROJECT_KEY" 2>/dev/null || echo "")
        
        if [[ -n "$existing_key" ]]; then
            echo "Warning: Epic with similar name already exists: $existing_key" >&2
            echo "Consider using a different name or updating the existing epic" >&2
            
            if [[ "$DRY_RUN" != "true" ]]; then
                read -p "Continue with creation anyway? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    echo "Epic creation cancelled by user" >&2
                    exit 1
                fi
            fi
        fi
    fi
    
    # Validate epic data structure
    if ! validate_ccpm_epic "$epic_data_json" 2>/dev/null; then
        echo "Warning: Epic data validation warnings detected" >&2
        [[ "$VERBOSE_MODE" == "true" ]] && validate_ccpm_epic "$epic_data_json" >&2 || true
    fi
    
    # Check Jira connectivity
    if ! validate_jira_config >/dev/null 2>&1; then
        echo "Error: Jira connection validation failed" >&2
        echo "Please check your Jira configuration and network connectivity" >&2
        exit 4
    fi
    
    [[ "$VERBOSE_MODE" == "true" ]] && echo "✅ Requirements validation completed" >&2
}

#' Display creation preview
show_creation_preview() {
    local epic_data_json="$1"
    
    echo
    echo "=== Epic Creation Preview ==="
    echo "Epic Name: $EPIC_NAME"
    echo "Project: ${DEFAULT_PROJECT_KEY:-<default>}"
    
    # Show key epic fields
    local description
    description=$(echo "$epic_data_json" | jq -r '.description // "No description"')
    echo "Description: $description"
    
    local priority
    priority=$(echo "$epic_data_json" | jq -r '.priority // "Medium"')
    echo "Priority: $priority"
    
    local labels
    labels=$(echo "$epic_data_json" | jq -r '.labels[]? // empty' | tr '\n' ',' | sed 's/,$//')
    [[ -n "$labels" ]] && echo "Labels: $labels"
    
    local start_date
    start_date=$(echo "$epic_data_json" | jq -r '.start_date // empty')
    [[ -n "$start_date" ]] && echo "Start Date: $start_date"
    
    local target_date
    target_date=$(echo "$epic_data_json" | jq -r '.target_date // empty')
    [[ -n "$target_date" ]] && echo "Target Date: $target_date"
    
    echo "=========================="
    echo
}

#' Execute epic creation
create_epic() {
    local epic_data_json="$1"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "🔍 DRY RUN: Epic would be created with the above data" >&2
        echo "To actually create the epic, remove the --dry-run flag" >&2
        return 0
    fi
    
    echo "Creating epic in Jira..." >&2
    
    # Create the epic
    local epic_key
    if epic_key=$(create_jira_epic_from_ccpm "$EPIC_NAME" "$epic_data_json" "$DEFAULT_PROJECT_KEY"); then
        echo
        echo "✅ Epic created successfully!"
        echo "Epic Key: $epic_key"
        
        # Get epic URL if possible
        local cloud_id
        cloud_id=$(get_cloud_id 2>/dev/null || echo "")
        if [[ -n "$cloud_id" ]]; then
            echo "Epic URL: https://$(echo "$cloud_id" | head -c 8).atlassian.net/browse/$epic_key"
        fi
        
        # Show epic metadata if verbose
        if [[ "$VERBOSE_MODE" == "true" ]]; then
            echo
            echo "Epic metadata:"
            get_epic_metadata "$epic_key" 2>/dev/null | jq '.' || echo "Could not retrieve metadata"
        fi
        
        return 0
    else
        echo
        echo "❌ Epic creation failed" >&2
        echo "Check the error messages above and try again" >&2
        return 2
    fi
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    # Initialize variables
    EPIC_NAME=""
    EPIC_DATA_FILE=""
    EPIC_DATA_JSON=""
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Load settings
    if command -v load_settings >/dev/null 2>&1; then
        load_settings >/dev/null 2>&1 || true
    fi
    
    # Get default project key if not specified
    if [[ -z "$DEFAULT_PROJECT_KEY" ]]; then
        DEFAULT_PROJECT_KEY=$(get_default_project_key 2>/dev/null || echo "")
    fi
    
    [[ "$VERBOSE_MODE" == "true" ]] && echo "Starting epic creation process..." >&2
    
    # Load epic data
    local epic_data
    if ! epic_data=$(load_epic_data); then
        echo "Error: Failed to load epic data" >&2
        exit 1
    fi
    
    # Validate requirements
    validate_requirements "$epic_data"
    
    # Show preview
    show_creation_preview "$epic_data"
    
    # Execute creation
    if create_epic "$epic_data"; then
        [[ "$VERBOSE_MODE" == "true" ]] && echo "Epic creation process completed successfully" >&2
        exit 0
    else
        echo "Epic creation process failed" >&2
        exit 2
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi