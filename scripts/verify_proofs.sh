#!/bin/bash

#############################################################################
# TLAPS Proof Verification Script for Alpenglow Protocol
#
# Usage: ./verify_proofs.sh [PROOF] [OPTIONS]
#   PROOF: Safety, Liveness, Resilience, or All (default: All)
#   OPTIONS: Additional TLAPS options
#
# Examples:
#   ./verify_proofs.sh                  # Verify all proofs
#   ./verify_proofs.sh Safety            # Verify only safety proofs
#   ./verify_proofs.sh All --verbose    # Verbose output
#############################################################################

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PROOFS_DIR="$PROJECT_DIR/proofs"
RESULTS_DIR="$PROJECT_DIR/results/proofs"
TLAPS_BIN="/usr/local/tlaps/bin/tlapm"

# Default values
PROOF="${1:-All}"
shift || true
ADDITIONAL_ARGS="$@"

# Proof files mapping
declare -A PROOF_FILES=(
    ["Safety"]="Safety.tla"
    ["Liveness"]="Liveness.tla"
    ["Resilience"]="Resilience.tla"
)

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

print_subheader() {
    echo -e "${MAGENTA}----------------------------------------${NC}"
    echo -e "${MAGENTA}  $1${NC}"
    echo -e "${MAGENTA}----------------------------------------${NC}"
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if TLAPS is installed
    if [ ! -f "$TLAPS_BIN" ]; then
        print_error "TLAPS not found. Please run setup.sh first."
        print_info "TLAPS is required for proof verification but optional for model checking."
        exit 1
    fi
    
    # Check if proof files exist
    if [ "$PROOF" != "All" ]; then
        if [ ! -f "$PROOFS_DIR/${PROOF_FILES[$PROOF]}" ]; then
            print_error "Proof file ${PROOF_FILES[$PROOF]} not found in $PROOFS_DIR"
            exit 1
        fi
    else
        for proof_file in "${PROOF_FILES[@]}"; do
            if [ ! -f "$PROOFS_DIR/$proof_file" ]; then
                print_warn "Proof file $proof_file not found"
            fi
        done
    fi
    
    # Create results directory
    mkdir -p "$RESULTS_DIR"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    SESSION_DIR="$RESULTS_DIR/session_${TIMESTAMP}"
    mkdir -p "$SESSION_DIR"
    
    print_info "Results will be saved to: $SESSION_DIR"
}

# Verify single proof file
verify_proof() {
    local proof_name=$1
    local proof_file=$2
    local output_dir="$SESSION_DIR/$proof_name"
    
    mkdir -p "$output_dir"
    
    print_subheader "Verifying $proof_name"
    
    # Check proof structure
    print_info "Checking proof structure..."
    $TLAPS_BIN --cleanfp -C "$PROOFS_DIR/$proof_file" > "$output_dir/structure.log" 2>&1
    
    if [ $? -eq 0 ]; then
        print_info "✓ Proof structure valid"
    else
        print_error "✗ Invalid proof structure"
        return 1
    fi
    
    # Generate proof obligations
    print_info "Generating proof obligations..."
    $TLAPS_BIN --cleanfp --nofp "$PROOFS_DIR/$proof_file" > "$output_dir/obligations.log" 2>&1
    
    # Count obligations
    TOTAL_OBLIGATIONS=$(grep -c "obligation" "$output_dir/obligations.log" 2>/dev/null || echo "0")
    print_info "Found $TOTAL_OBLIGATIONS proof obligations"
    
    # Verify with different backends
    local BACKENDS=("zenon" "ls4" "smt")
    local VERIFIED=0
    local FAILED=0
    local TIMEOUT=0
    
    for backend in "${BACKENDS[@]}"; do
        print_info "Verifying with $backend backend..."
        
        $TLAPS_BIN --cleanfp \
            --method "$backend" \
            --timeout 30 \
            $ADDITIONAL_ARGS \
            "$PROOFS_DIR/$proof_file" > "$output_dir/${backend}.log" 2>&1
        
        EXIT_CODE=$?
        
        # Parse results
        if grep -q "All proof obligations succeeded" "$output_dir/${backend}.log"; then
            VERIFIED=$((VERIFIED + $(grep -c "succeeded" "$output_dir/${backend}.log" || echo 0)))
            print_info "✓ $backend: Success"
        elif grep -q "failed" "$output_dir/${backend}.log"; then
            FAILED=$((FAILED + $(grep -c "failed" "$output_dir/${backend}.log" || echo 0)))
            print_warn "⚠ $backend: Some obligations failed"
        elif grep -q "timeout" "$output_dir/${backend}.log"; then
            TIMEOUT=$((TIMEOUT + $(grep -c "timeout" "$output_dir/${backend}.log" || echo 0)))
            print_warn "⚠ $backend: Some obligations timed out"
        fi
    done
    
    # Try combined backend approach for remaining obligations
    if [ $FAILED -gt 0 ] || [ $TIMEOUT -gt 0 ]; then
        print_info "Attempting combined backend verification..."
        
        $TLAPS_BIN --cleanfp \
            --method "zenon ls4 smt" \
            --timeout 60 \
            $ADDITIONAL_ARGS \
            "$PROOFS_DIR/$proof_file" > "$output_dir/combined.log" 2>&1
        
        if grep -q "All proof obligations succeeded" "$output_dir/combined.log"; then
            print_info "✓ Combined verification succeeded"
            VERIFIED=$TOTAL_OBLIGATIONS
            FAILED=0
            TIMEOUT=0
        fi
    fi
    
    # Generate summary
    cat > "$output_dir/summary.txt" << EOF
================================================================================
Proof Verification Summary: $proof_name
================================================================================

File: $proof_file
Timestamp: $(date)

Proof Obligations:
  - Total: $TOTAL_OBLIGATIONS
  - Verified: $VERIFIED
  - Failed: $FAILED
  - Timeout: $TIMEOUT

Success Rate: $(echo "scale=2; $VERIFIED * 100 / $TOTAL_OBLIGATIONS" | bc)%

Backends Used:
  - Zenon (automated theorem prover)
  - LS4 (temporal logic prover)
  - SMT (satisfiability modulo theories)

Detailed Logs:
  - Structure: $output_dir/structure.log
  - Obligations: $output_dir/obligations.log
  - Backend logs: $output_dir/*.log

EOF
    
    cat "$output_dir/summary.txt"
    
    # Return status
    if [ $FAILED -eq 0 ] && [ $TIMEOUT -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Extract failed obligations
extract_failures() {
    local output_dir=$1
    
    print_info "Extracting failed proof obligations..."
    
    for log_file in "$output_dir"/*.log; do
        if grep -q "failed" "$log_file"; then
            echo "Failed obligations in $(basename $log_file):" >> "$output_dir/failures.txt"
            grep -A 5 -B 5 "failed" "$log_file" >> "$output_dir/failures.txt"
            echo "---" >> "$output_dir/failures.txt"
        fi
    done
    
    if [ -f "$output_dir/failures.txt" ]; then
        print_warn "Failed obligations extracted to: $output_dir/failures.txt"
    fi
}

# Generate proof graph
generate_proof_graph() {
    local proof_name=$1
    local proof_file=$2
    local output_dir="$SESSION_DIR/$proof_name"
    
    print_info "Generating proof dependency graph..."
    
    # Use TLAPS to generate proof tree
    $TLAPS_BIN --graph "$PROOFS_DIR/$proof_file" > "$output_dir/proof_tree.dot" 2>/dev/null
    
    # Convert to image if graphviz is available
    if command -v dot &> /dev/null; then
        dot -Tpng "$output_dir/proof_tree.dot" -o "$output_dir/proof_tree.png" 2>/dev/null
        print_info "Proof graph saved to: $output_dir/proof_tree.png"
    fi
}

# Verify all proofs
verify_all() {
    local TOTAL_SUCCESS=0
    local TOTAL_FAILED=0
    
    for proof_name in "${!PROOF_FILES[@]}"; do
        if [ -f "$PROOFS_DIR/${PROOF_FILES[$proof_name]}" ]; then
            verify_proof "$proof_name" "${PROOF_FILES[$proof_name]}"
            if [ $? -eq 0 ]; then
                TOTAL_SUCCESS=$((TOTAL_SUCCESS + 1))
            else
                TOTAL_FAILED=$((TOTAL_FAILED + 1))
                extract_failures "$SESSION_DIR/$proof_name"
            fi
            generate_proof_graph "$proof_name" "${PROOF_FILES[$proof_name]}"
        else
            print_warn "Skipping $proof_name - file not found"
        fi
    done
    
    # Generate overall summary
    generate_overall_summary $TOTAL_SUCCESS $TOTAL_FAILED
}

# Generate overall summary
generate_overall_summary() {
    local success=$1
    local failed=$2
    local total=$((success + failed))
    
    cat > "$SESSION_DIR/overall_summary.txt" << EOF
================================================================================
Overall Proof Verification Summary
================================================================================

Session: $(basename $SESSION_DIR)
Date: $(date)

Results:
  - Total proof modules: $total
  - Successfully verified: $success
  - Failed verification: $failed
  - Success rate: $(echo "scale=2; $success * 100 / $total" | bc)%

Proof Modules:
$(for proof_name in "${!PROOF_FILES[@]}"; do
    if [ -f "$SESSION_DIR/$proof_name/summary.txt" ]; then
        status=$(grep "Success Rate" "$SESSION_DIR/$proof_name/summary.txt" | cut -d: -f2)
        echo "  - $proof_name: $status"
    fi
done)

Recommendations:
$(if [ $failed -gt 0 ]; then
    echo "  - Review failed obligations in individual failure logs"
    echo "  - Consider increasing timeout for complex proofs"
    echo "  - Try different backend combinations"
else
    echo "  - All proofs verified successfully!"
    echo "  - Consider running with --paranoid flag for extra checking"
fi)

Session Directory: $SESSION_DIR

EOF
    
    print_header "Overall Summary"
    cat "$SESSION_DIR/overall_summary.txt"
}

# Interactive proof debugging
debug_proof() {
    local proof_file=$1
    
    print_header "Interactive Proof Debugging"
    print_info "Starting interactive TLAPS session..."
    print_info "Commands: check, prove, print, status, quit"
    
    $TLAPS_BIN --interactive "$PROOFS_DIR/$proof_file"
}

# Main execution
main() {
    print_header "TLAPS Proof Verification"
    
    check_prerequisites
    
    START_TIME=$(date +%s)
    
    if [ "$PROOF" == "All" ]; then
        verify_all
    elif [ -n "${PROOF_FILES[$PROOF]}" ]; then
        verify_proof "$PROOF" "${PROOF_FILES[$PROOF]}"
        if [ $? -ne 0 ]; then
            extract_failures "$SESSION_DIR/$PROOF"
        fi
        generate_proof_graph "$PROOF" "${PROOF_FILES[$PROOF]}"
    elif [ "$PROOF" == "debug" ] && [ -n "$2" ]; then
        debug_proof "$2"
    else
        print_error "Unknown proof: $PROOF"
        echo "Available proofs: Safety, Liveness, Resilience, All"
        exit 1
    fi
    
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    print_header "Verification Complete"
    print_info "Total time: $(printf '%02d:%02d:%02d\n' $((DURATION/3600)) $((DURATION%3600/60)) $((DURATION%60)))"
    print_info "Results saved to: $SESSION_DIR"
    
    # Exit with appropriate code
    if [ -f "$SESSION_DIR/overall_summary.txt" ]; then
        if grep -q "Failed verification: 0" "$SESSION_DIR/overall_summary.txt"; then
            exit 0
        else
            exit 1
        fi
    fi
}

# Run main
main
