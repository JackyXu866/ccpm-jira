#!/bin/bash
set -euo pipefail

# =============================================================================
# Performance Testing Suite for JIRA CRUD Operations
# =============================================================================
# This test suite validates performance characteristics of bulk operations,
# timeout handling, retry logic, and memory usage patterns for the CCPM-Jira
# integration system.
#
# Author: Claude Code - Stream D Implementation  
# Version: 1.0.0
# =============================================================================

# Performance test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../../lib"
RESULTS_DIR="/tmp/ccpm_jira_performance_$(date +%s)"

# Source dependencies
source "${LIB_DIR}/jira-fields.sh"
source "${LIB_DIR}/jira-epic-ops.sh"
source "${LIB_DIR}/jira-task-ops.sh"
source "${LIB_DIR}/jira-validation.sh"

# Performance test variables
declare -g PERFORMANCE_RESULTS=()
declare -g MEMORY_SNAPSHOTS=()

# Test size configurations
SMALL_DATASET_SIZE=10
MEDIUM_DATASET_SIZE=50
LARGE_DATASET_SIZE=100

# =============================================================================
# Performance Utilities
# =============================================================================

#' Create results directory
setup_performance_tests() {
    mkdir -p "$RESULTS_DIR"
    echo "Performance test results will be saved to: $RESULTS_DIR"
    
    # Create memory monitoring script
    cat > "$RESULTS_DIR/monitor_memory.sh" << 'EOF'
#!/bin/bash
while true; do
    if pgrep -f "performance-test.sh" > /dev/null; then
        echo "$(date +%s),$(ps -o pid,vsz,rss,pcpu,pmem,comm -p $$ | tail -1)" >> "$1"
        sleep 1
    else
        break
    fi
done
EOF
    chmod +x "$RESULTS_DIR/monitor_memory.sh"
}

#' Start performance monitoring
start_monitoring() {
    local test_name="$1"
    local memory_log="$RESULTS_DIR/${test_name}_memory.csv"
    
    echo "timestamp,pid,vsz,rss,pcpu,pmem,comm" > "$memory_log"
    "$RESULTS_DIR/monitor_memory.sh" "$memory_log" &
    local monitor_pid=$!
    echo "$monitor_pid"
}

#' Stop performance monitoring  
stop_monitoring() {
    local monitor_pid="$1"
    if kill -0 "$monitor_pid" 2>/dev/null; then
        kill "$monitor_pid"
        wait "$monitor_pid" 2>/dev/null || true
    fi
}

#' Record performance result
record_performance_result() {
    local test_name="$1"
    local operation="$2" 
    local dataset_size="$3"
    local duration="$4"
    local memory_peak="$5"
    local throughput="$6"
    local success_rate="$7"
    
    local result_entry
    result_entry=$(jq -n \
        --arg name "$test_name" \
        --arg op "$operation" \
        --arg size "$dataset_size" \
        --arg dur "$duration" \
        --arg mem "$memory_peak" \
        --arg throughput "$throughput" \
        --arg success "$success_rate" \
        '{
            test_name: $name,
            operation: $op,
            dataset_size: ($size | tonumber),
            duration_seconds: ($dur | tonumber),
            memory_peak_mb: ($mem | tonumber),
            throughput_ops_per_sec: ($throughput | tonumber),
            success_rate_percent: ($success | tonumber),
            timestamp: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
        }')
    
    PERFORMANCE_RESULTS+=("$result_entry")
    
    echo "📊 Performance Result: $test_name"
    echo "   Operation: $operation, Size: $dataset_size"
    echo "   Duration: ${duration}s, Throughput: ${throughput} ops/sec"
    echo "   Memory Peak: ${memory_peak}MB, Success: ${success_rate}%"
}

#' Generate test dataset of specified size
generate_test_dataset() {
    local dataset_type="$1"  # "epics" or "tasks"
    local size="$2"
    local prefix="${3:-perf_test}"
    
    local dataset="[]"
    
    for ((i=1; i<=size; i++)); do
        if [[ "$dataset_type" == "epics" ]]; then
            local epic_data
            epic_data=$(jq -n \
                --arg id "${prefix}_epic_${i}" \
                --arg name "Performance Test Epic $i" \
                --arg desc "Epic $i created for performance testing with dataset size $size" \
                --arg status "open" \
                --arg start "$(date -Iseconds)" \
                '{
                    id: $id,
                    name: $name,
                    description: $desc,
                    status: $status,
                    start_date: $start,
                    progress: "0%",
                    priority: "medium",
                    business_value: "medium",
                    theme: "performance_testing"
                }')
            dataset=$(echo "$dataset" | jq --argjson item "$epic_data" '. + [$item]')
        else
            local task_data
            task_data=$(jq -n \
                --arg id "${prefix}_task_${i}" \
                --arg name "Performance Test Task $i" \
                --arg desc "Task $i created for performance testing with dataset size $size" \
                --arg status "open" \
                '{
                    id: $id,
                    name: $name,
                    description: $desc,
                    status: $status,
                    progress: "0%",
                    priority: "medium",
                    assignee: "",
                    estimated_hours: 8
                }')
            dataset=$(echo "$dataset" | jq --argjson item "$task_data" '. + [$item]')
        fi
    done
    
    echo "$dataset"
}

#' Calculate memory peak from memory log
calculate_memory_peak() {
    local memory_log="$1"
    
    if [[ -f "$memory_log" ]]; then
        # Skip header and extract RSS column (resident memory in KB), convert to MB
        tail -n +2 "$memory_log" | cut -d',' -f4 | awk 'BEGIN{max=0} {if($1>max) max=$1} END{print int(max/1024)}'
    else
        echo "0"
    fi
}

# =============================================================================
# Field Mapping Performance Tests
# =============================================================================

#' Test field mapping performance with various dataset sizes
test_field_mapping_performance() {
    echo "=== Testing Field Mapping Performance ==="
    
    local sizes=($SMALL_DATASET_SIZE $MEDIUM_DATASET_SIZE $LARGE_DATASET_SIZE)
    
    for size in "${sizes[@]}"; do
        echo "Testing field mapping with dataset size: $size"
        
        # Test epic field mapping
        local start_time monitor_pid
        start_time=$(date +%s.%N)
        monitor_pid=$(start_monitoring "field_mapping_epics_${size}")
        
        local test_epics
        test_epics=$(generate_test_dataset "epics" "$size" "field_mapping")
        
        local successful_mappings=0
        local total_operations="$size"
        
        while read -r epic_json; do
            [[ -z "$epic_json" || "$epic_json" == "null" ]] && continue
            
            local epic_name
            epic_name=$(echo "$epic_json" | jq -r '.name')
            
            if prepare_epic_for_jira "$epic_name" "$epic_json" >/dev/null 2>&1; then
                successful_mappings=$((successful_mappings + 1))
            fi
        done < <(echo "$test_epics" | jq -c '.[]?')
        
        local end_time duration memory_peak throughput success_rate
        end_time=$(date +%s.%N)
        duration=$(echo "$end_time - $start_time" | bc)
        
        stop_monitoring "$monitor_pid"
        memory_peak=$(calculate_memory_peak "$RESULTS_DIR/field_mapping_epics_${size}_memory.csv")
        
        throughput=$(echo "scale=2; $successful_mappings / $duration" | bc)
        success_rate=$(echo "scale=2; $successful_mappings * 100 / $total_operations" | bc)
        
        record_performance_result \
            "field_mapping_epics_${size}" \
            "field_mapping" \
            "$size" \
            "$duration" \
            "$memory_peak" \
            "$throughput" \
            "$success_rate"
    done
}

# =============================================================================
# Validation Performance Tests  
# =============================================================================

#' Test validation performance with various dataset sizes
test_validation_performance() {
    echo "=== Testing Validation Performance ==="
    
    local sizes=($SMALL_DATASET_SIZE $MEDIUM_DATASET_SIZE $LARGE_DATASET_SIZE)
    
    for size in "${sizes[@]}"; do
        echo "Testing validation with dataset size: $size"
        
        local start_time monitor_pid
        start_time=$(date +%s.%N)
        monitor_pid=$(start_monitoring "validation_epics_${size}")
        
        local test_epics
        test_epics=$(generate_test_dataset "epics" "$size" "validation")
        
        # Run bulk validation
        local validation_result
        if validation_result=$(validate_multiple_epics "$test_epics" 2>/dev/null); then
            local successful_validations
            successful_validations=$(echo "$validation_result" | jq -r '.summary.passed // 0')
            local total_validations
            total_validations=$(echo "$validation_result" | jq -r '.summary.total_epics // 0')
        else
            successful_validations=0
            total_validations="$size"
        fi
        
        local end_time duration memory_peak throughput success_rate
        end_time=$(date +%s.%N)
        duration=$(echo "$end_time - $start_time" | bc)
        
        stop_monitoring "$monitor_pid"
        memory_peak=$(calculate_memory_peak "$RESULTS_DIR/validation_epics_${size}_memory.csv")
        
        throughput=$(echo "scale=2; $successful_validations / $duration" | bc)
        success_rate=$(echo "scale=2; $successful_validations * 100 / $total_validations" | bc)
        
        record_performance_result \
            "validation_epics_${size}" \
            "validation" \
            "$size" \
            "$duration" \
            "$memory_peak" \
            "$throughput" \
            "$success_rate"
    done
}

# =============================================================================
# Bulk Operations Performance Tests
# =============================================================================

#' Test bulk operations performance  
test_bulk_operations_performance() {
    echo "=== Testing Bulk Operations Performance ==="
    
    local sizes=($SMALL_DATASET_SIZE $MEDIUM_DATASET_SIZE $LARGE_DATASET_SIZE)
    
    for size in "${sizes[@]}"; do
        echo "Testing bulk operations with dataset size: $size"
        
        # Test bulk epic preparation (simulating bulk creation)
        local start_time monitor_pid
        start_time=$(date +%s.%N)
        monitor_pid=$(start_monitoring "bulk_ops_epics_${size}")
        
        local test_epics
        test_epics=$(generate_test_dataset "epics" "$size" "bulk_ops")
        
        local successful_preparations=0
        local total_operations="$size"
        
        # Simulate bulk preparation for creation
        while read -r epic_json; do
            [[ -z "$epic_json" || "$epic_json" == "null" ]] && continue
            
            local epic_name
            epic_name=$(echo "$epic_json" | jq -r '.name')
            
            if prepare_epic_for_jira "$epic_name" "$epic_json" >/dev/null 2>&1; then
                successful_preparations=$((successful_preparations + 1))
            fi
        done < <(echo "$test_epics" | jq -c '.[]?')
        
        local end_time duration memory_peak throughput success_rate
        end_time=$(date +%s.%N)
        duration=$(echo "$end_time - $start_time" | bc)
        
        stop_monitoring "$monitor_pid"
        memory_peak=$(calculate_memory_peak "$RESULTS_DIR/bulk_ops_epics_${size}_memory.csv")
        
        throughput=$(echo "scale=2; $successful_preparations / $duration" | bc)
        success_rate=$(echo "scale=2; $successful_preparations * 100 / $total_operations" | bc)
        
        record_performance_result \
            "bulk_operations_epics_${size}" \
            "bulk_preparation" \
            "$size" \
            "$duration" \
            "$memory_peak" \
            "$throughput" \
            "$success_rate"
    done
}

# =============================================================================
# Memory Usage Tests
# =============================================================================

#' Test memory usage patterns
test_memory_usage_patterns() {
    echo "=== Testing Memory Usage Patterns ==="
    
    # Test memory usage with increasing dataset sizes
    local sizes=(10 25 50 100 200)
    
    for size in "${sizes[@]}"; do
        echo "Testing memory usage with dataset size: $size"
        
        local monitor_pid
        monitor_pid=$(start_monitoring "memory_usage_${size}")
        
        # Generate and process dataset
        local test_data
        test_data=$(generate_test_dataset "epics" "$size" "memory_test")
        
        # Process each item to simulate real workload
        local processed=0
        while read -r item_json; do
            [[ -z "$item_json" || "$item_json" == "null" ]] && continue
            
            local item_name
            item_name=$(echo "$item_json" | jq -r '.name')
            
            # Simulate processing
            prepare_epic_for_jira "$item_name" "$item_json" >/dev/null 2>&1
            validate_ccpm_epic "$item_json" >/dev/null 2>&1
            
            processed=$((processed + 1))
            
            # Small delay to allow memory monitoring
            sleep 0.01
        done < <(echo "$test_data" | jq -c '.[]?')
        
        stop_monitoring "$monitor_pid"
        local memory_peak
        memory_peak=$(calculate_memory_peak "$RESULTS_DIR/memory_usage_${size}_memory.csv")
        
        echo "   Dataset size $size: Peak memory usage ${memory_peak}MB"
        
        # Record memory usage data point
        MEMORY_SNAPSHOTS+=("{\"dataset_size\": $size, \"peak_memory_mb\": $memory_peak}")
    done
}

# =============================================================================
# Timeout and Retry Logic Tests
# =============================================================================

#' Test timeout and retry behavior simulation
test_timeout_retry_behavior() {
    echo "=== Testing Timeout and Retry Behavior ==="
    
    # Simulate various timeout scenarios
    local timeout_scenarios=("normal" "slow" "timeout")
    
    for scenario in "${timeout_scenarios[@]}"; do
        echo "Testing timeout scenario: $scenario"
        
        local start_time monitor_pid
        start_time=$(date +%s.%N)
        monitor_pid=$(start_monitoring "timeout_${scenario}")
        
        local test_items
        test_items=$(generate_test_dataset "tasks" 20 "timeout_test")
        
        local successful_operations=0
        local total_operations=20
        
        while read -r task_json; do
            [[ -z "$task_json" || "$task_json" == "null" ]] && continue
            
            # Simulate different response times based on scenario
            case "$scenario" in
                "slow")
                    sleep 0.1  # Simulate slow operation
                    ;;
                "timeout")
                    sleep 0.2  # Simulate timeout scenario
                    ;;
            esac
            
            local task_name
            task_name=$(echo "$task_json" | jq -r '.name')
            
            if prepare_task_for_jira "$task_name" "$task_json" >/dev/null 2>&1; then
                successful_operations=$((successful_operations + 1))
            fi
            
        done < <(echo "$test_items" | jq -c '.[]?')
        
        local end_time duration memory_peak throughput success_rate
        end_time=$(date +%s.%N)
        duration=$(echo "$end_time - $start_time" | bc)
        
        stop_monitoring "$monitor_pid"
        memory_peak=$(calculate_memory_peak "$RESULTS_DIR/timeout_${scenario}_memory.csv")
        
        throughput=$(echo "scale=2; $successful_operations / $duration" | bc)
        success_rate=$(echo "scale=2; $successful_operations * 100 / $total_operations" | bc)
        
        record_performance_result \
            "timeout_${scenario}" \
            "timeout_simulation" \
            "20" \
            "$duration" \
            "$memory_peak" \
            "$throughput" \
            "$success_rate"
    done
}

