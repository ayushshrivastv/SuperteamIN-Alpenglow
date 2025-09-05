#!/bin/bash

#############################################################################
# TLC Model Checking Script for Alpenglow Protocol
#
# Usage: ./check_model.sh [CONFIG] [OPTIONS]
#   CONFIG: Small, Medium, or Stress (default: Small)
#   OPTIONS: Additional TLC options
#
# Examples:
#   ./check_model.sh Small           # Run small configuration
#   ./check_model.sh Medium -workers 4  # Run with 4 workers
#   ./check_model.sh Stress -simulate   # Run simulation mode
#############################################################################

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SPECS_DIR="$PROJECT_DIR/specs"
MODELS_DIR="$PROJECT_DIR/models"
RESULTS_DIR="$PROJECT_DIR/results"
TLC_JAR="$HOME/tla-tools/tla2tools.jar"
PROPERTY_MAPPING_FILE="$SCRIPT_DIR/property_mapping.json"

# Default values
CONFIG="${1:-Small}"
shift || true
ADDITIONAL_ARGS="$@"
DYNAMIC_CONSTANTS=""
OUTPUT_JSON=false
CROSS_VALIDATE=false
SIMULATE_MODE=false
TIMEOUT=3600

# Parse additional arguments for enhanced features
while [[ $# -gt 0 ]]; do
    case $1 in
        --constants)
            DYNAMIC_CONSTANTS="$2"
            shift 2
            ;;
        --json)
            OUTPUT_JSON=true
            shift
            ;;
        --cross-validate)
            CROSS_VALIDATE=true
            shift
            ;;
        --simulate)
            SIMULATE_MODE=true
            shift
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        *)
            # Keep other arguments for TLC
            ADDITIONAL_ARGS="$ADDITIONAL_ARGS $1"
            shift
            ;;
    esac
done

# Java memory settings based on configuration
case "$CONFIG" in
    Small)
        JAVA_HEAP="-Xmx2G"
        WORKERS=2
        ;;
    Medium)
        JAVA_HEAP="-Xmx8G"
        WORKERS=4
        ;;
    Boundary)
        JAVA_HEAP="-Xmx4G"
        WORKERS=3
        ;;
    EdgeCase)
        JAVA_HEAP="-Xmx4G"
        WORKERS=2
        ;;
    Partition)
        JAVA_HEAP="-Xmx8G"
        WORKERS=4
        ;;
    *)
        echo -e "${RED}[ERROR]${NC} Unknown configuration: $CONFIG"
        print_usage
        exit 1
        ;;
esac

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
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}================================================${NC}"
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if TLA+ tools exist
    if [ ! -f "$TLC_JAR" ]; then
        print_error "TLA+ tools not found. Please run setup.sh first."
        exit 1
    fi
    
    # Check if specification exists
    if [ ! -f "$SPECS_DIR/Alpenglow.tla" ]; then
        print_error "Alpenglow.tla not found in $SPECS_DIR"
        exit 1
    fi
    
    # Check if configuration exists
    if [ ! -f "$MODELS_DIR/$CONFIG.cfg" ]; then
        print_error "Configuration file $CONFIG.cfg not found in $MODELS_DIR"
        exit 1
    fi
    
    # Check property mapping file if cross-validation is enabled
    if [ "$CROSS_VALIDATE" == true ] && [ ! -f "$PROPERTY_MAPPING_FILE" ]; then
        print_warn "Property mapping file not found: $PROPERTY_MAPPING_FILE"
        print_warn "Cross-validation features will be limited"
    fi
    
    # Create results directory
    mkdir -p "$RESULTS_DIR"
    
    print_info "Prerequisites satisfied"
}

# Generate dynamic configuration file with constants
generate_dynamic_config() {
    local base_config="$MODELS_DIR/$CONFIG.cfg"
    local dynamic_config="$RESULT_DIR/dynamic_$CONFIG.cfg"
    
    if [ -n "$DYNAMIC_CONSTANTS" ]; then
        print_info "Generating dynamic configuration with constants: $DYNAMIC_CONSTANTS"
        
        # Copy base configuration
        cp "$base_config" "$dynamic_config"
        
        # Parse and add dynamic constants
        IFS=',' read -ra CONST_PAIRS <<< "$DYNAMIC_CONSTANTS"
        for pair in "${CONST_PAIRS[@]}"; do
            IFS='=' read -ra CONST_KV <<< "$pair"
            if [ ${#CONST_KV[@]} -eq 2 ]; then
                local const_name="${CONST_KV[0]}"
                local const_value="${CONST_KV[1]}"
                
                # Check if constant already exists in config
                if grep -q "^CONSTANT $const_name" "$dynamic_config"; then
                    # Replace existing constant
                    sed -i.bak "s/^CONSTANT $const_name.*/CONSTANT $const_name = $const_value/" "$dynamic_config"
                else
                    # Add new constant
                    echo "CONSTANT $const_name = $const_value" >> "$dynamic_config"
                fi
                
                print_info "  Added constant: $const_name = $const_value"
            fi
        done
        
        CONFIG_FILE="$dynamic_config"
    else
        CONFIG_FILE="$base_config"
    fi
}

# Clean previous results
clean_results() {
    print_info "Cleaning previous results..."
    
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    RESULT_DIR="$RESULTS_DIR/${CONFIG}_${TIMESTAMP}"
    mkdir -p "$RESULT_DIR"
    
    # Move old state files if they exist
    if [ -d "$SPECS_DIR/states" ]; then
        mv "$SPECS_DIR/states" "$RESULT_DIR/states_backup" 2>/dev/null || true
    fi
    
    print_info "Results will be saved to: $RESULT_DIR"
    
    # Generate dynamic configuration if needed
    generate_dynamic_config
}

# Run syntax check
check_syntax() {
    print_info "Checking specification syntax..."
    
    java -cp "$TLC_JAR" tla2sany.SANY \
        "$SPECS_DIR/Alpenglow.tla" > "$RESULT_DIR/syntax_check.log" 2>&1
    
    if [ $? -eq 0 ]; then
        print_info "✓ Syntax check passed"
    else
        print_error "✗ Syntax errors found. See $RESULT_DIR/syntax_check.log"
        exit 1
    fi
}

# Run model checking
run_tlc() {
    print_header "Running TLC Model Checker"
    
    echo "Configuration: $CONFIG"
    echo "Workers: $WORKERS"
    echo "Memory: $JAVA_HEAP"
    echo "Additional args: $ADDITIONAL_ARGS"
    echo
    
    # Prepare TLC command with enhanced options
    local tlc_options="-workers $WORKERS -cleanup -deadlock -coverage 1 -terse -metadir $RESULT_DIR/states"
    
    # Add simulation mode if requested
    if [ "$SIMULATE_MODE" == true ]; then
        tlc_options="$tlc_options -simulate"
        print_info "Running in simulation mode"
    fi
    
    # Add timeout if specified
    if [ "$TIMEOUT" -gt 0 ]; then
        tlc_options="$tlc_options -deadlock -lncheck final"
        print_info "Timeout set to: ${TIMEOUT}s"
    fi
    
    TLC_CMD="timeout ${TIMEOUT}s java $JAVA_HEAP -cp $TLC_JAR tlc2.TLC \
        -config $CONFIG_FILE \
        $tlc_options \
        $ADDITIONAL_ARGS \
        $SPECS_DIR/Alpenglow.tla"
    
    # Run TLC with output capture
    print_info "Starting model checking..."
    echo "Command: $TLC_CMD"
    echo
    
    # Create named pipe for real-time output processing
    PIPE=$(mktemp -u)
    mkfifo "$PIPE"
    
    # Start background process to monitor output
    (
        ERRORS=0
        WARNINGS=0
        STATES=0
        
        while IFS= read -r line; do
            echo "$line"
            
            # Track progress
            if [[ "$line" == *"states generated"* ]]; then
                STATES=$(echo "$line" | grep -oE '[0-9]+' | head -1)
            elif [[ "$line" == *"Error:"* ]] || [[ "$line" == *"error"* ]]; then
                ERRORS=$((ERRORS + 1))
            elif [[ "$line" == *"Warning:"* ]] || [[ "$line" == *"warning"* ]]; then
                WARNINGS=$((WARNINGS + 1))
            fi
        done < "$PIPE"
    ) &
    MONITOR_PID=$!
    
    # Run TLC with timeout handling
    START_TIME=$(date +%s)
    
    eval "$TLC_CMD" 2>&1 | tee "$PIPE" > "$RESULT_DIR/tlc_output.log"
    TLC_EXIT_CODE=$?
    
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    # Handle timeout exit code
    if [ $TLC_EXIT_CODE -eq 124 ]; then
        print_warn "Model checking timed out after ${TIMEOUT}s"
        echo "TIMEOUT: Model checking exceeded ${TIMEOUT}s limit" >> "$RESULT_DIR/tlc_output.log"
    fi
    
    # Clean up
    rm "$PIPE"
    wait $MONITOR_PID 2>/dev/null || true
    
    # Check results
    if [ $TLC_EXIT_CODE -eq 0 ]; then
        print_info "✓ Model checking completed successfully"
    else
        print_error "✗ Model checking failed with exit code $TLC_EXIT_CODE"
    fi
    
    echo
    print_info "Duration: $(format_duration $DURATION)"
}

# Format duration in human-readable format
format_duration() {
    local duration=$1
    local hours=$((duration / 3600))
    local minutes=$(( (duration % 3600) / 60 ))
    local seconds=$((duration % 60))
    
    if [ $hours -gt 0 ]; then
        echo "${hours}h ${minutes}m ${seconds}s"
    elif [ $minutes -gt 0 ]; then
        echo "${minutes}m ${seconds}s"
    else
        echo "${seconds}s"
    fi
}

# Map TLA+ property names to standard names using property mapping
map_tla_property() {
    local tla_property="$1"
    
    if [ -f "$PROPERTY_MAPPING_FILE" ]; then
        # Try to find mapping in all categories
        for category in "safety_properties" "liveness_properties" "type_invariants" "partial_synchrony_properties" "performance_properties"; do
            local mapped=$(jq -r ".mappings.${category}.tla_to_rust.\"${tla_property}\" // empty" "$PROPERTY_MAPPING_FILE" 2>/dev/null)
            if [ -n "$mapped" ] && [ "$mapped" != "null" ]; then
                echo "$mapped"
                return
            fi
        done
    fi
    
    # Return original if no mapping found
    echo "$tla_property"
}

# Enhanced result parsing with property mapping
parse_results() {
    print_header "Analyzing Results with Property Mapping"
    
    if [ ! -f "$RESULT_DIR/tlc_output.log" ]; then
        print_error "Output log not found"
        return 1
    fi
    
    # Extract key metrics
    STATES_GENERATED=$(grep "states generated" "$RESULT_DIR/tlc_output.log" | tail -1 | grep -oE '[0-9]+' | head -1 || echo "0")
    DISTINCT_STATES=$(grep "distinct states" "$RESULT_DIR/tlc_output.log" | tail -1 | grep -oE '[0-9]+' | head -1 || echo "0")
    DEPTH=$(grep "depth" "$RESULT_DIR/tlc_output.log" | tail -1 | grep -oE '[0-9]+' | head -1 || echo "0")
    
    # Enhanced violation detection with property mapping
    SAFETY_VIOLATIONS=$(grep -c "Invariant .* is violated" "$RESULT_DIR/tlc_output.log" || echo "0")
    LIVENESS_VIOLATIONS=$(grep -c "Temporal property .* is violated" "$RESULT_DIR/tlc_output.log" || echo "0")
    DEADLOCKS=$(grep -c "deadlock" "$RESULT_DIR/tlc_output.log" || echo "0")
    TIMEOUT_OCCURRED=$(grep -c "TIMEOUT:" "$RESULT_DIR/tlc_output.log" || echo "0")
    
    # Extract specific violated properties with mapping
    local violated_properties=()
    local verified_properties=()
    
    # Parse violated invariants
    while IFS= read -r line; do
        if [[ "$line" =~ Invariant\ ([^\s]+)\ is\ violated ]]; then
            local tla_prop="${BASH_REMATCH[1]}"
            local mapped_prop=$(map_tla_property "$tla_prop")
            violated_properties+=("$mapped_prop")
        fi
    done < "$RESULT_DIR/tlc_output.log"
    
    # Parse violated temporal properties
    while IFS= read -r line; do
        if [[ "$line" =~ Temporal\ property\ ([^\s]+)\ is\ violated ]]; then
            local tla_prop="${BASH_REMATCH[1]}"
            local mapped_prop=$(map_tla_property "$tla_prop")
            violated_properties+=("$mapped_prop")
        fi
    done < "$RESULT_DIR/tlc_output.log"
    
    # Determine verified properties (those that didn't fail)
    if [ -f "$PROPERTY_MAPPING_FILE" ]; then
        local all_tla_properties=$(jq -r '.mappings | to_entries[] | .value.rust_to_tla | to_entries[] | .value' "$PROPERTY_MAPPING_FILE" 2>/dev/null)
        while IFS= read -r tla_prop; do
            if [ -n "$tla_prop" ] && [[ ! " ${violated_properties[*]} " =~ " $(map_tla_property "$tla_prop") " ]]; then
                verified_properties+=("$(map_tla_property "$tla_prop")")
            fi
        done <<< "$all_tla_properties"
    fi
    
    # Coverage information
    if grep -q "coverage" "$RESULT_DIR/tlc_output.log"; then
        cp "$SPECS_DIR/"*.tlacov "$RESULT_DIR/" 2>/dev/null || true
    fi
    
    # Generate enhanced summary with property mapping
    cat > "$RESULT_DIR/summary.txt" << EOF
================================================================================
Enhanced Model Checking Summary for $CONFIG Configuration
================================================================================

Timestamp: $(date)
Duration: $(format_duration $DURATION)
Timeout: ${TIMEOUT}s
Timed Out: $([ "$TIMEOUT_OCCURRED" -gt 0 ] && echo "Yes" || echo "No")

State Space Exploration:
  - States generated: $STATES_GENERATED
  - Distinct states: $DISTINCT_STATES
  - Search depth: $DEPTH

Verification Results:
  - Safety violations: $SAFETY_VIOLATIONS
  - Liveness violations: $LIVENESS_VIOLATIONS  
  - Deadlocks: $DEADLOCKS
  - Total violations: $((SAFETY_VIOLATIONS + LIVENESS_VIOLATIONS + DEADLOCKS))

Property Analysis:
  - Verified properties: ${#verified_properties[@]}
  - Violated properties: ${#violated_properties[@]}
$([ ${#violated_properties[@]} -gt 0 ] && printf "  - Failed: %s\n" "$(IFS=', '; echo "${violated_properties[*]}")")
$([ ${#verified_properties[@]} -gt 0 ] && printf "  - Passed: %s\n" "$(IFS=', '; echo "${verified_properties[*]}")")

Configuration:
  - Model: $CONFIG
  - Workers: $WORKERS
  - Memory: $JAVA_HEAP
  - Simulation mode: $([ "$SIMULATE_MODE" == true ] && echo "Yes" || echo "No")
  - Dynamic constants: $([ -n "$DYNAMIC_CONSTANTS" ] && echo "$DYNAMIC_CONSTANTS" || echo "None")
  - Property mapping: $([ -f "$PROPERTY_MAPPING_FILE" ] && echo "Enabled" || echo "Disabled")

Output Files:
  - Full log: $RESULT_DIR/tlc_output.log
  - Coverage: $RESULT_DIR/*.tlacov
  - State dump: $RESULT_DIR/states/
$([ "$OUTPUT_JSON" == true ] && echo "  - JSON summary: $RESULT_DIR/tla_summary.json")
$([ -n "$DYNAMIC_CONSTANTS" ] && echo "  - Dynamic config: $RESULT_DIR/dynamic_$CONFIG.cfg")

EOF
    
    # Print summary
    cat "$RESULT_DIR/summary.txt"
    
    # Generate JSON summary if requested
    if [ "$OUTPUT_JSON" == true ]; then
        generate_json_summary
    fi
    
    # Check overall result
    local total_violations=$((SAFETY_VIOLATIONS + LIVENESS_VIOLATIONS + DEADLOCKS))
    
    if [ "$total_violations" -eq 0 ] && [ "$TIMEOUT_OCCURRED" -eq 0 ]; then
        print_info "✓ All properties verified successfully!"
        print_info "  Verified ${#verified_properties[@]} properties without violations"
        return 0
    elif [ "$TIMEOUT_OCCURRED" -gt 0 ]; then
        print_warn "⚠ Model checking timed out - results may be incomplete"
        print_info "  Consider increasing timeout or reducing model size"
        return 2
    else
        print_error "✗ $total_violations violations found! Check the output for details."
        
        if [ ${#violated_properties[@]} -gt 0 ]; then
            print_error "  Failed properties: $(IFS=', '; echo "${violated_properties[*]}")"
        fi
        
        # Extract counterexample if present
        if grep -q "Error:" "$RESULT_DIR/tlc_output.log"; then
            print_warn "Counterexample found. Extracting trace..."
            sed -n '/Error:/,/^$/p' "$RESULT_DIR/tlc_output.log" > "$RESULT_DIR/counterexample.txt"
            print_info "Counterexample saved to: $RESULT_DIR/counterexample.txt"
        fi
        
        return 1
    fi
}

# Generate JSON summary for cross-validation
generate_json_summary() {
    print_info "Generating JSON summary for cross-validation..."
    
    local success=$([ $((SAFETY_VIOLATIONS + LIVENESS_VIOLATIONS + DEADLOCKS)) -eq 0 ] && [ "$TIMEOUT_OCCURRED" -eq 0 ] && echo "true" || echo "false")
    local exit_code=0
    
    if [ "$TIMEOUT_OCCURRED" -gt 0 ]; then
        exit_code=124
    elif [ $((SAFETY_VIOLATIONS + LIVENESS_VIOLATIONS + DEADLOCKS)) -gt 0 ]; then
        exit_code=1
    fi
    
    cat > "$RESULT_DIR/tla_summary.json" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "config": "$CONFIG",
    "success": $success,
    "exit_code": $exit_code,
    "timeout_occurred": $([ "$TIMEOUT_OCCURRED" -gt 0 ] && echo "true" || echo "false"),
    "simulation_mode": $([ "$SIMULATE_MODE" == true ] && echo "true" || echo "false"),
    "dynamic_constants": "$DYNAMIC_CONSTANTS",
    "metrics": {
        "states_generated": $STATES_GENERATED,
        "distinct_states": $DISTINCT_STATES,
        "search_depth": $DEPTH,
        "duration_seconds": $DURATION,
        "violations_found": $((SAFETY_VIOLATIONS + LIVENESS_VIOLATIONS + DEADLOCKS)),
        "safety_violations": $SAFETY_VIOLATIONS,
        "liveness_violations": $LIVENESS_VIOLATIONS,
        "deadlocks": $DEADLOCKS,
        "properties_verified": ${#verified_properties[@]},
        "properties_violated": ${#violated_properties[@]}
    },
    "properties_verified": [$(printf '"%s",' "${verified_properties[@]}" | sed 's/,$//')],
    "properties_violated": [$(printf '"%s",' "${violated_properties[@]}" | sed 's/,$//')],
    "configuration": {
        "workers": $WORKERS,
        "memory": "$JAVA_HEAP",
        "timeout": $TIMEOUT,
        "additional_args": "$ADDITIONAL_ARGS"
    },
    "files": {
        "log_file": "$RESULT_DIR/tlc_output.log",
        "summary_file": "$RESULT_DIR/summary.txt",
        "config_file": "$CONFIG_FILE",
        "counterexample_file": "$([ -f "$RESULT_DIR/counterexample.txt" ] && echo "$RESULT_DIR/counterexample.txt" || echo "null")",
        "coverage_files": "$RESULT_DIR/*.tlacov"
    },
    "property_mapping": {
        "enabled": $([ -f "$PROPERTY_MAPPING_FILE" ] && echo "true" || echo "false"),
        "file": "$PROPERTY_MAPPING_FILE",
        "version": "$([ -f "$PROPERTY_MAPPING_FILE" ] && jq -r '.version' "$PROPERTY_MAPPING_FILE" 2>/dev/null || echo 'unknown')"
    }
}
EOF
    
    print_info "JSON summary saved to: $RESULT_DIR/tla_summary.json"
}

# Generate coverage report
generate_coverage() {
    print_info "Generating coverage report..."
    
    if ls "$RESULT_DIR"/*.tlacov 1> /dev/null 2>&1; then
        # Parse coverage files
        python3 - << 'EOF' > "$RESULT_DIR/coverage_report.html"
import glob
import re
import os

coverage_files = glob.glob("$RESULT_DIR/*.tlacov")
html = """
<html>
<head>
    <title>TLA+ Coverage Report</title>
    <style>
        body { font-family: monospace; }
        .covered { background-color: #90EE90; }
        .uncovered { background-color: #FFB6C1; }
        .stats { margin: 20px 0; padding: 10px; background: #f0f0f0; }
    </style>
</head>
<body>
    <h1>TLA+ Model Checking Coverage Report</h1>
    <div class="stats">
"""

for cf in coverage_files:
    with open(cf, 'r') as f:
        content = f.read()
        # Parse coverage data
        # Add coverage visualization
        html += f"<h2>{os.path.basename(cf)}</h2><pre>{content}</pre>"

html += """
    </div>
</body>
</html>
"""

print(html)
EOF
        print_info "Coverage report saved to: $RESULT_DIR/coverage_report.html"
    else
        print_warn "No coverage data found"
    fi
}

# Print usage information
print_usage() {
    echo "Usage: $0 [CONFIG] [OPTIONS]"
    echo
    echo "CONFIG: Small, Medium, Boundary, EdgeCase, Partition (default: Small)"
    echo
    echo "Enhanced OPTIONS:"
    echo "  --constants KEY=VALUE,KEY2=VALUE2  Set dynamic TLA+ constants"
    echo "  --json                             Generate JSON summary for cross-validation"
    echo "  --cross-validate                   Enable cross-validation features"
    echo "  --simulate                         Run in simulation mode"
    echo "  --timeout SECONDS                  Set timeout (default: 3600)"
    echo "  --help                             Show this help message"
    echo
    echo "Examples:"
    echo "  $0 Small --json                                    # Generate JSON output"
    echo "  $0 Medium --constants N=4,F=1 --timeout 7200      # Custom constants and timeout"
    echo "  $0 Boundary --simulate --cross-validate            # Simulation with cross-validation"
    echo "  $0 EdgeCase --constants BYZANTINE_NODES=2 --json   # Byzantine scenario with JSON"
}

# Main execution
main() {
    # Handle help option
    if [[ " $* " =~ " --help " ]]; then
        print_usage
        exit 0
    fi
    
    print_header "Enhanced Alpenglow Model Checking"
    
    print_info "Configuration: $CONFIG"
    [ -n "$DYNAMIC_CONSTANTS" ] && print_info "Dynamic constants: $DYNAMIC_CONSTANTS"
    [ "$OUTPUT_JSON" == true ] && print_info "JSON output: Enabled"
    [ "$CROSS_VALIDATE" == true ] && print_info "Cross-validation: Enabled"
    [ "$SIMULATE_MODE" == true ] && print_info "Simulation mode: Enabled"
    print_info "Timeout: ${TIMEOUT}s"
    echo
    
    check_prerequisites
    clean_results
    check_syntax
    run_tlc
    local tlc_result=$?
    parse_results
    local parse_result=$?
    generate_coverage
    
    print_header "Enhanced Model Checking Complete"
    
    # Determine final exit code
    local final_exit_code=0
    
    if [ $parse_result -eq 2 ]; then
        print_warn "⚠ Model checking timed out - results may be incomplete"
        final_exit_code=2
    elif [ $parse_result -eq 1 ]; then
        print_error "✗ Violations found! Check logs in: $RESULT_DIR"
        final_exit_code=1
    elif [ $tlc_result -ne 0 ]; then
        print_error "✗ TLC execution failed! Check logs in: $RESULT_DIR"
        final_exit_code=1
    else
        print_info "✓ Success! Results saved to: $RESULT_DIR"
        final_exit_code=0
    fi
    
    # Print integration summary for automated tools
    if [ "$OUTPUT_JSON" == true ] || [ "$CROSS_VALIDATE" == true ]; then
        echo
        print_info "=== INTEGRATION SUMMARY ==="
        print_info "Exit Code: $final_exit_code"
        print_info "Result Directory: $RESULT_DIR"
        print_info "JSON Summary: $([ "$OUTPUT_JSON" == true ] && echo "$RESULT_DIR/tla_summary.json" || echo "Not generated")"
        print_info "Property Mapping: $([ -f "$PROPERTY_MAPPING_FILE" ] && echo "Available" || echo "Not available")"
    fi
    
    exit $final_exit_code
}

# Run main
main
