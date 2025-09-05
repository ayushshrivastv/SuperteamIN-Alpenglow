#!/bin/bash

# Alpenglow Specification Validation Script
# Validates all TLA+ specifications and runs model checking

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
TLC_PATH="${TLC_PATH:-../tools/tla2tools.jar}"
SPEC_DIR="../specs"
MODEL_DIR="../models"
PROOF_DIR="../proofs"
LOG_DIR="../logs"
REPORT_FILE="$LOG_DIR/validation_report_$(date +%Y%m%d_%H%M%S).txt"

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "SUCCESS")
            echo -e "${GREEN}[✓]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[✗]${NC} $message"
            ;;
        "INFO")
            echo -e "${YELLOW}[i]${NC} $message"
            ;;
    esac
}

# Function to validate a single spec
validate_spec() {
    local spec=$1
    local config=$2
    local spec_name=$(basename "$spec" .tla)
    local config_name=$(basename "$config" .cfg)
    
    print_status "INFO" "Validating $spec_name with $config_name..."
    
    # Run TLC model checker
    if java -cp "$TLC_PATH" tlc2.TLC \
        -config "$config" \
        -workers auto \
        -coverage 1 \
        -deadlock \
        "$spec" > "$LOG_DIR/${spec_name}_${config_name}.log" 2>&1; then
        
        print_status "SUCCESS" "$spec_name validated successfully with $config_name"
        echo "✓ $spec_name ($config_name): PASSED" >> "$REPORT_FILE"
        return 0
    else
        print_status "ERROR" "$spec_name validation failed with $config_name"
        echo "✗ $spec_name ($config_name): FAILED" >> "$REPORT_FILE"
        echo "  See $LOG_DIR/${spec_name}_${config_name}.log for details" >> "$REPORT_FILE"
        return 1
    fi
}

# Function to check syntax of TLA+ files
check_syntax() {
    local file=$1
    local name=$(basename "$file")
    
    print_status "INFO" "Checking syntax of $name..."
    
    if java -cp "$TLC_PATH" tla2sany.SANY "$file" > /dev/null 2>&1; then
        print_status "SUCCESS" "$name syntax is valid"
        return 0
    else
        print_status "ERROR" "$name has syntax errors"
        return 1
    fi
}

# Function to check for undefined symbol references
check_symbol_references() {
    local file=$1
    local name=$(basename "$file")
    local errors=0
    
    print_status "INFO" "Checking symbol references in $name..."
    
    # Common undefined symbols to check for
    local undefined_symbols=(
        "currentRotor"
        "shredAssignments"
        "rotorShredAssignments"
        "certificates"
        "RequiredStake"
        "FastCertificate"
        "SlowCertificate"
        "TotalStakeSum"
        "StakeOfSet"
        "FastPathThreshold"
        "SlowPathThreshold"
        "MessageDelay"
        "EventualDelivery"
        "AllMessagesDelivered"
        "PartialSynchrony"
        "BoundedDelayAfterGST"
        "ProtocolDelayTolerance"
        "ByzantineAssumption"
        "HonestMajorityAssumption"
        "PigeonholePrinciple"
        "Min"
        "Max"
    )
    
    for symbol in "${undefined_symbols[@]}"; do
        if grep -q "$symbol" "$file" 2>/dev/null; then
            # Check if symbol is defined in the same file
            if ! grep -q "^[[:space:]]*$symbol[[:space:]]*==" "$file" && \
               ! grep -q "^[[:space:]]*$symbol[[:space:]]*\\\\in" "$file" && \
               ! grep -q "^[[:space:]]*$symbol[[:space:]]*\\\\triangleq" "$file"; then
                print_status "ERROR" "Undefined symbol '$symbol' referenced in $name"
                echo "  ✗ Undefined symbol: $symbol" >> "$REPORT_FILE"
                ((errors++))
            fi
        fi
    done
    
    return $errors
}

# Function to check type consistency
check_type_consistency() {
    local file=$1
    local name=$(basename "$file")
    local errors=0
    
    print_status "INFO" "Checking type consistency in $name..."
    
    # Check for common type inconsistencies
    
    # Check if messages is used as both set and function
    if grep -q "messages\[" "$file" && grep -q "messages \\\\cup" "$file"; then
        print_status "ERROR" "Type inconsistency: 'messages' used as both function and set in $name"
        echo "  ✗ Type inconsistency: messages used as both function and set" >> "$REPORT_FILE"
        ((errors++))
    fi
    
    # Check for stake type consistency
    if grep -q "Stake\[" "$file" && grep -q "Stake \\\\in" "$file"; then
        local stake_as_func=$(grep -c "Stake\[" "$file" 2>/dev/null || echo 0)
        local stake_as_set=$(grep -c "Stake \\\\in" "$file" 2>/dev/null || echo 0)
        if [ "$stake_as_func" -gt 0 ] && [ "$stake_as_set" -gt 0 ]; then
            print_status "ERROR" "Type inconsistency: 'Stake' used inconsistently in $name"
            echo "  ✗ Type inconsistency: Stake used inconsistently" >> "$REPORT_FILE"
            ((errors++))
        fi
    fi
    
    # Check for certificate type consistency
    if grep -q "votorGeneratedCerts" "$file" && grep -q "certificates" "$file"; then
        print_status "ERROR" "Type inconsistency: Both 'certificates' and 'votorGeneratedCerts' used in $name"
        echo "  ✗ Type inconsistency: Mixed certificate variable names" >> "$REPORT_FILE"
        ((errors++))
    fi
    
    return $errors
}

# Function to validate INSTANCE declarations
check_imports() {
    local file=$1
    local name=$(basename "$file")
    local errors=0
    
    print_status "INFO" "Checking imports in $name..."
    
    # Extract INSTANCE declarations
    local instances=$(grep "^[[:space:]]*INSTANCE" "$file" 2>/dev/null | sed 's/.*INSTANCE[[:space:]]*\([^[:space:]]*\).*/\1/' || true)
    
    for instance in $instances; do
        local instance_file="$SPEC_DIR/${instance}.tla"
        if [ ! -f "$instance_file" ]; then
            print_status "ERROR" "Missing module: $instance referenced in $name"
            echo "  ✗ Missing module: $instance.tla" >> "$REPORT_FILE"
            ((errors++))
        fi
    done
    
    # Check for common missing modules
    local required_modules=("Utils" "Crypto" "NetworkIntegration")
    for module in "${required_modules[@]}"; do
        if grep -q "$module" "$file" && ! grep -q "INSTANCE $module" "$file"; then
            if [ ! -f "$SPEC_DIR/${module}.tla" ]; then
                print_status "ERROR" "Referenced but not imported: $module in $name"
                echo "  ✗ Referenced but not imported: $module" >> "$REPORT_FILE"
                ((errors++))
            fi
        fi
    done
    
    return $errors
}

# Function to validate configuration files
check_config_syntax() {
    local config=$1
    local name=$(basename "$config")
    local errors=0
    
    print_status "INFO" "Checking configuration syntax in $name..."
    
    # Check for proper constant definitions
    if grep -q "^[[:space:]]*Stake[[:space:]]*=" "$config"; then
        local stake_def=$(grep "^[[:space:]]*Stake[[:space:]]*=" "$config")
        if [[ ! "$stake_def" =~ \[.*\|->.*\] ]]; then
            print_status "ERROR" "Invalid Stake definition syntax in $name"
            echo "  ✗ Invalid Stake definition syntax" >> "$REPORT_FILE"
            ((errors++))
        fi
    fi
    
    # Check for required constants
    local required_constants=("Validators" "MaxView" "MaxTime")
    for constant in "${required_constants[@]}"; do
        if ! grep -q "^[[:space:]]*$constant[[:space:]]*=" "$config"; then
            print_status "ERROR" "Missing required constant: $constant in $name"
            echo "  ✗ Missing required constant: $constant" >> "$REPORT_FILE"
            ((errors++))
        fi
    done
    
    # Check INVARIANT references
    local invariants=$(grep "^[[:space:]]*INVARIANT" "$config" 2>/dev/null | sed 's/.*INVARIANT[[:space:]]*\([^[:space:]]*\).*/\1/' || true)
    for invariant in $invariants; do
        # This is a basic check - in practice, we'd need to parse the spec to verify
        if [[ "$invariant" =~ ^[A-Z] ]]; then
            print_status "INFO" "Found invariant reference: $invariant in $name"
        else
            print_status "ERROR" "Invalid invariant reference: $invariant in $name"
            echo "  ✗ Invalid invariant reference: $invariant" >> "$REPORT_FILE"
            ((errors++))
        fi
    done
    
    # Check CONSTRAINT syntax
    if grep -q "^[[:space:]]*CONSTRAINT" "$config"; then
        local constraints=$(grep "^[[:space:]]*CONSTRAINT" "$config")
        while IFS= read -r constraint; do
            if [[ ! "$constraint" =~ CONSTRAINT[[:space:]]+[A-Za-z] ]]; then
                print_status "ERROR" "Invalid CONSTRAINT syntax in $name"
                echo "  ✗ Invalid CONSTRAINT syntax" >> "$REPORT_FILE"
                ((errors++))
            fi
        done <<< "$constraints"
    fi
    
    return $errors
}

# Function to generate detailed error report
generate_error_report() {
    local file=$1
    local error_type=$2
    local details=$3
    
    echo "" >> "$REPORT_FILE"
    echo "ERROR DETAILS for $(basename "$file"):" >> "$REPORT_FILE"
    echo "  Type: $error_type" >> "$REPORT_FILE"
    echo "  Details: $details" >> "$REPORT_FILE"
    echo "  File: $file" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

# Function to check for common symbol mismatches
check_symbol_mismatches() {
    local file=$1
    local name=$(basename "$file")
    local errors=0
    
    print_status "INFO" "Checking for symbol mismatches in $name..."
    
    # Check for double-binding issues (like currentTime -> clock, clock)
    if grep -q "INSTANCE.*WITH.*clock.*clock" "$file"; then
        print_status "ERROR" "Double-binding detected in $name"
        echo "  ✗ Double-binding: clock parameter bound twice" >> "$REPORT_FILE"
        ((errors++))
    fi
    
    # Check for shredAssignments vs rotorShredAssignments mismatch
    if grep -q "shredAssignments" "$file" && grep -q "rotorShredAssignments" "$file"; then
        print_status "ERROR" "Variable name mismatch: shredAssignments vs rotorShredAssignments in $name"
        echo "  ✗ Variable name mismatch: shredAssignments vs rotorShredAssignments" >> "$REPORT_FILE"
        ((errors++))
    fi
    
    return $errors
}

# Main validation process
main() {
    echo "=========================================="
    echo "    Alpenglow Specification Validator    "
    echo "=========================================="
    echo ""
    
    # Initialize report
    echo "Alpenglow Validation Report" > "$REPORT_FILE"
    echo "Generated: $(date)" >> "$REPORT_FILE"
    echo "===========================================" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    
    # Check TLC availability
    if [ ! -f "$TLC_PATH" ]; then
        print_status "ERROR" "TLA+ tools not found at $TLC_PATH"
        echo "Please ensure tla2tools.jar exists in ../tools/ directory or set TLC_PATH environment variable"
        exit 1
    fi
    
    print_status "INFO" "Starting specification validation..."
    echo ""
    
    # 1. Syntax check all specifications
    echo "Phase 1: Syntax Checking" | tee -a "$REPORT_FILE"
    echo "------------------------" | tee -a "$REPORT_FILE"
    
    for spec in "$SPEC_DIR"/*.tla; do
        if [ -f "$spec" ]; then
            ((total_tests++))
            if check_syntax "$spec"; then
                ((passed_tests++))
            else
                ((failed_tests++))
            fi
        fi
    done
    
    # Check proof files
    for proof in "$PROOF_DIR"/*.tla; do
        if [ -f "$proof" ]; then
            ((total_tests++))
            if check_syntax "$proof"; then
                ((passed_tests++))
            else
                ((failed_tests++))
            fi
        fi
    done
    
    echo "" | tee -a "$REPORT_FILE"
    
    # 1.5. Symbol reference checking
    echo "Phase 1.5: Symbol Reference Checking" | tee -a "$REPORT_FILE"
    echo "------------------------------------" | tee -a "$REPORT_FILE"
    
    for spec in "$SPEC_DIR"/*.tla "$PROOF_DIR"/*.tla; do
        if [ -f "$spec" ]; then
            ((total_tests++))
            local symbol_errors=0
            symbol_errors=$(check_symbol_references "$spec")
            symbol_errors=$((symbol_errors + $(check_symbol_mismatches "$spec")))
            
            if [ $symbol_errors -eq 0 ]; then
                ((passed_tests++))
                print_status "SUCCESS" "No symbol reference issues in $(basename "$spec")"
            else
                ((failed_tests++))
                generate_error_report "$spec" "Symbol Reference" "$symbol_errors undefined symbols found"
            fi
        fi
    done
    
    echo "" | tee -a "$REPORT_FILE"
    
    # 1.6. Type consistency checking
    echo "Phase 1.6: Type Consistency Checking" | tee -a "$REPORT_FILE"
    echo "------------------------------------" | tee -a "$REPORT_FILE"
    
    for spec in "$SPEC_DIR"/*.tla "$PROOF_DIR"/*.tla; do
        if [ -f "$spec" ]; then
            ((total_tests++))
            local type_errors=0
            type_errors=$(check_type_consistency "$spec")
            
            if [ $type_errors -eq 0 ]; then
                ((passed_tests++))
                print_status "SUCCESS" "No type consistency issues in $(basename "$spec")"
            else
                ((failed_tests++))
                generate_error_report "$spec" "Type Consistency" "$type_errors type inconsistencies found"
            fi
        fi
    done
    
    echo "" | tee -a "$REPORT_FILE"
    
    # 1.7. Import validation
    echo "Phase 1.7: Import Validation" | tee -a "$REPORT_FILE"
    echo "----------------------------" | tee -a "$REPORT_FILE"
    
    for spec in "$SPEC_DIR"/*.tla "$PROOF_DIR"/*.tla; do
        if [ -f "$spec" ]; then
            ((total_tests++))
            local import_errors=0
            import_errors=$(check_imports "$spec")
            
            if [ $import_errors -eq 0 ]; then
                ((passed_tests++))
                print_status "SUCCESS" "All imports valid in $(basename "$spec")"
            else
                ((failed_tests++))
                generate_error_report "$spec" "Import Validation" "$import_errors missing modules found"
            fi
        fi
    done
    
    echo "" | tee -a "$REPORT_FILE"
    
    # 1.8. Configuration validation
    echo "Phase 1.8: Configuration Validation" | tee -a "$REPORT_FILE"
    echo "-----------------------------------" | tee -a "$REPORT_FILE"
    
    for config in "$MODEL_DIR"/*.cfg; do
        if [ -f "$config" ]; then
            ((total_tests++))
            local config_errors=0
            config_errors=$(check_config_syntax "$config")
            
            if [ $config_errors -eq 0 ]; then
                ((passed_tests++))
                print_status "SUCCESS" "Configuration valid: $(basename "$config")"
            else
                ((failed_tests++))
                generate_error_report "$config" "Configuration Syntax" "$config_errors configuration issues found"
            fi
        fi
    done
    
    echo "" | tee -a "$REPORT_FILE"
    
    # 2. Model checking with small configuration
    echo "Phase 2: Model Checking (Small)" | tee -a "$REPORT_FILE"
    echo "-------------------------------" | tee -a "$REPORT_FILE"
    
    if [ -f "$SPEC_DIR/Alpenglow.tla" ] && [ -f "$MODEL_DIR/Small.cfg" ]; then
        ((total_tests++))
        if validate_spec "$SPEC_DIR/Alpenglow.tla" "$MODEL_DIR/Small.cfg"; then
            ((passed_tests++))
        else
            ((failed_tests++))
        fi
    fi
    
    echo "" | tee -a "$REPORT_FILE"
    
    # 3. Component validation
    echo "Phase 3: Component Validation" | tee -a "$REPORT_FILE"
    echo "-----------------------------" | tee -a "$REPORT_FILE"
    
    # Validate Votor
    if [ -f "$SPEC_DIR/Votor.tla" ]; then
        print_status "INFO" "Validating Votor component..."
        ((total_tests++))
        if check_syntax "$SPEC_DIR/Votor.tla"; then
            ((passed_tests++))
        else
            ((failed_tests++))
        fi
    fi
    
    # Validate Rotor
    if [ -f "$SPEC_DIR/Rotor.tla" ]; then
        print_status "INFO" "Validating Rotor component..."
        ((total_tests++))
        if check_syntax "$SPEC_DIR/Rotor.tla"; then
            ((passed_tests++))
        else
            ((failed_tests++))
        fi
    fi
    
    # Validate Network
    if [ -f "$SPEC_DIR/Network.tla" ]; then
        print_status "INFO" "Validating Network component..."
        ((total_tests++))
        if check_syntax "$SPEC_DIR/Network.tla"; then
            ((passed_tests++))
        else
            ((failed_tests++))
        fi
    fi
    
    echo "" | tee -a "$REPORT_FILE"
    
    # 4. Proof validation
    echo "Phase 4: Proof Validation" | tee -a "$REPORT_FILE"
    echo "-------------------------" | tee -a "$REPORT_FILE"
    
    for proof in Safety Liveness Resilience; do
        if [ -f "$PROOF_DIR/${proof}.tla" ]; then
            print_status "INFO" "Checking $proof proof..."
            ((total_tests++))
            if check_syntax "$PROOF_DIR/${proof}.tla"; then
                ((passed_tests++))
                print_status "SUCCESS" "$proof proof structure valid"
            else
                ((failed_tests++))
            fi
        fi
    done
    
    echo "" | tee -a "$REPORT_FILE"
    
    # 5. Integration validation (if time permits)
    if [ -f "$SPEC_DIR/Integration.tla" ]; then
        echo "Phase 5: Integration Testing" | tee -a "$REPORT_FILE"
        echo "----------------------------" | tee -a "$REPORT_FILE"
        
        ((total_tests++))
        if check_syntax "$SPEC_DIR/Integration.tla"; then
            ((passed_tests++))
            print_status "SUCCESS" "Integration specification valid"
        else
            ((failed_tests++))
        fi
    fi
    
    echo "" | tee -a "$REPORT_FILE"
    echo "===========================================" | tee -a "$REPORT_FILE"
    echo "           VALIDATION SUMMARY              " | tee -a "$REPORT_FILE"
    echo "===========================================" | tee -a "$REPORT_FILE"
    echo "Total Tests:  $total_tests" | tee -a "$REPORT_FILE"
    echo "Passed:       $passed_tests" | tee -a "$REPORT_FILE"
    echo "Failed:       $failed_tests" | tee -a "$REPORT_FILE"
    
    if [ $failed_tests -eq 0 ]; then
        echo "" | tee -a "$REPORT_FILE"
        print_status "SUCCESS" "All validations passed! ✨"
        echo "Status: ALL TESTS PASSED ✓" >> "$REPORT_FILE"
    else
        echo "" | tee -a "$REPORT_FILE"
        print_status "ERROR" "$failed_tests validation(s) failed"
        echo "Status: FAILURES DETECTED ✗" >> "$REPORT_FILE"
        
        # Add troubleshooting section
        echo "" >> "$REPORT_FILE"
        echo "TROUBLESHOOTING GUIDE:" >> "$REPORT_FILE"
        echo "=====================" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "Common Issues and Solutions:" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "1. Undefined Symbol Errors:" >> "$REPORT_FILE"
        echo "   - Check if missing modules (Utils.tla, Crypto.tla, NetworkIntegration.tla) exist" >> "$REPORT_FILE"
        echo "   - Verify INSTANCE declarations match existing files" >> "$REPORT_FILE"
        echo "   - Ensure all referenced operators are defined or imported" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "2. Type Consistency Errors:" >> "$REPORT_FILE"
        echo "   - Standardize variable usage (e.g., messages as set vs function)" >> "$REPORT_FILE"
        echo "   - Check certificate variable naming consistency" >> "$REPORT_FILE"
        echo "   - Verify stake representation consistency" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "3. Configuration Errors:" >> "$REPORT_FILE"
        echo "   - Use proper TLC syntax for constant definitions" >> "$REPORT_FILE"
        echo "   - Example: Stake = [v1 |-> 10, v2 |-> 10, v3 |-> 10]" >> "$REPORT_FILE"
        echo "   - Ensure all required constants are defined" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "4. Import Validation Errors:" >> "$REPORT_FILE"
        echo "   - Create missing module files" >> "$REPORT_FILE"
        echo "   - Fix INSTANCE declaration syntax" >> "$REPORT_FILE"
        echo "   - Verify module dependencies" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    fi
    
    echo "" | tee -a "$REPORT_FILE"
    echo "Full report saved to: $REPORT_FILE"
    
    # Return appropriate exit code
    [ $failed_tests -eq 0 ]
}

# Run main function
main "$@"
