# API Limits and Performance Tuning Guide

This comprehensive guide covers API rate limits, performance optimization strategies, and tuning recommendations for Claude Code PM with Jira integration.

## Table of Contents

- [API Rate Limits Overview](#api-rate-limits-overview)
- [Jira API Limits](#jira-api-limits)
- [GitHub API Limits](#github-api-limits)
- [MCP Service Limits](#mcp-service-limits)
- [Performance Monitoring](#performance-monitoring)
- [Optimization Strategies](#optimization-strategies)
- [Caching Optimization](#caching-optimization)
- [Request Optimization](#request-optimization)
- [Batch Processing](#batch-processing)
- [Throttling and Backoff](#throttling-and-backoff)
- [Performance Benchmarks](#performance-benchmarks)
- [Tuning Recommendations](#tuning-recommendations)
- [Troubleshooting Performance Issues](#troubleshooting-performance-issues)

---

## API Rate Limits Overview

Understanding and respecting API limits is crucial for reliable operation:

### Rate Limit Headers

All API responses include rate limit information:

```http
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 950
X-RateLimit-Reset: 1640995200
Retry-After: 60
```

### Monitoring Rate Limits

```bash
# Check current rate limit status
/pm:api-status

# Output:
Service      Limit    Used    Remaining    Reset In
-------      -----    ----    ---------    --------
Jira         1000     50      950          45m
GitHub       5000     200     4800         58m
MCP Search   100      10      90           5m
```

---

## Jira API Limits

### Standard Limits

| Endpoint Category | Rate Limit | Window | Notes |
|------------------|------------|---------|--------|
| Search (JQL) | 50 req/min | Sliding | Per user |
| Issue Operations | 100 req/min | Sliding | Create/Update/Delete |
| Bulk Operations | 10 req/min | Fixed | Batch API only |
| Webhooks | 500 req/hour | Fixed | Incoming webhooks |
| Attachments | 50 req/hour | Fixed | File operations |

### Jira Cloud Specifics

```json
{
  "jira": {
    "rate_limits": {
      "global": {
        "requests_per_minute": 100,
        "concurrent_requests": 10
      },
      "per_endpoint": {
        "/rest/api/3/search": 50,
        "/rest/api/3/issue": 100,
        "/rest/api/3/issue/bulk": 10,
        "/rest/agile/1.0/*": 100
      }
    }
  }
}
```

### Handling Jira Rate Limits

```bash
# Rate limit handler implementation
handle_jira_rate_limit() {
    local response="$1"
    local retry_after=$(extract_header "$response" "Retry-After")
    
    if [[ -n "$retry_after" ]]; then
        echo "⏳ Rate limited. Waiting ${retry_after}s..."
        sleep "$retry_after"
        return 0
    fi
    
    # Exponential backoff for 429 errors
    local attempt=1
    while [[ $attempt -le 3 ]]; do
        sleep $((2 ** attempt))
        if retry_request; then
            return 0
        fi
        attempt=$((attempt + 1))
    done
    
    return 1
}
```

---

## GitHub API Limits

### REST API Limits

| Authentication | Requests/Hour | Search/Min | GraphQL Points/Hour |
|----------------|--------------|------------|-------------------|
| Unauthenticated | 60 | 10 | N/A |
| Personal Token | 5,000 | 30 | 5,000 |
| GitHub App | 5,000* | 30 | 5,000* |

*Can be increased based on installation

### GitHub Specific Limits

```bash
# Check GitHub rate limits
gh api rate_limit

# Response:
{
  "resources": {
    "core": {
      "limit": 5000,
      "remaining": 4999,
      "reset": 1640995200,
      "used": 1
    },
    "search": {
      "limit": 30,
      "remaining": 30,
      "reset": 1640991660
    }
  }
}
```

### Optimizing GitHub API Usage

```bash
# Use conditional requests
github_conditional_request() {
    local url="$1"
    local etag_file="/tmp/github-etag-$(echo "$url" | md5sum | cut -d' ' -f1)"
    
    # Use stored ETag
    if [[ -f "$etag_file" ]]; then
        local etag=$(cat "$etag_file")
        response=$(gh api "$url" -H "If-None-Match: $etag")
        
        if [[ $? -eq 0 ]]; then
            # Save new ETag
            echo "$response" | jq -r '.etag' > "$etag_file"
        fi
    else
        response=$(gh api "$url")
        echo "$response" | jq -r '.etag' > "$etag_file"
    fi
    
    echo "$response"
}
```

---

## MCP Service Limits

### MCP Search Limits

```json
{
  "mcp": {
    "search": {
      "requests_per_minute": 100,
      "max_results_per_query": 100,
      "max_query_length": 1000,
      "timeout_seconds": 30
    },
    "operations": {
      "requests_per_minute": 200,
      "bulk_size": 50,
      "concurrent_operations": 5
    }
  }
}
```

### MCP Optimization

```bash
# MCP request pooling
declare -A MCP_REQUEST_POOL

pool_mcp_request() {
    local request_type="$1"
    local request_data="$2"
    
    # Add to pool
    MCP_REQUEST_POOL["$request_type"]+="$request_data|"
    
    # Flush pool if size threshold reached
    if [[ $(echo "${MCP_REQUEST_POOL["$request_type"]}" | tr '|' '\n' | wc -l) -ge 10 ]]; then
        flush_mcp_pool "$request_type"
    fi
}

flush_mcp_pool() {
    local request_type="$1"
    local pooled_data="${MCP_REQUEST_POOL["$request_type"]}"
    
    # Execute batch request
    claude "mcp__atlassian__batch${request_type}" --data "$pooled_data"
    
    # Clear pool
    unset MCP_REQUEST_POOL["$request_type"]
}
```

---

## Performance Monitoring

### Metrics Collection

```bash
# Performance metrics tracking
track_performance_metrics() {
    local operation="$1"
    local start_time="$2"
    local end_time="$3"
    local cache_hit="${4:-false}"
    
    local duration=$((end_time - start_time))
    local metrics_file="$HOME/.cache/ccpm-jira/metrics.csv"
    
    # Log metrics
    echo "$(date +%s),$operation,$duration,$cache_hit" >> "$metrics_file"
    
    # Real-time alerting for slow operations
    if [[ $duration -gt 5000 ]]; then
        echo "⚠️ Slow operation detected: $operation took ${duration}ms"
    fi
}
```

### Performance Dashboard

```bash
# Generate performance report
/pm:performance-report --last 24h

# Output:
Performance Report (Last 24 Hours)
==================================

API Calls Summary:
- Total: 1,234
- Cached: 456 (37%)
- Failed: 12 (0.97%)

Average Response Times:
- Jira Search: 245ms
- GitHub API: 123ms
- MCP Search: 567ms
- File Operations: 12ms

Slowest Operations:
1. epic-sync user-auth: 3,456ms
2. search "complex query": 2,123ms
3. bulk-update 50 issues: 1,890ms

Cache Performance:
- Hit Rate: 37%
- Size: 23MB / 100MB
- Evictions: 123
```

---

## Optimization Strategies

### 1. Request Batching

```bash
# Batch multiple operations
batch_jira_updates() {
    local updates=()
    local batch_size=50
    
    # Collect updates
    while read -r issue_update; do
        updates+=("$issue_update")
        
        # Process batch when full
        if [[ ${#updates[@]} -eq $batch_size ]]; then
            process_jira_batch "${updates[@]}"
            updates=()
        fi
    done
    
    # Process remaining
    if [[ ${#updates[@]} -gt 0 ]]; then
        process_jira_batch "${updates[@]}"
    fi
}

process_jira_batch() {
    local batch_data=$(printf '%s\n' "$@" | jq -s '.')
    
    claude mcp__atlassian__bulkEditJiraIssues \
        --cloudId "$CLOUD_ID" \
        --updates "$batch_data"
}
```

### 2. Parallel Processing

```bash
# Parallel execution with rate limiting
parallel_process() {
    local max_parallel=4
    local rate_limit=10  # requests per second
    local job_count=0
    
    while read -r task; do
        # Rate limiting
        if [[ $job_count -ge $rate_limit ]]; then
            sleep 1
            job_count=0
        fi
        
        # Process in background
        process_task "$task" &
        job_count=$((job_count + 1))
        
        # Limit parallel jobs
        while [[ $(jobs -r | wc -l) -ge $max_parallel ]]; do
            sleep 0.1
        done
    done
    
    # Wait for completion
    wait
}
```

### 3. Smart Caching

```bash
# Intelligent cache warming
warm_cache() {
    echo "🔥 Warming cache..."
    
    # Predictive caching based on usage patterns
    local common_queries=(
        "assignee = currentUser() AND status = 'In Progress'"
        "project = PROJ AND updated >= -7d"
        "labels = high-priority"
    )
    
    for query in "${common_queries[@]}"; do
        search_with_cache "$query" &
    done
    
    # Cache user metadata
    cache_user_info &
    
    # Cache project configuration
    cache_project_metadata &
    
    wait
    echo "✅ Cache warmed successfully"
}
```

---

## Caching Optimization

### Cache Configuration

```json
{
  "cache": {
    "strategies": {
      "memory": {
        "enabled": true,
        "max_size_mb": 50,
        "ttl_seconds": 300
      },
      "disk": {
        "enabled": true,
        "max_size_mb": 100,
        "ttl_seconds": 3600,
        "compression": true
      },
      "distributed": {
        "enabled": false,
        "redis_url": "redis://localhost:6379",
        "ttl_seconds": 7200
      }
    }
  }
}
```

### Cache Key Strategy

```bash
# Normalized cache key generation
generate_cache_key() {
    local operation="$1"
    local params="$2"
    
    # Normalize parameters
    local normalized=$(echo "$params" | \
        tr '[:upper:]' '[:lower:]' | \
        sed 's/[[:space:]]\+/ /g' | \
        sort)
    
    # Generate deterministic key
    echo "${operation}:$(echo "$normalized" | sha256sum | cut -c1-16)"
}

# Cache invalidation patterns
invalidate_related_cache() {
    local entity_type="$1"
    local entity_id="$2"
    
    # Invalidate all related cache entries
    find "$CACHE_DIR" -name "*${entity_type}*${entity_id}*" -delete
    
    # Also invalidate parent caches
    case "$entity_type" in
        "issue")
            invalidate_cache "epic:*"
            invalidate_cache "search:*"
            ;;
        "epic")
            invalidate_cache "project:*"
            ;;
    esac
}
```

---

## Request Optimization

### Query Optimization

```bash
# JQL query optimization
optimize_jql_query() {
    local query="$1"
    
    # Add performance hints
    query="$query ORDER BY created DESC"
    
    # Limit fields for better performance
    local fields="summary,status,assignee,priority,updated"
    
    # Use indexed fields
    query=$(echo "$query" | sed 's/text ~/summary ~/')
    
    echo "$query"
}

# Paginated requests
paginated_search() {
    local query="$1"
    local page_size=50
    local start_at=0
    local total_results=0
    
    while true; do
        local response=$(search_jira \
            --jql "$query" \
            --startAt "$start_at" \
            --maxResults "$page_size")
        
        local count=$(echo "$response" | jq '.issues | length')
        total_results=$((total_results + count))
        
        # Process results
        echo "$response" | process_results
        
        # Check if more pages
        if [[ $count -lt $page_size ]]; then
            break
        fi
        
        start_at=$((start_at + page_size))
        
        # Rate limit pause
        sleep 0.1
    done
    
    echo "✅ Processed $total_results results"
}
```

### Response Size Optimization

```bash
# Minimize response payload
minimal_api_request() {
    local endpoint="$1"
    local required_fields="$2"
    
    # Only request needed fields
    claude mcp__atlassian__getJiraIssue \
        --issueIdOrKey "$issue_key" \
        --fields "$required_fields" \
        --expand ""  # Don't expand nested objects
}

# Compressed responses
enable_response_compression() {
    export CCPM_HTTP_COMPRESSION=gzip
    export CCPM_ACCEPT_ENCODING="gzip, deflate"
}
```

---

## Batch Processing

### Batch Configuration

```json
{
  "batch": {
    "sizes": {
      "create": 50,
      "update": 100,
      "delete": 25,
      "search": 1000
    },
    "timeout": 300,
    "retry_failed": true,
    "parallel_batches": 2
  }
}
```

### Batch Implementation

```bash
# Intelligent batching with error handling
process_batch_with_retry() {
    local batch_type="$1"
    local items=("${@:2}")
    local batch_size="${BATCH_SIZES[$batch_type]:-50}"
    local successful=0
    local failed=0
    
    # Split into batches
    for ((i=0; i<${#items[@]}; i+=batch_size)); do
        local batch=("${items[@]:i:batch_size}")
        
        if process_single_batch "$batch_type" "${batch[@]}"; then
            successful=$((successful + ${#batch[@]}))
        else
            # Retry failed items individually
            for item in "${batch[@]}"; do
                if retry_single_item "$batch_type" "$item"; then
                    successful=$((successful + 1))
                else
                    failed=$((failed + 1))
                    log_failed_item "$item"
                fi
            done
        fi
        
        # Progress update
        local progress=$((successful * 100 / ${#items[@]}))
        echo -ne "\rProgress: $progress% ($successful/${#items[@]})\r"
    done
    
    echo -e "\n✅ Batch complete: $successful succeeded, $failed failed"
}
```

---

## Throttling and Backoff

### Adaptive Throttling

```bash
# Dynamic rate adjustment
declare -g CURRENT_RATE=10  # requests per second
declare -g MIN_RATE=1
declare -g MAX_RATE=50

adaptive_throttle() {
    local success="$1"
    
    if [[ "$success" == "true" ]]; then
        # Gradually increase rate
        CURRENT_RATE=$((CURRENT_RATE * 110 / 100))  # 10% increase
        [[ $CURRENT_RATE -gt $MAX_RATE ]] && CURRENT_RATE=$MAX_RATE
    else
        # Quickly decrease rate
        CURRENT_RATE=$((CURRENT_RATE * 50 / 100))  # 50% decrease
        [[ $CURRENT_RATE -lt $MIN_RATE ]] && CURRENT_RATE=$MIN_RATE
    fi
    
    # Calculate delay
    local delay=$(bc <<< "scale=3; 1.0 / $CURRENT_RATE")
    sleep "$delay"
}
```

### Exponential Backoff

```bash
# Exponential backoff with jitter
exponential_backoff() {
    local attempt="$1"
    local base_delay="${2:-1}"
    local max_delay="${3:-60}"
    
    # Calculate delay with exponential growth
    local delay=$((base_delay * (2 ** (attempt - 1))))
    
    # Cap at maximum
    [[ $delay -gt $max_delay ]] && delay=$max_delay
    
    # Add jitter to prevent thundering herd
    local jitter=$(( RANDOM % (delay / 2) ))
    delay=$((delay + jitter))
    
    echo "⏳ Backing off for ${delay}s (attempt $attempt)"
    sleep "$delay"
}
```

---

## Performance Benchmarks

### Baseline Performance Metrics

| Operation | Target | Acceptable | Poor |
|-----------|---------|------------|------|
| Simple Search | <500ms | <2s | >2s |
| Issue Create | <1s | <3s | >3s |
| Bulk Update (50) | <5s | <10s | >10s |
| Epic Sync | <10s | <30s | >30s |
| Cache Hit | <10ms | <50ms | >50ms |

### Benchmark Tests

```bash
# Performance benchmark suite
run_performance_benchmarks() {
    echo "Running Performance Benchmarks..."
    echo "================================"
    
    # Test 1: Simple search
    benchmark "Simple Search" \
        "search_jql 'project = PROJ' 10"
    
    # Test 2: Complex search
    benchmark "Complex Search" \
        "search_natural_language 'high priority bugs in current sprint' 25"
    
    # Test 3: Bulk operations
    benchmark "Bulk Update (50 issues)" \
        "bulk_update_issues 50"
    
    # Test 4: Cache performance
    benchmark "Cache Operations" \
        "cache_stress_test 1000"
    
    # Generate report
    generate_benchmark_report
}

benchmark() {
    local test_name="$1"
    local command="$2"
    
    echo -n "Testing $test_name... "
    
    local start=$(date +%s%N)
    eval "$command" >/dev/null 2>&1
    local end=$(date +%s%N)
    
    local duration=$(( (end - start) / 1000000 ))
    
    # Evaluate performance
    local status="✅ GOOD"
    [[ $duration -gt 2000 ]] && status="⚠️ ACCEPTABLE"
    [[ $duration -gt 5000 ]] && status="❌ POOR"
    
    echo "$status (${duration}ms)"
    
    # Log for analysis
    echo "$test_name,$duration,$status" >> benchmark-results.csv
}
```

---

## Tuning Recommendations

### Environment-Specific Tuning

#### Development Environment
```bash
# Optimized for fast iteration
export CCPM_CACHE_TTL=60
export CCPM_MAX_PARALLEL=2
export CCPM_REQUEST_TIMEOUT=10
export CCPM_DEBUG=true
```

#### Production Environment
```bash
# Optimized for reliability
export CCPM_CACHE_TTL=300
export CCPM_MAX_PARALLEL=4
export CCPM_REQUEST_TIMEOUT=30
export CCPM_RETRY_ATTEMPTS=3
export CCPM_ENABLE_MONITORING=true
```

### Workload-Specific Tuning

#### High-Volume Search
```json
{
  "performance": {
    "search": {
      "cache_ttl": 600,
      "max_results": 100,
      "enable_compression": true,
      "use_pagination": true,
      "parallel_searches": 3
    }
  }
}
```

#### Bulk Operations
```json
{
  "performance": {
    "bulk": {
      "batch_size": 100,
      "parallel_batches": 2,
      "retry_failed": true,
      "progress_updates": true
    }
  }
}
```

### Network Optimization

```bash
# Network tuning
optimize_network() {
    # Enable connection pooling
    export CCPM_CONNECTION_POOL_SIZE=10
    
    # Enable HTTP/2
    export CCPM_HTTP_VERSION=2
    
    # Compression
    export CCPM_ENABLE_COMPRESSION=true
    
    # DNS caching
    export CCPM_DNS_CACHE_TTL=3600
}
```

---

## Troubleshooting Performance Issues

### Performance Diagnostic Tools

```bash
# Comprehensive performance diagnosis
diagnose_performance() {
    echo "🔍 Running Performance Diagnostics..."
    
    # Check API rate limits
    check_rate_limits
    
    # Analyze cache performance
    analyze_cache_performance
    
    # Network latency test
    test_network_latency
    
    # Memory usage
    check_memory_usage
    
    # Identify bottlenecks
    identify_bottlenecks
    
    # Generate recommendations
    generate_tuning_recommendations
}

# Bottleneck identification
identify_bottlenecks() {
    # Analyze slow operations
    grep "duration" ~/.cache/ccpm-jira/performance.log | \
        sort -t, -k3 -n -r | \
        head -20 | \
        while IFS=, read -r timestamp operation duration; do
            echo "$operation: ${duration}ms"
        done
}
```

### Common Performance Issues

#### Issue: Slow Search Performance
```bash
# Solution 1: Optimize query
optimize_search_query() {
    # Use specific fields
    local optimized_query="project = PROJ AND status = Open"
    
    # Add ordering for better index usage
    optimized_query="$optimized_query ORDER BY created DESC"
    
    # Limit fields returned
    search_with_fields "$optimized_query" "key,summary,status"
}

# Solution 2: Increase cache usage
boost_cache_performance() {
    # Increase cache size
    export CCPM_CACHE_SIZE_MB=200
    
    # Extend TTL for stable data
    export CCPM_PROJECT_CACHE_TTL=86400
    
    # Pre-warm cache
    warm_cache_async
}
```

#### Issue: API Rate Limiting
```bash
# Solution: Implement request queue
implement_request_queue() {
    # Queue requests when approaching limit
    local limit_threshold=0.8
    
    if [[ $(get_rate_limit_usage) > $limit_threshold ]]; then
        queue_request "$@"
    else
        execute_request "$@"
    fi
}
```

#### Issue: Memory Usage
```bash
# Solution: Optimize memory usage
optimize_memory() {
    # Limit cache size
    export CCPM_MAX_MEMORY_MB=256
    
    # Enable streaming for large responses
    export CCPM_STREAM_RESPONSES=true
    
    # Garbage collection tuning
    export CCPM_GC_INTERVAL=300
}
```

---

## Best Practices Summary

1. **Respect Rate Limits**
   - Monitor usage continuously
   - Implement proper backoff
   - Use caching aggressively

2. **Optimize Requests**
   - Batch operations
   - Request only needed fields
   - Use pagination for large results

3. **Cache Intelligently**
   - Cache stable data longer
   - Invalidate cache on updates
   - Monitor cache performance

4. **Monitor Performance**
   - Track all API calls
   - Alert on degradation
   - Regular benchmark tests

5. **Plan for Scale**
   - Design for 10x growth
   - Implement circuit breakers
   - Use async operations

Remember: Performance tuning is an iterative process. Measure, optimize, and measure again.