#!/bin/bash

# Advanced Search Cache Library
# Provides intelligent caching with TTL, LRU eviction, and performance tracking

set -euo pipefail

# Constants
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

readonly CACHE_BASE_DIR="${HOME}/.cache/ccpm-jira"
readonly SEARCH_CACHE_DIR="${CACHE_BASE_DIR}/searches"
readonly CACHE_META_DIR="${CACHE_BASE_DIR}/meta"
readonly CACHE_STATS_FILE="${CACHE_META_DIR}/stats.json"
readonly CACHE_WARMUP_FILE="${CACHE_META_DIR}/warmup_queries.txt"
readonly DEFAULT_TTL=300 # 5 minutes
readonly MAX_CACHE_SIZE=100 # Maximum number of cached queries
readonly CACHE_SIZE_MB=50 # Maximum cache size in MB

# Initialize cache directories
init_cache() {
    mkdir -p "$SEARCH_CACHE_DIR" "$CACHE_META_DIR"
    
    # Initialize stats file if not exists
    if [[ ! -f "$CACHE_STATS_FILE" ]]; then
        echo '{"hits": 0, "misses": 0, "evictions": 0, "refreshes": 0, "total_queries": 0}' > "$CACHE_STATS_FILE"
    fi
    
    # Initialize warmup queries with defaults
    if [[ ! -f "$CACHE_WARMUP_FILE" ]]; then
        cat > "$CACHE_WARMUP_FILE" <<EOF
my open issues
status = "In Progress"
priority = High
assignee = currentUser() AND status != Done
created >= -7d
updated >= -1d
project = "${JIRA_PROJECT:-}"
EOF
    fi
}

# Generate cache key from query and parameters
generate_cache_key() {
    local query="$1"
    local search_type="${2:-auto}"
    local max_results="${3:-25}"
    local extra_params="${4:-}"
    
    local key_input="${search_type}:${query}:${max_results}:${extra_params}"
    echo "$key_input" | sha256sum | cut -d' ' -f1
}

# Get cache file paths for a key
get_cache_paths() {
    local cache_key="$1"
    
    echo "data:${SEARCH_CACHE_DIR}/${cache_key}"
    echo "meta:${SEARCH_CACHE_DIR}/${cache_key}.meta"
    echo "access:${SEARCH_CACHE_DIR}/${cache_key}.access"
}

# Update cache statistics
update_stats() {
    local stat_type="$1" # hits, misses, evictions, refreshes, total_queries
    local increment="${2:-1}"
    
    # Read current stats
    local stats
    stats=$(cat "$CACHE_STATS_FILE" 2>/dev/null || echo '{}')
    
    # Update specific stat
    stats=$(echo "$stats" | jq --arg type "$stat_type" --arg inc "$increment" \
        '.[$type] = ((.[$type] // 0) + ($inc | tonumber))')
    
    # Write back
    echo "$stats" > "$CACHE_STATS_FILE"
}

# Get cache entry age in seconds
get_cache_age() {
    local cache_key="$1"
    local meta_file="${SEARCH_CACHE_DIR}/${cache_key}.meta"
    
    if [[ -f "$meta_file" ]]; then
        local created_at
        created_at=$(jq -r '.created_at // 0' < "$meta_file")
        local current_time
        current_time=$(date +%s)
        echo $((current_time - created_at))
    else
        echo "999999" # Return large number if no metadata
    fi
}

# Check if cache entry is valid
is_cache_valid() {
    local cache_key="$1"
    local ttl="${2:-$DEFAULT_TTL}"
    
    local age
    age=$(get_cache_age "$cache_key")
    [[ $age -lt $ttl ]]
}

# Store data in cache with metadata
cache_put() {
    local cache_key="$1"
    local data="$2"
    local query="$3"
    local search_type="${4:-auto}"
    local ttl="${5:-$DEFAULT_TTL}"
    
    local data_file="${SEARCH_CACHE_DIR}/${cache_key}"
    local meta_file="${SEARCH_CACHE_DIR}/${cache_key}.meta"
    local access_file="${SEARCH_CACHE_DIR}/${cache_key}.access"
    
    # Store data
    echo "$data" > "$data_file"
    
    # Store metadata
    jq -n \
        --arg query "$query" \
        --arg search_type "$search_type" \
        --arg ttl "$ttl" \
        --arg created_at "$(date +%s)" \
        --arg size "$(stat -c%s "$data_file" 2>/dev/null || echo 0)" \
        '{
            query: $query,
            search_type: $search_type,
            ttl: ($ttl | tonumber),
            created_at: ($created_at | tonumber),
            size: ($size | tonumber),
            access_count: 1,
            last_accessed: ($created_at | tonumber)
        }' > "$meta_file"
    
    # Initialize access tracking
    echo "$(date +%s)" > "$access_file"
    
    # Perform cache maintenance if needed
    maintain_cache_size
}

# Retrieve data from cache
cache_get() {
    local cache_key="$1"
    local ttl="${2:-$DEFAULT_TTL}"
    
    local data_file="${SEARCH_CACHE_DIR}/${cache_key}"
    local meta_file="${SEARCH_CACHE_DIR}/${cache_key}.meta"
    local access_file="${SEARCH_CACHE_DIR}/${cache_key}.access"
    
    # Check if cache entry exists and is valid
    if [[ -f "$data_file" ]] && is_cache_valid "$cache_key" "$ttl"; then
        # Update access time and count
        echo "$(date +%s)" >> "$access_file"
        
        # Update metadata
        if [[ -f "$meta_file" ]]; then
            local meta
            meta=$(cat "$meta_file")
            meta=$(echo "$meta" | jq \
                --arg now "$(date +%s)" \
                '.last_accessed = ($now | tonumber) | .access_count += 1')
            echo "$meta" > "$meta_file"
        fi
        
        update_stats "hits"
        cat "$data_file"
        return 0
    else
        update_stats "misses"
        return 1
    fi
}

# Remove cache entry
cache_delete() {
    local cache_key="$1"
    
    rm -f "${SEARCH_CACHE_DIR}/${cache_key}" \
          "${SEARCH_CACHE_DIR}/${cache_key}.meta" \
          "${SEARCH_CACHE_DIR}/${cache_key}.access"
}

# Get cache entry metadata
cache_get_meta() {
    local cache_key="$1"
    local meta_file="${SEARCH_CACHE_DIR}/${cache_key}.meta"
    
    if [[ -f "$meta_file" ]]; then
        cat "$meta_file"
    else
        echo "{}"
    fi
}

# List all cache entries with metadata
cache_list() {
    local sort_by="${1:-last_accessed}" # last_accessed, access_count, size, age
    
    local entries="[]"
    
    for meta_file in "$SEARCH_CACHE_DIR"/*.meta; do
        [[ -f "$meta_file" ]] || continue
        
        local cache_key
        cache_key=$(basename "$meta_file" .meta)
        
        local meta
        meta=$(cat "$meta_file")
        
        # Add cache key to metadata
        meta=$(echo "$meta" | jq --arg key "$cache_key" '.key = $key')
        
        # Calculate age
        local age
        age=$(get_cache_age "$cache_key")
        meta=$(echo "$meta" | jq --arg age "$age" '.age = ($age | tonumber)')
        
        entries=$(echo "$entries" | jq --argjson entry "$meta" '. + [$entry]')
    done
    
    # Sort entries
    case "$sort_by" in
        "last_accessed")
            echo "$entries" | jq 'sort_by(.last_accessed) | reverse'
            ;;
        "access_count")
            echo "$entries" | jq 'sort_by(.access_count) | reverse'
            ;;
        "size")
            echo "$entries" | jq 'sort_by(.size) | reverse'
            ;;
        "age")
            echo "$entries" | jq 'sort_by(.age)'
            ;;
        *)
            echo "$entries"
            ;;
    esac
}

# Maintain cache size using LRU eviction
maintain_cache_size() {
    # Check number of cache entries
    local cache_count
    cache_count=$(find "$SEARCH_CACHE_DIR" -name "*.meta" | wc -l)
    
    if [[ $cache_count -gt $MAX_CACHE_SIZE ]]; then
        echo "🧹 Cache size exceeded ($cache_count > $MAX_CACHE_SIZE), performing LRU eviction..." >&2
        
        # Get entries sorted by last access time (oldest first)
        local entries_to_delete
        entries_to_delete=$((cache_count - MAX_CACHE_SIZE + 10)) # Remove 10 extra for headroom
        
        cache_list "last_accessed" | jq -r ".[0:$entries_to_delete] | .[].key" | while read -r cache_key; do
            echo "  Evicting: $(cache_get_meta "$cache_key" | jq -r '.query')" >&2
            cache_delete "$cache_key"
            update_stats "evictions"
        done
    fi
    
    # Check total cache size in MB
    local cache_size_bytes
    cache_size_bytes=$(du -sb "$SEARCH_CACHE_DIR" 2>/dev/null | cut -f1)
    local cache_size_mb=$((cache_size_bytes / 1024 / 1024))
    
    if [[ $cache_size_mb -gt $CACHE_SIZE_MB ]]; then
        echo "🧹 Cache disk usage exceeded (${cache_size_mb}MB > ${CACHE_SIZE_MB}MB), cleaning large entries..." >&2
        
        # Remove largest entries until under limit
        cache_list "size" | jq -r '.[].key' | while read -r cache_key; do
            cache_delete "$cache_key"
            update_stats "evictions"
            
            # Check if we're under limit now
            cache_size_bytes=$(du -sb "$SEARCH_CACHE_DIR" 2>/dev/null | cut -f1)
            cache_size_mb=$((cache_size_bytes / 1024 / 1024))
            [[ $cache_size_mb -lt $CACHE_SIZE_MB ]] && break
        done
    fi
}

# Clear entire cache
cache_clear() {
    local confirm="${1:-}"
    
    if [[ "$confirm" != "yes" ]]; then
        echo "⚠️  This will clear all cached search results." >&2
        echo "Run with 'yes' parameter to confirm: cache_clear yes" >&2
        return 1
    fi
    
    rm -rf "$SEARCH_CACHE_DIR"
    mkdir -p "$SEARCH_CACHE_DIR"
    echo "✅ Cache cleared" >&2
}

# Get cache statistics
cache_stats() {
    local format="${1:-human}" # human, json
    
    local stats
    stats=$(cat "$CACHE_STATS_FILE" 2>/dev/null || echo '{}')
    
    local cache_count
    cache_count=$(find "$SEARCH_CACHE_DIR" -name "*.meta" 2>/dev/null | wc -l)
    
    local cache_size_bytes
    cache_size_bytes=$(du -sb "$SEARCH_CACHE_DIR" 2>/dev/null | cut -f1 || echo 0)
    local cache_size_mb=$((cache_size_bytes / 1024 / 1024))
    
    # Add current state to stats
    stats=$(echo "$stats" | jq \
        --arg count "$cache_count" \
        --arg size_mb "$cache_size_mb" \
        '.current_entries = ($count | tonumber) | .size_mb = ($size_mb | tonumber)')
    
    # Calculate hit rate
    local hits
    hits=$(echo "$stats" | jq -r '.hits // 0')
    local total
    total=$(echo "$stats" | jq -r '.total_queries // 1')
    local hit_rate
    if [[ $total -gt 0 ]]; then
        hit_rate=$(echo "scale=2; $hits * 100 / $total" | bc)
    else
        hit_rate="0"
    fi
    
    stats=$(echo "$stats" | jq --arg rate "$hit_rate" '.hit_rate = ($rate | tonumber)')
    
    if [[ "$format" == "json" ]]; then
        echo "$stats"
    else
        echo "📊 Cache Statistics"
        echo "=================="
        echo "Current entries: $cache_count / $MAX_CACHE_SIZE"
        echo "Cache size: ${cache_size_mb}MB / ${CACHE_SIZE_MB}MB"
        echo "Hit rate: ${hit_rate}%"
        echo ""
        echo "Total queries: $(echo "$stats" | jq -r '.total_queries // 0')"
        echo "Cache hits: $(echo "$stats" | jq -r '.hits // 0')"
        echo "Cache misses: $(echo "$stats" | jq -r '.misses // 0')"
        echo "Evictions: $(echo "$stats" | jq -r '.evictions // 0')"
        echo "Refreshes: $(echo "$stats" | jq -r '.refreshes // 0')"
    fi
}

# Warm cache with common queries (background process)
cache_warm() {
    local background="${1:-true}"
    
    if [[ ! -f "$CACHE_WARMUP_FILE" ]]; then
        echo "❌ No warmup queries defined" >&2
        return 1
    fi
    
    if [[ "$background" == "true" ]]; then
        (
            echo "🔥 Starting cache warmup in background..." >&2
            while IFS= read -r query; do
                [[ -z "$query" || "$query" =~ ^[[:space:]]*# ]] && continue
                
                # Generate cache key
                local cache_key
                cache_key=$(generate_cache_key "$query" "auto" "25")
                
                # Check if already cached
                if ! is_cache_valid "$cache_key"; then
                    echo "  Warming: $query" >&2
                    # Source the search library and perform search
                    source "${SCRIPT_DIR}/search-mcp.sh"
                    if result=$(search_with_fallback "$query" "auto" "25" "false"); then
                        cache_put "$cache_key" "$result" "$query" "auto"
                        update_stats "refreshes"
                    fi
                fi
            done < "$CACHE_WARMUP_FILE"
            echo "✅ Cache warmup complete" >&2
        ) &
    else
        # Run in foreground
        while IFS= read -r query; do
            [[ -z "$query" || "$query" =~ ^[[:space:]]*# ]] && continue
            
            local cache_key
            cache_key=$(generate_cache_key "$query" "auto" "25")
            
            if ! is_cache_valid "$cache_key"; then
                echo "Warming: $query" >&2
                source "${SCRIPT_DIR}/search-mcp.sh"
                if result=$(search_with_fallback "$query" "auto" "25" "false"); then
                    cache_put "$cache_key" "$result" "$query" "auto"
                    update_stats "refreshes"
                fi
            fi
        done < "$CACHE_WARMUP_FILE"
    fi
}

# Add query to warmup list
add_warmup_query() {
    local query="$1"
    
    # Check if already exists
    if grep -Fxq "$query" "$CACHE_WARMUP_FILE" 2>/dev/null; then
        echo "Query already in warmup list" >&2
        return 0
    fi
    
    echo "$query" >> "$CACHE_WARMUP_FILE"
    echo "✅ Added to warmup list: $query" >&2
}

# Background cache refresh for frequently accessed queries
cache_refresh_frequent() {
    local min_access_count="${1:-5}"
    local background="${2:-true}"
    
    if [[ "$background" == "true" ]]; then
        (
            echo "🔄 Starting background refresh of frequent queries..." >&2
            cache_list "access_count" | jq -r --arg min "$min_access_count" \
                '.[] | select(.access_count >= ($min | tonumber)) | "\(.key):\(.query)"' | \
            while IFS=: read -r cache_key query; do
                if ! is_cache_valid "$cache_key"; then
                    echo "  Refreshing: $query" >&2
                    source "${SCRIPT_DIR}/search-mcp.sh"
                    if result=$(search_with_fallback "$query" "auto" "25" "false"); then
                        cache_put "$cache_key" "$result" "$query" "auto"
                        update_stats "refreshes"
                    fi
                fi
            done
            echo "✅ Frequent queries refreshed" >&2
        ) &
    else
        # Run in foreground
        cache_list "access_count" | jq -r --arg min "$min_access_count" \
            '.[] | select(.access_count >= ($min | tonumber)) | "\(.key):\(.query)"' | \
        while IFS=: read -r cache_key query; do
            if ! is_cache_valid "$cache_key"; then
                echo "Refreshing: $query" >&2
                source "${SCRIPT_DIR}/search-mcp.sh"
                if result=$(search_with_fallback "$query" "auto" "25" "false"); then
                    cache_put "$cache_key" "$result" "$query" "auto"
                    update_stats "refreshes"
                fi
            fi
        done
    fi
}

# Performance tracking for cache operations
track_performance() {
    local operation="$1" # get, put, search
    local duration="$2"  # in milliseconds
    local cache_hit="${3:-false}"
    
    local perf_file="${CACHE_META_DIR}/performance.jsonl"
    
    jq -n \
        --arg op "$operation" \
        --arg dur "$duration" \
        --arg hit "$cache_hit" \
        --arg ts "$(date +%s)" \
        '{
            timestamp: ($ts | tonumber),
            operation: $op,
            duration_ms: ($dur | tonumber),
            cache_hit: ($hit | test("true"))
        }' >> "$perf_file"
}

# Get performance metrics
get_performance_metrics() {
    local perf_file="${CACHE_META_DIR}/performance.jsonl"
    local time_range="${1:-3600}" # Last hour by default
    
    if [[ ! -f "$perf_file" ]]; then
        echo '{"error": "No performance data available"}'
        return
    fi
    
    local cutoff_time=$(($(date +%s) - time_range))
    
    # Calculate metrics
    jq -s --arg cutoff "$cutoff_time" '
        map(select(.timestamp >= ($cutoff | tonumber))) |
        group_by(.operation) |
        map({
            operation: .[0].operation,
            count: length,
            avg_duration_ms: (map(.duration_ms) | add / length),
            min_duration_ms: (map(.duration_ms) | min),
            max_duration_ms: (map(.duration_ms) | max),
            cache_hits: (map(select(.cache_hit)) | length),
            cache_hit_rate: ((map(select(.cache_hit)) | length) * 100 / length)
        })
    ' < "$perf_file"
}

# Main function for CLI usage
main() {
    local action="${1:-help}"
    shift || true
    
    init_cache
    
    case "$action" in
        "get")
            local cache_key="$1"
            cache_get "$cache_key"
            ;;
        "put")
            local cache_key="$1"
            local query="$2"
            local data
            data=$(cat)
            cache_put "$cache_key" "$data" "$query"
            ;;
        "delete")
            local cache_key="$1"
            cache_delete "$cache_key"
            ;;
        "list")
            local sort_by="${1:-last_accessed}"
            cache_list "$sort_by"
            ;;
        "stats")
            local format="${1:-human}"
            cache_stats "$format"
            ;;
        "clear")
            cache_clear "$@"
            ;;
        "warm")
            local background="${1:-true}"
            cache_warm "$background"
            ;;
        "refresh")
            local min_access="${1:-5}"
            local background="${2:-true}"
            cache_refresh_frequent "$min_access" "$background"
            ;;
        "add-warmup")
            local query="$1"
            add_warmup_query "$query"
            ;;
        "perf"|"performance")
            local time_range="${1:-3600}"
            get_performance_metrics "$time_range"
            ;;
        "help"|*)
            echo "Usage: $0 <action> [options]"
            echo ""
            echo "Actions:"
            echo "  get <key>                Get cached data"
            echo "  put <key> <query>        Store data (from stdin)"
            echo "  delete <key>             Delete cache entry"
            echo "  list [sort_by]           List cache entries"
            echo "  stats [format]           Show cache statistics"
            echo "  clear [yes]              Clear entire cache"
            echo "  warm [background]        Warm cache with common queries"
            echo "  refresh [min] [bg]       Refresh frequent queries"
            echo "  add-warmup <query>       Add query to warmup list"
            echo "  performance [seconds]    Show performance metrics"
            echo ""
            echo "Sort options for list: last_accessed, access_count, size, age"
            echo "Format options for stats: human, json"
            ;;
    esac
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi