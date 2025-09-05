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
BASELINE_DIR="$RESULTS_DIR/baseline_obligations.txt"
TLAPS_BIN="/usr/local/tlaps/bin/tlapm"

# Default values
PROOF="${1:-All}"
shift || true
ADDITIONAL_ARGS="$@"

# Proof files mapping (bash 3.2 compatible)
get_proof_file() {
    case "$1" in
        "Safety") echo "Safety.tla" ;;
        "Liveness") echo "Liveness.tla" ;;
        "Resilience") echo "Resilience.tla" ;;
        "MathHelpers") echo "MathHelpers.tla" ;;
        "WhitepaperTheorems") echo "WhitepaperTheorems.tla" ;;
        *) echo "" ;;
    esac
}

PROOF_NAMES="MathHelpers Safety Liveness Resilience WhitepaperTheorems"

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
        PROOF_FILE=$(get_proof_file "$PROOF")
        if [ -z "$PROOF_FILE" ] || [ ! -f "$PROOFS_DIR/$PROOF_FILE" ]; then
            print_error "Proof file $PROOF_FILE not found in $PROOFS_DIR"
            exit 1
        fi
    else
        for proof_name in $PROOF_NAMES; do
            proof_file=$(get_proof_file "$proof_name")
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

# Get enhanced timeout for complex proofs
get_timeout() {
    local proof_name=$1
    case "$proof_name" in
        "WhitepaperTheorems") echo "120" ;;
        "MathHelpers") echo "60" ;;
        *) echo "30" ;;
    esac
}

# Get backend combinations for stubborn proofs
get_backend_combinations() {
    local proof_name=$1
    case "$proof_name" in
        "WhitepaperTheorems") echo "zenon ls4 smt zenon+ls4 ls4+smt zenon+smt zenon+ls4+smt" ;;
        "MathHelpers") echo "zenon ls4 smt zenon+ls4" ;;
        *) echo "zenon ls4 smt" ;;
    esac
}

# Extract individual lemma status
extract_lemma_status() {
    local output_dir=$1
    local proof_name=$2
    
    print_info "Extracting individual lemma verification status..."
    
    # Create lemma status file
    echo "================================================================================" > "$output_dir/lemma_status.txt"
    echo "Individual Lemma Verification Status: $proof_name" >> "$output_dir/lemma_status.txt"
    echo "================================================================================" >> "$output_dir/lemma_status.txt"
    echo "" >> "$output_dir/lemma_status.txt"
    
    # Parse obligations log for lemma-specific information
    if [ -f "$output_dir/obligations.log" ]; then
        # Extract lemma names and their obligation counts
        grep -n "LEMMA\|THEOREM" "$PROOFS_DIR/$(get_proof_file $proof_name)" | while read line; do
            lemma_name=$(echo "$line" | sed 's/.*LEMMA\|THEOREM \([^ ]*\).*/\1/')
            line_num=$(echo "$line" | cut -d: -f1)
            echo "Lemma: $lemma_name (Line $line_num)" >> "$output_dir/lemma_status.txt"
        done
    fi
    
    # Parse verification logs for lemma-specific results
    for log_file in "$output_dir"/*.log; do
        if [ -f "$log_file" ]; then
            backend=$(basename "$log_file" .log)
            echo "" >> "$output_dir/lemma_status.txt"
            echo "Backend: $backend" >> "$output_dir/lemma_status.txt"
            echo "----------------------------------------" >> "$output_dir/lemma_status.txt"
            
            # Extract lemma-specific results
            grep -A 2 -B 2 "WhitepaperLemma\|WhitepaperTheorem\|SimpleArithmetic\|StakeArithmetic" "$log_file" >> "$output_dir/lemma_status.txt" 2>/dev/null || true
        fi
    done
}

# Compare with baseline
compare_with_baseline() {
    local output_dir=$1
    local proof_name=$2
    
    if [ -f "$BASELINE_DIR" ] && [ "$proof_name" == "WhitepaperTheorems" ]; then
        print_info "Comparing with baseline obligations..."
        
        # Extract current obligation count
        current_total=$(grep -c "obligation" "$output_dir/obligations.log" 2>/dev/null || echo "0")
        current_verified=$(grep -c "succeeded" "$output_dir"/*.log 2>/dev/null || echo "0")
        
        # Compare with baseline if it exists
        if grep -q "WhitepaperTheorems" "$BASELINE_DIR" 2>/dev/null; then
            baseline_total=$(grep "WhitepaperTheorems.*Total:" "$BASELINE_DIR" | cut -d: -f2 | tr -d ' ')
            baseline_verified=$(grep "WhitepaperTheorems.*Verified:" "$BASELINE_DIR" | cut -d: -f2 | tr -d ' ')
            
            echo "Baseline Comparison:" >> "$output_dir/baseline_comparison.txt"
            echo "  Previous Total: $baseline_total" >> "$output_dir/baseline_comparison.txt"
            echo "  Current Total: $current_total" >> "$output_dir/baseline_comparison.txt"
            echo "  Previous Verified: $baseline_verified" >> "$output_dir/baseline_comparison.txt"
            echo "  Current Verified: $current_verified" >> "$output_dir/baseline_comparison.txt"
            
            if [ "$current_verified" -gt "$baseline_verified" ]; then
                echo "  Progress: +$((current_verified - baseline_verified)) obligations verified" >> "$output_dir/baseline_comparison.txt"
                print_info "✓ Progress: +$((current_verified - baseline_verified)) obligations verified"
            elif [ "$current_verified" -lt "$baseline_verified" ]; then
                echo "  Regression: -$((baseline_verified - current_verified)) obligations lost" >> "$output_dir/baseline_comparison.txt"
                print_warn "⚠ Regression: -$((baseline_verified - current_verified)) obligations lost"
            else
                echo "  Status: No change in verification count" >> "$output_dir/baseline_comparison.txt"
                print_info "Status: No change in verification count"
            fi
        else
            echo "No baseline found for $proof_name" >> "$output_dir/baseline_comparison.txt"
        fi
        
        # Update baseline
        update_baseline "$proof_name" "$current_total" "$current_verified"
    fi
}

# Update baseline file
update_baseline() {
    local proof_name=$1
    local total=$2
    local verified=$3
    
    # Create baseline directory if it doesn't exist
    mkdir -p "$(dirname "$BASELINE_DIR")"
    
    # Remove old entry for this proof
    if [ -f "$BASELINE_DIR" ]; then
        grep -v "^$proof_name" "$BASELINE_DIR" > "$BASELINE_DIR.tmp" || true
        mv "$BASELINE_DIR.tmp" "$BASELINE_DIR"
    fi
    
    # Add new entry
    echo "$proof_name Total: $total Verified: $verified Date: $(date)" >> "$BASELINE_DIR"
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
    
    # Get enhanced settings for this proof
    TIMEOUT=$(get_timeout "$proof_name")
    BACKEND_COMBINATIONS=$(get_backend_combinations "$proof_name")
    
    # Verify with different backend combinations
    local VERIFIED=0
    local FAILED=0
    local TIMEOUT_COUNT=0
    local BEST_VERIFIED=0
    
    for backend_combo in $BACKEND_COMBINATIONS; do
        print_info "Verifying with $backend_combo backend(s) (timeout: ${TIMEOUT}s)..."
        
        $TLAPS_BIN --cleanfp \
            --method "$backend_combo" \
            --timeout "$TIMEOUT" \
            $ADDITIONAL_ARGS \
            "$PROOFS_DIR/$proof_file" > "$output_dir/${backend_combo}.log" 2>&1
        
        EXIT_CODE=$?
        
        # Parse results
        current_verified=$(grep -c "succeeded" "$output_dir/${backend_combo}.log" 2>/dev/null || echo "0")
        current_failed=$(grep -c "failed" "$output_dir/${backend_combo}.log" 2>/dev/null || echo "0")
        current_timeout=$(grep -c "timeout" "$output_dir/${backend_combo}.log" 2>/dev/null || echo "0")
        
        if [ "$current_verified" -gt "$BEST_VERIFIED" ]; then
            BEST_VERIFIED=$current_verified
            VERIFIED=$current_verified
            FAILED=$current_failed
            TIMEOUT_COUNT=$current_timeout
        fi
        
        if grep -q "All proof obligations succeeded" "$output_dir/${backend_combo}.log"; then
            print_info "✓ $backend_combo: All obligations succeeded"
            VERIFIED=$TOTAL_OBLIGATIONS
            FAILED=0
            TIMEOUT_COUNT=0
            break
        elif [ "$current_verified" -gt 0 ]; then
            print_info "✓ $backend_combo: $current_verified/$TOTAL_OBLIGATIONS obligations succeeded"
        else
            print_warn "⚠ $backend_combo: No obligations succeeded"
        fi
    done
    
    # Try extended timeout for stubborn obligations if needed
    if [ "$FAILED" -gt 0 ] || [ "$TIMEOUT_COUNT" -gt 0 ]; then
        EXTENDED_TIMEOUT=$((TIMEOUT * 2))
        print_info "Attempting extended timeout verification (${EXTENDED_TIMEOUT}s)..."
        
        $TLAPS_BIN --cleanfp \
            --method "zenon ls4 smt" \
            --timeout "$EXTENDED_TIMEOUT" \
            $ADDITIONAL_ARGS \
            "$PROOFS_DIR/$proof_file" > "$output_dir/extended.log" 2>&1
        
        extended_verified=$(grep -c "succeeded" "$output_dir/extended.log" 2>/dev/null || echo "0")
        if [ "$extended_verified" -gt "$VERIFIED" ]; then
            VERIFIED=$extended_verified
            FAILED=$((TOTAL_OBLIGATIONS - VERIFIED))
            TIMEOUT_COUNT=0
            print_info "✓ Extended timeout: $VERIFIED/$TOTAL_OBLIGATIONS obligations succeeded"
        fi
    fi
    
    # Extract individual lemma status
    extract_lemma_status "$output_dir" "$proof_name"
    
    # Compare with baseline for WhitepaperTheorems
    compare_with_baseline "$output_dir" "$proof_name"
    
    # Generate enhanced summary
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
  - Timeout: $TIMEOUT_COUNT

Success Rate: $(echo "scale=2; $VERIFIED * 100 / $TOTAL_OBLIGATIONS" | bc 2>/dev/null || echo "0")%

Verification Settings:
  - Timeout: ${TIMEOUT}s (extended: $((TIMEOUT * 2))s)
  - Backend combinations: $(echo $BACKEND_COMBINATIONS | wc -w)
  - Enhanced mode: $([ "$proof_name" == "WhitepaperTheorems" ] && echo "Yes" || echo "No")

Backends Used:
$(for combo in $BACKEND_COMBINATIONS; do
    echo "  - $combo"
done)

Individual Lemma Analysis:
$(if [ -f "$output_dir/lemma_status.txt" ]; then
    echo "  - Available in lemma_status.txt"
else
    echo "  - Not available"
fi)

Baseline Comparison:
$(if [ -f "$output_dir/baseline_comparison.txt" ]; then
    cat "$output_dir/baseline_comparison.txt" | sed 's/^/  /'
else
    echo "  - Not available"
fi)

Detailed Logs:
  - Structure: $output_dir/structure.log
  - Obligations: $output_dir/obligations.log
  - Backend logs: $output_dir/*.log
  - Lemma status: $output_dir/lemma_status.txt
  - Failure analysis: $output_dir/failures.txt

EOF
    
    cat "$output_dir/summary.txt"
    
    # Return status
    if [ $FAILED -eq 0 ] && [ $TIMEOUT_COUNT -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Extract failed obligations with enhanced debugging
extract_failures() {
    local output_dir=$1
    local proof_name=$2
    
    print_info "Extracting failed proof obligations with debugging info..."
    
    echo "================================================================================" > "$output_dir/failures.txt"
    echo "Failed Proof Obligations Analysis: $proof_name" >> "$output_dir/failures.txt"
    echo "================================================================================" >> "$output_dir/failures.txt"
    echo "" >> "$output_dir/failures.txt"
    
    for log_file in "$output_dir"/*.log; do
        if grep -q "failed" "$log_file"; then
            backend=$(basename "$log_file" .log)
            echo "Backend: $backend" >> "$output_dir/failures.txt"
            echo "----------------------------------------" >> "$output_dir/failures.txt"
            
            # Extract failed obligations with context
            grep -n -A 10 -B 5 "failed" "$log_file" >> "$output_dir/failures.txt"
            echo "" >> "$output_dir/failures.txt"
            
            # Extract specific lemma failures for WhitepaperTheorems
            if [ "$proof_name" == "WhitepaperTheorems" ]; then
                echo "Specific Lemma Failures:" >> "$output_dir/failures.txt"
                grep -A 3 -B 3 "WhitepaperLemma.*failed\|WhitepaperTheorem.*failed" "$log_file" >> "$output_dir/failures.txt" 2>/dev/null || true
                echo "" >> "$output_dir/failures.txt"
            fi
            
            echo "---" >> "$output_dir/failures.txt"
        fi
    done
    
    # Add debugging recommendations
    echo "" >> "$output_dir/failures.txt"
    echo "Debugging Recommendations:" >> "$output_dir/failures.txt"
    echo "1. Check if all required modules are properly imported" >> "$output_dir/failures.txt"
    echo "2. Verify that helper lemmas are proven before use" >> "$output_dir/failures.txt"
    echo "3. Consider breaking complex proofs into smaller steps" >> "$output_dir/failures.txt"
    echo "4. Try different backend combinations for stubborn obligations" >> "$output_dir/failures.txt"
    echo "5. Increase timeout for complex arithmetic proofs" >> "$output_dir/failures.txt"
    
    if [ "$proof_name" == "WhitepaperTheorems" ]; then
        echo "6. Ensure MathHelpers module is verified first" >> "$output_dir/failures.txt"
        echo "7. Check that all predicate definitions are complete" >> "$output_dir/failures.txt"
        echo "8. Verify Byzantine and network assumptions are properly stated" >> "$output_dir/failures.txt"
    fi
    
    if [ -f "$output_dir/failures.txt" ]; then
        print_warn "Enhanced failure analysis saved to: $output_dir/failures.txt"
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

# Verify all proofs with dependency order
verify_all() {
    local TOTAL_SUCCESS=0
    local TOTAL_FAILED=0
    
    # Verify in dependency order: MathHelpers first, then others, WhitepaperTheorems last
    local ORDERED_PROOFS="MathHelpers Safety Liveness Resilience WhitepaperTheorems"
    
    for proof_name in $ORDERED_PROOFS; do
        proof_file=$(get_proof_file "$proof_name")
        if [ -f "$PROOFS_DIR/$proof_file" ]; then
            verify_proof "$proof_name" "$proof_file"
            if [ $? -eq 0 ]; then
                TOTAL_SUCCESS=$((TOTAL_SUCCESS + 1))
                print_info "✓ $proof_name verification completed successfully"
            else
                TOTAL_FAILED=$((TOTAL_FAILED + 1))
                extract_failures "$SESSION_DIR/$proof_name" "$proof_name"
                print_error "✗ $proof_name verification failed"
                
                # For WhitepaperTheorems, provide additional guidance
                if [ "$proof_name" == "WhitepaperTheorems" ]; then
                    print_info "Consider verifying MathHelpers first if not already done"
                    print_info "Check that all predicate definitions are complete"
                fi
            fi
            generate_proof_graph "$proof_name" "$proof_file"
        else
            print_warn "Skipping $proof_name - file not found"
        fi
    done
    
    # Generate overall summary
    generate_overall_summary $TOTAL_SUCCESS $TOTAL_FAILED
}

# Generate overall summary with enhanced reporting
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
  - Success rate: $(echo "scale=2; $success * 100 / $total" | bc 2>/dev/null || echo "0")%

Proof Modules:
$(for proof_name in $PROOF_NAMES; do
    if [ -f "$SESSION_DIR/$proof_name/summary.txt" ]; then
        status=$(grep "Success Rate" "$SESSION_DIR/$proof_name/summary.txt" | cut -d: -f2 | tr -d ' ')
        obligations=$(grep "Total:" "$SESSION_DIR/$proof_name/summary.txt" | cut -d: -f2 | tr -d ' ')
        verified=$(grep "Verified:" "$SESSION_DIR/$proof_name/summary.txt" | cut -d: -f2 | tr -d ' ')
        echo "  - $proof_name: $verified/$obligations obligations ($status success rate)"
    fi
done)

WhitepaperTheorems Progress:
$(if [ -f "$SESSION_DIR/WhitepaperTheorems/baseline_comparison.txt" ]; then
    echo "$(cat "$SESSION_DIR/WhitepaperTheorems/baseline_comparison.txt" | sed 's/^/  /')"
else
    echo "  - No baseline comparison available"
fi)

Module Dependencies:
  - MathHelpers: Foundation for arithmetic proofs
  - Safety/Liveness/Resilience: Core protocol properties  
  - WhitepaperTheorems: Main theorems (depends on all above)

Recommendations:
$(if [ $failed -gt 0 ]; then
    echo "  - Review enhanced failure analysis in individual failure logs"
    echo "  - Verify dependencies: MathHelpers → Core modules → WhitepaperTheorems"
    echo "  - Consider increasing timeout for complex proofs (current: 30-120s)"
    echo "  - Try extended backend combinations for stubborn obligations"
    if [ -f "$SESSION_DIR/WhitepaperTheorems/failures.txt" ]; then
        echo "  - Check WhitepaperTheorems specific debugging recommendations"
    fi
else
    echo "  - All proofs verified successfully!"
    echo "  - Consider running with --paranoid flag for extra checking"
    echo "  - Baseline has been updated for progress tracking"
fi)

Enhanced Features Used:
  - Individual lemma status tracking
  - Baseline comparison for progress monitoring
  - Extended timeout settings for complex proofs
  - Multiple backend combinations
  - Dependency-aware verification order

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
    elif [ "$PROOF" == "debug" ] && [ -n "$2" ]; then
        debug_proof "$2"
    else
        PROOF_FILE=$(get_proof_file "$PROOF")
        if [ -n "$PROOF_FILE" ]; then
            verify_proof "$PROOF" "$PROOF_FILE"
            if [ $? -ne 0 ]; then
                extract_failures "$SESSION_DIR/$PROOF" "$PROOF"
            fi
            generate_proof_graph "$PROOF" "$PROOF_FILE"
        else
            print_error "Unknown proof: $PROOF"
            echo "Available proofs: MathHelpers, Safety, Liveness, Resilience, WhitepaperTheorems, All"
            exit 1
        fi
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
