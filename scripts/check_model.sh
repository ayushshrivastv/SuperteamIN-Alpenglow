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

# Default values
CONFIG="${1:-Small}"
shift || true
ADDITIONAL_ARGS="$@"

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
        echo "Usage: $0 [Small|Medium|Boundary|EdgeCase|Partition] [additional TLC options]"
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
    
    # Create results directory
    mkdir -p "$RESULTS_DIR"
    
    print_info "Prerequisites satisfied"
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
    
    # Prepare TLC command
    TLC_CMD="java $JAVA_HEAP -cp $TLC_JAR tlc2.TLC \
        -config $MODELS_DIR/$CONFIG.cfg \
        -workers $WORKERS \
        -cleanup \
        -deadlock \
        -coverage 1 \
        -terse \
        -metadir $RESULT_DIR/states \
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
    
    # Run TLC
    START_TIME=$(date +%s)
    
    $TLC_CMD 2>&1 | tee "$PIPE" > "$RESULT_DIR/tlc_output.log"
    TLC_EXIT_CODE=$?
    
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
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

# Parse results
parse_results() {
    print_header "Analyzing Results"
    
    if [ ! -f "$RESULT_DIR/tlc_output.log" ]; then
        print_error "Output log not found"
        return 1
    fi
    
    # Extract key metrics
    STATES_GENERATED=$(grep "states generated" "$RESULT_DIR/tlc_output.log" | tail -1 | grep -oE '[0-9]+' | head -1 || echo "0")
    DISTINCT_STATES=$(grep "distinct states" "$RESULT_DIR/tlc_output.log" | tail -1 | grep -oE '[0-9]+' | head -1 || echo "0")
    DEPTH=$(grep "depth" "$RESULT_DIR/tlc_output.log" | tail -1 | grep -oE '[0-9]+' | head -1 || echo "0")
    
    # Check for violations
    SAFETY_VIOLATIONS=$(grep -c "Invariant .* is violated" "$RESULT_DIR/tlc_output.log" || true)
    LIVENESS_VIOLATIONS=$(grep -c "Temporal property .* is violated" "$RESULT_DIR/tlc_output.log" || true)
    DEADLOCKS=$(grep -c "deadlock" "$RESULT_DIR/tlc_output.log" || true)
    
    # Coverage information
    if grep -q "coverage" "$RESULT_DIR/tlc_output.log"; then
        cp "$SPECS_DIR/"*.tlacov "$RESULT_DIR/" 2>/dev/null || true
    fi
    
    # Generate summary
    cat > "$RESULT_DIR/summary.txt" << EOF
================================================================================
Model Checking Summary for $CONFIG Configuration
================================================================================

Timestamp: $(date)
Duration: $(format_duration $DURATION)

State Space Exploration:
  - States generated: $STATES_GENERATED
  - Distinct states: $DISTINCT_STATES
  - Search depth: $DEPTH

Verification Results:
  - Safety violations: $SAFETY_VIOLATIONS
  - Liveness violations: $LIVENESS_VIOLATIONS  
  - Deadlocks: $DEADLOCKS

Configuration:
  - Model: $CONFIG
  - Workers: $WORKERS
  - Memory: $JAVA_HEAP

Output Files:
  - Full log: $RESULT_DIR/tlc_output.log
  - Coverage: $RESULT_DIR/*.tlacov
  - State dump: $RESULT_DIR/states/

EOF
    
    # Print summary
    cat "$RESULT_DIR/summary.txt"
    
    # Check overall result
    if [ "$SAFETY_VIOLATIONS" -eq 0 ] && [ "$LIVENESS_VIOLATIONS" -eq 0 ] && [ "$DEADLOCKS" -eq 0 ]; then
        print_info "✓ All properties verified successfully!"
        return 0
    else
        print_error "✗ Violations found! Check the output for details."
        
        # Extract counterexample if present
        if grep -q "Error:" "$RESULT_DIR/tlc_output.log"; then
            print_warn "Counterexample found. Extracting trace..."
            sed -n '/Error:/,/^$/p' "$RESULT_DIR/tlc_output.log" > "$RESULT_DIR/counterexample.txt"
            print_info "Counterexample saved to: $RESULT_DIR/counterexample.txt"
        fi
        
        return 1
    fi
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

# Main execution
main() {
    print_header "Alpenglow Model Checking"
    
    check_prerequisites
    clean_results
    check_syntax
    run_tlc
    parse_results
    generate_coverage
    
    print_header "Model Checking Complete"
    
    if [ $? -eq 0 ]; then
        print_info "✓ Success! Results saved to: $RESULT_DIR"
        exit 0
    else
        print_error "✗ Failed! Check logs in: $RESULT_DIR"
        exit 1
    fi
}

# Run main
main
