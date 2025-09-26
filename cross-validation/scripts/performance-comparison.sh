#!/bin/bash
# Author: Ayush Srivastava

#############################################################################
# Performance Comparison Script
# 
# Benchmarks verification performance between TLA+ and Stateright
# implementations while ensuring correctness is maintained.
#############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
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

mkdir -p "$RESULTS_DIR"

print_info "Starting performance comparison between TLA+ and Stateright..."

# Benchmark configurations
BENCHMARK_CONFIGS=(
    "Small:4_validators"
    "Medium:7_validators" 
    "Large:15_validators"
)

# Results storage
declare -A TLA_TIMES
declare -A STATERIGHT_TIMES
declare -A TLA_STATES
declare -A STATERIGHT_STATES

for config in "${BENCHMARK_CONFIGS[@]}"; do
    IFS=':' read -r config_name description <<< "$config"
    
    print_info "Benchmarking configuration: $config_name ($description)"
    
    # Benchmark TLA+ model checking
    print_info "Running TLA+ benchmark for $config_name..."
    TLA_START=$(date +%s.%N)
    
    java -jar "$PROJECT_ROOT/tools/tla2tools.jar" \
        -config "$PROJECT_ROOT/models/${config_name}.cfg" \
        "$PROJECT_ROOT/specs/Alpenglow.tla" \
        > "$RESULTS_DIR/tla_${config_name}_benchmark.out" 2>&1
    
    TLA_END=$(date +%s.%N)
    TLA_DURATION=$(echo "$TLA_END - $TLA_START" | bc)
    TLA_TIMES[$config_name]=$TLA_DURATION
    
    # Extract states explored
    TLA_STATES_COUNT=$(grep "states generated" "$RESULTS_DIR/tla_${config_name}_benchmark.out" | \
                      grep -o '[0-9,]*' | tr -d ',' || echo "0")
    TLA_STATES[$config_name]=$TLA_STATES_COUNT
    
    print_info "TLA+ $config_name: ${TLA_DURATION}s, $TLA_STATES_COUNT states"
    
    # Benchmark Stateright verification
    print_info "Running Stateright benchmark for $config_name..."
    STATERIGHT_START=$(date +%s.%N)
    
    (cd "$PROJECT_ROOT/stateright" && \
        cargo test --release "benchmark_${config_name}" \
        > "$RESULTS_DIR/stateright_${config_name}_benchmark.out" 2>&1)
    
    STATERIGHT_END=$(date +%s.%N)
    STATERIGHT_DURATION=$(echo "$STATERIGHT_END - $STATERIGHT_START" | bc)
    STATERIGHT_TIMES[$config_name]=$STATERIGHT_DURATION
    
    # Extract states explored (from Stateright output)
    STATERIGHT_STATES_COUNT=$(grep -o "explored [0-9,]* states" \
                             "$RESULTS_DIR/stateright_${config_name}_benchmark.out" | \
                             grep -o '[0-9,]*' | tr -d ',' || echo "0")
    STATERIGHT_STATES[$config_name]=$STATERIGHT_STATES_COUNT
    
    print_info "Stateright $config_name: ${STATERIGHT_DURATION}s, $STATERIGHT_STATES_COUNT states"
    
    # Calculate speedup
    if [[ $(echo "$TLA_DURATION > 0" | bc) -eq 1 ]]; then
        SPEEDUP=$(echo "scale=2; $TLA_DURATION / $STATERIGHT_DURATION" | bc)
        print_success "Speedup for $config_name: ${SPEEDUP}x"
    fi
done

# Generate comprehensive performance report
cat > "$RESULTS_DIR/performance_comparison.json" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "benchmarks": {
EOF

first=true
for config in "${!TLA_TIMES[@]}"; do
    if [[ "$first" == "true" ]]; then
        first=false
    else
        echo "," >> "$RESULTS_DIR/performance_comparison.json"
    fi
    
    speedup="0"
    if [[ $(echo "${TLA_TIMES[$config]} > 0" | bc) -eq 1 ]]; then
        speedup=$(echo "scale=2; ${TLA_TIMES[$config]} / ${STATERIGHT_TIMES[$config]}" | bc)
    fi
    
    cat >> "$RESULTS_DIR/performance_comparison.json" << EOF
    "$config": {
      "tla_time": ${TLA_TIMES[$config]},
      "stateright_time": ${STATERIGHT_TIMES[$config]},
      "tla_states": ${TLA_STATES[$config]},
      "stateright_states": ${STATERIGHT_STATES[$config]},
      "speedup": $speedup
    }
EOF
done

cat >> "$RESULTS_DIR/performance_comparison.json" << EOF
  }
}
EOF

# Calculate average speedup
total_speedup=0
config_count=0
for config in "${!TLA_TIMES[@]}"; do
    if [[ $(echo "${TLA_TIMES[$config]} > 0" | bc) -eq 1 ]]; then
        speedup=$(echo "scale=2; ${TLA_TIMES[$config]} / ${STATERIGHT_TIMES[$config]}" | bc)
        total_speedup=$(echo "$total_speedup + $speedup" | bc)
        ((config_count++))
    fi
done

if [[ $config_count -gt 0 ]]; then
    avg_speedup=$(echo "scale=2; $total_speedup / $config_count" | bc)
    print_success "Average speedup: ${avg_speedup}x"
    
    # Check if we achieved the expected 3x speedup
    if [[ $(echo "$avg_speedup >= 3.0" | bc) -eq 1 ]]; then
        print_success "🎉 Target 3x speedup achieved!"
        exit 0
    else
        print_error "⚠ Target 3x speedup not achieved (got ${avg_speedup}x)"
        exit 1
    fi
else
    print_error "No valid benchmarks completed"
    exit 1
fi
