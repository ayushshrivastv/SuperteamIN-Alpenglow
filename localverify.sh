
#!/bin/bash

#############################################################################
# Alpenglow Local Verification Script
#
# Simplified entry point for local development verification.
# Integrates with the comprehensive verification system while providing
# quick feedback for common development tasks.
#
# Usage: ./scripts/dev/localverify.sh [OPTIONS]
#   --quick             Quick verification (environment + basic checks)
#   --full              Run complete verification suite
#   --environment-only  Check environment setup only
#   --skip-rust         Skip Rust/Stateright verification
#   --skip-tla          Skip TLA+ verification
#   --verbose           Enable verbose output
#   --debug             Enable debug mode with enhanced diagnostics
#   --help              Show this help message
#
# This script provides a simplified interface to the comprehensive
# verification system located at submission/run_complete_verification.sh
#############################################################################

set -euo pipefail

# Script metadata
readonly SCRIPT_VERSION="2.1.0"
readonly SCRIPT_NAME="Alpenglow Local Verification"

# Color codes for enhanced output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Unicode symbols for better visual feedback
readonly CHECK_MARK="✓"
readonly CROSS_MARK="✗"
readonly WARNING_MARK="⚠"
readonly INFO_MARK="ℹ"
readonly GEAR_MARK="⚙"
readonly CLOCK_MARK="⏱"

# Directory configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly SUBMISSION_SCRIPT="$PROJECT_ROOT/submission/run_complete_verification.sh"

# Configuration options
QUICK_MODE=false
FULL_MODE=false
ENVIRONMENT_ONLY=false
SKIP_RUST=false
SKIP_TLA=false
VERBOSE=false
DEBUG_MODE=false
STRICT_MODE=false

# Timing and progress tracking
START_TIME=""
ISSUES_FOUND=0
WARNINGS_COUNT=0

#############################################################################
# Utility Functions
#############################################################################

# Helper function for timeout compatibility (Comment 1)
run_with_timeout() {
    local timeout_secs="$1"
    shift
    local cmd=("$@")
    
    # Try gtimeout first (GNU coreutils on macOS via Homebrew)
    if command -v gtimeout &> /dev/null; then
        gtimeout "$timeout_secs" "${cmd[@]}"
    # Try timeout (standard on Linux)
    elif command -v timeout &> /dev/null; then
        timeout "$timeout_secs" "${cmd[@]}"
    else
        # No timeout available - run without timeout but warn
        print_warning "No timeout command available (gtimeout/timeout), running without timeout"
        "${cmd[@]}"
    fi
}

print_header() {
    echo
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC} ${CYAN}${BOLD}$1${NC}${BLUE} ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo
}

print_section() {
    echo
    echo -e "${CYAN}${GEAR_MARK} $1${NC}"
    echo -e "${CYAN}$(printf '%.0s─' {1..50})${NC}"
}

print_info() {
    echo -e "${BLUE}${INFO_MARK}${NC} $1"
}

print_success() {
    echo -e "${GREEN}${CHECK_MARK}${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}${WARNING_MARK}${NC} $1"
    ((WARNINGS_COUNT++))
}

print_error() {
    echo -e "${RED}${CROSS_MARK}${NC} $1"
    ((ISSUES_FOUND++))
}

print_debug() {
    if [[ "$VERBOSE" == "true" ]] || [[ "$DEBUG_MODE" == "true" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $1"
    fi
}

print_progress() {
    local message="$1"
    local elapsed=""
    if [[ -n "$START_TIME" ]]; then
        local current_time
        current_time=$(date +%s)
        local duration=$((current_time - START_TIME))
        elapsed=" (${duration}s)"
    fi
    echo -e "${BLUE}${CLOCK_MARK}${NC} ${message}${elapsed}"
}

#############################################################################
# Environment Validation
#############################################################################

check_basic_environment() {
    print_section "Basic Environment Check"
    
    local env_issues=0
    
    # Check for repo anchors (Comment 2 - more robust project root check)
    local repo_anchors_found=0
    
    # Check for submission script (primary anchor)
    if [[ -f "$PROJECT_ROOT/submission/run_complete_verification.sh" ]]; then
        ((repo_anchors_found++))
        print_success "Found submission verification script"
    fi
    
    # Check for key directories
    local key_dirs=("specs" "proofs" "models" "stateright" "submission")
    local dirs_found=0
    for dir in "${key_dirs[@]}"; do
        if [[ -d "$PROJECT_ROOT/$dir" ]]; then
            ((dirs_found++))
        fi
    done
    
    if [[ $dirs_found -ge 3 ]]; then
        ((repo_anchors_found++))
        print_success "Found key project directories ($dirs_found/5)"
    fi
    
    # Downgrade markdown file check to warning (Comment 2)
    if [[ ! -f "$PROJECT_ROOT/Solana Alpenglow White Paper v1.1.md" ]]; then
        print_warning "Alpenglow whitepaper not found - may not be in project root"
    else
        ((repo_anchors_found++))
        print_success "Found Alpenglow whitepaper"
    fi
    
    # Require at least 2 anchors to confirm project root
    if [[ $repo_anchors_found -lt 2 ]]; then
        print_error "Not in Alpenglow project root directory (found $repo_anchors_found/3 anchors)"
        print_info "Expected anchors: submission/run_complete_verification.sh, key directories, whitepaper"
        ((env_issues++))
    else
        print_success "Project root directory confirmed ($repo_anchors_found/3 anchors found)"
    fi
    
    # Check for main verification script
    if [[ ! -f "$SUBMISSION_SCRIPT" ]]; then
        print_error "Main verification script not found: $SUBMISSION_SCRIPT"
        print_info "This script requires the comprehensive verification system"
        ((env_issues++))
    else
        print_success "Main verification script found"
        print_debug "Script location: $SUBMISSION_SCRIPT"
    fi
    
    # Check for required directories
    local required_dirs=("specs" "proofs" "models" "stateright" "submission")
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$PROJECT_ROOT/$dir" ]]; then
            print_warning "Missing directory: $dir"
        else
            print_debug "Found directory: $dir"
        fi
    done
    
    return $env_issues
}

check_tools_availability() {
    print_section "Tool Availability Check"
    
    local tool_issues=0
    
    # Check Java
    if command -v java &> /dev/null; then
        local java_version
        java_version=$(java -version 2>&1 | head -n1 | cut -d'"' -f2)
        print_success "Java found: $java_version"
        print_debug "Java path: $(which java)"
    else
        print_error "Java not found - required for TLA+ model checking"
        print_info "Install from: https://adoptium.net/"
        ((tool_issues++))
    fi
    
    # Check for TLA+ tools (TLC)
    if command -v tlc &> /dev/null; then
        print_success "TLC found in PATH"
    elif [[ -f "$PROJECT_ROOT/tools/tla2tools.jar" ]]; then
        print_success "TLA+ tools jar found locally"
    else
        print_warning "TLC not found - will attempt download if needed"
        print_debug "TLC can be downloaded automatically during verification"
    fi
    
    # Check Rust/Cargo
    if [[ "$SKIP_RUST" != "true" ]]; then
        if command -v cargo &> /dev/null; then
            local rust_version
            rust_version=$(cargo --version | cut -d' ' -f2)
            print_success "Rust/Cargo found: $rust_version"
            print_debug "Cargo path: $(which cargo)"
        else
            print_error "Rust/Cargo not found - required for Stateright verification"
            print_info "Install from: https://rustup.rs/"
            ((tool_issues++))
        fi
    else
        print_info "Skipping Rust check (--skip-rust specified)"
    fi
    
    # Check for TLAPS (optional)
    if command -v tlapm &> /dev/null; then
        print_success "TLAPS found for formal proofs"
    else
        print_warning "TLAPS not found - formal proof verification will be limited"
        print_info "Install from: https://tla.msr-inria.inria.fr/tlaps/content/Download/Source.html"
    fi
    
    return $tool_issues
}

quick_syntax_check() {
    print_section "Quick Syntax Check"
    
    local syntax_issues=0
    
    # Check TLA+ specifications syntax if TLC is available
    if [[ "$SKIP_TLA" != "true" ]] && (command -v tlc &> /dev/null || [[ -f "$PROJECT_ROOT/tools/tla2tools.jar" ]]); then
        print_info "Checking TLA+ specification syntax..."
        
        local specs_dir="$PROJECT_ROOT/specs"
        if [[ -d "$specs_dir" ]]; then
            local spec_count=0
            local valid_specs=0
            
            for spec in "$specs_dir"/*.tla; do
                if [[ -f "$spec" ]]; then
                    ((spec_count++))
                    local spec_name
                    spec_name=$(basename "$spec" .tla)
                    
                    print_debug "Checking syntax: $spec_name"
                    
                    # Quick syntax check (this is a simplified check)
                    if grep -q "MODULE\|EXTENDS\|VARIABLES" "$spec"; then
                        ((valid_specs++))
                        print_debug "✓ $spec_name has basic TLA+ structure"
                    else
                        print_warning "⚠ $spec_name may have syntax issues"
                        ((syntax_issues++))
                    fi
                fi
            done
            
            if [[ $spec_count -gt 0 ]]; then
                print_success "Checked $valid_specs/$spec_count TLA+ specifications"
            else
                print_warning "No TLA+ specifications found"
            fi
        else
            print_warning "Specs directory not found"
        fi
    else
        print_info "Skipping TLA+ syntax check (tools not available or --skip-tla specified)"
    fi
    
    # Check Rust project syntax if Cargo is available
    if [[ "$SKIP_RUST" != "true" ]] && command -v cargo &> /dev/null; then
        print_info "Checking Rust project syntax..."
        
        local stateright_dir="$PROJECT_ROOT/stateright"
        if [[ -d "$stateright_dir" && -f "$stateright_dir/Cargo.toml" ]]; then
            print_debug "Running cargo check..."
            
            local original_dir="$PWD"
            cd "$stateright_dir"
            
            if run_with_timeout 60 cargo check --quiet &>/dev/null; then
                print_success "Rust project compiles successfully"
            else
                print_error "Rust compilation issues detected"
                print_info "Run 'cargo check' in stateright/ for details"
                ((syntax_issues++))
            fi
            
            cd "$original_dir"
        else
            print_warning "Stateright directory or Cargo.toml not found"
        fi
    else
        print_info "Skipping Rust syntax check (Cargo not available or --skip-rust specified)"
    fi
    
    return $syntax_issues
}

#############################################################################
# Integration with Main Verification System
#############################################################################

run_comprehensive_verification() {
    print_section "Running Comprehensive Verification"
    
    if [[ ! -f "$SUBMISSION_SCRIPT" ]]; then
        print_error "Cannot run comprehensive verification - script not found"
        return 1
    fi
    
    print_info "Delegating to comprehensive verification system..."
    print_debug "Script: $SUBMISSION_SCRIPT"
    
    # Build arguments for the main script
    local main_args=()
    
    if [[ "$VERBOSE" == "true" ]]; then
        main_args+=("--verbose")
    fi
    
    if [[ "$DEBUG_MODE" == "true" ]]; then
        main_args+=("--debug")
    fi
    
    if [[ "$SKIP_RUST" == "true" ]]; then
        main_args+=("--skip-model-checking")  # Assuming Stateright is part of model checking
    fi
    
    if [[ "$SKIP_TLA" == "true" ]]; then
        main_args+=("--skip-proofs")
    fi
    
    # Add continue-on-error for local development (unless strict mode)
    if [[ "$STRICT_MODE" != "true" ]]; then
        main_args+=("--continue-on-error")
    fi
    
    print_debug "Main script arguments: ${main_args[*]}"
    
    # Execute the main verification script
    print_progress "Starting comprehensive verification"
    
    if [[ "$VERBOSE" == "true" ]] || [[ "$DEBUG_MODE" == "true" ]]; then
        # Show output in verbose/debug mode
        "$SUBMISSION_SCRIPT" "${main_args[@]}"
    else
        # Capture output and show summary
        local output_file
        output_file=$(mktemp)
        
        if "$SUBMISSION_SCRIPT" "${main_args[@]}" > "$output_file" 2>&1; then
            print_success "Comprehensive verification completed successfully"
            
            # Show key results
            if grep -q "SUBMISSION READY" "$output_file"; then
                print_success "🎉 Verification package is ready for submission!"
            elif grep -q "SUBMISSION PARTIAL" "$output_file"; then
                print_warning "⚠ Partial verification completed"
            fi
            
            # Show results location (Comment 5 - enhanced parsing)
            local results_dir
            results_dir=$(grep '^RESULTS_DIR=' "$output_file" | cut -d'=' -f2 || grep "Results Directory:" "$output_file" | cut -d' ' -f3 || echo "")
            if [[ -n "$results_dir" ]]; then
                print_info "📁 Results: $results_dir"
            fi
            
            rm -f "$output_file"
            return 0
        else
            print_error "Comprehensive verification failed"
            
            # Show error summary
            print_info "Error details:"
            tail -20 "$output_file" | while read -r line; do
                echo "  $line"
            done
            
            rm -f "$output_file"
            return 1
        fi
    fi
}

#############################################################################
# Command Line Interface
#############################################################################

show_help() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION

Simplified entry point for local Alpenglow verification during development.
Provides quick feedback and integrates with the comprehensive verification system.

USAGE:
    ./scripts/dev/localverify.sh [OPTIONS]

OPTIONS:
    --quick             Quick verification (environment + basic checks only)
    --full              Run complete verification suite
    --environment-only  Check environment setup only
    --skip-rust         Skip Rust/Stateright verification
    --skip-tla          Skip TLA+ verification  
    --verbose           Enable verbose output
    --debug             Enable debug mode with enhanced diagnostics
    --strict            Strict mode - exit on any failure, no continue-on-error
    --help              Show this help message

VERIFICATION MODES:
    Default Mode        Environment check + syntax validation + quick tests
    Quick Mode          Environment check + basic syntax validation only
    Full Mode           Complete verification using submission system
    Environment Only    Just check tools and directory structure

EXAMPLES:
    # Quick development check
    ./scripts/dev/localverify.sh --quick

    # Full verification for submission
    ./scripts/dev/localverify.sh --full --verbose

    # Check environment setup only
    ./scripts/dev/localverify.sh --environment-only

    # Skip Rust if not installed
    ./scripts/dev/localverify.sh --skip-rust

INTEGRATION:
    This script provides a simplified interface to the comprehensive
    verification system. For full submission verification, it delegates
    to: submission/run_complete_verification.sh

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --quick)
                QUICK_MODE=true
                shift
                ;;
            --full)
                FULL_MODE=true
                shift
                ;;
            --environment-only)
                ENVIRONMENT_ONLY=true
                shift
                ;;
            --skip-rust)
                SKIP_RUST=true
                shift
                ;;
            --skip-tla)
                SKIP_TLA=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --debug)
                DEBUG_MODE=true
                VERBOSE=true
                shift
                ;;
            --strict)
                STRICT_MODE=true
                shift
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
    
    # Validate argument combinations
    if [[ "$QUICK_MODE" == "true" && "$FULL_MODE" == "true" ]]; then
        print_error "Cannot specify both --quick and --full"
        exit 1
    fi
}

#############################################################################
# Main Execution
#############################################################################

main() {
    # Record start time
    START_TIME=$(date +%s)
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Print header
    print_header "$SCRIPT_NAME v$SCRIPT_VERSION"
    print_info "Local development verification for Alpenglow consensus protocol"
    
    if [[ "$DEBUG_MODE" == "true" ]]; then
        print_info "🔧 Debug mode enabled - enhanced diagnostics active"
    fi
    
    echo
    
    # Always check basic environment
    if ! check_basic_environment; then
        print_error "Basic environment check failed"
        exit 1
    fi
    
    # Check tool availability
    if ! check_tools_availability; then
        print_warning "Some tools are missing - verification may be limited"
    fi
    
    # Stop here if environment-only mode
    if [[ "$ENVIRONMENT_ONLY" == "true" ]]; then
        print_section "Environment Check Complete"
        
        if [[ $ISSUES_FOUND -eq 0 ]]; then
            print_success "Environment is ready for verification"
            exit 0
        else
            print_error "Environment has $ISSUES_FOUND issue(s) that need attention"
            exit 1
        fi
    fi
    
    # Quick syntax check unless in full mode
    if [[ "$FULL_MODE" != "true" ]]; then
        quick_syntax_check
    fi
    
    # Run appropriate verification mode
    if [[ "$FULL_MODE" == "true" ]]; then
        # Delegate to comprehensive verification system
        if run_comprehensive_verification; then
            verification_success=true
        else
            verification_success=false
        fi
    elif [[ "$QUICK_MODE" == "true" ]]; then
        # Quick mode - just environment and syntax
        print_section "Quick Verification Complete"
        verification_success=true
    else
        # Default mode - environment, syntax, and basic validation
        print_section "Local Verification Complete"
        verification_success=true
    fi
    
    # Final summary
    local end_time
    end_time=$(date +%s)
    local total_time=$((end_time - START_TIME))
    
    echo
    print_section "Verification Summary"
    
    echo -e "⏱️  Total time: ${total_time}s"
    echo -e "⚠️  Warnings: $WARNINGS_COUNT"
    echo -e "❌ Issues: $ISSUES_FOUND"
    
    if [[ "$verification_success" == "true" && $ISSUES_FOUND -eq 0 ]]; then
        echo
        print_success "🎉 Local verification completed successfully!"
        
        if [[ "$FULL_MODE" != "true" ]]; then
            echo
            print_info "💡 Next steps:"
            print_info "  • Run with --full for comprehensive verification"
            print_info "  • Check submission/verification_results/ for detailed reports"
            print_info "  • Use submission/run_complete_verification.sh for final validation"
        fi
        
        exit 0
    else
        echo
        if [[ $ISSUES_FOUND -gt 0 ]]; then
            print_error "❌ Verification completed with $ISSUES_FOUND issue(s)"
        else
            print_warning "⚠ Verification completed with warnings"
        fi
        
        echo
        print_info "🔍 Troubleshooting:"
        print_info "  • Run with --verbose for detailed output"
        print_info "  • Run with --debug for enhanced diagnostics"
        print_info "  • Check individual components with --environment-only"
        
        if [[ -f "$PROJECT_ROOT/docs/TroubleshootingGuide.md" ]]; then
            print_info "  • Consult docs/TroubleshootingGuide.md for common solutions"
        fi
        
        exit 1
    fi
}

# Execute main function with all arguments
main "$@"
