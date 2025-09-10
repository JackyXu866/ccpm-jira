#!/bin/bash

# MCP Search Integration Library
# Provides natural language search with JQL fallback for Jira issues

set -euo pipefail

# Constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CACHE_DIR="${HOME}/.cache/ccpm-jira"
readonly AUTH_CACHE_FILE="${CACHE_DIR}/auth_state"
readonly SEARCH_CACHE_DIR="${CACHE_DIR}/searches"

# Initialize cache directories
init_cache_dirs() {
    mkdir -p "$CACHE_DIR" "$SEARCH_CACHE_DIR"
}

# Check if MCP Atlassian tools are available
check_mcp_availability() {
    # Try a simple call to test MCP availability
    if ! command -v claude >/dev/null 2>&1; then
        echo "❌ Claude CLI not found. MCP search requires Claude CLI." >&2
        return 1
    fi
    return 0
}

# Check authentication state with caching
check_auth_state() {
    local cache_ttl=300 # 5 minutes
    
    # Check cache first
    if [[ -f "$AUTH_CACHE_FILE" ]]; then
        local cache_age=$(($(date +%s) - $(stat -c %Y "$AUTH_CACHE_FILE" 2>/dev/null || echo 0)))
        if [[ $cache_age -lt $cache_ttl ]]; then
            cat "$AUTH_CACHE_FILE"
            return 0
        fi
    fi
    
    # Test auth by trying to get user info
    local auth_result
    if auth_result=$(claude mcp__atlassian__atlassianUserInfo 2>/dev/null); then
        echo "authenticated" | tee "$AUTH_CACHE_FILE"
        return 0
    else
        echo "unauthenticated" | tee "$AUTH_CACHE_FILE"
        return 1
    fi
}

# Perform natural language search using MCP
search_natural_language() {
    local query="$1"
    local max_results="${2:-25}"
    
    if ! check_mcp_availability; then
        return 1
    fi
    
    echo "🔍 Searching with natural language: '$query'..." >&2
    
    # Call MCP search tool
    local search_result
    if search_result=$(claude mcp__atlassian__search --query "$query" 2>/dev/null); then
        echo "$search_result"
        return 0
    else
        echo "❌ Natural language search failed" >&2
        return 1
    fi
}

# Perform JQL search using MCP
search_jql() {
    local jql_query="$1"
    local max_results="${2:-50}"
    local fields="${3:-summary,description,status,issuetype,priority,created,assignee}"
    
    if ! check_mcp_availability; then
        return 1
    fi
    
    # Check authentication first
    if ! check_auth_state >/dev/null; then
        echo "❌ JQL search requires Atlassian authentication" >&2
        echo "ℹ️ Run 'claude login' to authenticate with Atlassian" >&2
        return 1
    fi
    
    echo "🔍 Searching with JQL: '$jql_query'..." >&2
    
    # Get cloud ID (required for JQL search)
    local cloud_id
    if ! cloud_id=$(get_cloud_id); then
        echo "❌ Failed to get Atlassian cloud ID" >&2
        return 1
    fi
    
    # Call MCP JQL search tool
    local search_result
    if search_result=$(claude mcp__atlassian__searchJiraIssuesUsingJql \
        --cloudId "$cloud_id" \
        --jql "$jql_query" \
        --maxResults "$max_results" \
        --fields "$fields" 2>/dev/null); then
        echo "$search_result"
        return 0
    else
        echo "❌ JQL search failed" >&2
        return 1
    fi
}

# Get Atlassian cloud ID
get_cloud_id() {
    local cache_file="${CACHE_DIR}/cloud_id"
    local cache_ttl=3600 # 1 hour
    
    # Check cache first
    if [[ -f "$cache_file" ]]; then
        local cache_age=$(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0)))
        if [[ $cache_age -lt $cache_ttl ]]; then
            cat "$cache_file"
            return 0
        fi
    fi
    
    # Get cloud ID from MCP
    local resources
    if resources=$(claude mcp__atlassian__getAccessibleAtlassianResources 2>/dev/null); then
        # Extract first cloud ID from the response
        local cloud_id
        cloud_id=$(echo "$resources" | grep -oP '"id":\s*"\K[^"]+' | head -n1)
        if [[ -n "$cloud_id" ]]; then
            echo "$cloud_id" | tee "$cache_file"
            return 0
        fi
    fi
    
    echo "❌ Failed to retrieve cloud ID" >&2
    return 1
}

# Normalize search results to common format
normalize_results() {
    local search_type="$1" # "nl" or "jql"
    local raw_results="$2"
    
    # For now, pass through raw results
    # TODO: Implement result normalization based on search type
    echo "$raw_results"
}

# Extract issue keys from search results
extract_issue_keys() {
    local results="$1"
    
    # Extract issue keys using various patterns
    echo "$results" | grep -oP '\b[A-Z]+-\d+\b' | sort -u
}

# Get issue count from results
get_result_count() {
    local results="$1"
    local search_type="${2:-nl}"
    
    if [[ "$search_type" == "jql" ]]; then
        # For JQL results, try to extract total count
        echo "$results" | grep -oP '"total":\s*\K\d+' | head -n1
    else
        # For NL results, count issue keys
        extract_issue_keys "$results" | wc -l
    fi
}

# Cache search results
cache_search_results() {
    local query="$1"
    local search_type="$2"
    local results="$3"
    
    local cache_key
    cache_key=$(echo "${search_type}:${query}" | sha256sum | cut -d' ' -f1)
    local cache_file="${SEARCH_CACHE_DIR}/${cache_key}"
    
    echo "$results" > "$cache_file"
    echo "$(date +%s)" > "${cache_file}.timestamp"
}

# Get cached search results
get_cached_results() {
    local query="$1"
    local search_type="$2"
    local cache_ttl="${3:-300}" # 5 minutes default
    
    local cache_key
    cache_key=$(echo "${search_type}:${query}" | sha256sum | cut -d' ' -f1)
    local cache_file="${SEARCH_CACHE_DIR}/${cache_key}"
    local timestamp_file="${cache_file}.timestamp"
    
    if [[ -f "$cache_file" && -f "$timestamp_file" ]]; then
        local cache_time
        cache_time=$(cat "$timestamp_file")
        local current_time
        current_time=$(date +%s)
        local age=$((current_time - cache_time))
        
        if [[ $age -lt $cache_ttl ]]; then
            cat "$cache_file"
            return 0
        fi
    fi
    
    return 1
}

# Main search function with caching and fallback
search_with_fallback() {
    local query="$1"
    local search_type="${2:-auto}" # auto, nl, jql
    local max_results="${3:-25}"
    local use_cache="${4:-true}"
    
    init_cache_dirs
    
    # Try cache first
    if [[ "$use_cache" == "true" ]]; then
        local cached_results
        if cached_results=$(get_cached_results "$query" "$search_type"); then
            echo "📋 Using cached results..." >&2
            echo "$cached_results"
            return 0
        fi
    fi
    
    local results
    local final_search_type="$search_type"
    
    case "$search_type" in
        "jql")
            if results=$(search_jql "$query" "$max_results"); then
                final_search_type="jql"
            else
                return 1
            fi
            ;;
        "nl")
            if results=$(search_natural_language "$query" "$max_results"); then
                final_search_type="nl"
            else
                return 1
            fi
            ;;
        "auto"|*)
            # Try natural language first
            if results=$(search_natural_language "$query" "$max_results"); then
                final_search_type="nl"
            else
                echo "⚠️ Natural language search failed, trying JQL..." >&2
                if results=$(search_jql "$query" "$max_results"); then
                    final_search_type="jql"
                else
                    echo "❌ Both search methods failed" >&2
                    return 1
                fi
            fi
            ;;
    esac
    
    # Normalize and cache results
    local normalized_results
    normalized_results=$(normalize_results "$final_search_type" "$results")
    
    if [[ "$use_cache" == "true" ]]; then
        cache_search_results "$query" "$final_search_type" "$normalized_results"
    fi
    
    echo "$normalized_results"
    return 0
}

# Display auth help message
show_auth_help() {
    echo "🔐 Authentication Required"
    echo "=========================="
    echo ""
    echo "JQL searches require authentication with Atlassian."
    echo ""
    echo "To authenticate:"
    echo "  1. Run: claude login"
    echo "  2. Follow the authentication flow"
    echo "  3. Retry your search"
    echo ""
    echo "Note: Natural language searches work without authentication."
}

# Main function for CLI usage
main() {
    local query=""
    local search_type="auto"
    local max_results=25
    local use_cache="true"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --jql)
                search_type="jql"
                shift
                ;;
            --nl|--natural-language)
                search_type="nl"
                shift
                ;;
            --max-results)
                max_results="$2"
                shift 2
                ;;
            --no-cache)
                use_cache="false"
                shift
                ;;
            --auth-help)
                show_auth_help
                exit 0
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS] <query>"
                echo ""
                echo "Options:"
                echo "  --jql                Force JQL search"
                echo "  --nl                 Force natural language search"
                echo "  --max-results NUM    Maximum results to return (default: 25)"
                echo "  --no-cache           Don't use cached results"
                echo "  --auth-help          Show authentication help"
                echo "  -h, --help           Show this help"
                exit 0
                ;;
            *)
                query="$1"
                shift
                ;;
        esac
    done
    
    if [[ -z "$query" ]]; then
        echo "❌ Please provide a search query" >&2
        exit 1
    fi
    
    search_with_fallback "$query" "$search_type" "$max_results" "$use_cache"
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi