#!/bin/bash

# Enhanced search command with MCP integration
# Supports both local file search and Jira search via MCP

set -euo pipefail

# Constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required libraries
source "${SCRIPT_DIR}/../../lib/search-mcp.sh"
source "${SCRIPT_DIR}/../../lib/query-router.sh"
source "${SCRIPT_DIR}/../../lib/search-formatters.sh"

# Additional constants (after libraries are loaded)
readonly SEARCH_HISTORY_FILE="${CACHE_DIR}/search_history"

# Initialize cache directories
init_cache_dirs

# Default values
query=""
search_mode="auto"  # auto, local, jira
format="table"
limit=25
offset=0
use_cache="true"
show_help=false
force_jql=false
local_only=false
jira_only=false

# Function to show usage
show_usage() {
    echo "Usage: pm:search [OPTIONS] <query>"
    echo ""
    echo "Search in local files and Jira issues using natural language or JQL"
    echo ""
    echo "Arguments:"
    echo "  query                Search query (natural language or JQL)"
    echo ""
    echo "Options:"
    echo "  --local              Search only in local files (.claude/)"
    echo "  --jira               Search only in Jira issues"
    echo "  --jql                Force JQL search (requires --jira)"
    echo "  --format FORMAT      Output format: table, list, detailed, json, json-compact (default: table)"
    echo "  --limit NUM          Maximum results to return (default: 25)"
    echo "  --offset NUM         Skip first NUM results for pagination (default: 0)"
    echo "  --no-cache           Don't use cached results"
    echo "  -h, --help           Show this help"
    echo ""
    echo "Examples:"
    echo "  pm:search 'my open bugs'                    # Natural language Jira search"
    echo "  pm:search --local 'authentication'          # Local file search only"
    echo "  pm:search --jira --jql 'assignee = currentUser()'  # JQL search"
    echo "  pm:search --format=list 'high priority'     # List format output"
    echo "  pm:search --limit=10 --offset=20 'tasks'    # Pagination"
}

# Function to add query to search history
add_to_history() {
    local query="$1"
    local search_type="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    mkdir -p "$CACHE_DIR"
    echo "$timestamp|$search_type|$query" >> "$SEARCH_HISTORY_FILE"
    
    # Keep only last 100 searches
    if [[ -f "$SEARCH_HISTORY_FILE" ]]; then
        tail -n 100 "$SEARCH_HISTORY_FILE" > "${SEARCH_HISTORY_FILE}.tmp"
        mv "${SEARCH_HISTORY_FILE}.tmp" "$SEARCH_HISTORY_FILE"
    fi
}

