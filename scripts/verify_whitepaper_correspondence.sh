#!/bin/bash

# verify_whitepaper_correspondence.sh
# Comprehensive verification audit script for Alpenglow whitepaper theorems
# Systematically checks TLAPS verification status of all 25 whitepaper theorems

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TLA_FILE="$PROJECT_ROOT/proofs/WhitepaperTheorems.tla"
WHITEPAPER_FILE="$PROJECT_ROOT/Solana Alpenglow White Paper v1.1.md"
OUTPUT_DIR="$PROJECT_ROOT/verification_reports"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="$OUTPUT_DIR/whitepaper_verification_report_$TIMESTAMP.json"
DETAILED_LOG="$OUTPUT_DIR/verification_detailed_log_$TIMESTAMP.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$DETAILED_LOG"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$DETAILED_LOG"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$DETAILED_LOG"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$DETAILED_LOG"
}

# Initialize output directory
init_output_dir() {
    mkdir -p "$OUTPUT_DIR"
    echo "Alpenglow Whitepaper Verification Audit - $(date)" > "$DETAILED_LOG"
    echo "=================================================" >> "$DETAILED_LOG"
    echo "" >> "$DETAILED_LOG"
}

# Check dependencies
check_dependencies() {
    log_info "Checking dependencies..."
    
    local missing_deps=()
    
    # Check for TLAPS
    if ! command -v tlapm &> /dev/null; then
        missing_deps+=("tlapm (TLA+ Proof Manager)")
    fi
    
    # Check for jq for JSON processing
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq (JSON processor)")
    fi
    
    # Check for required files
    if [[ ! -f "$TLA_FILE" ]]; then
        missing_deps+=("WhitepaperTheorems.tla file")
    fi
    
    if [[ ! -f "$WHITEPAPER_FILE" ]]; then
        missing_deps+=("Whitepaper file")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing dependencies:"
        for dep in "${missing_deps[@]}"; do
            log_error "  - $dep"
        done
        exit 1
    fi
    
    log_success "All dependencies found"
}

# Extract theorem list from TLA+ file
extract_tla_theorems() {
    log_info "Extracting theorems and lemmas from TLA+ file..."
    
    local theorems_json="[]"
    
    # Extract main theorems
    while IFS= read -r line; do
        if [[ $line =~ ^THEOREM[[:space:]]+([^[:space:]]+)[[:space:]]+== ]]; then
            local theorem_name="${BASH_REMATCH[1]}"
            local line_num=$(grep -n "^THEOREM $theorem_name ==" "$TLA_FILE" | cut -d: -f1)
            
            theorems_json=$(echo "$theorems_json" | jq --arg name "$theorem_name" --arg type "THEOREM" --arg line "$line_num" \
                '. += [{"name": $name, "type": $type, "line_number": ($line | tonumber), "status": "unknown", "proof_obligations": [], "errors": []}]')
        fi
    done < "$TLA_FILE"
    
    # Extract lemmas
    while IFS= read -r line; do
        if [[ $line =~ ^LEMMA[[:space:]]+([^[:space:]]+)[[:space:]]+== ]]; then
            local lemma_name="${BASH_REMATCH[1]}"
            local line_num=$(grep -n "^LEMMA $lemma_name ==" "$TLA_FILE" | cut -d: -f1)
            
            theorems_json=$(echo "$theorems_json" | jq --arg name "$lemma_name" --arg type "LEMMA" --arg line "$line_num" \
                '. += [{"name": $name, "type": $type, "line_number": ($line | tonumber), "status": "unknown", "proof_obligations": [], "errors": []}]')
        fi
    done < "$TLA_FILE"
    
    echo "$theorems_json"
}

# Extract theorem references from whitepaper
extract_whitepaper_theorems() {
    log_info "Extracting theorem references from whitepaper..."
    
    local whitepaper_theorems="[]"
    
    # Extract Theorem 1 and 2
    local theorem1_line=$(grep -n "Theorem 1" "$WHITEPAPER_FILE" | head -1 | cut -d: -f1)
    local theorem2_line=$(grep -n "Theorem 2" "$WHITEPAPER_FILE" | head -1 | cut -d: -f1)
    
    if [[ -n "$theorem1_line" ]]; then
        whitepaper_theorems=$(echo "$whitepaper_theorems" | jq --arg name "Theorem 1" --arg line "$theorem1_line" --arg desc "Safety" \
            '. += [{"name": $name, "line_number": ($line | tonumber), "description": $desc, "type": "main_theorem"}]')
    fi
    
    if [[ -n "$theorem2_line" ]]; then
        whitepaper_theorems=$(echo "$whitepaper_theorems" | jq --arg name "Theorem 2" --arg line "$theorem2_line" --arg desc "Liveness" \
            '. += [{"name": $name, "line_number": ($line | tonumber), "description": $desc, "type": "main_theorem"}]')
    fi
    
    # Extract Lemmas 20-42
    for i in {20..42}; do
        local lemma_line=$(grep -n "Lemma $i" "$WHITEPAPER_FILE" | head -1 | cut -d: -f1)
        if [[ -n "$lemma_line" ]]; then
            local lemma_desc=$(sed -n "${lemma_line}p" "$WHITEPAPER_FILE" | sed 's/.*Lemma [0-9]* *(\([^)]*\)).*/\1/' | tr -d '>')
            whitepaper_theorems=$(echo "$whitepaper_theorems" | jq --arg name "Lemma $i" --arg line "$lemma_line" --arg desc "$lemma_desc" \
                '. += [{"name": $name, "line_number": ($line | tonumber), "description": $desc, "type": "supporting_lemma"}]')
        fi
    done
    
    echo "$whitepaper_theorems"
}

# Run TLAPS verification
run_tlaps_verification() {
    local tla_theorems="$1"
    log_info "Running TLAPS verification on WhitepaperTheorems.tla..."
    
    # Create temporary file for TLAPS output
    local tlaps_output="$OUTPUT_DIR/tlaps_output_$TIMESTAMP.txt"
    local tlaps_status="$OUTPUT_DIR/tlaps_status_$TIMESTAMP.txt"
    
    # Run TLAPS with detailed output
    log_info "Executing: tlapm --verbose --timing --stats \"$TLA_FILE\""
    
    if timeout 1800 tlapm --verbose --timing --stats "$TLA_FILE" > "$tlaps_output" 2>&1; then
        local tlaps_exit_code=0
    else
        local tlaps_exit_code=$?
    fi
    
    log_info "TLAPS completed with exit code: $tlaps_exit_code"
    
    # Parse TLAPS output
    local updated_theorems="$tla_theorems"
    
    # Process each theorem/lemma
    while IFS= read -r theorem_info; do
        local theorem_name=$(echo "$theorem_info" | jq -r '.name')
        local theorem_type=$(echo "$theorem_info" | jq -r '.type')
        
        log_info "Processing verification results for $theorem_type $theorem_name..."
        
        # Extract proof obligations and status for this theorem
        local proof_obligations="[]"
        local theorem_status="unknown"
        local errors="[]"
        
        # Parse TLAPS output for this specific theorem
        if grep -q "$theorem_name" "$tlaps_output"; then
            # Extract proof obligations
            local obligations_section=$(sed -n "/$theorem_name/,/^$/p" "$tlaps_output")
            
            # Count successful and failed obligations
            local total_obligations=$(echo "$obligations_section" | grep -c "obligation" || echo "0")
            local proved_obligations=$(echo "$obligations_section" | grep -c "proved\|success" || echo "0")
            local failed_obligations=$(echo "$obligations_section" | grep -c "failed\|error" || echo "0")
            local omitted_obligations=$(echo "$obligations_section" | grep -c "omitted\|skipped" || echo "0")
            
            # Determine overall status
            if [[ $total_obligations -eq 0 ]]; then
                theorem_status="no_obligations"
            elif [[ $failed_obligations -gt 0 ]]; then
                theorem_status="failed"
            elif [[ $omitted_obligations -gt 0 ]]; then
                theorem_status="partial"
            elif [[ $proved_obligations -gt 0 ]]; then
                theorem_status="proved"
            else
                theorem_status="unknown"
            fi
            
            # Extract specific errors
            while IFS= read -r error_line; do
                if [[ $error_line =~ (error|failed|Error|Failed) ]]; then
                    errors=$(echo "$errors" | jq --arg error "$error_line" '. += [$error]')
                fi
            done <<< "$obligations_section"
            
            # Build proof obligations summary
            proof_obligations=$(jq -n \
                --arg total "$total_obligations" \
                --arg proved "$proved_obligations" \
                --arg failed "$failed_obligations" \
                --arg omitted "$omitted_obligations" \
                '{
                    total: ($total | tonumber),
                    proved: ($proved | tonumber),
                    failed: ($failed | tonumber),
                    omitted: ($omitted | tonumber),
                    success_rate: (if ($total | tonumber) > 0 then (($proved | tonumber) / ($total | tonumber) * 100) else 0 end)
                }')
        else
            # Theorem not found in output - likely not processed
            theorem_status="not_processed"
            errors=$(echo "$errors" | jq '. += ["Theorem not found in TLAPS output"]')
        fi
        
        # Update theorem information
        updated_theorems=$(echo "$updated_theorems" | jq \
            --arg name "$theorem_name" \
            --arg status "$theorem_status" \
            --argjson obligations "$proof_obligations" \
            --argjson errors "$errors" \
            'map(if .name == $name then .status = $status | .proof_obligations = $obligations | .errors = $errors else . end)')
        
        log_info "$theorem_type $theorem_name: $theorem_status"
        
    done <<< "$(echo "$tla_theorems" | jq -c '.[]')"
    
    echo "$updated_theorems"
}

# Validate theorem correspondence
validate_correspondence() {
    local tla_theorems="$1"
    local whitepaper_theorems="$2"
    
    log_info "Validating correspondence between whitepaper and TLA+ theorems..."
    
    local correspondence_report="{}"
    local total_whitepaper=$(echo "$whitepaper_theorems" | jq 'length')
    local total_tla=$(echo "$tla_theorems" | jq 'length')
    
    correspondence_report=$(echo "$correspondence_report" | jq \
        --arg total_wp "$total_whitepaper" \
        --arg total_tla "$total_tla" \
        '.summary = {
            whitepaper_theorems: ($total_wp | tonumber),
            tla_theorems: ($total_tla | tonumber),
            expected_total: 25
        }')
    
    # Check for missing theorems
    local missing_in_tla="[]"
    local missing_in_whitepaper="[]"
    local matched_theorems="[]"
    
    # Check whitepaper theorems against TLA+
    while IFS= read -r wp_theorem; do
        local wp_name=$(echo "$wp_theorem" | jq -r '.name')
        local wp_type=$(echo "$wp_theorem" | jq -r '.type')
        
        # Map whitepaper names to TLA+ names
        local tla_name=""
        case "$wp_name" in
            "Theorem 1") tla_name="WhitepaperTheorem1" ;;
            "Theorem 2") tla_name="WhitepaperTheorem2" ;;
            "Lemma "*) 
                local lemma_num=$(echo "$wp_name" | sed 's/Lemma //')
                tla_name="WhitepaperLemma${lemma_num}Proof"
                ;;
        esac
        
        # Check if corresponding TLA+ theorem exists
        local tla_match=$(echo "$tla_theorems" | jq --arg name "$tla_name" '.[] | select(.name == $name)')
        
        if [[ -n "$tla_match" && "$tla_match" != "null" ]]; then
            matched_theorems=$(echo "$matched_theorems" | jq \
                --arg wp_name "$wp_name" \
                --arg tla_name "$tla_name" \
                --argjson wp_theorem "$wp_theorem" \
                --argjson tla_theorem "$tla_match" \
                '. += [{
                    whitepaper: $wp_theorem,
                    tla: $tla_theorem,
                    correspondence_status: "matched"
                }]')
        else
            missing_in_tla=$(echo "$missing_in_tla" | jq --argjson theorem "$wp_theorem" '. += [$theorem]')
        fi
    done <<< "$(echo "$whitepaper_theorems" | jq -c '.[]')"
    
    # Check for TLA+ theorems not in whitepaper
    while IFS= read -r tla_theorem; do
        local tla_name=$(echo "$tla_theorem" | jq -r '.name')
        
        # Check if this TLA+ theorem corresponds to a whitepaper theorem
        local found_match=false
        case "$tla_name" in
            "WhitepaperTheorem1"|"WhitepaperTheorem2"|"WhitepaperLemma"*"Proof")
                # Check if already matched
                local match_check=$(echo "$matched_theorems" | jq --arg name "$tla_name" '.[] | select(.tla.name == $name)')
                if [[ -n "$match_check" && "$match_check" != "null" ]]; then
                    found_match=true
                fi
                ;;
            *)
                # Helper lemmas not directly from whitepaper
                found_match=true
                ;;
        esac
        
        if [[ "$found_match" == "false" ]]; then
            missing_in_whitepaper=$(echo "$missing_in_whitepaper" | jq --argjson theorem "$tla_theorem" '. += [$theorem]')
        fi
    done <<< "$(echo "$tla_theorems" | jq -c '.[]')"
    
    correspondence_report=$(echo "$correspondence_report" | jq \
        --argjson missing_tla "$missing_in_tla" \
        --argjson missing_wp "$missing_in_whitepaper" \
        --argjson matched "$matched_theorems" \
        '.missing_in_tla = $missing_tla |
         .missing_in_whitepaper = $missing_wp |
         .matched_theorems = $matched |
         .correspondence_complete = (($missing_tla | length) == 0 and ($missing_wp | length) == 0)')
    
    echo "$correspondence_report"
}

