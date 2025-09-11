# Technical Architecture Guide

This comprehensive guide explains the technical architecture of Claude Code PM with Jira integration, focusing on the Model Context Protocol (MCP) integration, system design decisions, and implementation details.

## Table of Contents

- [System Overview](#system-overview)
- [Architecture Principles](#architecture-principles)
- [Core Components](#core-components)
- [MCP Integration Architecture](#mcp-integration-architecture)
- [Data Flow Architecture](#data-flow-architecture)
- [Command Processing Pipeline](#command-processing-pipeline)
- [Caching Strategy](#caching-strategy)
- [Sync Engine Design](#sync-engine-design)
- [Search Architecture](#search-architecture)
- [Security Model](#security-model)
- [Extension Points](#extension-points)
- [Performance Considerations](#performance-considerations)
- [Deployment Architecture](#deployment-architecture)

---

## System Overview

Claude Code PM is a sophisticated project management system that bridges local development workflows with cloud-based issue tracking systems. The architecture emphasizes:

- **Bidirectional Synchronization**: Seamless data flow between local files, GitHub, and Jira
- **Intelligent Routing**: Smart decision-making for search queries and API calls
- **Performance Optimization**: Multi-layer caching and request batching
- **Extensibility**: Plugin architecture for additional integrations

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        User Interface                            │
│                    (Claude Code Commands)                        │
└─────────────────────────────┬───────────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────────┐
│                     Command Router                               │
│              (pm:* command processing)                           │
└─────────────┬───────────────────────────────┬───────────────────┘
              │                               │
┌─────────────▼──────────┐      ┌────────────▼──────────────────┐
│   Local File System    │      │      External Services         │
│  - Task files (.md)    │      │  - GitHub API                  │
│  - Cache (.json)       │      │  - Jira (via MCP)              │
│  - Configuration       │      │  - Search Services             │
└────────────────────────┘      └────────────────────────────────┘
```

---

## Architecture Principles

### 1. **Offline-First Design**
- All operations work locally first
- Network calls are asynchronous and non-blocking
- Graceful degradation when services unavailable

### 2. **Event-Driven Synchronization**
- Changes trigger sync events
- Conflict detection before resolution
- Audit trail for all modifications

### 3. **Layered Architecture**
```
┌──────────────────────┐
│   Presentation Layer │ - Command interface
├──────────────────────┤
│   Business Logic     │ - Workflow orchestration
├──────────────────────┤
│   Integration Layer  │ - API adapters
├──────────────────────┤
│   Data Access Layer  │ - File system, cache
└──────────────────────┘
```

### 4. **Separation of Concerns**
- Each script has single responsibility
- Shared functionality in libraries
- Clear interfaces between components

---

## Core Components

### 1. **Command Scripts** (`claude/scripts/pm/`)

Each command follows a standard pattern:

```bash
#!/bin/bash
# 1. Load configuration
source_config

# 2. Parse arguments
parse_args "$@"

# 3. Validate input
validate_input

# 4. Execute business logic
execute_command

# 5. Handle results
handle_output
```

### 2. **Library Modules** (`claude/lib/`)

#### Core Libraries:
- `jira-transitions.sh`: State machine for issue status
- `git-integration.sh`: Git operations and branch management
- `search-mcp.sh`: MCP search integration
- `query-router.sh`: Intelligent query routing
- `sync-conflict-handler.sh`: Conflict resolution logic

#### Library Architecture:
```
┌────────────────────────┐
│   Public Interface     │ - Exported functions
├────────────────────────┤
│   Private Functions    │ - Internal helpers
├────────────────────────┤
│   Constants/Config     │ - Library settings
└────────────────────────┘
```

### 3. **Data Storage**

```
.claude/
├── epics/              # Epic data
│   └── [epic-name]/
│       ├── epic.md     # Epic definition
│       ├── *.md        # Task files
│       ├── jira-cache/ # Sync cache
│       └── updates/    # Progress tracking
├── prds/               # Product requirements
└── settings.local.json # Configuration
```

---

## MCP Integration Architecture

The Model Context Protocol (MCP) integration is the cornerstone of Jira connectivity:

### MCP Tool Flow

```
User Command
     │
     ▼
Query Router ──────► Determines: NL or JQL?
     │
     ├─── Natural Language Path
     │         │
     │         ▼
     │    MCP Search Tool
     │    (mcp__atlassian__search)
     │         │
     │         ▼
     │    Rovo Search API
     │         │
     │         ▼
     │    Unified Results
     │
     └─── JQL Path
              │
              ▼
         Auth Check ──────► Cached?
              │                │
              │                No
              │                ▼
              │         MCP Auth Tool
              │    (mcp__atlassian__atlassianUserInfo)
              │
              ▼
         Get Cloud ID
    (mcp__atlassian__getAccessibleAtlassianResources)
              │
              ▼
         JQL Search
    (mcp__atlassian__searchJiraIssuesUsingJql)
              │
              ▼
         Jira Results
```

### MCP Tool Inventory

1. **Authentication & Setup**
   - `atlassianUserInfo`: Get current user information
   - `getAccessibleAtlassianResources`: Retrieve cloud IDs

2. **Search Operations**
   - `search`: Natural language search (Rovo)
   - `searchJiraIssuesUsingJql`: JQL-based search
   - `searchConfluenceUsingCql`: Confluence search

3. **Issue Operations**
   - `getJiraIssue`: Fetch issue details
   - `createJiraIssue`: Create new issues
   - `editJiraIssue`: Update issue fields
   - `transitionJiraIssue`: Change issue status
   - `addCommentToJiraIssue`: Add comments

4. **Metadata Operations**
   - `getTransitionsForJiraIssue`: Available transitions
   - `lookupJiraAccountId`: User lookup
   - `getVisibleJiraProjects`: Project access
   - `getJiraProjectIssueTypesMetadata`: Issue types

### MCP Request Optimization

```bash
# Batching pattern
prepare_batch_request() {
    local requests=()
    
    # Collect multiple operations
    requests+=("issue:PROJ-101")
    requests+=("issue:PROJ-102")
    requests+=("issue:PROJ-103")
    
    # Single MCP call with batch
    claude mcp__atlassian__batchOperation \
        --operations "${requests[@]}"
}

# Caching pattern
cached_mcp_call() {
    local cache_key="$1"
    local cache_file="$HOME/.cache/ccpm-jira/$cache_key"
    
    # Check cache first
    if [[ -f "$cache_file" ]] && cache_is_valid "$cache_file"; then
        cat "$cache_file"
        return 0
    fi
    
    # Make MCP call
    local result
    result=$(claude mcp__atlassian__"$2" "${@:3}")
    
    # Cache result
    echo "$result" > "$cache_file"
    echo "$result"
}
```

---

## Data Flow Architecture

### Issue Creation Flow

```
1. User: /pm:epic-decompose user-auth --with-jira
                    │
                    ▼
2. Parse Epic → Generate Tasks
                    │
                    ▼
3. Create Local Task Files
                    │
                    ▼
4. For Each Task:
   ├─► Create GitHub Issue
   │        │
   │        ▼
   │   Get Issue Number
   │        │
   └────────┴─► Create Jira Story
                     │
                     ▼
                Link GitHub ↔ Jira
                     │
                     ▼
                Update Local Cache
```

### Bidirectional Sync Flow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Local     │     │   GitHub    │     │    Jira     │
│   Files     │     │   Issues    │     │   Issues    │
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                    │
       ▼                   ▼                    ▼
   ┌───────────────────────────────────────────────┐
   │            Sync Conflict Detector             │
   └───────────────────────┬───────────────────────┘
                           │
                    ┌──────▼──────┐
                    │  Conflicts?  │
                    └──────┬──────┘
                           │
                ┌──────────┴──────────┐
                │                     │
                No                   Yes
                │                     │
                ▼                     ▼
          Auto-merge          Resolution Strategy
                │              ├─► Local wins
                │              ├─► Remote wins
                │              └─► Manual merge
                │                     │
                └──────────┬──────────┘
                           │
                           ▼
                    Apply Changes
                           │
                    ┌──────┴──────┐
                    │             │
                    ▼             ▼
               Update Local   Update Remote
```

---

## Command Processing Pipeline

### Pipeline Stages

```bash
# Stage 1: Input Validation
validate_command_input() {
    local cmd="$1"
    shift
    
    # Check command exists
    [[ -f "$SCRIPTS_DIR/$cmd.sh" ]] || error "Unknown command"
    
    # Validate arguments
    validate_args_for_command "$cmd" "$@"
}

# Stage 2: Context Loading
load_command_context() {
    # Load configuration
    load_config
    
    # Check authentication
    check_auth_status
    
    # Load epic/issue context
    load_working_context
}

# Stage 3: Pre-processing
preprocess_command() {
    # Check prerequisites
    check_dependencies
    
    # Prepare environment
    setup_temp_dirs
    
    # Lock resources
    acquire_locks
}

# Stage 4: Execution
execute_command_logic() {
    # Run main logic
    run_command "$@"
    
    # Handle errors
    trap cleanup_on_error ERR
}

# Stage 5: Post-processing
postprocess_command() {
    # Update caches
    update_caches
    
    # Trigger sync
    queue_sync_operations
    
    # Clean up
    release_locks
}
```

### Error Handling Strategy

```bash
# Layered error handling
handle_error() {
    local error_code="$1"
    local error_context="$2"
    
    case "$error_code" in
        AUTH_*)
            handle_auth_error "$error_context"
            ;;
        SYNC_*)
            handle_sync_error "$error_context"
            ;;
        NET_*)
            handle_network_error "$error_context"
            ;;
        *)
            handle_generic_error "$error_context"
            ;;
    esac
}

# Retry logic with exponential backoff
retry_with_backoff() {
    local max_attempts=3
    local attempt=1
    local delay=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if "$@"; then
            return 0
        fi
        
        echo "Attempt $attempt failed, retrying in ${delay}s..."
        sleep "$delay"
        
        attempt=$((attempt + 1))
        delay=$((delay * 2))
    done
    
    return 1
}
```

---

## Caching Strategy

### Multi-Layer Cache Architecture

```
┌─────────────────────────────────┐
│      Memory Cache (Runtime)      │ - Process-level
├─────────────────────────────────┤
│      File Cache (Persistent)     │ - ~/.cache/ccpm-jira/
├─────────────────────────────────┤
│    Remote Cache (Optional)       │ - Redis/Memcached
└─────────────────────────────────┘
```

### Cache Implementation

```bash
# Cache key generation
generate_cache_key() {
    local namespace="$1"
    local identifier="$2"
    local params="$3"
    
    echo "${namespace}:${identifier}:$(echo "$params" | sha256sum | cut -d' ' -f1)"
}

# Cache with TTL
cache_with_ttl() {
    local key="$1"
    local value="$2"
    local ttl="${3:-300}"  # 5 minutes default
    
    local cache_file="$CACHE_DIR/$key"
    local meta_file="$cache_file.meta"
    
    # Write data
    echo "$value" > "$cache_file"
    
    # Write metadata
    cat > "$meta_file" <<EOF
{
    "created": $(date +%s),
    "ttl": $ttl,
    "hits": 0
}
EOF
}

# Cache invalidation
invalidate_cache() {
    local pattern="$1"
    
    find "$CACHE_DIR" -name "*${pattern}*" -delete
}
```

### Cache Performance Metrics

```bash
# Track cache performance
track_cache_metrics() {
    local operation="$1"  # hit, miss, evict
    local key="$2"
    
    local metrics_file="$CACHE_DIR/.metrics"
    
    echo "$(date +%s),$operation,$key" >> "$metrics_file"
}

# Generate cache report
cache_report() {
    local metrics_file="$CACHE_DIR/.metrics"
    
    echo "Cache Performance Report"
    echo "========================"
    
    local total=$(wc -l < "$metrics_file")
    local hits=$(grep ",hit," "$metrics_file" | wc -l)
    local misses=$(grep ",miss," "$metrics_file" | wc -l)
    
    echo "Total operations: $total"
    echo "Cache hits: $hits ($(( hits * 100 / total ))%)"
    echo "Cache misses: $misses ($(( misses * 100 / total ))%)"
}
```

---

## Sync Engine Design

### Sync State Machine

```
     ┌─────────┐
     │  IDLE   │
     └────┬────┘
          │ Trigger
          ▼
     ┌─────────┐
     │PREPARING│ ← Gathering changes
     └────┬────┘
          │
          ▼
     ┌─────────┐
     │DETECTING│ ← Conflict detection
     └────┬────┘
          │
     ┌────┴────┐
     │Conflicts│
     └────┬────┘
      No  │  Yes
      │   └───────┐
      ▼           ▼
 ┌────────┐  ┌─────────┐
 │APPLYING│  │RESOLVING│
 └────┬───┘  └────┬────┘
      │           │
      ▼           ▼
 ┌────────┐  ┌─────────┐
 │COMPLETE│  │ FAILED  │
 └────────┘  └─────────┘
```

### Conflict Resolution Engine

```bash
# Conflict detection algorithm
detect_conflicts() {
    local local_state="$1"
    local remote_state="$2"
    local base_state="$3"
    
    local conflicts=()
    
    # Three-way comparison
    for field in $(get_tracked_fields); do
        local local_val=$(get_field "$local_state" "$field")
        local remote_val=$(get_field "$remote_state" "$field")
        local base_val=$(get_field "$base_state" "$field")
        
        if [[ "$local_val" != "$base_val" ]] && \
           [[ "$remote_val" != "$base_val" ]] && \
           [[ "$local_val" != "$remote_val" ]]; then
            conflicts+=("$field")
        fi
    done
    
    echo "${conflicts[@]}"
}

# Resolution strategies
resolve_conflict() {
    local field="$1"
    local strategy="$2"
    
    case "$strategy" in
        "local-wins")
            use_local_value "$field"
            ;;
        "remote-wins")
            use_remote_value "$field"
            ;;
        "merge")
            merge_values "$field"
            ;;
        "manual")
            prompt_user_resolution "$field"
            ;;
    esac
}
```

### Sync Optimization

```bash
# Batch sync operations
batch_sync() {
    local operations=()
    local batch_size=10
    
    # Collect pending syncs
    while read -r operation; do
        operations+=("$operation")
        
        if [[ ${#operations[@]} -ge $batch_size ]]; then
            execute_sync_batch "${operations[@]}"
            operations=()
        fi
    done < <(get_pending_syncs)
    
    # Process remaining
    if [[ ${#operations[@]} -gt 0 ]]; then
        execute_sync_batch "${operations[@]}"
    fi
}

# Delta sync for efficiency
delta_sync() {
    local last_sync="$1"
    local current_time=$(date +%s)
    
    # Only sync changed items
    find_changed_since "$last_sync" | while read -r item; do
        sync_item "$item"
    done
    
    # Update sync timestamp
    echo "$current_time" > "$SYNC_STATE_FILE"
}
```

---

## Search Architecture

### Query Processing Pipeline

```
User Query
    │
    ▼
Query Analysis ─────► Extract: keywords, operators, intent
    │
    ▼
Router Decision ────► NL / JQL / Hybrid
    │
    ├─── Natural Language
    │         │
    │         ▼
    │    Tokenization
    │         │
    │         ▼
    │    Semantic Search
    │         │
    │         ▼
    │    Result Ranking
    │
    └─── JQL
              │
              ▼
         Parse & Validate
              │
              ▼
         Field Mapping
              │
              ▼
         Execute Query
              │
              ▼
         Format Results
```

### Search Optimization

```bash
# Query optimization
optimize_query() {
    local query="$1"
    
    # Remove stop words
    query=$(remove_stop_words "$query")
    
    # Expand abbreviations
    query=$(expand_abbreviations "$query")
    
    # Add field boosts
    query=$(add_field_boosts "$query")
    
    echo "$query"
}

# Result ranking algorithm
rank_results() {
    local results="$1"
    local query="$2"
    
    # Score each result
    while read -r result; do
        local score=0
        
        # Title match weight: 10
        [[ $(get_field "$result" "title") =~ $query ]] && score=$((score + 10))
        
        # Description match weight: 5
        [[ $(get_field "$result" "description") =~ $query ]] && score=$((score + 5))
        
        # Recency boost
        local age=$(get_age "$result")
        score=$((score + (100 - age) / 10))
        
        echo "$score:$result"
    done < <(echo "$results") | sort -rn | cut -d: -f2-
}
```

### Search Caching Strategy

```bash
# Intelligent cache key generation
generate_search_cache_key() {
    local query="$1"
    local search_type="$2"
    local user_context="$3"
    
    # Normalize query
    local normalized=$(normalize_query "$query")
    
    # Include context for personalized results
    local context_hash=$(echo "$user_context" | sha256sum | cut -c1-8)
    
    echo "search:${search_type}:${context_hash}:$(echo "$normalized" | sha256sum | cut -c1-16)"
}

# Predictive cache warming
warm_search_cache() {
    # Common queries
    local common_queries=(
        "my open issues"
        "high priority bugs"
        "current sprint"
    )
    
    for query in "${common_queries[@]}"; do
        search_with_cache "$query" "auto" "25" &
    done
    
    wait
}
```

---

## Security Model

### Authentication Flow

```
┌──────────────┐      ┌──────────────┐      ┌──────────────┐
│    User      │      │  Claude CLI  │      │  Atlassian   │
└──────┬───────┘      └──────┬───────┘      └──────┬───────┘
       │                     │                      │
       │  claude login       │                      │
       ├────────────────────►│                      │
       │                     │  OAuth flow          │
       │                     ├─────────────────────►│
       │                     │                      │
       │                     │  Authorization code  │
       │                     │◄─────────────────────┤
       │                     │                      │
       │                     │  Exchange for token  │
       │                     ├─────────────────────►│
       │                     │                      │
       │                     │  Access token        │
       │                     │◄─────────────────────┤
       │                     │                      │
       │  Success            │                      │
       │◄────────────────────┤                      │
```

### Token Management

```bash
# Secure token storage
store_token() {
    local token="$1"
    local token_file="$HOME/.config/ccpm-jira/tokens"
    
    # Encrypt token
    local encrypted=$(echo "$token" | openssl enc -aes-256-cbc -salt -pass pass:"$USER")
    
    # Store with restricted permissions
    mkdir -p "$(dirname "$token_file")"
    echo "$encrypted" > "$token_file"
    chmod 600 "$token_file"
}

# Token refresh logic
refresh_token_if_needed() {
    local token_file="$HOME/.config/ccpm-jira/tokens"
    local token_age=$(($(date +%s) - $(stat -c %Y "$token_file")))
    
    # Refresh if older than 1 hour
    if [[ $token_age -gt 3600 ]]; then
        refresh_auth_token
    fi
}
```

### Permission Model

```bash
# Role-based access control
check_permissions() {
    local action="$1"
    local resource="$2"
    local user_role=$(get_user_role)
    
    case "$action" in
        "create")
            [[ "$user_role" =~ ^(admin|developer)$ ]]
            ;;
        "transition")
            [[ "$user_role" =~ ^(admin|developer|qa)$ ]]
            ;;
        "delete")
            [[ "$user_role" == "admin" ]]
            ;;
        *)
            return 0  # Read allowed for all
            ;;
    esac
}
```

---

## Extension Points

### Plugin Architecture

```bash
# Plugin discovery
discover_plugins() {
    local plugin_dir="$HOME/.config/ccpm-jira/plugins"
    
    find "$plugin_dir" -name "*.plugin" -type f | while read -r plugin; do
        source "$plugin"
        register_plugin "$(basename "$plugin" .plugin)"
    done
}

# Plugin hooks
declare -A PLUGIN_HOOKS=(
    ["pre_command"]=""
    ["post_command"]=""
    ["pre_sync"]=""
    ["post_sync"]=""
    ["search_filter"]=""
)

# Register hook
register_hook() {
    local hook_name="$1"
    local plugin_function="$2"
    
    PLUGIN_HOOKS["$hook_name"]+=" $plugin_function"
}

# Execute hooks
execute_hooks() {
    local hook_name="$1"
    shift
    
    for hook_function in ${PLUGIN_HOOKS["$hook_name"]}; do
        "$hook_function" "$@"
    done
}
```

### Custom Integration Example

```bash
# Example: Slack notification plugin
slack_plugin_init() {
    register_hook "post_sync" "slack_notify_sync"
    register_hook "post_command" "slack_notify_completion"
}

slack_notify_sync() {
    local sync_result="$1"
    
    if [[ "$SLACK_WEBHOOK_URL" ]]; then
        curl -X POST "$SLACK_WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "{\"text\": \"Sync completed: $sync_result\"}"
    fi
}
```

---

## Performance Considerations

### Optimization Strategies

1. **Request Batching**
   - Combine multiple API calls
   - Use bulk operations where available
   - Queue and process asynchronously

2. **Parallel Processing**
   ```bash
   # Parallel task processing
   process_tasks_parallel() {
       local max_jobs=4
       local job_count=0
       
       while read -r task; do
           process_task "$task" &
           
           job_count=$((job_count + 1))
           if [[ $job_count -ge $max_jobs ]]; then
               wait -n  # Wait for any job to finish
               job_count=$((job_count - 1))
           fi
       done
       
       wait  # Wait for remaining jobs
   }
   ```

3. **Resource Pooling**
   ```bash
   # Connection pool for API calls
   declare -A CONNECTION_POOL
   
   get_connection() {
       local service="$1"
       
       if [[ -z "${CONNECTION_POOL[$service]}" ]]; then
           CONNECTION_POOL[$service]=$(create_connection "$service")
       fi
       
       echo "${CONNECTION_POOL[$service]}"
   }
   ```

### Performance Monitoring

```bash
# Performance tracking
track_performance() {
    local operation="$1"
    local start_time="$2"
    local end_time="$3"
    
    local duration=$((end_time - start_time))
    local perf_log="$HOME/.cache/ccpm-jira/performance.log"
    
    echo "$(date +%s),$operation,$duration" >> "$perf_log"
}

# Performance report
generate_performance_report() {
    local perf_log="$HOME/.cache/ccpm-jira/performance.log"
    
    echo "Performance Report"
    echo "=================="
    
    # Average duration by operation
    awk -F, '{
        sum[$2] += $3
        count[$2]++
    }
    END {
        for (op in sum) {
            printf "%-20s: %6.2f ms avg\n", op, sum[op]/count[op]
        }
    }' "$perf_log" | sort
}
```

---

## Deployment Architecture

### Local Development Setup

```bash
# Development environment setup
setup_dev_environment() {
    # Install dependencies
    check_and_install_dependencies
    
    # Configure git hooks
    install_git_hooks
    
    # Set up test data
    create_test_fixtures
    
    # Initialize local services
    start_local_services
}
```

### Production Deployment

```yaml
# Docker deployment example
version: '3.8'

services:
  ccpm-jira:
    image: ccpm-jira:latest
    environment:
      - JIRA_API_TOKEN=${JIRA_API_TOKEN}
      - GITHUB_TOKEN=${GITHUB_TOKEN}
    volumes:
      - ~/.cache/ccpm-jira:/cache
      - ~/.config/ccpm-jira:/config
    networks:
      - ccpm-network
      
  redis:
    image: redis:alpine
    networks:
      - ccpm-network
    volumes:
      - redis-data:/data
```

### Scaling Considerations

1. **Horizontal Scaling**
   - Stateless command processing
   - Shared cache layer
   - Load balancing for API calls

2. **Vertical Scaling**
   - Increase cache sizes
   - Parallel processing limits
   - Connection pool sizes

3. **Distributed Setup**
   ```bash
   # Distributed cache configuration
   configure_distributed_cache() {
       export CCPM_CACHE_TYPE="redis"
       export CCPM_CACHE_REDIS_URL="redis://cache-cluster:6379"
       export CCPM_CACHE_REDIS_TTL="3600"
   }
   ```

---

## Conclusion

Claude Code PM's architecture emphasizes:
- **Modularity**: Clear separation of concerns
- **Performance**: Multi-layer caching and optimization
- **Reliability**: Robust error handling and recovery
- **Extensibility**: Plugin system for customization
- **Security**: Secure token management and access control

The system is designed to scale from individual developers to large teams while maintaining simplicity and performance.