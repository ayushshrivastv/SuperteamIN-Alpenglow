#!/bin/bash

#############################################################################
# Trace Equivalence Verification Script
# 
# Compares execution traces between TLA+ and Stateright implementations
# to verify behavioral consistency at the trace level.
#############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TRACES_DIR="$PROJECT_ROOT/cross-validation/traces"
RESULTS_DIR="$PROJECT_ROOT/cross-validation/results"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Create directories
mkdir -p "$TRACES_DIR" "$RESULTS_DIR"

print_info "Starting trace equivalence verification..."

# Generate TLA+ traces
print_info "Generating TLA+ execution traces..."
java -jar "$PROJECT_ROOT/tools/tla2tools.jar" \
    -config "$PROJECT_ROOT/models/TraceGeneration.cfg" \
    "$PROJECT_ROOT/specs/Alpenglow.tla" \
    -dump dot "$TRACES_DIR/tla_trace.dot" \
    > "$RESULTS_DIR/tla_trace_generation.out" 2>&1

# Generate Stateright traces
print_info "Generating Stateright execution traces..."
(cd "$PROJECT_ROOT/stateright" && \
    cargo run --release --bin trace_generator \
    --output "$TRACES_DIR/stateright_trace.json" \
    > "$RESULTS_DIR/stateright_trace_generation.out" 2>&1)

# Compare traces
print_info "Comparing execution traces..."
python3 "$SCRIPT_DIR/compare_traces.py" \
    --tla-trace "$TRACES_DIR/tla_trace.dot" \
    --stateright-trace "$TRACES_DIR/stateright_trace.json" \
    --output "$RESULTS_DIR/trace_comparison.json" \
    > "$RESULTS_DIR/trace_comparison.out" 2>&1

if [[ $? -eq 0 ]]; then
    print_success "✓ Trace equivalence verification completed successfully"
    EQUIVALENCE_RATE=$(jq -r '.equivalence_rate' "$RESULTS_DIR/trace_comparison.json")
    print_info "Trace equivalence rate: $EQUIVALENCE_RATE%"
    
    if [[ "$EQUIVALENCE_RATE" == "100" ]]; then
        print_success "🎉 Perfect trace equivalence achieved!"
        exit 0
    else
        print_error "⚠ Trace differences detected"
        exit 1
    fi
else
    print_error "✗ Trace equivalence verification failed"
    exit 1
fi
