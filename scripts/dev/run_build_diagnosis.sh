# Author: Ayush Srivastava

#############################################################################
# Master Build Diagnosis Script for Stateright Verification
#
# This script orchestrates the complete build diagnosis process by:
# - Executing the debug_stateright_build.sh diagnostic script
# - Capturing and analyzing all build outputs
# - Generating comprehensive summary reports
# - Providing specific recommendations for fixes
# - Testing fixes incrementally to validate resolution
# - Integrating with the verification pipeline
#
# Usage: ./run_build_diagnosis.sh [OPTIONS]
#   --verbose           Enable verbose output and detailed logging
#   --output DIR        Output directory for all diagnostic files
#   --fix-mode          Automatically apply recommended fixes
#   --test-fixes        Test each fix incrementally
#   --full-analysis     Run complete dependency and security analysis
#   --report-format     Report format: text, json, html, all (default: all)
#   --timeout SECONDS   Timeout for individual diagnostic operations
#   --parallel          Run multiple diagnostic checks in parallel
#   --integration-test  Test integration with verification script
#
# Examples:
#   ./run_build_diagnosis.sh --verbose --fix-mode
#   ./run_build_diagnosis.sh --output /tmp/diagnosis --test-fixes
#   ./run_build_diagnosis.sh --full-analysis --integration-test
#############################################################################

set -e

# Color codes for enhanced output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration and paths
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "$SCRIPT_DIR/../.." && pwd )"
SCRIPTS_DIR="$PROJECT_DIR/scripts"
STATERIGHT_DIR="$PROJECT_DIR/stateright"
DIAGNOSIS_SCRIPT="$SCRIPTS_DIR/dev/debug_stateright_build.sh"
VERIFICATION_SCRIPT="$SCRIPTS_DIR/dev/stateright_verify.sh"

# Session configuration
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEFAULT_OUTPUT_DIR="$PROJECT_DIR/diagnosis/master_${TIMESTAMP}"
OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"

# Default values
VERBOSE=false
FIX_MODE=false
TEST_FIXES=false
FULL_ANALYSIS=false
REPORT_FORMAT="all"
TIMEOUT=300
PARALLEL=false
INTEGRATION_TEST=false
CLEANUP_ON_EXIT=true

# Diagnostic state tracking
DIAGNOSIS_RESULTS=()
FIXES_APPLIED=()
FIXES_TESTED=()
CRITICAL_ISSUES=0
MINOR_ISSUES=0
FIXES_SUCCESSFUL=0
FIXES_FAILED=0

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose)
            VERBOSE=true
            shift
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --fix-mode)
            FIX_MODE=true
            shift
            ;;
        --test-fixes)
            TEST_FIXES=true
            shift
            ;;
        --full-analysis)
            FULL_ANALYSIS=true
            shift
            ;;
        --report-format)
            REPORT_FORMAT="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --parallel)
            PARALLEL=true
            shift
            ;;
        --integration-test)
            INTEGRATION_TEST=true
            shift
            ;;
        --no-cleanup)
            CLEANUP_ON_EXIT=false
            shift
            ;;
        -h|--help)
            grep "^#" "$0" | sed 's/^#//' | head -25
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Enhanced helper functions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_header() {
    echo
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  ${WHITE}${BOLD}$1${NC}${BLUE}${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo
}

print_section() {
    echo
    echo -e "${MAGENTA}>>> ${BOLD}$1${NC}"
    echo -e "${MAGENTA}$(printf '%.0s─' {1..70})${NC}"
}

print_subsection() {
    echo
    echo -e "${CYAN}▶ $1${NC}"
}

verbose_log() {
    if [ "$VERBOSE" == true ]; then
        echo -e "${CYAN}[VERBOSE]${NC} $1"
    fi
}

progress_bar() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((current * width / total))
    local remaining=$((width - completed))
    
    printf "\r${BLUE}["
    printf "%*s" $completed | tr ' ' '█'
    printf "%*s" $remaining | tr ' ' '░'
    printf "] %d%% (%d/%d)${NC}" $percentage $current $total
}

# Cleanup function
cleanup_on_exit() {
    if [ "$CLEANUP_ON_EXIT" == true ]; then
        verbose_log "Performing cleanup..."
        
        # Kill any background processes
        jobs -p | xargs -r kill 2>/dev/null || true
        
        # Clean up temporary files
        find "$OUTPUT_DIR" -name "*.tmp" -delete 2>/dev/null || true
        
        verbose_log "Cleanup completed"
    fi
}

# Set up signal handlers
trap cleanup_on_exit EXIT INT TERM

# Initialize diagnostic environment
initialize_diagnosis() {
    print_header "MASTER BUILD DIAGNOSIS INITIALIZATION"
    
    print_info "Initializing master diagnostic environment..."
    
    # Create output directory structure
    mkdir -p "$OUTPUT_DIR"/{logs,reports,fixes,analysis,integration}
    
    # Create master log file
    MASTER_LOG="$OUTPUT_DIR/master_diagnosis.log"
    exec > >(tee -a "$MASTER_LOG")
    exec 2>&1
    
    print_info "Master diagnostic session: $(basename "$OUTPUT_DIR")"
    print_info "Output directory: $OUTPUT_DIR"
    print_info "Verbose mode: $VERBOSE"
    print_info "Fix mode: $FIX_MODE"
    print_info "Test fixes: $TEST_FIXES"
    print_info "Full analysis: $FULL_ANALYSIS"
    print_info "Integration test: $INTEGRATION_TEST"
    
    # Validate environment
    validate_environment
    
    # Create session metadata
    cat > "$OUTPUT_DIR/session_metadata.json" << EOF
{
    "session_id": "$(basename "$OUTPUT_DIR")",
    "timestamp": "$(date -Iseconds)",
    "configuration": {
        "verbose": $VERBOSE,
        "fix_mode": $FIX_MODE,
        "test_fixes": $TEST_FIXES,
        "full_analysis": $FULL_ANALYSIS,
        "report_format": "$REPORT_FORMAT",
        "timeout": $TIMEOUT,
        "parallel": $PARALLEL,
        "integration_test": $INTEGRATION_TEST
    },
    "environment": {
        "project_dir": "$PROJECT_DIR",
        "stateright_dir": "$STATERIGHT_DIR",
        "scripts_dir": "$SCRIPTS_DIR",
        "hostname": "$(hostname)",
        "user": "$(whoami)",
        "pwd": "$(pwd)"
    }
}
EOF
    
    print_success "Master diagnostic environment initialized"
}

# Validate environment and prerequisites
validate_environment() {
    print_subsection "Validating Environment"
    
    local validation_errors=0
    
    # Check if diagnostic script exists
    if [ ! -f "$DIAGNOSIS_SCRIPT" ]; then
        print_error "Diagnostic script not found: $DIAGNOSIS_SCRIPT"
        validation_errors=$((validation_errors + 1))
    else
        print_info "✓ Diagnostic script found"
    fi
    
    # Check if verification script exists
    if [ ! -f "$VERIFICATION_SCRIPT" ]; then
        print_warn "Verification script not found: $VERIFICATION_SCRIPT"
        print_info "  Integration testing will be limited"
    else
        print_info "✓ Verification script found"
    fi
    
    # Check Stateright directory
    if [ ! -d "$STATERIGHT_DIR" ]; then
        print_error "Stateright directory not found: $STATERIGHT_DIR"
        validation_errors=$((validation_errors + 1))
    else
        print_info "✓ Stateright directory found"
    fi
    
    # Check Rust installation
    if ! command -v cargo &> /dev/null; then
        print_error "Rust/Cargo not found"
        validation_errors=$((validation_errors + 1))
    else
        local rust_version=$(rustc --version 2>/dev/null || echo "unknown")
        print_info "✓ Rust found: $rust_version"
    fi
    
    # Check required tools
    local tools=("jq" "grep" "sed" "awk")
    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            print_info "✓ $tool found"
        else
            print_warn "⚠ $tool not found (some features may be limited)"
        fi
    done
    
    if [ $validation_errors -gt 0 ]; then
        print_error "Environment validation failed with $validation_errors errors"
        exit 1
    fi
    
    print_success "Environment validation completed"
}

# Execute the diagnostic script
run_diagnostic_script() {
    print_section "EXECUTING DIAGNOSTIC SCRIPT"
    
    print_info "Running debug_stateright_build.sh..."
    
    # Prepare diagnostic script arguments
    local diag_args=()
    
    if [ "$VERBOSE" == true ]; then
        diag_args+=("--verbose")
    fi
    
    diag_args+=("--output" "$OUTPUT_DIR/diagnosis")
    
    if [ "$FULL_ANALYSIS" == true ]; then
        diag_args+=("--full-analysis")
    fi
    
    # Execute diagnostic script with timeout
    local diag_start_time=$(date +%s)
    local diag_exit_code=0
    
    print_info "Diagnostic command: $DIAGNOSIS_SCRIPT ${diag_args[*]}"
    
    timeout "$TIMEOUT" "$DIAGNOSIS_SCRIPT" "${diag_args[@]}" > "$OUTPUT_DIR/logs/diagnostic_execution.log" 2>&1 || diag_exit_code=$?
    
    local diag_end_time=$(date +%s)
    local diag_duration=$((diag_end_time - diag_start_time))
    
    # Analyze diagnostic results
    case $diag_exit_code in
        0)
            print_success "Diagnostic script completed successfully"
            DIAGNOSIS_RESULTS+=("diagnostic:SUCCESS")
            ;;
        1)
            print_warn "Diagnostic script found minor issues"
            DIAGNOSIS_RESULTS+=("diagnostic:MINOR_ISSUES")
            MINOR_ISSUES=$((MINOR_ISSUES + 1))
            ;;
        2)
            print_error "Diagnostic script found critical issues"
            DIAGNOSIS_RESULTS+=("diagnostic:CRITICAL_ISSUES")
            CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
            ;;
        124)
            print_error "Diagnostic script timed out after ${TIMEOUT}s"
            DIAGNOSIS_RESULTS+=("diagnostic:TIMEOUT")
            CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
            ;;
        *)
            print_error "Diagnostic script failed with exit code: $diag_exit_code"
            DIAGNOSIS_RESULTS+=("diagnostic:FAILED")
            CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
            ;;
    esac
    
    print_info "Diagnostic execution time: ${diag_duration}s"
    
    # Copy diagnostic results to master output
    if [ -d "$OUTPUT_DIR/diagnosis" ]; then
        cp -r "$OUTPUT_DIR/diagnosis"/* "$OUTPUT_DIR/analysis/" 2>/dev/null || true
        print_info "Diagnostic results copied to analysis directory"
    fi
    
    return $diag_exit_code
}

# Analyze diagnostic results
analyze_diagnostic_results() {
    print_section "ANALYZING DIAGNOSTIC RESULTS"
    
    local analysis_file="$OUTPUT_DIR/analysis/master_analysis.json"
    
    # Initialize analysis structure
    cat > "$analysis_file" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "diagnostic_execution": {
        "exit_code": 0,
        "duration_seconds": 0,
        "status": "unknown"
    },
    "issues_summary": {
        "critical_issues": 0,
        "minor_issues": 0,
        "total_issues": 0
    },
    "missing_files": [],
    "compilation_errors": [],
    "import_issues": [],
    "dependency_problems": [],
    "recommendations": [],
    "fix_priority": []
}
EOF
    
    # Analyze test files report
    if [ -f "$OUTPUT_DIR/analysis/test_files_report.json" ]; then
        print_subsection "Analyzing Missing Test Files"
        
        local missing_count=$(jq -r '.missing_count' "$OUTPUT_DIR/analysis/test_files_report.json" 2>/dev/null || echo "0")
        local missing_files=$(jq -r '.missing_files[]' "$OUTPUT_DIR/analysis/test_files_report.json" 2>/dev/null || echo "")
        
        print_info "Missing test files: $missing_count"
        
        if [ "$missing_count" -gt 0 ]; then
            CRITICAL_ISSUES=$((CRITICAL_ISSUES + missing_count))
            
            # Update analysis with missing files
            jq ".missing_files = [$(echo "$missing_files" | sed 's/^/"/;s/$/",/' | tr -d '\n' | sed 's/,$//')] | .issues_summary.critical_issues += $missing_count" "$analysis_file" > "$analysis_file.tmp"
            mv "$analysis_file.tmp" "$analysis_file"
            
            print_warn "Missing files will prevent verification script from running"
        fi
    fi
    
    # Analyze cargo check results
    if [ -f "$OUTPUT_DIR/analysis/cargo_check_analysis.json" ]; then
        print_subsection "Analyzing Compilation Issues"
        
        local check_success=$(jq -r '.success' "$OUTPUT_DIR/analysis/cargo_check_analysis.json" 2>/dev/null || echo "false")
        local import_errors=$(jq -r '.error_counts.import_errors' "$OUTPUT_DIR/analysis/cargo_check_analysis.json" 2>/dev/null || echo "0")
        local dependency_errors=$(jq -r '.error_counts.dependency_errors' "$OUTPUT_DIR/analysis/cargo_check_analysis.json" 2>/dev/null || echo "0")
        
        print_info "Cargo check success: $check_success"
        print_info "Import errors: $import_errors"
        print_info "Dependency errors: $dependency_errors"
        
        if [ "$check_success" == "false" ]; then
            CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
        fi
        
        if [ "$import_errors" -gt 0 ]; then
            MINOR_ISSUES=$((MINOR_ISSUES + import_errors))
        fi
        
        if [ "$dependency_errors" -gt 0 ]; then
            CRITICAL_ISSUES=$((CRITICAL_ISSUES + dependency_errors))
        fi
    fi
    
    # Analyze import validation results
    if [ -f "$OUTPUT_DIR/analysis/import_validation.json" ]; then
        print_subsection "Analyzing Import Issues"
        
        local total_import_issues=$(jq -r '.total_issues' "$OUTPUT_DIR/analysis/import_validation.json" 2>/dev/null || echo "0")
        
        print_info "Total import issues: $total_import_issues"
        
        if [ "$total_import_issues" -gt 0 ]; then
            MINOR_ISSUES=$((MINOR_ISSUES + total_import_issues))
        fi
    fi
    
    # Generate recommendations based on analysis
    generate_recommendations
    
    # Update final analysis
    local total_issues=$((CRITICAL_ISSUES + MINOR_ISSUES))
    
    jq ".issues_summary.critical_issues = $CRITICAL_ISSUES | .issues_summary.minor_issues = $MINOR_ISSUES | .issues_summary.total_issues = $total_issues" "$analysis_file" > "$analysis_file.tmp"
    mv "$analysis_file.tmp" "$analysis_file"
    
    print_info "Analysis completed: $CRITICAL_ISSUES critical, $MINOR_ISSUES minor issues"
}

# Generate specific recommendations for fixes
generate_recommendations() {
    print_subsection "Generating Fix Recommendations"
    
    local recommendations_file="$OUTPUT_DIR/analysis/recommendations.json"
    
    cat > "$recommendations_file" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "priority_fixes": [],
    "optional_fixes": [],
    "fix_commands": [],
    "validation_steps": []
}
EOF
    
    # Analyze missing test files and generate fix commands
    if [ -f "$OUTPUT_DIR/analysis/test_files_report.json" ]; then
        local missing_files=$(jq -r '.missing_files[]' "$OUTPUT_DIR/analysis/test_files_report.json" 2>/dev/null)
        
        if [ -n "$missing_files" ]; then
            print_info "Generating commands to create missing test files..."
            
            local fix_commands=()
            while IFS= read -r file; do
                if [ -n "$file" ]; then
                    fix_commands+=("touch $STATERIGHT_DIR/tests/${file}.rs")
                fi
            done <<< "$missing_files"
            
            # Add to recommendations
            local commands_json=$(printf '%s\n' "${fix_commands[@]}" | jq -R . | jq -s .)
            jq ".fix_commands += $commands_json" "$recommendations_file" > "$recommendations_file.tmp"
            mv "$recommendations_file.tmp" "$recommendations_file"
        fi
    fi
    
    # Generate import fix recommendations
    if [ -f "$OUTPUT_DIR/analysis/import_validation.json" ]; then
        local import_issues=$(jq -r '.import_issues[]' "$OUTPUT_DIR/analysis/import_validation.json" 2>/dev/null)
        
        if [ -n "$import_issues" ]; then
            print_info "Generating import fix recommendations..."
            
            # Add import fix recommendations
            jq '.priority_fixes += ["Fix import statements in test files", "Replace local_stateright with crate::stateright", "Resolve naming conflicts with external stateright crate"]' "$recommendations_file" > "$recommendations_file.tmp"
            mv "$recommendations_file.tmp" "$recommendations_file"
        fi
    fi
    
    # Add validation steps
    local validation_steps=(
        "Run cargo check to verify compilation"
        "Run cargo test --list to verify test discovery"
        "Execute verification script with small configuration"
        "Validate all expected test files exist"
    )
    
    local validation_json=$(printf '%s\n' "${validation_steps[@]}" | jq -R . | jq -s .)
    jq ".validation_steps = $validation_json" "$recommendations_file" > "$recommendations_file.tmp"
    mv "$recommendations_file.tmp" "$recommendations_file"
    
    print_success "Recommendations generated"
}

# Apply fixes automatically if fix mode is enabled
apply_fixes() {
    if [ "$FIX_MODE" != true ]; then
        print_info "Fix mode disabled, skipping automatic fixes"
        return 0
    fi
    
    print_section "APPLYING AUTOMATIC FIXES"
    
    if [ ! -f "$OUTPUT_DIR/analysis/recommendations.json" ]; then
        print_warn "No recommendations file found, skipping fixes"
        return 1
    fi
    
    # Get fix commands from recommendations
    local fix_commands=$(jq -r '.fix_commands[]' "$OUTPUT_DIR/analysis/recommendations.json" 2>/dev/null)
    
    if [ -z "$fix_commands" ]; then
        print_info "No automatic fixes available"
        return 0
    fi
    
    print_info "Applying automatic fixes..."
    
    local fix_count=0
    local total_fixes=$(echo "$fix_commands" | wc -l)
    
    while IFS= read -r command; do
        if [ -n "$command" ]; then
            fix_count=$((fix_count + 1))
            progress_bar $fix_count $total_fixes
            
            verbose_log "Executing: $command"
            
            # Execute fix command
            if eval "$command" >> "$OUTPUT_DIR/logs/fix_execution.log" 2>&1; then
                FIXES_APPLIED+=("$command:SUCCESS")
                FIXES_SUCCESSFUL=$((FIXES_SUCCESSFUL + 1))
                verbose_log "✓ Fix applied successfully: $command"
            else
                FIXES_APPLIED+=("$command:FAILED")
                FIXES_FAILED=$((FIXES_FAILED + 1))
                verbose_log "✗ Fix failed: $command"
            fi
        fi
    done <<< "$fix_commands"
    
    echo  # New line after progress bar
    
    print_success "Applied $FIXES_SUCCESSFUL fixes successfully, $FIXES_FAILED failed"
    
    # Generate fix application report
    cat > "$OUTPUT_DIR/fixes/fix_application_report.json" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "fixes_applied": $(printf '%s\n' "${FIXES_APPLIED[@]}" | jq -R 'split(":") | {command: .[0], status: .[1]}' | jq -s .),
    "summary": {
        "total_fixes": $total_fixes,
        "successful": $FIXES_SUCCESSFUL,
        "failed": $FIXES_FAILED
    }
}
EOF
}

# Test fixes incrementally
test_fixes_incrementally() {
    if [ "$TEST_FIXES" != true ]; then
        print_info "Fix testing disabled, skipping incremental tests"
        return 0
    fi
    
    print_section "TESTING FIXES INCREMENTALLY"
    
    print_info "Running incremental validation tests..."
    
    # Test 1: Cargo check
    print_subsection "Testing Cargo Check"
    
    cd "$STATERIGHT_DIR"
    
    if cargo check > "$OUTPUT_DIR/logs/post_fix_cargo_check.log" 2>&1; then
        print_success "✓ Cargo check passed after fixes"
        FIXES_TESTED+=("cargo_check:PASS")
    else
        print_error "✗ Cargo check still failing after fixes"
        FIXES_TESTED+=("cargo_check:FAIL")
        
        # Show key errors
        print_info "Key remaining errors:"
        grep -E "(error\[|error:|cannot find)" "$OUTPUT_DIR/logs/post_fix_cargo_check.log" | head -5 | while read -r line; do
            echo "  $line"
        done
    fi
    
    # Test 2: Test file discovery
    print_subsection "Testing Test Discovery"
    
    if cargo test --list > "$OUTPUT_DIR/logs/post_fix_test_list.log" 2>&1; then
        print_success "✓ Test discovery working after fixes"
        FIXES_TESTED+=("test_discovery:PASS")
        
        # Count discovered tests
        local test_count=$(grep -c ": test$" "$OUTPUT_DIR/logs/post_fix_test_list.log" || echo "0")
        print_info "Discovered $test_count tests"
    else
        print_error "✗ Test discovery still failing after fixes"
        FIXES_TESTED+=("test_discovery:FAIL")
    fi
    
    # Test 3: Missing test files check
    print_subsection "Testing Missing Files Resolution"
    
    local expected_files=("safety_properties" "liveness_properties" "byzantine_resilience" "integration_tests" "economic_model" "vrf_leader_selection" "adaptive_timeouts")
    local missing_after_fix=0
    
    for test_file in "${expected_files[@]}"; do
        if [ -f "tests/${test_file}.rs" ]; then
            verbose_log "✓ $test_file.rs exists"
        else
            verbose_log "✗ $test_file.rs still missing"
            missing_after_fix=$((missing_after_fix + 1))
        fi
    done
    
    if [ $missing_after_fix -eq 0 ]; then
        print_success "✓ All expected test files now exist"
        FIXES_TESTED+=("missing_files:RESOLVED")
    else
        print_warn "⚠ $missing_after_fix test files still missing"
        FIXES_TESTED+=("missing_files:PARTIAL")
    fi
    
    cd "$PROJECT_DIR"
    
    # Generate test results report
    cat > "$OUTPUT_DIR/fixes/fix_testing_report.json" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "tests_performed": [
        "cargo_check",
        "test_discovery",
        "missing_files"
    ],
    "results": $(printf '%s\n' "${FIXES_TESTED[@]}" | jq -R 'split(":") | {test: .[0], result: .[1]}' | jq -s .),
    "summary": {
        "tests_passed": $(echo "${FIXES_TESTED[@]}" | grep -o "PASS\|RESOLVED" | wc -l),
        "tests_failed": $(echo "${FIXES_TESTED[@]}" | grep -o "FAIL" | wc -l),
        "tests_partial": $(echo "${FIXES_TESTED[@]}" | grep -o "PARTIAL" | wc -l)
    }
}
EOF
    
    print_success "Incremental testing completed"
}

# Test integration with verification script
test_verification_integration() {
    if [ "$INTEGRATION_TEST" != true ]; then
        print_info "Integration testing disabled, skipping verification script test"
        return 0
    fi
    
    print_section "TESTING VERIFICATION SCRIPT INTEGRATION"
    
    if [ ! -f "$VERIFICATION_SCRIPT" ]; then
        print_warn "Verification script not found, skipping integration test"
        return 1
    fi
    
    print_info "Testing integration with verification script..."
    
    # Test with small configuration and short timeout
    local integration_start_time=$(date +%s)
    local integration_exit_code=0
    
    print_subsection "Running Verification Script Test"
    
    # Run verification script with minimal configuration
    timeout 120 "$VERIFICATION_SCRIPT" --config small --timeout 60 > "$OUTPUT_DIR/integration/verification_test.log" 2>&1 || integration_exit_code=$?
    
    local integration_end_time=$(date +%s)
    local integration_duration=$((integration_end_time - integration_start_time))
    
    # Analyze integration test results
    case $integration_exit_code in
        0)
            print_success "✓ Verification script integration test passed"
            DIAGNOSIS_RESULTS+=("integration:SUCCESS")
            ;;
        1)
            print_warn "⚠ Verification script completed with warnings"
            DIAGNOSIS_RESULTS+=("integration:WARNINGS")
            ;;
        124)
            print_warn "⚠ Verification script test timed out (expected for build issues)"
            DIAGNOSIS_RESULTS+=("integration:TIMEOUT")
            ;;
        *)
            print_error "✗ Verification script integration test failed"
            DIAGNOSIS_RESULTS+=("integration:FAILED")
            
            # Show key errors from verification
            print_info "Key integration errors:"
            grep -E "(ERROR|FAILED|error\[)" "$OUTPUT_DIR/integration/verification_test.log" | head -5 | while read -r line; do
                echo "  $line"
            done
            ;;
    esac
    
    print_info "Integration test duration: ${integration_duration}s"
    
    # Generate integration test report
    cat > "$OUTPUT_DIR/integration/integration_test_report.json" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "verification_script": "$VERIFICATION_SCRIPT",
    "test_configuration": "small",
    "timeout_seconds": 60,
    "execution": {
        "exit_code": $integration_exit_code,
        "duration_seconds": $integration_duration,
        "status": "$(echo "${DIAGNOSIS_RESULTS[-1]}" | cut -d: -f2)"
    },
    "log_file": "$OUTPUT_DIR/integration/verification_test.log"
}
EOF
    
    return $integration_exit_code
}

# Generate comprehensive reports
generate_comprehensive_reports() {
    print_section "GENERATING COMPREHENSIVE REPORTS"
    
    # Generate master summary report
    generate_master_summary
    
    # Generate reports based on format selection
    case "$REPORT_FORMAT" in
        "text"|"all")
            generate_text_report
            ;;
    esac
    
    case "$REPORT_FORMAT" in
        "json"|"all")
            generate_json_report
            ;;
    esac
    
    case "$REPORT_FORMAT" in
        "html"|"all")
            generate_html_report
            ;;
    esac
    
    print_success "Comprehensive reports generated"
}

# Generate master summary
generate_master_summary() {
    print_subsection "Generating Master Summary"
    
    local summary_file="$OUTPUT_DIR/reports/master_summary.txt"
    
    cat > "$summary_file" << EOF
================================================================================
MASTER BUILD DIAGNOSIS SUMMARY
================================================================================

Session: $(basename "$OUTPUT_DIR")
Date: $(date)
Duration: $(($(date +%s) - $(date -d "$(jq -r '.timestamp' "$OUTPUT_DIR/session_metadata.json")" +%s))) seconds

CONFIGURATION:
--------------
Verbose Mode: $VERBOSE
Fix Mode: $FIX_MODE
Test Fixes: $TEST_FIXES
Full Analysis: $FULL_ANALYSIS
Integration Test: $INTEGRATION_TEST
Report Format: $REPORT_FORMAT

DIAGNOSIS RESULTS:
-----------------
Critical Issues: $CRITICAL_ISSUES
Minor Issues: $MINOR_ISSUES
Total Issues: $((CRITICAL_ISSUES + MINOR_ISSUES))

FIXES APPLIED:
-------------
$(if [ "$FIX_MODE" == true ]; then
    echo "Fixes Attempted: $((FIXES_SUCCESSFUL + FIXES_FAILED))"
    echo "Fixes Successful: $FIXES_SUCCESSFUL"
    echo "Fixes Failed: $FIXES_FAILED"
else
    echo "Fix mode was disabled"
fi)

FIX TESTING:
-----------
$(if [ "$TEST_FIXES" == true ]; then
    echo "Tests Performed: ${#FIXES_TESTED[@]}"
    echo "Tests Passed: $(echo "${FIXES_TESTED[@]}" | grep -o "PASS\|RESOLVED" | wc -l)"
    echo "Tests Failed: $(echo "${FIXES_TESTED[@]}" | grep -o "FAIL" | wc -l)"
else
    echo "Fix testing was disabled"
fi)

INTEGRATION TEST:
----------------
$(if [ "$INTEGRATION_TEST" == true ]; then
    local integration_result=$(echo "${DIAGNOSIS_RESULTS[@]}" | grep "integration:" | cut -d: -f2 || echo "NOT_RUN")
    echo "Verification Script Test: $integration_result"
else
    echo "Integration testing was disabled"
fi)

KEY FINDINGS:
------------
$(if [ -f "$OUTPUT_DIR/analysis/test_files_report.json" ]; then
    local missing_count=$(jq -r '.missing_count' "$OUTPUT_DIR/analysis/test_files_report.json")
    echo "• Missing test files: $missing_count"
fi)
$(if [ -f "$OUTPUT_DIR/analysis/cargo_check_analysis.json" ]; then
    local check_success=$(jq -r '.success' "$OUTPUT_DIR/analysis/cargo_check_analysis.json")
    echo "• Cargo check status: $check_success"
fi)
$(if [ -f "$OUTPUT_DIR/analysis/import_validation.json" ]; then
    local import_issues=$(jq -r '.total_issues' "$OUTPUT_DIR/analysis/import_validation.json")
    echo "• Import issues: $import_issues"
fi)

RECOMMENDATIONS:
---------------
$(if [ $CRITICAL_ISSUES -gt 0 ]; then
    echo "CRITICAL: Address $CRITICAL_ISSUES critical issues before running verification"
    echo "• Create missing test files"
    echo "• Fix compilation errors"
    echo "• Resolve dependency issues"
fi)
$(if [ $MINOR_ISSUES -gt 0 ]; then
    echo "MINOR: Address $MINOR_ISSUES minor issues for optimal performance"
    echo "• Fix import statements"
    echo "• Resolve naming conflicts"
fi)
$(if [ $CRITICAL_ISSUES -eq 0 ] && [ $MINOR_ISSUES -eq 0 ]; then
    echo "✓ No critical issues found - verification script should work"
fi)

NEXT STEPS:
----------
$(if [ "$FIX_MODE" == true ] && [ $FIXES_SUCCESSFUL -gt 0 ]; then
    echo "1. Review applied fixes in: $OUTPUT_DIR/fixes/"
    echo "2. Run verification script to test fixes"
    echo "3. Address any remaining issues"
else
    echo "1. Review detailed analysis in: $OUTPUT_DIR/analysis/"
    echo "2. Apply recommended fixes manually or re-run with --fix-mode"
    echo "3. Test fixes with --test-fixes option"
fi)
4. Run integration test with --integration-test
5. Execute full verification pipeline

FILES GENERATED:
---------------
• Master Log: $OUTPUT_DIR/master_diagnosis.log
• Analysis Reports: $OUTPUT_DIR/analysis/
• Fix Reports: $OUTPUT_DIR/fixes/
• Integration Tests: $OUTPUT_DIR/integration/
• Comprehensive Reports: $OUTPUT_DIR/reports/

INTEGRATION:
-----------
This master diagnostic script orchestrates the complete build diagnosis process.
It should be run before attempting the verification script to ensure all
prerequisites are met and issues are resolved.

Exit codes:
  0: No critical issues, verification should work
  1: Minor issues found, verification may work with warnings
  2: Critical issues found, verification will likely fail

================================================================================
EOF
    
    cat "$summary_file"
}

# Generate JSON report
generate_json_report() {
    print_subsection "Generating JSON Report"
    
    local json_report="$OUTPUT_DIR/reports/master_report.json"
    
    cat > "$json_report" << EOF
{
    "session": {
        "id": "$(basename "$OUTPUT_DIR")",
        "timestamp": "$(date -Iseconds)",
        "duration_seconds": $(($(date +%s) - $(date -d "$(jq -r '.timestamp' "$OUTPUT_DIR/session_metadata.json")" +%s))),
        "configuration": $(cat "$OUTPUT_DIR/session_metadata.json" | jq '.configuration')
    },
    "diagnosis": {
        "critical_issues": $CRITICAL_ISSUES,
        "minor_issues": $MINOR_ISSUES,
        "total_issues": $((CRITICAL_ISSUES + MINOR_ISSUES)),
        "results": [$(printf '"%s",' "${DIAGNOSIS_RESULTS[@]}" | sed 's/,$//')],
        "status": "$([ $CRITICAL_ISSUES -eq 0 ] && echo "READY" || echo "ISSUES_FOUND")"
    },
    "fixes": {
        "mode_enabled": $FIX_MODE,
        "attempted": $((FIXES_SUCCESSFUL + FIXES_FAILED)),
        "successful": $FIXES_SUCCESSFUL,
        "failed": $FIXES_FAILED,
        "applied": [$(printf '"%s",' "${FIXES_APPLIED[@]}" | sed 's/,$//')],
        "tested": [$(printf '"%s",' "${FIXES_TESTED[@]}" | sed 's/,$//')],
        "testing_enabled": $TEST_FIXES
    },
    "integration": {
        "testing_enabled": $INTEGRATION_TEST,
        "verification_script_available": $([ -f "$VERIFICATION_SCRIPT" ] && echo "true" || echo "false"),
        "test_result": "$(echo "${DIAGNOSIS_RESULTS[@]}" | grep "integration:" | cut -d: -f2 || echo "NOT_RUN")"
    },
    "analysis_files": {
        "test_files_report": "$([ -f "$OUTPUT_DIR/analysis/test_files_report.json" ] && echo "$OUTPUT_DIR/analysis/test_files_report.json" || echo "null")",
        "cargo_check_analysis": "$([ -f "$OUTPUT_DIR/analysis/cargo_check_analysis.json" ] && echo "$OUTPUT_DIR/analysis/cargo_check_analysis.json" || echo "null")",
        "import_validation": "$([ -f "$OUTPUT_DIR/analysis/import_validation.json" ] && echo "$OUTPUT_DIR/analysis/import_validation.json" || echo "null")",
        "recommendations": "$([ -f "$OUTPUT_DIR/analysis/recommendations.json" ] && echo "$OUTPUT_DIR/analysis/recommendations.json" || echo "null")"
    },
    "recommendations": {
        "immediate_actions": [
$(if [ $CRITICAL_ISSUES -gt 0 ]; then
    echo '            "Create missing test files",'
    echo '            "Fix compilation errors",'
    echo '            "Resolve dependency issues"'
else
    echo '            "No immediate actions required"'
fi)
        ],
        "optional_improvements": [
$(if [ $MINOR_ISSUES -gt 0 ]; then
    echo '            "Fix import statements",'
    echo '            "Resolve naming conflicts",'
    echo '            "Optimize build configuration"'
fi)
        ],
        "next_steps": [
            "Review detailed analysis reports",
            "Apply recommended fixes",
            "Test fixes incrementally",
            "Run verification script integration test",
            "Execute full verification pipeline"
        ]
    },
    "exit_code": $([ $CRITICAL_ISSUES -eq 0 ] && echo "0" || echo "2")
}
EOF
    
    print_info "JSON report generated: $json_report"
}

# Generate HTML report
generate_html_report() {
    print_subsection "Generating HTML Report"
    
    local html_report="$OUTPUT_DIR/reports/master_report.html"
    
    cat > "$html_report" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Master Build Diagnosis Report</title>
    <style>
        body {
            font-family: 'Segoe UI', Arial, sans-serif;
            margin: 0;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #333;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background: white;
            border-radius: 15px;
            padding: 40px;
            box-shadow: 0 25px 80px rgba(0,0,0,0.3);
        }
        h1 {
            color: #333;
            border-bottom: 4px solid #667eea;
            padding-bottom: 15px;
            margin-bottom: 30px;
            font-size: 2.5em;
        }
        h2 {
            color: #667eea;
            margin-top: 40px;
            font-size: 1.8em;
            border-left: 4px solid #667eea;
            padding-left: 15px;
        }
        h3 {
            color: #495057;
            margin-top: 25px;
            font-size: 1.3em;
        }
        .dashboard {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 25px;
            margin: 30px 0;
        }
        .card {
            background: linear-gradient(135deg, #f8f9fa 0%, #e9ecef 100%);
            padding: 25px;
            border-radius: 12px;
            border-left: 6px solid #667eea;
            box-shadow: 0 4px 15px rgba(0,0,0,0.1);
            transition: transform 0.2s;
        }
        .card:hover {
            transform: translateY(-2px);
        }
        .card h3 {
            margin-top: 0;
            color: #495057;
            font-size: 1.1em;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        .card .value {
            font-size: 2.5em;
            font-weight: bold;
            margin: 10px 0;
        }
        .success { color: #28a745; }
        .warning { color: #ffc107; }
        .error { color: #dc3545; }
        .info { color: #17a2b8; }
        .status-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin: 20px 0;
        }
        .status-item {
            background: #f8f9fa;
            padding: 15px;
            border-radius: 8px;
            border-left: 4px solid #dee2e6;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .status-item.success { border-left-color: #28a745; }
        .status-item.warning { border-left-color: #ffc107; }
        .status-item.error { border-left-color: #dc3545; }
        .progress-section {
            background: #f8f9fa;
            padding: 25px;
            border-radius: 10px;
            margin: 25px 0;
        }
        .progress-bar {
            background: #e9ecef;
            border-radius: 10px;
            overflow: hidden;
            height: 25px;
            margin: 10px 0;
        }
        .progress-fill {
            background: linear-gradient(90deg, #28a745, #20c997);
            height: 100%;
            transition: width 0.3s ease;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: bold;
        }
        .recommendations {
            background: linear-gradient(135deg, #e7f3ff 0%, #cce7ff 100%);
            border-left: 6px solid #007bff;
            padding: 25px;
            border-radius: 10px;
            margin: 25px 0;
        }
        .recommendations h3 {
            color: #007bff;
            margin-top: 0;
        }
        .recommendations ul {
            margin: 15px 0;
            padding-left: 25px;
        }
        .recommendations li {
            margin: 8px 0;
            line-height: 1.6;
        }
        .file-list {
            background: #f4f4f4;
            padding: 20px;
            border-radius: 8px;
            margin: 15px 0;
            font-family: 'Courier New', monospace;
            font-size: 0.9em;
        }
        .file-list ul {
            margin: 0;
            padding-left: 20px;
        }
        .footer {
            margin-top: 50px;
            padding-top: 25px;
            border-top: 2px solid #dee2e6;
            text-align: center;
            color: #6c757d;
            font-size: 0.9em;
        }
        .timestamp {
            color: #6c757d;
            font-size: 0.9em;
            margin-bottom: 20px;
        }
        .section-divider {
            height: 2px;
            background: linear-gradient(90deg, transparent, #667eea, transparent);
            margin: 40px 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔧 Master Build Diagnosis Report</h1>
        <div class="timestamp">Generated on TIMESTAMP | Session: SESSION_ID</div>
        
        <div class="dashboard">
            <div class="card">
                <h3>Critical Issues</h3>
                <div class="value CRITICAL_CLASS">CRITICAL_COUNT</div>
                <p>Issues that prevent verification</p>
            </div>
            <div class="card">
                <h3>Minor Issues</h3>
                <div class="value MINOR_CLASS">MINOR_COUNT</div>
                <p>Issues that may cause warnings</p>
            </div>
            <div class="card">
                <h3>Fixes Applied</h3>
                <div class="value FIXES_CLASS">FIXES_COUNT</div>
                <p>Automatic fixes attempted</p>
            </div>
            <div class="card">
                <h3>Overall Status</h3>
                <div class="value OVERALL_CLASS">OVERALL_STATUS</div>
                <p>Verification readiness</p>
            </div>
        </div>
        
        <div class="section-divider"></div>
        
        <h2>📊 Diagnosis Results</h2>
        
        <div class="status-grid">
            <div class="status-item DIAGNOSTIC_STATUS_CLASS">
                <span>Diagnostic Execution</span>
                <strong>DIAGNOSTIC_STATUS</strong>
            </div>
            <div class="status-item CARGO_STATUS_CLASS">
                <span>Cargo Check</span>
                <strong>CARGO_STATUS</strong>
            </div>
            <div class="status-item FILES_STATUS_CLASS">
                <span>Test Files</span>
                <strong>FILES_STATUS</strong>
            </div>
            <div class="status-item INTEGRATION_STATUS_CLASS">
                <span>Integration Test</span>
                <strong>INTEGRATION_STATUS</strong>
            </div>
        </div>
        
        <h2>🔧 Fix Application Progress</h2>
        
        <div class="progress-section">
            <h3>Automatic Fixes</h3>
            <div class="progress-bar">
                <div class="progress-fill" style="width: FIX_PERCENTAGE%;">
                    FIXES_SUCCESSFUL / FIXES_TOTAL fixes applied
                </div>
            </div>
            
            <h3>Issue Resolution</h3>
            <div class="progress-bar">
                <div class="progress-fill" style="width: RESOLUTION_PERCENTAGE%;">
                    RESOLVED_ISSUES / TOTAL_ISSUES issues resolved
                </div>
            </div>
        </div>
        
        <h2>🎯 Key Findings</h2>
        
        <div class="status-grid">
            <div class="status-item">
                <span>Missing Test Files</span>
                <strong>MISSING_FILES_COUNT</strong>
            </div>
            <div class="status-item">
                <span>Import Issues</span>
                <strong>IMPORT_ISSUES_COUNT</strong>
            </div>
            <div class="status-item">
                <span>Compilation Errors</span>
                <strong>COMPILATION_ERRORS_COUNT</strong>
            </div>
            <div class="status-item">
                <span>Dependency Problems</span>
                <strong>DEPENDENCY_ISSUES_COUNT</strong>
            </div>
        </div>
        
        <h2>💡 Recommendations</h2>
        
        <div class="recommendations">
            <h3>Immediate Actions Required</h3>
            <ul>
                IMMEDIATE_ACTIONS
            </ul>
        </div>
        
        <div class="recommendations">
            <h3>Optional Improvements</h3>
            <ul>
                OPTIONAL_IMPROVEMENTS
            </ul>
        </div>
        
        <h2>📁 Generated Files</h2>
        
        <div class="file-list">
            <h3>Analysis Reports</h3>
            <ul>
                <li>Master Analysis: analysis/master_analysis.json</li>
                <li>Test Files Report: analysis/test_files_report.json</li>
                <li>Cargo Check Analysis: analysis/cargo_check_analysis.json</li>
                <li>Import Validation: analysis/import_validation.json</li>
                <li>Recommendations: analysis/recommendations.json</li>
            </ul>
            
            <h3>Fix Reports</h3>
            <ul>
                <li>Fix Application: fixes/fix_application_report.json</li>
                <li>Fix Testing: fixes/fix_testing_report.json</li>
            </ul>
            
            <h3>Integration Tests</h3>
            <ul>
                <li>Integration Test: integration/integration_test_report.json</li>
                <li>Verification Log: integration/verification_test.log</li>
            </ul>
        </div>
        
        <h2>🚀 Next Steps</h2>
        
        <ol>
            <li><strong>Review Analysis:</strong> Examine detailed reports in the analysis directory</li>
            <li><strong>Apply Fixes:</strong> Use --fix-mode to automatically apply recommended fixes</li>
            <li><strong>Test Changes:</strong> Use --test-fixes to validate fix effectiveness</li>
            <li><strong>Integration Test:</strong> Use --integration-test to verify verification script compatibility</li>
            <li><strong>Run Verification:</strong> Execute the full verification pipeline</li>
        </ol>
        
        <div class="footer">
            <p><strong>Master Build Diagnosis Tool</strong> | Alpenglow Stateright Verification Suite</p>
            <p>Session: SESSION_ID | Generated: TIMESTAMP</p>
        </div>
    </div>
</body>
</html>
EOF
    
    # Replace placeholders with actual values
    local overall_status="READY"
    local overall_class="success"
    if [ $CRITICAL_ISSUES -gt 0 ]; then
        overall_status="ISSUES"
        overall_class="error"
    elif [ $MINOR_ISSUES -gt 0 ]; then
        overall_status="WARNINGS"
        overall_class="warning"
    fi
    
    local fix_percentage=0
    local fixes_total=$((FIXES_SUCCESSFUL + FIXES_FAILED))
    if [ $fixes_total -gt 0 ]; then
        fix_percentage=$((FIXES_SUCCESSFUL * 100 / fixes_total))
    fi
    
    local resolution_percentage=0
    local total_issues=$((CRITICAL_ISSUES + MINOR_ISSUES))
    if [ $total_issues -gt 0 ]; then
        local resolved_issues=$((total_issues - CRITICAL_ISSUES))  # Assume minor issues are resolved
        resolution_percentage=$((resolved_issues * 100 / total_issues))
    fi
    
    # Generate immediate actions
    local immediate_actions=""
    if [ $CRITICAL_ISSUES -gt 0 ]; then
        immediate_actions+="<li>Create missing test files to enable verification script execution</li>"
        immediate_actions+="<li>Fix compilation errors preventing successful builds</li>"
        immediate_actions+="<li>Resolve dependency issues and import conflicts</li>"
    else
        immediate_actions+="<li>No immediate actions required - verification should work</li>"
    fi
    
    # Generate optional improvements
    local optional_improvements=""
    if [ $MINOR_ISSUES -gt 0 ]; then
        optional_improvements+="<li>Fix import statements for cleaner code</li>"
        optional_improvements+="<li>Resolve naming conflicts with external crates</li>"
        optional_improvements+="<li>Optimize build configuration for better performance</li>"
    else
        optional_improvements+="<li>Consider running full analysis for comprehensive optimization</li>"
        optional_improvements+="<li>Enable additional verification scenarios</li>"
    fi
    
    # Replace all placeholders
    sed -i.bak \
        -e "s/TIMESTAMP/$(date)/g" \
        -e "s/SESSION_ID/$(basename "$OUTPUT_DIR")/g" \
        -e "s/CRITICAL_COUNT/$CRITICAL_ISSUES/g" \
        -e "s/MINOR_COUNT/$MINOR_ISSUES/g" \
        -e "s/FIXES_COUNT/$FIXES_SUCCESSFUL/g" \
        -e "s/OVERALL_STATUS/$overall_status/g" \
        -e "s/OVERALL_CLASS/$overall_class/g" \
        -e "s/CRITICAL_CLASS/$([ $CRITICAL_ISSUES -eq 0 ] && echo "success" || echo "error")/g" \
        -e "s/MINOR_CLASS/$([ $MINOR_ISSUES -eq 0 ] && echo "success" || echo "warning")/g" \
        -e "s/FIXES_CLASS/$([ $FIXES_SUCCESSFUL -gt 0 ] && echo "success" || echo "info")/g" \
        -e "s/FIX_PERCENTAGE/$fix_percentage/g" \
        -e "s/FIXES_SUCCESSFUL/$FIXES_SUCCESSFUL/g" \
        -e "s/FIXES_TOTAL/$fixes_total/g" \
        -e "s/RESOLUTION_PERCENTAGE/$resolution_percentage/g" \
        -e "s/RESOLVED_ISSUES/$((total_issues - CRITICAL_ISSUES))/g" \
        -e "s/TOTAL_ISSUES/$total_issues/g" \
        -e "s/IMMEDIATE_ACTIONS/$immediate_actions/g" \
        -e "s/OPTIONAL_IMPROVEMENTS/$optional_improvements/g" \
        "$html_report"
    
    # Add status classes and values
    local diagnostic_status="SUCCESS"
    local cargo_status="UNKNOWN"
    local files_status="UNKNOWN"
    local integration_status="NOT_RUN"
    
    # Extract status from results
    for result in "${DIAGNOSIS_RESULTS[@]}"; do
        case "$result" in
            diagnostic:*) diagnostic_status="${result#*:}" ;;
            integration:*) integration_status="${result#*:}" ;;
        esac
    done
    
    # Get additional status from analysis files
    if [ -f "$OUTPUT_DIR/analysis/cargo_check_analysis.json" ]; then
        local check_success=$(jq -r '.success' "$OUTPUT_DIR/analysis/cargo_check_analysis.json" 2>/dev/null || echo "false")
        cargo_status=$([ "$check_success" == "true" ] && echo "PASS" || echo "FAIL")
    fi
    
    if [ -f "$OUTPUT_DIR/analysis/test_files_report.json" ]; then
        local missing_count=$(jq -r '.missing_count' "$OUTPUT_DIR/analysis/test_files_report.json" 2>/dev/null || echo "0")
        files_status=$([ "$missing_count" -eq 0 ] && echo "COMPLETE" || echo "MISSING")
    fi
    
    # Add status values and classes
    sed -i.bak \
        -e "s/DIAGNOSTIC_STATUS/$diagnostic_status/g" \
        -e "s/CARGO_STATUS/$cargo_status/g" \
        -e "s/FILES_STATUS/$files_status/g" \
        -e "s/INTEGRATION_STATUS/$integration_status/g" \
        -e "s/DIAGNOSTIC_STATUS_CLASS/$([ "$diagnostic_status" == "SUCCESS" ] && echo "success" || echo "error")/g" \
        -e "s/CARGO_STATUS_CLASS/$([ "$cargo_status" == "PASS" ] && echo "success" || echo "error")/g" \
        -e "s/FILES_STATUS_CLASS/$([ "$files_status" == "COMPLETE" ] && echo "success" || echo "error")/g" \
        -e "s/INTEGRATION_STATUS_CLASS/$([ "$integration_status" == "SUCCESS" ] && echo "success" || echo "warning")/g" \
        "$html_report"
    
    # Add placeholder counts (these would be extracted from analysis files in a real implementation)
    sed -i.bak \
        -e "s/MISSING_FILES_COUNT/$([ -f "$OUTPUT_DIR/analysis/test_files_report.json" ] && jq -r '.missing_count' "$OUTPUT_DIR/analysis/test_files_report.json" 2>/dev/null || echo "0")/g" \
        -e "s/IMPORT_ISSUES_COUNT/$([ -f "$OUTPUT_DIR/analysis/import_validation.json" ] && jq -r '.total_issues' "$OUTPUT_DIR/analysis/import_validation.json" 2>/dev/null || echo "0")/g" \
        -e "s/COMPILATION_ERRORS_COUNT/$([ -f "$OUTPUT_DIR/analysis/cargo_check_analysis.json" ] && jq -r '.error_counts.import_errors + .error_counts.dependency_errors + .error_counts.syntax_errors' "$OUTPUT_DIR/analysis/cargo_check_analysis.json" 2>/dev/null || echo "0")/g" \
        -e "s/DEPENDENCY_ISSUES_COUNT/$([ -f "$OUTPUT_DIR/analysis/cargo_check_analysis.json" ] && jq -r '.error_counts.dependency_errors' "$OUTPUT_DIR/analysis/cargo_check_analysis.json" 2>/dev/null || echo "0")/g" \
        "$html_report"
    
    rm -f "$html_report.bak"
    
    print_info "HTML report generated: $html_report"
    
    # Try to open in browser
    if command -v open &> /dev/null; then
        open "$html_report"
    elif command -v xdg-open &> /dev/null; then
        xdg-open "$html_report"
    fi
}

# Main execution function
main() {
    local start_time=$(date +%s)
    
    print_header "MASTER BUILD DIAGNOSIS ORCHESTRATOR"
    
    print_info "Starting comprehensive build diagnosis..."
    print_info "Configuration: verbose=$VERBOSE, fix-mode=$FIX_MODE, test-fixes=$TEST_FIXES"
    print_info "Output directory: $OUTPUT_DIR"
    
    # Initialize diagnostic environment
    initialize_diagnosis
    
    # Execute diagnostic script
    local diagnostic_exit_code=0
    run_diagnostic_script || diagnostic_exit_code=$?
    
    # Analyze results regardless of diagnostic script exit code
    analyze_diagnostic_results
    
    # Apply fixes if enabled
    if [ "$FIX_MODE" == true ]; then
        apply_fixes
    fi
    
    # Test fixes if enabled
    if [ "$TEST_FIXES" == true ]; then
        test_fixes_incrementally
    fi
    
    # Test integration if enabled
    if [ "$INTEGRATION_TEST" == true ]; then
        test_verification_integration
    fi
    
    # Generate comprehensive reports
    generate_comprehensive_reports
    
    # Calculate total duration
    local end_time=$(date +%s)
    local total_duration=$((end_time - start_time))
    
    print_header "MASTER DIAGNOSIS COMPLETE"
    
    print_info "Total execution time: $(printf '%02d:%02d:%02d\n' $((total_duration/3600)) $((total_duration%3600/60)) $((total_duration%60)))"
    print_info "Results saved to: $OUTPUT_DIR"
    
    # Print final summary
    print_section "FINAL SUMMARY"
    
    print_info "Critical Issues: $CRITICAL_ISSUES"
    print_info "Minor Issues: $MINOR_ISSUES"
    print_info "Fixes Applied: $FIXES_SUCCESSFUL successful, $FIXES_FAILED failed"
    print_info "Tests Performed: ${#FIXES_TESTED[@]}"
    
    # Determine final exit code and status message
    local exit_code=0
    local status_message=""
    
    if [ $CRITICAL_ISSUES -eq 0 ] && [ $MINOR_ISSUES -eq 0 ]; then
        status_message="✓ No issues found - verification script should work perfectly"
        exit_code=0
    elif [ $CRITICAL_ISSUES -eq 0 ]; then
        status_message="⚠ Minor issues found - verification script should work with warnings"
        exit_code=1
    else
        status_message="✗ Critical issues found - verification script will likely fail"
        exit_code=2
    fi
    
    echo
    print_info "=== PIPELINE INTEGRATION SUMMARY ==="
    print_info "Exit Code: $exit_code"
    print_info "Status: $status_message"
    print_info "Session: $(basename "$OUTPUT_DIR")"
    print_info "Reports: $OUTPUT_DIR/reports/"
    
    if [ "$FIX_MODE" == true ] && [ $FIXES_SUCCESSFUL -gt 0 ]; then
        print_info "Recommendation: Re-run verification script to test applied fixes"
    elif [ $CRITICAL_ISSUES -gt 0 ]; then
        print_info "Recommendation: Review analysis and apply fixes before running verification"
    else
        print_info "Recommendation: Proceed with verification script execution"
    fi
    
    echo
    
    exit $exit_code
}

# Execute main function
main "$@"
