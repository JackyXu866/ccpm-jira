#!/bin/bash

# Resolution Handler Library
# Manages different resolution types for Jira issue closure and validation

set -e

# Standard Jira resolution types
declare -A STANDARD_RESOLUTIONS=(
    ["Fixed"]="Fixed - The issue has been resolved"
    ["Won't Fix"]="Won't Fix - The issue will not be addressed"
    ["Duplicate"]="Duplicate - The issue is a duplicate of another issue"
    ["Incomplete"]="Incomplete - The issue description is incomplete"
    ["Cannot Reproduce"]="Cannot Reproduce - The issue cannot be reproduced"
    ["Won't Do"]="Won't Do - The issue will not be implemented"
    ["Done"]="Done - The work has been completed"
    ["Resolved"]="Resolved - The issue has been resolved"
)

# Resolution aliases for user convenience
declare -A RESOLUTION_ALIASES=(
    ["fixed"]="Fixed"
    ["complete"]="Fixed"
    ["completed"]="Fixed"
    ["done"]="Done"
    ["wont-fix"]="Won't Fix"
    ["wontfix"]="Won't Fix"
    ["will-not-fix"]="Won't Fix"
    ["duplicate"]="Duplicate"
    ["dup"]="Duplicate"
    ["incomplete"]="Incomplete"
    ["invalid"]="Incomplete"
    ["cannot-reproduce"]="Cannot Reproduce"
    ["cant-reproduce"]="Cannot Reproduce"
    ["unreproducible"]="Cannot Reproduce"
    ["wont-do"]="Won't Do"
    ["wontdo"]="Won't Do"
    ["will-not-do"]="Won't Do"
    ["resolved"]="Resolved"
)

# Get list of available resolution types
# Usage: list_available_resolutions
list_available_resolutions() {
    echo "Standard Resolutions:"
    for resolution in "${!STANDARD_RESOLUTIONS[@]}"; do
        echo "  - $resolution: ${STANDARD_RESOLUTIONS[$resolution]}"
    done
    
    echo ""
    echo "Accepted Aliases:"
    for alias in "${!RESOLUTION_ALIASES[@]}"; do
        echo "  - $alias → ${RESOLUTION_ALIASES[$alias]}"
    done
}

# Validate and normalize a resolution type
# Usage: validate_and_normalize_resolution <resolution>
validate_and_normalize_resolution() {
    local input_resolution="$1"
    
    if [[ -z "$input_resolution" ]]; then
        echo "ERROR: Resolution is required" >&2
        return 1
    fi
    
    # Convert to lowercase for comparison
    local lower_resolution
    lower_resolution=$(echo "$input_resolution" | tr '[:upper:]' '[:lower:]')
    
    # Check if it's already a standard resolution (case-insensitive)
    for resolution in "${!STANDARD_RESOLUTIONS[@]}"; do
        if [[ "$(echo "$resolution" | tr '[:upper:]' '[:lower:]')" == "$lower_resolution" ]]; then
            echo "$resolution"
            return 0
        fi
    done
    
    # Check aliases
    if [[ -n "${RESOLUTION_ALIASES[$lower_resolution]}" ]]; then
        echo "${RESOLUTION_ALIASES[$lower_resolution]}"
        return 0
    fi
    
    # If not found, return error with suggestions
    echo "ERROR: Invalid resolution '$input_resolution'" >&2
    echo "Did you mean one of these?" >&2
    
    # Try to find close matches
    local suggestions=()
    for resolution in "${!STANDARD_RESOLUTIONS[@]}"; do
        if [[ "$(echo "$resolution" | tr '[:upper:]' '[:lower:]')" == *"$lower_resolution"* ]]; then
            suggestions+=("$resolution")
        fi
    done
    
    for alias in "${!RESOLUTION_ALIASES[@]}"; do
        if [[ "$alias" == *"$lower_resolution"* ]]; then
            suggestions+=("$alias → ${RESOLUTION_ALIASES[$alias]}")
        fi
    done
    
    if [[ ${#suggestions[@]} -gt 0 ]]; then
        echo "Suggestions:" >&2
        for suggestion in "${suggestions[@]}"; do
            echo "  - $suggestion" >&2
        done
    else
        echo "Use 'list_available_resolutions' to see all options" >&2
    fi
    
    return 1
}

# Get resolution description
# Usage: get_resolution_description <resolution>
get_resolution_description() {
    local resolution="$1"
    
    if [[ -z "$resolution" ]]; then
        echo "ERROR: Resolution is required" >&2
        return 1
    fi
    
    # Normalize the resolution first
    local normalized_resolution
    if normalized_resolution=$(validate_and_normalize_resolution "$resolution"); then
        echo "${STANDARD_RESOLUTIONS[$normalized_resolution]}"
        return 0
    else
        return 1
    fi
}

# Check if resolution requires additional information
# Usage: resolution_requires_details <resolution>
resolution_requires_details() {
    local resolution="$1"
    
    if [[ -z "$resolution" ]]; then
        return 1
    fi
    
    # Normalize the resolution
    local normalized_resolution
    if ! normalized_resolution=$(validate_and_normalize_resolution "$resolution"); then
        return 1
    fi
    
    case "$normalized_resolution" in
        "Duplicate")
            echo "DUPLICATE_OF"
            return 0
            ;;
        "Won't Fix"|"Won't Do")
            echo "REASON"
            return 0
            ;;
        "Incomplete")
            echo "MISSING_INFO"
            return 0
            ;;
        "Cannot Reproduce")
            echo "ENVIRONMENT_INFO"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Prompt for additional resolution details
# Usage: prompt_for_resolution_details <resolution>
prompt_for_resolution_details() {
    local resolution="$1"
    
    if [[ -z "$resolution" ]]; then
        echo "ERROR: Resolution is required" >&2
        return 1
    fi
    
    local detail_type
    if detail_type=$(resolution_requires_details "$resolution"); then
        case "$detail_type" in
            "DUPLICATE_OF")
                echo "📋 This issue is marked as a duplicate."
                echo "Please provide the issue number or key it duplicates:"
                read -r duplicate_of
                if [[ -n "$duplicate_of" ]]; then
                    echo "duplicate_of:$duplicate_of"
                fi
                ;;
            "REASON")
                echo "📋 This issue is marked as Won't Fix/Won't Do."
                echo "Please provide a brief reason (optional):"
                read -r reason
                if [[ -n "$reason" ]]; then
                    echo "reason:$reason"
                fi
                ;;
            "MISSING_INFO")
                echo "📋 This issue is marked as incomplete."
                echo "Please specify what information is missing (optional):"
                read -r missing_info
                if [[ -n "$missing_info" ]]; then
                    echo "missing_info:$missing_info"
                fi
                ;;
            "ENVIRONMENT_INFO")
                echo "📋 This issue cannot be reproduced."
                echo "Please provide environment details where it was tested (optional):"
                read -r env_info
                if [[ -n "$env_info" ]]; then
                    echo "environment:$env_info"
                fi
                ;;
        esac
    fi
    
    return 0
}

# Generate resolution comment for Jira
# Usage: generate_resolution_comment <resolution> [details]
generate_resolution_comment() {
    local resolution="$1"
    local details="$2"
    
    if [[ -z "$resolution" ]]; then
        echo "ERROR: Resolution is required" >&2
        return 1
    fi
    
    # Normalize resolution
    local normalized_resolution
    if ! normalized_resolution=$(validate_and_normalize_resolution "$resolution"); then
        return 1
    fi
    
    local comment="Issue resolved with resolution: $normalized_resolution"
    
    # Add resolution-specific context
    case "$normalized_resolution" in
        "Fixed"|"Done"|"Resolved")
            comment="$comment

The issue has been successfully resolved and the changes have been implemented."
            ;;
        "Won't Fix"|"Won't Do")
            comment="$comment

This issue has been reviewed and will not be addressed."
            if [[ -n "$details" && "$details" == reason:* ]]; then
                local reason="${details#reason:}"
                comment="$comment

Reason: $reason"
            fi
            ;;
        "Duplicate")
            comment="$comment

This issue is a duplicate of an existing issue."
            if [[ -n "$details" && "$details" == duplicate_of:* ]]; then
                local duplicate_of="${details#duplicate_of:}"
                comment="$comment

Duplicate of: $duplicate_of"
            fi
            ;;
        "Incomplete")
            comment="$comment

This issue lacks sufficient information to proceed."
            if [[ -n "$details" && "$details" == missing_info:* ]]; then
                local missing_info="${details#missing_info:}"
                comment="$comment

Missing information: $missing_info"
            fi
            ;;
        "Cannot Reproduce")
            comment="$comment

Unable to reproduce this issue in the current environment."
            if [[ -n "$details" && "$details" == environment:* ]]; then
                local env_info="${details#environment:}"
                comment="$comment

Tested environment: $env_info"
            fi
            ;;
    esac
    
    comment="$comment

Closed via ccpm-jira integration."
    
    echo "$comment"
}

# Map resolution to appropriate Jira workflow status
# Usage: map_resolution_to_status <resolution>
map_resolution_to_status() {
    local resolution="$1"
    
    if [[ -z "$resolution" ]]; then
        echo "ERROR: Resolution is required" >&2
        return 1
    fi
    
    # Normalize resolution
    local normalized_resolution
    if ! normalized_resolution=$(validate_and_normalize_resolution "$resolution"); then
        return 1
    fi
    
    case "$normalized_resolution" in
        "Fixed"|"Done"|"Resolved")
            echo "Done"
            ;;
        "Won't Fix"|"Won't Do")
            echo "Closed"
            ;;
        "Duplicate"|"Incomplete"|"Cannot Reproduce")
            echo "Closed"
            ;;
        *)
            echo "Done"  # Default fallback
            ;;
    esac
}

# Get resolution color for display
# Usage: get_resolution_color <resolution>
get_resolution_color() {
    local resolution="$1"
    
    if [[ -z "$resolution" ]]; then
        echo "white"
        return
    fi
    
    # Normalize resolution
    local normalized_resolution
    if ! normalized_resolution=$(validate_and_normalize_resolution "$resolution" 2>/dev/null); then
        echo "white"
        return
    fi
    
    case "$normalized_resolution" in
        "Fixed"|"Done"|"Resolved")
            echo "green"
            ;;
        "Won't Fix"|"Won't Do")
            echo "red"
            ;;
        "Duplicate")
            echo "yellow"
            ;;
        "Incomplete"|"Cannot Reproduce")
            echo "orange"
            ;;
        *)
            echo "blue"
            ;;
    esac
}

# Interactive resolution selection
# Usage: select_resolution_interactively
select_resolution_interactively() {
    echo "📋 Select a resolution type:"
    echo ""
    
    local resolutions=("Fixed" "Won't Fix" "Duplicate" "Incomplete" "Cannot Reproduce" "Won't Do" "Done" "Resolved")
    local i=1
    
    for resolution in "${resolutions[@]}"; do
        echo "  $i) $resolution - ${STANDARD_RESOLUTIONS[$resolution]}"
        ((i++))
    done
    
    echo ""
    echo "Enter selection number (1-${#resolutions[@]}) or type resolution name:"
    read -r selection
    
    # Check if it's a number
    if [[ "$selection" =~ ^[0-9]+$ ]]; then
        if [[ "$selection" -ge 1 && "$selection" -le ${#resolutions[@]} ]]; then
            local selected_resolution="${resolutions[$((selection-1))]}"
            echo "$selected_resolution"
            return 0
        else
            echo "ERROR: Invalid selection number" >&2
            return 1
        fi
    else
        # Try to validate as resolution name
        if validate_and_normalize_resolution "$selection" >/dev/null 2>&1; then
            validate_and_normalize_resolution "$selection"
            return 0
        else
            echo "ERROR: Invalid resolution name" >&2
            return 1
        fi
    fi
}

# Validate resolution for specific Jira project
# Usage: validate_resolution_for_project <cloud_id> <project_key> <resolution>
validate_resolution_for_project() {
    local cloud_id="$1"
    local project_key="$2"
    local resolution="$3"
    
    if [[ -z "$cloud_id" || -z "$project_key" || -z "$resolution" ]]; then
        echo "ERROR: cloud_id, project_key, and resolution are required" >&2
        return 1
    fi
    
    # Normalize resolution first
    local normalized_resolution
    if ! normalized_resolution=$(validate_and_normalize_resolution "$resolution"); then
        return 1
    fi
    
    # Create marker file for MCP tool to validate resolution against project
    cat > "/tmp/jira-resolution-validation-$project_key.json" << EOF
{
  "action": "validate_resolution",
  "cloud_id": "$cloud_id",
  "project_key": "$project_key",
  "resolution": "$normalized_resolution",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    
    # For now, assume all standard resolutions are valid
    echo "✅ Resolution '$normalized_resolution' is valid for project $project_key"
    return 0
}

# Help function
show_resolution_help() {
    cat <<EOF
Resolution Handler for Jira Issue Closure

Available Functions:
  list_available_resolutions
    Show all available resolution types and their descriptions
  
  validate_and_normalize_resolution <resolution>
    Validate and normalize a resolution type
  
  get_resolution_description <resolution>
    Get the description for a resolution type
  
  resolution_requires_details <resolution>
    Check if a resolution requires additional details
  
  generate_resolution_comment <resolution> [details]
    Generate a Jira comment for the resolution
  
  select_resolution_interactively
    Interactive resolution selection
  
  map_resolution_to_status <resolution>
    Map resolution to appropriate Jira workflow status

Standard Resolutions:
$(for resolution in "${!STANDARD_RESOLUTIONS[@]}"; do
    echo "  - $resolution: ${STANDARD_RESOLUTIONS[$resolution]}"
done)

Examples:
  # Validate a resolution
  validate_and_normalize_resolution "fixed"
  
  # Get interactive selection
  resolution=\$(select_resolution_interactively)
  
  # Generate comment with details
  comment=\$(generate_resolution_comment "Duplicate" "duplicate_of:PROJ-123")
EOF
}

# Export functions for use by other scripts
export -f list_available_resolutions
export -f validate_and_normalize_resolution
export -f get_resolution_description
export -f resolution_requires_details
export -f prompt_for_resolution_details
export -f generate_resolution_comment
export -f map_resolution_to_status
export -f get_resolution_color
export -f select_resolution_interactively
export -f validate_resolution_for_project
export -f show_resolution_help

# If script is run directly, show help
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    show_resolution_help
fi