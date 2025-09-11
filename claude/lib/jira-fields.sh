#!/bin/bash
set -euo pipefail

# =============================================================================
# Jira Field Mapping Library
# =============================================================================
# This library provides field mapping and transformation functions between
# CCPM and Jira data models. It serves as the core translation layer for
# Stream A (Epic Operations) and Stream B (Issue Operations).
#
# Author: Claude Code - Stream C Implementation
# Version: 1.0.0
# =============================================================================

# Source helper libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/../config"
FIELD_MAPPING_CONFIG="${CONFIG_DIR}/field-mapping.json"

# Ensure jq is available for JSON processing
if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required for field mapping operations" >&2
    exit 1
fi

# =============================================================================
# Core Field Mapping Functions
# =============================================================================

#' Load field mapping configuration
#' Usage: load_field_mapping_config
#' Returns: Success/failure status
load_field_mapping_config() {
    if [[ ! -f "$FIELD_MAPPING_CONFIG" ]]; then
        echo "Error: Field mapping configuration not found: $FIELD_MAPPING_CONFIG" >&2
        return 1
    fi
    
    # Validate JSON structure
    if ! jq . "$FIELD_MAPPING_CONFIG" >/dev/null 2>&1; then
        echo "Error: Invalid JSON in field mapping configuration" >&2
        return 1
    fi
    
    return 0
}

#' Map CCPM epic fields to Jira format
#' Usage: map_ccpm_epic_to_jira CCPM_JSON
#' Returns: Jira-formatted JSON
map_ccpm_epic_to_jira() {
    local ccpm_json="$1"
    
    if [[ -z "$ccpm_json" ]]; then
        echo "Error: CCPM JSON is required" >&2
        return 1
    fi
    
    if ! load_field_mapping_config; then
        return 1
    fi
    
    # Extract epic mappings
    local epic_mappings
    epic_mappings=$(jq -r '.epic_mappings.ccpm_to_jira' "$FIELD_MAPPING_CONFIG")
    
    # Start building Jira fields JSON
    local jira_fields="{}"
    
    # Process each field mapping
    while read -r ccpm_field; do
        [[ -z "$ccpm_field" || "$ccpm_field" == "null" ]] && continue
        
        local ccpm_value
        ccpm_value=$(echo "$ccpm_json" | jq -r ".$ccpm_field // empty")
        
        [[ -z "$ccpm_value" || "$ccpm_value" == "null" ]] && continue
        
        # Get field mapping info
        local mapping_info
        mapping_info=$(echo "$epic_mappings" | jq -r ".[\"$ccpm_field\"]")
        
        if [[ "$mapping_info" == "null" ]]; then
            continue
        fi
        
        local jira_target
        jira_target=$(echo "$mapping_info" | jq -r '.target // empty')
        
        local transform_type
        transform_type=$(echo "$mapping_info" | jq -r '.transform // "preserve"')
        
        [[ -z "$jira_target" ]] && continue
        
        # Transform the value
        local transformed_value
        if ! transformed_value=$(transform_field_value "$ccpm_value" "$transform_type"); then
            echo "Warning: Failed to transform field $ccpm_field with value $ccpm_value" >&2
            continue
        fi
        
        # Add to Jira fields
        jira_fields=$(echo "$jira_fields" | jq --arg key "$jira_target" --arg value "$transformed_value" '. + {($key): $value}')
        
    done < <(echo "$epic_mappings" | jq -r 'keys[]')
    
    echo "$jira_fields"
}

#' Map Jira epic fields to CCPM format
#' Usage: map_jira_epic_to_ccpm JIRA_JSON
#' Returns: CCPM-formatted JSON
map_jira_epic_to_ccpm() {
    local jira_json="$1"
    
    if [[ -z "$jira_json" ]]; then
        echo "Error: Jira JSON is required" >&2
        return 1
    fi
    
    if ! load_field_mapping_config; then
        return 1
    fi
    
    # Extract reverse mappings
    local reverse_mappings
    reverse_mappings=$(jq -r '.epic_mappings.jira_to_ccpm' "$FIELD_MAPPING_CONFIG")
    
    # Start building CCPM fields JSON
    local ccpm_fields="{}"
    
    # Process each field mapping
    while read -r jira_field; do
        [[ -z "$jira_field" || "$jira_field" == "null" ]] && continue
        
        local jira_value
        jira_value=$(echo "$jira_json" | jq -r ".$jira_field // empty")
        
        [[ -z "$jira_value" || "$jira_value" == "null" ]] && continue
        
        # Get field mapping info
        local mapping_info
        mapping_info=$(echo "$reverse_mappings" | jq -r ".[\"$jira_field\"]")
        
        if [[ "$mapping_info" == "null" ]]; then
            continue
        fi
        
        local ccpm_target
        ccpm_target=$(echo "$mapping_info" | jq -r '.target // empty')
        
        local transform_type
        transform_type=$(echo "$mapping_info" | jq -r '.transform // "preserve"')
        
        [[ -z "$ccpm_target" ]] && continue
        
        # Transform the value
        local transformed_value
        if ! transformed_value=$(transform_field_value "$jira_value" "$transform_type"); then
            echo "Warning: Failed to transform field $jira_field with value $jira_value" >&2
            continue
        fi
        
        # Add to CCPM fields
        ccpm_fields=$(echo "$ccpm_fields" | jq --arg key "$ccpm_target" --arg value "$transformed_value" '. + {($key): $value}')
        
    done < <(echo "$reverse_mappings" | jq -r 'keys[]')
    
    echo "$ccpm_fields"
}

#' Map CCPM task fields to Jira format
#' Usage: map_ccpm_task_to_jira CCPM_JSON
#' Returns: Jira-formatted JSON
map_ccpm_task_to_jira() {
    local ccpm_json="$1"
    
    if [[ -z "$ccpm_json" ]]; then
        echo "Error: CCPM JSON is required" >&2
        return 1
    fi
    
    if ! load_field_mapping_config; then
        return 1
    fi
    
    # Extract task mappings
    local task_mappings
    task_mappings=$(jq -r '.task_mappings.ccpm_to_jira' "$FIELD_MAPPING_CONFIG")
    
    # Start building Jira fields JSON
    local jira_fields="{}"
    
    # Process each field mapping
    while read -r ccpm_field; do
        [[ -z "$ccpm_field" || "$ccpm_field" == "null" ]] && continue
        
        local ccpm_value
        ccpm_value=$(echo "$ccpm_json" | jq -r ".$ccpm_field // empty")
        
        [[ -z "$ccpm_value" || "$ccpm_value" == "null" ]] && continue
        
        # Get field mapping info
        local mapping_info
        mapping_info=$(echo "$task_mappings" | jq -r ".[\"$ccpm_field\"]")
        
        if [[ "$mapping_info" == "null" ]]; then
            continue
        fi
        
        local jira_target
        jira_target=$(echo "$mapping_info" | jq -r '.target // empty')
        
        local transform_type
        transform_type=$(echo "$mapping_info" | jq -r '.transform // "preserve"')
        
        [[ -z "$jira_target" ]] && continue
        
        # Transform the value
        local transformed_value
        if ! transformed_value=$(transform_field_value "$ccpm_value" "$transform_type"); then
            echo "Warning: Failed to transform field $ccpm_field with value $ccpm_value" >&2
            continue
        fi
        
        # Add to Jira fields
        jira_fields=$(echo "$jira_fields" | jq --arg key "$jira_target" --arg value "$transformed_value" '. + {($key): $value}')
        
    done < <(echo "$task_mappings" | jq -r 'keys[]')
    
    echo "$jira_fields"
}

#' Map Jira task fields to CCPM format
#' Usage: map_jira_task_to_ccpm JIRA_JSON
#' Returns: CCPM-formatted JSON
map_jira_task_to_ccpm() {
    local jira_json="$1"
    
    if [[ -z "$jira_json" ]]; then
        echo "Error: Jira JSON is required" >&2
        return 1
    fi
    
    if ! load_field_mapping_config; then
        return 1
    fi
    
    # Extract reverse mappings
    local reverse_mappings
    reverse_mappings=$(jq -r '.task_mappings.jira_to_ccpm' "$FIELD_MAPPING_CONFIG")
    
    # Start building CCPM fields JSON
    local ccpm_fields="{}"
    
    # Process each field mapping
    while read -r jira_field; do
        [[ -z "$jira_field" || "$jira_field" == "null" ]] && continue
        
        local jira_value
        jira_value=$(echo "$jira_json" | jq -r ".$jira_field // empty")
        
        [[ -z "$jira_value" || "$jira_value" == "null" ]] && continue
        
        # Get field mapping info
        local mapping_info
        mapping_info=$(echo "$reverse_mappings" | jq -r ".[\"$jira_field\"]")
        
        if [[ "$mapping_info" == "null" ]]; then
            continue
        fi
        
        local ccpm_target
        ccpm_target=$(echo "$mapping_info" | jq -r '.target // empty')
        
        local transform_type
        transform_type=$(echo "$mapping_info" | jq -r '.transform // "preserve"')
        
        [[ -z "$ccpm_target" ]] && continue
        
        # Transform the value
        local transformed_value
        if ! transformed_value=$(transform_field_value "$jira_value" "$transform_type"); then
            echo "Warning: Failed to transform field $jira_field with value $jira_value" >&2
            continue
        fi
        
        # Add to CCPM fields
        ccpm_fields=$(echo "$ccpm_fields" | jq --arg key "$ccpm_target" --arg value "$transformed_value" '. + {($key): $value}')
        
    done < <(echo "$reverse_mappings" | jq -r 'keys[]')
    
    echo "$ccpm_fields"
}

# =============================================================================
# Field Transformation Functions
# =============================================================================

#' Transform field value based on transformation type
#' Usage: transform_field_value VALUE TRANSFORM_TYPE
#' Returns: Transformed value
transform_field_value() {
    local value="$1"
    local transform_type="$2"
    
    case "$transform_type" in
        "preserve")
            echo "$value"
            ;;
        "status_mapping")
            transform_status_ccpm_to_jira "$value"
            ;;
        "reverse_status_mapping")
            transform_status_jira_to_ccpm "$value"
            ;;
        "datetime")
            transform_datetime_ccpm_to_jira "$value"
            ;;
        "datetime_from_jira")
            transform_datetime_jira_to_ccpm "$value"
            ;;
        "percentage")
            transform_percentage_ccpm_to_jira "$value"
            ;;
        "percentage_from_jira")
            transform_percentage_jira_to_ccpm "$value"
            ;;
        "url")
            validate_and_preserve_url "$value"
            ;;
        "boolean")
            transform_boolean_ccpm_to_jira "$value"
            ;;
        "boolean_from_jira")
            transform_boolean_jira_to_ccpm "$value"
            ;;
        "array")
            transform_array_ccpm_to_jira "$value"
            ;;
        "array_from_jira")
            transform_array_jira_to_ccpm "$value"
            ;;
        "dependency_array")
            transform_array_ccpm_to_jira "$value"
            ;;
        "dependency_array_from_jira")
            transform_array_jira_to_ccpm "$value"
            ;;
        *)
            echo "Warning: Unknown transform type: $transform_type" >&2
            echo "$value"
            ;;
    esac
}

#' Transform CCPM status to Jira status
transform_status_ccpm_to_jira() {
    local ccpm_status="$1"
    local jira_status
    jira_status=$(jq -r --arg status "$ccpm_status" '.status_mappings.ccpm_to_jira[$status] // "To Do"' "$FIELD_MAPPING_CONFIG")
    echo "$jira_status"
}

#' Transform Jira status to CCPM status  
transform_status_jira_to_ccpm() {
    local jira_status="$1"
    local ccpm_status
    ccpm_status=$(jq -r --arg status "$jira_status" '.status_mappings.jira_to_ccpm[$status] // "open"' "$FIELD_MAPPING_CONFIG")
    echo "$ccpm_status"
}

#' Transform CCPM datetime to Jira format
transform_datetime_ccpm_to_jira() {
    local ccpm_date="$1"
    # CCPM uses ISO8601, Jira typically expects the same format
    # Just validate and pass through for now
    if [[ "$ccpm_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z?$ ]]; then
        echo "$ccpm_date"
    else
        echo "Warning: Invalid datetime format: $ccpm_date" >&2
        echo ""
    fi
}

#' Transform Jira datetime to CCPM format
transform_datetime_jira_to_ccpm() {
    local jira_date="$1" 
    # Convert Jira datetime to ISO8601 if needed
    echo "$jira_date"
}

#' Transform CCPM percentage to Jira
transform_percentage_ccpm_to_jira() {
    local percentage="$1"
    # Remove % sign if present and validate range
    percentage=${percentage%\%}
    if [[ "$percentage" =~ ^[0-9]+$ ]] && (( percentage >= 0 && percentage <= 100 )); then
        echo "$percentage"
    else
        echo "Warning: Invalid percentage: $1" >&2
        echo "0"
    fi
}

#' Transform Jira percentage to CCPM
transform_percentage_jira_to_ccpm() {
    local jira_percentage="$1"
    # Add % suffix for CCPM display
    if [[ "$jira_percentage" =~ ^[0-9]+$ ]]; then
        echo "${jira_percentage}%"
    else
        echo "0%"
    fi
}

#' Validate and preserve URL
validate_and_preserve_url() {
    local url="$1"
    if [[ "$url" =~ ^https?:// ]]; then
        echo "$url"
    else
        echo "Warning: Invalid URL format: $url" >&2
        echo ""
    fi
}

#' Transform CCPM boolean to Jira
transform_boolean_ccpm_to_jira() {
    local value="$1"
    case "$value" in
        "true"|"True"|"TRUE"|"1"|"yes"|"Yes"|"YES")
            echo "true"
            ;;
        *)
            echo "false"
            ;;
    esac
}

#' Transform Jira boolean to CCPM
transform_boolean_jira_to_ccpm() {
    local value="$1"
    case "$value" in
        "true"|"True"|"TRUE")
            echo "true"
            ;;
        *)
            echo "false"
            ;;
    esac
}

#' Transform CCPM array to Jira
transform_array_ccpm_to_jira() {
    local array_value="$1"
    # If it's already JSON array, pass through
    if echo "$array_value" | jq -e . >/dev/null 2>&1; then
        echo "$array_value"
    else
        # Convert comma-separated to JSON array
        echo "$array_value" | sed 's/,/","/g' | sed 's/^/["/' | sed 's/$/""]/'
    fi
}

#' Transform Jira array to CCPM
transform_array_jira_to_ccpm() {
    local jira_array="$1"
    # Convert JSON array to comma-separated for CCPM
    echo "$jira_array" | jq -r '. | join(",")'
}

#' Transform CCPM dependency array to Jira
transform_dependency_array_ccpm_to_jira() {
    local deps="$1"
    # CCPM dependency format: [2, 3] -> Jira blocks format
    if echo "$deps" | jq -e . >/dev/null 2>&1; then
        echo "$deps"
    else
        echo "[]"
    fi
}

#' Transform Jira dependency array to CCPM
transform_dependency_array_jira_to_ccpm() {
    local jira_deps="$1"
    # Convert Jira blocks to CCPM depends_on format
    echo "$jira_deps"
}

# =============================================================================
# Validation Functions
# =============================================================================

#' Validate CCPM epic data structure
#' Usage: validate_ccpm_epic CCMP_JSON
#' Returns: Success/failure status
validate_ccpm_epic() {
    local ccpm_json="$1"
    
    if [[ -z "$ccpm_json" ]]; then
        echo "Error: CCPM JSON is required" >&2
        return 1
    fi
    
    # Check required fields
    local required_fields
    required_fields=$(jq -r '.field_validation.required_epic_fields[]' "$FIELD_MAPPING_CONFIG")
    
    while read -r field; do
        [[ -z "$field" ]] && continue
        local field_value
        field_value=$(echo "$ccpm_json" | jq -r ".$field // empty")
        if [[ -z "$field_value" ]]; then
            echo "Error: Required epic field missing: $field" >&2
            return 1
        fi
    done < <(echo "$required_fields")
    
    return 0
}

#' Validate CCPM task data structure
#' Usage: validate_ccpm_task CCMP_JSON  
#' Returns: Success/failure status
validate_ccpm_task() {
    local ccpm_json="$1"
    
    if [[ -z "$ccpm_json" ]]; then
        echo "Error: CCPM JSON is required" >&2
        return 1
    fi
    
    # Check required fields
    local required_fields
    required_fields=$(jq -r '.field_validation.required_task_fields[]' "$FIELD_MAPPING_CONFIG")
    
    while read -r field; do
        [[ -z "$field" ]] && continue
        local field_value
        field_value=$(echo "$ccpm_json" | jq -r ".$field // empty")
        if [[ -z "$field_value" ]]; then
            echo "Error: Required task field missing: $field" >&2
            return 1
        fi
    done < <(echo "$required_fields")
    
    return 0
}

