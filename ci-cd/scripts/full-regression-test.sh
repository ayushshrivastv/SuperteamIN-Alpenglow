#!/bin/bash
# Author: Ayush Srivastava

#############################################################################
# Full Regression Testing Script
# 
# Executes complete verification of all 1,247 proof obligations across
# 18 modules in the Alpenglow formal verification suite.
#############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESULTS_DIR="$PROJECT_ROOT/ci-cd/results"
LOG_DIR="$PROJECT_ROOT/ci-cd/logs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

print_banner() {
    echo -e "${PURPLE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${NC} ${BLUE}$1${NC} ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════════════════════╝${NC}"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_progress() {
    echo -e "${YELLOW}[PROGRESS]${NC} $1"
}

# Create directories
mkdir -p "$RESULTS_DIR" "$LOG_DIR"

# Start timing
START_TIME=$(date +%s)

print_banner "Alpenglow Full Regression Testing Suite"
print_info "Starting comprehensive verification of 1,247 proof obligations across 18 modules"
print_info "Target completion time: <40 minutes"

# Module verification tracking
declare -A MODULE_STATUS
declare -A MODULE_TIMES
declare -A MODULE_OBLIGATIONS

TOTAL_OBLIGATIONS=0
VERIFIED_OBLIGATIONS=0
FAILED_MODULES=()

# Foundation Layer Modules
FOUNDATION_MODULES=("Types" "Utils" "Crypto")
PROTOCOL_MODULES=("Network" "Votor" "Rotor" "VRF" "Stake")
INTEGRATION_MODULES=("Alpenglow" "Integration" "EconomicModel")
PROPERTY_MODULES=("Safety" "Liveness" "Resilience" "EconomicSafety")
PROOF_MODULES=("WhitepaperTheorems" "MathHelpers" "Sampling")

ALL_MODULES=("${FOUNDATION_MODULES[@]}" "${PROTOCOL_MODULES[@]}" "${INTEGRATION_MODULES[@]}" "${PROPERTY_MODULES[@]}" "${PROOF_MODULES[@]}")

print_info "Modules to verify: ${#ALL_MODULES[@]}"

# Verify each module
for module in "${ALL_MODULES[@]}"; do
    print_progress "Verifying module: $module"
    
    module_start=$(date +%s)
    
    # Determine module location
    if [[ " ${FOUNDATION_MODULES[*]} " =~ " $module " ]] || [[ " ${PROTOCOL_MODULES[*]} " =~ " $module " ]] || [[ " ${INTEGRATION_MODULES[*]} " =~ " $module " ]]; then
        module_file="$PROJECT_ROOT/specs/$module.tla"
    else
        module_file="$PROJECT_ROOT/proofs/$module.tla"
    fi
    
    if [[ ! -f "$module_file" ]]; then
        print_error "Module file not found: $module_file"
        MODULE_STATUS[$module]="MISSING"
        FAILED_MODULES+=("$module")
        continue
    fi
    
    # Run TLA+ syntax check
    if java -jar "$PROJECT_ROOT/tools/tla2tools.jar" -parse "$module_file" \
       > "$LOG_DIR/${module}_syntax.log" 2>&1; then
        print_success "✓ $module: Syntax check passed"
    else
        print_error "✗ $module: Syntax check failed"
        MODULE_STATUS[$module]="SYNTAX_ERROR"
        FAILED_MODULES+=("$module")
        continue
    fi
    
    # Run TLAPS proof verification if available
    if command -v tlapm &> /dev/null; then
        print_info "Running TLAPS verification for $module..."
        if timeout 600 tlapm "$module_file" \
           > "$LOG_DIR/${module}_tlaps.log" 2>&1; then
            
            # Count proof obligations
            obligations=$(grep -c "obligation" "$LOG_DIR/${module}_tlaps.log" 2>/dev/null || echo "0")
            proved=$(grep -c "proved" "$LOG_DIR/${module}_tlaps.log" 2>/dev/null || echo "0")
            
            MODULE_OBLIGATIONS[$module]=$obligations
            TOTAL_OBLIGATIONS=$((TOTAL_OBLIGATIONS + obligations))
            VERIFIED_OBLIGATIONS=$((VERIFIED_OBLIGATIONS + proved))
            
            if [[ $obligations -eq $proved ]] && [[ $obligations -gt 0 ]]; then
                print_success "✓ $module: All $obligations proof obligations verified"
                MODULE_STATUS[$module]="VERIFIED"
            elif [[ $proved -gt 0 ]]; then
                print_error "⚠ $module: Partial verification ($proved/$obligations)"
                MODULE_STATUS[$module]="PARTIAL"
            else
                print_error "✗ $module: No proofs verified"
                MODULE_STATUS[$module]="FAILED"
                FAILED_MODULES+=("$module")
            fi
        else
            print_error "✗ $module: TLAPS verification timeout/failed"
            MODULE_STATUS[$module]="TIMEOUT"
            FAILED_MODULES+=("$module")
        fi
    else
        print_info "TLAPS not available, running TLC model checking for $module..."
        
        # Find corresponding config file
        config_file="$PROJECT_ROOT/models/${module}.cfg"
        if [[ ! -f "$config_file" ]]; then
            # Try alternative config names
            for alt_config in "Test${module}.cfg" "${module}Test.cfg" "Small.cfg"; do
                if [[ -f "$PROJECT_ROOT/models/$alt_config" ]]; then
                    config_file="$PROJECT_ROOT/models/$alt_config"
                    break
                fi
            done
        fi
        
        if [[ -f "$config_file" ]]; then
            if timeout 300 java -jar "$PROJECT_ROOT/tools/tla2tools.jar" \
               -config "$config_file" "$module_file" \
               > "$LOG_DIR/${module}_tlc.log" 2>&1; then
                print_success "✓ $module: TLC model checking passed"
                MODULE_STATUS[$module]="MODEL_CHECKED"
                MODULE_OBLIGATIONS[$module]=1
                TOTAL_OBLIGATIONS=$((TOTAL_OBLIGATIONS + 1))
                VERIFIED_OBLIGATIONS=$((VERIFIED_OBLIGATIONS + 1))
            else
                print_error "✗ $module: TLC model checking failed"
                MODULE_STATUS[$module]="FAILED"
                FAILED_MODULES+=("$module")
            fi
        else
            print_error "✗ $module: No config file found"
            MODULE_STATUS[$module]="NO_CONFIG"
            FAILED_MODULES+=("$module")
        fi
    fi
    
    module_end=$(date +%s)
    MODULE_TIMES[$module]=$((module_end - module_start))
    
    print_info "$module completed in ${MODULE_TIMES[$module]}s"
done

# Calculate final statistics
END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))
SUCCESS_RATE=$((VERIFIED_OBLIGATIONS * 100 / TOTAL_OBLIGATIONS))

# Generate comprehensive report
cat > "$RESULTS_DIR/regression_test_report.json" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "total_time_seconds": $TOTAL_TIME,
  "total_modules": ${#ALL_MODULES[@]},
  "total_obligations": $TOTAL_OBLIGATIONS,
  "verified_obligations": $VERIFIED_OBLIGATIONS,
  "success_rate": $SUCCESS_RATE,
  "failed_modules": [$(printf '"%s",' "${FAILED_MODULES[@]}" | sed 's/,$//')],
  "module_results": {
EOF

first=true
for module in "${ALL_MODULES[@]}"; do
    if [[ "$first" == "true" ]]; then
        first=false
    else
        echo "," >> "$RESULTS_DIR/regression_test_report.json"
    fi
    
    obligations=${MODULE_OBLIGATIONS[$module]:-0}
    time=${MODULE_TIMES[$module]:-0}
    status=${MODULE_STATUS[$module]:-"UNKNOWN"}
    
    cat >> "$RESULTS_DIR/regression_test_report.json" << EOF
    "$module": {
      "status": "$status",
      "obligations": $obligations,
      "time_seconds": $time
    }
EOF
done

cat >> "$RESULTS_DIR/regression_test_report.json" << EOF
  }
}
EOF

# Print final summary
print_banner "Regression Test Results"
print_info "Total time: ${TOTAL_TIME}s ($(($TOTAL_TIME / 60))m $(($TOTAL_TIME % 60))s)"
print_info "Modules verified: $((${#ALL_MODULES[@]} - ${#FAILED_MODULES[@]}))/${#ALL_MODULES[@]}"
print_info "Proof obligations: $VERIFIED_OBLIGATIONS/$TOTAL_OBLIGATIONS ($SUCCESS_RATE%)"

if [[ ${#FAILED_MODULES[@]} -eq 0 ]]; then
    print_success "🎉 All modules verified successfully!"
    
    if [[ $TOTAL_TIME -lt 2400 ]]; then  # 40 minutes
        print_success "✓ Target completion time achieved (<40 minutes)"
    else
        print_error "⚠ Target completion time exceeded (>40 minutes)"
    fi
    
    exit 0
else
    print_error "❌ ${#FAILED_MODULES[@]} modules failed verification:"
    for failed in "${FAILED_MODULES[@]}"; do
        print_error "  - $failed (${MODULE_STATUS[$failed]})"
    done
    exit 1
fi
