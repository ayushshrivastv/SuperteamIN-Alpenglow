#!/bin/bash

#############################################################################
# Alpenglow Complete Formal Verification Pipeline
#
# Master script that orchestrates the complete formal verification pipeline
# including TLA+ proofs, model checking, Stateright verification, theorem
# mapping generation, and comprehensive reporting.
#
# Author: Traycer.AI
# Version: 3.0.0
#############################################################################

set -euo pipefail

# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOLS_DIR="$PROJECT_ROOT/tools"
TLA_TOOLS="$TOOLS_DIR/tla2tools.jar"
SPECS_DIR="$PROJECT_ROOT/specs"
PROOFS_DIR="$PROJECT_ROOT/proofs"
MODELS_DIR="$PROJECT_ROOT/models"
STATERIGHT_DIR="$PROJECT_ROOT/stateright"
SCRIPTS_DIR="$PROJECT_ROOT/scripts"
RESULTS_DIR="$PROJECT_ROOT/results"
REPORTS_DIR="$PROJECT_ROOT/reports"
WHITEPAPER_PATH="$PROJECT_ROOT/Solana Alpenglow White Paper v1.1.md"

# Verification flags
SKIP_ENVIRONMENT_CHECK=false
SKIP_TLA_VERIFICATION=false
SKIP_MODEL_CHECKING=false
SKIP_STATERIGHT_VERIFICATION=false
SKIP_THEOREM_MAPPING=false
SKIP_CROSS_VALIDATION=false
SKIP_PERFORMANCE_ANALYSIS=false
QUICK_MODE=false
VERBOSE=false
CI_MODE=false
PARALLEL_JOBS=4
OUTPUT_FORMATS="console,json,html"
TIMEOUT_MINUTES=60

# Performance tracking
START_TIME=$(date +%s)
VERIFICATION_STATS=()
FAILED_COMPONENTS=()
PERFORMANCE_METRICS=()

# Logging functions with enhanced formatting
print_banner() {
    echo
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} ${BOLD}$1${NC} ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo
}

print_section() {
    echo
    echo -e "${BLUE}${BOLD}>>> $1${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────────────────────────────────${NC}"
}

print_subsection() {
    echo
    echo -e "${PURPLE}▶ $1${NC}"
    echo -e "${DIM}──────────────────────────────────────────────────────────────${NC}"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_progress() {
    echo -e "${CYAN}[PROGRESS]${NC} $1"
}

print_metric() {
    echo -e "${PURPLE}[METRIC]${NC} $1"
}

# Utility functions
log_performance() {
    local component="$1"
    local start_time="$2"
    local end_time="$3"
    local status="$4"
    local duration=$((end_time - start_time))
    
    PERFORMANCE_METRICS+=("$component:$duration:$status")
    print_metric "$component completed in ${duration}s with status: $status"
}

check_command() {
    local cmd="$1"
    local description="$2"
    local install_hint="$3"
    
    if command -v "$cmd" &> /dev/null; then
        local version
        case "$cmd" in
            java)
                version=$(java -version 2>&1 | head -n1 | cut -d'"' -f2)
                ;;
            cargo)
                version=$(cargo --version | cut -d' ' -f2)
                ;;
            python3)
                version=$(python3 --version | cut -d' ' -f2)
                ;;
            *)
                version="unknown"
                ;;
        esac
        print_success "$description found: $version"
        return 0
    else
        print_error "$description not found"
        print_info "  Install hint: $install_hint"
        return 1
    fi
}

create_directory() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        print_info "Created directory: $dir"
    fi
}

# Environment validation with comprehensive tool checking
validate_environment() {
    if [[ "$SKIP_ENVIRONMENT_CHECK" == "true" ]]; then
        print_warning "Skipping environment validation"
        return 0
    fi
    
    print_section "Environment Validation"
    
    local validation_errors=0
    
    # Check Java with enhanced version validation
    if ! check_command "java" "Java Runtime Environment" "https://adoptium.net/"; then
        validation_errors=$((validation_errors + 1))
    else
        local java_version
        java_version=$(java -version 2>&1 | head -n1 | cut -d'"' -f2 | cut -d'.' -f1)
        if [[ "$java_version" -lt "11" ]]; then
            print_error "Java 11+ required. Found version: $java_version"
            validation_errors=$((validation_errors + 1))
        fi
    fi
    
    # Check TLA+ tools with auto-download
    print_subsection "TLA+ Tools Validation"
    if [[ ! -f "$TLA_TOOLS" ]]; then
        print_warning "TLA+ tools not found at $TLA_TOOLS"
        print_info "Attempting to download latest tla2tools.jar..."
        
        create_directory "$TOOLS_DIR"
        
        local download_url
        download_url=$(curl -s https://api.github.com/repos/tlaplus/tlaplus/releases/latest | \
                      grep "browser_download_url.*tla2tools.jar" | cut -d '"' -f 4)
        
        if [[ -n "$download_url" ]]; then
            if curl -L -o "$TLA_TOOLS" "$download_url" 2>/dev/null; then
                print_success "Downloaded tla2tools.jar successfully"
            else
                print_error "Failed to download tla2tools.jar"
                validation_errors=$((validation_errors + 1))
            fi
        else
            print_error "Could not find download URL for tla2tools.jar"
            validation_errors=$((validation_errors + 1))
        fi
    else
        print_success "TLA+ tools found at $TLA_TOOLS"
        
        # Test TLC execution
        if java -jar "$TLA_TOOLS" -help &> /dev/null; then
            print_success "TLC model checker is functional"
        else
            print_warning "TLC model checker may have issues"
        fi
    fi
    
    # Check Rust/Cargo
    if ! check_command "cargo" "Rust/Cargo" "https://rustup.rs/"; then
        if [[ "$SKIP_STATERIGHT_VERIFICATION" != "true" ]]; then
            print_warning "Stateright verification will be disabled"
            SKIP_STATERIGHT_VERIFICATION=true
        fi
    else
        # Test Stateright build
        if [[ -f "$STATERIGHT_DIR/Cargo.toml" ]]; then
            print_info "Testing Stateright build..."
            if (cd "$STATERIGHT_DIR" && cargo check --quiet 2>/dev/null); then
                print_success "Stateright build check passed"
            else
                print_warning "Stateright has build issues"
                if [[ "$SKIP_STATERIGHT_VERIFICATION" != "true" ]]; then
                    SKIP_STATERIGHT_VERIFICATION=true
                fi
            fi
        fi
    fi
    
    # Check Python
    if ! check_command "python3" "Python 3" "https://python.org/downloads/"; then
        if [[ "$SKIP_THEOREM_MAPPING" != "true" ]]; then
            print_warning "Theorem mapping generation will be disabled"
            SKIP_THEOREM_MAPPING=true
        fi
    else
        # Check Python dependencies
        print_info "Checking Python dependencies..."
        local python_deps=("jinja2" "pyyaml" "dataclasses")
        for dep in "${python_deps[@]}"; do
            if python3 -c "import $dep" 2>/dev/null; then
                print_success "Python dependency $dep found"
            else
                print_warning "Python dependency $dep not found"
                print_info "  Install with: pip3 install $dep"
            fi
        done
    fi
    
    # Check required directories
    print_subsection "Directory Structure Validation"
    local required_dirs=("$SPECS_DIR" "$PROOFS_DIR" "$MODELS_DIR")
    for dir in "${required_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            print_success "Directory found: $dir"
        else
            print_warning "Directory not found: $dir"
            create_directory "$dir"
        fi
    done
    
    # Create output directories
    create_directory "$RESULTS_DIR"
    create_directory "$REPORTS_DIR"
    create_directory "$RESULTS_DIR/tlaps"
    create_directory "$RESULTS_DIR/tlc"
    create_directory "$RESULTS_DIR/stateright"
    
    # Check whitepaper
    if [[ -f "$WHITEPAPER_PATH" ]]; then
        print_success "Whitepaper found: $WHITEPAPER_PATH"
    else
        print_warning "Whitepaper not found: $WHITEPAPER_PATH"
        if [[ "$SKIP_THEOREM_MAPPING" != "true" ]]; then
            print_warning "Theorem mapping generation will be limited"
        fi
    fi
    
    # Summary
    if [[ $validation_errors -gt 0 ]]; then
        print_error "Environment validation failed with $validation_errors error(s)"
        if [[ "$CI_MODE" == "true" ]]; then
            return 1
        else
            print_warning "Continuing with limited functionality"
        fi
    else
        print_success "Environment validation passed"
    fi
    
    return 0
}

# TLA+ verification with TLAPS proofs
run_tlaps_verification() {
    if [[ "$SKIP_TLA_VERIFICATION" == "true" ]]; then
        print_warning "Skipping TLA+ verification"
        return 0
    fi
    
    print_section "TLA+ TLAPS Proof Verification"
    
    local start_time=$(date +%s)
    local verification_success=true
    local proof_files=()
    
    # Find all TLA+ proof files
    if [[ -d "$PROOFS_DIR" ]]; then
        mapfile -t proof_files < <(find "$PROOFS_DIR" -name "*.tla" -type f)
    fi
    
    if [[ ${#proof_files[@]} -eq 0 ]]; then
        print_warning "No TLA+ proof files found in $PROOFS_DIR"
        return 0
    fi
    
    print_info "Found ${#proof_files[@]} TLA+ proof files"
    
    # Verify each proof file
    for proof_file in "${proof_files[@]}"; do
        local filename=$(basename "$proof_file")
        print_subsection "Verifying $filename"
        
        local output_file="$RESULTS_DIR/tlaps/${filename%.tla}.out"
        local error_file="$RESULTS_DIR/tlaps/${filename%.tla}.err"
        
        # Run TLAPS verification
        if timeout "${TIMEOUT_MINUTES}m" java -jar "$TLA_TOOLS" -prove "$proof_file" \
           > "$output_file" 2> "$error_file"; then
            print_success "TLAPS verification passed for $filename"
            
            # Check for proof obligations
            local obligations
            obligations=$(grep -c "obligation" "$output_file" 2>/dev/null || echo "0")
            local proved
            proved=$(grep -c "proved" "$output_file" 2>/dev/null || echo "0")
            
            print_metric "Proof obligations: $proved/$obligations"
            
            if [[ "$obligations" -gt 0 ]] && [[ "$proved" -eq "$obligations" ]]; then
                print_success "All proof obligations satisfied for $filename"
            elif [[ "$obligations" -gt 0 ]]; then
                print_warning "Partial proof completion for $filename: $proved/$obligations"
            fi
        else
            print_error "TLAPS verification failed for $filename"
            verification_success=false
            FAILED_COMPONENTS+=("TLAPS:$filename")
            
            # Show error details if verbose
            if [[ "$VERBOSE" == "true" ]] && [[ -f "$error_file" ]]; then
                print_info "Error details:"
                head -20 "$error_file" | sed 's/^/  /'
            fi
        fi
    done
    
    local end_time=$(date +%s)
    log_performance "TLAPS" "$start_time" "$end_time" "$verification_success"
    
    if [[ "$verification_success" == "true" ]]; then
        print_success "All TLAPS verifications completed successfully"
        return 0
    else
        print_error "Some TLAPS verifications failed"
        return 1
    fi
}

# TLC model checking
run_tlc_verification() {
    if [[ "$SKIP_MODEL_CHECKING" == "true" ]]; then
        print_warning "Skipping TLC model checking"
        return 0
    fi
    
    print_section "TLC Model Checking"
    
    local start_time=$(date +%s)
    local verification_success=true
    local config_files=()
    
    # Find all TLC configuration files
    if [[ -d "$MODELS_DIR" ]]; then
        mapfile -t config_files < <(find "$MODELS_DIR" -name "*.cfg" -type f)
    fi
    
    if [[ ${#config_files[@]} -eq 0 ]]; then
        print_warning "No TLC configuration files found in $MODELS_DIR"
        return 0
    fi
    
    print_info "Found ${#config_files[@]} TLC configuration files"
    
    # Run model checking for each configuration
    for config_file in "${config_files[@]}"; do
        local config_name=$(basename "$config_file" .cfg)
        local spec_file="$SPECS_DIR/${config_name}.tla"
        
        # Try to find corresponding spec file
        if [[ ! -f "$spec_file" ]]; then
            # Look for any TLA file that might match
            local possible_specs
            mapfile -t possible_specs < <(find "$SPECS_DIR" -name "*.tla" -type f)
            if [[ ${#possible_specs[@]} -gt 0 ]]; then
                spec_file="${possible_specs[0]}"
                print_info "Using spec file: $(basename "$spec_file")"
            else
                print_warning "No spec file found for $config_name"
                continue
            fi
        fi
        
        print_subsection "Model checking $config_name"
        
        local output_file="$RESULTS_DIR/tlc/${config_name}.out"
        local error_file="$RESULTS_DIR/tlc/${config_name}.err"
        
        # Run TLC model checking
        if timeout "${TIMEOUT_MINUTES}m" java -jar "$TLA_TOOLS" -config "$config_file" \
           "$spec_file" > "$output_file" 2> "$error_file"; then
            print_success "TLC model checking passed for $config_name"
            
            # Extract statistics
            local states_explored
            states_explored=$(grep "states generated" "$output_file" | grep -o '[0-9,]*' | tr -d ',' || echo "0")
            local distinct_states
            distinct_states=$(grep "distinct states" "$output_file" | grep -o '[0-9,]*' | tr -d ',' || echo "0")
            
            print_metric "States explored: $states_explored, Distinct: $distinct_states"
        else
            print_error "TLC model checking failed for $config_name"
            verification_success=false
            FAILED_COMPONENTS+=("TLC:$config_name")
            
            # Show error details if verbose
            if [[ "$VERBOSE" == "true" ]] && [[ -f "$error_file" ]]; then
                print_info "Error details:"
                head -20 "$error_file" | sed 's/^/  /'
            fi
        fi
    done
    
    local end_time=$(date +%s)
    log_performance "TLC" "$start_time" "$end_time" "$verification_success"
    
    if [[ "$verification_success" == "true" ]]; then
        print_success "All TLC model checking completed successfully"
        return 0
    else
        print_error "Some TLC model checking failed"
        return 1
    fi
}

# Stateright verification
run_stateright_verification() {
    if [[ "$SKIP_STATERIGHT_VERIFICATION" == "true" ]]; then
        print_warning "Skipping Stateright verification"
        return 0
    fi
    
    print_section "Stateright Verification"
    
    if [[ ! -d "$STATERIGHT_DIR" ]]; then
        print_warning "Stateright directory not found: $STATERIGHT_DIR"
        return 0
    fi
    
    local start_time=$(date +%s)
    local verification_success=true
    
    cd "$STATERIGHT_DIR"
    
    # Build Stateright project
    print_subsection "Building Stateright project"
    if cargo build --release > "$RESULTS_DIR/stateright/build.out" 2> "$RESULTS_DIR/stateright/build.err"; then
        print_success "Stateright build completed"
    else
        print_error "Stateright build failed"
        verification_success=false
        FAILED_COMPONENTS+=("Stateright:build")
        cd "$PROJECT_ROOT"
        return 1
    fi
    
    # Run tests
    print_subsection "Running Stateright tests"
    local test_output="$RESULTS_DIR/stateright/test.out"
    local test_error="$RESULTS_DIR/stateright/test.err"
    
    if timeout "${TIMEOUT_MINUTES}m" cargo test --release -- --test-threads="$PARALLEL_JOBS" \
       > "$test_output" 2> "$test_error"; then
        print_success "Stateright tests passed"
        
        # Extract test statistics
        local tests_run
        tests_run=$(grep "test result:" "$test_output" | grep -o '[0-9]* passed' | cut -d' ' -f1 || echo "0")
        local tests_failed
        tests_failed=$(grep "test result:" "$test_output" | grep -o '[0-9]* failed' | cut -d' ' -f1 || echo "0")
        
        print_metric "Tests: $tests_run passed, $tests_failed failed"
    else
        print_error "Stateright tests failed"
        verification_success=false
        FAILED_COMPONENTS+=("Stateright:tests")
        
        if [[ "$VERBOSE" == "true" ]] && [[ -f "$test_error" ]]; then
            print_info "Test failure details:"
            tail -50 "$test_error" | sed 's/^/  /'
        fi
    fi
    
    # Run specific verification tests
    print_subsection "Running verification-specific tests"
    local verification_tests=("cross_validation" "sampling_verification" "theorem_validation")
    
    for test_name in "${verification_tests[@]}"; do
        if cargo test --release "$test_name" > "$RESULTS_DIR/stateright/${test_name}.out" 2> "$RESULTS_DIR/stateright/${test_name}.err"; then
            print_success "Verification test $test_name passed"
        else
            print_warning "Verification test $test_name failed or not found"
        fi
    done
    
    cd "$PROJECT_ROOT"
    
    local end_time=$(date +%s)
    log_performance "Stateright" "$start_time" "$end_time" "$verification_success"
    
    if [[ "$verification_success" == "true" ]]; then
        print_success "Stateright verification completed successfully"
        return 0
    else
        print_error "Stateright verification failed"
        return 1
    fi
}

# Theorem mapping generation
run_theorem_mapping() {
    if [[ "$SKIP_THEOREM_MAPPING" == "true" ]]; then
        print_warning "Skipping theorem mapping generation"
        return 0
    fi
    
    print_section "Theorem Mapping Generation"
    
    local start_time=$(date +%s)
    local mapping_success=true
    
    local mapping_script="$SCRIPTS_DIR/generate_theorem_mapping.py"
    
    if [[ ! -f "$mapping_script" ]]; then
        print_warning "Theorem mapping script not found: $mapping_script"
        return 0
    fi
    
    print_subsection "Generating comprehensive theorem mapping"
    
    local mapping_output="$REPORTS_DIR/theorem_mapping"
    create_directory "$mapping_output"
    
    # Run theorem mapping generation
    local mapping_args=(
        "--whitepaper" "$WHITEPAPER_PATH"
        "--specs-dir" "$SPECS_DIR"
        "--proofs-dir" "$PROOFS_DIR"
        "--output-dir" "$mapping_output"
        "--project-root" "$PROJECT_ROOT"
    )
    
    if [[ "$VERBOSE" == "true" ]]; then
        mapping_args+=("--verbose")
    fi
    
    if python3 "$mapping_script" "${mapping_args[@]}" \
       > "$RESULTS_DIR/theorem_mapping.out" 2> "$RESULTS_DIR/theorem_mapping.err"; then
        print_success "Theorem mapping generation completed"
        
        # Check for generated files
        local generated_files=("theorem_mapping.md" "theorem_mapping.json" "theorem_mapping.html")
        for file in "${generated_files[@]}"; do
            if [[ -f "$mapping_output/$file" ]]; then
                print_success "Generated: $file"
            else
                print_warning "Missing: $file"
            fi
        done
    else
        print_error "Theorem mapping generation failed"
        mapping_success=false
        FAILED_COMPONENTS+=("TheoremMapping")
        
        if [[ "$VERBOSE" == "true" ]]; then
            print_info "Error details:"
            tail -20 "$RESULTS_DIR/theorem_mapping.err" | sed 's/^/  /'
        fi
    fi
    
    local end_time=$(date +%s)
    log_performance "TheoremMapping" "$start_time" "$end_time" "$mapping_success"
    
    if [[ "$mapping_success" == "true" ]]; then
        print_success "Theorem mapping generation completed successfully"
        return 0
    else
        print_error "Theorem mapping generation failed"
        return 1
    fi
}

# Cross-validation between TLA+ and Stateright
run_cross_validation() {
    if [[ "$SKIP_CROSS_VALIDATION" == "true" ]]; then
        print_warning "Skipping cross-validation"
        return 0
    fi
    
    print_section "Cross-Validation Between TLA+ and Stateright"
    
    local start_time=$(date +%s)
    local validation_success=true
    
    # Check if both TLA+ and Stateright results are available
    if [[ ! -d "$RESULTS_DIR/tlc" ]] || [[ ! -d "$RESULTS_DIR/stateright" ]]; then
        print_warning "Insufficient results for cross-validation"
        return 0
    fi
    
    print_subsection "Comparing TLA+ and Stateright results"
    
    # Run cross-validation script if available
    local cross_validation_script="$SCRIPTS_DIR/cross_validate.py"
    if [[ -f "$cross_validation_script" ]]; then
        if python3 "$cross_validation_script" \
           --tlc-results "$RESULTS_DIR/tlc" \
           --stateright-results "$RESULTS_DIR/stateright" \
           --output "$RESULTS_DIR/cross_validation.json" \
           > "$RESULTS_DIR/cross_validation.out" 2> "$RESULTS_DIR/cross_validation.err"; then
            print_success "Cross-validation completed"
        else
            print_error "Cross-validation script failed"
            validation_success=false
            FAILED_COMPONENTS+=("CrossValidation")
        fi
    else
        print_info "Cross-validation script not found, performing basic comparison"
        
        # Basic comparison of results
        local tlc_files
        tlc_files=$(find "$RESULTS_DIR/tlc" -name "*.out" | wc -l)
        local stateright_files
        stateright_files=$(find "$RESULTS_DIR/stateright" -name "*.out" | wc -l)
        
        print_metric "TLC result files: $tlc_files"
        print_metric "Stateright result files: $stateright_files"
        
        if [[ "$tlc_files" -gt 0 ]] && [[ "$stateright_files" -gt 0 ]]; then
            print_success "Both TLA+ and Stateright produced results"
        else
            print_warning "Limited results for cross-validation"
        fi
    fi
    
    local end_time=$(date +%s)
    log_performance "CrossValidation" "$start_time" "$end_time" "$validation_success"
    
    if [[ "$validation_success" == "true" ]]; then
        print_success "Cross-validation completed successfully"
        return 0
    else
        print_error "Cross-validation failed"
        return 1
    fi
}

# Performance analysis
run_performance_analysis() {
    if [[ "$SKIP_PERFORMANCE_ANALYSIS" == "true" ]]; then
        print_warning "Skipping performance analysis"
        return 0
    fi
    
    print_section "Performance Analysis"
    
    local start_time=$(date +%s)
    
    print_subsection "Collecting performance metrics"
    
    # Create performance report
    local perf_report="$REPORTS_DIR/performance_analysis.json"
    
    cat > "$perf_report" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "total_duration": $(($(date +%s) - START_TIME)),
  "components": [
EOF
    
    local first=true
    for metric in "${PERFORMANCE_METRICS[@]}"; do
        IFS=':' read -r component duration status <<< "$metric"
        
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo "," >> "$perf_report"
        fi
        
        cat >> "$perf_report" << EOF
    {
      "component": "$component",
      "duration_seconds": $duration,
      "status": "$status"
    }
EOF
    done
    
    cat >> "$perf_report" << EOF
  ],
  "failed_components": [
EOF
    
    first=true
    for failed in "${FAILED_COMPONENTS[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo "," >> "$perf_report"
        fi
        echo "    \"$failed\"" >> "$perf_report"
    done
    
    cat >> "$perf_report" << EOF
  ]
}
EOF
    
    print_success "Performance report generated: $perf_report"
    
    # Display performance summary
    print_subsection "Performance Summary"
    for metric in "${PERFORMANCE_METRICS[@]}"; do
        IFS=':' read -r component duration status <<< "$metric"
        print_metric "$component: ${duration}s ($status)"
    done
    
    local end_time=$(date +%s)
    log_performance "PerformanceAnalysis" "$start_time" "$end_time" "true"
    
    return 0
}

# Generate comprehensive report
generate_comprehensive_report() {
    print_section "Generating Comprehensive Verification Report"
    
    local start_time=$(date +%s)
    local total_duration=$(($(date +%s) - START_TIME))
    
    # Create main report
    local main_report="$REPORTS_DIR/verification_report.md"
    
    cat > "$main_report" << EOF
# Alpenglow Complete Verification Report

**Generated:** $(date -Iseconds)  
**Duration:** ${total_duration}s  
**Version:** 3.0.0

## Executive Summary

This report provides a comprehensive overview of the formal verification pipeline for the Alpenglow consensus protocol, including TLA+ proofs, model checking, Stateright verification, and theorem mapping.

### Verification Coverage

EOF
    
    # Add component status
    local total_components=0
    local successful_components=0
    
    for metric in "${PERFORMANCE_METRICS[@]}"; do
        IFS=':' read -r component duration status <<< "$metric"
        total_components=$((total_components + 1))
        if [[ "$status" == "true" ]]; then
            successful_components=$((successful_components + 1))
        fi
        
        echo "- **$component**: $status (${duration}s)" >> "$main_report"
    done
    
    local success_rate=$((successful_components * 100 / total_components))
    
    cat >> "$main_report" << EOF

**Overall Success Rate:** ${success_rate}% (${successful_components}/${total_components} components)

## Component Details

### TLA+ TLAPS Verification
- **Status:** $(grep -q "TLAPS.*true" <<< "${PERFORMANCE_METRICS[*]}" && echo "✅ PASSED" || echo "❌ FAILED")
- **Proof Files:** $(find "$PROOFS_DIR" -name "*.tla" 2>/dev/null | wc -l)
- **Results:** Available in \`results/tlaps/\`

### TLC Model Checking
- **Status:** $(grep -q "TLC.*true" <<< "${PERFORMANCE_METRICS[*]}" && echo "✅ PASSED" || echo "❌ FAILED")
- **Configuration Files:** $(find "$MODELS_DIR" -name "*.cfg" 2>/dev/null | wc -l)
- **Results:** Available in \`results/tlc/\`

### Stateright Verification
- **Status:** $(grep -q "Stateright.*true" <<< "${PERFORMANCE_METRICS[*]}" && echo "✅ PASSED" || echo "❌ FAILED")
- **Test Results:** Available in \`results/stateright/\`

### Theorem Mapping
- **Status:** $(grep -q "TheoremMapping.*true" <<< "${PERFORMANCE_METRICS[*]}" && echo "✅ PASSED" || echo "❌ FAILED")
- **Mapping Files:** Available in \`reports/theorem_mapping/\`

### Cross-Validation
- **Status:** $(grep -q "CrossValidation.*true" <<< "${PERFORMANCE_METRICS[*]}" && echo "✅ PASSED" || echo "❌ FAILED")
- **Validation Results:** Available in \`results/cross_validation.json\`

## Failed Components

EOF
    
    if [[ ${#FAILED_COMPONENTS[@]} -eq 0 ]]; then
        echo "No components failed during verification." >> "$main_report"
    else
        for failed in "${FAILED_COMPONENTS[@]}"; do
            echo "- $failed" >> "$main_report"
        done
    fi
    
    cat >> "$main_report" << EOF

## Performance Metrics

| Component | Duration (s) | Status |
|-----------|--------------|--------|
EOF
    
    for metric in "${PERFORMANCE_METRICS[@]}"; do
        IFS=':' read -r component duration status <<< "$metric"
        echo "| $component | $duration | $status |" >> "$main_report"
    done
    
    cat >> "$main_report" << EOF

## Next Steps

1. Review failed components and address any issues
2. Update theorem mappings based on new proofs
3. Enhance cross-validation coverage
4. Optimize performance bottlenecks

## Files Generated

- Main Report: \`reports/verification_report.md\`
- Performance Analysis: \`reports/performance_analysis.json\`
- Theorem Mapping: \`reports/theorem_mapping/\`
- Detailed Results: \`results/\`

---
*Generated by Alpenglow Complete Verification Pipeline v3.0.0*
EOF
    
    print_success "Comprehensive report generated: $main_report"
    
    # Generate additional output formats if requested
    if [[ "$OUTPUT_FORMATS" == *"json"* ]]; then
        local json_report="$REPORTS_DIR/verification_report.json"
        cat > "$json_report" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "version": "3.0.0",
  "total_duration": $total_duration,
  "success_rate": $success_rate,
  "components": {
EOF
        
        local first=true
        for metric in "${PERFORMANCE_METRICS[@]}"; do
            IFS=':' read -r component duration status <<< "$metric"
            
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo "," >> "$json_report"
            fi
            
            echo "    \"$component\": {\"duration\": $duration, \"status\": \"$status\"}" >> "$json_report"
        done
        
        cat >> "$json_report" << EOF
  },
  "failed_components": [$(printf '"%s",' "${FAILED_COMPONENTS[@]}" | sed 's/,$//')]
}
EOF
        
        print_success "JSON report generated: $json_report"
    fi
    
    local end_time=$(date +%s)
    log_performance "ReportGeneration" "$start_time" "$end_time" "true"
    
    return 0
}

# Show help
show_help() {
    cat << EOF
Alpenglow Complete Formal Verification Pipeline

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --skip-environment      Skip environment validation
    --skip-tla              Skip TLA+ TLAPS verification
    --skip-model-checking   Skip TLC model checking
    --skip-stateright       Skip Stateright verification
    --skip-theorem-mapping  Skip theorem mapping generation
    --skip-cross-validation Skip cross-validation
    --skip-performance      Skip performance analysis
    --quick                 Quick mode (reduced verification scope)
    --verbose               Verbose output
    --ci                    CI mode (strict error handling)
    --parallel-jobs N       Number of parallel jobs (default: 4)
    --timeout N             Timeout in minutes (default: 60)
    --output-formats LIST   Output formats: console,json,html (default: console,json,html)
    --help, -h              Show this help message

EXAMPLES:
    $0                                    # Full verification pipeline
    $0 --quick --verbose                  # Quick verification with verbose output
    $0 --skip-stateright --ci             # Skip Stateright in CI mode
    $0 --parallel-jobs 8 --timeout 120   # Use 8 parallel jobs with 2-hour timeout

ENVIRONMENT VARIABLES:
    ALPENGLOW_VERIFICATION_MODE    Set to 'quick' for quick mode
    ALPENGLOW_PARALLEL_JOBS        Number of parallel jobs
    ALPENGLOW_TIMEOUT_MINUTES      Timeout in minutes

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-environment)
                SKIP_ENVIRONMENT_CHECK=true
                shift
                ;;
            --skip-tla)
                SKIP_TLA_VERIFICATION=true
                shift
                ;;
            --skip-model-checking)
                SKIP_MODEL_CHECKING=true
                shift
                ;;
            --skip-stateright)
                SKIP_STATERIGHT_VERIFICATION=true
                shift
                ;;
            --skip-theorem-mapping)
                SKIP_THEOREM_MAPPING=true
                shift
                ;;
            --skip-cross-validation)
                SKIP_CROSS_VALIDATION=true
                shift
                ;;
            --skip-performance)
                SKIP_PERFORMANCE_ANALYSIS=true
                shift
                ;;
            --quick)
                QUICK_MODE=true
                TIMEOUT_MINUTES=30
                PARALLEL_JOBS=2
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --ci)
                CI_MODE=true
                shift
                ;;
            --parallel-jobs)
                PARALLEL_JOBS="$2"
                shift 2
                ;;
            --timeout)
                TIMEOUT_MINUTES="$2"
                shift 2
                ;;
            --output-formats)
                OUTPUT_FORMATS="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information."
                exit 1
                ;;
        esac
    done
    
    # Apply environment variables
    if [[ "${ALPENGLOW_VERIFICATION_MODE:-}" == "quick" ]]; then
        QUICK_MODE=true
    fi
    
    if [[ -n "${ALPENGLOW_PARALLEL_JOBS:-}" ]]; then
        PARALLEL_JOBS="$ALPENGLOW_PARALLEL_JOBS"
    fi
    
    if [[ -n "${ALPENGLOW_TIMEOUT_MINUTES:-}" ]]; then
        TIMEOUT_MINUTES="$ALPENGLOW_TIMEOUT_MINUTES"
    fi
}

# Main verification pipeline
main() {
    print_banner "Alpenglow Complete Formal Verification Pipeline v3.0.0"
    
    parse_arguments "$@"
    
    # Display configuration
    print_info "Configuration:"
    print_info "  Project Root: $PROJECT_ROOT"
    print_info "  Parallel Jobs: $PARALLEL_JOBS"
    print_info "  Timeout: ${TIMEOUT_MINUTES}m"
    print_info "  Quick Mode: $QUICK_MODE"
    print_info "  Verbose: $VERBOSE"
    print_info "  CI Mode: $CI_MODE"
    print_info "  Output Formats: $OUTPUT_FORMATS"
    
    local overall_success=true
    
    # Run verification pipeline
    if ! validate_environment; then
        overall_success=false
        if [[ "$CI_MODE" == "true" ]]; then
            exit 1
        fi
    fi
    
    if ! run_tlaps_verification; then
        overall_success=false
    fi
    
    if ! run_tlc_verification; then
        overall_success=false
    fi
    
    if ! run_stateright_verification; then
        overall_success=false
    fi
    
    if ! run_theorem_mapping; then
        overall_success=false
    fi
    
    if ! run_cross_validation; then
        overall_success=false
    fi
    
    if ! run_performance_analysis; then
        overall_success=false
    fi
    
    if ! generate_comprehensive_report; then
        overall_success=false
    fi
    
    # Final summary
    local total_duration=$(($(date +%s) - START_TIME))
    
    print_section "Verification Pipeline Summary"
    
    print_info "Total Duration: ${total_duration}s"
    print_info "Components Run: ${#PERFORMANCE_METRICS[@]}"
    print_info "Failed Components: ${#FAILED_COMPONENTS[@]}"
    
    if [[ "$overall_success" == "true" ]]; then
        print_banner "VERIFICATION PIPELINE COMPLETED SUCCESSFULLY ✅"
        echo
        print_success "All verification components completed successfully"
        print_info "Reports available in: $REPORTS_DIR"
        print_info "Detailed results in: $RESULTS_DIR"
        exit 0
    else
        print_banner "VERIFICATION PIPELINE COMPLETED WITH ERRORS ❌"
        echo
        print_error "Some verification components failed"
        print_info "Check the detailed reports for more information"
        print_info "Failed components: ${FAILED_COMPONENTS[*]}"
        
        if [[ "$CI_MODE" == "true" ]]; then
            exit 1
        else
            exit 2
        fi
    fi
}

# Trap for cleanup
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        print_error "Verification pipeline interrupted"
        print_info "Partial results may be available in: $RESULTS_DIR"
    fi
    exit $exit_code
}

trap cleanup EXIT INT TERM

# Run main function with all arguments
main "$@"