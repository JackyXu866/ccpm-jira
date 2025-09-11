#!/bin/bash

# Saved Searches Management Library
# Provides functionality to save, manage, and execute named searches

set -euo pipefail

# Constants
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

readonly SAVED_SEARCHES_DIR="${HOME}/.config/ccpm-jira/searches"
readonly SAVED_SEARCHES_FILE="${SAVED_SEARCHES_DIR}/saved_searches.json"
readonly SEARCH_HISTORY_FILE="${SAVED_SEARCHES_DIR}/history.jsonl"
readonly DEFAULT_SEARCHES_FILE="${SAVED_SEARCHES_DIR}/defaults.json"
readonly SEARCH_SUGGESTIONS_FILE="${SAVED_SEARCHES_DIR}/suggestions.json"
readonly MAX_HISTORY_SIZE=1000

# Source required libraries
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${LIB_DIR}/search-mcp.sh"
source "${LIB_DIR}/query-router.sh"
source "${LIB_DIR}/search-formatters.sh"

# Initialize saved searches directory and files
init_saved_searches() {
    mkdir -p "$SAVED_SEARCHES_DIR"
    
    # Initialize saved searches file
    if [[ ! -f "$SAVED_SEARCHES_FILE" ]]; then
        echo '{}' > "$SAVED_SEARCHES_FILE"
    fi
    
    # Initialize default searches
    if [[ ! -f "$DEFAULT_SEARCHES_FILE" ]]; then
        create_default_searches
    fi
    
    # Initialize suggestions file
    if [[ ! -f "$SEARCH_SUGGESTIONS_FILE" ]]; then
        echo '[]' > "$SEARCH_SUGGESTIONS_FILE"
    fi
}

# Create default search templates
create_default_searches() {
    cat > "$DEFAULT_SEARCHES_FILE" <<'EOF'
{
    "my-tasks": {
        "query": "assignee = currentUser() AND status != Done",
        "type": "jql",
        "description": "All my open tasks"
    },
    "my-in-progress": {
        "query": "assignee = currentUser() AND status = \"In Progress\"",
        "type": "jql",
        "description": "My tasks currently in progress"
    },
    "urgent": {
        "query": "priority in (Critical, Highest) AND status not in (Done, Closed)",
        "type": "jql",
        "description": "High priority open issues"
    },
    "recent-updates": {
        "query": "updated >= -1d ORDER BY updated DESC",
        "type": "jql",
        "description": "Issues updated in the last 24 hours"
    },
    "my-reviews": {
        "query": "reviewer = currentUser() AND status = \"In Review\"",
        "type": "jql",
        "description": "Issues waiting for my review"
    },
    "blocked": {
        "query": "status = Blocked OR labels in (blocked)",
        "type": "jql",
        "description": "All blocked issues"
    },
    "sprint-active": {
        "query": "sprint in openSprints() AND project = \"${JIRA_PROJECT}\"",
        "type": "jql",
        "description": "Issues in current sprint"
    },
    "bugs-open": {
        "query": "issuetype = Bug AND status not in (Done, Closed, Resolved)",
        "type": "jql",
        "description": "All open bugs"
    },
    "epics": {
        "query": "issuetype = Epic AND project = \"${JIRA_PROJECT}\"",
        "type": "jql",
        "description": "All epics in project"
    },
    "no-assignee": {
        "query": "assignee is EMPTY AND status not in (Done, Closed)",
        "type": "jql",
        "description": "Unassigned open issues"
    }
}
EOF
}

# Save a named search
save_search() {
    local name="$1"
    local query="$2"
    local search_type="${3:-auto}"
    local description="${4:-}"
    local tags="${5:-}"
    
    # Validate name
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "❌ Search name must contain only letters, numbers, hyphens, and underscores" >&2
        return 1
    fi
    
    # Load existing searches
    local searches
    searches=$(cat "$SAVED_SEARCHES_FILE")
    
    # Create search object
    local search_obj
    search_obj=$(jq -n \
        --arg query "$query" \
        --arg type "$search_type" \
        --arg desc "$description" \
        --arg tags "$tags" \
        --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            query: $query,
            type: $type,
            description: $desc,
            tags: ($tags | split(",") | map(ltrimstr(" ") | rtrimstr(" "))),
            created: $created,
            updated: $updated,
            usage_count: 0,
            last_used: null
        }')
    
    # Add or update search
    searches=$(echo "$searches" | jq --arg name "$name" --argjson search "$search_obj" \
        '.[$name] = $search')
    
    # Save back to file
    echo "$searches" > "$SAVED_SEARCHES_FILE"
    
    echo "✅ Search saved as '$name'" >&2
}

# Get a saved search
get_saved_search() {
    local name="$1"
    
    # Check default searches first
    local search
    search=$(jq -r --arg name "$name" '.[$name] // empty' < "$DEFAULT_SEARCHES_FILE")
    
    # If not found, check user saved searches
    if [[ -z "$search" ]]; then
        search=$(jq -r --arg name "$name" '.[$name] // empty' < "$SAVED_SEARCHES_FILE")
    fi
    
    if [[ -z "$search" || "$search" == "null" ]]; then
        echo "❌ Saved search '$name' not found" >&2
        return 1
    fi
    
    echo "$search"
}

# List all saved searches
list_saved_searches() {
    local format="${1:-table}"
    local filter_tags="${2:-}"
    
    # Combine default and user searches
    local all_searches
    all_searches=$(jq -s '.[0] * .[1]' "$DEFAULT_SEARCHES_FILE" "$SAVED_SEARCHES_FILE" 2>/dev/null || echo '{}')
    
    # Apply tag filter if specified
    if [[ -n "$filter_tags" ]]; then
        all_searches=$(echo "$all_searches" | jq --arg tags "$filter_tags" '
            with_entries(select(.value.tags // [] | map(. == $tags) | any))
        ')
    fi
    
    case "$format" in
        "table")
            echo -e "${BOLD}NAME                 TYPE    USAGE   DESCRIPTION${RESET}"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "$all_searches" | jq -r '
                to_entries | .[] |
                "\(.key)\t\(.value.type // "auto")\t\(.value.usage_count // 0)\t\(.value.description // "")"
            ' | while IFS=$'\t' read -r name type usage desc; do
                printf "%-20s %-7s %-7s %s\n" "$name" "$type" "$usage" "${desc:0:40}"
            done
            ;;
        "json")
            echo "$all_searches"
            ;;
        "names")
            echo "$all_searches" | jq -r 'keys | .[]'
            ;;
        *)
            echo "❌ Unknown format: $format" >&2
            return 1
            ;;
    esac
}

# Execute a saved search
execute_saved_search() {
    local name="$1"
    local format="${2:-table}"
    local max_results="${3:-25}"
    
    # Get the saved search
    local search_json
    if ! search_json=$(get_saved_search "$name"); then
        return 1
    fi
    
    # Extract query and type
    local query
    query=$(echo "$search_json" | jq -r '.query')
    local search_type
    search_type=$(echo "$search_json" | jq -r '.type // "auto"')
    
    # Expand environment variables in query
    query=$(eval echo "\"$query\"")
    
    echo "🔍 Executing saved search: $name" >&2
    echo "📝 Query: $query" >&2
    echo "" >&2
    
    # Update usage statistics
    update_search_usage "$name"
    
    # Execute the search
    local results
    if results=$(smart_search "$query" "$search_type" "$max_results"); then
        # Add to history
        add_to_history "$query" "$search_type" "saved:$name"
        
        # Format and display results
        format_results "$format" "$results"
    else
        echo "❌ Search execution failed" >&2
        return 1
    fi
}

# Update usage statistics for a saved search
update_search_usage() {
    local name="$1"
    
    # Only update user saved searches, not defaults
    if jq -e --arg name "$name" '.[$name]' < "$SAVED_SEARCHES_FILE" >/dev/null 2>&1; then
        local searches
        searches=$(cat "$SAVED_SEARCHES_FILE")
        
        searches=$(echo "$searches" | jq --arg name "$name" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
            .[$name] |= (
                .usage_count = ((.usage_count // 0) + 1) |
                .last_used = $now
            )
        ')
        
        echo "$searches" > "$SAVED_SEARCHES_FILE"
    fi
}

# Edit a saved search
edit_saved_search() {
    local name="$1"
    local field="$2"
    local value="$3"
    
    # Check if search exists in user saves
    if ! jq -e --arg name "$name" '.[$name]' < "$SAVED_SEARCHES_FILE" >/dev/null 2>&1; then
        # If it's a default search, create a copy first
        if jq -e --arg name "$name" '.[$name]' < "$DEFAULT_SEARCHES_FILE" >/dev/null 2>&1; then
            local default_search
            default_search=$(jq --arg name "$name" '.[$name]' < "$DEFAULT_SEARCHES_FILE")
            
            local searches
            searches=$(cat "$SAVED_SEARCHES_FILE")
            searches=$(echo "$searches" | jq --arg name "$name" --argjson search "$default_search" \
                '.[$name] = $search')
            echo "$searches" > "$SAVED_SEARCHES_FILE"
        else
            echo "❌ Saved search '$name' not found" >&2
            return 1
        fi
    fi
    
    # Update the field
    local searches
    searches=$(cat "$SAVED_SEARCHES_FILE")
    
    case "$field" in
        "query")
            searches=$(echo "$searches" | jq --arg name "$name" --arg value "$value" \
                '.[$name].query = $value | .[$name].updated = now | todate')
            ;;
        "type")
            if [[ ! "$value" =~ ^(auto|jql|nl|hybrid)$ ]]; then
                echo "❌ Invalid type: $value (must be auto, jql, nl, or hybrid)" >&2
                return 1
            fi
            searches=$(echo "$searches" | jq --arg name "$name" --arg value "$value" \
                '.[$name].type = $value | .[$name].updated = now | todate')
            ;;
        "description")
            searches=$(echo "$searches" | jq --arg name "$name" --arg value "$value" \
                '.[$name].description = $value | .[$name].updated = now | todate')
            ;;
        "tags")
            searches=$(echo "$searches" | jq --arg name "$name" --arg value "$value" \
                '.[$name].tags = ($value | split(",") | map(ltrimstr(" ") | rtrimstr(" "))) | .[$name].updated = now | todate')
            ;;
        *)
            echo "❌ Unknown field: $field (valid fields: query, type, description, tags)" >&2
            return 1
            ;;
    esac
    
    echo "$searches" > "$SAVED_SEARCHES_FILE"
    echo "✅ Updated '$field' for search '$name'" >&2
}

# Delete a saved search
delete_saved_search() {
    local name="$1"
    local confirm="${2:-}"
    
    # Can't delete default searches
    if jq -e --arg name "$name" '.[$name]' < "$DEFAULT_SEARCHES_FILE" >/dev/null 2>&1; then
        echo "❌ Cannot delete default search '$name'" >&2
        return 1
    fi
    
    # Check if exists
    if ! jq -e --arg name "$name" '.[$name]' < "$SAVED_SEARCHES_FILE" >/dev/null 2>&1; then
        echo "❌ Saved search '$name' not found" >&2
        return 1
    fi
    
    if [[ "$confirm" != "yes" ]]; then
        echo "⚠️  Delete saved search '$name'? Type 'yes' to confirm:" >&2
        read -r response
        [[ "$response" != "yes" ]] && return 1
    fi
    
    # Delete the search
    local searches
    searches=$(cat "$SAVED_SEARCHES_FILE")
    searches=$(echo "$searches" | jq --arg name "$name" 'del(.[$name])')
    echo "$searches" > "$SAVED_SEARCHES_FILE"
    
    echo "✅ Deleted saved search '$name'" >&2
}

# Export saved searches
export_saved_searches() {
    local output_file="${1:-}"
    local include_defaults="${2:-false}"
    
    local searches
    if [[ "$include_defaults" == "true" ]]; then
        searches=$(jq -s '.[0] * .[1]' "$DEFAULT_SEARCHES_FILE" "$SAVED_SEARCHES_FILE")
    else
        searches=$(cat "$SAVED_SEARCHES_FILE")
    fi
    
    if [[ -n "$output_file" ]]; then
        echo "$searches" | jq '.' > "$output_file"
        echo "✅ Exported searches to: $output_file" >&2
    else
        echo "$searches" | jq '.'
    fi
}

# Import saved searches
import_saved_searches() {
    local input_file="$1"
    local merge="${2:-false}"
    
    if [[ ! -f "$input_file" ]]; then
        echo "❌ File not found: $input_file" >&2
        return 1
    fi
    
    # Validate JSON
    if ! jq '.' < "$input_file" >/dev/null 2>&1; then
        echo "❌ Invalid JSON in file: $input_file" >&2
        return 1
    fi
    
    local imported
    imported=$(cat "$input_file")
    
    if [[ "$merge" == "true" ]]; then
        # Merge with existing searches
        local existing
        existing=$(cat "$SAVED_SEARCHES_FILE")
        local merged
        merged=$(echo "$existing" "$imported" | jq -s '.[0] * .[1]')
        echo "$merged" > "$SAVED_SEARCHES_FILE"
        
        local count
        count=$(echo "$imported" | jq 'keys | length')
        echo "✅ Imported and merged $count searches" >&2
    else
        # Replace existing searches
        cp "$SAVED_SEARCHES_FILE" "${SAVED_SEARCHES_FILE}.bak"
        echo "$imported" > "$SAVED_SEARCHES_FILE"
        
        local count
        count=$(echo "$imported" | jq 'keys | length')
        echo "✅ Imported $count searches (backup saved to ${SAVED_SEARCHES_FILE}.bak)" >&2
    fi
}

# Add search to history
add_to_history() {
    local query="$1"
    local search_type="${2:-auto}"
    local source="${3:-manual}"
    
    # Create history entry
    local entry
    entry=$(jq -n \
        --arg query "$query" \
        --arg type "$search_type" \
        --arg source "$source" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            query: $query,
            type: $type,
            source: $source,
            timestamp: $timestamp
        }')
    
    # Append to history
    echo "$entry" >> "$SEARCH_HISTORY_FILE"
    
    # Maintain history size
    if [[ $(wc -l < "$SEARCH_HISTORY_FILE") -gt $MAX_HISTORY_SIZE ]]; then
        tail -n $MAX_HISTORY_SIZE "$SEARCH_HISTORY_FILE" > "${SEARCH_HISTORY_FILE}.tmp"
        mv "${SEARCH_HISTORY_FILE}.tmp" "$SEARCH_HISTORY_FILE"
    fi
    
    # Update suggestions based on history
    update_suggestions
}

# Get search history
get_search_history() {
    local limit="${1:-20}"
    local unique="${2:-true}"
    
    if [[ ! -f "$SEARCH_HISTORY_FILE" ]]; then
        echo "[]"
        return
    fi
    
    if [[ "$unique" == "true" ]]; then
        # Get unique queries with their latest timestamp
        tac "$SEARCH_HISTORY_FILE" | jq -s '
            group_by(.query) |
            map(.[0]) |
            .[0:'$limit']
        '
    else
        # Get raw history
        tac "$SEARCH_HISTORY_FILE" | head -n "$limit" | jq -s '.'
    fi
}

# Update search suggestions based on history
update_suggestions() {
    if [[ ! -f "$SEARCH_HISTORY_FILE" ]]; then
        return
    fi
    
    # Analyze history for patterns
    local suggestions="[]"
    
    # Most frequently used queries
    local frequent
    frequent=$(jq -s '
        group_by(.query) |
        map({query: .[0].query, count: length}) |
        sort_by(.count) | reverse |
        .[0:10] |
        map(.query)
    ' < "$SEARCH_HISTORY_FILE")
    
    suggestions=$(echo "$suggestions" | jq --argjson freq "$frequent" \
        '. + ($freq | map({type: "frequent", value: .}))')
    
    # Recent unique queries
    local recent
    recent=$(get_search_history 10 true | jq 'map(.query)')
    
    suggestions=$(echo "$suggestions" | jq --argjson rec "$recent" \
        '. + ($rec | map({type: "recent", value: .}))')
    
    # Extract common patterns
    local patterns
    patterns=$(jq -r '.query' < "$SEARCH_HISTORY_FILE" | \
        grep -oP '(status|priority|assignee|project|type)\s*[=~]\s*[^AND]+' | \
        sort | uniq -c | sort -nr | head -10 | \
        awk '{$1=""; print $0}' | sed 's/^ //' | jq -R -s 'split("\n") | map(select(. != ""))')
    
    suggestions=$(echo "$suggestions" | jq --argjson pat "$patterns" \
        '. + ($pat | map({type: "pattern", value: .}))')
    
    # Save suggestions
    echo "$suggestions" | jq 'unique_by(.value)' > "$SEARCH_SUGGESTIONS_FILE"
}

# Get search suggestions
get_suggestions() {
    local prefix="${1:-}"
    local limit="${2:-10}"
    
    if [[ ! -f "$SEARCH_SUGGESTIONS_FILE" ]]; then
        echo "[]"
        return
    fi
    
    local suggestions
    suggestions=$(cat "$SEARCH_SUGGESTIONS_FILE")
    
    # Filter by prefix if provided
    if [[ -n "$prefix" ]]; then
        suggestions=$(echo "$suggestions" | jq --arg prefix "$prefix" \
            'map(select(.value | startswith($prefix)))')
    fi
    
    # Return limited results
    echo "$suggestions" | jq ".[0:$limit]"
}

# Fuzzy search for issue titles
fuzzy_search_titles() {
    local pattern="$1"
    local max_results="${2:-25}"
    
    echo "🔍 Performing fuzzy search for: $pattern" >&2
    
    # Build a fuzzy JQL query
    local fuzzy_query="summary ~ \"$pattern*\" OR description ~ \"$pattern*\""
    
    # Execute search
    search_jql "$fuzzy_query" "$max_results"
}

# Interactive search with suggestions
interactive_search() {
    echo "📝 Interactive Search Mode" >&2
    echo "=========================" >&2
    
    # Show saved searches
    echo "" >&2
    echo "Saved searches:" >&2
    list_saved_searches "names" | head -10 | sed 's/^/  - /' >&2
    
    # Show recent searches
    echo "" >&2
    echo "Recent searches:" >&2
    get_search_history 5 true | jq -r '.[].query' | sed 's/^/  - /' >&2
    
    # Show suggestions
    echo "" >&2
    echo "Suggestions:" >&2
    get_suggestions "" 5 | jq -r '.[] | "  - \(.value) [\(.type)]"' >&2
    
    echo "" >&2
    echo -n "Enter search query (or saved search name): " >&2
    read -r query
    
    if [[ -z "$query" ]]; then
        echo "❌ No query provided" >&2
        return 1
    fi
    
    # Check if it's a saved search
    if get_saved_search "$query" >/dev/null 2>&1; then
        execute_saved_search "$query"
    else
        # Execute as regular query
        add_to_history "$query" "auto" "interactive"
        smart_search "$query" "auto" "25"
    fi
}

# Main function for CLI usage
main() {
    local action="${1:-help}"
    shift || true
    
    init_saved_searches
    
    case "$action" in
        "save")
            local name="$1"
            local query="$2"
            local type="${3:-auto}"
            local description="${4:-}"
            local tags="${5:-}"
            save_search "$name" "$query" "$type" "$description" "$tags"
            ;;
        "list")
            local format="${1:-table}"
            local tags="${2:-}"
            list_saved_searches "$format" "$tags"
            ;;
        "exec"|"execute"|"run")
            local name="$1"
            local format="${2:-table}"
            local max_results="${3:-25}"
            execute_saved_search "$name" "$format" "$max_results"
            ;;
        "get"|"show")
            local name="$1"
            get_saved_search "$name" | jq '.'
            ;;
        "edit")
            local name="$1"
            local field="$2"
            local value="$3"
            edit_saved_search "$name" "$field" "$value"
            ;;
        "delete"|"remove")
            local name="$1"
            local confirm="${2:-}"
            delete_saved_search "$name" "$confirm"
            ;;
        "export")
            local file="${1:-}"
            local include_defaults="${2:-false}"
            export_saved_searches "$file" "$include_defaults"
            ;;
        "import")
            local file="$1"
            local merge="${2:-false}"
            import_saved_searches "$file" "$merge"
            ;;
        "history")
            local limit="${1:-20}"
            local unique="${2:-true}"
            get_search_history "$limit" "$unique" | jq '.'
            ;;
        "suggest"|"suggestions")
            local prefix="${1:-}"
            local limit="${2:-10}"
            get_suggestions "$prefix" "$limit" | jq '.'
            ;;
        "fuzzy")
            local pattern="$1"
            local max_results="${2:-25}"
            fuzzy_search_titles "$pattern" "$max_results"
            ;;
        "interactive"|"i")
            interactive_search
            ;;
        "help"|*)
            echo "Usage: $0 <action> [options]"
            echo ""
            echo "Actions:"
            echo "  save <name> <query> [type] [desc] [tags]   Save a named search"
            echo "  list [format] [tags]                        List saved searches"
            echo "  exec <name> [format] [max]                  Execute saved search"
            echo "  get <name>                                  Show search details"
            echo "  edit <name> <field> <value>                 Edit search field"
            echo "  delete <name> [yes]                         Delete saved search"
            echo "  export [file] [include_defaults]            Export searches"
            echo "  import <file> [merge]                       Import searches"
            echo "  history [limit] [unique]                    Show search history"
            echo "  suggest [prefix] [limit]                    Get suggestions"
            echo "  fuzzy <pattern> [max]                       Fuzzy title search"
            echo "  interactive                                 Interactive search"
            echo ""
            echo "List formats: table, json, names"
            echo "Search types: auto, jql, nl, hybrid"
            echo "Edit fields: query, type, description, tags"
            ;;
    esac
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi