#!/bin/bash

# check_model.sh - TLA+ Model Checking Script for CI Pipeline
# Part of the Alpenglow Protocol Verification Suite
#
# This script runs TLC model checking with specified configurations
# and handles the output formatting expected by the CI pipeline.

set -euo pipefail

# Script metadata
SCRIPT_NAME="check_model.sh"
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default configuration
DEFAULT_TIMEOUT=1200
DEFAULT_WORKERS=4
DEFAULT_TLA_TOOLS_VERSION="1.8.0"
TLA_TOOLS_DIR="$HOME/tla-tools"
TLA_TOOLS_JAR="$TLA_TOOLS_DIR/tla2tools.jar"

# Output configuration
RESULTS_DIR="$PROJECT_ROOT/results/ci"
LOG_FILE=""
VERBOSE=false
CI_MODE=false
TLC_ONLY=false

# Configuration parameters
CONFIG_NAME=""
TIMEOUT=$DEFAULT_TIMEOUT
WORKERS=$DEFAULT_WORKERS
SPEC_FILE="$PROJECT_ROOT/specs/Alpenglow.tla"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}[VERBOSE]${NC} $*" >&2
    fi
}

# Usage information
usage() {
    cat << EOF
Usage: $SCRIPT_NAME <config> [options]

DESCRIPTION:
    Run TLC model checking for the Alpenglow protocol with specified configuration.
    This script is designed for use in CI/CD pipelines and development workflows.

ARGUMENTS:
    config              Configuration name (Small, Medium, EdgeCase, etc.)

OPTIONS:
    --verbose           Enable verbose output
    --ci                Enable CI mode (structured output, no colors)
    --tlc-only          Run only TLC model checking (skip TLAPS)
    --timeout SECONDS   Set timeout in seconds (default: $DEFAULT_TIMEOUT)
    --workers N         Number of TLC worker threads (default: $DEFAULT_WORKERS)
    --config FILE       Use specific configuration file
    --spec FILE         Use specific specification file (default: Alpenglow.tla)
    --results-dir DIR   Output directory for results (default: $RESULTS_DIR)
    --help              Show this help message

CONFIGURATIONS:
    Small               Quick verification with minimal state space
    Medium              Standard verification with moderate state space
    EdgeCase            Edge case scenarios and boundary conditions
    LargeScale          Large-scale verification (extended timeout)
    Adversarial         Adversarial scenarios and attack vectors
    WhitepaperValidation Whitepaper theorem validation
    BoundaryConditions  Boundary condition testing
    AdversarialScenarios Advanced adversarial testing

EXAMPLES:
    $SCRIPT_NAME Small --verbose
    $SCRIPT_NAME Medium --ci --timeout 1800
    $SCRIPT_NAME EdgeCase --tlc-only --workers 8
    $SCRIPT_NAME WhitepaperValidation --config models/Custom.cfg

EXIT CODES:
    0   Success - Model checking passed
    1   Failure - Model checking failed or errors occurred
    2   Timeout - Model checking timed out
    3   Configuration error - Invalid configuration or missing files
    4   Environment error - TLA+ tools not available

EOF
}