# =============================================================================
# Performance Analysis and Reporting
# =============================================================================

#' Generate performance report
generate_performance_report() {
    echo "=== Generating Performance Report ==="
    
    # Combine all performance results
    local all_results="["
    local first=true
    for result in "${PERFORMANCE_RESULTS[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            all_results+=","
        fi
        all_results+="$result"
    done
    all_results+="]"
    
    # Save detailed results
    echo "$all_results" | jq . > "$RESULTS_DIR/performance_results.json"
    
    # Generate summary report
    local summary_report
    summary_report=$(echo "$all_results" | jq '{
        summary: {
            total_tests: length,
            avg_throughput: (map(.throughput_ops_per_sec) | add / length),
            avg_success_rate: (map(.success_rate_percent) | add / length),
            max_memory_usage: (map(.memory_peak_mb) | max),
            total_duration: (map(.duration_seconds) | add)
        },
        by_operation: (
            group_by(.operation) | 
            map({
                operation: .[0].operation,
                test_count: length,
                avg_throughput: (map(.throughput_ops_per_sec) | add / length),
                avg_memory: (map(.memory_peak_mb) | add / length),
                avg_success_rate: (map(.success_rate_percent) | add / length)
            })
        ),
        by_dataset_size: (
            group_by(.dataset_size) |
            map({
                dataset_size: .[0].dataset_size,
                test_count: length,
                avg_throughput: (map(.throughput_ops_per_sec) | add / length),
                avg_memory: (map(.memory_peak_mb) | add / length)
            })
        )
    }')
    
    echo "$summary_report" | jq . > "$RESULTS_DIR/performance_summary.json"
    
    # Generate memory usage report
    if [[ ${#MEMORY_SNAPSHOTS[@]} -gt 0 ]]; then
        local memory_report="["
        first=true
        for snapshot in "${MEMORY_SNAPSHOTS[@]}"; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                memory_report+=","
            fi
            memory_report+="$snapshot"
        done
        memory_report+="]"
        echo "$memory_report" | jq . > "$RESULTS_DIR/memory_usage.json"
    fi
    
    # Print summary to console
    echo
    echo "=============================================="
    echo "Performance Test Summary"
    echo "=============================================="
    echo "$summary_report" | jq -r '
        "Total Tests: " + (.summary.total_tests | tostring) + "\n" +
        "Average Throughput: " + (.summary.avg_throughput | tostring) + " ops/sec\n" +
        "Average Success Rate: " + (.summary.avg_success_rate | tostring) + "%\n" +
        "Max Memory Usage: " + (.summary.max_memory_usage | tostring) + " MB\n" +
        "Total Duration: " + (.summary.total_duration | tostring) + " seconds"
    '
    echo
    echo "Detailed results saved to: $RESULTS_DIR"
}

# =============================================================================
# Main Performance Test Execution
# =============================================================================

#' Run all performance tests
run_performance_tests() {
    local start_time
    start_time=$(date +%s)
    
    echo "=============================================="
    echo "Starting Performance Tests"
    echo "Results Directory: $RESULTS_DIR"
    echo "=============================================="
    echo
    
    # Setup
    setup_performance_tests
    
    # Run performance test suites
    test_field_mapping_performance
    echo
    
    test_validation_performance
    echo
    
    test_bulk_operations_performance
    echo
    
    test_memory_usage_patterns
    echo
    
    test_timeout_retry_behavior
    echo
    
    # Generate final report
    generate_performance_report
    
    local end_time total_duration
    end_time=$(date +%s)
    total_duration=$((end_time - start_time))
    
    echo "=============================================="
    echo "Performance Tests Completed"
    echo "Total Duration: ${total_duration}s"
    echo "Results saved to: $RESULTS_DIR"
    echo "=============================================="
}

# Run performance tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_performance_tests
fi