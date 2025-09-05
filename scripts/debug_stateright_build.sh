#!/bin/bash

#############################################################################
# Stateright Build Diagnostic Script
#
# This script diagnoses build failures in the Stateright verification by:
# - Running detailed cargo commands with verbose output
# - Checking for missing test files expected by the verification script
# - Validating imports and dependencies
# - Generating a comprehensive diagnostic report
#
# Usage: ./debug_stateright_build.sh [OPTIONS]
#   --verbose           Enable verbose output
#   --output DIR        Output directory for diagnostic files
#   --check-only        Only run cargo check, skip test listing
#   --full-analysis     Run complete analysis including dependency tree
#
# Examples:
#   ./debug_stateright_build.sh --verbose
#   ./debug_stateright_build.sh --output /tmp/diagnosis --full-analysis
#############################################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STATERIGHT_DIR="$PROJECT_DIR/stateright"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="$PROJECT_DIR/diagnosis/build_${TIMESTAMP}"

# Default values
VERBOSE=false
CHECK_ONLY=false
FULL_ANALYSIS=false

# Expected test files from verification script analysis
EXPECTED_TEST_FILES=(
    "safety_properties"
    "liveness_properties"
    "byzantine_resilience"
    "integration_tests"
    "economic_model"
    "vrf_leader_selection"
    "adaptive_timeouts"
    "cross_validation"
)

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
        --check-only)
            CHECK_ONLY=true
            shift
            ;;
        --full-analysis)
            FULL_ANALYSIS=true
            shift
            ;;
        -h|--help)
            grep "^#" "$0" | sed 's/^#//' | head -20
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Helper functions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  ${CYAN}$1${BLUE}${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo
}

print_section() {
    echo
    echo -e "${MAGENTA}>>> $1${NC}"
    echo -e "${MAGENTA}$(printf '%.0s─' {1..60})${NC}"
}

verbose_log() {
    if [ "$VERBOSE" == true ]; then
        echo -e "${CYAN}[VERBOSE]${NC} $1"
    fi
}

# Initialize diagnostic environment
initialize_diagnosis() {
    print_header "STATERIGHT BUILD DIAGNOSIS"
    
    print_info "Initializing diagnostic environment..."
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Create diagnostic log
    DIAGNOSTIC_LOG="$OUTPUT_DIR/diagnostic.log"
    exec > >(tee -a "$DIAGNOSTIC_LOG")
    exec 2>&1
    
    print_info "Diagnostic session: $(basename "$OUTPUT_DIR")"
    print_info "Output directory: $OUTPUT_DIR"
    print_info "Stateright directory: $STATERIGHT_DIR"
    
    # Validate basic setup
    if [ ! -d "$STATERIGHT_DIR" ]; then
        print_error "Stateright directory not found: $STATERIGHT_DIR"
        exit 1
    fi
    
    if [ ! -f "$STATERIGHT_DIR/Cargo.toml" ]; then
        print_error "Cargo.toml not found in Stateright directory"
        exit 1
    fi
    
    # Check Rust installation
    if ! command -v cargo &> /dev/null; then
        print_error "Rust/Cargo not found. Please install Rust first."
        exit 1
    fi
    
    print_info "Environment validation complete"
}

# Check for missing test files
check_test_files() {
    print_section "Checking Test Files"
    
    local tests_dir="$STATERIGHT_DIR/tests"
    local missing_files=()
    local existing_files=()
    
    print_info "Expected test files from verification script:"
    
    for test_file in "${EXPECTED_TEST_FILES[@]}"; do
        local file_path="$tests_dir/${test_file}.rs"
        if [ -f "$file_path" ]; then
            print_info "  ✓ $test_file.rs (exists)"
            existing_files+=("$test_file")
        else
            print_warn "  ✗ $test_file.rs (missing)"
            missing_files+=("$test_file")
        fi
    done
    
    # Check for unexpected test files
    print_info "Scanning for existing test files..."
    if [ -d "$tests_dir" ]; then
        for file in "$tests_dir"/*.rs; do
            if [ -f "$file" ]; then
                local basename=$(basename "$file" .rs)
                if [[ ! " ${EXPECTED_TEST_FILES[@]} " =~ " ${basename} " ]]; then
                    print_info "  ? $basename.rs (unexpected)"
                fi
            fi
        done
    else
        print_warn "Tests directory does not exist: $tests_dir"
    fi
    
    # Generate test files report
    cat > "$OUTPUT_DIR/test_files_report.json" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "tests_directory": "$tests_dir",
    "expected_files": [$(printf '"%s",' "${EXPECTED_TEST_FILES[@]}" | sed 's/,$//')],
    "existing_files": [$(printf '"%s",' "${existing_files[@]}" | sed 's/,$//')],
    "missing_files": [$(printf '"%s",' "${missing_files[@]}" | sed 's/,$//')],
    "missing_count": ${#missing_files[@]},
    "existing_count": ${#existing_files[@]}
}
EOF
    
    print_info "Missing files: ${#missing_files[@]}"
    print_info "Existing files: ${#existing_files[@]}"
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        print_warn "Missing test files will cause verification script to fail"
        return 1
    fi
    
    return 0
}

# Run cargo check with detailed output
run_cargo_check() {
    print_section "Running Cargo Check"
    
    cd "$STATERIGHT_DIR"
    
    print_info "Running cargo check --verbose..."
    
    # Run cargo check with verbose output
    local check_output="$OUTPUT_DIR/cargo_check_verbose.log"
    local check_exit_code=0
    
    cargo check --verbose > "$check_output" 2>&1 || check_exit_code=$?
    
    if [ $check_exit_code -eq 0 ]; then
        print_info "✓ Cargo check passed"
    else
        print_error "✗ Cargo check failed (exit code: $check_exit_code)"
        
        # Extract and display key errors
        print_info "Key compilation errors:"
        grep -E "(error\[|error:|cannot find|unresolved import)" "$check_output" | head -10 | while read -r line; do
            echo "  $line"
        done
    fi
    
    # Analyze specific error patterns
    local import_errors=$(grep -c "unresolved import\|cannot find" "$check_output" || echo "0")
    local dependency_errors=$(grep -c "failed to resolve\|couldn't read" "$check_output" || echo "0")
    local syntax_errors=$(grep -c "expected.*found\|unexpected token" "$check_output" || echo "0")
    
    cat > "$OUTPUT_DIR/cargo_check_analysis.json" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "exit_code": $check_exit_code,
    "success": $([ $check_exit_code -eq 0 ] && echo "true" || echo "false"),
    "error_counts": {
        "import_errors": $import_errors,
        "dependency_errors": $dependency_errors,
        "syntax_errors": $syntax_errors
    },
    "log_file": "$check_output"
}
EOF
    
    print_info "Import errors: $import_errors"
    print_info "Dependency errors: $dependency_errors"
    print_info "Syntax errors: $syntax_errors"
    
    cd "$PROJECT_DIR"
    return $check_exit_code
}

# List available tests
list_available_tests() {
    print_section "Listing Available Tests"
    
    if [ "$CHECK_ONLY" == true ]; then
        print_info "Skipping test listing (--check-only specified)"
        return 0
    fi
    
    cd "$STATERIGHT_DIR"
    
    print_info "Running cargo test --list..."
    
    local test_list_output="$OUTPUT_DIR/cargo_test_list.log"
    local test_list_exit_code=0
    
    cargo test --list > "$test_list_output" 2>&1 || test_list_exit_code=$?
    
    if [ $test_list_exit_code -eq 0 ]; then
        print_info "✓ Test listing successful"
        
        # Count available tests
        local unit_tests=$(grep -c ": test$" "$test_list_output" || echo "0")
        local integration_tests=$(grep -c "tests/" "$test_list_output" || echo "0")
        local doc_tests=$(grep -c "src/" "$test_list_output" || echo "0")
        
        print_info "Unit tests: $unit_tests"
        print_info "Integration tests: $integration_tests"
        print_info "Doc tests: $doc_tests"
        
        # Check for expected test modules
        print_info "Checking for expected test modules:"
        for test_file in "${EXPECTED_TEST_FILES[@]}"; do
            if grep -q "$test_file" "$test_list_output"; then
                print_info "  ✓ $test_file tests found"
            else
                print_warn "  ✗ $test_file tests not found"
            fi
        done
        
    else
        print_error "✗ Test listing failed (exit code: $test_list_exit_code)"
        
        # Show compilation errors that prevent test listing
        print_info "Compilation errors preventing test listing:"
        grep -E "(error\[|error:|cannot find)" "$test_list_output" | head -5 | while read -r line; do
            echo "  $line"
        done
    fi
    
    cat > "$OUTPUT_DIR/test_listing_analysis.json" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "exit_code": $test_list_exit_code,
    "success": $([ $test_list_exit_code -eq 0 ] && echo "true" || echo "false"),
    "test_counts": {
        "unit_tests": $([ $test_list_exit_code -eq 0 ] && echo "$unit_tests" || echo "0"),
        "integration_tests": $([ $test_list_exit_code -eq 0 ] && echo "$integration_tests" || echo "0"),
        "doc_tests": $([ $test_list_exit_code -eq 0 ] && echo "$doc_tests" || echo "0")
    },
    "expected_modules_found": [
$(if [ $test_list_exit_code -eq 0 ]; then
    for test_file in "${EXPECTED_TEST_FILES[@]}"; do
        if grep -q "$test_file" "$test_list_output"; then
            echo "        \"$test_file\","
        fi
    done | sed 's/,$//'
fi)
    ],
    "log_file": "$test_list_output"
}
EOF
    
    cd "$PROJECT_DIR"
    return $test_list_exit_code
}

# Validate imports and dependencies
validate_imports() {
    print_section "Validating Imports and Dependencies"
    
    cd "$STATERIGHT_DIR"
    
    # Check dependency tree
    print_info "Analyzing dependency tree..."
    local deps_output="$OUTPUT_DIR/cargo_tree.log"
    cargo tree > "$deps_output" 2>&1 || true
    
    # Check for specific import issues in source files
    print_info "Checking source file imports..."
    local import_issues=()
    
    # Check main library file
    if [ -f "src/lib.rs" ]; then
        verbose_log "Checking src/lib.rs imports"
        if grep -q "local_stateright" "src/lib.rs"; then
            import_issues+=("src/lib.rs: contains 'local_stateright' import")
        fi
    fi
    
    # Check stateright module
    if [ -f "src/stateright.rs" ]; then
        verbose_log "Checking src/stateright.rs imports"
        # Add specific checks for stateright.rs
    fi
    
    # Check test files for import issues
    if [ -d "tests" ]; then
        for test_file in tests/*.rs; do
            if [ -f "$test_file" ]; then
                verbose_log "Checking $(basename "$test_file") imports"
                if grep -q "local_stateright" "$test_file"; then
                    import_issues+=("$test_file: contains 'local_stateright' import")
                fi
                if grep -q "use stateright::" "$test_file" && grep -q "extern crate stateright" "$test_file"; then
                    import_issues+=("$test_file: potential naming conflict with external stateright crate")
                fi
            fi
        done
    fi
    
    # Check Cargo.toml for dependency issues
    print_info "Validating Cargo.toml dependencies..."
    local cargo_issues=()
    
    if ! grep -q "stateright.*=" "Cargo.toml"; then
        cargo_issues+=("Missing stateright dependency in Cargo.toml")
    fi
    
    # Generate import validation report
    cat > "$OUTPUT_DIR/import_validation.json" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "import_issues": [$(printf '"%s",' "${import_issues[@]}" | sed 's/,$//')],
    "cargo_issues": [$(printf '"%s",' "${cargo_issues[@]}" | sed 's/,$//')],
    "total_issues": $((${#import_issues[@]} + ${#cargo_issues[@]})),
    "dependency_tree_file": "$deps_output"
}
EOF
    
    print_info "Import issues found: ${#import_issues[@]}"
    print_info "Cargo.toml issues found: ${#cargo_issues[@]}"
    
    if [ ${#import_issues[@]} -gt 0 ]; then
        print_warn "Import issues detected:"
        for issue in "${import_issues[@]}"; do
            echo "  - $issue"
        done
    fi
    
    if [ ${#cargo_issues[@]} -gt 0 ]; then
        print_warn "Cargo.toml issues detected:"
        for issue in "${cargo_issues[@]}"; do
            echo "  - $issue"
        done
    fi
    
    cd "$PROJECT_DIR"
    return $((${#import_issues[@]} + ${#cargo_issues[@]}))
}

# Run full dependency analysis
run_full_analysis() {
    if [ "$FULL_ANALYSIS" != true ]; then
        return 0
    fi
    
    print_section "Running Full Dependency Analysis"
    
    cd "$STATERIGHT_DIR"
    
    # Check for outdated dependencies
    print_info "Checking for outdated dependencies..."
    cargo outdated > "$OUTPUT_DIR/cargo_outdated.log" 2>&1 || true
    
    # Audit dependencies for security issues
    print_info "Running security audit..."
    cargo audit > "$OUTPUT_DIR/cargo_audit.log" 2>&1 || true
    
    # Check feature flags
    print_info "Analyzing feature flags..."
    cargo check --all-features > "$OUTPUT_DIR/cargo_check_all_features.log" 2>&1 || true
    
    # Generate metadata
    print_info "Extracting package metadata..."
    cargo metadata --format-version 1 > "$OUTPUT_DIR/cargo_metadata.json" 2>&1 || true
    
    cd "$PROJECT_DIR"
}

# Simulate verification script test execution
simulate_verification_tests() {
    print_section "Simulating Verification Script Test Execution"
    
    cd "$STATERIGHT_DIR"
    
    local simulation_results=()
    
    print_info "Simulating test execution for each expected scenario..."
    
    for test_file in "${EXPECTED_TEST_FILES[@]}"; do
        print_info "Testing scenario: $test_file"
        
        local test_output="$OUTPUT_DIR/simulate_${test_file}.log"
        local test_exit_code=0
        
        # Try to run the specific test
        timeout 30 cargo test --test "$test_file" --no-run > "$test_output" 2>&1 || test_exit_code=$?
        
        if [ $test_exit_code -eq 0 ]; then
            print_info "  ✓ $test_file: compilation successful"
            simulation_results+=("$test_file:COMPILE_OK")
        elif [ $test_exit_code -eq 124 ]; then
            print_warn "  ⚠ $test_file: compilation timeout"
            simulation_results+=("$test_file:TIMEOUT")
        else
            print_error "  ✗ $test_file: compilation failed"
            simulation_results+=("$test_file:COMPILE_FAIL")
            
            # Extract key error
            local key_error=$(grep -E "(error\[|cannot find)" "$test_output" | head -1 || echo "Unknown error")
            verbose_log "    Error: $key_error"
        fi
    done
    
    # Generate simulation report
    cat > "$OUTPUT_DIR/verification_simulation.json" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "scenarios_tested": [$(printf '"%s",' "${EXPECTED_TEST_FILES[@]}" | sed 's/,$//')],
    "results": {
$(for i in "${!EXPECTED_TEST_FILES[@]}"; do
    scenario="${EXPECTED_TEST_FILES[$i]}"
    result="${simulation_results[$i]#*:}"
    echo "        \"$scenario\": \"$result\""
    if [ $i -lt $((${#EXPECTED_TEST_FILES[@]} - 1)) ]; then echo ","; fi
done)
    },
    "summary": {
        "compile_ok": $(echo "${simulation_results[@]}" | grep -o "COMPILE_OK" | wc -l),
        "compile_fail": $(echo "${simulation_results[@]}" | grep -o "COMPILE_FAIL" | wc -l),
        "timeout": $(echo "${simulation_results[@]}" | grep -o "TIMEOUT" | wc -l)
    }
}
EOF
    
    local compile_ok=$(echo "${simulation_results[@]}" | grep -o "COMPILE_OK" | wc -l)
    local compile_fail=$(echo "${simulation_results[@]}" | grep -o "COMPILE_FAIL" | wc -l)
    
    print_info "Simulation results: $compile_ok successful, $compile_fail failed"
    
    cd "$PROJECT_DIR"
    return $compile_fail
}

# Generate comprehensive diagnostic report
generate_diagnostic_report() {
    print_section "Generating Comprehensive Diagnostic Report"
    
    local report_file="$OUTPUT_DIR/diagnostic_report.html"
    
    # Collect all analysis results
    local test_files_missing=0
    local cargo_check_failed=false
    local import_issues=0
    local compile_failures=0
    
    if [ -f "$OUTPUT_DIR/test_files_report.json" ]; then
        test_files_missing=$(jq -r '.missing_count' "$OUTPUT_DIR/test_files_report.json" 2>/dev/null || echo "0")
    fi
    
    if [ -f "$OUTPUT_DIR/cargo_check_analysis.json" ]; then
        cargo_check_failed=$(jq -r '.success | not' "$OUTPUT_DIR/cargo_check_analysis.json" 2>/dev/null || echo "true")
    fi
    
    if [ -f "$OUTPUT_DIR/import_validation.json" ]; then
        import_issues=$(jq -r '.total_issues' "$OUTPUT_DIR/import_validation.json" 2>/dev/null || echo "0")
    fi
    
    if [ -f "$OUTPUT_DIR/verification_simulation.json" ]; then
        compile_failures=$(jq -r '.summary.compile_fail' "$OUTPUT_DIR/verification_simulation.json" 2>/dev/null || echo "0")
    fi
    
    # Generate HTML report
    cat > "$report_file" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Stateright Build Diagnostic Report</title>
    <style>
        body {
            font-family: 'Segoe UI', Arial, sans-serif;
            margin: 0;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 10px;
            padding: 30px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
        }
        h1 { color: #333; border-bottom: 3px solid #667eea; padding-bottom: 10px; }
        h2 { color: #667eea; margin-top: 30px; }
        .summary {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin: 20px 0;
        }
        .card {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 8px;
            border-left: 4px solid #667eea;
        }
        .card h3 { margin-top: 0; color: #495057; }
        .success { color: #28a745; font-weight: bold; }
        .warning { color: #ffc107; font-weight: bold; }
        .error { color: #dc3545; font-weight: bold; }
        .issue-list {
            background: #f8f9fa;
            padding: 15px;
            border-radius: 5px;
            margin: 10px 0;
        }
        .issue-list ul { margin: 0; padding-left: 20px; }
        .recommendation {
            background: #e7f3ff;
            border-left: 4px solid #007bff;
            padding: 15px;
            margin: 15px 0;
        }
        pre {
            background: #f4f4f4;
            padding: 15px;
            border-radius: 5px;
            overflow-x: auto;
            font-size: 12px;
        }
        .footer {
            margin-top: 40px;
            padding-top: 20px;
            border-top: 1px solid #dee2e6;
            text-align: center;
            color: #6c757d;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔧 Stateright Build Diagnostic Report</h1>
        
        <div class="summary">
            <div class="card">
                <h3>Test Files</h3>
                <p class="TEST_FILES_CLASS">MISSING_FILES missing</p>
            </div>
            <div class="card">
                <h3>Cargo Check</h3>
                <p class="CARGO_CHECK_CLASS">CARGO_CHECK_STATUS</p>
            </div>
            <div class="card">
                <h3>Import Issues</h3>
                <p class="IMPORT_CLASS">IMPORT_ISSUES issues</p>
            </div>
            <div class="card">
                <h3>Compilation</h3>
                <p class="COMPILE_CLASS">COMPILE_FAILURES failures</p>
            </div>
        </div>
        
        <h2>🎯 Root Cause Analysis</h2>
        
        <div class="issue-list">
            <h3>Primary Issues Identified:</h3>
            <ul>
                PRIMARY_ISSUES
            </ul>
        </div>
        
        <h2>📋 Detailed Findings</h2>
        
        <h3>Missing Test Files</h3>
        <p>The verification script expects the following test files that are currently missing:</p>
        <div class="issue-list">
            MISSING_TEST_FILES_LIST
        </div>
        
        <h3>Compilation Errors</h3>
        <p>Key compilation issues preventing successful build:</p>
        <div class="issue-list">
            COMPILATION_ERRORS
        </div>
        
        <h3>Import and Dependency Issues</h3>
        <p>Problems with module imports and dependency resolution:</p>
        <div class="issue-list">
            IMPORT_DEPENDENCY_ISSUES
        </div>
        
        <h2>🛠️ Recommended Fixes</h2>
        
        <div class="recommendation">
            <h4>1. Create Missing Test Files</h4>
            <p>Create the missing test files with basic placeholder implementations:</p>
            <pre>MISSING_FILES_COMMANDS</pre>
        </div>
        
        <div class="recommendation">
            <h4>2. Fix Import Issues</h4>
            <p>Update import statements in existing files:</p>
            <pre>IMPORT_FIX_COMMANDS</pre>
        </div>
        
        <div class="recommendation">
            <h4>3. Resolve Compilation Errors</h4>
            <p>Address the compilation errors found:</p>
            <pre>COMPILATION_FIX_COMMANDS</pre>
        </div>
        
        <h2>📊 Next Steps</h2>
        
        <ol>
            <li>Create the missing test files with basic implementations</li>
            <li>Fix the import issues in existing files</li>
            <li>Run cargo check to verify compilation</li>
            <li>Test the verification script with the fixes</li>
            <li>Iterate on any remaining issues</li>
        </ol>
        
        <div class="footer">
            <p>Generated by Stateright Build Diagnostic Tool | Session: SESSION_ID</p>
        </div>
    </div>
</body>
</html>
EOF
    
    # Replace placeholders with actual values
    local primary_issues=""
    if [ "$test_files_missing" -gt 0 ]; then
        primary_issues+="<li>Missing $test_files_missing expected test files</li>"
    fi
    if [ "$cargo_check_failed" == "true" ]; then
        primary_issues+="<li>Cargo compilation failures</li>"
    fi
    if [ "$import_issues" -gt 0 ]; then
        primary_issues+="<li>$import_issues import/dependency issues</li>"
    fi
    if [ "$compile_failures" -gt 0 ]; then
        primary_issues+="<li>$compile_failures test compilation failures</li>"
    fi
    
    # Generate missing files commands
    local missing_files_commands=""
    for test_file in "${EXPECTED_TEST_FILES[@]}"; do
        if [ ! -f "$STATERIGHT_DIR/tests/${test_file}.rs" ]; then
            missing_files_commands+="touch tests/${test_file}.rs\n"
        fi
    done
    
    sed -i.bak \
        -e "s/MISSING_FILES/$test_files_missing/g" \
        -e "s/CARGO_CHECK_STATUS/$([ "$cargo_check_failed" == "true" ] && echo "FAILED" || echo "PASSED")/g" \
        -e "s/IMPORT_ISSUES/$import_issues/g" \
        -e "s/COMPILE_FAILURES/$compile_failures/g" \
        -e "s/PRIMARY_ISSUES/$primary_issues/g" \
        -e "s/MISSING_FILES_COMMANDS/$missing_files_commands/g" \
        -e "s/SESSION_ID/$(basename "$OUTPUT_DIR")/g" \
        "$report_file"
    
    # Add CSS classes based on severity
    local test_files_class=$([ "$test_files_missing" -eq 0 ] && echo "success" || echo "error")
    local cargo_check_class=$([ "$cargo_check_failed" == "false" ] && echo "success" || echo "error")
    local import_class=$([ "$import_issues" -eq 0 ] && echo "success" || echo "warning")
    local compile_class=$([ "$compile_failures" -eq 0 ] && echo "success" || echo "error")
    
    sed -i.bak \
        -e "s/TEST_FILES_CLASS/$test_files_class/g" \
        -e "s/CARGO_CHECK_CLASS/$cargo_check_class/g" \
        -e "s/IMPORT_CLASS/$import_class/g" \
        -e "s/COMPILE_CLASS/$compile_class/g" \
        "$report_file"
    
    rm -f "$report_file.bak"
    
    print_info "Diagnostic report generated: $report_file"
    
    # Try to open in browser
    if command -v open &> /dev/null; then
        open "$report_file"
    elif command -v xdg-open &> /dev/null; then
        xdg-open "$report_file"
    fi
}

# Generate summary and recommendations
generate_summary() {
    print_section "Generating Summary and Recommendations"
    
    # Collect all results
    local issues_found=0
    local critical_issues=0
    
    # Count issues from various checks
    if [ -f "$OUTPUT_DIR/test_files_report.json" ]; then
        local missing_files=$(jq -r '.missing_count' "$OUTPUT_DIR/test_files_report.json" 2>/dev/null || echo "0")
        issues_found=$((issues_found + missing_files))
        if [ "$missing_files" -gt 0 ]; then
            critical_issues=$((critical_issues + 1))
        fi
    fi
    
    if [ -f "$OUTPUT_DIR/cargo_check_analysis.json" ]; then
        local check_failed=$(jq -r '.success | not' "$OUTPUT_DIR/cargo_check_analysis.json" 2>/dev/null || echo "true")
        if [ "$check_failed" == "true" ]; then
            critical_issues=$((critical_issues + 1))
        fi
    fi
    
    if [ -f "$OUTPUT_DIR/import_validation.json" ]; then
        local import_issues=$(jq -r '.total_issues' "$OUTPUT_DIR/import_validation.json" 2>/dev/null || echo "0")
        issues_found=$((issues_found + import_issues))
    fi
    
    # Generate final summary
    cat > "$OUTPUT_DIR/diagnostic_summary.txt" << EOF
================================================================================
STATERIGHT BUILD DIAGNOSTIC SUMMARY
================================================================================

Session: $(basename "$OUTPUT_DIR")
Date: $(date)
Stateright Directory: $STATERIGHT_DIR

DIAGNOSIS RESULTS:
-----------------
Total Issues Found: $issues_found
Critical Issues: $critical_issues

TEST FILES STATUS:
-----------------
$(if [ -f "$OUTPUT_DIR/test_files_report.json" ]; then
    echo "Expected Files: $(jq -r '.expected_files | length' "$OUTPUT_DIR/test_files_report.json")"
    echo "Missing Files: $(jq -r '.missing_count' "$OUTPUT_DIR/test_files_report.json")"
    echo "Existing Files: $(jq -r '.existing_count' "$OUTPUT_DIR/test_files_report.json")"
    echo ""
    echo "Missing Test Files:"
    jq -r '.missing_files[]' "$OUTPUT_DIR/test_files_report.json" | sed 's/^/  - /'
else
    echo "Test file analysis not completed"
fi)

COMPILATION STATUS:
------------------
$(if [ -f "$OUTPUT_DIR/cargo_check_analysis.json" ]; then
    echo "Cargo Check: $(jq -r '.success' "$OUTPUT_DIR/cargo_check_analysis.json" | sed 's/true/PASSED/;s/false/FAILED/')"
    echo "Import Errors: $(jq -r '.error_counts.import_errors' "$OUTPUT_DIR/cargo_check_analysis.json")"
    echo "Dependency Errors: $(jq -r '.error_counts.dependency_errors' "$OUTPUT_DIR/cargo_check_analysis.json")"
    echo "Syntax Errors: $(jq -r '.error_counts.syntax_errors' "$OUTPUT_DIR/cargo_check_analysis.json")"
else
    echo "Compilation analysis not completed"
fi)

VERIFICATION SIMULATION:
-----------------------
$(if [ -f "$OUTPUT_DIR/verification_simulation.json" ]; then
    echo "Scenarios Tested: $(jq -r '.scenarios_tested | length' "$OUTPUT_DIR/verification_simulation.json")"
    echo "Compilation Successful: $(jq -r '.summary.compile_ok' "$OUTPUT_DIR/verification_simulation.json")"
    echo "Compilation Failed: $(jq -r '.summary.compile_fail' "$OUTPUT_DIR/verification_simulation.json")"
    echo "Timeouts: $(jq -r '.summary.timeout' "$OUTPUT_DIR/verification_simulation.json")"
else
    echo "Verification simulation not completed"
fi)

ROOT CAUSE ANALYSIS:
-------------------
$(if [ "$critical_issues" -gt 0 ]; then
    echo "CRITICAL: The verification script will fail due to:"
    if [ -f "$OUTPUT_DIR/test_files_report.json" ] && [ "$(jq -r '.missing_count' "$OUTPUT_DIR/test_files_report.json")" -gt 0 ]; then
        echo "  1. Missing test files that the script expects to run"
    fi
    if [ -f "$OUTPUT_DIR/cargo_check_analysis.json" ] && [ "$(jq -r '.success' "$OUTPUT_DIR/cargo_check_analysis.json")" == "false" ]; then
        echo "  2. Compilation failures preventing test execution"
    fi
else
    echo "No critical issues found. The build should work with minor fixes."
fi)

IMMEDIATE ACTIONS REQUIRED:
--------------------------
$(if [ -f "$OUTPUT_DIR/test_files_report.json" ] && [ "$(jq -r '.missing_count' "$OUTPUT_DIR/test_files_report.json")" -gt 0 ]; then
    echo "1. CREATE MISSING TEST FILES:"
    jq -r '.missing_files[]' "$OUTPUT_DIR/test_files_report.json" | while read -r file; do
        echo "   touch $STATERIGHT_DIR/tests/${file}.rs"
    done
    echo ""
fi)
$(if [ -f "$OUTPUT_DIR/import_validation.json" ] && [ "$(jq -r '.total_issues' "$OUTPUT_DIR/import_validation.json")" -gt 0 ]; then
    echo "2. FIX IMPORT ISSUES:"
    echo "   - Replace 'local_stateright' with 'crate::stateright' in test files"
    echo "   - Resolve naming conflicts with external stateright crate"
    echo ""
fi)
$(if [ -f "$OUTPUT_DIR/cargo_check_analysis.json" ] && [ "$(jq -r '.success' "$OUTPUT_DIR/cargo_check_analysis.json")" == "false" ]; then
    echo "3. RESOLVE COMPILATION ERRORS:"
    echo "   - Check detailed errors in: $OUTPUT_DIR/cargo_check_verbose.log"
    echo "   - Fix syntax and dependency issues"
    echo ""
fi)

NEXT STEPS:
----------
1. Review the detailed diagnostic report: $OUTPUT_DIR/diagnostic_report.html
2. Implement the recommended fixes above
3. Re-run this diagnostic script to verify fixes
4. Test the verification script: ./stateright_verify.sh --config small
5. Iterate on any remaining issues

FILES GENERATED:
---------------
• Diagnostic Log: $OUTPUT_DIR/diagnostic.log
• Test Files Report: $OUTPUT_DIR/test_files_report.json
• Cargo Check Analysis: $OUTPUT_DIR/cargo_check_analysis.json
• Import Validation: $OUTPUT_DIR/import_validation.json
• Verification Simulation: $OUTPUT_DIR/verification_simulation.json
• HTML Report: $OUTPUT_DIR/diagnostic_report.html
• Summary: $OUTPUT_DIR/diagnostic_summary.txt

INTEGRATION:
-----------
This diagnostic script should be run before attempting the verification script.
Exit code indicates severity: 0=no issues, 1=minor issues, 2=critical issues

================================================================================
EOF
    
    cat "$OUTPUT_DIR/diagnostic_summary.txt"
    
    # Determine exit code
    if [ "$critical_issues" -gt 0 ]; then
        return 2  # Critical issues
    elif [ "$issues_found" -gt 0 ]; then
        return 1  # Minor issues
    else
        return 0  # No issues
    fi
}

# Main execution
main() {
    local start_time=$(date +%s)
    
    # Initialize diagnostic environment
    initialize_diagnosis
    
    # Run all diagnostic checks
    local exit_code=0
    
    # Check for missing test files
    check_test_files || exit_code=1
    
    # Run cargo check
    run_cargo_check || exit_code=1
    
    # List available tests
    list_available_tests || exit_code=1
    
    # Validate imports and dependencies
    validate_imports || exit_code=1
    
    # Run full analysis if requested
    run_full_analysis
    
    # Simulate verification script execution
    simulate_verification_tests || exit_code=1
    
    # Generate comprehensive report
    generate_diagnostic_report
    
    # Generate summary and determine final exit code
    generate_summary || exit_code=$?
    
    # Calculate duration
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    print_header "DIAGNOSIS COMPLETE"
    print_info "Total duration: $(printf '%02d:%02d:%02d\n' $((duration/3600)) $((duration%3600/60)) $((duration%60)))"
    print_info "Results saved to: $OUTPUT_DIR"
    
    case $exit_code in
        0)
            print_info "✓ No critical issues found"
            ;;
        1)
            print_warn "⚠ Minor issues found - see report for details"
            ;;
        2)
            print_error "✗ Critical issues found - verification script will fail"
            ;;
    esac
    
    exit $exit_code
}

# Run main function
main "$@"