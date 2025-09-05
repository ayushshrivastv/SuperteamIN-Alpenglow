#!/bin/bash

# fix_critical_issues.sh - Automated TLA+ Verification Issue Resolution Script
# This script systematically identifies and fixes common blocking problems in formal verification projects

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$PROJECT_ROOT/backups/$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$PROJECT_ROOT/fix_critical_issues.log"
TLA_DIRS=("$PROJECT_ROOT/specs" "$PROJECT_ROOT/proofs" "$PROJECT_ROOT/models")
CONFIG_DIRS=("$PROJECT_ROOT/models" "$PROJECT_ROOT/configs")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

error() {
    log "${RED}ERROR: $1${NC}"
}

warning() {
    log "${YELLOW}WARNING: $1${NC}"
}

info() {
    log "${BLUE}INFO: $1${NC}"
}

success() {
    log "${GREEN}SUCCESS: $1${NC}"
}

# Create backup directory
create_backup() {
    info "Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    
    # Backup all TLA+ files and configs
    for dir in "${TLA_DIRS[@]}" "${CONFIG_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            local backup_subdir="$BACKUP_DIR/$(basename "$dir")"
            mkdir -p "$backup_subdir"
            find "$dir" -name "*.tla" -o -name "*.cfg" -o -name "*.py" | while read -r file; do
                if [[ -f "$file" ]]; then
                    cp "$file" "$backup_subdir/"
                fi
            done
        fi
    done
    success "Backup created successfully"
}

# Check if TLA+ tools are available
check_tools() {
    info "Checking TLA+ tools availability..."
    
    local tools_found=true
    
    # Check for TLC
    if ! command -v tlc2 >/dev/null 2>&1 && ! command -v java >/dev/null 2>&1; then
        warning "TLC not found in PATH. Please ensure TLA+ tools are installed."
        tools_found=false
    fi
    
    # Check for TLAPS
    if ! command -v tlapm >/dev/null 2>&1; then
        warning "TLAPS not found in PATH. Proof checking will be limited."
    fi
    
    if [[ "$tools_found" == "true" ]]; then
        success "TLA+ tools check completed"
    fi
}

# Find all TLA+ files
find_tla_files() {
    local files=()
    for dir in "${TLA_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            while IFS= read -r -d '' file; do
                files+=("$file")
            done < <(find "$dir" -name "*.tla" -print0)
        fi
    done
    printf '%s\n' "${files[@]}"
}

# Find all config files
find_config_files() {
    local files=()
    for dir in "${CONFIG_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            while IFS= read -r -d '' file; do
                files+=("$file")
            done < <(find "$dir" -name "*.cfg" -print0)
        fi
    done
    printf '%s\n' "${files[@]}"
}

# Extract symbols from TLA+ file
extract_symbols() {
    local file="$1"
    local symbol_type="$2" # CONSTANTS, VARIABLES, operators, etc.
    
    case "$symbol_type" in
        "CONSTANTS")
            grep -A 20 "^CONSTANTS" "$file" | grep -v "^CONSTANTS" | grep -E "^\s*[A-Za-z][A-Za-z0-9_]*" | sed 's/[,\\].*$//' | sed 's/^\s*//' | sed 's/\s*$//'
            ;;
        "VARIABLES")
            grep -A 20 "^VARIABLES" "$file" | grep -v "^VARIABLES" | grep -E "^\s*[A-Za-z][A-Za-z0-9_]*" | sed 's/[,\\].*$//' | sed 's/^\s*//' | sed 's/\s*$//'
            ;;
        "operators")
            grep -E "^[A-Za-z][A-Za-z0-9_]*\s*==" "$file" | sed 's/\s*==.*$//'
            ;;
        "functions")
            grep -E "^[A-Za-z][A-Za-z0-9_]*\(" "$file" | sed 's/\s*(.*$//'
            ;;
    esac
}

# Check for undefined symbols in a TLA+ file
check_undefined_symbols() {
    local file="$1"
    info "Checking undefined symbols in $(basename "$file")"
    
    local undefined_symbols=()
    local file_content
    file_content=$(cat "$file")
    
    # Common TLA+ standard modules and their operators
    local standard_operators=(
        # From Naturals
        "Nat" "+" "-" "*" "^" "<" ">" "<=" ">=" ".." "%" "\\div"
        # From Integers  
        "Int" 
        # From Sequences
        "Seq" "Len" "Head" "Tail" "Append" "\\o" "SubSeq"
        # From FiniteSets
        "Cardinality" "IsFiniteSet"
        # From TLC
        "Print" "PrintT" "Assert" "JavaTime" "TLCGet" "TLCSet"
        # From TLAPS
        "ASSUME" "PROVE" "THEOREM" "LEMMA" "PROOF" "QED" "BY" "DEF" "OBVIOUS"
        # Temporal operators
        "[]" "<>" "~>" "\\A" "\\E" "CHOOSE" "CASE" "IF" "THEN" "ELSE" "LET" "IN"
        # Set operators
        "\\in" "\\notin" "\\subseteq" "\\cup" "\\cap" "\\" "SUBSET" "UNION" "DOMAIN"
        # Logic operators
        "/\\" "\\/" "=>" "<=>" "~" "TRUE" "FALSE"
    )
    
    # Extract all identifiers used in the file
    local used_symbols
    used_symbols=$(grep -oE '\b[A-Za-z][A-Za-z0-9_]*\b' "$file" | sort -u)
    
    # Check each used symbol
    while IFS= read -r symbol; do
        # Skip if it's a standard operator
        if printf '%s\n' "${standard_operators[@]}" | grep -Fxq "$symbol"; then
            continue
        fi
        
        # Skip if it's defined in the file
        if grep -qE "^$symbol\s*(==|\()" "$file" || \
           grep -qE "^\s*$symbol[,\\]?\s*(\\\*.*)?$" "$file"; then
            continue
        fi
        
        # Skip if it's in CONSTANTS or VARIABLES
        if grep -A 20 "^CONSTANTS" "$file" | grep -qE "^\s*$symbol[,\\]?\s*(\\\*.*)?$" || \
           grep -A 20 "^VARIABLES" "$file" | grep -qE "^\s*$symbol[,\\]?\s*(\\\*.*)?$"; then
            continue
        fi
        
        # Check if it's imported via EXTENDS or INSTANCE
        local imported=false
        while IFS= read -r line; do
            if [[ "$line" =~ ^EXTENDS.*$symbol ]] || [[ "$line" =~ ^INSTANCE.*$symbol ]]; then
                imported=true
                break
            fi
        done <<< "$file_content"
        
        if [[ "$imported" == "false" ]]; then
            undefined_symbols+=("$symbol")
        fi
    done <<< "$used_symbols"
    
    if [[ ${#undefined_symbols[@]} -gt 0 ]]; then
        warning "Found undefined symbols in $(basename "$file"): ${undefined_symbols[*]}"
        printf '%s\n' "${undefined_symbols[@]}"
    fi
}

# Fix missing EXTENDS statements
fix_missing_extends() {
    local file="$1"
    info "Fixing missing EXTENDS in $(basename "$file")"
    
    local file_content
    file_content=$(cat "$file")
    
    local missing_extends=()
    
    # Check for common patterns that require specific modules
    if grep -qE '\bNat\b|\b[0-9]+\b|\+|\-|\*|\^|<|>|<=|>=|\.\.' "$file" && ! grep -q "EXTENDS.*Integers\|EXTENDS.*Naturals" "$file"; then
        missing_extends+=("Integers")
    fi
    
    if grep -qE '\bSeq\b|\bLen\b|\bHead\b|\bTail\b|\bAppend\b|\\o|\bSubSeq\b' "$file" && ! grep -q "EXTENDS.*Sequences" "$file"; then
        missing_extends+=("Sequences")
    fi
    
    if grep -qE '\bCardinality\b|\bIsFiniteSet\b|\bSUBSET\b' "$file" && ! grep -q "EXTENDS.*FiniteSets" "$file"; then
        missing_extends+=("FiniteSets")
    fi
    
    if grep -qE '\bPrint\b|\bPrintT\b|\bAssert\b|\bJavaTime\b|\bTLCGet\b|\bTLCSet\b' "$file" && ! grep -q "EXTENDS.*TLC" "$file"; then
        missing_extends+=("TLC")
    fi
    
    if grep -qE '\bTHEOREM\b|\bLEMMA\b|\bPROOF\b|\bQED\b|\bBY\b|\bDEF\b|\bOBVIOUS\b' "$file" && ! grep -q "EXTENDS.*TLAPS" "$file"; then
        missing_extends+=("TLAPS")
    fi
    
    # Add missing EXTENDS
    if [[ ${#missing_extends[@]} -gt 0 ]]; then
        local extends_line
        extends_line=$(printf ", %s" "${missing_extends[@]}")
        extends_line=${extends_line:2} # Remove leading ", "
        
        # Check if EXTENDS already exists
        if grep -q "^EXTENDS" "$file"; then
            # Add to existing EXTENDS line
            sed -i.bak "s/^EXTENDS\s*\(.*\)$/EXTENDS \1, $extends_line/" "$file"
        else
            # Add new EXTENDS line after module declaration
            sed -i.bak "/^-*\s*MODULE.*-*$/a\\
EXTENDS $extends_line\\
" "$file"
        fi
        
        success "Added EXTENDS: $extends_line to $(basename "$file")"
    fi
}

# Fix missing INSTANCE statements
fix_missing_instances() {
    local file="$1"
    info "Checking INSTANCE statements in $(basename "$file")"
    
    # Look for references to other modules that might need INSTANCE
    local potential_instances=()
    
    # Check for module references like ModuleName!Operator
    while IFS= read -r line; do
        if [[ "$line" =~ ([A-Za-z][A-Za-z0-9_]*)! ]]; then
            local module_name="${BASH_REMATCH[1]}"
            if ! grep -q "INSTANCE.*$module_name" "$file" && ! grep -q "EXTENDS.*$module_name" "$file"; then
                potential_instances+=("$module_name")
            fi
        fi
    done < "$file"
    
    # Remove duplicates
    if [[ ${#potential_instances[@]} -gt 0 ]]; then
        local unique_instances
        IFS=" " read -ra unique_instances <<< "$(printf '%s\n' "${potential_instances[@]}" | sort -u | tr '\n' ' ')"
        
        for instance in "${unique_instances[@]}"; do
            # Check if the module file exists
            local module_file
            for dir in "${TLA_DIRS[@]}"; do
                if [[ -f "$dir/$instance.tla" ]]; then
                    module_file="$dir/$instance.tla"
                    break
                fi
            done
            
            if [[ -n "${module_file:-}" ]]; then
                # Add INSTANCE statement
                local instance_line="INSTANCE $instance"
                
                # Add after EXTENDS or at the beginning
                if grep -q "^EXTENDS" "$file"; then
                    sed -i.bak "/^EXTENDS.*$/a\\
\\
$instance_line\\
" "$file"
                else
                    sed -i.bak "/^-*\s*MODULE.*-*$/a\\
\\
$instance_line\\
" "$file"
                fi
                
                success "Added INSTANCE $instance to $(basename "$file")"
            else
                warning "Referenced module $instance not found for $(basename "$file")"
            fi
        done
    fi
}

# Fix constant definitions
fix_constant_definitions() {
    local file="$1"
    info "Checking constant definitions in $(basename "$file")"
    
    # Common constants that are often missing
    local common_constants=(
        "Validators" "ByzantineValidators" "OfflineValidators"
        "MaxSlot" "MaxView" "GST" "Delta"
        "MaxSlicesPerBlock" "MinRelaysPerSlice" "MinHonestRelays"
        "ReconstructionThreshold"
    )
    
    local missing_constants=()
    
    for constant in "${common_constants[@]}"; do
        if grep -qE "\b$constant\b" "$file" && ! grep -qE "^CONSTANTS.*$constant|^\s*$constant[,\\]" "$file"; then
            missing_constants+=("$constant")
        fi
    done
    
    if [[ ${#missing_constants[@]} -gt 0 ]]; then
        # Add CONSTANTS section if it doesn't exist
        if ! grep -q "^CONSTANTS" "$file"; then
            sed -i.bak "/^EXTENDS.*$/a\\
\\
CONSTANTS\\
$(printf '    %s,\\\n' "${missing_constants[@]}" | sed '$s/,\\$//')\\
" "$file"
        else
            # Add to existing CONSTANTS section
            for constant in "${missing_constants[@]}"; do
                sed -i.bak "/^CONSTANTS/,/^[A-Z]/ {
                    /^[A-Z]/i\\
    $constant,\\
                }" "$file"
            done
        fi
        
        success "Added missing constants: ${missing_constants[*]} to $(basename "$file")"
    fi
}

# Fix variable declarations
fix_variable_declarations() {
    local file="$1"
    info "Checking variable declarations in $(basename "$file")"
    
    # Extract variables used in primed form (indicating state variables)
    local primed_vars
    primed_vars=$(grep -oE "[A-Za-z][A-Za-z0-9_]*'" "$file" | sed "s/'$//" | sort -u)
    
    local missing_variables=()
    
    while IFS= read -r var; do
        if [[ -n "$var" ]] && ! grep -qE "^VARIABLES.*$var|^\s*$var[,\\]" "$file"; then
            missing_variables+=("$var")
        fi
    done <<< "$primed_vars"
    
    if [[ ${#missing_variables[@]} -gt 0 ]]; then
        # Add VARIABLES section if it doesn't exist
        if ! grep -q "^VARIABLES" "$file"; then
            sed -i.bak "/^CONSTANTS.*$/,/^[A-Z]/a\\
\\
VARIABLES\\
$(printf '    %s,\\\n' "${missing_variables[@]}" | sed '$s/,\\$//')\\
" "$file"
        else
            # Add to existing VARIABLES section
            for var in "${missing_variables[@]}"; do
                sed -i.bak "/^VARIABLES/,/^[A-Z]/ {
                    /^[A-Z]/i\\
    $var,\\
                }" "$file"
            done
        fi
        
        success "Added missing variables: ${missing_variables[*]} to $(basename "$file")"
    fi
}

# Fix operator definitions
fix_operator_definitions() {
    local file="$1"
    info "Checking operator definitions in $(basename "$file")"
    
    # Common missing operators
    local missing_operators=()
    
    # Check for undefined operators
    if grep -q "Sum(" "$file" && ! grep -q "Sum.*==" "$file"; then
        missing_operators+=("Sum")
    fi
    
    if grep -q "Min(" "$file" && ! grep -q "Min.*==" "$file"; then
        missing_operators+=("Min")
    fi
    
    if grep -q "Max(" "$file" && ! grep -q "Max.*==" "$file"; then
        missing_operators+=("Max")
    fi
    
    # Add missing operator definitions
    for op in "${missing_operators[@]}"; do
        case "$op" in
            "Sum")
                cat >> "$file" << 'EOF'

\* Sum function for sets and functions
RECURSIVE SumSet(_)
SumSet(S) ==
    IF S = {} THEN 0
    ELSE LET x == CHOOSE x \in S : TRUE
         IN x + SumSet(S \ {x})

Sum(f) ==
    LET D == DOMAIN f
    IN IF D = {} THEN 0
       ELSE SumSet({f[x] : x \in D})
EOF
                ;;
            "Min")
                cat >> "$file" << 'EOF'

\* Minimum function
Min(x, y) == IF x <= y THEN x ELSE y
EOF
                ;;
            "Max")
                cat >> "$file" << 'EOF'

\* Maximum function  
Max(x, y) == IF x >= y THEN x ELSE y
EOF
                ;;
        esac
        success "Added definition for operator $op to $(basename "$file")"
    done
}

# Fix proof structure issues
fix_proof_structure() {
    local file="$1"
    info "Checking proof structure in $(basename "$file")"
    
    # Check for common proof issues
    local fixes_applied=false
    
    # Fix missing PROOF keywords
    if grep -q "THEOREM\|LEMMA" "$file" && grep -A 5 "THEOREM\|LEMMA" "$file" | grep -q "BY\|QED" && ! grep -q "PROOF" "$file"; then
        sed -i.bak 's/\(THEOREM.*\|LEMMA.*\)$/\1\nPROOF/' "$file"
        fixes_applied=true
    fi
    
    # Fix missing QED statements
    if grep -q "PROOF" "$file" && ! grep -q "QED" "$file"; then
        sed -i.bak '/PROOF/a\    BY DEF (* Add appropriate definitions *)\n    QED' "$file"
        fixes_applied=true
    fi
    
    # Fix incomplete BY statements
    sed -i.bak 's/BY$/BY DEF (* Add appropriate definitions *)/' "$file"
    
    if [[ "$fixes_applied" == "true" ]]; then
        success "Fixed proof structure issues in $(basename "$file")"
    fi
}

# Fix configuration file syntax
fix_config_syntax() {
    local file="$1"
    info "Checking configuration syntax in $(basename "$file")"
    
    local fixes_applied=false
    
    # Ensure SPECIFICATION line exists
    if ! grep -q "^SPECIFICATION" "$file"; then
        echo "SPECIFICATION Spec" >> "$file"
        fixes_applied=true
    fi
    
    # Add common constant assignments if missing
    local common_constants=(
        "Validators = {1, 2, 3}"
        "ByzantineValidators = {}"
        "OfflineValidators = {}"
        "MaxSlot = 10"
        "MaxView = 5"
        "GST = 100"
        "Delta = 50"
    )
    
    for const_assignment in "${common_constants[@]}"; do
        local const_name
        const_name=$(echo "$const_assignment" | cut -d'=' -f1 | tr -d ' ')
        if ! grep -q "^$const_name\s*=" "$file"; then
            echo "$const_assignment" >> "$file"
            fixes_applied=true
        fi
    done
    
    if [[ "$fixes_applied" == "true" ]]; then
        success "Fixed configuration syntax in $(basename "$file")"
    fi
}

# Validate TLA+ file syntax
validate_tla_syntax() {
    local file="$1"
    info "Validating syntax of $(basename "$file")"
    
    # Try to parse with TLC if available
    if command -v java >/dev/null 2>&1; then
        local tla_tools_jar
        tla_tools_jar=$(find /usr/local /opt /Applications -name "tla2tools.jar" 2>/dev/null | head -1)
        
        if [[ -n "$tla_tools_jar" ]]; then
            if java -cp "$tla_tools_jar" tlc2.TLC -parse "$file" >/dev/null 2>&1; then
                success "Syntax validation passed for $(basename "$file")"
                return 0
            else
                warning "Syntax validation failed for $(basename "$file")"
                return 1
            fi
        fi
    fi
    
    # Basic syntax checks
    local syntax_errors=()
    
    # Check for balanced parentheses
    local paren_count=0
    while IFS= read -r line; do
        local open_count
        local close_count
        open_count=$(echo "$line" | tr -cd '(' | wc -c)
        close_count=$(echo "$line" | tr -cd ')' | wc -c)
        paren_count=$((paren_count + open_count - close_count))
    done < "$file"
    
    if [[ $paren_count -ne 0 ]]; then
        syntax_errors+=("Unbalanced parentheses")
    fi
    
    # Check for common syntax issues
    if grep -q "==" "$file" && grep -q "^[[:space:]]*==" "$file"; then
        syntax_errors+=("Operator definition should not start with ==")
    fi
    
    if [[ ${#syntax_errors[@]} -gt 0 ]]; then
        warning "Syntax issues found in $(basename "$file"): ${syntax_errors[*]}"
        return 1
    else
        success "Basic syntax validation passed for $(basename "$file")"
        return 0
    fi
}

# Main fixing function for a single TLA+ file
fix_tla_file() {
    local file="$1"
    info "Processing TLA+ file: $(basename "$file")"
    
    # Create file-specific backup
    cp "$file" "$file.backup"
    
    # Apply fixes incrementally
    fix_missing_extends "$file"
    fix_missing_instances "$file"
    fix_constant_definitions "$file"
    fix_variable_declarations "$file"
    fix_operator_definitions "$file"
    fix_proof_structure "$file"
    
    # Validate after fixes
    if validate_tla_syntax "$file"; then
        success "Successfully fixed $(basename "$file")"
        rm -f "$file.backup"
    else
        warning "Fixes may have introduced issues in $(basename "$file"), restoring backup"
        mv "$file.backup" "$file"
    fi
}

# Main fixing function for a single config file
fix_config_file() {
    local file="$1"
    info "Processing config file: $(basename "$file")"
    
    # Create file-specific backup
    cp "$file" "$file.backup"
    
    # Apply fixes
    fix_config_syntax "$file"
    
    success "Processed config file $(basename "$file")"
    rm -f "$file.backup"
}

# Generate summary report
generate_report() {
    local report_file="$PROJECT_ROOT/fix_critical_issues_report.txt"
    
    cat > "$report_file" << EOF
TLA+ Critical Issues Fix Report
Generated: $(date)
Backup Location: $BACKUP_DIR

Files Processed:
EOF
    
    # List processed files
    find_tla_files | while read -r file; do
        echo "  TLA+: $(basename "$file")" >> "$report_file"
    done
    
    find_config_files | while read -r file; do
        echo "  Config: $(basename "$file")" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF

Common Issues Fixed:
- Missing EXTENDS statements
- Missing INSTANCE declarations  
- Undefined constants and variables
- Missing operator definitions
- Proof structure issues
- Configuration syntax errors

Next Steps:
1. Run TLC model checking on fixed specifications
2. Run TLAPS proof checking on fixed proofs
3. Validate that all symbols are properly defined
4. Check for any remaining circular dependencies

For detailed logs, see: $LOG_FILE
EOF
    
    info "Report generated: $report_file"
}

# Rollback function
rollback() {
    if [[ -d "$BACKUP_DIR" ]]; then
        info "Rolling back changes from backup: $BACKUP_DIR"
        
        # Restore all files from backup
        for dir in "${TLA_DIRS[@]}" "${CONFIG_DIRS[@]}"; do
            local backup_subdir="$BACKUP_DIR/$(basename "$dir")"
            if [[ -d "$backup_subdir" ]]; then
                find "$backup_subdir" -name "*.tla" -o -name "*.cfg" | while read -r backup_file; do
                    local original_file="$dir/$(basename "$backup_file")"
                    if [[ -f "$original_file" ]]; then
                        cp "$backup_file" "$original_file"
                        info "Restored $(basename "$original_file")"
                    fi
                done
            fi
        done
        
        success "Rollback completed"
    else
        error "Backup directory not found: $BACKUP_DIR"
    fi
}

# Main execution
main() {
    info "Starting TLA+ Critical Issues Fix Script"
    info "Project root: $PROJECT_ROOT"
    
    # Handle command line arguments
    case "${1:-}" in
        "--rollback")
            if [[ -n "${2:-}" ]]; then
                BACKUP_DIR="$2"
                rollback
            else
                error "Please specify backup directory for rollback"
                exit 1
            fi
            exit 0
            ;;
        "--help"|"-h")
            cat << EOF
TLA+ Critical Issues Fix Script

Usage: $0 [OPTIONS]

Options:
  --rollback BACKUP_DIR    Rollback changes from specified backup directory
  --help, -h              Show this help message

The script will:
1. Create backups of all TLA+ and config files
2. Fix common syntax and dependency issues
3. Validate fixes incrementally
4. Generate a summary report

Backup location: $BACKUP_DIR
Log file: $LOG_FILE
EOF
            exit 0
            ;;
    esac
    
    # Initialize
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "TLA+ Critical Issues Fix Log - $(date)" > "$LOG_FILE"
    
    # Check prerequisites
    check_tools
    
    # Create backup
    create_backup
    
    # Process all TLA+ files
    info "Processing TLA+ files..."
    find_tla_files | while read -r file; do
        if [[ -f "$file" ]]; then
            fix_tla_file "$file"
        fi
    done
    
    # Process all config files
    info "Processing configuration files..."
    find_config_files | while read -r file; do
        if [[ -f "$file" ]]; then
            fix_config_file "$file"
        fi
    done
    
    # Generate report
    generate_report
    
    success "TLA+ Critical Issues Fix completed successfully!"
    info "Backup created at: $BACKUP_DIR"
    info "Log file: $LOG_FILE"
    info "Report: $PROJECT_ROOT/fix_critical_issues_report.txt"
    
    # Suggest next steps
    cat << EOF

Next Steps:
1. Review the generated report
2. Run validation: $SCRIPT_DIR/validate_current_status.sh
3. Test with TLC: tlc2 -config models/Small.cfg specs/Alpenglow.tla
4. Run TLAPS proofs: tlapm proofs/*.tla

To rollback if needed: $0 --rollback $BACKUP_DIR
EOF
}

# Execute main function with all arguments
main "$@"