# Generate verification summary
generate_verification_summary() {
    local tla_theorems="$1"
    local correspondence="$2"
    
    log_info "Generating verification summary..."
    
    local summary="{}"
    
    # Count verification status
    local total_theorems=$(echo "$tla_theorems" | jq 'length')
    local proved_count=$(echo "$tla_theorems" | jq '[.[] | select(.status == "proved")] | length')
    local failed_count=$(echo "$tla_theorems" | jq '[.[] | select(.status == "failed")] | length')
    local partial_count=$(echo "$tla_theorems" | jq '[.[] | select(.status == "partial")] | length')
    local unknown_count=$(echo "$tla_theorems" | jq '[.[] | select(.status == "unknown" or .status == "not_processed")] | length')
    
    # Calculate success rate
    local success_rate=0
    if [[ $total_theorems -gt 0 ]]; then
        success_rate=$(echo "scale=2; $proved_count * 100 / $total_theorems" | bc -l)
    fi
    
    summary=$(jq -n \
        --arg total "$total_theorems" \
        --arg proved "$proved_count" \
        --arg failed "$failed_count" \
        --arg partial "$partial_count" \
        --arg unknown "$unknown_count" \
        --arg success_rate "$success_rate" \
        '{
            total_theorems: ($total | tonumber),
            verification_status: {
                proved: ($proved | tonumber),
                failed: ($failed | tonumber),
                partial: ($partial | tonumber),
                unknown: ($unknown | tonumber)
            },
            success_rate: ($success_rate | tonumber),
            verification_complete: (($proved | tonumber) == ($total | tonumber))
        }')
    
    # Add correspondence summary
    summary=$(echo "$summary" | jq --argjson corr "$correspondence" '.correspondence = $corr')
    
    # Add blocking issues
    local blocking_issues="[]"
    while IFS= read -r theorem; do
        local name=$(echo "$theorem" | jq -r '.name')
        local status=$(echo "$theorem" | jq -r '.status')
        local errors=$(echo "$theorem" | jq -r '.errors[]?' 2>/dev/null || echo "")
        
        if [[ "$status" == "failed" || "$status" == "unknown" || "$status" == "not_processed" ]]; then
            blocking_issues=$(echo "$blocking_issues" | jq \
                --arg name "$name" \
                --arg status "$status" \
                --arg errors "$errors" \
                '. += [{
                    theorem: $name,
                    status: $status,
                    issues: (if $errors != "" then [$errors] else [] end)
                }]')
        fi
    done <<< "$(echo "$tla_theorems" | jq -c '.[]')"
    
    summary=$(echo "$summary" | jq --argjson issues "$blocking_issues" '.blocking_issues = $issues')
    
    echo "$summary"
}

# Generate final report
generate_final_report() {
    local tla_theorems="$1"
    local whitepaper_theorems="$2"
    local correspondence="$3"
    local summary="$4"
    
    log_info "Generating final verification report..."
    
    local final_report=$(jq -n \
        --arg timestamp "$(date -Iseconds)" \
        --arg script_version "1.0.0" \
        --arg tla_file "$TLA_FILE" \
        --arg whitepaper_file "$WHITEPAPER_FILE" \
        '{
            metadata: {
                timestamp: $timestamp,
                script_version: $script_version,
                tla_file: $tla_file,
                whitepaper_file: $whitepaper_file
            }
        }')
    
    final_report=$(echo "$final_report" | jq \
        --argjson summary "$summary" \
        --argjson tla_theorems "$tla_theorems" \
        --argjson whitepaper_theorems "$whitepaper_theorems" \
        --argjson correspondence "$correspondence" \
        '.summary = $summary |
         .tla_theorems = $tla_theorems |
         .whitepaper_theorems = $whitepaper_theorems |
         .correspondence_analysis = $correspondence')
    
    # Write to file
    echo "$final_report" | jq '.' > "$REPORT_FILE"
    
    log_success "Verification report written to: $REPORT_FILE"
}

# Print summary to console
print_summary() {
    local summary="$1"
    
    echo ""
    echo "=============================================="
    echo "    ALPENGLOW VERIFICATION AUDIT SUMMARY"
    echo "=============================================="
    echo ""
    
    local total=$(echo "$summary" | jq -r '.total_theorems')
    local proved=$(echo "$summary" | jq -r '.verification_status.proved')
    local failed=$(echo "$summary" | jq -r '.verification_status.failed')
    local partial=$(echo "$summary" | jq -r '.verification_status.partial')
    local unknown=$(echo "$summary" | jq -r '.verification_status.unknown')
    local success_rate=$(echo "$summary" | jq -r '.success_rate')
    local verification_complete=$(echo "$summary" | jq -r '.verification_complete')
    
    echo "Total Theorems/Lemmas: $total"
    echo "Verification Status:"
    echo "  ✓ Proved:    $proved"
    echo "  ✗ Failed:    $failed"
    echo "  ~ Partial:   $partial"
    echo "  ? Unknown:   $unknown"
    echo ""
    echo "Success Rate: ${success_rate}%"
    echo "Verification Complete: $verification_complete"
    echo ""
    
    # Correspondence summary
    local wp_total=$(echo "$summary" | jq -r '.correspondence.summary.whitepaper_theorems')
    local tla_total=$(echo "$summary" | jq -r '.correspondence.summary.tla_theorems')
    local correspondence_complete=$(echo "$summary" | jq -r '.correspondence.correspondence_complete')
    
    echo "Correspondence Analysis:"
    echo "  Whitepaper Theorems: $wp_total"
    echo "  TLA+ Theorems:       $tla_total"
    echo "  Correspondence Complete: $correspondence_complete"
    echo ""
    
    # Blocking issues
    local blocking_count=$(echo "$summary" | jq -r '.blocking_issues | length')
    if [[ $blocking_count -gt 0 ]]; then
        echo "Blocking Issues ($blocking_count):"
        while IFS= read -r issue; do
            local theorem=$(echo "$issue" | jq -r '.theorem')
            local status=$(echo "$issue" | jq -r '.status')
            echo "  - $theorem: $status"
        done <<< "$(echo "$summary" | jq -c '.blocking_issues[]')"
        echo ""
    fi
    
    echo "Detailed report: $REPORT_FILE"
    echo "Detailed log: $DETAILED_LOG"
    echo "=============================================="
}

# Main execution
main() {
    log_info "Starting Alpenglow Whitepaper Verification Audit"
    
    init_output_dir
    check_dependencies
    
    # Extract theorems from both sources
    local tla_theorems=$(extract_tla_theorems)
    local whitepaper_theorems=$(extract_whitepaper_theorems)
    
    log_info "Found $(echo "$tla_theorems" | jq 'length') theorems/lemmas in TLA+ file"
    log_info "Found $(echo "$whitepaper_theorems" | jq 'length') theorems/lemmas in whitepaper"
    
    # Run TLAPS verification
    tla_theorems=$(run_tlaps_verification "$tla_theorems")
    
    # Validate correspondence
    local correspondence=$(validate_correspondence "$tla_theorems" "$whitepaper_theorems")
    
    # Generate summary
    local summary=$(generate_verification_summary "$tla_theorems" "$correspondence")
    
    # Generate final report
    generate_final_report "$tla_theorems" "$whitepaper_theorems" "$correspondence" "$summary"
    
    # Print summary
    print_summary "$summary"
    
    log_success "Verification audit completed successfully"
    
    # Exit with appropriate code
    local verification_complete=$(echo "$summary" | jq -r '.verification_complete')
    local correspondence_complete=$(echo "$summary" | jq -r '.correspondence.correspondence_complete')
    
    if [[ "$verification_complete" == "true" && "$correspondence_complete" == "true" ]]; then
        exit 0
    else
        exit 1
    fi
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --version, -v  Show version information"
        echo ""
        echo "This script performs a comprehensive verification audit of the"
        echo "Alpenglow whitepaper theorems against their TLA+ implementations."
        exit 0
        ;;
    --version|-v)
        echo "Alpenglow Whitepaper Verification Audit Script v1.0.0"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac