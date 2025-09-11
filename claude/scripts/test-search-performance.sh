#!/bin/bash

# Test script for search caching and saved searches performance
# Tests cache hits, saved searches, and performance metrics

set -euo pipefail

# Constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libraries
source "${SCRIPT_DIR}/../lib/search-cache.sh"
source "${SCRIPT_DIR}/../lib/saved-searches.sh"

# Initialize
init_cache
init_saved_searches

echo "🧪 Search Performance Test Suite"
echo "================================"
echo ""

# Test 1: Cache performance
echo "📊 Test 1: Cache Performance"
echo "---------------------------"

# Clear cache first
cache_clear yes >/dev/null 2>&1

# Test queries
test_queries=(
    "status = \"In Progress\""
    "assignee = currentUser()"
    "priority = High"
    "created >= -7d"
)

for query in "${test_queries[@]}"; do
    echo ""
    echo "Testing: $query"
    
    # First search (cache miss)
    start_time=$(date +%s%N)
    cache_key=$(generate_cache_key "$query" "jql" "25")
    echo "Test data for $query" | cache_put "$cache_key" - "$query" "jql"
    end_time=$(date +%s%N)
    miss_time=$(( (end_time - start_time) / 1000000 ))
    echo "  Cache write: ${miss_time}ms"
    
    # Second search (cache hit)
    start_time=$(date +%s%N)
    result=$(cache_get "$cache_key")
    end_time=$(date +%s%N)
    hit_time=$(( (end_time - start_time) / 1000000 ))
    echo "  Cache read: ${hit_time}ms"
    echo "  Speedup: $(( miss_time / (hit_time + 1) ))x"
done

# Test 2: Saved searches
echo ""
echo ""
echo "📚 Test 2: Saved Searches"
echo "------------------------"

# Create test saved searches
save_search "test-high-priority" "priority = High AND status != Done" "jql" "High priority open tasks" >/dev/null
save_search "test-my-tasks" "assignee = currentUser()" "jql" "My assigned tasks" >/dev/null
save_search "test-recent" "updated >= -1d" "jql" "Recently updated" >/dev/null

echo "Created test searches:"
list_saved_searches "names" | grep "^test-" | sed 's/^/  - /'

# Test 3: Cache statistics
echo ""
echo ""
echo "📈 Test 3: Cache Statistics"
echo "--------------------------"
cache_stats

# Test 4: Performance metrics
echo ""
echo ""
echo "⚡ Test 4: Performance Metrics"
echo "-----------------------------"
get_performance_metrics 3600 | jq -r '.[] | "Operation: \(.operation), Avg: \(.avg_duration_ms)ms, Count: \(.count), Hit Rate: \(.cache_hit_rate)%"'

# Test 5: LRU eviction
echo ""
echo ""
echo "🧹 Test 5: LRU Eviction Test"
echo "---------------------------"

# Create many cache entries
for i in {1..110}; do
    cache_key=$(generate_cache_key "test-query-$i" "jql" "25")
    echo "Data for query $i" | cache_put "$cache_key" - "test-query-$i" "jql" >/dev/null 2>&1
done

# Check cache size
cache_count=$(cache_list | jq length)
echo "Cache entries after adding 110 items: $cache_count (max: 100)"

# Cleanup test saved searches
echo ""
echo ""
echo "🧹 Cleaning up test data..."
delete_saved_search "test-high-priority" yes >/dev/null 2>&1
delete_saved_search "test-my-tasks" yes >/dev/null 2>&1
delete_saved_search "test-recent" yes >/dev/null 2>&1

echo "✅ Performance tests complete!"
echo ""
echo "💡 Tips:"
echo "  - Use 'cache_stats' to monitor cache performance"
echo "  - Use 'cache_warm' to pre-load common queries"
echo "  - Saved searches execute faster than typing queries"
echo "  - Background refresh keeps frequent queries fresh"