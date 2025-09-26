#!/bin/bash

#############################################################################
# Dual Framework Testing Script
# 
# Runs identical test scenarios across both TLA+ and Stateright frameworks
# to verify behavioral consistency and property agreement.
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

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Create results directory
mkdir -p "$RESULTS_DIR"

print_info "Starting dual framework consistency testing..."

# Test scenarios to run across both frameworks
TEST_SCENARIOS=(
    "basic_consensus"
    "byzantine_fault_tolerance"
    "network_partition_recovery"
    "leader_rotation"
    "fast_path_finalization"
    "slow_path_finalization"
    "concurrent_path_execution"
    "erasure_coding_recovery"
    "stake_weighted_sampling"
    "economic_incentives"
)

TOTAL_SCENARIOS=${#TEST_SCENARIOS[@]}
PASSED_SCENARIOS=0
FAILED_SCENARIOS=0

print_info "Running $TOTAL_SCENARIOS test scenarios across TLA+ and Stateright..."

for scenario in "${TEST_SCENARIOS[@]}"; do
    print_info "Testing scenario: $scenario"
    
    # Run TLA+ version
    TLA_RESULT="$RESULTS_DIR/tla_${scenario}.json"
    STATERIGHT_RESULT="$RESULTS_DIR/stateright_${scenario}.json"
    
    # Run TLA+ model checking for this scenario
    if java -jar "$PROJECT_ROOT/tools/tla2tools.jar" \
        -config "$PROJECT_ROOT/models/CrossValidation_${scenario}.cfg" \
        "$PROJECT_ROOT/specs/Alpenglow.tla" \
        > "$RESULTS_DIR/tla_${scenario}.out" 2>&1; then
        print_success "TLA+ test passed for $scenario"
        TLA_PASSED=true
    else
        print_error "TLA+ test failed for $scenario"
        TLA_PASSED=false
    fi
    
    # Run Stateright version
    if (cd "$PROJECT_ROOT/stateright" && \
        cargo test --release "test_${scenario}" \
        > "$RESULTS_DIR/stateright_${scenario}.out" 2>&1); then
        print_success "Stateright test passed for $scenario"
        STATERIGHT_PASSED=true
    else
        print_error "Stateright test failed for $scenario"
        STATERIGHT_PASSED=false
    fi
    
    # Compare results
    if [[ "$TLA_PASSED" == "true" && "$STATERIGHT_PASSED" == "true" ]]; then
        print_success "✓ Scenario $scenario: Both frameworks passed"
        ((PASSED_SCENARIOS++))
    elif [[ "$TLA_PASSED" == "false" && "$STATERIGHT_PASSED" == "false" ]]; then
        print_warning "⚠ Scenario $scenario: Both frameworks failed (consistent)"
        ((PASSED_SCENARIOS++))
    else
        print_error "✗ Scenario $scenario: Inconsistent results between frameworks"
        ((FAILED_SCENARIOS++))
    fi
done

# Generate summary report
CONSISTENCY_RATE=$((PASSED_SCENARIOS * 100 / TOTAL_SCENARIOS))

cat > "$RESULTS_DIR/dual_framework_summary.json" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "total_scenarios": $TOTAL_SCENARIOS,
  "consistent_scenarios": $PASSED_SCENARIOS,
  "inconsistent_scenarios": $FAILED_SCENARIOS,
  "consistency_rate": $CONSISTENCY_RATE,
  "scenarios": [
$(for scenario in "${TEST_SCENARIOS[@]}"; do
    echo "    \"$scenario\""
done | sed '$!s/$/,/')
  ]
}
EOF

print_info "Dual framework testing completed"
print_info "Results: $PASSED_SCENARIOS/$TOTAL_SCENARIOS scenarios consistent ($CONSISTENCY_RATE%)"

if [[ $CONSISTENCY_RATE -eq 100 ]]; then
    print_success "🎉 Perfect consistency achieved across all frameworks!"
    exit 0
else
    print_warning "⚠ Some inconsistencies detected. Check individual test outputs."
    exit 1
fi