# Parse command line arguments
parse_arguments() {
    if [ $# -eq 0 ]; then
        log_error "Configuration name is required"
        usage
        exit 3
    fi

    CONFIG_NAME="$1"
    shift

    while [ $# -gt 0 ]; do
        case "$1" in
            --verbose)
                VERBOSE=true
                ;;
            --ci)
                CI_MODE=true
                # Disable colors in CI mode
                RED=""
                GREEN=""
                YELLOW=""
                BLUE=""
                NC=""
                ;;
            --tlc-only)
                TLC_ONLY=true
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
            --workers)
                shift
                if [ $# -eq 0 ]; then
                    log_error "--workers requires a value"
                    exit 3
                fi
                WORKERS="$1"
                if ! [[ "$WORKERS" =~ ^[0-9]+$ ]]; then
                    log_error "Workers must be a positive integer"
                    exit 3
                fi
                ;;
            --config)
                shift
                if [ $# -eq 0 ]; then
                    log_error "--config requires a file path"
                    exit 3
                fi
                CONFIG_FILE="$1"
                ;;
            --spec)
                shift
                if [ $# -eq 0 ]; then
                    log_error "--spec requires a file path"
                    exit 3
                fi
                SPEC_FILE="$1"
                ;;
            --results-dir)
                shift
                if [ $# -eq 0 ]; then
                    log_error "--results-dir requires a directory path"
                    exit 3
                fi
                RESULTS_DIR="$1"
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

# Validate environment and dependencies
validate_environment() {
    log_verbose "Validating environment..."

    # Check Java availability
    if ! command -v java >/dev/null 2>&1; then
        log_error "Java is not installed or not in PATH"
        exit 4
    fi

    local java_version
    java_version=$(java -version 2>&1 | head -n 1 | cut -d'"' -f2 | cut -d'.' -f1)
    if [ "$java_version" -lt 8 ]; then
        log_error "Java 8 or higher is required (found Java $java_version)"
        exit 4
    fi

    log_verbose "Java version: $(java -version 2>&1 | head -n 1)"

    # Check project structure
    if [ ! -d "$PROJECT_ROOT/specs" ]; then
        log_error "Specs directory not found: $PROJECT_ROOT/specs"
        exit 3
    fi

    if [ ! -d "$PROJECT_ROOT/models" ]; then
        log_error "Models directory not found: $PROJECT_ROOT/models"
        exit 3
    fi

    # Check specification file
    if [ ! -f "$SPEC_FILE" ]; then
        log_error "Specification file not found: $SPEC_FILE"
        exit 3
    fi

    log_verbose "Environment validation completed"
}

# Install or verify TLA+ tools
setup_tla_tools() {
    log_verbose "Setting up TLA+ tools..."

    mkdir -p "$TLA_TOOLS_DIR"

    if [ ! -f "$TLA_TOOLS_JAR" ]; then
        log_info "Downloading TLA+ tools version $DEFAULT_TLA_TOOLS_VERSION..."
        
        local download_url="https://github.com/tlaplus/tlaplus/releases/download/v$DEFAULT_TLA_TOOLS_VERSION/tla2tools.jar"
        
        if command -v wget >/dev/null 2>&1; then
            wget -q "$download_url" -O "$TLA_TOOLS_JAR"
        elif command -v curl >/dev/null 2>&1; then
            curl -sL "$download_url" -o "$TLA_TOOLS_JAR"
        else
            log_error "Neither wget nor curl is available for downloading TLA+ tools"
            exit 4
        fi

        if [ ! -f "$TLA_TOOLS_JAR" ]; then
            log_error "Failed to download TLA+ tools"
            exit 4
        fi
    fi

    # Verify TLA+ tools installation
    if ! java -cp "$TLA_TOOLS_JAR" tla2sany.SANY -h >/dev/null 2>&1; then
        log_error "TLA+ tools verification failed"
        exit 4
    fi

    log_verbose "TLA+ tools ready: $TLA_TOOLS_JAR"
}

# Determine configuration file
determine_config_file() {
    if [ -n "${CONFIG_FILE:-}" ]; then
        if [ ! -f "$CONFIG_FILE" ]; then
            log_error "Specified configuration file not found: $CONFIG_FILE"
            exit 3
        fi
        return
    fi

    # Standard configuration file mapping
    case "$CONFIG_NAME" in
        Small)
            CONFIG_FILE="$PROJECT_ROOT/models/Small.cfg"
            ;;
        Medium)
            CONFIG_FILE="$PROJECT_ROOT/models/Medium.cfg"
            ;;
        EdgeCase)
            CONFIG_FILE="$PROJECT_ROOT/models/EdgeCase.cfg"
            ;;
        LargeScale)
            CONFIG_FILE="$PROJECT_ROOT/models/LargeScale.cfg"
            ;;
        Adversarial)
            CONFIG_FILE="$PROJECT_ROOT/models/Adversarial.cfg"
            ;;
        WhitepaperValidation)
            CONFIG_FILE="$PROJECT_ROOT/models/WhitepaperValidation.cfg"
            ;;
        BoundaryConditions)
            CONFIG_FILE="$PROJECT_ROOT/models/BoundaryConditions.cfg"
            ;;
        AdversarialScenarios)
            CONFIG_FILE="$PROJECT_ROOT/models/AdversarialScenarios.cfg"
            ;;
        *)
            # Try generic configuration file
            CONFIG_FILE="$PROJECT_ROOT/models/$CONFIG_NAME.cfg"
            ;;
    esac

    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        log_error "Available configurations in $PROJECT_ROOT/models/:"
        if [ -d "$PROJECT_ROOT/models" ]; then
            ls -1 "$PROJECT_ROOT/models"/*.cfg 2>/dev/null | sed 's/.*\//  /' | sed 's/\.cfg$//' || log_error "  No .cfg files found"
        fi
        exit 3
    fi

    log_verbose "Using configuration file: $CONFIG_FILE"
}

# Setup results directory and logging
setup_results() {
    mkdir -p "$RESULTS_DIR"
    
    LOG_FILE="$RESULTS_DIR/model_${CONFIG_NAME}.log"
    
    # Initialize log file
    cat > "$LOG_FILE" << EOF
TLA+ Model Checking Log
Configuration: $CONFIG_NAME
Timestamp: $(date -Iseconds)
Specification: $SPEC_FILE
Configuration File: $CONFIG_FILE
Timeout: ${TIMEOUT}s
Workers: $WORKERS
Script Version: $SCRIPT_VERSION

EOF

    log_verbose "Results directory: $RESULTS_DIR"
    log_verbose "Log file: $LOG_FILE"
}

# Run TLC model checking
run_tlc_model_checking() {
    log_info "Starting TLC model checking for configuration: $CONFIG_NAME"
    
    local start_time
    start_time=$(date +%s)
    
    # Prepare TLC command
    local tlc_cmd=(
        "timeout" "$TIMEOUT"
        "java" "-cp" "$TLA_TOOLS_JAR"
        "tlc2.TLC"
        "-config" "$CONFIG_FILE"
        "-workers" "$WORKERS"
        "-cleanup"
    )

    # Add verbose flag if requested
    if [ "$VERBOSE" = true ]; then
        tlc_cmd+=("-verbose")
    fi

    # Add CI-specific flags
    if [ "$CI_MODE" = true ]; then
        tlc_cmd+=("-noGenerateSpecTE")
        tlc_cmd+=("-tool")
    fi

    # Add specification file (must be last, without .tla extension)
    local spec_name
    spec_name=$(basename "$SPEC_FILE" .tla)
    tlc_cmd+=("$spec_name")

    log_verbose "TLC command: ${tlc_cmd[*]}"
    
    # Change to specs directory for TLC execution
    local original_dir
    original_dir=$(pwd)
    cd "$(dirname "$SPEC_FILE")"

    # Execute TLC with timeout and capture output
    local exit_code=0
    local tlc_output
    
    {
        echo "=== TLC Model Checking Started ==="
        echo "Command: ${tlc_cmd[*]}"
        echo "Working directory: $(pwd)"
        echo "Start time: $(date)"
        echo ""
        
        # Run TLC and capture both stdout and stderr
        if tlc_output=$("${tlc_cmd[@]}" 2>&1); then
            echo "$tlc_output"
            echo ""
            echo "=== TLC Model Checking Completed Successfully ==="
        else
            exit_code=$?
            echo "$tlc_output"
            echo ""
            echo "=== TLC Model Checking Failed (exit code: $exit_code) ==="
        fi
        
        echo "End time: $(date)"
        
    } >> "$LOG_FILE"

    # Return to original directory
    cd "$original_dir"

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Analyze results and determine exit status
    local verification_status
    local states_explored=0
    local states_generated=0
    local violations=0
    local properties_checked=0

    if [ $exit_code -eq 124 ]; then
        # Timeout occurred
        verification_status="TIMEOUT"
        log_warn "Model checking timed out after ${TIMEOUT}s"
        exit_code=2
    elif [ $exit_code -eq 0 ]; then
        # Success
        verification_status="VERIFIED"
        log_success "Model checking completed successfully"
        
        # Extract metrics from output
        if [ -n "$tlc_output" ]; then
            states_explored=$(echo "$tlc_output" | grep -o '[0-9]* distinct states' | head -1 | cut -d' ' -f1 || echo "0")
            states_generated=$(echo "$tlc_output" | grep -o '[0-9]* states generated' | head -1 | cut -d' ' -f1 || echo "0")
            violations=$(echo "$tlc_output" | grep -c 'Error:' || echo "0")
            properties_checked=$(echo "$tlc_output" | grep -c 'Property.*satisfied' || echo "0")
        fi
    else
        # Failure
        verification_status="FAILED"
        log_error "Model checking failed with exit code $exit_code"
        
        # Still try to extract some metrics
        if [ -n "$tlc_output" ]; then
            violations=$(echo "$tlc_output" | grep -c 'Error:' || echo "0")
        fi
    fi

    # Generate metrics file
    local metrics_file="$RESULTS_DIR/metrics_${CONFIG_NAME}.json"
    cat > "$metrics_file" << EOF
{
  "config": "$CONFIG_NAME",
  "timestamp": "$(date -Iseconds)",
  "status": "$verification_status",
  "duration_seconds": $duration,
  "timeout_seconds": $TIMEOUT,
  "workers": $WORKERS,
  "states_explored": $states_explored,
  "states_generated": $states_generated,
  "violations_found": $violations,
  "properties_checked": $properties_checked,
  "specification_file": "$SPEC_FILE",
  "configuration_file": "$CONFIG_FILE",
  "log_file": "$LOG_FILE",
  "script_version": "$SCRIPT_VERSION"
}
EOF

    # Output summary
    if [ "$CI_MODE" = true ]; then
        # Structured output for CI
        echo "::group::Model Checking Summary"
        echo "Configuration: $CONFIG_NAME"
        echo "Status: $verification_status"
        echo "Duration: ${duration}s"
        echo "States explored: $states_explored"
        echo "States generated: $states_generated"
        echo "Violations: $violations"
        echo "Properties checked: $properties_checked"
        echo "::endgroup::"
        
        if [ "$verification_status" = "VERIFIED" ]; then
            echo "::notice::Model checking passed for $CONFIG_NAME"
        elif [ "$verification_status" = "TIMEOUT" ]; then
            echo "::warning::Model checking timed out for $CONFIG_NAME"
        else
            echo "::error::Model checking failed for $CONFIG_NAME"
        fi
    else
        # Human-readable output
        echo ""
        log_info "=== Model Checking Summary ==="
        log_info "Configuration: $CONFIG_NAME"
        log_info "Status: $verification_status"
        log_info "Duration: ${duration}s"
        log_info "States explored: $states_explored"
        log_info "States generated: $states_generated"
        log_info "Violations found: $violations"
        log_info "Properties checked: $properties_checked"
        log_info "Log file: $LOG_FILE"
        log_info "Metrics file: $metrics_file"
    fi

    return $exit_code
}

# Cleanup function
cleanup() {
    local exit_code=$?
    
    # Clean up any temporary TLC files
    if [ -d "$(dirname "$SPEC_FILE")" ]; then
        cd "$(dirname "$SPEC_FILE")"
        rm -f states 2>/dev/null || true
        rm -f *.st 2>/dev/null || true
        rm -f *.fp 2>/dev/null || true
        rm -f *_TTrace_*.tla 2>/dev/null || true
    fi
    
    log_verbose "Cleanup completed"
    exit $exit_code
}

# Set up signal handlers
trap cleanup EXIT INT TERM

# Main execution
main() {
    log_info "$SCRIPT_NAME v$SCRIPT_VERSION - TLA+ Model Checking"
    
    parse_arguments "$@"
    validate_environment
    setup_tla_tools
    determine_config_file
    setup_results
    
    log_info "Configuration: $CONFIG_NAME"
    log_info "Timeout: ${TIMEOUT}s"
    log_info "Workers: $WORKERS"
    log_info "Specification: $SPEC_FILE"
    log_info "Configuration file: $CONFIG_FILE"
    
    run_tlc_model_checking
}

# Execute main function with all arguments
main "$@"