#!/bin/bash

# Query Router Library
# Provides intelligent routing between natural language and JQL searches

set -euo pipefail

# Constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the search MCP library
source "${SCRIPT_DIR}/search-mcp.sh"

# JQL trigger keywords and patterns
declare -A JQL_KEYWORDS=(
    ["assignee"]="field"
    ["assigned to"]="field"
    ["assigned"]="field"
    ["reporter"]="field"
    ["status"]="field"
    ["priority"]="field" 
    ["type"]="field"
    ["issuetype"]="field"
    ["project"]="field"
    ["component"]="field"
    ["version"]="field"
    ["resolution"]="field"
    ["created"]="field"
    ["updated"]="field"
    ["resolved"]="field"
    ["due"]="field"
    ["labels"]="field"
    ["fixVersion"]="field"
)

declare -A JQL_OPERATORS=(
    ["="]="operator"
    ["!="]="operator"
    [">"]="operator"
    ["<"]="operator"
    [">="]="operator"
    ["<="]="operator"
    ["~"]="operator"
    ["!~"]="operator"
    ["in"]="operator"
    ["not in"]="operator"
    ["is"]="operator"
    ["is not"]="operator"
    ["was"]="operator"
    ["was not"]="operator"
    ["changed"]="operator"
)

declare -A JQL_FUNCTIONS=(
    ["currentUser()"]="function"
    ["now()"]="function"
    ["startOfDay()"]="function"
    ["endOfDay()"]="function"
    ["startOfWeek()"]="function"
    ["endOfWeek()"]="function"
    ["startOfMonth()"]="function"
    ["endOfMonth()"]="function"
    ["startOfYear()"]="function"
    ["endOfYear()"]="function"
)

# Detect if query contains JQL syntax
detect_jql_syntax() {
    local query="$1"
    local confidence=0
    
    # Convert to lowercase for pattern matching
    local query_lower
    query_lower=$(echo "$query" | tr '[:upper:]' '[:lower:]')
    
    # Check for JQL keywords
    for keyword in "${!JQL_KEYWORDS[@]}"; do
        if [[ "$query_lower" == *"$keyword"* ]]; then
            confidence=$((confidence + 2))
        fi
    done
    
    # Check for JQL operators
    for operator in "${!JQL_OPERATORS[@]}"; do
        if [[ "$query" == *"$operator"* ]]; then
            confidence=$((confidence + 3))
        fi
    done
    
    # Check for JQL functions
    for func in "${!JQL_FUNCTIONS[@]}"; do
        if [[ "$query" == *"$func"* ]]; then
            confidence=$((confidence + 4))
        fi
    done
    
    # Check for field-specific patterns
    if [[ "$query_lower" =~ (assignee|assigned\ to)\ *[=~] ]]; then
        confidence=$((confidence + 5))
    fi
    
    if [[ "$query_lower" =~ status\ *(in|=|!=) ]]; then
        confidence=$((confidence + 5))
    fi
    
    if [[ "$query_lower" =~ priority\ *(in|=|!=) ]]; then
        confidence=$((confidence + 5))
    fi
    
    # Check for epic parent syntax
    if [[ "$query_lower" =~ (epic|parent)\ *=\ *[a-z]+-[0-9]+ ]]; then
        confidence=$((confidence + 6))
    fi
    
    echo "$confidence"
}

# Detect epic-related queries that benefit from hybrid search
detect_epic_query() {
    local query="$1"
    local query_lower
    query_lower=$(echo "$query" | tr '[:upper:]' '[:lower:]')
    
    # Look for epic-related terms
    if [[ "$query_lower" == *"epic"* || "$query_lower" == *"story"* || "$query_lower" == *"feature"* ]]; then
        # Check if it's a specific epic reference vs general epic search
        if [[ "$query_lower" =~ epic\ *=\ *[a-z]+-[0-9]+ ]]; then
            echo "jql" # Specific epic parent query
        else
            echo "hybrid" # General epic search
        fi
    else
        echo "none"
    fi
}

# Detect assignee queries
detect_assignee_query() {
    local query="$1"
    local query_lower
    query_lower=$(echo "$query" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$query_lower" == *"assigned to"* || "$query_lower" == *"assignee"* ]]; then
        echo "jql"
    elif [[ "$query_lower" == *"my"* && ("$query_lower" == *"issue"* || "$query_lower" == *"task"* || "$query_lower" == *"bug"*) ]]; then
        echo "hybrid" # "my issues" could benefit from both approaches
    else
        echo "none"
    fi
}

# Detect status/priority queries  
detect_status_priority_query() {
    local query="$1"
    local query_lower
    query_lower=$(echo "$query" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$query_lower" == *"status"* || "$query_lower" == *"priority"* ]]; then
        # Check for specific field syntax
        if [[ "$query_lower" =~ (status|priority)\ *(in|=|!=) ]]; then
            echo "jql"
        else
            echo "hybrid" # Natural mentions of status/priority
        fi
    else
        echo "none"
    fi
}

# Route query to appropriate search method
route_query() {
    local query="$1"
    local force_type="${2:-auto}"
    
    # Honor forced type
    if [[ "$force_type" != "auto" ]]; then
        echo "$force_type"
        return 0
    fi
    
    # Calculate JQL confidence score
    local jql_confidence
    jql_confidence=$(detect_jql_syntax "$query")
    
    # Check for specific query types
    local epic_type
    epic_type=$(detect_epic_query "$query")
    
    local assignee_type
    assignee_type=$(detect_assignee_query "$query")
    
    local status_priority_type
    status_priority_type=$(detect_status_priority_query "$query")
    
    # Decision logic
    if [[ $jql_confidence -ge 6 ]]; then
        echo "jql"
    elif [[ "$epic_type" == "jql" || "$assignee_type" == "jql" || "$status_priority_type" == "jql" ]]; then
        echo "jql"
    elif [[ "$epic_type" == "hybrid" || "$assignee_type" == "hybrid" || "$status_priority_type" == "hybrid" ]]; then
        echo "hybrid"
    elif [[ $jql_confidence -ge 3 ]]; then
        echo "hybrid"
    else
        echo "nl"
    fi
}

# Perform hybrid search (NL + JQL combination)
search_hybrid() {
    local query="$1"
    local max_results="${2:-25}"
    
    echo "🔀 Using hybrid search strategy..." >&2
    
    # Try natural language first
    local nl_results=""
    if nl_results=$(search_natural_language "$query" "$max_results"); then
        local nl_count
        nl_count=$(get_result_count "$nl_results" "nl")
        echo "✅ Natural language search found $nl_count results" >&2
    fi
    
    # Try to construct JQL query for comparison
    local jql_query=""
    local jql_results=""
    
    # Attempt intelligent JQL construction
    jql_query=$(construct_jql_from_nl "$query")
    
    if [[ -n "$jql_query" ]] && check_auth_state >/dev/null; then
        echo "🔍 Trying constructed JQL: $jql_query" >&2
        if jql_results=$(search_jql "$jql_query" "$max_results"); then
            local jql_count
            jql_count=$(get_result_count "$jql_results" "jql")
            echo "✅ JQL search found $jql_count results" >&2
        fi
    fi
    
    # Merge results (prefer JQL if both available, fallback to NL)
    if [[ -n "$jql_results" ]]; then
        echo "$jql_results"
    elif [[ -n "$nl_results" ]]; then
        echo "$nl_results"
    else
        echo "❌ Hybrid search found no results" >&2
        return 1
    fi
}

# Construct JQL from natural language (basic patterns)
construct_jql_from_nl() {
    local query="$1"
    local query_lower
    query_lower=$(echo "$query" | tr '[:upper:]' '[:lower:]')
    local jql=""
    
    # Handle "my" queries
    if [[ "$query_lower" == *"my"* ]]; then
        jql="assignee = currentUser()"
        
        # Add status filters
        if [[ "$query_lower" == *"open"* || "$query_lower" == *"active"* ]]; then
            jql="$jql AND status not in (Done, Closed, Resolved)"
        fi
        
        # Add type filters
        if [[ "$query_lower" == *"bug"* ]]; then
            jql="$jql AND issuetype = Bug"
        elif [[ "$query_lower" == *"task"* ]]; then
            jql="$jql AND issuetype in (Task, Story)"
        fi
        
        echo "$jql"
        return 0
    fi
    
    # Handle priority queries
    if [[ "$query_lower" == *"high priority"* ]]; then
        jql="priority = High"
    elif [[ "$query_lower" == *"critical"* ]]; then
        jql="priority in (Critical, Highest)"
    fi
    
    # Handle status queries
    if [[ "$query_lower" == *"open"* || "$query_lower" == *"active"* ]]; then
        if [[ -n "$jql" ]]; then
            jql="$jql AND status not in (Done, Closed, Resolved)"
        else
            jql="status not in (Done, Closed, Resolved)"
        fi
    fi
    
    echo "$jql"
}

# Main routing function
smart_search() {
    local query="$1"
    local force_type="${2:-auto}"
    local max_results="${3:-25}"
    
    local route_decision
    route_decision=$(route_query "$query" "$force_type")
    
    echo "🧠 Query routing decision: $route_decision" >&2
    
    case "$route_decision" in
        "jql")
            search_jql "$query" "$max_results"
            ;;
        "nl")
            search_natural_language "$query" "$max_results"
            ;;
        "hybrid")
            search_hybrid "$query" "$max_results"
            ;;
        *)
            echo "❌ Unknown routing decision: $route_decision" >&2
            return 1
            ;;
    esac
}

# Explain routing decision for debugging
explain_routing() {
    local query="$1"
    
    echo "Query Analysis for: '$query'"
    echo "================================="
    
    local jql_confidence
    jql_confidence=$(detect_jql_syntax "$query")
    echo "JQL confidence score: $jql_confidence"
    
    local epic_type
    epic_type=$(detect_epic_query "$query")
    echo "Epic query type: $epic_type"
    
    local assignee_type
    assignee_type=$(detect_assignee_query "$query")
    echo "Assignee query type: $assignee_type"
    
    local status_priority_type
    status_priority_type=$(detect_status_priority_query "$query")
    echo "Status/Priority query type: $status_priority_type"
    
    local route_decision
    route_decision=$(route_query "$query")
    echo "Final routing decision: $route_decision"
    
    # Check auth state for context
    local auth_state
    if check_auth_state >/dev/null; then
        auth_state="authenticated"
    else
        auth_state="unauthenticated"
    fi
    echo "Authentication state: $auth_state"
}

# Test query routing with examples
test_routing() {
    local test_queries=(
        "my open issues"
        "assignee = john.doe"
        "status in (To Do, In Progress)"  
        "high priority bugs"
        "epic = PROJ-123"
        "agent encryption epic"
        "bugs in current sprint"
        "priority = High AND status != Done"
    )
    
    echo "Query Routing Test Results"
    echo "=========================="
    echo ""
    
    for query in "${test_queries[@]}"; do
        local route_decision
        route_decision=$(route_query "$query")
        printf "%-35s -> %s\n" "'$query'" "$route_decision"
    done
}

# Main function for CLI usage
main() {
    local query=""
    local action="search"
    local force_type="auto"
    local max_results=25
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --explain)
                action="explain"
                shift
                ;;
            --test)
                action="test"
                shift
                ;;
            --jql)
                force_type="jql"
                shift
                ;;
            --nl|--natural-language)
                force_type="nl"
                shift
                ;;
            --hybrid)
                force_type="hybrid"
                shift
                ;;
            --max-results)
                max_results="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS] <query>"
                echo ""
                echo "Options:"
                echo "  --explain            Explain routing decision"
                echo "  --test               Run routing tests"
                echo "  --jql                Force JQL search"
                echo "  --nl                 Force natural language search"
                echo "  --hybrid             Force hybrid search"
                echo "  --max-results NUM    Maximum results to return"
                echo "  -h, --help           Show this help"
                exit 0
                ;;
            *)
                query="$1"
                shift
                ;;
        esac
    done
    
    case "$action" in
        "explain")
            if [[ -z "$query" ]]; then
                echo "❌ Please provide a query to analyze" >&2
                exit 1
            fi
            explain_routing "$query"
            ;;
        "test")
            test_routing
            ;;
        "search")
            if [[ -z "$query" ]]; then
                echo "❌ Please provide a search query" >&2
                exit 1
            fi
            smart_search "$query" "$force_type" "$max_results"
            ;;
    esac
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi