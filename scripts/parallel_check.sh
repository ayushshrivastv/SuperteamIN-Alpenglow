#!/bin/bash

#############################################################################
# Parallel Model Checking Script for Alpenglow Protocol
#
# This script runs multiple model configurations in parallel for faster
# verification. It manages resource allocation and provides real-time
# progress monitoring.
#
# Usage: ./parallel_check.sh [OPTIONS]
#   --configs CONFIG1,CONFIG2,...  Configurations to run (default: all)
#   --max-parallel N              Maximum parallel jobs (default: auto)
#   --timeout SECONDS             Timeout per configuration (default: 3600)
#   --output-dir DIR              Output directory (default: results/parallel)
#############################################################################

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CHECK_MODEL="$SCRIPT_DIR/check_model.sh"

# Default values
ALL_CONFIGS=("Small" "Medium" "Boundary" "EdgeCase" "Partition")
CONFIGS=()
MAX_PARALLEL=""
TIMEOUT=3600
OUTPUT_DIR="$PROJECT_DIR/results/parallel"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --configs)
            IFS=',' read -ra CONFIGS <<< "$2"
            shift 2
            ;;
        --max-parallel)
            MAX_PARALLEL="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "  --configs CONFIG1,CONFIG2,...  Configurations to run"
            echo "  --max-parallel N              Maximum parallel jobs"
            echo "  --timeout SECONDS             Timeout per configuration"
            echo "  --output-dir DIR              Output directory"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Use all configs if none specified
if [ ${#CONFIGS[@]} -eq 0 ]; then
    CONFIGS=("${ALL_CONFIGS[@]}")
fi

# Auto-detect max parallel jobs if not specified
if [ -z "$MAX_PARALLEL" ]; then
    if command -v nproc &> /dev/null; then
        MAX_PARALLEL=$(nproc)
    elif command -v sysctl &> /dev/null; then
        MAX_PARALLEL=$(sysctl -n hw.ncpu)
    else
        MAX_PARALLEL=4
    fi
    # Use half the CPU cores for model checking
    MAX_PARALLEL=$((MAX_PARALLEL / 2))
    [ $MAX_PARALLEL -lt 1 ] && MAX_PARALLEL=1
fi

# Helper functions
print_header() {
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_progress() {
    local config=$1
    local status=$2
    local color=$3
    printf "${color}%-15s${NC} %s\n" "[$config]" "$status"
}

# Create output directory
mkdir -p "$OUTPUT_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SESSION_DIR="$OUTPUT_DIR/session_${TIMESTAMP}"
mkdir -p "$SESSION_DIR"

# Job management
declare -A JOB_PIDS
declare -A JOB_STATUS
declare -A JOB_START
declare -A JOB_END

# Start a model checking job
start_job() {
    local config=$1
    local output_file="$SESSION_DIR/${config}.log"
    
    print_progress "$config" "Starting..." "$CYAN"
    JOB_START[$config]=$(date +%s)
    
    # Run model checker with timeout
    timeout $TIMEOUT "$CHECK_MODEL" "$config" > "$output_file" 2>&1 &
    local pid=$!
    
    JOB_PIDS[$config]=$pid
    JOB_STATUS[$config]="RUNNING"
    
    return 0
}

# Check job status
check_job() {
    local config=$1
    local pid=${JOB_PIDS[$config]}
    
    if kill -0 $pid 2>/dev/null; then
        return 1  # Still running
    else
        wait $pid
        local exit_code=$?
        JOB_END[$config]=$(date +%s)
        
        if [ $exit_code -eq 0 ]; then
            JOB_STATUS[$config]="SUCCESS"
            return 0
        elif [ $exit_code -eq 124 ]; then
            JOB_STATUS[$config]="TIMEOUT"
            return 2
        else
            JOB_STATUS[$config]="FAILED"
            return 3
        fi
    fi
}

# Monitor running jobs
monitor_jobs() {
    local running=0
    local completed=0
    local failed=0
    local timeout=0
    
    for config in "${!JOB_STATUS[@]}"; do
        case ${JOB_STATUS[$config]} in
            RUNNING)
                running=$((running + 1))
                ;;
            SUCCESS)
                completed=$((completed + 1))
                ;;
            FAILED)
                failed=$((failed + 1))
                ;;
            TIMEOUT)
                timeout=$((timeout + 1))
                ;;
        esac
    done
    
    echo -ne "\r${CYAN}Running: $running${NC} | ${GREEN}Completed: $completed${NC} | ${RED}Failed: $failed${NC} | ${YELLOW}Timeout: $timeout${NC}    "
}

# Extract results from log file
extract_results() {
    local config=$1
    local log_file="$SESSION_DIR/${config}.log"
    local results_file="$SESSION_DIR/${config}_results.txt"
    
    if [ ! -f "$log_file" ]; then
        echo "No results available" > "$results_file"
        return
    fi
    
    {
        echo "Configuration: $config"
        echo "Status: ${JOB_STATUS[$config]}"
        if [ -n "${JOB_START[$config]}" ] && [ -n "${JOB_END[$config]}" ]; then
            local duration=$((JOB_END[$config] - JOB_START[$config]))
            echo "Duration: $(printf '%02d:%02d:%02d' $((duration/3600)) $((duration%3600/60)) $((duration%60)))"
        fi
        echo ""
        
        # Extract key metrics from log
        if grep -q "Model checking completed" "$log_file"; then
            echo "States Generated: $(grep -oE '[0-9]+ states generated' "$log_file" | head -1)"
            echo "Distinct States: $(grep -oE '[0-9]+ distinct states' "$log_file" | head -1)"
            echo "Queue Size: $(grep -oE 'Queue size: [0-9]+' "$log_file" | head -1)"
        fi
        
        # Check for violations
        if grep -q "Invariant .* is violated" "$log_file"; then
            echo ""
            echo "VIOLATIONS FOUND:"
            grep "Invariant .* is violated" "$log_file"
        fi
        
        if grep -q "Deadlock" "$log_file"; then
            echo ""
            echo "DEADLOCK DETECTED"
        fi
    } > "$results_file"
}

