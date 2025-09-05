#!/bin/bash

# verify_whitepaper_theorems.sh
# Comprehensive verification script for Alpenglow whitepaper theorems
# Supports both TLA+ (TLAPS/TLC) and Stateright verification with cross-validation

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SPECS_DIR="$PROJECT_ROOT/specs"
PROOFS_DIR="$PROJECT_ROOT/proofs"
MODELS_DIR="$PROJECT_ROOT/models"
STATERIGHT_DIR="$PROJECT_ROOT/stateright"
RESULTS_DIR="$PROJECT_ROOT/verification_results"
LOGS_DIR="$RESULTS_DIR/logs"
REPORTS_DIR="$RESULTS_DIR/reports"
ARTIFACTS_DIR="$RESULTS_DIR/artifacts"

# Tool paths (can be overridden by environment variables)
TLC_PATH="${TLC_PATH:-tlc}"
TLAPS_PATH="${TLAPS_PATH:-tlapm}"
CARGO_PATH="${CARGO_PATH:-cargo}"
JAVA_PATH="${JAVA_PATH:-java}"

# Verification configuration
PARALLEL_JOBS="${PARALLEL_JOBS:-4}"
TIMEOUT_TLAPS="${TIMEOUT_TLAPS:-3600}"  # 1 hour
TIMEOUT_TLC="${TIMEOUT_TLC:-1800}"      # 30 minutes
TIMEOUT_STATERIGHT="${TIMEOUT_STATERIGHT:-900}"  # 15 minutes
VERBOSE="${VERBOSE:-false}"
INCREMENTAL="${INCREMENTAL:-false}"
CI_MODE="${CI_MODE:-false}"
GENERATE_ARTIFACTS="${GENERATE_ARTIFACTS:-true}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOGS_DIR/verification.log"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOGS_DIR/verification.log"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOGS_DIR/verification.log"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOGS_DIR/verification.log"
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $*" | tee -a "$LOGS_DIR/verification.log"
    fi
}

# Progress tracking
declare -A verification_status
declare -A verification_times
declare -A verification_errors
total_steps=0
completed_steps=0

update_progress() {
    local step_name="$1"
    local status="$2"  # "running", "success", "failed", "skipped"
    local message="${3:-}"
    
    verification_status["$step_name"]="$status"
    
    case "$status" in
        "running")
            log_info "Starting: $step_name"
            ;;
        "success")
            ((completed_steps++))
            log_success "Completed: $step_name${message:+ - $message}"
            ;;
        "failed")
            ((completed_steps++))
            log_error "Failed: $step_name${message:+ - $message}"
            ;;
        "skipped")
            ((completed_steps++))
            log_warning "Skipped: $step_name${message:+ - $message}"
            ;;
    esac
    
    if [[ "$total_steps" -gt 0 ]]; then
        local progress=$((completed_steps * 100 / total_steps))
        echo -e "${CYAN}Progress: $completed_steps/$total_steps ($progress%)${NC}"
    fi
}

# Environment setup and validation
check_environment() {
    log_info "Checking verification environment..."
    
    local missing_tools=()
    
    # Check Java (required for TLA+ tools)
    if ! command -v "$JAVA_PATH" &> /dev/null; then
        missing_tools+=("java")
    else
        local java_version
        java_version=$("$JAVA_PATH" -version 2>&1 | head -n1 | cut -d'"' -f2)
        log_debug "Found Java: $java_version"
    fi
    
    # Check TLC
    if ! command -v "$TLC_PATH" &> /dev/null; then
        missing_tools+=("tlc")
    else
        log_debug "Found TLC: $TLC_PATH"
    fi
    
    # Check TLAPS
    if ! command -v "$TLAPS_PATH" &> /dev/null; then
        missing_tools+=("tlapm")
    else
        local tlaps_version
        tlaps_version=$("$TLAPS_PATH" --version 2>&1 | head -n1 || echo "unknown")
        log_debug "Found TLAPS: $tlaps_version"
    fi
    
    # Check Rust/Cargo
    if ! command -v "$CARGO_PATH" &> /dev/null; then
        missing_tools+=("cargo")
    else
        local rust_version
        rust_version=$("$CARGO_PATH" --version | head -n1)
        log_debug "Found Rust: $rust_version"
    fi
    
    # Check for required directories
    local missing_dirs=()
    for dir in "$SPECS_DIR" "$PROOFS_DIR" "$MODELS_DIR" "$STATERIGHT_DIR"; do
        if [[ ! -d "$dir" ]]; then
            missing_dirs+=("$dir")
        fi
    done
    
    # Report missing dependencies
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install missing tools and ensure they are in PATH"
        return 1
    fi
    
    if [[ ${#missing_dirs[@]} -gt 0 ]]; then
        log_error "Missing required directories: ${missing_dirs[*]}"
        return 1
    fi
    
    # Create output directories
    mkdir -p "$RESULTS_DIR" "$LOGS_DIR" "$REPORTS_DIR" "$ARTIFACTS_DIR"
    
    log_success "Environment check passed"
    return 0
}

# File modification tracking for incremental verification
get_file_hash() {
    local file="$1"
    if [[ -f "$file" ]]; then
        if command -v sha256sum &> /dev/null; then
            sha256sum "$file" | cut -d' ' -f1
        elif command -v shasum &> /dev/null; then
            shasum -a 256 "$file" | cut -d' ' -f1
        else
            # Fallback to modification time
            stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null || echo "0"
        fi
    else
        echo "missing"
    fi
}

should_verify_file() {
    local file="$1"
    local cache_file="$RESULTS_DIR/.verification_cache"
    
    if [[ "$INCREMENTAL" != "true" ]]; then
        return 0  # Always verify if not incremental
    fi
    
    if [[ ! -f "$cache_file" ]]; then
        return 0  # No cache, must verify
    fi
    
    local current_hash
    current_hash=$(get_file_hash "$file")
    local cached_hash
    cached_hash=$(grep "^$(basename "$file"):" "$cache_file" 2>/dev/null | cut -d: -f2 || echo "")
    
    if [[ "$current_hash" != "$cached_hash" ]]; then
        return 0  # File changed, must verify
    else
        return 1  # File unchanged, skip verification
    fi
}

update_verification_cache() {
    local file="$1"
    local status="$2"
    local cache_file="$RESULTS_DIR/.verification_cache"
    
    if [[ "$status" == "success" ]]; then
        local hash
        hash=$(get_file_hash "$file")
        local basename_file
        basename_file=$(basename "$file")
        
        # Remove old entry and add new one
        grep -v "^$basename_file:" "$cache_file" 2>/dev/null > "$cache_file.tmp" || true
        echo "$basename_file:$hash" >> "$cache_file.tmp"
        mv "$cache_file.tmp" "$cache_file"
    fi
}

# TLA+ proof verification with TLAPS
verify_tlaps_module() {
    local module_file="$1"
    local module_name
    module_name=$(basename "$module_file" .tla)
    local log_file="$LOGS_DIR/tlaps_$module_name.log"
    local start_time
    start_time=$(date +%s)
    
    update_progress "TLAPS_$module_name" "running"
    
    if ! should_verify_file "$module_file"; then
        update_progress "TLAPS_$module_name" "skipped" "unchanged since last verification"
        return 0
    fi
    
    log_info "Verifying proofs in $module_name with TLAPS..."
    
    # Run TLAPS with timeout
    local tlaps_cmd="$TLAPS_PATH --verbose --toolbox 0 0 $module_file"
    log_debug "Running: $tlaps_cmd"
    
    if timeout "$TIMEOUT_TLAPS" bash -c "$tlaps_cmd" > "$log_file" 2>&1; then
        local end_time
        end_time=$(date +%s)
        verification_times["TLAPS_$module_name"]=$((end_time - start_time))
        
        # Check for proof obligations
        local total_obligations
        local proved_obligations
        total_obligations=$(grep -c "obligation" "$log_file" 2>/dev/null || echo "0")
        proved_obligations=$(grep -c "proved" "$log_file" 2>/dev/null || echo "0")
        
        if [[ "$total_obligations" -gt 0 ]] && [[ "$proved_obligations" -eq "$total_obligations" ]]; then
            update_progress "TLAPS_$module_name" "success" "$proved_obligations/$total_obligations proofs verified"
            update_verification_cache "$module_file" "success"
            return 0
        else
            verification_errors["TLAPS_$module_name"]="Only $proved_obligations/$total_obligations proofs verified"
            update_progress "TLAPS_$module_name" "failed" "incomplete proofs: $proved_obligations/$total_obligations"
            return 1
        fi
    else
        local exit_code=$?
        verification_errors["TLAPS_$module_name"]="TLAPS failed with exit code $exit_code"
        update_progress "TLAPS_$module_name" "failed" "exit code $exit_code"
        return 1
    fi
}

# TLA+ model checking with TLC
verify_tlc_model() {
    local config_file="$1"
    local config_name
    config_name=$(basename "$config_file" .cfg)
    local log_file="$LOGS_DIR/tlc_$config_name.log"
    local start_time
    start_time=$(date +%s)
    
    update_progress "TLC_$config_name" "running"
    
    if ! should_verify_file "$config_file"; then
        update_progress "TLC_$config_name" "skipped" "unchanged since last verification"
        return 0
    fi
    
    log_info "Model checking $config_name with TLC..."
    
    # Prepare TLC command
    local tlc_cmd="$TLC_PATH -config $config_file -workers $PARALLEL_JOBS"
    if [[ "$VERBOSE" == "true" ]]; then
        tlc_cmd="$tlc_cmd -verbose"
    fi
    
    # Add the specification file (extract from config)
    local spec_file
    spec_file=$(grep "^SPECIFICATION" "$config_file" | awk '{print $2}' || echo "Alpenglow")
    tlc_cmd="$tlc_cmd $SPECS_DIR/$spec_file"
    
    log_debug "Running: $tlc_cmd"
    
    if timeout "$TIMEOUT_TLC" bash -c "$tlc_cmd" > "$log_file" 2>&1; then
        local end_time
        end_time=$(date +%s)
        verification_times["TLC_$config_name"]=$((end_time - start_time))
        
        # Parse TLC results
        local states_explored
        local properties_checked
        local violations_found
        
        states_explored=$(grep "states generated" "$log_file" | tail -n1 | awk '{print $1}' || echo "0")
        properties_checked=$(grep -c "Property.*satisfied" "$log_file" 2>/dev/null || echo "0")
        violations_found=$(grep -c "Error:" "$log_file" 2>/dev/null || echo "0")
        
        if [[ "$violations_found" -eq 0 ]]; then
            update_progress "TLC_$config_name" "success" "$states_explored states, $properties_checked properties"
            update_verification_cache "$config_file" "success"
            return 0
        else
            verification_errors["TLC_$config_name"]="$violations_found property violations found"
            update_progress "TLC_$config_name" "failed" "$violations_found violations"
            return 1
        fi
    else
        local exit_code=$?
        verification_errors["TLC_$config_name"]="TLC failed with exit code $exit_code"
        update_progress "TLC_$config_name" "failed" "exit code $exit_code"
        return 1
    fi
}

# Stateright verification
verify_stateright() {
    local start_time
    start_time=$(date +%s)
    
    update_progress "Stateright" "running"
    
    if ! should_verify_file "$STATERIGHT_DIR/Cargo.toml"; then
        update_progress "Stateright" "skipped" "unchanged since last verification"
        return 0
    fi
    
    log_info "Running Stateright verification..."
    
    local log_file="$LOGS_DIR/stateright.log"
    
    # Build Stateright project
    if ! (cd "$STATERIGHT_DIR" && timeout 300 "$CARGO_PATH" build --release) > "$log_file" 2>&1; then
        verification_errors["Stateright"]="Failed to build Stateright project"
        update_progress "Stateright" "failed" "build failed"
        return 1
    fi
    
    # Run Stateright tests
    local test_cmd="$CARGO_PATH test --release -- --nocapture"
    log_debug "Running: $test_cmd (in $STATERIGHT_DIR)"
    
    if (cd "$STATERIGHT_DIR" && timeout "$TIMEOUT_STATERIGHT" $test_cmd) >> "$log_file" 2>&1; then
        local end_time
        end_time=$(date +%s)
        verification_times["Stateright"]=$((end_time - start_time))
        
        # Parse test results
        local tests_run
        local tests_passed
        tests_run=$(grep "test result:" "$log_file" | tail -n1 | awk '{print $3}' || echo "0")
        tests_passed=$(grep "test result:" "$log_file" | tail -n1 | awk '{print $3}' || echo "0")
        
        update_progress "Stateright" "success" "$tests_passed tests passed"
        update_verification_cache "$STATERIGHT_DIR/Cargo.toml" "success"
        return 0
    else
        local exit_code=$?
        verification_errors["Stateright"]="Stateright tests failed with exit code $exit_code"
        update_progress "Stateright" "failed" "exit code $exit_code"
        return 1
    fi
}

# Cross-validation between TLA+ and Stateright
run_cross_validation() {
    local start_time
    start_time=$(date +%s)
    
    update_progress "CrossValidation" "running"
    
    log_info "Running cross-validation tests..."
    
    local log_file="$LOGS_DIR/cross_validation.log"
    local test_cmd="$CARGO_PATH test cross_validation -- --nocapture"
    
    if (cd "$STATERIGHT_DIR" && timeout "$TIMEOUT_STATERIGHT" $test_cmd) > "$log_file" 2>&1; then
        local end_time
        end_time=$(date +%s)
        verification_times["CrossValidation"]=$((end_time - start_time))
        
        # Check for consistency reports
        local consistency_score
        consistency_score=$(grep "consistency_score" "$log_file" | tail -n1 | grep -o '[0-9.]*' || echo "0.0")
        
        if (( $(echo "$consistency_score >= 0.8" | bc -l 2>/dev/null || echo "0") )); then
            update_progress "CrossValidation" "success" "consistency score: $consistency_score"
            return 0
        else
            verification_errors["CrossValidation"]="Low consistency score: $consistency_score"
            update_progress "CrossValidation" "failed" "consistency score: $consistency_score"
            return 1
        fi
    else
        local exit_code=$?
        verification_errors["CrossValidation"]="Cross-validation failed with exit code $exit_code"
        update_progress "CrossValidation" "failed" "exit code $exit_code"
        return 1
    fi
}

# Parallel execution wrapper
run_parallel() {
    local -a pids=()
    local -a commands=()
    local -a names=()
    
    # Collect commands to run in parallel
    while [[ $# -gt 0 ]]; do
        names+=("$1")
        commands+=("$2")
        shift 2
    done
    
    # Start all commands in parallel
    for i in "${!commands[@]}"; do
        {
            eval "${commands[$i]}"
            echo $? > "$RESULTS_DIR/.exit_${names[$i]}"
        } &
        pids+=($!)
    done
    
    # Wait for all to complete
    local overall_success=0
    for i in "${!pids[@]}"; do
        wait "${pids[$i]}"
        local exit_code
        exit_code=$(cat "$RESULTS_DIR/.exit_${names[$i]}" 2>/dev/null || echo "1")
        if [[ "$exit_code" -ne 0 ]]; then
            overall_success=1
        fi
        rm -f "$RESULTS_DIR/.exit_${names[$i]}"
    done
    
    return $overall_success
}

# Generate comprehensive verification report
generate_report() {
    local report_file="$REPORTS_DIR/verification_report.json"
    local html_report="$REPORTS_DIR/verification_report.html"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    log_info "Generating verification report..."
    
    # Create JSON report
    cat > "$report_file" << EOF
{
  "verification_report": {
    "timestamp": "$timestamp",
    "environment": {
      "script_version": "1.0.0",
      "project_root": "$PROJECT_ROOT",
      "parallel_jobs": $PARALLEL_JOBS,
      "incremental_mode": $INCREMENTAL,
      "ci_mode": $CI_MODE
    },
    "verification_results": {
EOF

    # Add verification status for each component
    local first=true
    for component in "${!verification_status[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo "," >> "$report_file"
        fi
        
        local status="${verification_status[$component]}"
        local time="${verification_times[$component]:-0}"
        local error="${verification_errors[$component]:-}"
        
        cat >> "$report_file" << EOF
      "$component": {
        "status": "$status",
        "execution_time_seconds": $time,
        "error_message": "$error"
      }
EOF
    done
    
    # Calculate summary statistics
    local total_components=${#verification_status[@]}
    local successful_components=0
    local failed_components=0
    local skipped_components=0
    local total_time=0
    
    for component in "${!verification_status[@]}"; do
        case "${verification_status[$component]}" in
            "success") ((successful_components++)) ;;
            "failed") ((failed_components++)) ;;
            "skipped") ((skipped_components++)) ;;
        esac
        total_time=$((total_time + ${verification_times[$component]:-0}))
    done
    
    cat >> "$report_file" << EOF
    },
    "summary": {
      "total_components": $total_components,
      "successful": $successful_components,
      "failed": $failed_components,
      "skipped": $skipped_components,
      "total_execution_time_seconds": $total_time,
      "success_rate": $(echo "scale=2; $successful_components * 100 / $total_components" | bc -l 2>/dev/null || echo "0")
    },
    "artifacts": {
      "logs_directory": "$LOGS_DIR",
      "reports_directory": "$REPORTS_DIR",
      "verification_cache": "$RESULTS_DIR/.verification_cache"
    }
  }
}
EOF

    # Generate HTML report
    cat > "$html_report" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Alpenglow Verification Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f0f0f0; padding: 20px; border-radius: 5px; }
        .summary { display: flex; gap: 20px; margin: 20px 0; }
        .metric { background: #e8f4f8; padding: 15px; border-radius: 5px; text-align: center; }
        .success { color: #28a745; }
        .failed { color: #dc3545; }
        .skipped { color: #ffc107; }
        .running { color: #007bff; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .status-success { background-color: #d4edda; }
        .status-failed { background-color: #f8d7da; }
        .status-skipped { background-color: #fff3cd; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Alpenglow Whitepaper Theorem Verification Report</h1>
        <p>Generated: TIMESTAMP</p>
    </div>
    
    <div class="summary">
        <div class="metric">
            <h3>Total Components</h3>
            <div>TOTAL_COMPONENTS</div>
        </div>
        <div class="metric">
            <h3 class="success">Successful</h3>
            <div>SUCCESSFUL_COMPONENTS</div>
        </div>
        <div class="metric">
            <h3 class="failed">Failed</h3>
            <div>FAILED_COMPONENTS</div>
        </div>
        <div class="metric">
            <h3 class="skipped">Skipped</h3>
            <div>SKIPPED_COMPONENTS</div>
        </div>
        <div class="metric">
            <h3>Success Rate</h3>
            <div>SUCCESS_RATE%</div>
        </div>
    </div>
    
    <h2>Detailed Results</h2>
    <table>
        <tr>
            <th>Component</th>
            <th>Status</th>
            <th>Execution Time</th>
            <th>Details</th>
        </tr>
EOF

    # Add table rows for each component
    for component in $(printf '%s\n' "${!verification_status[@]}" | sort); do
        local status="${verification_status[$component]}"
        local time="${verification_times[$component]:-0}"
        local error="${verification_errors[$component]:-}"
        local css_class="status-$status"
        
        cat >> "$html_report" << EOF
        <tr class="$css_class">
            <td>$component</td>
            <td>$status</td>
            <td>${time}s</td>
            <td>$error</td>
        </tr>
EOF
    done
    
    cat >> "$html_report" << 'EOF'
    </table>
    
    <h2>Log Files</h2>
    <ul>
EOF

    # Add links to log files
    for log_file in "$LOGS_DIR"/*.log; do
        if [[ -f "$log_file" ]]; then
            local basename_log
            basename_log=$(basename "$log_file")
            echo "        <li><a href=\"../logs/$basename_log\">$basename_log</a></li>" >> "$html_report"
        fi
    done
    
    cat >> "$html_report" << 'EOF'
    </ul>
</body>
</html>
EOF

    # Replace placeholders in HTML
    sed -i.bak \
        -e "s/TIMESTAMP/$timestamp/g" \
        -e "s/TOTAL_COMPONENTS/$total_components/g" \
        -e "s/SUCCESSFUL_COMPONENTS/$successful_components/g" \
        -e "s/FAILED_COMPONENTS/$failed_components/g" \
        -e "s/SKIPPED_COMPONENTS/$skipped_components/g" \
        -e "s/SUCCESS_RATE/$(echo "scale=1; $successful_components * 100 / $total_components" | bc -l 2>/dev/null || echo "0")/g" \
        "$html_report"
    rm -f "$html_report.bak"
    
    log_success "Verification report generated: $report_file"
    log_success "HTML report generated: $html_report"
}

# Generate CI artifacts
generate_ci_artifacts() {
    if [[ "$GENERATE_ARTIFACTS" != "true" ]]; then
        return 0
    fi
    
    log_info "Generating CI artifacts..."
    
    # Create JUnit XML report for CI systems
    local junit_file="$ARTIFACTS_DIR/junit_results.xml"
    cat > "$junit_file" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="Alpenglow Verification" tests="${#verification_status[@]}" failures="$failed_components" time="$total_time">
    <testsuite name="Verification" tests="${#verification_status[@]}" failures="$failed_components" time="$total_time">
EOF

    for component in "${!verification_status[@]}"; do
        local status="${verification_status[$component]}"
        local time="${verification_times[$component]:-0}"
        local error="${verification_errors[$component]:-}"
        
        if [[ "$status" == "success" ]]; then
            echo "        <testcase name=\"$component\" time=\"$time\"/>" >> "$junit_file"
        else
            cat >> "$junit_file" << EOF
        <testcase name="$component" time="$time">
            <failure message="$error">$error</failure>
        </testcase>
EOF
        fi
    done
    
    cat >> "$junit_file" << EOF
    </testsuite>
</testsuites>
EOF

    # Create performance metrics file
    local metrics_file="$ARTIFACTS_DIR/performance_metrics.json"
    cat > "$metrics_file" << EOF
{
    "verification_metrics": {
        "total_execution_time": $total_time,
        "component_times": {
EOF

    local first=true
    for component in "${!verification_times[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo "," >> "$metrics_file"
        fi
        echo "            \"$component\": ${verification_times[$component]}" >> "$metrics_file"
    done
    
    cat >> "$metrics_file" << EOF
        },
        "success_rate": $(echo "scale=4; $successful_components / ${#verification_status[@]}" | bc -l 2>/dev/null || echo "0"),
        "parallel_efficiency": $(echo "scale=4; $total_time / ($total_time / $PARALLEL_JOBS)" | bc -l 2>/dev/null || echo "1")
    }
}
EOF

    # Copy important log files to artifacts
    cp -r "$LOGS_DIR" "$ARTIFACTS_DIR/"
    cp -r "$REPORTS_DIR" "$ARTIFACTS_DIR/"
    
    log_success "CI artifacts generated in $ARTIFACTS_DIR"
}

# Main verification workflow
main() {
    local start_time
    start_time=$(date +%s)
    
    echo -e "${CYAN}Alpenglow Whitepaper Theorem Verification${NC}"
    echo -e "${CYAN}=========================================${NC}"
    echo
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --incremental|-i)
                INCREMENTAL=true
                shift
                ;;
            --ci)
                CI_MODE=true
                VERBOSE=false
                shift
                ;;
            --parallel|-j)
                PARALLEL_JOBS="$2"
                shift 2
                ;;
            --timeout-tlaps)
                TIMEOUT_TLAPS="$2"
                shift 2
                ;;
            --timeout-tlc)
                TIMEOUT_TLC="$2"
                shift 2
                ;;
            --timeout-stateright)
                TIMEOUT_STATERIGHT="$2"
                shift 2
                ;;
            --no-artifacts)
                GENERATE_ARTIFACTS=false
                shift
                ;;
            --help|-h)
                cat << EOF
Usage: $0 [OPTIONS]

Options:
    --verbose, -v           Enable verbose output
    --incremental, -i       Only verify changed files
    --ci                    CI mode (less verbose, structured output)
    --parallel, -j N        Number of parallel jobs (default: 4)
    --timeout-tlaps N       TLAPS timeout in seconds (default: 3600)
    --timeout-tlc N         TLC timeout in seconds (default: 1800)
    --timeout-stateright N  Stateright timeout in seconds (default: 900)
    --no-artifacts          Don't generate CI artifacts
    --help, -h              Show this help message

Environment Variables:
    TLC_PATH               Path to TLC executable
    TLAPS_PATH             Path to TLAPS executable
    CARGO_PATH             Path to Cargo executable
    JAVA_PATH              Path to Java executable
    PARALLEL_JOBS          Number of parallel jobs
    VERBOSE                Enable verbose output (true/false)
    INCREMENTAL            Enable incremental verification (true/false)
    CI_MODE                Enable CI mode (true/false)
    GENERATE_ARTIFACTS     Generate CI artifacts (true/false)

EOF
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Initialize logging
    echo "Verification started at $(date)" > "$LOGS_DIR/verification.log"
    
    # Environment check
    if ! check_environment; then
        log_error "Environment check failed"
        exit 1
    fi
    
    # Calculate total steps for progress tracking
    total_steps=0
    
    # TLA+ proof modules (in dependency order)
    local tla_modules=(
        "$PROOFS_DIR/Safety.tla"
        "$PROOFS_DIR/Liveness.tla"
        "$PROOFS_DIR/Resilience.tla"
        "$PROOFS_DIR/WhitepaperTheorems.tla"
    )
    
    # Count existing modules
    for module in "${tla_modules[@]}"; do
        if [[ -f "$module" ]]; then
            ((total_steps++))
        fi
    done
    
    # TLC model checking
    if [[ -f "$MODELS_DIR/WhitepaperValidation.cfg" ]]; then
        ((total_steps++))
    fi
    
    # Stateright verification
    if [[ -d "$STATERIGHT_DIR" ]]; then
        ((total_steps++))
        ((total_steps++))  # Cross-validation
    fi
    
    log_info "Starting verification of $total_steps components..."
    
    # Phase 1: TLA+ Proof Verification (sequential due to dependencies)
    log_info "Phase 1: TLA+ Proof Verification"
    for module in "${tla_modules[@]}"; do
        if [[ -f "$module" ]]; then
            if ! verify_tlaps_module "$module"; then
                log_warning "TLAPS verification failed for $(basename "$module"), continuing..."
            fi
        else
            log_warning "Module not found: $module"
        fi
    done
    
    # Phase 2: Model Checking and Stateright (can run in parallel)
    log_info "Phase 2: Model Checking and Implementation Verification"
    
    local parallel_commands=()
    local parallel_names=()
    
    # TLC model checking
    if [[ -f "$MODELS_DIR/WhitepaperValidation.cfg" ]]; then
        parallel_names+=("TLC")
        parallel_commands+=("verify_tlc_model '$MODELS_DIR/WhitepaperValidation.cfg'")
    fi
    
    # Stateright verification
    if [[ -d "$STATERIGHT_DIR" ]]; then
        parallel_names+=("Stateright")
        parallel_commands+=("verify_stateright")
    fi
    
    # Run parallel verifications
    if [[ ${#parallel_commands[@]} -gt 0 ]]; then
        local parallel_args=()
        for i in "${!parallel_names[@]}"; do
            parallel_args+=("${parallel_names[$i]}" "${parallel_commands[$i]}")
        done
        
        if ! run_parallel "${parallel_args[@]}"; then
            log_warning "Some parallel verifications failed, continuing..."
        fi
    fi
    
    # Phase 3: Cross-validation
    if [[ -d "$STATERIGHT_DIR" ]] && [[ "${verification_status[Stateright]}" == "success" ]]; then
        log_info "Phase 3: Cross-validation"
        if ! run_cross_validation; then
            log_warning "Cross-validation failed, continuing..."
        fi
    fi
    
    # Generate reports
    local end_time
    end_time=$(date +%s)
    local total_execution_time=$((end_time - start_time))
    
    generate_report
    
    if [[ "$CI_MODE" == "true" ]] || [[ "$GENERATE_ARTIFACTS" == "true" ]]; then
        generate_ci_artifacts
    fi
    
    # Final summary
    echo
    echo -e "${CYAN}Verification Summary${NC}"
    echo -e "${CYAN}===================${NC}"
    echo "Total execution time: ${total_execution_time}s"
    echo "Successful components: $successful_components/${#verification_status[@]}"
    echo "Failed components: $failed_components"
    echo "Skipped components: $skipped_components"
    echo
    
    # List failed components
    if [[ $failed_components -gt 0 ]]; then
        echo -e "${RED}Failed Components:${NC}"
        for component in "${!verification_status[@]}"; do
            if [[ "${verification_status[$component]}" == "failed" ]]; then
                echo -e "  ${RED}✗${NC} $component: ${verification_errors[$component]}"
            fi
        done
        echo
    fi
    
    # List successful components
    if [[ $successful_components -gt 0 ]]; then
        echo -e "${GREEN}Successful Components:${NC}"
        for component in "${!verification_status[@]}"; do
            if [[ "${verification_status[$component]}" == "success" ]]; then
                echo -e "  ${GREEN}✓${NC} $component (${verification_times[$component]}s)"
            fi
        done
        echo
    fi
    
    echo "Detailed logs available in: $LOGS_DIR"
    echo "Reports available in: $REPORTS_DIR"
    
    if [[ "$GENERATE_ARTIFACTS" == "true" ]]; then
        echo "CI artifacts available in: $ARTIFACTS_DIR"
    fi
    
    # Exit with appropriate code
    if [[ $failed_components -eq 0 ]]; then
        log_success "All verifications completed successfully!"
        exit 0
    else
        log_error "$failed_components verification(s) failed"
        exit 1
    fi
}

# Handle script interruption
cleanup() {
    log_warning "Verification interrupted"
    
    # Kill any background processes
    jobs -p | xargs -r kill 2>/dev/null || true
    
    # Generate partial report if possible
    if [[ ${#verification_status[@]} -gt 0 ]]; then
        generate_report
    fi
    
    exit 130
}

trap cleanup SIGINT SIGTERM

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi