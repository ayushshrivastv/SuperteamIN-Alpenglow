#!/bin/bash
# Author: Ayush Srivastava

# quick_test.sh - Rapid Testing Script for Development
# Part of the Alpenglow Protocol Verification Suite
#
# This script provides fast validation for development workflows:
# - Rust compilation check (no full tests)
# - TLA+ syntax validation (no model checking)
# - Basic smoke tests
# - Environment sanity checks
# - Pre-commit validation
#
# Designed for sub-30 second execution time

set -euo pipefail

# Script metadata
SCRIPT_NAME="quick_test.sh"
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
TIMEOUT=25  # Maximum execution time in seconds
VERBOSE=false
SKIP_RUST=false
SKIP_TLA=false
SKIP_ENV=false
FAIL_FAST=true

# Paths
STATERIGHT_DIR="$PROJECT_ROOT/stateright"
SPECS_DIR="$PROJECT_ROOT/specs"
MODELS_DIR="$PROJECT_ROOT/models"
TLA_TOOLS_DIR="$HOME/tla-tools"
TLA_TOOLS_JAR="$TLA_TOOLS_DIR/tla2tools.jar"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Test results tracking
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
START_TIME=$(date +%s)

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $*"
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
}

log_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${CYAN}[VERBOSE]${NC} $*"
    fi
}

log_test_start() {
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    echo -e "${BOLD}[$TESTS_TOTAL]${NC} $*"
}

log_test_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    log_success "$*"
}

log_test_fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    log_fail "$*"
    if [ "$FAIL_FAST" = true ]; then
        log_error "Failing fast due to test failure"
        exit 1
    fi
}

# Usage information
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [options]

DESCRIPTION:
    Rapid testing script for development workflows. Performs quick validation
    of Rust compilation, TLA+ syntax, and environment setup without running
    full test suites or model checking.

    Designed for sub-30 second execution time to provide fast feedback.

OPTIONS:
    --verbose           Enable verbose output
    --skip-rust         Skip Rust compilation checks
    --skip-tla          Skip TLA+ syntax validation
    --skip-env          Skip environment checks
    --no-fail-fast      Continue testing even after failures
    --timeout SECONDS   Set maximum execution time (default: $TIMEOUT)
    --help              Show this help message

TESTS PERFORMED:
    1. Environment Sanity Check
       - Tool availability (rustc, cargo, java)
       - Project structure validation
       - Basic dependency checks

    2. Rust Compilation Check
       - Fast compilation without running tests
       - Syntax and type checking
       - Dependency resolution

    3. TLA+ Syntax Validation
       - Specification syntax checking
       - Module dependency validation
       - Basic semantic analysis

    4. Basic Smoke Tests
       - Critical path validation
       - Configuration file checks
       - Integration point verification

EXAMPLES:
    $SCRIPT_NAME                    # Run all quick tests
    $SCRIPT_NAME --verbose          # Run with detailed output
    $SCRIPT_NAME --skip-tla         # Skip TLA+ checks (faster)
    $SCRIPT_NAME --no-fail-fast     # Continue after failures

EXIT CODES:
    0   All tests passed
    1   One or more tests failed
    2   Timeout exceeded
    3   Configuration or usage error

EOF
}

# Parse command line arguments
parse_arguments() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --verbose)
                VERBOSE=true
                ;;
            --skip-rust)
                SKIP_RUST=true
                ;;
            --skip-tla)
                SKIP_TLA=true
                ;;
            --skip-env)
                SKIP_ENV=true
                ;;
            --no-fail-fast)
                FAIL_FAST=false
                ;;
            --timeout)
                shift
                if [ $# -eq 0 ]; then
                    log_error "--timeout requires a value"
                    exit 3
                fi
                TIMEOUT="$1"
                if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]]; then
                    log_error "Timeout must be a positive integer"
                    exit 3
                fi
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 3
                ;;
        esac
        shift
    done
}

# Timeout handler
timeout_handler() {
    log_error "Quick test timed out after ${TIMEOUT}s"
    log_error "Consider using --skip-* options to reduce test scope"
    exit 2
}

# Set up timeout
setup_timeout() {
    trap timeout_handler ALRM
    (sleep "$TIMEOUT" && kill -ALRM $$) &
    TIMEOUT_PID=$!
    log_verbose "Timeout set to ${TIMEOUT}s (PID: $TIMEOUT_PID)"
}

# Environment sanity checks
test_environment() {
    if [ "$SKIP_ENV" = true ]; then
        log_info "Skipping environment checks"
        return 0
    fi

    log_test_start "Environment Sanity Check"

    # Check basic tools
    local tools_ok=true

    if ! command -v rustc >/dev/null 2>&1; then
        log_test_fail "rustc not found in PATH"
        tools_ok=false
    else
        local rust_version
        rust_version=$(rustc --version | cut -d' ' -f2)
        log_verbose "Rust version: $rust_version"
    fi

    if ! command -v cargo >/dev/null 2>&1; then
        log_test_fail "cargo not found in PATH"
        tools_ok=false
    else
        local cargo_version
        cargo_version=$(cargo --version | cut -d' ' -f2)
        log_verbose "Cargo version: $cargo_version"
    fi

    if ! command -v java >/dev/null 2>&1; then
        log_warn "java not found in PATH (TLA+ checks will be skipped)"
        SKIP_TLA=true
    else
        local java_version
        java_version=$(java -version 2>&1 | head -n 1 | cut -d'"' -f2)
        log_verbose "Java version: $java_version"
    fi

    # Check project structure
    local structure_ok=true

    if [ ! -d "$STATERIGHT_DIR" ]; then
        log_test_fail "Stateright directory not found: $STATERIGHT_DIR"
        structure_ok=false
        SKIP_RUST=true
    fi

    if [ ! -f "$STATERIGHT_DIR/Cargo.toml" ]; then
        log_test_fail "Cargo.toml not found: $STATERIGHT_DIR/Cargo.toml"
        structure_ok=false
        SKIP_RUST=true
    fi

    if [ ! -d "$SPECS_DIR" ]; then
        log_warn "Specs directory not found: $SPECS_DIR (TLA+ checks will be skipped)"
        SKIP_TLA=true
    fi

    if [ "$tools_ok" = true ] && [ "$structure_ok" = true ]; then
        log_test_pass "Environment check completed"
    else
        log_test_fail "Environment check failed"
    fi
}

# Fast Rust compilation check
test_rust_compilation() {
    if [ "$SKIP_RUST" = true ]; then
        log_info "Skipping Rust compilation checks"
        return 0
    fi

    log_test_start "Rust Compilation Check"

    cd "$STATERIGHT_DIR"

    # Check if Cargo.lock exists and is recent
    if [ -f "Cargo.lock" ]; then
        log_verbose "Found existing Cargo.lock"
    else
        log_verbose "No Cargo.lock found, dependencies will be resolved"
    fi

    # Fast compilation check without running tests
    log_verbose "Running cargo check..."
    local check_output
    local check_exit_code=0

    if check_output=$(cargo check --quiet --message-format=short 2>&1); then
        log_test_pass "Rust compilation check passed"
        log_verbose "Compilation successful"
    else
        check_exit_code=$?
        log_test_fail "Rust compilation check failed (exit code: $check_exit_code)"
        
        # Show first few compilation errors for quick diagnosis
        echo "$check_output" | head -10 | while IFS= read -r line; do
            log_error "  $line"
        done
        
        # Check for common issues
        if echo "$check_output" | grep -q "type mismatch"; then
            log_error "Hint: Type mismatch detected - check for u64 vs [u8; 32] issues"
        fi
        
        if echo "$check_output" | grep -q "cannot find"; then
            log_error "Hint: Missing dependency or module - check imports"
        fi
    fi

    cd - >/dev/null
}

# TLA+ syntax validation
test_tla_syntax() {
    if [ "$SKIP_TLA" = true ]; then
        log_info "Skipping TLA+ syntax validation"
        return 0
    fi

    log_test_start "TLA+ Syntax Validation"

    # Check if TLA+ tools are available
    if [ ! -f "$TLA_TOOLS_JAR" ]; then
        log_warn "TLA+ tools not found at $TLA_TOOLS_JAR"
        log_warn "Attempting to download TLA+ tools..."
        
        mkdir -p "$TLA_TOOLS_DIR"
        local download_url="https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar"
        
        if command -v curl >/dev/null 2>&1; then
            if curl -sL "$download_url" -o "$TLA_TOOLS_JAR" --connect-timeout 10; then
                log_verbose "TLA+ tools downloaded successfully"
            else
                log_test_fail "Failed to download TLA+ tools"
                return 1
            fi
        else
            log_test_fail "curl not available for downloading TLA+ tools"
            return 1
        fi
    fi

    # Find TLA+ specification files
    local tla_files=()
    if [ -d "$SPECS_DIR" ]; then
        while IFS= read -r -d '' file; do
            tla_files+=("$file")
        done < <(find "$SPECS_DIR" -name "*.tla" -print0 2>/dev/null)
    fi

    if [ ${#tla_files[@]} -eq 0 ]; then
        log_warn "No TLA+ specification files found in $SPECS_DIR"
        log_test_pass "TLA+ syntax validation skipped (no files)"
        return 0
    fi

    # Validate syntax of each TLA+ file
    local syntax_ok=true
    for tla_file in "${tla_files[@]}"; do
        log_verbose "Checking syntax: $(basename "$tla_file")"
        
        local spec_name
        spec_name=$(basename "$tla_file" .tla)
        
        # Change to specs directory for SANY
        cd "$SPECS_DIR"
        
        local sany_output
        if sany_output=$(java -cp "$TLA_TOOLS_JAR" tla2sany.SANY "$spec_name" 2>&1); then
            log_verbose "  ✓ $(basename "$tla_file") syntax OK"
        else
            log_error "  ✗ $(basename "$tla_file") syntax error:"
            echo "$sany_output" | head -5 | while IFS= read -r line; do
                log_error "    $line"
            done
            syntax_ok=false
        fi
        
        cd - >/dev/null
    done

    if [ "$syntax_ok" = true ]; then
        log_test_pass "TLA+ syntax validation passed (${#tla_files[@]} files)"
    else
        log_test_fail "TLA+ syntax validation failed"
    fi
}

# Basic smoke tests
test_smoke_tests() {
    log_test_start "Basic Smoke Tests"

    local smoke_ok=true

    # Test 1: Check critical configuration files
    local config_files=(
        "$MODELS_DIR/Small.cfg"
        "$MODELS_DIR/WhitepaperValidation.cfg"
    )

    for config_file in "${config_files[@]}"; do
        if [ -f "$config_file" ]; then
            log_verbose "  ✓ Found config: $(basename "$config_file")"
        else
            log_warn "  ✗ Missing config: $(basename "$config_file")"
            # Don't fail for missing configs, just warn
        fi
    done

    # Test 2: Check if Rust project has basic structure
    if [ -d "$STATERIGHT_DIR/src" ]; then
        log_verbose "  ✓ Rust src directory exists"
    else
        log_error "  ✗ Rust src directory missing"
        smoke_ok=false
    fi

    # Test 3: Check for common files
    local important_files=(
        "$PROJECT_ROOT/README.md"
        "$STATERIGHT_DIR/Cargo.toml"
    )

    for file in "${important_files[@]}"; do
        if [ -f "$file" ]; then
            log_verbose "  ✓ Found: $(basename "$file")"
        else
            log_warn "  ✗ Missing: $(basename "$file")"
        fi
    done

    # Test 4: Quick dependency check
    if [ "$SKIP_RUST" != true ] && [ -f "$STATERIGHT_DIR/Cargo.toml" ]; then
        cd "$STATERIGHT_DIR"
        if cargo tree --quiet --depth 0 >/dev/null 2>&1; then
            log_verbose "  ✓ Rust dependencies resolvable"
        else
            log_warn "  ✗ Rust dependency issues detected"
        fi
        cd - >/dev/null
    fi

    if [ "$smoke_ok" = true ]; then
        log_test_pass "Basic smoke tests passed"
    else
        log_test_fail "Basic smoke tests failed"
    fi
}

# Cleanup function
cleanup() {
    local exit_code=$?
    
    # Kill timeout process if it exists
    if [ -n "${TIMEOUT_PID:-}" ]; then
        kill "$TIMEOUT_PID" 2>/dev/null || true
    fi
    
    # Calculate execution time
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    
    # Print summary
    echo ""
    echo "=== Quick Test Summary ==="
    echo "Total tests: $TESTS_TOTAL"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    echo "Duration: ${duration}s"
    echo "Status: $([ $exit_code -eq 0 ] && echo "SUCCESS" || echo "FAILURE")"
    
    if [ $duration -gt $((TIMEOUT - 5)) ]; then
        log_warn "Test execution took ${duration}s (close to ${TIMEOUT}s timeout)"
        log_warn "Consider using --skip-* options for faster execution"
    fi
    
    exit $exit_code
}

# Set up signal handlers
trap cleanup EXIT INT TERM

# Main execution
main() {
    echo -e "${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION - Rapid Development Testing${NC}"
    echo "Project: $(basename "$PROJECT_ROOT")"
    echo "Timeout: ${TIMEOUT}s"
    echo ""
    
    parse_arguments "$@"
    setup_timeout
    
    # Run test suite
    test_environment
    test_rust_compilation
    test_tla_syntax
    test_smoke_tests
    
    # Success if we reach here
    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "All quick tests passed! ✨"
        exit 0
    else
        log_error "$TESTS_FAILED test(s) failed"
        exit 1
    fi
}

# Execute main function with all arguments
main "$@"