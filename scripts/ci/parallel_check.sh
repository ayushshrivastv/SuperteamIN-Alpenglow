#!/bin/bash
# Author: Ayush Srivastava

# parallel_check.sh - Run multiple TLA+ model checking configurations in parallel
# Part of the Alpenglow Protocol Verification Suite

set -euo pipefail

# Script metadata
SCRIPT_NAME="parallel_check.sh"
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default configuration
DEFAULT_CONFIGS=("Small" "Medium" "Boundary" "EdgeCase")
DEFAULT_TIMEOUT=1800
DEFAULT_WORKERS=4
DEFAULT_MAX_PARALLEL=4
DEFAULT_OUTPUT_DIR="results/ci"
DEFAULT_TLA_TOOLS_PATH="$HOME/tla-tools/tla2tools.jar"

# Global variables
CONFIGS=()
TIMEOUT=$DEFAULT_TIMEOUT
MAX_PARALLEL=$DEFAULT_MAX_PARALLEL
WORKERS=$DEFAULT_WORKERS
OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
TLA_TOOLS_PATH="$DEFAULT_TLA_TOOLS_PATH"
VERBOSE=false
CI_MODE=false
FAIL_FAST=false
DRY_RUN=false
FORCE_CLEANUP=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $*" >&2
    fi
}

# Usage information
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS] [CONFIGS...]

Run multiple TLA+ model checking configurations in parallel.

ARGUMENTS:
    CONFIGS...              List of configurations to check (default: ${DEFAULT_CONFIGS[*]})
                           Available: Small, Medium, Boundary, EdgeCase, LargeScale, Adversarial

OPTIONS:
    -h, --help             Show this help message
    -v, --verbose          Enable verbose output
    --version              Show version information
    
    Configuration:
    -t, --timeout SECONDS  Timeout for each configuration (default: $DEFAULT_TIMEOUT)
    -p, --parallel COUNT   Maximum parallel jobs (default: $DEFAULT_MAX_PARALLEL)
    -w, --workers COUNT    TLC worker threads per job (default: $DEFAULT_WORKERS)
    -o, --output DIR       Output directory (default: $DEFAULT_OUTPUT_DIR)
    
    Execution:
    --ci                   CI mode (structured output, no colors)
    --fail-fast            Stop on first failure
    --dry-run              Show what would be executed without running
    --force-cleanup        Clean output directory before starting
    
    TLA+ Tools:
    --tla-tools PATH       Path to tla2tools.jar (default: $DEFAULT_TLA_TOOLS_PATH)

EXAMPLES:
    # Run default configurations
    $SCRIPT_NAME
    
    # Run specific configurations with custom timeout
    $SCRIPT_NAME --timeout 3600 Small Medium
    
    # CI mode with fail-fast
    $SCRIPT_NAME --ci --fail-fast --parallel 8
    
    # Dry run to see what would be executed
    $SCRIPT_NAME --dry-run --verbose

EXIT CODES:
    0    All configurations passed
    1    Some configurations failed
    2    All configurations failed
    3    Configuration or setup error
    4    Interrupted by user

EOF
}

# Version information
version() {
    cat << EOF
$SCRIPT_NAME version $SCRIPT_VERSION
Part of the Alpenglow Protocol Verification Suite

Copyright (c) 2024 Alpenglow Protocol Team
This is free software; see the source for copying conditions.
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            --version)
                version
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -t|--timeout)
                if [[ -z "${2:-}" ]] || [[ "$2" =~ ^- ]]; then
                    log_error "Option $1 requires an argument"
                    exit 3
                fi
                TIMEOUT="$2"
                shift 2
                ;;
            -p|--parallel)
                if [[ -z "${2:-}" ]] || [[ "$2" =~ ^- ]]; then
                    log_error "Option $1 requires an argument"
                    exit 3
                fi
                MAX_PARALLEL="$2"
                shift 2
                ;;
            -w|--workers)
                if [[ -z "${2:-}" ]] || [[ "$2" =~ ^- ]]; then
                    log_error "Option $1 requires an argument"
                    exit 3
                fi
                WORKERS="$2"
                shift 2
                ;;
            -o|--output)
                if [[ -z "${2:-}" ]] || [[ "$2" =~ ^- ]]; then
                    log_error "Option $1 requires an argument"
                    exit 3
                fi
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --ci)
                CI_MODE=true
                shift
                ;;
            --fail-fast)
                FAIL_FAST=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force-cleanup)
                FORCE_CLEANUP=true
                shift
                ;;
            --tla-tools)
                if [[ -z "${2:-}" ]] || [[ "$2" =~ ^- ]]; then
                    log_error "Option $1 requires an argument"
                    exit 3
                fi
                TLA_TOOLS_PATH="$2"
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                exit 3
                ;;
            *)
                CONFIGS+=("$1")
                shift
                ;;
        esac
    done
    
    # Use default configs if none specified
    if [[ ${#CONFIGS[@]} -eq 0 ]]; then
        CONFIGS=("${DEFAULT_CONFIGS[@]}")
    fi
    
    # Validate numeric arguments
    if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$TIMEOUT" -lt 1 ]]; then
        log_error "Invalid timeout: $TIMEOUT (must be positive integer)"
        exit 3
    fi
    
    if ! [[ "$MAX_PARALLEL" =~ ^[0-9]+$ ]] || [[ "$MAX_PARALLEL" -lt 1 ]]; then
        log_error "Invalid parallel count: $MAX_PARALLEL (must be positive integer)"
        exit 3
    fi
    
    if ! [[ "$WORKERS" =~ ^[0-9]+$ ]] || [[ "$WORKERS" -lt 1 ]]; then
        log_error "Invalid worker count: $WORKERS (must be positive integer)"
        exit 3
    fi
}

# Setup environment and validate prerequisites
setup_environment() {
    log_debug "Setting up environment..."
    
    # Change to project root
    cd "$PROJECT_ROOT"
    
    # Disable colors in CI mode
    if [[ "$CI_MODE" == "true" ]]; then
        RED=""
        GREEN=""
        YELLOW=""
        BLUE=""
        PURPLE=""
        CYAN=""
        NC=""
    fi
    
    # Validate TLA+ tools
    if [[ ! -f "$TLA_TOOLS_PATH" ]]; then
        log_error "TLA+ tools not found at: $TLA_TOOLS_PATH"
        log_error "Please install TLA+ tools or specify correct path with --tla-tools"
        exit 3
    fi
    
    # Test TLA+ tools
    if ! java -cp "$TLA_TOOLS_PATH" tlc2.TLC -h >/dev/null 2>&1; then
        log_error "TLA+ tools test failed. Please check Java installation and TLA+ tools."
        exit 3
    fi
    
    # Validate project structure
    local required_dirs=("specs" "models")
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_error "Required directory not found: $dir"
            exit 3
        fi
    done
    
    # Validate configurations
    for config in "${CONFIGS[@]}"; do
        local config_file="models/${config}.cfg"
        if [[ ! -f "$config_file" ]]; then
            log_error "Configuration file not found: $config_file"
            exit 3
        fi
    done
    
    # Setup output directory
    if [[ "$FORCE_CLEANUP" == "true" ]] && [[ -d "$OUTPUT_DIR" ]]; then
        log_info "Cleaning output directory: $OUTPUT_DIR"
        if [[ "$DRY_RUN" == "false" ]]; then
            rm -rf "$OUTPUT_DIR"
        fi
    fi
    
    if [[ "$DRY_RUN" == "false" ]]; then
        mkdir -p "$OUTPUT_DIR"
    fi
    
    log_debug "Environment setup complete"
}

# Get configuration-specific timeout
get_config_timeout() {
    local config="$1"
    case "$config" in
        Small)
            echo $((TIMEOUT < 600 ? TIMEOUT : 600))
            ;;
        Medium)
            echo $((TIMEOUT < 1800 ? TIMEOUT : 1800))
            ;;
        LargeScale|Adversarial)
            echo $((TIMEOUT < 3600 ? TIMEOUT : 3600))
            ;;
        *)
            echo "$TIMEOUT"
            ;;
    esac
}

# Run model checking for a single configuration
run_single_config() {
    local config="$1"
    local config_timeout
    config_timeout=$(get_config_timeout "$config")
    
    local log_file="$OUTPUT_DIR/model_${config}.log"
    local metrics_file="$OUTPUT_DIR/metrics_${config}.json"
    local start_time
    start_time=$(date +%s)
    
    log_info "Starting model checking for $config (timeout: ${config_timeout}s)"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would execute: timeout $config_timeout java -cp $TLA_TOOLS_PATH tlc2.TLC -config models/${config}.cfg -workers $WORKERS specs/Alpenglow"
        return 0
    fi
    
    # Run TLC with timeout
    local exit_code=0
    timeout "$config_timeout" java -cp "$TLA_TOOLS_PATH" tlc2.TLC \
        -config "models/${config}.cfg" \
        -workers "$WORKERS" \
        -verbose \
        specs/Alpenglow \
        > "$log_file" 2>&1 || exit_code=$?
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Determine status
    local status
    local states_explored=0
    local states_generated=0
    local violations=0
    
    if [[ -f "$log_file" ]]; then
        states_explored=$(grep -o '[0-9]* distinct states' "$log_file" | head -1 | cut -d' ' -f1 || echo "0")
        states_generated=$(grep -o '[0-9]* states generated' "$log_file" | head -1 | cut -d' ' -f1 || echo "0")
        violations=$(grep -c 'Error:' "$log_file" || echo "0")
    fi
    
    case $exit_code in
        0)
            status="VERIFIED"
            log_success "Model checking passed for $config (${duration}s)"
            ;;
        124)
            status="TIMEOUT"
            log_warn "Model checking timed out for $config (${duration}s)"
            ;;
        *)
            status="FAILED"
            log_error "Model checking failed for $config (${duration}s, exit code: $exit_code)"
            ;;
    esac
    
    # Save metrics
    cat > "$metrics_file" << EOF
{
  "config": "$config",
  "timestamp": "$(date -Iseconds)",
  "status": "$status",
  "exit_code": $exit_code,
  "duration_seconds": $duration,
  "timeout_seconds": $config_timeout,
  "states_explored": $states_explored,
  "states_generated": $states_generated,
  "violations_found": $violations,
  "workers": $WORKERS,
  "timed_out": $([ "$status" = "TIMEOUT" ] && echo "true" || echo "false")
}
EOF
    
    return $exit_code
}

# Run all configurations in parallel
run_parallel_checks() {
    log_info "Running parallel model checking for ${#CONFIGS[@]} configurations"
    log_info "Configurations: ${CONFIGS[*]}"
    log_info "Max parallel jobs: $MAX_PARALLEL"
    log_info "Workers per job: $WORKERS"
    log_info "Timeout per job: $TIMEOUT seconds"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        for config in "${CONFIGS[@]}"; do
            run_single_config "$config"
        done
        return 0
    fi
    
    # Track running jobs
    local pids=()
    local results=()
    local running_configs=()
    
    # Function to wait for a job slot
    wait_for_slot() {
        while [[ ${#pids[@]} -ge $MAX_PARALLEL ]]; do
            local finished_pids=()
            for i in "${!pids[@]}"; do
                local pid="${pids[$i]}"
                if ! kill -0 "$pid" 2>/dev/null; then
                    # Job finished
                    wait "$pid"
                    local exit_code=$?
                    results+=("${running_configs[$i]}:$exit_code")
                    finished_pids+=("$i")
                    
                    local config="${running_configs[$i]}"
                    if [[ $exit_code -eq 0 ]]; then
                        log_debug "Job completed successfully: $config"
                    else
                        log_debug "Job completed with exit code $exit_code: $config"
                        if [[ "$FAIL_FAST" == "true" ]]; then
                            log_error "Fail-fast enabled, stopping remaining jobs"
                            # Kill remaining jobs
                            for remaining_pid in "${pids[@]}"; do
                                if kill -0 "$remaining_pid" 2>/dev/null; then
                                    kill "$remaining_pid" 2>/dev/null || true
                                fi
                            done
                            return 1
                        fi
                    fi
                fi
            done
            
            # Remove finished jobs from tracking arrays
            for i in $(printf '%s\n' "${finished_pids[@]}" | sort -nr); do
                unset pids["$i"]
                unset running_configs["$i"]
            done
            
            # Rebuild arrays to remove gaps
            pids=("${pids[@]}")
            running_configs=("${running_configs[@]}")
            
            if [[ ${#pids[@]} -ge $MAX_PARALLEL ]]; then
                sleep 1
            fi
        done
    }
    
    # Start jobs
    for config in "${CONFIGS[@]}"; do
        wait_for_slot
        
        log_debug "Starting job for configuration: $config"
        run_single_config "$config" &
        local pid=$!
        pids+=("$pid")
        running_configs+=("$config")
    done
    
    # Wait for all remaining jobs
    log_debug "Waiting for remaining jobs to complete..."
    for pid in "${pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            wait "$pid"
            local exit_code=$?
            # Find config for this pid
            for i in "${!pids[@]}"; do
                if [[ "${pids[$i]}" == "$pid" ]]; then
                    results+=("${running_configs[$i]}:$exit_code")
                    break
                fi
            done
        fi
    done
    
    return 0
}

# Aggregate and analyze results
aggregate_results() {
    log_info "Aggregating results..."
    
    local total_configs=${#CONFIGS[@]}
    local successful_configs=0
    local failed_configs=0
    local timeout_configs=0
    local total_states=0
    local total_violations=0
    local total_duration=0
    
    local summary_file="$OUTPUT_DIR/parallel_check_summary.json"
    local report_file="$OUTPUT_DIR/parallel_check_report.md"
    
    # Collect metrics from individual runs
    local config_results=()
    for config in "${CONFIGS[@]}"; do
        local metrics_file="$OUTPUT_DIR/metrics_${config}.json"
        if [[ -f "$metrics_file" ]]; then
            local status
            status=$(jq -r '.status' "$metrics_file" 2>/dev/null || echo "UNKNOWN")
            local duration
            duration=$(jq -r '.duration_seconds' "$metrics_file" 2>/dev/null || echo "0")
            local states
            states=$(jq -r '.states_explored' "$metrics_file" 2>/dev/null || echo "0")
            local violations
            violations=$(jq -r '.violations_found' "$metrics_file" 2>/dev/null || echo "0")
            
            case "$status" in
                VERIFIED)
                    ((successful_configs++))
                    ;;
                TIMEOUT)
                    ((timeout_configs++))
                    ;;
                *)
                    ((failed_configs++))
                    ;;
            esac
            
            total_duration=$((total_duration + duration))
            total_states=$((total_states + states))
            total_violations=$((total_violations + violations))
            
            config_results+=("$config:$status:$duration:$states:$violations")
        else
            log_warn "Metrics file not found for $config"
            ((failed_configs++))
            config_results+=("$config:MISSING:0:0:0")
        fi
    done
    
    # Calculate success rate
    local success_rate=0
    if [[ $total_configs -gt 0 ]]; then
        success_rate=$(echo "scale=1; $successful_configs * 100 / $total_configs" | bc -l 2>/dev/null || echo "0.0")
    fi
    
    # Determine overall status
    local overall_status
    if [[ $successful_configs -eq $total_configs ]]; then
        overall_status="ALL_PASSED"
    elif [[ $successful_configs -gt 0 ]]; then
        overall_status="PARTIAL_SUCCESS"
    else
        overall_status="ALL_FAILED"
    fi
    
    # Generate summary JSON
    if [[ "$DRY_RUN" == "false" ]]; then
        cat > "$summary_file" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "script_version": "$SCRIPT_VERSION",
  "overall_status": "$overall_status",
  "summary": {
    "total_configurations": $total_configs,
    "successful_configurations": $successful_configs,
    "failed_configurations": $failed_configs,
    "timeout_configurations": $timeout_configs,
    "success_rate_percent": $success_rate,
    "total_duration_seconds": $total_duration,
    "total_states_explored": $total_states,
    "total_violations_found": $total_violations
  },
  "configuration_results": [
$(for result in "${config_results[@]}"; do
    IFS=':' read -r config status duration states violations <<< "$result"
    cat << INNER_EOF
    {
      "config": "$config",
      "status": "$status",
      "duration_seconds": $duration,
      "states_explored": $states,
      "violations_found": $violations
    }$([ "$result" != "${config_results[-1]}" ] && echo ",")
INNER_EOF
done)
  ],
  "execution_parameters": {
    "max_parallel_jobs": $MAX_PARALLEL,
    "workers_per_job": $WORKERS,
    "timeout_seconds": $TIMEOUT,
    "fail_fast": $FAIL_FAST,
    "configurations": [$(printf '"%s",' "${CONFIGS[@]}" | sed 's/,$//')]
  }
}
EOF
    fi
    
    # Generate markdown report
    if [[ "$DRY_RUN" == "false" ]]; then
        cat > "$report_file" << EOF
# Parallel Model Checking Report

**Generated**: $(date)  
**Overall Status**: $overall_status  
**Success Rate**: $success_rate%

## Summary

- **Total Configurations**: $total_configs
- **Successful**: $successful_configs
- **Failed**: $failed_configs
- **Timeouts**: $timeout_configs
- **Total Duration**: ${total_duration}s
- **Total States Explored**: $total_states
- **Total Violations Found**: $total_violations

## Configuration Results

| Configuration | Status | Duration | States | Violations |
|---------------|--------|----------|--------|------------|
$(for result in "${config_results[@]}"; do
    IFS=':' read -r config status duration states violations <<< "$result"
    local status_icon
    case "$status" in
        VERIFIED) status_icon="✅" ;;
        TIMEOUT) status_icon="⏱️" ;;
        FAILED) status_icon="❌" ;;
        *) status_icon="❓" ;;
    esac
    echo "| $config | $status_icon $status | ${duration}s | $states | $violations |"
done)