# =============================================================================
# Interface Functions for Stream A and B
# =============================================================================

#' High-level function to prepare CCPM epic for Jira creation
#' Usage: prepare_epic_for_jira EPIC_NAME EPIC_DATA_JSON
#' Returns: Jira-ready JSON structure
prepare_epic_for_jira() {
    local epic_name="$1"
    local epic_data="$2"
    
    if [[ -z "$epic_name" || -z "$epic_data" ]]; then
        echo "Error: Epic name and data are required" >&2
        return 1
    fi
    
    # Validate CCPM epic data
    if ! validate_ccpm_epic "$epic_data"; then
        return 1
    fi
    
    # Map fields to Jira format
    local jira_fields
    if ! jira_fields=$(map_ccpm_epic_to_jira "$epic_data"); then
        return 1
    fi
    
    # Create final structure for Jira API
    local jira_request
    jira_request=$(jq -n \
        --arg issue_type "Epic" \
        --arg summary "$epic_name" \
        --argjson fields "$jira_fields" \
        '{
            issueTypeName: $issue_type,
            summary: $summary,
            fields: $fields
        }')
    
    echo "$jira_request"
}

#' High-level function to prepare CCPM task for Jira creation
#' Usage: prepare_task_for_jira TASK_NAME TASK_DATA_JSON [ISSUE_TYPE]
#' Returns: Jira-ready JSON structure
prepare_task_for_jira() {
    local task_name="$1"
    local task_data="$2"
    local issue_type="${3:-Task}"
    
    if [[ -z "$task_name" || -z "$task_data" ]]; then
        echo "Error: Task name and data are required" >&2
        return 1
    fi
    
    # Validate CCPM task data
    if ! validate_ccpm_task "$task_data"; then
        return 1
    fi
    
    # Map fields to Jira format
    local jira_fields
    if ! jira_fields=$(map_ccpm_task_to_jira "$task_data"); then
        return 1
    fi
    
    # Create final structure for Jira API
    local jira_request
    jira_request=$(jq -n \
        --arg issue_type "$issue_type" \
        --arg summary "$task_name" \
        --argjson fields "$jira_fields" \
        '{
            issueTypeName: $issue_type,
            summary: $summary,
            fields: $fields
        }')
    
    echo "$jira_request"
}

#' Convert Jira epic response back to CCPM format
#' Usage: process_jira_epic_response JIRA_RESPONSE_JSON
#' Returns: CCPM-formatted epic data
process_jira_epic_response() {
    local jira_response="$1"
    
    if [[ -z "$jira_response" ]]; then
        echo "Error: Jira response is required" >&2
        return 1
    fi
    
    # Extract fields from Jira response
    local jira_fields
    jira_fields=$(echo "$jira_response" | jq -r '.fields // {}')
    
    # Map back to CCPM format
    map_jira_epic_to_ccpm "$jira_fields"
}

#' Convert Jira task response back to CCPM format
#' Usage: process_jira_task_response JIRA_RESPONSE_JSON
#' Returns: CCMP-formatted task data
process_jira_task_response() {
    local jira_response="$1"
    
    if [[ -z "$jira_response" ]]; then
        echo "Error: Jira response is required" >&2
        return 1
    fi
    
    # Extract fields from Jira response
    local jira_fields
    jira_fields=$(echo "$jira_response" | jq -r '.fields // {}')
    
    # Map back to CCPM format
    map_jira_task_to_ccpm "$jira_fields"
}

# =============================================================================
# Export Functions for Other Streams
# =============================================================================

# Export key functions that Streams A and B will use
export -f load_field_mapping_config
export -f prepare_epic_for_jira
export -f prepare_task_for_jira
export -f process_jira_epic_response
export -f process_jira_task_response
export -f validate_ccpm_epic
export -f validate_ccpm_task
export -f transform_status_ccpm_to_jira
export -f transform_status_jira_to_ccpm

# Initialize the configuration on load
if ! load_field_mapping_config; then
    echo "Warning: Failed to load field mapping configuration" >&2
fi