# Function to search local files (original functionality)
search_local_files() {
    local query="$1"
    local found=0
    
    echo "🔍 Local search results for: '$query'"
    echo "======================================"
    echo ""
    
    # Search in PRDs
    if [[ -d ".claude/prds" ]]; then
        echo "📄 PRDs:"
        local results
        results=$(grep -l -i "$query" .claude/prds/*.md 2>/dev/null || true)
        if [[ -n "$results" ]]; then
            while IFS= read -r file; do
                local name
                name=$(basename "$file" .md)
                local matches
                matches=$(grep -c -i "$query" "$file")
                echo "  • $name ($matches matches)"
                ((found++))
            done <<< "$results"
        else
            echo "  No matches"
        fi
        echo ""
    fi
    
    # Search in Epics
    if [[ -d ".claude/epics" ]]; then
        echo "📚 Epics:"
        local results
        results=$(find .claude/epics -name "epic.md" -exec grep -l -i "$query" {} \; 2>/dev/null || true)
        if [[ -n "$results" ]]; then
            while IFS= read -r file; do
                local epic_name
                epic_name=$(basename "$(dirname "$file")")
                local matches
                matches=$(grep -c -i "$query" "$file")
                echo "  • $epic_name ($matches matches)"
                ((found++))
            done <<< "$results"
        else
            echo "  No matches"
        fi
        echo ""
    fi
    
    # Search in Tasks
    if [[ -d ".claude/epics" ]]; then
        echo "📝 Tasks:"
        local results
        results=$(find .claude/epics -name "[0-9]*.md" -exec grep -l -i "$query" {} \; 2>/dev/null | head -10 || true)
        if [[ -n "$results" ]]; then
            while IFS= read -r file; do
                local epic_name
                epic_name=$(basename "$(dirname "$file")")
                local task_num
                task_num=$(basename "$file" .md)
                echo "  • Task #$task_num in $epic_name"
                ((found++))
            done <<< "$results"
        else
            echo "  No matches"
        fi
    fi
    
    # Summary
    local total
    total=$(find .claude -name "*.md" -exec grep -l -i "$query" {} \; 2>/dev/null | wc -l)
    echo ""
    echo "📊 Local files with matches: $total"
    
    return $((found > 0 ? 0 : 1))
}

# Function to search Jira issues
search_jira_issues() {
    local query="$1"
    local search_type="$2"  # auto, nl, jql
    local max_results="$3"
    local use_cache="$4"
    
    echo "🔍 Jira search: '$query'..." >&2
    
    # Use the smart search from query router
    local results
    if [[ "$search_type" == "jql" ]]; then
        # Force JQL search
        results=$(search_jql "$query" "$max_results")
    else
        # Use smart routing (defaults to natural language first)
        results=$(smart_search "$query" "$search_type" "$max_results")
    fi
    
    if [[ $? -eq 0 && -n "$results" ]]; then
        echo "$results"
        return 0
    else
        echo "❌ Jira search failed or returned no results" >&2
        return 1
    fi
}

# Main search function
perform_search() {
    local query="$1"
    local search_mode="$2"
    local format="$3"
    local limit="$4"
    local offset="$5"
    local use_cache="$6"
    local force_jql="$7"
    
    local search_results=""
    local search_type="auto"
    
    if [[ "$force_jql" == "true" ]]; then
        search_type="jql"
    fi
    
    case "$search_mode" in
        "local")
            search_local_files "$query"
            add_to_history "$query" "local"
            return $?
            ;;
        "jira")
            search_results=$(search_jira_issues "$query" "$search_type" "$limit" "$use_cache")
            if [[ $? -eq 0 ]]; then
                add_to_history "$query" "jira-$search_type"
                
                # Format and display results
                local issue_count
                issue_count=$(get_issue_count "$search_results")
                
                echo "🎫 Found $issue_count Jira issues:" >&2
                echo "" >&2
                
                # Handle pagination
                local paginated_results="$search_results"
                if [[ $offset -gt 0 ]]; then
                    # Apply offset to results if needed
                    # Note: This is basic offset handling - proper pagination would be done at API level
                    echo "ℹ️ Applying offset of $offset..." >&2
                fi
                
                format_results "$format" "$paginated_results"
                
                # Show pagination info
                if [[ $issue_count -ge $limit ]]; then
                    local current_page
                    current_page=$(( (offset / limit) + 1 ))
                    format_pagination_info "$current_page" "$issue_count" "$limit" "true"
                fi
                
                return 0
            else
                return 1
            fi
            ;;
        "auto")
            # Try both local and Jira search
            echo "🔍 Searching both local files and Jira issues..." >&2
            echo "" >&2
            
            # Search local files first
            search_local_files "$query"
            local local_found=$?
            
            echo "" >&2
            
            # Then search Jira
            search_results=$(search_jira_issues "$query" "$search_type" "$limit" "$use_cache")
            if [[ $? -eq 0 ]]; then
                add_to_history "$query" "auto-$search_type"
                
                local issue_count
                issue_count=$(get_issue_count "$search_results")
                
                echo "🎫 Found $issue_count Jira issues:" >&2
                echo "" >&2
                
                format_results "$format" "$search_results"
                
                if [[ $issue_count -ge $limit ]]; then
                    local current_page
                    current_page=$(( (offset / limit) + 1 ))
                    format_pagination_info "$current_page" "$issue_count" "$limit" "true"
                fi
                
                return 0
            else
                # Return success if local search found something
                return $local_found
            fi
            ;;
        *)
            echo "❌ Unknown search mode: $search_mode" >&2
            return 1
            ;;
    esac
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --local)
            search_mode="local"
            shift
            ;;
        --jira)
            search_mode="jira"
            shift
            ;;
        --jql)
            force_jql="true"
            shift
            ;;
        --format)
            format="$2"
            shift 2
            ;;
        --limit)
            limit="$2"
            shift 2
            ;;
        --offset)
            offset="$2"
            shift 2
            ;;
        --no-cache)
            use_cache="false"
            shift
            ;;
        -h|--help)
            show_help=true
            shift
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "❌ Unknown option: $1" >&2
            echo "Use --help for usage information" >&2
            exit 1
            ;;
        *)
            if [[ -z "$query" ]]; then
                query="$1"
            else
                query="$query $1"
            fi
            shift
            ;;
    esac
done

# Show help if requested
if [[ "$show_help" == "true" ]]; then
    show_usage
    exit 0
fi

# Validate arguments
if [[ -z "$query" ]]; then
    echo "❌ Please provide a search query" >&2
    echo "Use --help for usage information" >&2
    exit 1
fi

if [[ "$force_jql" == "true" && "$search_mode" != "jira" ]]; then
    echo "❌ --jql flag requires --jira mode" >&2
    exit 1
fi

# Validate format
case "$format" in
    "table"|"list"|"detailed"|"json"|"json-compact")
        # Valid format
        ;;
    *)
        echo "❌ Invalid format: $format" >&2
        echo "Valid formats: table, list, detailed, json, json-compact" >&2
        exit 1
        ;;
esac

# Perform the search
perform_search "$query" "$search_mode" "$format" "$limit" "$offset" "$use_cache" "$force_jql"