## Execution Parameters

- **Max Parallel Jobs**: $MAX_PARALLEL
- **Workers per Job**: $WORKERS
- **Timeout**: ${TIMEOUT}s
- **Fail Fast**: $FAIL_FAST
- **Configurations**: ${CONFIGS[*]}

## Files Generated

- Summary: \`$summary_file\`
- Individual logs: \`$OUTPUT_DIR/model_*.log\`
- Individual metrics: \`$OUTPUT_DIR/metrics_*.json\`

EOF
    fi
    
    # Print summary to console
    log_info "Parallel model checking completed"
    log_info "Overall status: $overall_status"
    log_info "Success rate: $success_rate% ($successful_configs/$total_configs)"
    
    if [[ $timeout_configs -gt 0 ]]; then
        log_warn "$timeout_configs configuration(s) timed out"
    fi
    
    if [[ $failed_configs -gt 0 ]]; then
        log_error "$failed_configs configuration(s) failed"
    fi
    
    if [[ $total_violations -gt 0 ]]; then
        log_error "Total violations found: $total_violations"
    fi
    
    # Return appropriate exit code
    case "$overall_status" in
        ALL_PASSED)
            return 0
            ;;
        PARTIAL_SUCCESS)
            return 1
            ;;
        ALL_FAILED)
            return 2
            ;;
    esac
}

# Signal handlers
cleanup() {
    log_info "Cleaning up..."
    # Kill any remaining background jobs
    jobs -p | xargs -r kill 2>/dev/null || true
}

interrupt_handler() {
    log_warn "Interrupted by user"
    cleanup
    exit 4
}

# Main execution
main() {
    # Set up signal handlers
    trap interrupt_handler INT TERM
    trap cleanup EXIT
    
    # Parse arguments
    parse_args "$@"
    
    # Setup environment
    setup_environment
    
    # Show configuration
    if [[ "$VERBOSE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        log_info "Configuration:"
        log_info "  Configurations: ${CONFIGS[*]}"
        log_info "  Max parallel: $MAX_PARALLEL"
        log_info "  Workers per job: $WORKERS"
        log_info "  Timeout: ${TIMEOUT}s"
        log_info "  Output directory: $OUTPUT_DIR"
        log_info "  TLA+ tools: $TLA_TOOLS_PATH"
        log_info "  CI mode: $CI_MODE"
        log_info "  Fail fast: $FAIL_FAST"
        log_info "  Dry run: $DRY_RUN"
    fi
    
    # Run parallel checks
    if ! run_parallel_checks; then
        log_error "Parallel execution failed"
        exit 1
    fi
    
    # Aggregate results
    aggregate_results
    local exit_code=$?
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run completed successfully"
        exit 0
    fi
    
    exit $exit_code
}

# Execute main function with all arguments
main "$@"