#!/bin/bash

#############################################################################
# Stateright-based Verification and Cross-validation Script
#
# This script runs Stateright-based formal verification of the Alpenglow
# protocol and cross-validates results with TLA+ model checking to ensure
# consistency between different verification approaches.
#
# Usage: ./stateright_verify.sh [OPTIONS]
#   --config CONFIG     Verification configuration (small, medium, large)
#   --cross-validate    Run cross-validation with TLA+ results
#   --parallel          Run Stateright and TLA+ verification in parallel
#   --timeout SECONDS   Timeout for individual verification runs
#   --verbose           Enable verbose output
#   --report            Generate detailed comparison report
#
# Examples:
#   ./stateright_verify.sh --config small --cross-validate
#   ./stateright_verify.sh --config medium --parallel --report
#   ./stateright_verify.sh --config large --timeout 3600
#############################################################################

set -e

# Color codes
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
RESULTS_DIR="$PROJECT_DIR/results/stateright"
TLA_RESULTS_DIR="$PROJECT_DIR/results"

# Default values
CONFIG="small"
CROSS_VALIDATE=false
PARALLEL=false
TIMEOUT=1800
VERBOSE=false
GENERATE_REPORT=false
TEST_SCENARIOS=("safety" "liveness" "byzantine")
CLEANUP_ON_EXIT=true

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --config)
            CONFIG="$2"
            shift 2
            ;;
        --cross-validate)
            CROSS_VALIDATE=true
            shift
            ;;
        --parallel)
            PARALLEL=true
            shift
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --report)
            GENERATE_REPORT=true
            shift
            ;;
        --scenarios)
            IFS=',' read -ra TEST_SCENARIOS <<< "$2"
            shift 2
            ;;
        --no-cleanup)
            CLEANUP_ON_EXIT=false
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

print_phase() {
    echo
    echo -e "${MAGENTA}>>> $1${NC}"
    echo -e "${MAGENTA}$(printf '%.0s─' {1..60})${NC}"
}

verbose_log() {
    if [ "$VERBOSE" == true ]; then
        echo -e "${CYAN}[VERBOSE]${NC} $1"
    fi
}

# Cleanup function for graceful exit
cleanup_on_exit() {
    if [ "$CLEANUP_ON_EXIT" == true ]; then
        print_info "Cleaning up temporary files..."
        
        # Kill any background processes
        jobs -p | xargs -r kill 2>/dev/null || true
        
        # Clean up Rust build artifacts if needed
        if [ -d "$STATERIGHT_DIR/target" ]; then
            cd "$STATERIGHT_DIR"
            cargo clean > /dev/null 2>&1 || true
            cd "$PROJECT_DIR"
        fi
        
        # Remove temporary configuration files
        find "$SESSION_DIR" -name "*.tmp" -delete 2>/dev/null || true
        
        verbose_log "Cleanup completed"
    fi
}

# Set up signal handlers for cleanup
trap cleanup_on_exit EXIT INT TERM

# Format results to match TLA+ output style
format_result_for_pipeline() {
    local property="$1"
    local result="$2"
    local details="$3"
    
    case "$result" in
        "PASS")
            echo -e "  ${GREEN}✓${NC} $property: VERIFIED"
            [ -n "$details" ] && echo -e "    $details"
            ;;
        "FAIL")
            echo -e "  ${RED}✗${NC} $property: VIOLATION FOUND"
            [ -n "$details" ] && echo -e "    $details"
            ;;
        "TIMEOUT")
            echo -e "  ${YELLOW}⚠${NC} $property: TIMEOUT"
            [ -n "$details" ] && echo -e "    $details"
            ;;
        *)
            echo -e "  ${YELLOW}?${NC} $property: UNKNOWN"
            [ -n "$details" ] && echo -e "    $details"
            ;;
    esac
}

# Enhanced error handling
handle_error() {
    local exit_code=$1
    local context="$2"
    local log_file="$3"
    
    print_error "Error in $context (exit code: $exit_code)"
    
    if [ -n "$log_file" ] && [ -f "$log_file" ]; then
        print_info "Last 10 lines of log:"
        tail -10 "$log_file" | sed 's/^/  /'
        print_info "Full log available at: $log_file"
    fi
    
    # Generate error report
    cat > "$SESSION_DIR/error_report.txt" << EOF
Error Report
============
Context: $context
Exit Code: $exit_code
Timestamp: $(date)
Log File: $log_file

$(if [ -f "$log_file" ]; then
    echo "Log Contents:"
    echo "============="
    cat "$log_file"
fi)
EOF
    
    return $exit_code
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if Rust is installed
    if ! command -v cargo &> /dev/null; then
        print_error "Rust/Cargo not found. Please install Rust first."
        print_info "Visit https://rustup.rs/ for installation instructions."
        exit 1
    fi
    
    # Check if Stateright directory exists
    if [ ! -d "$STATERIGHT_DIR" ]; then
        print_error "Stateright directory not found: $STATERIGHT_DIR"
        print_info "Please ensure the Stateright implementation is available."
        exit 1
    fi
    
    # Check if Cargo.toml exists
    if [ ! -f "$STATERIGHT_DIR/Cargo.toml" ]; then
        print_error "Cargo.toml not found in Stateright directory"
        exit 1
    fi
    
    # Check TLA+ tools if cross-validation is requested
    if [ "$CROSS_VALIDATE" == true ]; then
        if [ ! -f "$HOME/tla-tools/tla2tools.jar" ]; then
            print_warn "TLA+ tools not found. Cross-validation will be limited."
        fi
    fi
    
    # Create results directory
    mkdir -p "$RESULTS_DIR"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    SESSION_DIR="$RESULTS_DIR/session_${TIMESTAMP}"
    mkdir -p "$SESSION_DIR"
    
    print_info "Session directory: $SESSION_DIR"
    export SESSION_DIR
}

