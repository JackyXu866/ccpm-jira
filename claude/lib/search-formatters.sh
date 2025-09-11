#!/bin/bash

# Search Result Formatters Library
# Provides multiple output formats for search results

set -euo pipefail

# Constants
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Color codes for terminal output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[0;37m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'

# Extract issue data from JSON results
extract_issue_data() {
    local json_data="$1"
    
    # Parse JSON and extract key fields
    echo "$json_data" | jq -r '
        if type == "object" and has("issues") then
            .issues[]
        elif type == "array" then
            .[]
        else
            .
        end |
        select(type == "object") |
        {
            key: (.key // .id // "N/A"),
            summary: (.fields.summary // .summary // "N/A"),
            status: (.fields.status.name // .status // "N/A"),
            issuetype: (.fields.issuetype.name // .issuetype // "N/A"),
            priority: (.fields.priority.name // .priority // "Medium"),
            assignee: (.fields.assignee.displayName // .assignee // "Unassigned"),
            created: (.fields.created // .created // "N/A"),
            updated: (.fields.updated // .updated // "N/A")
        }' 2>/dev/null || echo "{}"
}

# Extract issue data from natural language search results (text-based)
extract_nl_issue_data() {
    local text_data="$1"
    
    # Extract issue keys from text
    local issue_keys
    issue_keys=$(echo "$text_data" | grep -oP '\b[A-Z]+-\d+\b' | sort -u)
    
    if [[ -z "$issue_keys" ]]; then
        echo "[]"
        return 0
    fi
    
    # Create JSON structure for each issue key found
    local json_output="["
    local first=true
    
    while IFS= read -r key; do
        [[ -z "$key" ]] && continue
        
        if [[ "$first" == "true" ]]; then
            first=false
        else
            json_output+=","
        fi
        
        # Extract title/summary from the surrounding text
        local summary
        summary=$(echo "$text_data" | grep -i "$key" | head -1 | sed "s/.*$key[^a-zA-Z0-9]*//g" | cut -c1-100 | sed 's/[^a-zA-Z0-9 .-].*$//')
        [[ -z "$summary" ]] && summary="Issue $key"
        
        json_output+="{\"key\":\"$key\",\"summary\":\"$summary\",\"status\":\"Unknown\",\"issuetype\":\"Unknown\",\"priority\":\"Unknown\",\"assignee\":\"Unknown\",\"created\":\"N/A\",\"updated\":\"N/A\"}"
    done <<< "$issue_keys"
    
    json_output+="]"
    echo "$json_output"
}

# Format results as a table (default format)
format_table() {
    local json_data="$1"
    local max_width="${2:-120}"
    
    # Parse and extract issues
    local issues
    if echo "$json_data" | jq -e 'type == "object" and has("issues")' >/dev/null 2>&1; then
        issues=$(extract_issue_data "$json_data")
    elif echo "$json_data" | jq -e 'type == "array"' >/dev/null 2>&1; then
        issues=$(echo "$json_data")
    else
        # Try to extract from natural language results
        issues=$(extract_nl_issue_data "$json_data")
    fi
    
    if [[ -z "$issues" || "$issues" == "[]" || "$issues" == "{}" ]]; then
        echo "No issues found in results"
        return 0
    fi
    
    # Table header
    printf "${BOLD}%-12s %-40s %-12s %-10s %-8s %-15s${RESET}\n" \
        "KEY" "SUMMARY" "STATUS" "TYPE" "PRIORITY" "ASSIGNEE"
    printf "%-12s %-40s %-12s %-10s %-8s %-15s\n" \
        "$(printf '%.12s' '============')" \
        "$(printf '%.40s' '========================================')" \
        "$(printf '%.12s' '============')" \
        "$(printf '%.10s' '==========')" \
        "$(printf '%.8s' '========')" \
        "$(printf '%.15s' '===============')"
    
    # Table rows
    echo "$issues" | jq -r '
        if type == "array" then .[] else . end |
        select(type == "object") |
        "\(.key // "N/A")\t\(.summary // "N/A")\t\(.status // "N/A")\t\(.issuetype // "N/A")\t\(.priority // "N/A")\t\(.assignee // "N/A")"
    ' 2>/dev/null | while IFS=$'\t' read -r key summary status issuetype priority assignee; do
        # Truncate long summaries
        local short_summary
        short_summary=$(printf '%.40s' "$summary")
        [[ ${#summary} -gt 40 ]] && short_summary="${short_summary:0:37}..."
        
        # Color code by status
        local status_color=""
        case "$status" in
            "To Do"|"Open"|"New") status_color="$CYAN" ;;
            "In Progress"|"Active") status_color="$YELLOW" ;;
            "Done"|"Closed"|"Resolved") status_color="$GREEN" ;;
            "Blocked"|"On Hold") status_color="$RED" ;;
            *) status_color="$WHITE" ;;
        esac
        
        printf "%-12s %-40s ${status_color}%-12s${RESET} %-10s %-8s %-15s\n" \
            "$key" "$short_summary" "$status" "$issuetype" "$priority" "$assignee"
    done
}

# Format results as a simple list (one line per issue)
format_list() {
    local json_data="$1"
    
    # Parse and extract issues
    local issues
    if echo "$json_data" | jq -e 'type == "object" and has("issues")' >/dev/null 2>&1; then
        issues=$(extract_issue_data "$json_data")
    elif echo "$json_data" | jq -e 'type == "array"' >/dev/null 2>&1; then
        issues=$(echo "$json_data")
    else
        # Try to extract from natural language results
        issues=$(extract_nl_issue_data "$json_data")
    fi
    
    if [[ -z "$issues" || "$issues" == "[]" || "$issues" == "{}" ]]; then
        echo "No issues found in results"
        return 0
    fi
    
    echo "$issues" | jq -r '
        if type == "array" then .[] else . end |
        select(type == "object") |
        "• \(.key // "N/A") - \(.summary // "N/A") [\(.status // "N/A")]"
    ' 2>/dev/null
}

# Format results with detailed information
format_detailed() {
    local json_data="$1"
    
    # Parse and extract issues
    local issues
    if echo "$json_data" | jq -e 'type == "object" and has("issues")' >/dev/null 2>&1; then
        issues=$(extract_issue_data "$json_data")
    elif echo "$json_data" | jq -e 'type == "array"' >/dev/null 2>&1; then
        issues=$(echo "$json_data")
    else
        # Try to extract from natural language results
        issues=$(extract_nl_issue_data "$json_data")
    fi
    
    if [[ -z "$issues" || "$issues" == "[]" || "$issues" == "{}" ]]; then
        echo "No issues found in results"
        return 0
    fi
    
    local count=0
    echo "$issues" | jq -r '
        if type == "array" then .[] else . end |
        select(type == "object") |
        [
            "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
            "🎫 Issue: \(.key // "N/A")",
            "📝 Summary: \(.summary // "N/A")",
            "📊 Status: \(.status // "N/A")",
            "🏷️  Type: \(.issuetype // "N/A")",
            "⚡ Priority: \(.priority // "N/A")",
            "👤 Assignee: \(.assignee // "Unassigned")",
            "📅 Created: \(.created // "N/A")",
            "🔄 Updated: \(.updated // "N/A")",
            ""
        ] | .[]
    ' 2>/dev/null
}

# Format results as raw JSON
format_json() {
    local json_data="$1"
    local pretty="${2:-true}"
    
    if [[ "$pretty" == "true" ]]; then
        echo "$json_data" | jq '.' 2>/dev/null || echo "$json_data"
    else
        echo "$json_data" | jq -c '.' 2>/dev/null || echo "$json_data"
    fi
}

# Get issue count from results
get_issue_count() {
    local json_data="$1"
    
    local count
    if echo "$json_data" | jq -e 'type == "object" and has("total")' >/dev/null 2>&1; then
        count=$(echo "$json_data" | jq -r '.total // 0')
    elif echo "$json_data" | jq -e 'type == "object" and has("issues")' >/dev/null 2>&1; then
        count=$(echo "$json_data" | jq -r '.issues | length')
    elif echo "$json_data" | jq -e 'type == "array"' >/dev/null 2>&1; then
        count=$(echo "$json_data" | jq -r 'length')
    else
        # Count issue keys in text
        count=$(echo "$json_data" | grep -oP '\b[A-Z]+-\d+\b' | sort -u | wc -l)
    fi
    
    echo "${count:-0}"
}

# Format pagination info
format_pagination_info() {
    local current_page="$1"
    local total_results="$2"
    local page_size="$3"
    local has_more="${4:-false}"
    
    local total_pages
    total_pages=$(( (total_results + page_size - 1) / page_size ))
    
    echo ""
    echo "${BOLD}📄 Pagination:${RESET} Page $current_page of $total_pages (${total_results} total results)"
    
    if [[ "$has_more" == "true" ]]; then
        local next_offset=$((current_page * page_size))
        echo "💡 Use --offset $next_offset to see more results"
    fi
}

# Generate pagination navigation commands
generate_pagination_commands() {
    local base_command="$1"
    local current_page="$2"
    local page_size="$3"
    local total_pages="$4"
    
    local current_offset=$(( (current_page - 1) * page_size ))
    local next_offset=$((current_page * page_size))
    local prev_offset=$(( (current_page - 2) * page_size ))
    
    echo ""
    echo "${BOLD}📄 Navigation Commands:${RESET}"
    
    # Previous page
    if [[ $current_page -gt 1 ]]; then
        echo "⬅️  Previous: $base_command --offset $prev_offset"
    fi
    
    # Next page
    if [[ $current_page -lt $total_pages ]]; then
        echo "➡️  Next: $base_command --offset $next_offset"
    fi
    
    # First page
    if [[ $current_page -gt 2 ]]; then
        echo "⏮️  First: $base_command --offset 0"
    fi
}

# Main formatting function
format_results() {
    local format="$1"
    local json_data="$2"
    local pagination_info="${3:-}"
    
    case "$format" in
        "table")
            format_table "$json_data"
            ;;
        "list")
            format_list "$json_data"
            ;;
        "detailed")
            format_detailed "$json_data"
            ;;
        "json")
            format_json "$json_data"
            ;;
        "json-compact")
            format_json "$json_data" false
            ;;
        *)
            echo "❌ Unknown format: $format" >&2
            echo "ℹ️ Available formats: table, list, detailed, json, json-compact" >&2
            return 1
            ;;
    esac
    
    # Add pagination info if provided
    if [[ -n "$pagination_info" ]]; then
        echo "$pagination_info"
    fi
}

# Helper function to truncate text
truncate_text() {
    local text="$1"
    local max_length="$2"
    local suffix="${3:-...}"
    
    if [[ ${#text} -le $max_length ]]; then
        echo "$text"
    else
        echo "${text:0:$((max_length - ${#suffix}))}$suffix"
    fi
}

# Main function for CLI usage
main() {
    local format="table"
    local input_file=""
    local pagination_info=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --format)
                format="$2"
                shift 2
                ;;
            --file)
                input_file="$2"
                shift 2
                ;;
            --pagination)
                pagination_info="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --format FORMAT     Output format (table, list, detailed, json, json-compact)"
                echo "  --file FILE         Read input from file (default: stdin)"
                echo "  --pagination INFO   Pagination information to display"
                echo "  -h, --help          Show this help"
                exit 0
                ;;
            *)
                echo "❌ Unknown option: $1" >&2
                exit 1
                ;;
        esac
    done
    
    # Read input data
    local input_data
    if [[ -n "$input_file" ]]; then
        input_data=$(cat "$input_file")
    else
        input_data=$(cat)
    fi
    
    format_results "$format" "$input_data" "$pagination_info"
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi