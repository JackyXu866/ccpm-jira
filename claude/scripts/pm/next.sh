#!/bin/bash

# Enhanced next command with intelligent Jira integration
# Finds next available tasks using both local epic data and Jira queries

set -euo pipefail

# Constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required libraries
source "${SCRIPT_DIR}/../../lib/search-mcp.sh"
source "${SCRIPT_DIR}/../../lib/query-router.sh"
source "${SCRIPT_DIR}/../../lib/search-formatters.sh"
source "${SCRIPT_DIR}/../../lib/saved-searches.sh"
source "${SCRIPT_DIR}/../../lib/search-cache.sh"

# Initialize cache directories
init_cache_dirs

# Default values
include_jira=true
include_local=true
limit=10
format="table"
show_reasoning=true
priority_filter=""
assignee_filter=""
project_filter=""
status_filter=""
show_help=false
use_cache=true
saved_search=""

# Function to show usage
show_usage() {
    echo "Usage: pm:next [OPTIONS]"
    echo ""
    echo "Find next available tasks to work on using local epic data and Jira queries"
    echo ""
    echo "Options:"
    echo "  --local-only         Search only in local epic files"
    echo "  --jira-only          Search only in Jira issues"
    echo "  --limit NUM          Maximum tasks to show (default: 10)"
    echo "  --format FORMAT      Output format: table, list, detailed (default: table)"
    echo "  --no-reasoning       Don't show why each task is suggested"
    echo "  --priority PRIORITY  Filter by priority (High, Medium, Low, etc.)"
    echo "  --assignee USER      Filter by assignee (use 'me' for current user, 'unassigned' for unassigned)"
    echo "  --project PROJECT    Filter by project key"
    echo "  --status STATUS      Filter by status (default: open/in-progress statuses)"
    echo "  --no-cache           Don't use cached results"
    echo "  --saved NAME         Use a saved search as base (e.g., 'my-tasks')"
    echo "  -h, --help           Show this help"
    echo ""
    echo "Examples:"
    echo "  pm:next                                    # Show all available tasks"
    echo "  pm:next --jira-only --priority High        # High priority Jira tasks only"
    echo "  pm:next --assignee me --limit 5            # My tasks, limit to 5"
    echo "  pm:next --assignee unassigned --priority High  # High priority unassigned tasks"
    echo "  pm:next --local-only                       # Local epic tasks only"
}

# Function to get current user info
get_current_user() {
    local user_info
    if user_info=$(claude mcp__atlassian__atlassianUserInfo 2>/dev/null); then
        echo "$user_info" | jq -r '.accountId // .displayName // "currentUser()"' 2>/dev/null || echo "currentUser()"
    else
        echo "currentUser()"
    fi
}

# Function to find local next tasks (original functionality)
find_local_next_tasks() {
    local limit="$1"
    local found=0
    local tasks=()
    
    echo "📋 Local Next Available Tasks" >&2
    echo "=============================" >&2
    echo "" >&2
    
    for epic_dir in .claude/epics/*/; do
        [[ -d "$epic_dir" ]] || continue
        local epic_name
        epic_name=$(basename "$epic_dir")
        
        for task_file in "$epic_dir"[0-9]*.md; do
            [[ -f "$task_file" ]] || continue
            [[ $found -ge $limit ]] && break 2
            
            # Check if task is open or not started
            local status
            status=$(grep "^status:" "$task_file" | head -1 | sed 's/^status: *//' || echo "open")
            [[ "$status" != "open" && "$status" != "not_started" && -n "$status" ]] && continue
            
            # Check dependencies
            local deps
            deps=$(grep "^depends_on:" "$task_file" | head -1 | sed 's/^depends_on: *\[//' | sed 's/\]//' || echo "")
            
            # If no dependencies or empty, task is available
            if [[ -z "$deps" || "$deps" == "depends_on:" ]]; then
                local task_name
                task_name=$(grep "^title:" "$task_file" | head -1 | sed 's/^title: *//' || grep "^name:" "$task_file" | head -1 | sed 's/^name: *//' || echo "Untitled")
                local task_num
                task_num=$(basename "$task_file" .md)
                local parallel
                parallel=$(grep "^parallel:" "$task_file" | head -1 | sed 's/^parallel: *//' || echo "false")
                local priority
                priority=$(grep "^priority:" "$task_file" | head -1 | sed 's/^priority: *//' || echo "medium")
                local size
                size=$(grep "^size:" "$task_file" | head -1 | sed 's/^size: *//' || echo "unknown")
                
                # Create task entry
                local reason="Ready to start"
                [[ "$parallel" == "true" ]] && reason="$reason (can run in parallel)"
                [[ -z "$deps" ]] && reason="$reason (no dependencies)"
                
                # Add to tasks array
                tasks+=("{\"key\":\"#$task_num\",\"summary\":\"$task_name\",\"status\":\"$status\",\"priority\":\"$priority\",\"epic\":\"$epic_name\",\"size\":\"$size\",\"reason\":\"$reason\",\"source\":\"local\"}")
                ((found++))
            fi
        done
    done
    
    # Output as JSON array
    local json_output="["
    local first=true
    for task in "${tasks[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            json_output+=","
        fi
        json_output+="$task"
    done
    json_output+="]"
    
    echo "$json_output"
    return $((found > 0 ? 0 : 1))
}

# Function to build JQL query for next tasks
build_next_tasks_jql() {
    local assignee_filter="$1"
    local priority_filter="$2"
    local project_filter="$3"
    local status_filter="$4"
    
    local jql_parts=()
    
    # Default: exclude completed statuses, focus on actionable items
    if [[ -z "$status_filter" ]]; then
        jql_parts+=("status not in (Done, Closed, Resolved, Complete, Cancelled)")
    else
        jql_parts+=("status = \"$status_filter\"")
    fi
    
    # Assignee filter
    if [[ "$assignee_filter" == "me" ]]; then
        jql_parts+=("assignee = currentUser()")
    elif [[ "$assignee_filter" == "unassigned" ]]; then
        jql_parts+=("assignee is EMPTY")
    elif [[ -n "$assignee_filter" ]]; then
        jql_parts+=("assignee = \"$assignee_filter\"")
    fi
    
    # Priority filter
    if [[ -n "$priority_filter" ]]; then
        jql_parts+=("priority = \"$priority_filter\"")
    fi
    
    # Project filter
    if [[ -n "$project_filter" ]]; then
        jql_parts+=("project = \"$project_filter\"")
    fi
    
    # Smart ordering: priority first, then ready-to-start items, then by creation date
    local jql
    jql=$(IFS=" AND "; echo "${jql_parts[*]}")
    jql="$jql ORDER BY priority DESC, status = 'To Do' DESC, assignee is EMPTY DESC, created ASC"
    
    echo "$jql"
}

# Function to find Jira next tasks
find_jira_next_tasks() {
    local limit="$1"
    local assignee_filter="$2"
    local priority_filter="$3"
    local project_filter="$4"
    local status_filter="$5"
    local use_cache="$6"
    local saved_search="$7"
    
    echo "🎫 Jira Next Available Tasks" >&2
    echo "============================" >&2
    echo "" >&2
    
    # If using saved search, execute it instead
    if [[ -n "$saved_search" ]]; then
        echo "📚 Using saved search: $saved_search" >&2
        local search_json
        if search_json=$(get_saved_search "$saved_search"); then
            local query
            query=$(echo "$search_json" | jq -r '.query')
            local search_type
            search_type=$(echo "$search_json" | jq -r '.type // "auto"')
            
            # Expand environment variables
            query=$(eval echo "\"$query\"")
            
            echo "🔍 Query: $query" >&2
            echo "" >&2
            
            # Track performance
            local start_time=$(date +%s%N)
            
            # Check cache first if enabled
            if [[ "$use_cache" == "true" ]]; then
                local cache_key
                cache_key=$(generate_cache_key "$query" "$search_type" "$limit")
                local cached_results
                if cached_results=$(cache_get "$cache_key"); then
                    echo "📋 Using cached results..." >&2
                    local end_time=$(date +%s%N)
                    local duration=$(( (end_time - start_time) / 1000000 ))
                    track_performance "next-search" "$duration" "true"
                    echo "$cached_results"
                    return 0
                fi
            fi
            
            # Execute search
            local results
            if [[ "$search_type" == "jql" ]]; then
                results=$(search_jql "$query" "$limit")
            else
                results=$(smart_search "$query" "$search_type" "$limit")
            fi
            
            if [[ $? -eq 0 && -n "$results" ]]; then
                # Cache results
                if [[ "$use_cache" == "true" ]]; then
                    local cache_key
                    cache_key=$(generate_cache_key "$query" "$search_type" "$limit")
                    cache_put "$cache_key" "$results" "$query" "$search_type"
                fi
                
                # Track performance
                local end_time=$(date +%s%N)
                local duration=$(( (end_time - start_time) / 1000000 ))
                track_performance "next-search" "$duration" "false"
                
                echo "$results"
                return 0
            else
                return 1
            fi
        else
            echo "❌ Saved search '$saved_search' not found" >&2
            return 1
        fi
    fi
    
    # Build intelligent JQL query
    local jql
    jql=$(build_next_tasks_jql "$assignee_filter" "$priority_filter" "$project_filter" "$status_filter")
    
    echo "🔍 Query: $jql" >&2
    echo "" >&2
    
    # Track performance
    local start_time=$(date +%s%N)
    
    # Check cache first if enabled
    if [[ "$use_cache" == "true" ]]; then
        local cache_key
        cache_key=$(generate_cache_key "$jql" "jql" "$limit")
        local cached_results
        if cached_results=$(cache_get "$cache_key"); then
            echo "📋 Using cached results..." >&2
            local end_time=$(date +%s%N)
            local duration=$(( (end_time - start_time) / 1000000 ))
            track_performance "next-jql" "$duration" "true"
            echo "$cached_results"
            return 0
        fi
    fi
    
    # Execute search
    local results
    if results=$(search_jql "$jql" "$limit"); then
        # Cache results
        if [[ "$use_cache" == "true" ]]; then
            local cache_key
            cache_key=$(generate_cache_key "$jql" "jql" "$limit")
            cache_put "$cache_key" "$results" "$jql" "jql"
        fi
        
        # Track performance
        local end_time=$(date +%s%N)
        local duration=$(( (end_time - start_time) / 1000000 ))
        track_performance "next-jql" "$duration" "false"
        
        # Add reasoning to each result
        local enhanced_results
        enhanced_results=$(echo "$results" | jq --arg reasoning "Available for assignment" '
            if type == "object" and has("issues") then
                .issues[] |= . + {"reason": $reasoning, "source": "jira"}
            elif type == "array" then
                .[] |= . + {"reason": $reasoning, "source": "jira"}
            else
                . + {"reason": $reasoning, "source": "jira"}
            end
        ' 2>/dev/null || echo "$results")
        
        echo "$enhanced_results"
        return 0
    else
        echo "❌ Jira search failed or returned no results" >&2
        return 1
    fi
}

# Function to enhance task recommendations with reasoning
add_task_reasoning() {
    local task_data="$1"
    local source="$2"
    
    echo "$task_data" | jq --arg src "$source" '
        if type == "array" then
            .[] |= . + {
                "reason": (
                    if .status == "To Do" or .status == "Open" then
                        if (.priority // "") | test("High|Critical|Highest") then "High priority, ready to start"
                        elif .assignee == null or .assignee == "Unassigned" then "Unassigned and ready to start" 
                        else "Ready to start"
                    elif .status == "In Progress" then "Currently in progress"
                    elif .assignee == null or .assignee == "Unassigned" then 
                        if (.priority // "") | test("High|Critical|Highest") then "High priority, available for assignment"
                        else "Available for assignment"
                    elif (.priority // "") | test("High|Critical|Highest") then "High priority task"
                    else "Available task"
                    end
                ),
                "source": $src
            }
        else
            . + {
                "reason": (
                    if .status == "To Do" or .status == "Open" then
                        if (.priority // "") | test("High|Critical|Highest") then "High priority, ready to start"
                        elif .assignee == null or .assignee == "Unassigned" then "Unassigned and ready to start" 
                        else "Ready to start"
                    elif .status == "In Progress" then "Currently in progress"
                    elif .assignee == null or .assignee == "Unassigned" then 
                        if (.priority // "") | test("High|Critical|Highest") then "High priority, available for assignment"
                        else "Available for assignment"
                    elif (.priority // "") | test("High|Critical|Highest") then "High priority task"
                    else "Available task"
                    end
                ),
                "source": $src
            }
        end
    ' 2>/dev/null || echo "$task_data"
}

# Function to merge and deduplicate tasks from multiple sources
merge_task_sources() {
    local local_tasks="$1"
    local jira_tasks="$2"
    local limit="$3"
    
    # Combine arrays
    local combined
    if [[ -n "$local_tasks" && -n "$jira_tasks" ]]; then
        combined=$(echo "$local_tasks" "$jira_tasks" | jq -s 'add | sort_by(.priority == "High", .priority == "Critical", .priority == "Highest") | reverse | .[0:'"$limit"']' 2>/dev/null)
    elif [[ -n "$local_tasks" ]]; then
        combined="$local_tasks"
    elif [[ -n "$jira_tasks" ]]; then
        combined="$jira_tasks"
    else
        combined="[]"
    fi
    
    echo "$combined"
}

# Function to format next tasks output
format_next_tasks() {
    local tasks_json="$1"
    local format="$2"
    local show_reasoning="$3"
    
    if [[ -z "$tasks_json" || "$tasks_json" == "[]" ]]; then
        echo "No available tasks found."
        return 0
    fi
    
    case "$format" in
        "table")
            # Table header
            if [[ "$show_reasoning" == "true" ]]; then
                printf "%-12s %-40s %-12s %-8s %-15s %-30s\n" \
                    "KEY" "SUMMARY" "STATUS" "PRIORITY" "SOURCE" "REASON"
                printf "%-12s %-40s %-12s %-8s %-15s %-30s\n" \
                    "$(printf '%.12s' '============')" \
                    "$(printf '%.40s' '========================================')" \
                    "$(printf '%.12s' '============')" \
                    "$(printf '%.8s' '========')" \
                    "$(printf '%.15s' '===============')" \
                    "$(printf '%.30s' '==============================')"
            else
                printf "%-12s %-40s %-12s %-8s %-15s\n" \
                    "KEY" "SUMMARY" "STATUS" "PRIORITY" "SOURCE"
                printf "%-12s %-40s %-12s %-8s %-15s\n" \
                    "$(printf '%.12s' '============')" \
                    "$(printf '%.40s' '========================================')" \
                    "$(printf '%.12s' '============')" \
                    "$(printf '%.8s' '========')" \
                    "$(printf '%.15s' '===============')"
            fi
            
            # Table rows
            if [[ "$show_reasoning" == "true" ]]; then
                echo "$tasks_json" | jq -r '.[] | "\(.key // "N/A")\t\(.summary // .title // "N/A")\t\(.status // "N/A")\t\(.priority // "N/A")\t\(.source // "N/A")\t\(.reason // "N/A")"' | \
                while IFS=$'\t' read -r key summary status priority source reason; do
                    local short_summary
                    short_summary=$(printf '%.40s' "$summary")
                    [[ ${#summary} -gt 40 ]] && short_summary="${short_summary:0:37}..."
                    
                    local short_reason
                    short_reason=$(printf '%.30s' "$reason")
                    [[ ${#reason} -gt 30 ]] && short_reason="${short_reason:0:27}..."
                    
                    printf "%-12s %-40s %-12s %-8s %-15s %-30s\n" \
                        "$key" "$short_summary" "$status" "$priority" "$source" "$short_reason"
                done
            else
                echo "$tasks_json" | jq -r '.[] | "\(.key // "N/A")\t\(.summary // .title // "N/A")\t\(.status // "N/A")\t\(.priority // "N/A")\t\(.source // "N/A")"' | \
                while IFS=$'\t' read -r key summary status priority source; do
                    local short_summary
                    short_summary=$(printf '%.40s' "$summary")
                    [[ ${#summary} -gt 40 ]] && short_summary="${short_summary:0:37}..."
                    
                    printf "%-12s %-40s %-12s %-8s %-15s\n" \
                        "$key" "$short_summary" "$status" "$priority" "$source"
                done
            fi
            ;;
        "list")
            echo "$tasks_json" | jq -r '.[] | 
                if (.reason // "") != "" then
                    "• \(.key // "N/A") - \(.summary // .title // "N/A") [\(.status // "N/A")] (\(.reason // "N/A"))"
                else
                    "• \(.key // "N/A") - \(.summary // .title // "N/A") [\(.status // "N/A")]"
                end'
            ;;
        "detailed")
            echo "$tasks_json" | jq -r '.[] | [
                "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
                "🎫 Task: \(.key // "N/A")",
                "📝 Summary: \(.summary // .title // "N/A")",
                "📊 Status: \(.status // "N/A")",
                "⚡ Priority: \(.priority // "N/A")",
                "📂 Source: \(.source // "N/A")",
                if .epic then "📚 Epic: \(.epic)" else empty end,
                if .size then "📏 Size: \(.size)" else empty end,
                if .reason then "💡 Reason: \(.reason)" else empty end,
                ""
            ] | .[]'
            ;;
        *)
            echo "❌ Unknown format: $format" >&2
            return 1
            ;;
    esac
}

# Main function
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --local-only)
                include_jira=false
                shift
                ;;
            --jira-only)
                include_local=false
                shift
                ;;
            --limit)
                limit="$2"
                shift 2
                ;;
            --format)
                format="$2"
                shift 2
                ;;
            --no-reasoning)
                show_reasoning=false
                shift
                ;;
            --priority)
                priority_filter="$2"
                shift 2
                ;;
            --assignee)
                assignee_filter="$2"
                shift 2
                ;;
            --project)
                project_filter="$2"
                shift 2
                ;;
            --status)
                status_filter="$2"
                shift 2
                ;;
            --no-cache)
                use_cache=false
                shift
                ;;
            --saved)
                saved_search="$2"
                shift 2
                ;;
            -h|--help)
                show_help=true
                shift
                ;;
            -*)
                echo "❌ Unknown option: $1" >&2
                echo "Use --help for usage information" >&2
                exit 1
                ;;
            *)
                echo "❌ Unexpected argument: $1" >&2
                echo "Use --help for usage information" >&2
                exit 1
                ;;
        esac
    done
    
    # Show help if requested
    if [[ "$show_help" == "true" ]]; then
        show_usage
        exit 0
    fi
    
    # Validate format
    case "$format" in
        "table"|"list"|"detailed")
            # Valid format
            ;;
        *)
            echo "❌ Invalid format: $format" >&2
            echo "Valid formats: table, list, detailed" >&2
            exit 1
            ;;
    esac
    
    # Find tasks from requested sources
    local local_tasks=""
    local jira_tasks=""
    
    if [[ "$include_local" == "true" ]]; then
        local_tasks=$(find_local_next_tasks "$limit")
    fi
    
    if [[ "$include_jira" == "true" ]]; then
        jira_tasks=$(find_jira_next_tasks "$limit" "$assignee_filter" "$priority_filter" "$project_filter" "$status_filter" "$use_cache" "$saved_search")
    fi
    
    # Merge and format results
    local all_tasks
    all_tasks=$(merge_task_sources "$local_tasks" "$jira_tasks" "$limit")
    
    local task_count
    task_count=$(echo "$all_tasks" | jq length 2>/dev/null || echo 0)
    
    echo "📋 Next Available Tasks ($task_count found)"
    echo "==========================================="
    echo ""
    
    if [[ $task_count -eq 0 ]]; then
        echo "No available tasks found."
        echo ""
        echo "💡 Suggestions:"
        echo "  • Check blocked tasks: pm:blocked"
        echo "  • View all tasks: pm:epic-list"
        echo "  • Search for specific tasks: pm:search <query>"
        return 0
    fi
    
    format_next_tasks "$all_tasks" "$format" "$show_reasoning"
    
    echo ""
    echo "📊 Summary: $task_count tasks ready to start"
    
    if [[ "$include_jira" == "true" && "$assignee_filter" != "me" ]]; then
        echo "💡 Tip: Use --assignee me to see only your assigned tasks"
    fi
}

# Run main function
main "$@"