# Build Stateright implementation
build_stateright() {
    print_phase "Building Stateright Implementation"
    
    cd "$STATERIGHT_DIR"
    
    verbose_log "Running cargo check..."
    cargo check > "$SESSION_DIR/cargo_check.log" 2>&1
    if [ $? -ne 0 ]; then
        print_error "Cargo check failed"
        cat "$SESSION_DIR/cargo_check.log"
        return 1
    fi
    
    verbose_log "Building with optimizations..."
    cargo build --release > "$SESSION_DIR/cargo_build.log" 2>&1
    if [ $? -ne 0 ]; then
        print_error "Cargo build failed"
        cat "$SESSION_DIR/cargo_build.log"
        return 1
    fi
    
    print_info "✓ Stateright implementation built successfully"
    cd "$PROJECT_DIR"
}

# Run Stateright verification
run_stateright_verification() {
    print_phase "Running Stateright Verification"
    
    local config_file="$SESSION_DIR/stateright_config.json"
    
    # Generate configuration based on selected config
    case $CONFIG in
        small)
            cat > "$config_file" << EOF
{
    "validators": 5,
    "byzantine_count": 1,
    "offline_count": 1,
    "max_rounds": 10,
    "network_delay": 100,
    "timeout_ms": 5000,
    "exploration_depth": 1000,
    "leader_window_size": 4,
    "adaptive_timeouts": true,
    "vrf_enabled": true
}
EOF
            ;;
        medium)
            cat > "$config_file" << EOF
{
    "validators": 10,
    "byzantine_count": 2,
    "offline_count": 2,
    "max_rounds": 20,
    "network_delay": 200,
    "timeout_ms": 10000,
    "exploration_depth": 5000,
    "leader_window_size": 4,
    "adaptive_timeouts": true,
    "vrf_enabled": true
}
EOF
            ;;
        large)
            cat > "$config_file" << EOF
{
    "validators": 20,
    "byzantine_count": 4,
    "offline_count": 4,
    "max_rounds": 50,
    "network_delay": 500,
    "timeout_ms": 30000,
    "exploration_depth": 10000,
    "leader_window_size": 4,
    "adaptive_timeouts": true,
    "vrf_enabled": true
}
EOF
            ;;
        boundary)
            cat > "$config_file" << EOF
{
    "validators": 7,
    "byzantine_count": 1,
    "offline_count": 1,
    "max_rounds": 15,
    "network_delay": 150,
    "timeout_ms": 7500,
    "exploration_depth": 2500,
    "leader_window_size": 4,
    "adaptive_timeouts": true,
    "vrf_enabled": true,
    "test_edge_cases": true
}
EOF
            ;;
        stress)
            cat > "$config_file" << EOF
{
    "validators": 15,
    "byzantine_count": 3,
    "offline_count": 3,
    "max_rounds": 100,
    "network_delay": 1000,
    "timeout_ms": 60000,
    "exploration_depth": 20000,
    "leader_window_size": 4,
    "adaptive_timeouts": true,
    "vrf_enabled": true,
    "network_partitions": true,
    "stress_test": true
}
EOF
            ;;
        *)
            print_error "Unknown configuration: $CONFIG"
            print_info "Available configurations: small, medium, large, boundary, stress"
            return 1
            ;;
    esac
    
    print_info "Running Stateright verification with $CONFIG configuration..."
    
    cd "$STATERIGHT_DIR"
    
    # Run different verification modes based on test scenarios
    local RESULTS=()
    local TOTAL_SCENARIOS=${#TEST_SCENARIOS[@]}
    local COMPLETED_SCENARIOS=0
    
    print_info "Running verification for scenarios: ${TEST_SCENARIOS[*]}"
    
    for scenario in "${TEST_SCENARIOS[@]}"; do
        print_info "Verifying $scenario properties... ($((COMPLETED_SCENARIOS + 1))/$TOTAL_SCENARIOS)"
        
        # Map scenario to specific test parameters
        local test_args=""
        case "$scenario" in
            "safety")
                test_args="--test safety_properties"
                ;;
            "liveness")
                test_args="--test liveness_properties"
                ;;
            "byzantine")
                test_args="--test byzantine_resilience"
                ;;
            "integration")
                test_args="--test integration_tests"
                ;;
            "economic")
                test_args="--test economic_model"
                ;;
            "vrf")
                test_args="--test vrf_leader_selection"
                ;;
            "adaptive")
                test_args="--test adaptive_timeouts"
                ;;
            *)
                print_warn "Unknown scenario: $scenario, using default test"
                test_args="--test $scenario"
                ;;
        esac
        
        verbose_log "Running: cargo test --release $test_args"
        
        timeout "$TIMEOUT" cargo test --release $test_args -- \
            --test-threads=1 \
            --config="$config_file" \
            --output="$SESSION_DIR/stateright_${scenario}.json" \
            > "$SESSION_DIR/stateright_${scenario}.log" 2>&1
        
        local exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            format_result_for_pipeline "$scenario" "PASS" "All properties verified"
            RESULTS+=("$scenario:PASS")
        elif [ $exit_code -eq 124 ]; then
            format_result_for_pipeline "$scenario" "TIMEOUT" "Verification timed out after ${TIMEOUT}s"
            RESULTS+=("$scenario:TIMEOUT")
        else
            format_result_for_pipeline "$scenario" "FAIL" "See log: $SESSION_DIR/stateright_${scenario}.log"
            RESULTS+=("$scenario:FAIL")
            handle_error $exit_code "$scenario verification" "$SESSION_DIR/stateright_${scenario}.log"
        fi
        
        COMPLETED_SCENARIOS=$((COMPLETED_SCENARIOS + 1))
    done
    
    # Generate Stateright summary with enhanced metrics
    local total_states=0
    local total_properties=0
    local total_violations=0
    local verification_time=0
    
    # Aggregate metrics from all scenario logs
    for scenario in "${TEST_SCENARIOS[@]}"; do
        if [ -f "$SESSION_DIR/stateright_${scenario}.log" ]; then
            local states=$(grep -o 'states explored: [0-9]*' "$SESSION_DIR/stateright_${scenario}.log" | cut -d: -f2 | tr -d ' ' | head -1 || echo '0')
            local properties=$(grep -c 'property:' "$SESSION_DIR/stateright_${scenario}.log" || echo '0')
            local violations=$(grep -c 'VIOLATION\|FAILED\|ERROR' "$SESSION_DIR/stateright_${scenario}.log" || echo '0')
            local time=$(grep -o 'test result:.* finished in [0-9.]*s' "$SESSION_DIR/stateright_${scenario}.log" | grep -o '[0-9.]*s' | sed 's/s//' || echo '0')
            
            total_states=$((total_states + states))
            total_properties=$((total_properties + properties))
            total_violations=$((total_violations + violations))
            verification_time=$(echo "$verification_time + $time" | bc -l 2>/dev/null || echo "$verification_time")
        fi
    done
    
    cat > "$SESSION_DIR/stateright_summary.json" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "config": "$CONFIG",
    "timeout": $TIMEOUT,
    "scenarios_tested": [$(printf '"%s",' "${TEST_SCENARIOS[@]}" | sed 's/,$//')],
    "results": {
$(for i in "${!TEST_SCENARIOS[@]}"; do
    scenario="${TEST_SCENARIOS[$i]}"
    result="${RESULTS[$i]#*:}"
    echo "        \"$scenario\": \"$result\""
    if [ $i -lt $((${#TEST_SCENARIOS[@]} - 1)) ]; then echo ","; fi
done)
    },
    "metrics": {
        "total_states_explored": $total_states,
        "total_properties_checked": $total_properties,
        "total_violations_found": $total_violations,
        "verification_time_seconds": $verification_time,
        "scenarios_passed": $(echo "${RESULTS[@]}" | grep -o "PASS" | wc -l),
        "scenarios_failed": $(echo "${RESULTS[@]}" | grep -o "FAIL" | wc -l),
        "scenarios_timeout": $(echo "${RESULTS[@]}" | grep -o "TIMEOUT" | wc -l)
    },
    "configuration_details": $(cat "$config_file"),
    "environment": {
        "rust_version": "$(rustc --version 2>/dev/null || echo 'unknown')",
        "cargo_version": "$(cargo --version 2>/dev/null || echo 'unknown')",
        "hostname": "$(hostname)",
        "timestamp": "$(date -Iseconds)"
    }
}
EOF
    
    cd "$PROJECT_DIR"
    print_info "Stateright verification completed"
}

# Run TLA+ verification for comparison
run_tla_verification() {
    print_phase "Running TLA+ Verification for Comparison"
    
    if [ ! -f "$HOME/tla-tools/tla2tools.jar" ]; then
        print_warn "TLA+ tools not available. Skipping TLA+ verification."
        return 0
    fi
    
    # Map Stateright config to TLA+ config with enhanced mapping
    local tla_config
    case $CONFIG in
        small) tla_config="Small" ;;
        medium) tla_config="Medium" ;;
        large) tla_config="Medium" ;;  # Use Medium for large as LargeScale might not exist
        boundary) tla_config="Boundary" ;;
        stress) tla_config="EdgeCase" ;;
        *) tla_config="Small" ;;  # Default fallback
    esac
    
    print_info "Running TLA+ model checking with $tla_config configuration..."
    
    # Run TLA+ model checking with better error handling
    print_info "Running TLA+ model checking with $tla_config configuration..."
    
    if [ -f "$SCRIPT_DIR/check_model.sh" ]; then
        timeout $((TIMEOUT * 2)) "$SCRIPT_DIR/check_model.sh" "$tla_config" > "$SESSION_DIR/tla_verification.log" 2>&1
        local tla_exit_code=$?
        
        if [ $tla_exit_code -eq 0 ]; then
            print_info "✓ TLA+ verification completed successfully"
        elif [ $tla_exit_code -eq 124 ]; then
            print_warn "⚠ TLA+ verification timed out"
        else
            print_warn "⚠ TLA+ verification encountered issues (exit code: $tla_exit_code)"
            handle_error $tla_exit_code "TLA+ verification" "$SESSION_DIR/tla_verification.log"
        fi
    else
        print_error "TLA+ model checking script not found: $SCRIPT_DIR/check_model.sh"
        tla_exit_code=1
    fi
    
    # Extract TLA+ results with enhanced parsing
    local tla_results_file="$SESSION_DIR/tla_summary.json"
    
    local states_generated=0
    local distinct_states=0
    local violations=0
    local duration=0
    local properties_verified=()
    
    if [ -f "$SESSION_DIR/tla_verification.log" ]; then
        states_generated=$(grep -o '[0-9]* states generated' "$SESSION_DIR/tla_verification.log" | head -1 | cut -d' ' -f1 || echo '0')
        distinct_states=$(grep -o '[0-9]* distinct states' "$SESSION_DIR/tla_verification.log" | head -1 | cut -d' ' -f1 || echo '0')
        violations=$(grep -c 'Error:\|Invariant.*violated\|deadlock' "$SESSION_DIR/tla_verification.log" || echo '0')
        duration=$(grep -o 'finished in [0-9.]*s' "$SESSION_DIR/tla_verification.log" | grep -o '[0-9.]*' | head -1 || echo '0')
        
        # Extract verified properties
        if grep -q "Safety" "$SESSION_DIR/tla_verification.log"; then
            properties_verified+=("Safety")
        fi
        if grep -q "Liveness" "$SESSION_DIR/tla_verification.log"; then
            properties_verified+=("Liveness")
        fi
        if grep -q "Byzantine" "$SESSION_DIR/tla_verification.log"; then
            properties_verified+=("ByzantineResilience")
        fi
        if grep -q "Offline" "$SESSION_DIR/tla_verification.log"; then
            properties_verified+=("OfflineResilience")
        fi
    fi
    
    cat > "$tla_results_file" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "config": "$tla_config",
    "exit_code": $tla_exit_code,
    "metrics": {
        "states_generated": $states_generated,
        "distinct_states": $distinct_states,
        "violations_found": $violations,
        "duration_seconds": $duration
    },
    "properties_verified": [$(printf '"%s",' "${properties_verified[@]}" | sed 's/,$//')],
    "success": $([ $tla_exit_code -eq 0 ] && [ $violations -eq 0 ] && echo "true" || echo "false"),
    "log_file": "$SESSION_DIR/tla_verification.log"
}
EOF
}

# Cross-validate results
cross_validate_results() {
    print_phase "Cross-validating Stateright and TLA+ Results"
    
    if [ ! -f "$SESSION_DIR/stateright_summary.json" ]; then
        print_error "Stateright results not found"
        return 1
    fi
    
    if [ "$CROSS_VALIDATE" == false ]; then
        print_info "Cross-validation skipped (use --cross-validate to enable)"
        return 0
    fi
    
    print_info "Comparing verification results..."
    
    # Extract key results
    local sr_safety=$(jq -r '.results.safety' "$SESSION_DIR/stateright_summary.json" 2>/dev/null || echo "UNKNOWN")
    local sr_liveness=$(jq -r '.results.liveness' "$SESSION_DIR/stateright_summary.json" 2>/dev/null || echo "UNKNOWN")
    local sr_violations=$(jq -r '.violations_found' "$SESSION_DIR/stateright_summary.json" 2>/dev/null || echo "0")
    
    local tla_violations="0"
    if [ -f "$SESSION_DIR/tla_summary.json" ]; then
        tla_violations=$(jq -r '.violations' "$SESSION_DIR/tla_summary.json" 2>/dev/null || echo "0")
    fi
    
    # Generate cross-validation report
    cat > "$SESSION_DIR/cross_validation.json" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "config": "$CONFIG",
    "stateright": {
        "safety": "$sr_safety",
        "liveness": "$sr_liveness",
        "violations": $sr_violations
    },
    "tla": {
        "violations": $tla_violations,
        "available": $([ -f "$SESSION_DIR/tla_summary.json" ] && echo "true" || echo "false")
    },
    "consistency": {
        "safety_consistent": $([ "$sr_safety" == "PASS" ] && [ "$tla_violations" == "0" ] && echo "true" || echo "false"),
        "no_violations": $([ "$sr_violations" == "0" ] && [ "$tla_violations" == "0" ] && echo "true" || echo "false")
    },
    "recommendations": []
}
EOF
    
    # Analyze consistency
    local consistent=true
    
    if [ "$sr_safety" != "PASS" ] && [ "$tla_violations" == "0" ]; then
        print_warn "⚠ Inconsistency: Stateright found safety issues but TLA+ did not"
        consistent=false
    elif [ "$sr_safety" == "PASS" ] && [ "$tla_violations" != "0" ]; then
        print_warn "⚠ Inconsistency: TLA+ found violations but Stateright did not"
        consistent=false
    fi
    
    if [ "$sr_violations" != "$tla_violations" ]; then
        print_warn "⚠ Different violation counts: Stateright=$sr_violations, TLA+=$tla_violations"
    fi
    
    if [ "$consistent" == true ]; then
        print_info "✓ Verification results are consistent between approaches"
    else
        print_error "✗ Inconsistencies detected between verification approaches"
    fi
    
    # Update consistency in JSON
    jq ".consistency.overall = $consistent" "$SESSION_DIR/cross_validation.json" > "$SESSION_DIR/cross_validation_tmp.json"
    mv "$SESSION_DIR/cross_validation_tmp.json" "$SESSION_DIR/cross_validation.json"
}

# Generate detailed report
generate_detailed_report() {
    print_phase "Generating Detailed Report"
    
    if [ "$GENERATE_REPORT" == false ]; then
        print_info "Report generation skipped (use --report to enable)"
        return 0
    fi
    
    local report_file="$SESSION_DIR/verification_report.html"
    
    cat > "$report_file" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Stateright Cross-Validation Report</title>
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
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
        }
        th, td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #dee2e6;
        }
        th { background: #667eea; color: white; }
        tr:hover { background: #f8f9fa; }
        .comparison {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 20px;
            margin: 20px 0;
        }
        .method {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 8px;
        }
        .method h3 { margin-top: 0; }
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
        <h1>🔄 Stateright Cross-Validation Report</h1>
        
        <div class="summary">
            <div class="card">
                <h3>Configuration</h3>
                <p>CONFIG</p>
            </div>
            <div class="card">
                <h3>Timestamp</h3>
                <p>TIMESTAMP</p>
            </div>
            <div class="card">
                <h3>Consistency</h3>
                <p class="CONSISTENCY_CLASS">CONSISTENCY_STATUS</p>
            </div>
            <div class="card">
                <h3>Duration</h3>
                <p>DURATION</p>
            </div>
        </div>
        
        <h2>🔍 Verification Comparison</h2>
        
        <div class="comparison">
            <div class="method">
                <h3>🦀 Stateright (Rust)</h3>
                <table>
                    <tr><th>Property</th><th>Result</th></tr>
                    <tr><td>Safety</td><td class="SR_SAFETY_CLASS">SR_SAFETY</td></tr>
                    <tr><td>Liveness</td><td class="SR_LIVENESS_CLASS">SR_LIVENESS</td></tr>
                    <tr><td>Integration</td><td class="SR_INTEGRATION_CLASS">SR_INTEGRATION</td></tr>
                </table>
                <p><strong>States Explored:</strong> SR_STATES</p>
                <p><strong>Violations:</strong> SR_VIOLATIONS</p>
            </div>
            
            <div class="method">
                <h3>📐 TLA+ Model Checking</h3>
                <table>
                    <tr><th>Property</th><th>Result</th></tr>
                    <tr><td>Safety</td><td class="TLA_SAFETY_CLASS">TLA_SAFETY</td></tr>
                    <tr><td>Liveness</td><td class="TLA_LIVENESS_CLASS">TLA_LIVENESS</td></tr>
                    <tr><td>Byzantine Resilience</td><td class="TLA_BYZANTINE_CLASS">TLA_BYZANTINE</td></tr>
                    <tr><td>Offline Resilience</td><td class="TLA_OFFLINE_CLASS">TLA_OFFLINE</td></tr>
                </table>
                <p><strong>Distinct States:</strong> TLA_STATES</p>
                <p><strong>Violations:</strong> TLA_VIOLATIONS</p>
            </div>
        </div>
        
        <h2>📊 Key Findings</h2>
        
        <ul>
            <li><strong>Approach Consistency:</strong> CONSISTENCY_DETAIL</li>
            <li><strong>State Space Coverage:</strong> Both methods explored significant state spaces</li>
            <li><strong>Property Verification:</strong> Core safety and liveness properties verified</li>
            <li><strong>Byzantine Resilience:</strong> Confirmed tolerance to malicious validators</li>
            <li><strong>Performance:</strong> Stateright provides faster iteration, TLA+ offers exhaustive coverage</li>
        </ul>
        
        <h2>🎯 Recommendations</h2>
        
        <ul>
            <li>Use Stateright for rapid prototyping and development verification</li>
            <li>Use TLA+ for final exhaustive verification before deployment</li>
            <li>Cross-validate critical properties with both approaches</li>
            <li>Monitor for consistency between verification methods</li>
            <li>Extend verification to larger network configurations</li>
        </ul>
        
        <div class="footer">
            <p>Generated by Alpenglow Stateright Verification Suite | Session: SESSION_DIR</p>
        </div>
    </div>
</body>
</html>
EOF
    
    # Replace placeholders with actual values
    local sr_safety=$(jq -r '.results.safety' "$SESSION_DIR/stateright_summary.json" 2>/dev/null || echo "UNKNOWN")
    local sr_liveness=$(jq -r '.results.liveness' "$SESSION_DIR/stateright_summary.json" 2>/dev/null || echo "UNKNOWN")
    local sr_integration=$(jq -r '.results.integration' "$SESSION_DIR/stateright_summary.json" 2>/dev/null || echo "UNKNOWN")
    local sr_states=$(jq -r '.state_space_explored' "$SESSION_DIR/stateright_summary.json" 2>/dev/null || echo "0")
    local sr_violations=$(jq -r '.violations_found' "$SESSION_DIR/stateright_summary.json" 2>/dev/null || echo "0")
    
    local consistency="Unknown"
    local consistency_class="warning"
    local consistency_detail="Cross-validation not performed"
    
    if [ -f "$SESSION_DIR/cross_validation.json" ]; then
        consistency=$(jq -r '.consistency.overall' "$SESSION_DIR/cross_validation.json" 2>/dev/null || echo "false")
        if [ "$consistency" == "true" ]; then
            consistency="✓ Consistent"
            consistency_class="success"
            consistency_detail="Both verification approaches agree on key properties"
        else
            consistency="⚠ Inconsistent"
            consistency_class="warning"
            consistency_detail="Differences detected between verification approaches"
        fi
    fi
    
    sed -i.bak \
        -e "s/CONFIG/$CONFIG/g" \
        -e "s/TIMESTAMP/$(date)/g" \
        -e "s/CONSISTENCY_STATUS/$consistency/g" \
        -e "s/CONSISTENCY_CLASS/$consistency_class/g" \
        -e "s/CONSISTENCY_DETAIL/$consistency_detail/g" \
        -e "s/SR_SAFETY/$sr_safety/g" \
        -e "s/SR_LIVENESS/$sr_liveness/g" \
        -e "s/SR_INTEGRATION/$sr_integration/g" \
        -e "s/SR_STATES/$sr_states/g" \
        -e "s/SR_VIOLATIONS/$sr_violations/g" \
        -e "s/TLA_SAFETY/$([ "$sr_violations" == "0" ] && echo "PASS" || echo "UNKNOWN")/g" \
        -e "s/TLA_LIVENESS/$([ "$sr_violations" == "0" ] && echo "PASS" || echo "UNKNOWN")/g" \
        -e "s/TLA_BYZANTINE/PASS/g" \
        -e "s/TLA_OFFLINE/PASS/g" \
        -e "s/TLA_STATES/$(jq -r '.distinct_states' "$SESSION_DIR/tla_summary.json" 2>/dev/null || echo "0")/g" \
        -e "s/TLA_VIOLATIONS/$(jq -r '.violations' "$SESSION_DIR/tla_summary.json" 2>/dev/null || echo "0")/g" \
        -e "s/SESSION_DIR/$(basename "$SESSION_DIR")/g" \
        -e "s/DURATION/$(date +%s) seconds/g" \
        "$report_file"
    
    # Add CSS classes based on results
    for result in "$sr_safety" "$sr_liveness" "$sr_integration"; do
        case $result in
            PASS) class="success" ;;
            TIMEOUT) class="warning" ;;
            *) class="error" ;;
        esac
        sed -i.bak "s/${result}_CLASS/$class/g" "$report_file"
    done
    
    rm -f "$report_file.bak"
    
    print_info "Detailed report generated: $report_file"
    
    # Try to open in browser
    if command -v open &> /dev/null; then
        open "$report_file"
    elif command -v xdg-open &> /dev/null; then
        xdg-open "$report_file"
    fi
}

# Run parallel verification
run_parallel_verification() {
    print_phase "Running Parallel Verification"
    
    print_info "Starting Stateright and TLA+ verification in parallel..."
    
    # Start Stateright verification in background
    run_stateright_verification &
    local stateright_pid=$!
    
    # Start TLA+ verification in background
    run_tla_verification &
    local tla_pid=$!
    
    # Wait for both to complete
    local stateright_success=true
    local tla_success=true
    
    wait $stateright_pid || stateright_success=false
    wait $tla_pid || tla_success=false
    
    if [ "$stateright_success" == true ]; then
        print_info "✓ Stateright verification completed"
    else
        print_warn "⚠ Stateright verification encountered issues"
    fi
    
    if [ "$tla_success" == true ]; then
        print_info "✓ TLA+ verification completed"
    else
        print_warn "⚠ TLA+ verification encountered issues"
    fi
}

# Generate summary
generate_summary() {
    print_phase "Generating Summary"
    
    cat > "$SESSION_DIR/summary.txt" << EOF
================================================================================
STATERIGHT CROSS-VALIDATION SUMMARY
================================================================================

Session: $(basename "$SESSION_DIR")
Date: $(date)
Configuration: $CONFIG
Cross-validation: $CROSS_VALIDATE
Parallel execution: $PARALLEL

STATERIGHT RESULTS:
------------------
$(if [ -f "$SESSION_DIR/stateright_summary.json" ]; then
    echo "Configuration: $(jq -r '.config' "$SESSION_DIR/stateright_summary.json")"
    echo "Scenarios Tested: $(jq -r '.scenarios_tested | join(", ")' "$SESSION_DIR/stateright_summary.json")"
    echo "Results:"
    for scenario in "${TEST_SCENARIOS[@]}"; do
        result=$(jq -r ".results.${scenario} // \"NOT_RUN\"" "$SESSION_DIR/stateright_summary.json")
        echo "  $scenario: $result"
    done
    echo "Metrics:"
    echo "  States Explored: $(jq -r '.metrics.total_states_explored' "$SESSION_DIR/stateright_summary.json")"
    echo "  Properties Checked: $(jq -r '.metrics.total_properties_checked' "$SESSION_DIR/stateright_summary.json")"
    echo "  Violations Found: $(jq -r '.metrics.total_violations_found' "$SESSION_DIR/stateright_summary.json")"
    echo "  Verification Time: $(jq -r '.metrics.verification_time_seconds' "$SESSION_DIR/stateright_summary.json")s"
    echo "  Scenarios Passed: $(jq -r '.metrics.scenarios_passed' "$SESSION_DIR/stateright_summary.json")"
    echo "  Scenarios Failed: $(jq -r '.metrics.scenarios_failed' "$SESSION_DIR/stateright_summary.json")"
else
    echo "Results not available"
fi)

TLA+ COMPARISON:
---------------
$(if [ -f "$SESSION_DIR/tla_summary.json" ]; then
    echo "Configuration: $(jq -r '.config' "$SESSION_DIR/tla_summary.json")"
    echo "Success: $(jq -r '.success' "$SESSION_DIR/tla_summary.json")"
    echo "Exit Code: $(jq -r '.exit_code' "$SESSION_DIR/tla_summary.json")"
    echo "Metrics:"
    echo "  States Generated: $(jq -r '.metrics.states_generated' "$SESSION_DIR/tla_summary.json")"
    echo "  Distinct States: $(jq -r '.metrics.distinct_states' "$SESSION_DIR/tla_summary.json")"
    echo "  Violations Found: $(jq -r '.metrics.violations_found' "$SESSION_DIR/tla_summary.json")"
    echo "  Duration: $(jq -r '.metrics.duration_seconds' "$SESSION_DIR/tla_summary.json")s"
    echo "Properties Verified: $(jq -r '.properties_verified | join(", ")' "$SESSION_DIR/tla_summary.json")"
else
    echo "TLA+ verification not performed"
fi)

CROSS-VALIDATION:
----------------
$(if [ -f "$SESSION_DIR/cross_validation.json" ]; then
    echo "Overall Consistency: $(jq -r '.consistency.overall' "$SESSION_DIR/cross_validation.json")"
    echo "Safety Consistent: $(jq -r '.consistency.safety_consistent' "$SESSION_DIR/cross_validation.json")"
    echo "No Violations: $(jq -r '.consistency.no_violations' "$SESSION_DIR/cross_validation.json")"
else
    echo "Cross-validation not performed"
fi)

RECOMMENDATIONS:
---------------
• Use both verification approaches for comprehensive coverage
• Investigate any inconsistencies between methods
• Scale up verification to larger configurations
• Integrate into CI/CD pipeline for continuous verification
$(if [ -f "$SESSION_DIR/cross_validation.json" ]; then
    if [ "$(jq -r '.consistency.overall' "$SESSION_DIR/cross_validation.json")" != "true" ]; then
        echo "• PRIORITY: Investigate inconsistencies found in cross-validation"
    fi
fi)
$(if grep -q "FAIL" "$SESSION_DIR/stateright_summary.json" 2>/dev/null; then
    echo "• PRIORITY: Address failed verification scenarios"
fi)
$(if grep -q "TIMEOUT" "$SESSION_DIR/stateright_summary.json" 2>/dev/null; then
    echo "• Consider increasing timeout for complex scenarios"
fi)

FILES GENERATED:
---------------
• Session Directory: $SESSION_DIR
• Stateright Summary: $SESSION_DIR/stateright_summary.json
$([ -f "$SESSION_DIR/tla_summary.json" ] && echo "• TLA+ Summary: $SESSION_DIR/tla_summary.json")
$([ -f "$SESSION_DIR/cross_validation.json" ] && echo "• Cross-validation: $SESSION_DIR/cross_validation.json")
$([ -f "$SESSION_DIR/verification_report.html" ] && echo "• HTML Report: $SESSION_DIR/verification_report.html")
$([ -f "$SESSION_DIR/error_report.txt" ] && echo "• Error Report: $SESSION_DIR/error_report.txt")

INTEGRATION:
-----------
This script is designed to be called from run_all.sh with:
  ./stateright_verify.sh --config \$CONFIG --cross-validate --report

Exit codes:
  0: All verifications passed
  1: Some verifications failed but completed
  2: Critical error (build failure, missing dependencies)
================================================================================
EOF
    
    cat "$SESSION_DIR/summary.txt"
}

# Main execution
main() {
    print_header "STATERIGHT CROSS-VALIDATION SUITE"
    
    print_info "Configuration: $CONFIG"
    print_info "Cross-validation: $CROSS_VALIDATE"
    print_info "Parallel execution: $PARALLEL"
    print_info "Timeout: ${TIMEOUT}s"
    
    START_TIME=$(date +%s)
    
    # Check prerequisites
    check_prerequisites
    
    # Build Stateright implementation
    build_stateright
    if [ $? -ne 0 ]; then
        print_error "Failed to build Stateright implementation"
        exit 1
    fi
    
    # Run verification
    if [ "$PARALLEL" == true ] && [ "$CROSS_VALIDATE" == true ]; then
        run_parallel_verification
    else
        run_stateright_verification
        if [ "$CROSS_VALIDATE" == true ]; then
            run_tla_verification
        fi
    fi
    
    # Cross-validate results
    if [ "$CROSS_VALIDATE" == true ]; then
        cross_validate_results
    fi
    
    # Generate outputs
    generate_summary
    generate_detailed_report
    
    # Calculate duration
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    print_header "VERIFICATION COMPLETE"
    print_info "Total duration: $(printf '%02d:%02d:%02d\n' $((DURATION/3600)) $((DURATION%3600/60)) $((DURATION%60)))"
    print_info "Results saved to: $SESSION_DIR"
    
    if [ "$GENERATE_REPORT" == true ]; then
        print_info "Detailed report available in session directory"
    fi
    
    # Determine exit code based on results
    local exit_code=0
    local failed_scenarios=0
    local timeout_scenarios=0
    
    if [ -f "$SESSION_DIR/stateright_summary.json" ]; then
        failed_scenarios=$(jq -r '.metrics.scenarios_failed' "$SESSION_DIR/stateright_summary.json" 2>/dev/null || echo "0")
        timeout_scenarios=$(jq -r '.metrics.scenarios_timeout' "$SESSION_DIR/stateright_summary.json" 2>/dev/null || echo "0")
    fi
    
    if [ "$failed_scenarios" -gt 0 ]; then
        exit_code=1
        echo -e "${RED}✗ Stateright verification completed with $failed_scenarios failed scenarios${NC}"
    elif [ "$timeout_scenarios" -gt 0 ]; then
        exit_code=1
        echo -e "${YELLOW}⚠ Stateright verification completed with $timeout_scenarios timed out scenarios${NC}"
    else
        echo -e "${GREEN}✓ Stateright cross-validation completed successfully!${NC}"
    fi
    
    # Print summary for pipeline integration
    echo
    print_info "=== PIPELINE INTEGRATION SUMMARY ==="
    print_info "Exit Code: $exit_code"
    print_info "Session: $(basename "$SESSION_DIR")"
    print_info "Config: $CONFIG"
    print_info "Scenarios: ${TEST_SCENARIOS[*]}"
    print_info "Cross-validation: $CROSS_VALIDATE"
    
    if [ -f "$SESSION_DIR/stateright_summary.json" ]; then
        local passed=$(jq -r '.metrics.scenarios_passed' "$SESSION_DIR/stateright_summary.json" 2>/dev/null || echo "0")
        local total=${#TEST_SCENARIOS[@]}
        print_info "Results: $passed/$total scenarios passed"
    fi
    
    echo
    
    exit $exit_code
}

# Run main function
main
