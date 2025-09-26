#!/bin/bash
# Author: Ayush Srivastava

# verify_proofs.sh - TLAPS Proof Verification Script
# Part of the Alpenglow Protocol Formal Verification Suite
#
# This script runs TLAPS (TLA+ Proof System) verification for specified modules
# with support for dependency ordering, parallel execution, and CI integration.

set -euo pipefail

# Script metadata
SCRIPT_NAME="verify_proofs.sh"
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default configuration
DEFAULT_TIMEOUT=3600
DEFAULT_THREADS=4
DEFAULT_VERBOSE=false
DEFAULT_PARALLEL=false
DEFAULT_CI_MODE=false

# TLAPS configuration
TLAPS_BIN="${TLAPS_BIN:-/usr/local/tlaps/bin/tlapm}"
TLAPS_THREADS="${TLAPS_THREADS:-$DEFAULT_THREADS}"
TLAPS_TIMEOUT="${TLAPS_TIMEOUT:-$DEFAULT_TIMEOUT}"

# Output configuration
RESULTS_DIR="${PROJECT_ROOT}/results/ci/tlaps"
LOG_PREFIX="tlaps"

# Color codes for output
if [[ -t 1 ]] && [[ "${CI:-false}" != "true" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    PURPLE=''
    CYAN=''
    NC=''
fi

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_debug() {
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $*" >&2
    fi
}

# Usage information
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS] <module|all>

TLAPS Proof Verification Script for Alpenglow Protocol

ARGUMENTS:
    module          Name of the TLA+ module to verify (without .tla extension)
                   or 'all' to verify all proof modules

OPTIONS:
    --verbose       Enable verbose output
    --timeout SEC   Set timeout in seconds (default: $DEFAULT_TIMEOUT)
    --parallel      Run multiple modules in parallel (when verifying 'all')
    --threads N     Number of TLAPS threads (default: $DEFAULT_THREADS)
    --ci            Enable CI-compatible output format
    --results-dir   Custom results directory (default: $RESULTS_DIR)
    --help          Show this help message

EXAMPLES:
    $SCRIPT_NAME Safety                    # Verify Safety.tla proofs
    $SCRIPT_NAME all --parallel            # Verify all modules in parallel
    $SCRIPT_NAME Liveness --verbose --ci   # Verify with verbose CI output
    $SCRIPT_NAME all --timeout 7200        # Verify all with 2-hour timeout

MODULES:
    The script automatically detects proof modules in:
    - proofs/ directory (primary location)
    - specs/ directory (fallback for modules with proofs)

DEPENDENCIES:
    Module verification follows dependency order:
    Types → Utils → Safety → Liveness → Resilience → WhitepaperTheorems

ENVIRONMENT VARIABLES:
    TLAPS_BIN       Path to tlapm binary (default: /usr/local/tlaps/bin/tlapm)
    TLAPS_THREADS   Number of TLAPS threads
    TLAPS_TIMEOUT   Timeout in seconds
    CI              Set to 'true' for CI mode

EXIT CODES:
    0   All verifications successful
    1   Some verifications failed
    2   Invalid arguments or setup error
    3   TLAPS not available
    124 Timeout occurred

EOF
}

# Module dependency mapping
declare -A MODULE_DEPENDENCIES=(
    ["Types"]=""
    ["Utils"]="Types"
    ["Safety"]="Types Utils"
    ["Liveness"]="Types Utils Safety"
    ["Resilience"]="Types Utils Safety Liveness"
    ["WhitepaperTheorems"]="Types Utils Safety Liveness Resilience"
)

# Available proof modules (will be populated by discover_modules)
declare -a AVAILABLE_MODULES=()

# Parse command line arguments
parse_arguments() {
    local module=""
    local timeout="$DEFAULT_TIMEOUT"
    local threads="$DEFAULT_THREADS"
    local verbose="$DEFAULT_VERBOSE"
    local parallel="$DEFAULT_PARALLEL"
    local ci_mode="$DEFAULT_CI_MODE"
    local results_dir="$RESULTS_DIR"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose)
                verbose=true
                shift
                ;;
            --timeout)
                if [[ -n "${2:-}" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
                    timeout="$2"
                    shift 2
                else
                    log_error "Invalid timeout value: ${2:-}"
                    return 2
                fi
                ;;
            --parallel)
                parallel=true
                shift
                ;;
            --threads)
                if [[ -n "${2:-}" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
                    threads="$2"
                    shift 2
                else
                    log_error "Invalid threads value: ${2:-}"
                    return 2
                fi
                ;;
            --ci)
                ci_mode=true
                shift
                ;;
            --results-dir)
                if [[ -n "${2:-}" ]]; then
                    results_dir="$2"
                    shift 2
                else
                    log_error "Results directory not specified"
                    return 2
                fi
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                return 2
                ;;
            *)
                if [[ -z "$module" ]]; then
                    module="$1"
                else
                    log_error "Multiple modules specified: $module and $1"
                    return 2
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$module" ]]; then
        log_error "Module name required"
        usage
        return 2
    fi

    # Export parsed values
    export MODULE="$module"
    export TIMEOUT="$timeout"
    export THREADS="$threads"
    export VERBOSE="$verbose"
    export PARALLEL="$parallel"
    export CI_MODE="$ci_mode"
    export RESULTS_DIR="$results_dir"
}

# Check if TLAPS is available
check_tlaps() {
    log_debug "Checking TLAPS availability..."
    
    if [[ ! -x "$TLAPS_BIN" ]]; then
        log_error "TLAPS not found at: $TLAPS_BIN"
        log_error "Please install TLAPS or set TLAPS_BIN environment variable"
        return 3
    fi

    # Test TLAPS
    if ! "$TLAPS_BIN" --help >/dev/null 2>&1; then
        log_error "TLAPS binary not working: $TLAPS_BIN"
        return 3
    fi

    local tlaps_version
    tlaps_version=$("$TLAPS_BIN" --version 2>&1 | head -1 || echo "unknown")
    log_debug "TLAPS version: $tlaps_version"
    
    return 0
}

# Discover available proof modules
discover_modules() {
    log_debug "Discovering available proof modules..."
    
    AVAILABLE_MODULES=()
    
    # Check proofs/ directory first
    if [[ -d "$PROJECT_ROOT/proofs" ]]; then
        for file in "$PROJECT_ROOT/proofs"/*.tla; do
            if [[ -f "$file" ]]; then
                local module
                module=$(basename "$file" .tla)
                AVAILABLE_MODULES+=("$module")
                log_debug "Found proof module: $module (in proofs/)"
            fi
        done
    fi
    
    # Check specs/ directory for modules with proofs
    if [[ -d "$PROJECT_ROOT/specs" ]]; then
        for file in "$PROJECT_ROOT/specs"/*.tla; do
            if [[ -f "$file" ]] && grep -q "THEOREM\|LEMMA\|PROOF" "$file" 2>/dev/null; then
                local module
                module=$(basename "$file" .tla)
                # Only add if not already found in proofs/
                if [[ ! " ${AVAILABLE_MODULES[*]} " =~ " $module " ]]; then
                    AVAILABLE_MODULES+=("$module")
                    log_debug "Found proof module: $module (in specs/)"
                fi
            fi
        done
    fi
    
    if [[ ${#AVAILABLE_MODULES[@]} -eq 0 ]]; then
        log_error "No proof modules found in proofs/ or specs/ directories"
        return 2
    fi
    
    log_debug "Available modules: ${AVAILABLE_MODULES[*]}"
}

# Find module file path
find_module_path() {
    local module="$1"
    
    # Check proofs/ directory first
    if [[ -f "$PROJECT_ROOT/proofs/$module.tla" ]]; then
        echo "$PROJECT_ROOT/proofs/$module.tla"
        return 0
    fi
    
    # Check specs/ directory
    if [[ -f "$PROJECT_ROOT/specs/$module.tla" ]]; then
        echo "$PROJECT_ROOT/specs/$module.tla"
        return 0
    fi
    
    return 1
}

# Get module dependencies in verification order
get_verification_order() {
    local modules=("$@")
    local ordered=()
    local processed=()
    
    # Function to add module and its dependencies recursively
    add_module_with_deps() {
        local module="$1"
        
        # Skip if already processed
        if [[ " ${processed[*]} " =~ " $module " ]]; then
            return
        fi
        
        # Add dependencies first
        local deps="${MODULE_DEPENDENCIES[$module]:-}"
        if [[ -n "$deps" ]]; then
            for dep in $deps; do
                if [[ " ${modules[*]} " =~ " $dep " ]]; then
                    add_module_with_deps "$dep"
                fi
            done
        fi
        
        # Add the module itself
        if [[ " ${modules[*]} " =~ " $module " ]]; then
            ordered+=("$module")
            processed+=("$module")
        fi
    }
    
    # Process all modules
    for module in "${modules[@]}"; do
        add_module_with_deps "$module"
    done
    
    echo "${ordered[@]}"
}

# Verify a single module
verify_module() {
    local module="$1"
    local log_file="$2"
    local metrics_file="$3"
    
    log_info "Verifying module: $module"
    
    # Find module file
    local module_path
    if ! module_path=$(find_module_path "$module"); then
        log_error "Module file not found: $module.tla"
        return 1
    fi
    
    log_debug "Module path: $module_path"
    
    # Prepare TLAPS command
    local tlaps_cmd=(
        "$TLAPS_BIN"
        "--verbose"
        "--toolbox" "0" "0"
        "--threads" "$THREADS"
    )
    
    # Add CI-specific options
    if [[ "$CI_MODE" == "true" ]]; then
        tlaps_cmd+=("--batch")
    fi
    
    tlaps_cmd+=("$module_path")
    
    log_debug "TLAPS command: ${tlaps_cmd[*]}"
    
    # Run TLAPS with timeout
    local start_time
    start_time=$(date +%s)
    
    local exit_code=0
    if [[ "$TIMEOUT" -gt 0 ]]; then
        timeout "$TIMEOUT" "${tlaps_cmd[@]}" > "$log_file" 2>&1 || exit_code=$?
    else
        "${tlaps_cmd[@]}" > "$log_file" 2>&1 || exit_code=$?
    fi
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Determine status
    local status
    case $exit_code in
        0)
            status="VERIFIED"
            log_success "Module $module verified successfully"
            ;;
        124)
            status="TIMEOUT"
            log_warning "Module $module verification timed out after ${TIMEOUT}s"
            ;;
        *)
            status="PARTIAL"
            log_warning "Module $module verification completed with issues (exit code: $exit_code)"
            ;;
    esac
    
    # Extract metrics from log
    local obligations=0
    local verified=0
    local failed=0
    local timeout_count=0
    
    if [[ -f "$log_file" ]]; then
        obligations=$(grep -c "obligation" "$log_file" 2>/dev/null || echo "0")
        verified=$(grep -c "proved\|verified" "$log_file" 2>/dev/null || echo "0")
        failed=$(grep -c "failed\|error" "$log_file" 2>/dev/null || echo "0")
        timeout_count=$(grep -c "timeout" "$log_file" 2>/dev/null || echo "0")
    fi
    
    # Calculate verification rate
    local verification_rate="0.0"
    if [[ $obligations -gt 0 ]]; then
        verification_rate=$(echo "scale=2; $verified * 100 / $obligations" | bc -l 2>/dev/null || echo "0.0")
    fi
    
    # Get dependencies
    local dependencies="${MODULE_DEPENDENCIES[$module]:-}"
    
    # Save metrics
    cat > "$metrics_file" << EOF
{
  "module": "$module",
  "timestamp": "$(date -Iseconds)",
  "status": "$status",
  "execution_time_seconds": $duration,
  "total_obligations": $obligations,
  "verified_obligations": $verified,
  "failed_obligations": $failed,
  "timeout_obligations": $timeout_count,
  "verification_rate": $verification_rate,
  "dependencies": "$dependencies",
  "module_path": "$module_path",
  "tlaps_version": "$("$TLAPS_BIN" --version 2>&1 | head -1 || echo "unknown")",
  "threads_used": $THREADS,
  "timeout_seconds": $TIMEOUT
}
EOF
    
    # Output metrics for CI
    if [[ "$CI_MODE" == "true" ]] || [[ "$VERBOSE" == "true" ]]; then
        log_info "Verification metrics for $module:"
        log_info "  Status: $status"
        log_info "  Duration: ${duration}s"
        log_info "  Total obligations: $obligations"
        log_info "  Verified: $verified"
        log_info "  Failed: $failed"
        log_info "  Timeouts: $timeout_count"
        log_info "  Verification rate: $verification_rate%"
    fi
    
    return $exit_code
}

# Verify modules in parallel
verify_modules_parallel() {
    local modules=("$@")
    local pids=()
    local results=()
    
    log_info "Starting parallel verification of ${#modules[@]} modules..."
    
    # Start verification processes
    for module in "${modules[@]}"; do
        local log_file="$RESULTS_DIR/${LOG_PREFIX}_${module}.log"
        local metrics_file="$RESULTS_DIR/metrics_${module}.json"
        
        # Run verification in background
        (verify_module "$module" "$log_file" "$metrics_file") &
        local pid=$!
        pids+=($pid)
        
        log_debug "Started verification of $module (PID: $pid)"
    done
    
    # Wait for all processes and collect results
    local overall_exit_code=0
    for i in "${!pids[@]}"; do
        local pid=${pids[$i]}
        local module=${modules[$i]}
        
        if wait $pid; then
            log_debug "Module $module verification completed successfully"
            results+=("$module:SUCCESS")
        else
            local exit_code=$?
            log_debug "Module $module verification failed with exit code $exit_code"
            results+=("$module:FAILED:$exit_code")
            if [[ $exit_code -ne 124 ]]; then  # Don't fail overall for timeouts
                overall_exit_code=1
            fi
        fi
    done
    
    # Report results
    log_info "Parallel verification completed:"
    for result in "${results[@]}"; do
        IFS=':' read -r module status exit_code <<< "$result"
        case $status in
            SUCCESS)
                log_success "  $module: ✅ VERIFIED"
                ;;
            FAILED)
                if [[ "$exit_code" == "124" ]]; then
                    log_warning "  $module: ⏱️ TIMEOUT"
                else
                    log_warning "  $module: ❌ FAILED (exit code: $exit_code)"
                fi
                ;;
        esac
    done
    
    return $overall_exit_code
}

# Verify modules sequentially
verify_modules_sequential() {
    local modules=("$@")
    local overall_exit_code=0
    local successful=0
    local failed=0
    local timeouts=0
    
    log_info "Starting sequential verification of ${#modules[@]} modules..."
    
    for module in "${modules[@]}"; do
        local log_file="$RESULTS_DIR/${LOG_PREFIX}_${module}.log"
        local metrics_file="$RESULTS_DIR/metrics_${module}.json"
        
        if verify_module "$module" "$log_file" "$metrics_file"; then
            ((successful++))
        else
            local exit_code=$?
            if [[ $exit_code -eq 124 ]]; then
                ((timeouts++))
            else
                ((failed++))
                overall_exit_code=1
            fi
        fi
    done
    
    # Report summary
    log_info "Sequential verification completed:"
    log_info "  Successful: $successful"
    log_info "  Failed: $failed"
    log_info "  Timeouts: $timeouts"
    log_info "  Total: ${#modules[@]}"
    
    return $overall_exit_code
}

# Main verification function
main() {
    log_info "Starting TLAPS proof verification..."
    log_info "Script: $SCRIPT_NAME v$SCRIPT_VERSION"
    
    # Parse arguments
    if ! parse_arguments "$@"; then
        return $?
    fi
    
    # Check TLAPS availability
    if ! check_tlaps; then
        return $?
    fi
    
    # Discover available modules
    if ! discover_modules; then
        return $?
    fi
    
    # Determine modules to verify
    local modules_to_verify=()
    if [[ "$MODULE" == "all" ]]; then
        modules_to_verify=("${AVAILABLE_MODULES[@]}")
        log_info "Verifying all available modules: ${modules_to_verify[*]}"
    else
        if [[ " ${AVAILABLE_MODULES[*]} " =~ " $MODULE " ]]; then
            modules_to_verify=("$MODULE")
            log_info "Verifying single module: $MODULE"
        else
            log_error "Module not found: $MODULE"
            log_error "Available modules: ${AVAILABLE_MODULES[*]}"
            return 2
        fi
    fi
    
    # Create results directory
    mkdir -p "$RESULTS_DIR"
    
    # Get verification order (respecting dependencies)
    local ordered_modules
    read -ra ordered_modules <<< "$(get_verification_order "${modules_to_verify[@]}")"
    
    log_info "Verification order: ${ordered_modules[*]}"
    
    # Run verification
    local exit_code=0
    if [[ "$PARALLEL" == "true" ]] && [[ ${#ordered_modules[@]} -gt 1 ]]; then
        if ! verify_modules_parallel "${ordered_modules[@]}"; then
            exit_code=1
        fi
    else
        if ! verify_modules_sequential "${ordered_modules[@]}"; then
            exit_code=1
        fi
    fi
    
    # Generate summary
    local total_modules=${#ordered_modules[@]}
    local successful_modules=0
    local failed_modules=0
    local timeout_modules=0
    
    for module in "${ordered_modules[@]}"; do
        local metrics_file="$RESULTS_DIR/metrics_${module}.json"
        if [[ -f "$metrics_file" ]]; then
            local status
            status=$(jq -r '.status' "$metrics_file" 2>/dev/null || echo "UNKNOWN")
            case "$status" in
                VERIFIED) ((successful_modules++)) ;;
                TIMEOUT) ((timeout_modules++)) ;;
                *) ((failed_modules++)) ;;
            esac
        else
            ((failed_modules++))
        fi
    done
    
    # Final summary
    log_info "=== TLAPS Verification Summary ==="
    log_info "Total modules: $total_modules"
    log_success "Successful: $successful_modules"
    if [[ $timeout_modules -gt 0 ]]; then
        log_warning "Timeouts: $timeout_modules"
    fi
    if [[ $failed_modules -gt 0 ]]; then
        log_error "Failed: $failed_modules"
    fi
    
    local success_rate="0.0"
    if [[ $total_modules -gt 0 ]]; then
        success_rate=$(echo "scale=1; $successful_modules * 100 / $total_modules" | bc -l 2>/dev/null || echo "0.0")
    fi
    log_info "Success rate: $success_rate%"
    
    # Save overall summary
    cat > "$RESULTS_DIR/verification_summary.json" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "script_version": "$SCRIPT_VERSION",
  "total_modules": $total_modules,
  "successful_modules": $successful_modules,
  "failed_modules": $failed_modules,
  "timeout_modules": $timeout_modules,
  "success_rate": $success_rate,
  "modules_verified": $(printf '%s\n' "${ordered_modules[@]}" | jq -R . | jq -s .),
  "parallel_execution": $PARALLEL,
  "timeout_seconds": $TIMEOUT,
  "threads_used": $THREADS,
  "results_directory": "$RESULTS_DIR"
}
EOF
    
    if [[ $exit_code -eq 0 ]]; then
        log_success "All verifications completed successfully!"
    else
        log_warning "Some verifications failed or timed out"
    fi
    
    return $exit_code
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi