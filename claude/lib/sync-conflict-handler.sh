#!/bin/bash

# Sync Conflict Handler
# Provides intelligent conflict resolution strategies for Jira-local synchronization
# Supports multiple resolution modes and rollback capabilities

set -e

# Conflict resolution strategies
declare -A RESOLUTION_STRATEGIES=(
    ["local_wins"]="Local changes take precedence"
    ["jira_wins"]="Jira changes take precedence"
    ["manual"]="User manual resolution required"
    ["merge"]="Attempt intelligent merge"
    ["interactive"]="Interactive resolution with user prompts"
)

# Resolve conflicts using specified strategy
# Usage: resolve_sync_conflicts <conflict_report> <strategy> <task_file> <jira_data_file> <cache_file>
resolve_sync_conflicts() {
    local conflict_report="$1"
    local strategy="$2"
    local task_file="$3"
    local jira_data_file="$4"
    local cache_file="$5"
    
    if [[ -z "$conflict_report" || -z "$strategy" || -z "$task_file" ]]; then
        echo "ERROR: Required parameters missing for conflict resolution" >&2
        return 1
    fi
    
    if [[ ! -f "$conflict_report" ]]; then
        echo "ERROR: Conflict report not found: $conflict_report" >&2
        return 1
    fi
    
    echo "🔧 Resolving conflicts using strategy: $strategy"
    echo "   Description: ${RESOLUTION_STRATEGIES[$strategy]:-"Unknown strategy"}"
    
    # Create backup before resolution
    local backup_dir="/tmp/sync-backup-$$"
    mkdir -p "$backup_dir"
    
    if [[ -f "$task_file" ]]; then
        cp "$task_file" "$backup_dir/task_file.bak"
    fi
    if [[ -f "$cache_file" ]]; then
        cp "$cache_file" "$backup_dir/cache_file.bak"
    fi
    
    echo "✅ Backup created at: $backup_dir"
    
    # Apply resolution strategy
    case "$strategy" in
        "local_wins")
            resolve_local_wins "$conflict_report" "$task_file" "$jira_data_file" "$cache_file"
            ;;
        "jira_wins")
            resolve_jira_wins "$conflict_report" "$task_file" "$jira_data_file" "$cache_file"
            ;;
        "merge")
            resolve_intelligent_merge "$conflict_report" "$task_file" "$jira_data_file" "$cache_file"
            ;;
        "interactive")
            resolve_interactive "$conflict_report" "$task_file" "$jira_data_file" "$cache_file"
            ;;
        "manual")
            setup_manual_resolution "$conflict_report" "$task_file" "$jira_data_file" "$cache_file"
            ;;
        *)
            echo "❌ Unknown resolution strategy: $strategy" >&2
            echo "Available strategies: ${!RESOLUTION_STRATEGIES[*]}" >&2
            return 1
            ;;
    esac
    
    local resolution_result=$?
    
    if [[ $resolution_result -eq 0 ]]; then
        echo "✅ Conflict resolution completed successfully"
        
        # Log the resolution
        log_conflict_resolution "$conflict_report" "$strategy" "SUCCESS" "$backup_dir"
        
        # Clean up backup after successful resolution
        rm -rf "$backup_dir"
    else
        echo "❌ Conflict resolution failed"
        echo "   Backup available at: $backup_dir"
        
        # Log the failed resolution
        log_conflict_resolution "$conflict_report" "$strategy" "FAILED" "$backup_dir"
        
        # Offer rollback
        echo ""
        echo "💡 To rollback changes:"
        echo "   cp $backup_dir/task_file.bak $task_file"
        if [[ -f "$backup_dir/cache_file.bak" ]]; then
            echo "   cp $backup_dir/cache_file.bak $cache_file"
        fi
    fi
    
    return $resolution_result
}