# Generate summary report
generate_summary() {
    local summary_file="$SESSION_DIR/summary.txt"
    
    {
        echo "Parallel Model Checking Summary"
        echo "==============================="
        echo "Timestamp: $(date)"
        echo "Configurations: ${CONFIGS[*]}"
        echo "Max Parallel Jobs: $MAX_PARALLEL"
        echo "Timeout: $TIMEOUT seconds"
        echo ""
        echo "Results:"
        echo "--------"
        
        local total_time=0
        for config in "${CONFIGS[@]}"; do
            printf "%-15s: %-10s" "$config" "${JOB_STATUS[$config]:-PENDING}"
            
            if [ -n "${JOB_START[$config]}" ] && [ -n "${JOB_END[$config]}" ]; then
                local duration=$((JOB_END[$config] - JOB_START[$config]))
                total_time=$((total_time + duration))
                printf " (Time: %02d:%02d:%02d)" $((duration/3600)) $((duration%3600/60)) $((duration%60))
            fi
            echo
        done
        
        echo ""
        echo "Statistics:"
        echo "-----------"
        local success_count=0
        local failed_count=0
        local timeout_count=0
        
        for config in "${CONFIGS[@]}"; do
            case ${JOB_STATUS[$config]} in
                SUCCESS) success_count=$((success_count + 1)) ;;
                FAILED) failed_count=$((failed_count + 1)) ;;
                TIMEOUT) timeout_count=$((timeout_count + 1)) ;;
            esac
        done
        
        echo "Successful: $success_count / ${#CONFIGS[@]}"
        echo "Failed: $failed_count"
        echo "Timeout: $timeout_count"
        echo "Total Time: $(printf '%02d:%02d:%02d' $((total_time/3600)) $((total_time%3600/60)) $((total_time%60)))"
        
        # Calculate speedup
        local sequential_time=$((${#CONFIGS[@]} * TIMEOUT))
        local actual_time=$(($(date +%s) - START_TIME))
        local speedup=$(echo "scale=2; $total_time / $actual_time" | bc)
        echo "Speedup: ${speedup}x (vs sequential execution)"
        
    } > "$summary_file"
    
    cat "$summary_file"
}

# Main execution
main() {
    print_header "Parallel Model Checking"
    print_info "Configurations to check: ${CONFIGS[*]}"
    print_info "Max parallel jobs: $MAX_PARALLEL"
    print_info "Timeout per job: $TIMEOUT seconds"
    print_info "Output directory: $SESSION_DIR"
    echo
    
    START_TIME=$(date +%s)
    
    # Job queue
    local queue=("${CONFIGS[@]}")
    local queue_index=0
    local active_jobs=0
    
    # Start initial batch of jobs
    while [ $active_jobs -lt $MAX_PARALLEL ] && [ $queue_index -lt ${#queue[@]} ]; do
        start_job "${queue[$queue_index]}"
        active_jobs=$((active_jobs + 1))
        queue_index=$((queue_index + 1))
        sleep 1  # Small delay between starts
    done
    
    # Main loop - monitor jobs and start new ones as slots become available
    while [ $active_jobs -gt 0 ] || [ $queue_index -lt ${#queue[@]} ]; do
        # Check status of running jobs
        for config in "${!JOB_PIDS[@]}"; do
            if [ "${JOB_STATUS[$config]}" == "RUNNING" ]; then
                if check_job "$config"; then
                    active_jobs=$((active_jobs - 1))
                    
                    # Report completion
                    case ${JOB_STATUS[$config]} in
                        SUCCESS)
                            print_progress "$config" "Completed successfully" "$GREEN"
                            ;;
                        TIMEOUT)
                            print_progress "$config" "Timed out after $TIMEOUT seconds" "$YELLOW"
                            ;;
                        FAILED)
                            print_progress "$config" "Failed - check logs" "$RED"
                            ;;
                    esac
                    
                    # Extract results immediately
                    extract_results "$config"
                    
                    # Start next job if available
                    if [ $queue_index -lt ${#queue[@]} ]; then
                        start_job "${queue[$queue_index]}"
                        active_jobs=$((active_jobs + 1))
                        queue_index=$((queue_index + 1))
                    fi
                fi
            fi
        done
        
        # Show progress
        monitor_jobs
        
        sleep 2
    done
    
    echo  # New line after progress indicator
    echo
    
    # Generate final summary
    print_header "Summary"
    generate_summary
    
    END_TIME=$(date +%s)
    TOTAL_DURATION=$((END_TIME - START_TIME))
    
    echo
    print_info "Parallel checking completed in $(printf '%02d:%02d:%02d' $((TOTAL_DURATION/3600)) $((TOTAL_DURATION%3600/60)) $((TOTAL_DURATION%60)))"
    print_info "Full results saved to: $SESSION_DIR"
    
    # Exit with appropriate code
    for config in "${CONFIGS[@]}"; do
        if [ "${JOB_STATUS[$config]}" != "SUCCESS" ]; then
            exit 1
        fi
    done
    exit 0
}

# Run main
main
