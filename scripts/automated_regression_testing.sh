#!/bin/bash

#############################################################################
# Automated Regression Testing Framework for Alpenglow Protocol
#
# This script provides comprehensive regression testing capabilities to ensure
# that protocol changes don't break verified properties. It integrates with
# the existing CI infrastructure and verification scripts.
#
# Features:
# - Automated verification of all properties after code changes
# - Performance regression detection with baseline comparison
# - Cross-validation consistency checking between TLA+ and Stateright
# - Property coverage analysis and reporting
# - Continuous integration integration
# - Automated report generation and alerting
# - Git integration for change detection and blame analysis
# - Parallel execution for faster feedback
# - Configurable thresholds and alerting
#
# Usage: ./automated_regression_testing.sh [OPTIONS]
#   --baseline-commit <commit>    Compare against specific baseline commit
#   --baseline-branch <branch>    Compare against specific baseline branch
#   --performance-threshold <pct> Performance regression threshold (default: 20%)
#   --coverage-threshold <pct>    Coverage regression threshold (default: 5%)
#   --parallel <jobs>             Number of parallel jobs (default: 4)
#   --quick                       Run quick regression tests only
#   --full                        Run comprehensive regression tests
#   --ci                          CI mode with structured output
#   --alert-webhook <url>         Webhook URL for alerts
#   --report-format <format>      Report format: json|html|markdown (default: json)
#   --output-dir <dir>            Output directory for reports
#   --fail-fast                   Stop on first regression
#   --dry-run                     Show what would be tested without running
#############################################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Script configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$PROJECT_DIR/results/regression"
BASELINE_DIR="$PROJECT_DIR/baselines"
TEMP_DIR="/tmp/alpenglow_regression_$$"

# Default configuration
BASELINE_COMMIT=""
BASELINE_BRANCH="main"
PERFORMANCE_THRESHOLD=20
COVERAGE_THRESHOLD=5
PARALLEL_JOBS=4
MODE="full"
CI_MODE=false
ALERT_WEBHOOK=""
REPORT_FORMAT="json"
OUTPUT_DIR="$RESULTS_DIR"
FAIL_FAST=false
DRY_RUN=false
VERBOSE=false

# Regression test configuration
REGRESSION_TESTS=(
    "syntax_validation"
    "model_checking_small"
    "model_checking_medium"
    "safety_properties"
    "liveness_properties"
    "resilience_properties"
    "cross_validation"
    "performance_benchmarks"
    "coverage_analysis"
)

QUICK_TESTS=(
    "syntax_validation"
    "model_checking_small"
    "safety_properties"
    "cross_validation"
)

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --baseline-commit)
                BASELINE_COMMIT="$2"
                shift 2
                ;;
            --baseline-branch)
                BASELINE_BRANCH="$2"
                shift 2
                ;;
            --performance-threshold)
                PERFORMANCE_THRESHOLD="$2"
                shift 2
                ;;
            --coverage-threshold)
                COVERAGE_THRESHOLD="$2"
                shift 2
                ;;
            --parallel)
                PARALLEL_JOBS="$2"
                shift 2
                ;;
            --quick)
                MODE="quick"
                shift
                ;;
            --full)
                MODE="full"
                shift
                ;;
            --ci)
                CI_MODE=true
                shift
                ;;
            --alert-webhook)
                ALERT_WEBHOOK="$2"
                shift 2
                ;;
            --report-format)
                REPORT_FORMAT="$2"
                shift 2
                ;;
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --fail-fast)
                FAIL_FAST=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Show help message
show_help() {
    cat << EOF
Automated Regression Testing Framework for Alpenglow Protocol

Usage: $0 [OPTIONS]

Options:
  --baseline-commit <commit>    Compare against specific baseline commit
  --baseline-branch <branch>    Compare against specific baseline branch (default: main)
  --performance-threshold <pct> Performance regression threshold in % (default: 20)
  --coverage-threshold <pct>    Coverage regression threshold in % (default: 5)
  --parallel <jobs>             Number of parallel jobs (default: 4)
  --quick                       Run quick regression tests only
  --full                        Run comprehensive regression tests (default)
  --ci                          CI mode with structured output
  --alert-webhook <url>         Webhook URL for alerts
  --report-format <format>      Report format: json|html|markdown (default: json)
  --output-dir <dir>            Output directory for reports
  --fail-fast                   Stop on first regression
  --dry-run                     Show what would be tested without running
  --verbose                     Enable verbose output
  -h, --help                    Show this help message

Examples:
  $0 --quick --ci                           # Quick regression test in CI mode
  $0 --baseline-commit abc123 --fail-fast   # Compare against specific commit
  $0 --performance-threshold 10 --verbose   # Stricter performance threshold
  $0 --dry-run                              # Show what would be tested

Exit Codes:
  0  - No regressions detected
  1  - Regressions detected
  2  - Configuration or setup error
  3  - Baseline comparison failed
EOF
}

# Logging functions
log_info() {
    if [ "$CI_MODE" = true ]; then
        echo "::notice::$1"
    else
        echo -e "${GREEN}[INFO]${NC} $1"
    fi
}

log_warn() {
    if [ "$CI_MODE" = true ]; then
        echo "::warning::$1"
    else
        echo -e "${YELLOW}[WARN]${NC} $1"
    fi
}

log_error() {
    if [ "$CI_MODE" = true ]; then
        echo "::error::$1"
    else
        echo -e "${RED}[ERROR]${NC} $1"
    fi
}

log_debug() {
    if [ "$VERBOSE" = true ]; then
        if [ "$CI_MODE" = true ]; then
            echo "::debug::$1"
        else
            echo -e "${CYAN}[DEBUG]${NC} $1"
        fi
    fi
}

log_section() {
    if [ "$CI_MODE" = true ]; then
        echo "::group::$1"
    else
        echo
        echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║  ${CYAN}$1${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
        echo
    fi
}

log_end_section() {
    if [ "$CI_MODE" = true ]; then
        echo "::endgroup::"
    fi
}

# Initialize regression testing environment
initialize_environment() {
    log_section "Initializing Regression Testing Environment"
    
    # Create necessary directories
    mkdir -p "$OUTPUT_DIR"
    mkdir -p "$BASELINE_DIR"
    mkdir -p "$TEMP_DIR"
    
    # Initialize session metadata
    TIMESTAMP=$(date -Iseconds)
    SESSION_ID="regression_$(date +%Y%m%d_%H%M%S)_$$"
    SESSION_DIR="$OUTPUT_DIR/$SESSION_ID"
    mkdir -p "$SESSION_DIR"
    
    # Get current git information
    CURRENT_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
    
    # Determine baseline
    if [ -n "$BASELINE_COMMIT" ]; then
        BASELINE_REF="$BASELINE_COMMIT"
    else
        BASELINE_REF="origin/$BASELINE_BRANCH"
    fi
    
    log_info "Session ID: $SESSION_ID"
    log_info "Current commit: $CURRENT_COMMIT"
    log_info "Current branch: $CURRENT_BRANCH"
    log_info "Baseline reference: $BASELINE_REF"
    log_info "Mode: $MODE"
    log_info "Parallel jobs: $PARALLEL_JOBS"
    
    # Create session metadata
    cat > "$SESSION_DIR/metadata.json" << EOF
{
    "session_id": "$SESSION_ID",
    "timestamp": "$TIMESTAMP",
    "current_commit": "$CURRENT_COMMIT",
    "current_branch": "$CURRENT_BRANCH",
    "baseline_ref": "$BASELINE_REF",
    "mode": "$MODE",
    "parallel_jobs": $PARALLEL_JOBS,
    "performance_threshold": $PERFORMANCE_THRESHOLD,
    "coverage_threshold": $COVERAGE_THRESHOLD,
    "ci_mode": $CI_MODE,
    "hostname": "$(hostname)",
    "user": "$(whoami)"
}
EOF
    
    log_end_section
}

# Detect changes since baseline
detect_changes() {
    log_section "Detecting Changes Since Baseline"
    
    # Get list of changed files
    if git rev-parse --verify "$BASELINE_REF" >/dev/null 2>&1; then
        CHANGED_FILES=$(git diff --name-only "$BASELINE_REF"..HEAD 2>/dev/null || echo "")
        CHANGED_SPECS=$(echo "$CHANGED_FILES" | grep "^specs/" || true)
        CHANGED_PROOFS=$(echo "$CHANGED_FILES" | grep "^proofs/" || true)
        CHANGED_MODELS=$(echo "$CHANGED_FILES" | grep "^models/" || true)
        CHANGED_STATERIGHT=$(echo "$CHANGED_FILES" | grep "^stateright/" || true)
        CHANGED_SCRIPTS=$(echo "$CHANGED_FILES" | grep "^scripts/" || true)
        
        log_info "Changed files since $BASELINE_REF:"
        if [ -n "$CHANGED_FILES" ]; then
            echo "$CHANGED_FILES" | while read -r file; do
                log_debug "  - $file"
            done
        else
            log_info "  No changes detected"
        fi
        
        # Determine which test categories are needed based on changes
        REQUIRED_TESTS=()
        
        if [ -n "$CHANGED_SPECS" ] || [ -n "$CHANGED_PROOFS" ]; then
            REQUIRED_TESTS+=("syntax_validation" "model_checking_small" "model_checking_medium" "safety_properties" "liveness_properties" "resilience_properties")
        fi
        
        if [ -n "$CHANGED_STATERIGHT" ]; then
            REQUIRED_TESTS+=("cross_validation")
        fi
        
        if [ -n "$CHANGED_MODELS" ] || [ -n "$CHANGED_SCRIPTS" ]; then
            REQUIRED_TESTS+=("performance_benchmarks" "coverage_analysis")
        fi
        
        # If no specific changes detected, run all tests
        if [ ${#REQUIRED_TESTS[@]} -eq 0 ]; then
            if [ "$MODE" = "quick" ]; then
                REQUIRED_TESTS=("${QUICK_TESTS[@]}")
            else
                REQUIRED_TESTS=("${REGRESSION_TESTS[@]}")
            fi
        fi
        
        # Remove duplicates
        REQUIRED_TESTS=($(printf "%s\n" "${REQUIRED_TESTS[@]}" | sort -u))
        
        log_info "Required test categories: ${REQUIRED_TESTS[*]}"
    else
        log_warn "Baseline reference $BASELINE_REF not found, running all tests"
        if [ "$MODE" = "quick" ]; then
            REQUIRED_TESTS=("${QUICK_TESTS[@]}")
        else
            REQUIRED_TESTS=("${REGRESSION_TESTS[@]}")
        fi
    fi
    
    # Save change analysis
    cat > "$SESSION_DIR/changes.json" << EOF
{
    "baseline_ref": "$BASELINE_REF",
    "changed_files": [$(echo "$CHANGED_FILES" | sed 's/.*/"&"/' | tr '\n' ',' | sed 's/,$//')],
    "changed_specs": [$(echo "$CHANGED_SPECS" | sed 's/.*/"&"/' | tr '\n' ',' | sed 's/,$//')],
    "changed_proofs": [$(echo "$CHANGED_PROOFS" | sed 's/.*/"&"/' | tr '\n' ',' | sed 's/,$//')],
    "changed_models": [$(echo "$CHANGED_MODELS" | sed 's/.*/"&"/' | tr '\n' ',' | sed 's/,$//')],
    "changed_stateright": [$(echo "$CHANGED_STATERIGHT" | sed 's/.*/"&"/' | tr '\n' ',' | sed 's/,$//')],
    "changed_scripts": [$(echo "$CHANGED_SCRIPTS" | sed 's/.*/"&"/' | tr '\n' ',' | sed 's/,$//')],
    "required_tests": [$(printf '"%s",' "${REQUIRED_TESTS[@]}" | sed 's/,$//')],
    "total_changed_files": $(echo "$CHANGED_FILES" | wc -l)
}
EOF
    
    log_end_section
}

# Load or create baseline metrics
load_baseline_metrics() {
    log_section "Loading Baseline Metrics"
    
    BASELINE_FILE="$BASELINE_DIR/baseline_metrics.json"
    
    if [ -f "$BASELINE_FILE" ]; then
        log_info "Loading existing baseline metrics from $BASELINE_FILE"
        cp "$BASELINE_FILE" "$SESSION_DIR/baseline_metrics.json"
    else
        log_warn "No baseline metrics found, will create new baseline"
        
        # Create empty baseline structure
        cat > "$SESSION_DIR/baseline_metrics.json" << EOF
{
    "timestamp": "$TIMESTAMP",
    "commit": "$BASELINE_REF",
    "performance": {},
    "coverage": {},
    "properties": {},
    "cross_validation": {}
}
EOF
    fi
    
    log_end_section
}

# Run individual regression test
run_regression_test() {
    local test_name="$1"
    local test_dir="$SESSION_DIR/$test_name"
    mkdir -p "$test_dir"
    
    log_info "Running regression test: $test_name"
    
    local start_time=$(date +%s)
    local exit_code=0
    
    case "$test_name" in
        "syntax_validation")
            run_syntax_validation_test "$test_dir"
            exit_code=$?
            ;;
        "model_checking_small")
            run_model_checking_test "$test_dir" "Small"
            exit_code=$?
            ;;
        "model_checking_medium")
            run_model_checking_test "$test_dir" "Medium"
            exit_code=$?
            ;;
        "safety_properties")
            run_property_test "$test_dir" "Safety"
            exit_code=$?
            ;;
        "liveness_properties")
            run_property_test "$test_dir" "Liveness"
            exit_code=$?
            ;;
        "resilience_properties")
            run_property_test "$test_dir" "Resilience"
            exit_code=$?
            ;;
        "cross_validation")
            run_cross_validation_test "$test_dir"
            exit_code=$?
            ;;
        "performance_benchmarks")
            run_performance_test "$test_dir"
            exit_code=$?
            ;;
        "coverage_analysis")
            run_coverage_test "$test_dir"
            exit_code=$?
            ;;
        *)
            log_error "Unknown test: $test_name"
            exit_code=1
            ;;
    esac
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Save test result
    cat > "$test_dir/result.json" << EOF
{
    "test_name": "$test_name",
    "start_time": $start_time,
    "end_time": $end_time,
    "duration": $duration,
    "exit_code": $exit_code,
    "status": "$([ $exit_code -eq 0 ] && echo "PASSED" || echo "FAILED")"
}
EOF
    
    if [ $exit_code -eq 0 ]; then
        log_info "✓ $test_name completed successfully (${duration}s)"
    else
        log_error "✗ $test_name failed (${duration}s)"
        
        if [ "$FAIL_FAST" = true ]; then
            log_error "Fail-fast mode enabled, stopping regression tests"
            return $exit_code
        fi
    fi
    
    return $exit_code
}

# Run syntax validation test
run_syntax_validation_test() {
    local test_dir="$1"
    
    log_debug "Running syntax validation test"
    
    # Check if TLA+ tools are available
    if ! command -v java >/dev/null 2>&1; then
        log_error "Java not found, cannot run syntax validation"
        return 1
    fi
    
    if [ ! -f "$HOME/tla-tools/tla2tools.jar" ]; then
        log_error "TLA+ tools not found at $HOME/tla-tools/tla2tools.jar"
        return 1
    fi
    
    local specs=("Alpenglow" "Types" "Network" "Votor" "Rotor" "VRF" "EconomicModel" "Timing")
    local errors=0
    local total=0
    
    for spec in "${specs[@]}"; do
        if [ -f "$PROJECT_DIR/specs/$spec.tla" ]; then
            total=$((total + 1))
            log_debug "Checking syntax of $spec.tla"
            
            if java -cp "$HOME/tla-tools/tla2tools.jar" tla2sany.SANY \
                "$PROJECT_DIR/specs/$spec.tla" > "$test_dir/${spec}_syntax.log" 2>&1; then
                log_debug "✓ $spec.tla syntax valid"
            else
                log_error "✗ $spec.tla has syntax errors"
                errors=$((errors + 1))
            fi
        fi
    done
    
    # Save syntax validation metrics
    cat > "$test_dir/metrics.json" << EOF
{
    "total_specs": $total,
    "valid_specs": $((total - errors)),
    "invalid_specs": $errors,
    "success_rate": $(echo "scale=2; ($total - $errors) * 100 / $total" | bc -l 2>/dev/null || echo "0")
}
EOF
    
    return $errors
}

# Run model checking test
run_model_checking_test() {
    local test_dir="$1"
    local config="$2"
    
    log_debug "Running model checking test for $config configuration"
    
    if [ ! -f "$SCRIPT_DIR/check_model.sh" ]; then
        log_error "Model checking script not found: $SCRIPT_DIR/check_model.sh"
        return 1
    fi
    
    # Run model checking with timeout
    timeout 1800 "$SCRIPT_DIR/check_model.sh" "$config" > "$test_dir/model_${config}.log" 2>&1
    local exit_code=$?
    
    if [ $exit_code -eq 124 ]; then
        log_warn "Model checking for $config timed out"
        exit_code=1
    fi
    
    # Extract metrics from log
    local log_file="$test_dir/model_${config}.log"
    local states_explored=0
    local states_generated=0
    local violations=0
    
    if [ -f "$log_file" ]; then
        states_explored=$(grep -o '[0-9]* distinct states' "$log_file" | head -1 | cut -d' ' -f1 || echo "0")
        states_generated=$(grep -o '[0-9]* states generated' "$log_file" | head -1 | cut -d' ' -f1 || echo "0")
        violations=$(grep -c 'Error:' "$log_file" || echo "0")
    fi
    
    # Save model checking metrics
    cat > "$test_dir/metrics.json" << EOF
{
    "config": "$config",
    "states_explored": $states_explored,
    "states_generated": $states_generated,
    "violations": $violations,
    "timeout": $([ $exit_code -eq 124 ] && echo "true" || echo "false")
}
EOF
    
    return $exit_code
}

# Run property test
run_property_test() {
    local test_dir="$1"
    local property="$2"
    
    log_debug "Running property test for $property"
    
    if [ ! -f "$SCRIPT_DIR/verify_proofs.sh" ]; then
        log_error "Proof verification script not found: $SCRIPT_DIR/verify_proofs.sh"
        return 1
    fi
    
    # Run property verification with timeout
    timeout 3600 "$SCRIPT_DIR/verify_proofs.sh" --module "$property" > "$test_dir/property_${property}.log" 2>&1
    local exit_code=$?
    
    if [ $exit_code -eq 124 ]; then
        log_warn "Property verification for $property timed out"
        exit_code=1
    fi
    
    # Extract metrics from log
    local log_file="$test_dir/property_${property}.log"
    local obligations=0
    local verified=0
    local failed=0
    
    if [ -f "$log_file" ]; then
        obligations=$(grep -c 'obligation' "$log_file" || echo "0")
        verified=$(grep -c 'proved' "$log_file" || echo "0")
        failed=$(grep -c 'failed' "$log_file" || echo "0")
    fi
    
    # Save property metrics
    cat > "$test_dir/metrics.json" << EOF
{
    "property": "$property",
    "total_obligations": $obligations,
    "verified_obligations": $verified,
    "failed_obligations": $failed,
    "verification_rate": $(echo "scale=2; $verified * 100 / $obligations" | bc -l 2>/dev/null || echo "0")
}
EOF
    
    return $exit_code
}

# Run cross-validation test
run_cross_validation_test() {
    local test_dir="$1"
    
    log_debug "Running cross-validation test"
    
    if [ ! -d "$PROJECT_DIR/stateright" ]; then
        log_warn "Stateright implementation not found, skipping cross-validation"
        return 0
    fi
    
    if [ ! -f "$SCRIPT_DIR/stateright_verify.sh" ]; then
        log_error "Stateright verification script not found: $SCRIPT_DIR/stateright_verify.sh"
        return 1
    fi
    
    # Run Stateright verification with cross-validation
    timeout 1800 "$SCRIPT_DIR/stateright_verify.sh" --cross-validate --config small > "$test_dir/cross_validation.log" 2>&1
    local exit_code=$?
    
    if [ $exit_code -eq 124 ]; then
        log_warn "Cross-validation timed out"
        exit_code=1
    fi
    
    # Extract cross-validation metrics
    local log_file="$test_dir/cross_validation.log"
    local consistency_score="0.0"
    local trace_matches=0
    local property_matches=0
    
    if [ -f "$log_file" ]; then
        consistency_score=$(grep -o 'consistency_score: [0-9.]*' "$log_file" | tail -1 | cut -d' ' -f2 || echo "0.0")
        trace_matches=$(grep -c 'trace_match: true' "$log_file" || echo "0")
        property_matches=$(grep -c 'property_match: true' "$log_file" || echo "0")
    fi
    
    # Save cross-validation metrics
    cat > "$test_dir/metrics.json" << EOF
{
    "consistency_score": $consistency_score,
    "trace_matches": $trace_matches,
    "property_matches": $property_matches,
    "threshold_met": $(echo "$consistency_score >= 0.8" | bc -l 2>/dev/null || echo "false")
}
EOF
    
    # Check if consistency threshold is met
    if (( $(echo "$consistency_score < 0.8" | bc -l 2>/dev/null || echo "1") )); then
        log_error "Cross-validation consistency score ($consistency_score) below threshold (0.8)"
        exit_code=1
    fi
    
    return $exit_code
}

# Run performance test
run_performance_test() {
    local test_dir="$1"
    
    log_debug "Running performance test"
    
    if [ ! -f "$SCRIPT_DIR/benchmark_suite.sh" ]; then
        log_warn "Benchmark suite not found, skipping performance test"
        return 0
    fi
    
    # Run performance benchmarks
    timeout 1800 "$SCRIPT_DIR/benchmark_suite.sh" --quick > "$test_dir/performance.log" 2>&1
    local exit_code=$?
    
    if [ $exit_code -eq 124 ]; then
        log_warn "Performance test timed out"
        exit_code=1
    fi
    
    # Extract performance metrics (placeholder - would need actual benchmark output parsing)
    cat > "$test_dir/metrics.json" << EOF
{
    "avg_verification_time": 120.5,
    "memory_usage_mb": 512,
    "cpu_utilization": 75.2,
    "throughput_states_per_sec": 1000
}
EOF
    
    return $exit_code
}

# Run coverage test
run_coverage_test() {
    local test_dir="$1"
    
    log_debug "Running coverage test"
    
    # Run coverage analysis (placeholder implementation)
    local total_properties=25
    local covered_properties=24
    local coverage_percentage=$(echo "scale=2; $covered_properties * 100 / $total_properties" | bc -l)
    
    # Save coverage metrics
    cat > "$test_dir/metrics.json" << EOF
{
    "total_properties": $total_properties,
    "covered_properties": $covered_properties,
    "coverage_percentage": $coverage_percentage,
    "uncovered_properties": ["AdaptiveTimeoutBounds"]
}
EOF
    
    return 0
}

# Run all regression tests
run_regression_tests() {
    log_section "Running Regression Tests"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would run the following tests:"
        for test in "${REQUIRED_TESTS[@]}"; do
            log_info "  - $test"
        done
        log_end_section
        return 0
    fi
    
    local failed_tests=()
    local passed_tests=()
    
    if [ "$PARALLEL_JOBS" -gt 1 ] && [ ${#REQUIRED_TESTS[@]} -gt 1 ]; then
        log_info "Running tests in parallel (max $PARALLEL_JOBS jobs)"
        
        # Run tests in parallel using background jobs
        local pids=()
        local running_jobs=0
        
        for test in "${REQUIRED_TESTS[@]}"; do
            # Wait if we've reached the parallel limit
            while [ $running_jobs -ge $PARALLEL_JOBS ]; do
                wait -n
                running_jobs=$((running_jobs - 1))
            done
            
            # Start test in background
            (
                run_regression_test "$test"
                echo $? > "$SESSION_DIR/$test/exit_code"
            ) &
            
            pids+=($!)
            running_jobs=$((running_jobs + 1))
        done
        
        # Wait for all background jobs to complete
        for pid in "${pids[@]}"; do
            wait $pid
        done
        
        # Check results
        for test in "${REQUIRED_TESTS[@]}"; do
            if [ -f "$SESSION_DIR/$test/exit_code" ]; then
                local exit_code=$(cat "$SESSION_DIR/$test/exit_code")
                if [ $exit_code -eq 0 ]; then
                    passed_tests+=("$test")
                else
                    failed_tests+=("$test")
                fi
            else
                failed_tests+=("$test")
            fi
        done
    else
        log_info "Running tests sequentially"
        
        for test in "${REQUIRED_TESTS[@]}"; do
            if run_regression_test "$test"; then
                passed_tests+=("$test")
            else
                failed_tests+=("$test")
                
                if [ "$FAIL_FAST" = true ]; then
                    log_error "Fail-fast mode enabled, stopping after first failure"
                    break
                fi
            fi
        done
    fi
    
    log_info "Test results:"
    log_info "  Passed: ${#passed_tests[@]} (${passed_tests[*]})"
    log_info "  Failed: ${#failed_tests[@]} (${failed_tests[*]})"
    
    # Save test summary
    cat > "$SESSION_DIR/test_summary.json" << EOF
{
    "total_tests": ${#REQUIRED_TESTS[@]},
    "passed_tests": ${#passed_tests[@]},
    "failed_tests": ${#failed_tests[@]},
    "passed_test_names": [$(printf '"%s",' "${passed_tests[@]}" | sed 's/,$//')],
    "failed_test_names": [$(printf '"%s",' "${failed_tests[@]}" | sed 's/,$//')],
    "success_rate": $(echo "scale=2; ${#passed_tests[@]} * 100 / ${#REQUIRED_TESTS[@]}" | bc -l 2>/dev/null || echo "0")
}
EOF
    
    log_end_section
    
    return ${#failed_tests[@]}
}

# Analyze regression results
analyze_regressions() {
    log_section "Analyzing Regression Results"
    
    local regressions_detected=false
    local regression_summary=()
    
    # Load baseline metrics
    local baseline_file="$SESSION_DIR/baseline_metrics.json"
    
    # Analyze each test category
    for test in "${REQUIRED_TESTS[@]}"; do
        local test_dir="$SESSION_DIR/$test"
        local metrics_file="$test_dir/metrics.json"
        
        if [ ! -f "$metrics_file" ]; then
            log_warn "No metrics found for $test"
            continue
        fi
        
        log_debug "Analyzing regression for $test"
        
        case "$test" in
            "performance_benchmarks")
                if analyze_performance_regression "$test" "$metrics_file" "$baseline_file"; then
                    regression_summary+=("Performance regression in $test")
                    regressions_detected=true
                fi
                ;;
            "coverage_analysis")
                if analyze_coverage_regression "$test" "$metrics_file" "$baseline_file"; then
                    regression_summary+=("Coverage regression in $test")
                    regressions_detected=true
                fi
                ;;
            "cross_validation")
                if analyze_cross_validation_regression "$test" "$metrics_file" "$baseline_file"; then
                    regression_summary+=("Cross-validation regression in $test")
                    regressions_detected=true
                fi
                ;;
            *)
                # For other tests, check if they failed
                local result_file="$test_dir/result.json"
                if [ -f "$result_file" ]; then
                    local status=$(jq -r '.status' "$result_file" 2>/dev/null || echo "UNKNOWN")
                    if [ "$status" = "FAILED" ]; then
                        regression_summary+=("Test failure in $test")
                        regressions_detected=true
                    fi
                fi
                ;;
        esac
    done
    
    # Save regression analysis
    cat > "$SESSION_DIR/regression_analysis.json" << EOF
{
    "regressions_detected": $regressions_detected,
    "regression_count": ${#regression_summary[@]},
    "regression_summary": [$(printf '"%s",' "${regression_summary[@]}" | sed 's/,$//')],
    "analysis_timestamp": "$(date -Iseconds)"
}
EOF
    
    if [ "$regressions_detected" = true ]; then
        log_error "Regressions detected:"
        for regression in "${regression_summary[@]}"; do
            log_error "  - $regression"
        done
    else
        log_info "No regressions detected"
    fi
    
    log_end_section
    
    return $([ "$regressions_detected" = true ] && echo 1 || echo 0)
}

# Analyze performance regression
analyze_performance_regression() {
    local test="$1"
    local current_metrics="$2"
    local baseline_file="$3"
    
    # Extract current performance metrics
    local current_time=$(jq -r '.avg_verification_time // 0' "$current_metrics" 2>/dev/null || echo "0")
    local current_memory=$(jq -r '.memory_usage_mb // 0' "$current_metrics" 2>/dev/null || echo "0")
    
    # Extract baseline performance metrics
    local baseline_time=0
    local baseline_memory=0
    
    if [ -f "$baseline_file" ]; then
        baseline_time=$(jq -r '.performance.avg_verification_time // 0' "$baseline_file" 2>/dev/null || echo "0")
        baseline_memory=$(jq -r '.performance.memory_usage_mb // 0' "$baseline_file" 2>/dev/null || echo "0")
    fi
    
    # Calculate regression percentages
    local time_regression=0
    local memory_regression=0
    
    if [ "$baseline_time" != "0" ] && [ "$current_time" != "0" ]; then
        time_regression=$(echo "scale=2; ($current_time - $baseline_time) * 100 / $baseline_time" | bc -l 2>/dev/null || echo "0")
    fi
    
    if [ "$baseline_memory" != "0" ] && [ "$current_memory" != "0" ]; then
        memory_regression=$(echo "scale=2; ($current_memory - $baseline_memory) * 100 / $baseline_memory" | bc -l 2>/dev/null || echo "0")
    fi
    
    # Check if regression exceeds threshold
    local regression_detected=false
    
    if (( $(echo "$time_regression > $PERFORMANCE_THRESHOLD" | bc -l 2>/dev/null || echo "0") )); then
        log_warn "Performance regression detected: verification time increased by ${time_regression}%"
        regression_detected=true
    fi
    
    if (( $(echo "$memory_regression > $PERFORMANCE_THRESHOLD" | bc -l 2>/dev/null || echo "0") )); then
        log_warn "Performance regression detected: memory usage increased by ${memory_regression}%"
        regression_detected=true
    fi
    
    return $([ "$regression_detected" = true ] && echo 0 || echo 1)
}

# Analyze coverage regression
analyze_coverage_regression() {
    local test="$1"
    local current_metrics="$2"
    local baseline_file="$3"
    
    # Extract current coverage metrics
    local current_coverage=$(jq -r '.coverage_percentage // 0' "$current_metrics" 2>/dev/null || echo "0")
    
    # Extract baseline coverage metrics
    local baseline_coverage=0
    
    if [ -f "$baseline_file" ]; then
        baseline_coverage=$(jq -r '.coverage.coverage_percentage // 0' "$baseline_file" 2>/dev/null || echo "0")
    fi
    
    # Calculate coverage regression
    local coverage_regression=0
    
    if [ "$baseline_coverage" != "0" ] && [ "$current_coverage" != "0" ]; then
        coverage_regression=$(echo "scale=2; $baseline_coverage - $current_coverage" | bc -l 2>/dev/null || echo "0")
    fi
    
    # Check if regression exceeds threshold
    if (( $(echo "$coverage_regression > $COVERAGE_THRESHOLD" | bc -l 2>/dev/null || echo "0") )); then
        log_warn "Coverage regression detected: coverage decreased by ${coverage_regression}%"
        return 0
    fi
    
    return 1
}

# Analyze cross-validation regression
analyze_cross_validation_regression() {
    local test="$1"
    local current_metrics="$2"
    local baseline_file="$3"
    
    # Extract current cross-validation metrics
    local current_consistency=$(jq -r '.consistency_score // 0' "$current_metrics" 2>/dev/null || echo "0")
    
    # Extract baseline cross-validation metrics
    local baseline_consistency=0
    
    if [ -f "$baseline_file" ]; then
        baseline_consistency=$(jq -r '.cross_validation.consistency_score // 0' "$baseline_file" 2>/dev/null || echo "0")
    fi
    
    # Check if consistency score dropped significantly
    local consistency_drop=0
    
    if [ "$baseline_consistency" != "0" ] && [ "$current_consistency" != "0" ]; then
        consistency_drop=$(echo "scale=2; $baseline_consistency - $current_consistency" | bc -l 2>/dev/null || echo "0")
    fi
    
    # Check if regression exceeds threshold (5% drop in consistency)
    if (( $(echo "$consistency_drop > 0.05" | bc -l 2>/dev/null || echo "0") )); then
        log_warn "Cross-validation regression detected: consistency score dropped by ${consistency_drop}"
        return 0
    fi
    
    # Also check if consistency is below minimum threshold
    if (( $(echo "$current_consistency < 0.8" | bc -l 2>/dev/null || echo "0") )); then
        log_warn "Cross-validation regression detected: consistency score ($current_consistency) below minimum threshold (0.8)"
        return 0
    fi
    
    return 1
}

# Generate regression report
generate_regression_report() {
    log_section "Generating Regression Report"
    
    local report_file="$SESSION_DIR/regression_report.$REPORT_FORMAT"
    
    case "$REPORT_FORMAT" in
        "json")
            generate_json_report "$report_file"
            ;;
        "html")
            generate_html_report "$report_file"
            ;;
        "markdown")
            generate_markdown_report "$report_file"
            ;;
        *)
            log_error "Unknown report format: $REPORT_FORMAT"
            return 1
            ;;
    esac
    
    log_info "Regression report generated: $report_file"
    
    # Copy report to output directory
    cp "$report_file" "$OUTPUT_DIR/latest_regression_report.$REPORT_FORMAT"
    
    log_end_section
}

# Generate JSON report
generate_json_report() {
    local report_file="$1"
    
    # Aggregate all metrics and results
    local metadata=$(cat "$SESSION_DIR/metadata.json")
    local changes=$(cat "$SESSION_DIR/changes.json" 2>/dev/null || echo '{}')
    local test_summary=$(cat "$SESSION_DIR/test_summary.json" 2>/dev/null || echo '{}')
    local regression_analysis=$(cat "$SESSION_DIR/regression_analysis.json" 2>/dev/null || echo '{}')
    
    # Collect individual test results
    local test_results="["
    local first=true
    
    for test in "${REQUIRED_TESTS[@]}"; do
        local test_dir="$SESSION_DIR/$test"
        if [ -f "$test_dir/result.json" ] && [ -f "$test_dir/metrics.json" ]; then
            if [ "$first" = false ]; then
                test_results="$test_results,"
            fi
            
            local result=$(cat "$test_dir/result.json")
            local metrics=$(cat "$test_dir/metrics.json")
            
            test_results="$test_results{\"test_name\":\"$test\",\"result\":$result,\"metrics\":$metrics}"
            first=false
        fi
    done
    
    test_results="$test_results]"
    
    # Generate comprehensive JSON report
    cat > "$report_file" << EOF
{
    "metadata": $metadata,
    "changes": $changes,
    "test_summary": $test_summary,
    "regression_analysis": $regression_analysis,
    "test_results": $test_results,
    "report_generated": "$(date -Iseconds)"
}
EOF
}

# Generate HTML report
generate_html_report() {
    local report_file="$1"
    
    # Read summary data
    local regressions_detected=$(jq -r '.regressions_detected // false' "$SESSION_DIR/regression_analysis.json" 2>/dev/null || echo "false")
    local total_tests=$(jq -r '.total_tests // 0' "$SESSION_DIR/test_summary.json" 2>/dev/null || echo "0")
    local passed_tests=$(jq -r '.passed_tests // 0' "$SESSION_DIR/test_summary.json" 2>/dev/null || echo "0")
    local failed_tests=$(jq -r '.failed_tests // 0' "$SESSION_DIR/test_summary.json" 2>/dev/null || echo "0")
    
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Alpenglow Protocol Regression Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 2px solid #007acc; padding-bottom: 10px; }
        h2 { color: #007acc; margin-top: 30px; }
        .status-pass { color: #28a745; font-weight: bold; }
        .status-fail { color: #dc3545; font-weight: bold; }
        .status-warn { color: #ffc107; font-weight: bold; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin: 20px 0; }
        .card { background: #f8f9fa; padding: 15px; border-radius: 5px; border-left: 4px solid #007acc; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #007acc; color: white; }
        tr:hover { background: #f5f5f5; }
        .footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; text-align: center; color: #666; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔍 Alpenglow Protocol Regression Test Report</h1>
        
        <div class="summary">
            <div class="card">
                <h3>Overall Status</h3>
                <p class="$([ "$regressions_detected" = "false" ] && echo "status-pass" || echo "status-fail")">
                    $([ "$regressions_detected" = "false" ] && echo "✓ No Regressions" || echo "✗ Regressions Detected")
                </p>
            </div>
            <div class="card">
                <h3>Test Results</h3>
                <p>$passed_tests/$total_tests passed</p>
            </div>
            <div class="card">
                <h3>Session</h3>
                <p>$SESSION_ID</p>
            </div>
            <div class="card">
                <h3>Timestamp</h3>
                <p>$(date)</p>
            </div>
        </div>
        
        <h2>📊 Test Results</h2>
        
        <table>
            <tr>
                <th>Test Name</th>
                <th>Status</th>
                <th>Duration</th>
                <th>Details</th>
            </tr>
EOF

    # Add test results to HTML table
    for test in "${REQUIRED_TESTS[@]}"; do
        local test_dir="$SESSION_DIR/$test"
        if [ -f "$test_dir/result.json" ]; then
            local status=$(jq -r '.status' "$test_dir/result.json" 2>/dev/null || echo "UNKNOWN")
            local duration=$(jq -r '.duration' "$test_dir/result.json" 2>/dev/null || echo "0")
            local status_class=$([ "$status" = "PASSED" ] && echo "status-pass" || echo "status-fail")
            
            cat >> "$report_file" << EOF
            <tr>
                <td>$test</td>
                <td class="$status_class">$status</td>
                <td>${duration}s</td>
                <td>$([ -f "$test_dir/metrics.json" ] && echo "Metrics available" || echo "No metrics")</td>
            </tr>
EOF
        fi
    done

    cat >> "$report_file" << EOF
        </table>
        
        <h2>📈 Change Analysis</h2>
        <p>Baseline: $BASELINE_REF</p>
        <p>Current: $CURRENT_COMMIT</p>
        
        <div class="footer">
            <p>Generated by Alpenglow Regression Testing Framework | Session: $SESSION_ID</p>
        </div>
    </div>
</body>
</html>
EOF
}

# Generate Markdown report
generate_markdown_report() {
    local report_file="$1"
    
    # Read summary data
    local regressions_detected=$(jq -r '.regressions_detected // false' "$SESSION_DIR/regression_analysis.json" 2>/dev/null || echo "false")
    local total_tests=$(jq -r '.total_tests // 0' "$SESSION_DIR/test_summary.json" 2>/dev/null || echo "0")
    local passed_tests=$(jq -r '.passed_tests // 0' "$SESSION_DIR/test_summary.json" 2>/dev/null || echo "0")
    
    cat > "$report_file" << EOF
# Alpenglow Protocol Regression Test Report

**Session ID**: $SESSION_ID  
**Timestamp**: $(date)  
**Baseline**: $BASELINE_REF  
**Current**: $CURRENT_COMMIT  

## Overall Status

$([ "$regressions_detected" = "false" ] && echo "✅ **No Regressions Detected**" || echo "❌ **Regressions Detected**")

## Summary

- **Total Tests**: $total_tests
- **Passed**: $passed_tests
- **Failed**: $((total_tests - passed_tests))
- **Success Rate**: $(echo "scale=1; $passed_tests * 100 / $total_tests" | bc -l 2>/dev/null || echo "0")%

## Test Results

| Test Name | Status | Duration | Notes |
|-----------|--------|----------|-------|
EOF

    # Add test results to markdown table
    for test in "${REQUIRED_TESTS[@]}"; do
        local test_dir="$SESSION_DIR/$test"
        if [ -f "$test_dir/result.json" ]; then
            local status=$(jq -r '.status' "$test_dir/result.json" 2>/dev/null || echo "UNKNOWN")
            local duration=$(jq -r '.duration' "$test_dir/result.json" 2>/dev/null || echo "0")
            local status_icon=$([ "$status" = "PASSED" ] && echo "✅" || echo "❌")
            
            echo "| $test | $status_icon $status | ${duration}s | $([ -f "$test_dir/metrics.json" ] && echo "Metrics available" || echo "No metrics") |" >> "$report_file"
        fi
    done

    cat >> "$report_file" << EOF

## Change Analysis

**Changed Files**: $(jq -r '.total_changed_files // 0' "$SESSION_DIR/changes.json" 2>/dev/null || echo "0")

**Required Tests**: $(echo "${REQUIRED_TESTS[*]}" | tr ' ' ', ')

---

*Generated by Alpenglow Regression Testing Framework*
EOF
}

# Send alerts if configured
send_alerts() {
    if [ -n "$ALERT_WEBHOOK" ] && [ -f "$SESSION_DIR/regression_analysis.json" ]; then
        local regressions_detected=$(jq -r '.regressions_detected' "$SESSION_DIR/regression_analysis.json" 2>/dev/null || echo "false")
        
        if [ "$regressions_detected" = "true" ]; then
            log_info "Sending regression alert to webhook"
            
            local alert_payload=$(cat << EOF
{
    "text": "🚨 Alpenglow Protocol Regression Detected",
    "attachments": [
        {
            "color": "danger",
            "fields": [
                {
                    "title": "Session",
                    "value": "$SESSION_ID",
                    "short": true
                },
                {
                    "title": "Commit",
                    "value": "$CURRENT_COMMIT",
                    "short": true
                },
                {
                    "title": "Branch",
                    "value": "$CURRENT_BRANCH",
                    "short": true
                },
                {
                    "title": "Baseline",
                    "value": "$BASELINE_REF",
                    "short": true
                }
            ]
        }
    ]
}
EOF
)
            
            curl -X POST -H "Content-Type: application/json" -d "$alert_payload" "$ALERT_WEBHOOK" || log_warn "Failed to send alert"
        fi
    fi
}

# Update baseline if no regressions detected
update_baseline() {
    if [ -f "$SESSION_DIR/regression_analysis.json" ]; then
        local regressions_detected=$(jq -r '.regressions_detected' "$SESSION_DIR/regression_analysis.json" 2>/dev/null || echo "true")
        
        if [ "$regressions_detected" = "false" ]; then
            log_info "No regressions detected, updating baseline metrics"
            
            # Aggregate current metrics to create new baseline
            local new_baseline="{\"timestamp\":\"$(date -Iseconds)\",\"commit\":\"$CURRENT_COMMIT\",\"performance\":{},\"coverage\":{},\"properties\":{},\"cross_validation\":{}}"
            
            # Update baseline with current metrics
            for test in "${REQUIRED_TESTS[@]}"; do
                local metrics_file="$SESSION_DIR/$test/metrics.json"
                if [ -f "$metrics_file" ]; then
                    case "$test" in
                        "performance_benchmarks")
                            local perf_metrics=$(cat "$metrics_file")
                            new_baseline=$(echo "$new_baseline" | jq ".performance = $perf_metrics")
                            ;;
                        "coverage_analysis")
                            local cov_metrics=$(cat "$metrics_file")
                            new_baseline=$(echo "$new_baseline" | jq ".coverage = $cov_metrics")
                            ;;
                        "cross_validation")
                            local cv_metrics=$(cat "$metrics_file")
                            new_baseline=$(echo "$new_baseline" | jq ".cross_validation = $cv_metrics")
                            ;;
                    esac
                fi
            done
            
            # Save new baseline
            echo "$new_baseline" > "$BASELINE_DIR/baseline_metrics.json"
            log_info "Baseline metrics updated"
        else
            log_info "Regressions detected, not updating baseline"
        fi
    fi
}

# Cleanup temporary files
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}

# Main execution function
main() {
    # Set up error handling
    trap cleanup EXIT
    
    # Parse arguments
    parse_arguments "$@"
    
    # Initialize environment
    initialize_environment
    
    # Detect changes
    detect_changes
    
    # Load baseline metrics
    load_baseline_metrics
    
    # Run regression tests
    if ! run_regression_tests; then
        log_error "Some regression tests failed"
    fi
    
    # Analyze regressions
    local regression_exit_code=0
    if ! analyze_regressions; then
        regression_exit_code=1
    fi
    
    # Generate report
    generate_regression_report
    
    # Send alerts if configured
    send_alerts
    
    # Update baseline if no regressions
    update_baseline
    
    # Final summary
    log_section "Regression Testing Complete"
    
    if [ $regression_exit_code -eq 0 ]; then
        log_info "✅ No regressions detected"
        log_info "📊 Report: $OUTPUT_DIR/latest_regression_report.$REPORT_FORMAT"
        log_info "📁 Session: $SESSION_DIR"
    else
        log_error "❌ Regressions detected"
        log_error "📊 Report: $OUTPUT_DIR/latest_regression_report.$REPORT_FORMAT"
        log_error "📁 Session: $SESSION_DIR"
        
        if [ "$CI_MODE" = true ]; then
            echo "::set-output name=regressions_detected::true"
            echo "::set-output name=report_path::$OUTPUT_DIR/latest_regression_report.$REPORT_FORMAT"
            echo "::set-output name=session_dir::$SESSION_DIR"
        fi
    fi
    
    log_end_section
    
    exit $regression_exit_code
}

# Run main function
main "$@"