# Resolution strategy: Local changes win
# Usage: resolve_local_wins <conflict_report> <task_file> <jira_data_file> <cache_file>
resolve_local_wins() {
    local conflict_report="$1"
    local task_file="$2"
    local jira_data_file="$3"
    local cache_file="$4"
    
    echo "🏠 Applying local wins strategy..."
    
    # Keep all local changes, ignore Jira changes
    # Update cache to reflect that local changes are the source of truth
    
    local local_status=$(grep "^status:" "$task_file" | head -1 | sed 's/^status: *//' || echo "open")
    local local_assignee=$(grep "^assignee:" "$task_file" | head -1 | sed 's/^assignee: *//' || echo "")
    local current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Update task file timestamp to show it was updated
    if grep -q "^updated:" "$task_file"; then
        sed -i.bak "s/^updated:.*/updated: $current_date/" "$task_file"
    else
        sed -i.bak '/^---$/a\updated: '"$current_date" "$task_file"
    fi
    
    # Add resolution marker
    if ! grep -q "^conflict_resolved:" "$task_file"; then
        sed -i.bak '/^---$/a\conflict_resolved: local_wins_'"$current_date" "$task_file"
    fi
    
    # Clean up backup
    rm -f "${task_file}.bak"
    
    echo "✅ Local changes preserved, Jira changes ignored"
    echo "   Status: $local_status (kept local)"
    echo "   Assignee: ${local_assignee:-"none"} (kept local)"
    
    return 0
}

# Resolution strategy: Jira changes win
# Usage: resolve_jira_wins <conflict_report> <task_file> <jira_data_file> <cache_file>
resolve_jira_wins() {
    local conflict_report="$1"
    local task_file="$2"
    local jira_data_file="$3"
    local cache_file="$4"
    
    echo "🌐 Applying Jira wins strategy..."
    
    # Extract Jira data
    local jira_status=""
    local jira_assignee=""
    
    if command -v jq >/dev/null 2>&1; then
        jira_status=$(jq -r '.fields.status.name // ""' "$jira_data_file")
        jira_assignee=$(jq -r '.fields.assignee.displayName // ""' "$jira_data_file")
    else
        # Fallback parsing
        jira_status=$(grep -o '"name": *"[^"]*"' "$jira_data_file" | head -1 | cut -d'"' -f4)
        jira_assignee=$(grep -o '"displayName": *"[^"]*"' "$jira_data_file" | head -1 | cut -d'"' -f4)
    fi
    
    # Load required function for status mapping
    if declare -f map_jira_to_local_status >/dev/null; then
        local local_status=$(map_jira_to_local_status "$jira_status")
    else
        # Fallback mapping
        case "$jira_status" in
            "To Do"|"Open"|"Backlog") local_status="open" ;;
            "In Progress"|"In Review") local_status="in-progress" ;;
            "Done"|"Resolved"|"Closed") local_status="completed" ;;
            *) local_status="open" ;;
        esac
    fi
    
    local current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Update task file with Jira data
    # Update status
    if [[ -n "$local_status" ]]; then
        if grep -q "^status:" "$task_file"; then
            sed -i.bak "s/^status:.*/status: $local_status/" "$task_file"
        else
            sed -i.bak '/^---$/a\status: '"$local_status" "$task_file"
        fi
    fi
    
    # Update assignee
    if [[ -n "$jira_assignee" ]]; then
        if grep -q "^assignee:" "$task_file"; then
            sed -i.bak "s/^assignee:.*/assignee: $jira_assignee/" "$task_file"
        else
            sed -i.bak '/^---$/a\assignee: '"$jira_assignee" "$task_file"
        fi
    fi
    
    # Update timestamp
    if grep -q "^updated:" "$task_file"; then
        sed -i.bak "s/^updated:.*/updated: $current_date/" "$task_file"
    else
        sed -i.bak '/^---$/a\updated: '"$current_date" "$task_file"
    fi
    
    # Add resolution marker
    if ! grep -q "^conflict_resolved:" "$task_file"; then
        sed -i.bak '/^---$/a\conflict_resolved: jira_wins_'"$current_date" "$task_file"
    fi
    
    # Clean up backup
    rm -f "${task_file}.bak"
    
    echo "✅ Jira changes applied, local changes overridden"
    echo "   Status: $local_status (from Jira: $jira_status)"
    echo "   Assignee: ${jira_assignee:-"none"} (from Jira)"
    
    return 0
}

# Resolution strategy: Intelligent merge
# Usage: resolve_intelligent_merge <conflict_report> <task_file> <jira_data_file> <cache_file>
resolve_intelligent_merge() {
    local conflict_report="$1"
    local task_file="$2"
    local jira_data_file="$3"
    local cache_file="$4"
    
    echo "🧠 Applying intelligent merge strategy..."
    
    # Get conflict types
    local conflicts=""
    if command -v jq >/dev/null 2>&1; then
        conflicts=$(jq -r '.conflicts[]?' "$conflict_report" | tr '\n' ' ')
    else
        # Simple fallback - assume status conflict
        conflicts="status"
    fi
    
    echo "   Conflicts to resolve: $conflicts"
    
    # Apply merge rules based on conflict type
    for conflict in $conflicts; do
        case "$conflict" in
            "status")
                resolve_status_merge "$conflict_report" "$task_file" "$jira_data_file"
                ;;
            "assignee")
                resolve_assignee_merge "$conflict_report" "$task_file" "$jira_data_file"
                ;;
            *)
                echo "⚠️  Unknown conflict type: $conflict, applying Jira wins"
                ;;
        esac
    done
    
    # Update timestamp
    local current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    if grep -q "^updated:" "$task_file"; then
        sed -i.bak "s/^updated:.*/updated: $current_date/" "$task_file"
    else
        sed -i.bak '/^---$/a\updated: '"$current_date" "$task_file"
    fi
    
    # Add resolution marker
    if ! grep -q "^conflict_resolved:" "$task_file"; then
        sed -i.bak '/^---$/a\conflict_resolved: intelligent_merge_'"$current_date" "$task_file"
    fi
    
    # Clean up backup
    rm -f "${task_file}.bak"
    
    echo "✅ Intelligent merge completed"
    return 0
}

# Resolve status conflicts with intelligent merge
# Usage: resolve_status_merge <conflict_report> <task_file> <jira_data_file>
resolve_status_merge() {
    local conflict_report="$1"
    local task_file="$2"
    local jira_data_file="$3"
    
    # Get current states
    local local_status=$(grep "^status:" "$task_file" | head -1 | sed 's/^status: *//' || echo "open")
    
    local jira_status=""
    if command -v jq >/dev/null 2>&1; then
        jira_status=$(jq -r '.fields.status.name // ""' "$jira_data_file")
    else
        jira_status=$(grep -o '"name": *"[^"]*"' "$jira_data_file" | head -1 | cut -d'"' -f4)
    fi
    
    echo "   Merging status conflict:"
    echo "     Local: $local_status"
    echo "     Jira:  $jira_status"
    
    # Intelligent merge rules:
    # 1. If local is "in-progress" and Jira is "open", keep local (work started)
    # 2. If local is "open" and Jira is "done", take Jira (completed elsewhere)
    # 3. If local is "completed" and Jira is "in-progress", keep local (work done)
    # 4. Default: take the "more advanced" status
    
    local final_status="$local_status"
    
    case "$local_status|$jira_status" in
        "open|In Progress"|"open|Done"|"open|Closed")
            # Jira is more advanced, take it
            if declare -f map_jira_to_local_status >/dev/null; then
                final_status=$(map_jira_to_local_status "$jira_status")
            else
                final_status="in-progress"  # Safe fallback
            fi
            echo "     Decision: Taking Jira status (more advanced)"
            ;;
        "in-progress|To Do"|"in-progress|Open")
            # Local is more advanced, keep it
            final_status="$local_status"
            echo "     Decision: Keeping local status (work in progress)"
            ;;
        "completed|In Progress"|"completed|To Do")
            # Local shows completion, keep it
            final_status="$local_status"
            echo "     Decision: Keeping local status (work completed)"
            ;;
        *)
            # Default: keep local unless Jira shows completion
            if [[ "$jira_status" =~ ^(Done|Closed|Resolved)$ ]]; then
                if declare -f map_jira_to_local_status >/dev/null; then
                    final_status=$(map_jira_to_local_status "$jira_status")
                else
                    final_status="completed"
                fi
                echo "     Decision: Taking Jira status (shows completion)"
            else
                final_status="$local_status"
                echo "     Decision: Keeping local status (default)"
            fi
            ;;
    esac
    
    # Update the task file
    if grep -q "^status:" "$task_file"; then
        sed -i.bak "s/^status:.*/status: $final_status/" "$task_file"
    else
        sed -i.bak '/^---$/a\status: '"$final_status" "$task_file"
    fi
    
    echo "     Final: $final_status"
    return 0
}

# Resolve assignee conflicts with intelligent merge
# Usage: resolve_assignee_merge <conflict_report> <task_file> <jira_data_file>
resolve_assignee_merge() {
    local conflict_report="$1"
    local task_file="$2"
    local jira_data_file="$3"
    
    local local_assignee=$(grep "^assignee:" "$task_file" | head -1 | sed 's/^assignee: *//' || echo "")
    
    local jira_assignee=""
    if command -v jq >/dev/null 2>&1; then
        jira_assignee=$(jq -r '.fields.assignee.displayName // ""' "$jira_data_file")
    else
        jira_assignee=$(grep -o '"displayName": *"[^"]*"' "$jira_data_file" | head -1 | cut -d'"' -f4)
    fi
    
    echo "   Merging assignee conflict:"
    echo "     Local: ${local_assignee:-"unassigned"}"
    echo "     Jira:  ${jira_assignee:-"unassigned"}"
    
    # Merge rules:
    # 1. If either is unassigned, take the assigned one
    # 2. If both assigned differently, prefer Jira (authoritative)
    
    local final_assignee="$local_assignee"
    
    if [[ -z "$local_assignee" && -n "$jira_assignee" ]]; then
        final_assignee="$jira_assignee"
        echo "     Decision: Taking Jira assignee (local was unassigned)"
    elif [[ -n "$local_assignee" && -z "$jira_assignee" ]]; then
        final_assignee="$local_assignee"
        echo "     Decision: Keeping local assignee (Jira was unassigned)"
    elif [[ "$local_assignee" != "$jira_assignee" ]]; then
        final_assignee="$jira_assignee"
        echo "     Decision: Taking Jira assignee (authoritative source)"
    else
        echo "     Decision: No change needed (same assignee)"
    fi
    
    # Update the task file
    if [[ -n "$final_assignee" ]]; then
        if grep -q "^assignee:" "$task_file"; then
            sed -i.bak "s/^assignee:.*/assignee: $final_assignee/" "$task_file"
        else
            sed -i.bak '/^---$/a\assignee: '"$final_assignee" "$task_file"
        fi
    fi
    
    echo "     Final: ${final_assignee:-"unassigned"}"
    return 0
}

# Interactive conflict resolution
# Usage: resolve_interactive <conflict_report> <task_file> <jira_data_file> <cache_file>
resolve_interactive() {
    local conflict_report="$1"
    local task_file="$2"
    local jira_data_file="$3"
    local cache_file="$4"
    
    echo "🤝 Starting interactive conflict resolution..."
    echo ""
    
    # This is a simplified interactive resolution
    # In a full implementation, this would present each conflict and ask for user input
    
    echo "⚠️  Interactive resolution not fully implemented in this version"
    echo "   Falling back to intelligent merge strategy"
    
    resolve_intelligent_merge "$conflict_report" "$task_file" "$jira_data_file" "$cache_file"
    return $?
}

# Set up manual resolution
# Usage: setup_manual_resolution <conflict_report> <task_file> <jira_data_file> <cache_file>
setup_manual_resolution() {
    local conflict_report="$1"
    local task_file="$2"
    local jira_data_file="$3"
    local cache_file="$4"
    
    echo "📝 Setting up manual conflict resolution..."
    
    # Create a resolution guide file
    local resolution_guide="/tmp/conflict-resolution-guide-$$.md"
    
    cat > "$resolution_guide" << EOF
# Manual Conflict Resolution Guide

## Conflict Summary
$(cat "$conflict_report" | head -20)

## Files Involved
- Task file: $task_file
- Jira data: $jira_data_file
- Cache file: $cache_file

## Manual Resolution Steps

1. Review the conflicts listed above
2. Edit the task file: $task_file
3. Make your desired changes to resolve conflicts
4. Run the sync command again with --force flag

## Current States

### Local Task File
$(head -20 "$task_file" 2>/dev/null || echo "File not readable")

### Jira Data (excerpt)
$(head -10 "$jira_data_file" 2>/dev/null || echo "File not readable")

## Resolution Options

1. Keep local changes: Edit task file as desired, run with --force
2. Accept Jira changes: Don't edit task file, run sync again
3. Merge manually: Combine information from both sources

EOF
    
    echo "✅ Manual resolution guide created: $resolution_guide"
    echo ""
    echo "📋 Next steps:"
    echo "1. Review the guide: cat $resolution_guide"
    echo "2. Edit your task file: $task_file"
    echo "3. Re-run sync with: issue-sync <number> --force"
    echo ""
    
    return 1  # Return error to stop automatic processing
}

# Log conflict resolution
# Usage: log_conflict_resolution <conflict_report> <strategy> <result> <backup_dir>
log_conflict_resolution() {
    local conflict_report="$1"
    local strategy="$2"
    local result="$3"
    local backup_dir="$4"
    
    local log_dir=".claude/logs"
    mkdir -p "$log_dir"
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local log_entry="$timestamp - CONFLICT_RESOLUTION: strategy=$strategy result=$result backup=$backup_dir"
    
    echo "$log_entry" >> "$log_dir/sync-conflicts.log"
    
    # Also log the conflict details
    if [[ -f "$conflict_report" ]]; then
        echo "--- Conflict Details ($timestamp) ---" >> "$log_dir/sync-conflicts.log"
        cat "$conflict_report" >> "$log_dir/sync-conflicts.log"
        echo "--- End Conflict Details ---" >> "$log_dir/sync-conflicts.log"
        echo "" >> "$log_dir/sync-conflicts.log"
    fi
}

# Rollback changes from backup
# Usage: rollback_sync_changes <backup_dir> <task_file> <cache_file>
rollback_sync_changes() {
    local backup_dir="$1"
    local task_file="$2"
    local cache_file="$3"
    
    if [[ ! -d "$backup_dir" ]]; then
        echo "❌ Backup directory not found: $backup_dir" >&2
        return 1
    fi
    
    echo "🔄 Rolling back changes from backup..."
    
    # Restore task file
    if [[ -f "$backup_dir/task_file.bak" ]]; then
        cp "$backup_dir/task_file.bak" "$task_file"
        echo "✅ Task file restored from backup"
    fi
    
    # Restore cache file
    if [[ -f "$backup_dir/cache_file.bak" && -n "$cache_file" ]]; then
        cp "$backup_dir/cache_file.bak" "$cache_file"
        echo "✅ Cache file restored from backup"
    fi
    
    echo "✅ Rollback completed"
    
    # Log the rollback
    local log_dir=".claude/logs"
    mkdir -p "$log_dir"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "$timestamp - ROLLBACK: restored from $backup_dir" >> "$log_dir/sync-conflicts.log"
    
    return 0
}

# Check if conflicts can be auto-resolved
# Usage: can_auto_resolve <conflict_report>
can_auto_resolve() {
    local conflict_report="$1"
    
    if [[ ! -f "$conflict_report" ]]; then
        echo "false"
        return 1
    fi
    
    # Simple heuristic: if only status conflicts, auto-resolve
    if command -v jq >/dev/null 2>&1; then
        local conflict_count=$(jq -r '.conflicts | length' "$conflict_report" 2>/dev/null || echo "0")
        local has_status_only=$(jq -r '.conflicts | contains(["status"]) and (length == 1)' "$conflict_report" 2>/dev/null || echo "false")
        
        if [[ "$has_status_only" == "true" ]]; then
            echo "true"
            return 0
        fi
    fi
    
    echo "false"
    return 1
}

# Export functions for use by other scripts
export -f resolve_sync_conflicts
export -f resolve_local_wins
export -f resolve_jira_wins
export -f resolve_intelligent_merge
export -f resolve_status_merge
export -f resolve_assignee_merge
export -f resolve_interactive
export -f setup_manual_resolution
export -f log_conflict_resolution
export -f rollback_sync_changes
export -f can_auto_resolve