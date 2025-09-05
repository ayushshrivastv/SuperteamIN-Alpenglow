#!/bin/bash

# validate_current_status.sh
# Comprehensive status validation script for Alpenglow formal verification infrastructure
# Performs real-time assessment to establish ground truth about verification status

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SPECS_DIR="$PROJECT_ROOT/specs"
PROOFS_DIR="$PROJECT_ROOT/proofs"
MODELS_DIR="$PROJECT_ROOT/models"
STATERIGHT_DIR="$PROJECT_ROOT/stateright"
RESULTS_DIR="$PROJECT_ROOT/validation_results"
LOGS_DIR="$RESULTS_DIR/logs"
REPORTS_DIR="$RESULTS_DIR/reports"
CACHE_DIR="$RESULTS_DIR/cache"

# Tool paths (can be overridden by environment variables)
TLC_PATH="${TLC_PATH:-tlc}"
TLAPS_PATH="${TLAPS_PATH:-tlapm}"
CARGO_PATH="${CARGO_PATH:-cargo}"
JAVA_PATH="${JAVA_PATH:-java}"
RUSTC_PATH="${RUSTC_PATH:-rustc}"

# Validation configuration
TIMEOUT_SYNTAX="${TIMEOUT_SYNTAX:-60}"      # 1 minute for syntax checks
TIMEOUT_PROOF="${TIMEOUT_PROOF:-300}"       # 5 minutes for proof checks
TIMEOUT_MODEL="${TIMEOUT_MODEL:-180}"       # 3 minutes for small model checks
TIMEOUT_BUILD="${TIMEOUT_BUILD:-300}"       # 5 minutes for builds
VERBOSE="${VERBOSE:-false}"
DETAILED_ANALYSIS="${DETAILED_ANALYSIS:-true}"
GENERATE_FIXES="${GENERATE_FIXES:-true}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Status tracking
declare -A tool_status
declare -A file_status
declare -A dependency_status
declare -A proof_status
declare -A model_status
declare -A build_status
declare -A issue_list
declare -A fix_suggestions

total_checks=0
passed_checks=0
failed_checks=0
warning_checks=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOGS_DIR/validation.log"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOGS_DIR/validation.log"
    ((passed_checks++))
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOGS_DIR/validation.log"
    ((warning_checks++))
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOGS_DIR/validation.log"
    ((failed_checks++))
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $*" | tee -a "$LOGS_DIR/validation.log"
    fi
}

log_section() {
    echo -e "\n${CYAN}${BOLD}=== $* ===${NC}" | tee -a "$LOGS_DIR/validation.log"
}

# Progress tracking
update_progress() {
    ((total_checks++))
    local progress=$((passed_checks + failed_checks + warning_checks))
    if [[ "$total_checks" -gt 0 ]]; then
        local percent=$((progress * 100 / total_checks))
        echo -e "${CYAN}Progress: $progress/$total_checks ($percent%) - Passed: $passed_checks, Failed: $failed_checks, Warnings: $warning_checks${NC}"
    fi
}

# Add issue to tracking
add_issue() {
    local category="$1"
    local severity="$2"  # "critical", "major", "minor"
    local description="$3"
    local fix_suggestion="${4:-}"
    
    local issue_key="${category}_$(date +%s)_$$"
    issue_list["$issue_key"]="[$severity] $category: $description"
    if [[ -n "$fix_suggestion" ]]; then
        fix_suggestions["$issue_key"]="$fix_suggestion"
    fi
}

# Environment setup
setup_environment() {
    log_section "Setting Up Validation Environment"
    
    # Create output directories
    mkdir -p "$RESULTS_DIR" "$LOGS_DIR" "$REPORTS_DIR" "$CACHE_DIR"
    
    # Initialize log file
    echo "Alpenglow Formal Verification Status Validation" > "$LOGS_DIR/validation.log"
    echo "Started at: $(date)" >> "$LOGS_DIR/validation.log"
    echo "Project root: $PROJECT_ROOT" >> "$LOGS_DIR/validation.log"
    echo "========================================" >> "$LOGS_DIR/validation.log"
    
    log_success "Validation environment initialized"
    update_progress
}

# Tool verification with version compatibility
check_tool_installations() {
    log_section "Tool Installation Verification"
    
    # Check Java (required for TLA+ tools)
    log_info "Checking Java installation..."
    if command -v "$JAVA_PATH" &> /dev/null; then
        local java_version
        java_version=$("$JAVA_PATH" -version 2>&1 | head -n1 | cut -d'"' -f2)
        local java_major
        java_major=$(echo "$java_version" | cut -d'.' -f1)
        
        if [[ "$java_major" -ge 8 ]]; then
            log_success "Java found: $java_version (compatible)"
            tool_status["java"]="installed:$java_version"
        else
            log_error "Java version too old: $java_version (need >= 8)"
            tool_status["java"]="incompatible:$java_version"
            add_issue "java" "critical" "Java version $java_version is too old" "Install Java 8 or newer"
        fi
    else
        log_error "Java not found in PATH"
        tool_status["java"]="missing"
        add_issue "java" "critical" "Java not installed" "Install Java 8 or newer and add to PATH"
    fi
    update_progress
    
    # Check TLC
    log_info "Checking TLC installation..."
    if command -v "$TLC_PATH" &> /dev/null; then
        local tlc_test_output
        if tlc_test_output=$(timeout 10 "$TLC_PATH" -help 2>&1); then
            log_success "TLC found and functional"
            tool_status["tlc"]="installed:functional"
        else
            log_warning "TLC found but may not be functional"
            tool_status["tlc"]="installed:unknown"
            add_issue "tlc" "major" "TLC help command failed" "Check TLC installation and Java compatibility"
        fi
    else
        log_error "TLC not found in PATH"
        tool_status["tlc"]="missing"
        add_issue "tlc" "critical" "TLC not installed" "Install TLA+ Toolbox and add TLC to PATH"
    fi
    update_progress
    
    # Check TLAPS
    log_info "Checking TLAPS installation..."
    if command -v "$TLAPS_PATH" &> /dev/null; then
        local tlaps_version
        if tlaps_version=$("$TLAPS_PATH" --version 2>&1 | head -n1); then
            log_success "TLAPS found: $tlaps_version"
            tool_status["tlaps"]="installed:$tlaps_version"
            
            # Test TLAPS with simple proof
            local test_file="$CACHE_DIR/tlaps_test.tla"
            cat > "$test_file" << 'EOF'
---- MODULE TLAPSTest ----
EXTENDS Naturals
THEOREM Simple == 1 = 1
PROOF OBVIOUS
============================
EOF
            
            if timeout "$TIMEOUT_PROOF" "$TLAPS_PATH" "$test_file" &> "$LOGS_DIR/tlaps_test.log"; then
                log_success "TLAPS proof verification functional"
                tool_status["tlaps"]="functional:$tlaps_version"
            else
                log_warning "TLAPS installed but proof verification failed"
                tool_status["tlaps"]="installed:non-functional"
                add_issue "tlaps" "major" "TLAPS proof verification failed" "Check TLAPS dependencies (Isabelle, Zenon, etc.)"
            fi
        else
            log_warning "TLAPS found but version check failed"
            tool_status["tlaps"]="installed:unknown"
        fi
    else
        log_error "TLAPS not found in PATH"
        tool_status["tlaps"]="missing"
        add_issue "tlaps" "critical" "TLAPS not installed" "Install TLAPS proof system"
    fi
    update_progress
    
    # Check Rust/Cargo
    log_info "Checking Rust/Cargo installation..."
    if command -v "$CARGO_PATH" &> /dev/null; then
        local rust_version
        rust_version=$("$CARGO_PATH" --version | head -n1)
        log_success "Cargo found: $rust_version"
        tool_status["cargo"]="installed:$rust_version"
        
        # Check rustc
        if command -v "$RUSTC_PATH" &> /dev/null; then
            local rustc_version
            rustc_version=$("$RUSTC_PATH" --version | head -n1)
            log_success "Rustc found: $rustc_version"
            tool_status["rustc"]="installed:$rustc_version"
        else
            log_warning "Rustc not found separately"
            tool_status["rustc"]="missing"
        fi
    else
        log_error "Cargo not found in PATH"
        tool_status["cargo"]="missing"
        add_issue "cargo" "major" "Rust/Cargo not installed" "Install Rust toolchain for Stateright verification"
    fi
    update_progress
}

# Syntax validation for TLA+ specifications
validate_tla_syntax() {
    log_section "TLA+ Specification Syntax Validation"
    
    local tla_files=(
        "$SPECS_DIR/Types.tla"
        "$SPECS_DIR/Utils.tla"
        "$SPECS_DIR/Crypto.tla"
        "$SPECS_DIR/Network.tla"
        "$SPECS_DIR/Stake.tla"
        "$SPECS_DIR/Votor.tla"
        "$SPECS_DIR/Rotor.tla"
        "$SPECS_DIR/Alpenglow.tla"
        "$SPECS_DIR/Integration.tla"
    )
    
    for tla_file in "${tla_files[@]}"; do
        local filename
        filename=$(basename "$tla_file")
        log_info "Validating syntax: $filename"
        
        if [[ ! -f "$tla_file" ]]; then
            log_error "File not found: $filename"
            file_status["$filename"]="missing"
            add_issue "syntax" "critical" "Missing specification file: $filename" "Create the missing TLA+ specification file"
            update_progress
            continue
        fi
        
        # Check basic TLA+ syntax with TLC parse
        local syntax_log="$LOGS_DIR/syntax_${filename%.tla}.log"
        if timeout "$TIMEOUT_SYNTAX" "$TLC_PATH" -parse "$tla_file" &> "$syntax_log"; then
            log_success "Syntax valid: $filename"
            file_status["$filename"]="syntax_valid"
            
            # Check for undefined symbols
            if grep -q "Unknown operator" "$syntax_log" 2>/dev/null; then
                log_warning "Undefined symbols found in $filename"
                file_status["$filename"]="syntax_valid_with_warnings"
                add_issue "syntax" "major" "Undefined symbols in $filename" "Define missing operators or add proper imports"
            fi
        else
            log_error "Syntax errors in $filename"
            file_status["$filename"]="syntax_invalid"
            
            # Extract specific error information
            if [[ -f "$syntax_log" ]]; then
                local error_lines
                error_lines=$(grep -E "(Error|Exception|Undefined)" "$syntax_log" | head -3)
                if [[ -n "$error_lines" ]]; then
                    log_debug "Syntax errors: $error_lines"
                    add_issue "syntax" "critical" "Syntax errors in $filename: $error_lines" "Fix TLA+ syntax errors"
                fi
            fi
        fi
        update_progress
    done
}

# Dependency analysis
analyze_dependencies() {
    log_section "Module Dependency Analysis"
    
    local tla_files=(
        "$SPECS_DIR/Types.tla"
        "$SPECS_DIR/Utils.tla"
        "$SPECS_DIR/Crypto.tla"
        "$SPECS_DIR/Network.tla"
        "$SPECS_DIR/Stake.tla"
        "$SPECS_DIR/Votor.tla"
        "$SPECS_DIR/Rotor.tla"
        "$SPECS_DIR/Alpenglow.tla"
        "$SPECS_DIR/Integration.tla"
    )
    
    declare -A module_dependencies
    declare -A module_instances
    
    # Extract dependencies from each file
    for tla_file in "${tla_files[@]}"; do
        if [[ ! -f "$tla_file" ]]; then
            continue
        fi
        
        local filename
        filename=$(basename "$tla_file" .tla)
        log_info "Analyzing dependencies: $filename"
        
        # Extract EXTENDS dependencies
        local extends_deps
        extends_deps=$(grep -E "^EXTENDS" "$tla_file" 2>/dev/null | sed 's/EXTENDS //' | tr ',' '\n' | sed 's/^ *//' | sed 's/ *$//' || true)
        
        # Extract INSTANCE dependencies
        local instance_deps
        instance_deps=$(grep -E "^INSTANCE|^[A-Za-z_][A-Za-z0-9_]* == INSTANCE" "$tla_file" 2>/dev/null | sed -E 's/.*INSTANCE ([A-Za-z_][A-Za-z0-9_]*).*/\1/' || true)
        
        # Store dependencies
        if [[ -n "$extends_deps" ]]; then
            module_dependencies["$filename"]="$extends_deps"
            log_debug "$filename EXTENDS: $extends_deps"
        fi
        
        if [[ -n "$instance_deps" ]]; then
            module_instances["$filename"]="$instance_deps"
            log_debug "$filename INSTANCES: $instance_deps"
        fi
        
        update_progress
    done
    
    # Check for missing dependencies
    log_info "Checking for missing dependencies..."
    for module in "${!module_dependencies[@]}"; do
        local deps="${module_dependencies[$module]}"
        for dep in $deps; do
            # Skip standard TLA+ modules
            if [[ "$dep" =~ ^(Integers|Sequences|FiniteSets|TLC|Naturals|Reals)$ ]]; then
                continue
            fi
            
            # Check if dependency file exists
            local dep_file="$SPECS_DIR/$dep.tla"
            if [[ ! -f "$dep_file" ]]; then
                log_error "Missing dependency: $module requires $dep"
                dependency_status["$module->$dep"]="missing"
                add_issue "dependency" "critical" "$module requires missing module $dep" "Create $dep.tla or fix import statement"
            else
                log_debug "Dependency satisfied: $module -> $dep"
                dependency_status["$module->$dep"]="satisfied"
            fi
        done
    done
    
    # Check for circular dependencies (simplified)
    log_info "Checking for circular dependencies..."
    for module in "${!module_instances[@]}"; do
        local instances="${module_instances[$module]}"
        for instance in $instances; do
            # Check if instance module also instances this module
            if [[ -n "${module_instances[$instance]:-}" ]]; then
                local reverse_instances="${module_instances[$instance]}"
                if [[ "$reverse_instances" =~ $module ]]; then
                    log_warning "Potential circular dependency: $module <-> $instance"
                    dependency_status["$module<->$instance"]="circular"
                    add_issue "dependency" "major" "Circular dependency between $module and $instance" "Refactor to remove circular dependency"
                fi
            fi
        done
    done
    
    log_success "Dependency analysis completed"
    update_progress
}

# Proof validation with TLAPS
validate_proofs() {
    log_section "Proof Obligation Validation"
    
    if [[ "${tool_status[tlaps]}" != "functional:"* ]]; then
        log_warning "TLAPS not functional, skipping proof validation"
        return
    fi
    
    local proof_files=(
        "$PROOFS_DIR/Safety.tla"
        "$PROOFS_DIR/Liveness.tla"
        "$PROOFS_DIR/Resilience.tla"
        "$PROOFS_DIR/WhitepaperTheorems.tla"
    )
    
    for proof_file in "${proof_files[@]}"; do
        local filename
        filename=$(basename "$proof_file")
        log_info "Validating proofs: $filename"
        
        if [[ ! -f "$proof_file" ]]; then
            log_error "Proof file not found: $filename"
            proof_status["$filename"]="missing"
            add_issue "proof" "critical" "Missing proof file: $filename" "Create the proof file with formal proofs"
            update_progress
            continue
        fi
        
        # Run TLAPS on the proof file
        local proof_log="$LOGS_DIR/proof_${filename%.tla}.log"
        if timeout "$TIMEOUT_PROOF" "$TLAPS_PATH" --verbose "$proof_file" &> "$proof_log"; then
            # Parse TLAPS output for proof obligations
            local total_obligations
            local proved_obligations
            local failed_obligations
            
            total_obligations=$(grep -c "obligation" "$proof_log" 2>/dev/null || echo "0")
            proved_obligations=$(grep -c "proved" "$proof_log" 2>/dev/null || echo "0")
            failed_obligations=$(grep -c "failed\|error" "$proof_log" 2>/dev/null || echo "0")
            
            if [[ "$total_obligations" -gt 0 ]]; then
                if [[ "$proved_obligations" -eq "$total_obligations" ]]; then
                    log_success "All proofs verified: $filename ($proved_obligations/$total_obligations)"
                    proof_status["$filename"]="complete:$proved_obligations/$total_obligations"
                else
                    log_warning "Incomplete proofs: $filename ($proved_obligations/$total_obligations)"
                    proof_status["$filename"]="incomplete:$proved_obligations/$total_obligations"
                    add_issue "proof" "major" "Incomplete proofs in $filename" "Complete the missing proof obligations"
                fi
            else
                log_warning "No proof obligations found in $filename"
                proof_status["$filename"]="no_obligations"
                add_issue "proof" "minor" "No proof obligations in $filename" "Add formal proof statements"
            fi
        else
            log_error "TLAPS failed on $filename"
            proof_status["$filename"]="tlaps_failed"
            
            # Extract error information
            if [[ -f "$proof_log" ]]; then
                local error_info
                error_info=$(grep -E "(Error|Exception|Failed)" "$proof_log" | head -2 | tr '\n' '; ')
                if [[ -n "$error_info" ]]; then
                    add_issue "proof" "critical" "TLAPS errors in $filename: $error_info" "Fix proof syntax and logic errors"
                fi
            fi
        fi
        update_progress
    done
}

# Model checking validation
validate_model_checking() {
    log_section "Model Checking Validation"
    
    if [[ "${tool_status[tlc]}" != "installed:functional" ]]; then
        log_warning "TLC not functional, skipping model checking validation"
        return
    fi
    
    local config_files=(
        "$MODELS_DIR/Small.cfg"
        "$MODELS_DIR/Medium.cfg"
        "$MODELS_DIR/EdgeCase.cfg"
        "$MODELS_DIR/Boundary.cfg"
        "$MODELS_DIR/Partition.cfg"
        "$MODELS_DIR/Performance.cfg"
    )
    
    for config_file in "${config_files[@]}"; do
        local filename
        filename=$(basename "$config_file")
        log_info "Validating model configuration: $filename"
        
        if [[ ! -f "$config_file" ]]; then
            log_error "Configuration file not found: $filename"
            model_status["$filename"]="missing"
            add_issue "model" "major" "Missing configuration file: $filename" "Create model checking configuration"
            update_progress
            continue
        fi
        
        # Validate configuration syntax
        local spec_line
        spec_line=$(grep "^SPECIFICATION" "$config_file" || true)
        if [[ -z "$spec_line" ]]; then
            log_error "No SPECIFICATION line in $filename"
            model_status["$filename"]="invalid_config"
            add_issue "model" "major" "Invalid configuration: $filename missing SPECIFICATION" "Add SPECIFICATION line to config"
            update_progress
            continue
        fi
        
        # Extract specification file
        local spec_name
        spec_name=$(echo "$spec_line" | awk '{print $2}')
        local spec_file="$SPECS_DIR/$spec_name.tla"
        
        if [[ ! -f "$spec_file" ]]; then
            log_error "Specification file not found for $filename: $spec_name.tla"
            model_status["$filename"]="missing_spec"
            add_issue "model" "critical" "Configuration $filename references missing spec $spec_name.tla" "Create the specification file or fix config"
            update_progress
            continue
        fi
        
        # Run quick TLC check (limited states)
        local model_log="$LOGS_DIR/model_${filename%.cfg}.log"
        local tlc_cmd="$TLC_PATH -config $config_file -workers 1 -depth 3 $spec_file"
        
        if timeout "$TIMEOUT_MODEL" $tlc_cmd &> "$model_log"; then
            # Parse TLC output
            local states_generated
            local properties_checked
            local violations_found
            
            states_generated=$(grep "states generated" "$model_log" | tail -n1 | awk '{print $1}' 2>/dev/null || echo "0")
            properties_checked=$(grep -c "Property.*satisfied\|Invariant.*satisfied" "$model_log" 2>/dev/null || echo "0")
            violations_found=$(grep -c "Error:\|Invariant.*violated\|Property.*violated" "$model_log" 2>/dev/null || echo "0")
            
            if [[ "$violations_found" -eq 0 ]]; then
                log_success "Model check passed: $filename ($states_generated states, $properties_checked properties)"
                model_status["$filename"]="passed:$states_generated:$properties_checked"
            else
                log_error "Model check violations: $filename ($violations_found violations)"
                model_status["$filename"]="violations:$violations_found"
                add_issue "model" "critical" "Model checking violations in $filename" "Fix specification to satisfy all properties"
            fi
        else
            log_error "TLC failed on $filename"
            model_status["$filename"]="tlc_failed"
            
            # Check for specific errors
            if [[ -f "$model_log" ]]; then
                local error_info
                error_info=$(grep -E "(Error|Exception|Undefined)" "$model_log" | head -2 | tr '\n' '; ')
                if [[ -n "$error_info" ]]; then
                    add_issue "model" "critical" "TLC errors in $filename: $error_info" "Fix configuration and specification errors"
                fi
            fi
        fi
        update_progress
    done
}

# Stateright implementation testing
validate_stateright() {
    log_section "Stateright Implementation Validation"
    
    if [[ "${tool_status[cargo]}" != "installed:"* ]]; then
        log_warning "Cargo not available, skipping Stateright validation"
        return
    fi
    
    if [[ ! -d "$STATERIGHT_DIR" ]]; then
        log_error "Stateright directory not found: $STATERIGHT_DIR"
        build_status["stateright"]="missing_directory"
        add_issue "stateright" "major" "Stateright directory missing" "Create Stateright implementation directory"
        update_progress
        return
    fi
    
    local cargo_file="$STATERIGHT_DIR/Cargo.toml"
    if [[ ! -f "$cargo_file" ]]; then
        log_error "Cargo.toml not found in Stateright directory"
        build_status["stateright"]="missing_cargo"
        add_issue "stateright" "major" "Missing Cargo.toml" "Create Cargo.toml for Stateright project"
        update_progress
        return
    fi
    
    log_info "Checking Stateright project structure..."
    
    # Check for essential Rust files
    local rust_files=(
        "$STATERIGHT_DIR/src/lib.rs"
        "$STATERIGHT_DIR/src/main.rs"
    )
    
    local missing_files=()
    for rust_file in "${rust_files[@]}"; do
        if [[ ! -f "$rust_file" ]]; then
            missing_files+=("$(basename "$rust_file")")
        fi
    done
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        log_warning "Missing Rust files: ${missing_files[*]}"
        add_issue "stateright" "minor" "Missing Rust source files: ${missing_files[*]}" "Create missing Rust implementation files"
    fi
    
    # Attempt to build
    log_info "Attempting Stateright build..."
    local build_log="$LOGS_DIR/stateright_build.log"
    
    if (cd "$STATERIGHT_DIR" && timeout "$TIMEOUT_BUILD" "$CARGO_PATH" check) &> "$build_log"; then
        log_success "Stateright project builds successfully"
        build_status["stateright"]="build_success"
        
        # Try to run tests
        log_info "Running Stateright tests..."
        local test_log="$LOGS_DIR/stateright_test.log"
        
        if (cd "$STATERIGHT_DIR" && timeout "$TIMEOUT_BUILD" "$CARGO_PATH" test --no-run) &> "$test_log"; then
            log_success "Stateright tests compile successfully"
            build_status["stateright_tests"]="compile_success"
        else
            log_warning "Stateright tests fail to compile"
            build_status["stateright_tests"]="compile_failed"
            add_issue "stateright" "minor" "Stateright tests don't compile" "Fix test compilation errors"
        fi
    else
        log_error "Stateright build failed"
        build_status["stateright"]="build_failed"
        
        # Extract build errors
        if [[ -f "$build_log" ]]; then
            local error_info
            error_info=$(grep -E "(error|Error)" "$build_log" | head -3 | tr '\n' '; ')
            if [[ -n "$error_info" ]]; then
                add_issue "stateright" "major" "Stateright build errors: $error_info" "Fix Rust compilation errors"
            fi
        fi
    fi
    update_progress
}

# Configuration file validation
validate_configurations() {
    log_section "Configuration File Validation"
    
    local config_files=(
        "$MODELS_DIR/Small.cfg"
        "$MODELS_DIR/Medium.cfg"
        "$MODELS_DIR/EdgeCase.cfg"
        "$MODELS_DIR/Boundary.cfg"
        "$MODELS_DIR/Partition.cfg"
        "$MODELS_DIR/Performance.cfg"
    )
    
    for config_file in "${config_files[@]}"; do
        local filename
        filename=$(basename "$config_file")
        log_info "Validating configuration syntax: $filename"
        
        if [[ ! -f "$config_file" ]]; then
            log_error "Configuration file not found: $filename"
            update_progress
            continue
        fi
        
        # Check for required sections
        local has_specification=false
        local has_constants=false
        local has_invariants=false
        
        if grep -q "^SPECIFICATION" "$config_file"; then
            has_specification=true
        fi
        
        if grep -q "^CONSTANTS" "$config_file"; then
            has_constants=true
        fi
        
        if grep -q "^INVARIANT\|^PROPERTY" "$config_file"; then
            has_invariants=true
        fi
        
        # Validate configuration completeness
        if [[ "$has_specification" == true ]]; then
            log_success "Configuration has SPECIFICATION: $filename"
        else
            log_error "Configuration missing SPECIFICATION: $filename"
            add_issue "config" "critical" "Configuration $filename missing SPECIFICATION" "Add SPECIFICATION line"
        fi
        
        if [[ "$has_constants" == true ]]; then
            log_debug "Configuration has CONSTANTS: $filename"
        else
            log_warning "Configuration missing CONSTANTS: $filename"
            add_issue "config" "minor" "Configuration $filename missing CONSTANTS" "Add CONSTANTS section if needed"
        fi
        
        if [[ "$has_invariants" == true ]]; then
            log_debug "Configuration has properties/invariants: $filename"
        else
            log_warning "Configuration missing properties/invariants: $filename"
            add_issue "config" "minor" "Configuration $filename missing properties" "Add INVARIANT or PROPERTY statements"
        fi
        
        update_progress
    done
}

# Gap identification and analysis
identify_gaps() {
    log_section "Gap Identification and Analysis"
    
    # Analyze claimed vs actual status
    log_info "Analyzing verification completeness..."
    
    # Check whitepaper theorem coverage
    local whitepaper_file="$PROJECT_ROOT/Solana Alpenglow White Paper v1.1.md"
    if [[ -f "$whitepaper_file" ]]; then
        log_info "Analyzing whitepaper theorem coverage..."
        
        # Extract theorem references from whitepaper
        local theorem_count
        theorem_count=$(grep -c "Theorem [0-9]" "$whitepaper_file" 2>/dev/null || echo "0")
        local lemma_count
        lemma_count=$(grep -c "Lemma [0-9]" "$whitepaper_file" 2>/dev/null || echo "0")
        
        log_info "Found $theorem_count theorems and $lemma_count lemmas in whitepaper"
        
        # Check if WhitepaperTheorems.tla exists and has corresponding proofs
        local whitepaper_proofs="$PROOFS_DIR/WhitepaperTheorems.tla"
        if [[ -f "$whitepaper_proofs" ]]; then
            local formal_theorem_count
            formal_theorem_count=$(grep -c "THEOREM" "$whitepaper_proofs" 2>/dev/null || echo "0")
            local formal_lemma_count
            formal_lemma_count=$(grep -c "LEMMA" "$whitepaper_proofs" 2>/dev/null || echo "0")
            
            log_info "Found $formal_theorem_count formal theorems and $formal_lemma_count formal lemmas"
            
            if [[ "$formal_theorem_count" -lt "$theorem_count" ]]; then
                local missing_theorems=$((theorem_count - formal_theorem_count))
                log_warning "Missing formal theorems: $missing_theorems"
                add_issue "coverage" "major" "$missing_theorems whitepaper theorems not formalized" "Formalize all whitepaper theorems in TLA+"
            fi
            
            if [[ "$formal_lemma_count" -lt "$lemma_count" ]]; then
                local missing_lemmas=$((lemma_count - formal_lemma_count))
                log_warning "Missing formal lemmas: $missing_lemmas"
                add_issue "coverage" "major" "$missing_lemmas whitepaper lemmas not formalized" "Formalize all whitepaper lemmas in TLA+"
            fi
        else
            log_error "WhitepaperTheorems.tla not found"
            add_issue "coverage" "critical" "No formal whitepaper theorem file" "Create WhitepaperTheorems.tla with all theorem formalizations"
        fi
    else
        log_warning "Whitepaper file not found for analysis"
    fi
    
    # Analyze proof completeness
    local total_proof_files=0
    local complete_proof_files=0
    local incomplete_proof_files=0
    
    for status in "${proof_status[@]}"; do
        ((total_proof_files++))
        if [[ "$status" == "complete:"* ]]; then
            ((complete_proof_files++))
        elif [[ "$status" == "incomplete:"* || "$status" == "no_obligations" ]]; then
            ((incomplete_proof_files++))
        fi
    done
    
    if [[ "$total_proof_files" -gt 0 ]]; then
        local proof_completion_rate=$((complete_proof_files * 100 / total_proof_files))
        log_info "Proof completion rate: $proof_completion_rate% ($complete_proof_files/$total_proof_files)"
        
        if [[ "$proof_completion_rate" -lt 80 ]]; then
            add_issue "completeness" "major" "Low proof completion rate: $proof_completion_rate%" "Complete remaining proof obligations"
        fi
    fi
    
    # Analyze model checking coverage
    local total_model_files=0
    local passing_model_files=0
    
    for status in "${model_status[@]}"; do
        ((total_model_files++))
        if [[ "$status" == "passed:"* ]]; then
            ((passing_model_files++))
        fi
    done
    
    if [[ "$total_model_files" -gt 0 ]]; then
        local model_success_rate=$((passing_model_files * 100 / total_model_files))
        log_info "Model checking success rate: $model_success_rate% ($passing_model_files/$total_model_files)"
        
        if [[ "$model_success_rate" -lt 100 ]]; then
            add_issue "completeness" "major" "Model checking failures: $((total_model_files - passing_model_files)) configs failing" "Fix model checking violations"
        fi
    fi
    
    update_progress
}

# Generate blocking issues report
identify_blocking_issues() {
    log_section "Blocking Issues Identification"
    
    local critical_issues=0
    local major_issues=0
    local minor_issues=0
    
    # Count issues by severity
    for issue in "${issue_list[@]}"; do
        if [[ "$issue" == "[critical]"* ]]; then
            ((critical_issues++))
        elif [[ "$issue" == "[major]"* ]]; then
            ((major_issues++))
        elif [[ "$issue" == "[minor]"* ]]; then
            ((minor_issues++))
        fi
    done
    
    log_info "Issue summary: $critical_issues critical, $major_issues major, $minor_issues minor"
    
    # Identify top blocking issues
    if [[ "$critical_issues" -gt 0 ]]; then
        log_error "CRITICAL BLOCKING ISSUES FOUND ($critical_issues)"
        echo -e "\n${RED}${BOLD}TOP BLOCKING ISSUES:${NC}" | tee -a "$LOGS_DIR/validation.log"
        
        local count=0
        for issue_key in "${!issue_list[@]}"; do
            local issue="${issue_list[$issue_key]}"
            if [[ "$issue" == "[critical]"* && "$count" -lt 5 ]]; then
                echo -e "${RED}  • ${issue#[critical] }${NC}" | tee -a "$LOGS_DIR/validation.log"
                if [[ -n "${fix_suggestions[$issue_key]:-}" ]]; then
                    echo -e "${YELLOW}    Fix: ${fix_suggestions[$issue_key]}${NC}" | tee -a "$LOGS_DIR/validation.log"
                fi
                ((count++))
            fi
        done
    fi
    
    update_progress
}

# Generate comprehensive status report
generate_status_report() {
    log_section "Generating Comprehensive Status Report"
    
    local report_file="$REPORTS_DIR/validation_status_report.json"
    local html_report="$REPORTS_DIR/validation_status_report.html"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Generate JSON report
    cat > "$report_file" << EOF
{
  "validation_report": {
    "timestamp": "$timestamp",
    "project_root": "$PROJECT_ROOT",
    "summary": {
      "total_checks": $total_checks,
      "passed_checks": $passed_checks,
      "failed_checks": $failed_checks,
      "warning_checks": $warning_checks,
      "success_rate": $(echo "scale=2; $passed_checks * 100 / $total_checks" | bc -l 2>/dev/null || echo "0")
    },
    "tool_status": {
EOF

    # Add tool status
    local first=true
    for tool in "${!tool_status[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo "," >> "$report_file"
        fi
        echo "      \"$tool\": \"${tool_status[$tool]}\"" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF
    },
    "file_status": {
EOF

    # Add file status
    first=true
    for file in "${!file_status[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo "," >> "$report_file"
        fi
        echo "      \"$file\": \"${file_status[$file]}\"" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF
    },
    "proof_status": {
EOF

    # Add proof status
    first=true
    for proof in "${!proof_status[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo "," >> "$report_file"
        fi
        echo "      \"$proof\": \"${proof_status[$proof]}\"" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF
    },
    "model_status": {
EOF

    # Add model status
    first=true
    for model in "${!model_status[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo "," >> "$report_file"
        fi
        echo "      \"$model\": \"${model_status[$model]}\"" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF
    },
    "issues": [
EOF

    # Add issues
    first=true
    for issue_key in "${!issue_list[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo "," >> "$report_file"
        fi
        local issue="${issue_list[$issue_key]}"
        local fix="${fix_suggestions[$issue_key]:-}"
        cat >> "$report_file" << EOF
      {
        "id": "$issue_key",
        "description": "$issue",
        "fix_suggestion": "$fix"
      }
EOF
    done
    
    cat >> "$report_file" << EOF
    ],
    "recommendations": {
      "immediate_actions": [
EOF

    # Add immediate action recommendations
    local actions=()
    if [[ "${tool_status[java]}" == "missing" ]]; then
        actions+=("\"Install Java 8 or newer for TLA+ tools\"")
    fi
    if [[ "${tool_status[tlc]}" == "missing" ]]; then
        actions+=("\"Install TLA+ Toolbox and TLC\"")
    fi
    if [[ "${tool_status[tlaps]}" == "missing" ]]; then
        actions+=("\"Install TLAPS proof system\"")
    fi
    
    # Add critical file issues
    for file in "${!file_status[@]}"; do
        if [[ "${file_status[$file]}" == "missing" ]]; then
            actions+=("\"Create missing specification file: $file\"")
        elif [[ "${file_status[$file]}" == "syntax_invalid" ]]; then
            actions+=("\"Fix syntax errors in: $file\"")
        fi
    done
    
    # Output actions
    first=true
    for action in "${actions[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo "," >> "$report_file"
        fi
        echo "        $action" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF
      ],
      "next_steps": [
        "Fix all critical blocking issues",
        "Complete missing proof obligations",
        "Resolve model checking violations",
        "Implement missing Stateright components",
        "Validate whitepaper theorem coverage"
      ]
    }
  }
}
EOF

    # Generate HTML report (simplified)
    cat > "$html_report" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Alpenglow Verification Status Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f0f0f0; padding: 20px; border-radius: 5px; }
        .summary { display: flex; gap: 20px; margin: 20px 0; }
        .metric { background: #e8f4f8; padding: 15px; border-radius: 5px; text-align: center; }
        .success { color: #28a745; }
        .error { color: #dc3545; }
        .warning { color: #ffc107; }
        .section { margin: 20px 0; }
        .issue { margin: 10px 0; padding: 10px; border-left: 4px solid #dc3545; background: #f8f9fa; }
        .fix { color: #6c757d; font-style: italic; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Alpenglow Verification Status Report</h1>
        <p>Generated: $timestamp</p>
        <p>Project: $PROJECT_ROOT</p>
    </div>
    
    <div class="summary">
        <div class="metric">
            <h3>Total Checks</h3>
            <div>$total_checks</div>
        </div>
        <div class="metric">
            <h3 class="success">Passed</h3>
            <div>$passed_checks</div>
        </div>
        <div class="metric">
            <h3 class="error">Failed</h3>
            <div>$failed_checks</div>
        </div>
        <div class="metric">
            <h3 class="warning">Warnings</h3>
            <div>$warning_checks</div>
        </div>
    </div>
    
    <div class="section">
        <h2>Critical Issues</h2>
EOF

    # Add critical issues to HTML
    for issue_key in "${!issue_list[@]}"; do
        local issue="${issue_list[$issue_key]}"
        if [[ "$issue" == "[critical]"* ]]; then
            local description="${issue#[critical] }"
            local fix="${fix_suggestions[$issue_key]:-}"
            cat >> "$html_report" << EOF
        <div class="issue">
            <strong>$description</strong>
            $(if [[ -n "$fix" ]]; then echo "<br><span class=\"fix\">Fix: $fix</span>"; fi)
        </div>
EOF
        fi
    done
    
    cat >> "$html_report" << EOF
    </div>
    
    <div class="section">
        <h2>Tool Status</h2>
        <ul>
EOF

    # Add tool status to HTML
    for tool in "${!tool_status[@]}"; do
        local status="${tool_status[$tool]}"
        local css_class="success"
        if [[ "$status" == "missing" || "$status" == *"failed"* ]]; then
            css_class="error"
        elif [[ "$status" == *"unknown"* || "$status" == *"warning"* ]]; then
            css_class="warning"
        fi
        echo "            <li class=\"$css_class\">$tool: $status</li>" >> "$html_report"
    done
    
    cat >> "$html_report" << EOF
        </ul>
    </div>
</body>
</html>
EOF

    log_success "Status report generated: $report_file"
    log_success "HTML report generated: $html_report"
    update_progress
}

# Progress metrics and baseline establishment
establish_baseline_metrics() {
    log_section "Establishing Baseline Metrics"
    
    local metrics_file="$REPORTS_DIR/baseline_metrics.json"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Calculate metrics
    local tool_readiness=0
    local total_tools=0
    for tool in "${!tool_status[@]}"; do
        ((total_tools++))
        if [[ "${tool_status[$tool]}" == "installed:"* || "${tool_status[$tool]}" == "functional:"* ]]; then
            ((tool_readiness++))
        fi
    done
    local tool_readiness_percent=$((tool_readiness * 100 / total_tools))
    
    local syntax_validity=0
    local total_files=0
    for file in "${!file_status[@]}"; do
        ((total_files++))
        if [[ "${file_status[$file]}" == "syntax_valid"* ]]; then
            ((syntax_validity++))
        fi
    done
    local syntax_validity_percent=0
    if [[ "$total_files" -gt 0 ]]; then
        syntax_validity_percent=$((syntax_validity * 100 / total_files))
    fi
    
    local proof_completeness=0
    local total_proofs=0
    for proof in "${!proof_status[@]}"; do
        ((total_proofs++))
        if [[ "${proof_status[$proof]}" == "complete:"* ]]; then
            ((proof_completeness++))
        fi
    done
    local proof_completeness_percent=0
    if [[ "$total_proofs" -gt 0 ]]; then
        proof_completeness_percent=$((proof_completeness * 100 / total_proofs))
    fi
    
    # Generate metrics file
    cat > "$metrics_file" << EOF
{
  "baseline_metrics": {
    "timestamp": "$timestamp",
    "overall_readiness": {
      "percentage": $(echo "scale=2; ($passed_checks * 100) / $total_checks" | bc -l 2>/dev/null || echo "0"),
      "passed_checks": $passed_checks,
      "total_checks": $total_checks
    },
    "tool_readiness": {
      "percentage": $tool_readiness_percent,
      "ready_tools": $tool_readiness,
      "total_tools": $total_tools
    },
    "syntax_validity": {
      "percentage": $syntax_validity_percent,
      "valid_files": $syntax_validity,
      "total_files": $total_files
    },
    "proof_completeness": {
      "percentage": $proof_completeness_percent,
      "complete_proofs": $proof_completeness,
      "total_proofs": $total_proofs
    },
    "critical_issues": $(echo "${issue_list[@]}" | grep -c "\[critical\]" || echo "0"),
    "major_issues": $(echo "${issue_list[@]}" | grep -c "\[major\]" || echo "0"),
    "minor_issues": $(echo "${issue_list[@]}" | grep -c "\[minor\]" || echo "0"),
    "verification_readiness": "$(if [[ "$failed_checks" -eq 0 ]]; then echo "ready"; elif [[ "$failed_checks" -lt 5 ]]; then echo "nearly_ready"; else echo "not_ready"; fi)"
  }
}
EOF

    log_success "Baseline metrics established: $metrics_file"
    update_progress
}

# Main validation workflow
main() {
    local start_time
    start_time=$(date +%s)
    
    echo -e "${CYAN}${BOLD}Alpenglow Formal Verification Status Validation${NC}"
    echo -e "${CYAN}${BOLD}===============================================${NC}"
    echo
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --no-detailed-analysis)
                DETAILED_ANALYSIS=false
                shift
                ;;
            --no-fixes)
                GENERATE_FIXES=false
                shift
                ;;
            --timeout-syntax)
                TIMEOUT_SYNTAX="$2"
                shift 2
                ;;
            --timeout-proof)
                TIMEOUT_PROOF="$2"
                shift 2
                ;;
            --timeout-model)
                TIMEOUT_MODEL="$2"
                shift 2
                ;;
            --help|-h)
                cat << EOF
Usage: $0 [OPTIONS]

Options:
    --verbose, -v              Enable verbose output
    --no-detailed-analysis     Skip detailed dependency and gap analysis
    --no-fixes                 Don't generate fix suggestions
    --timeout-syntax N         Syntax check timeout in seconds (default: 60)
    --timeout-proof N          Proof check timeout in seconds (default: 300)
    --timeout-model N          Model check timeout in seconds (default: 180)
    --help, -h                 Show this help message

Environment Variables:
    TLC_PATH                   Path to TLC executable
    TLAPS_PATH                 Path to TLAPS executable
    CARGO_PATH                 Path to Cargo executable
    JAVA_PATH                  Path to Java executable
    VERBOSE                    Enable verbose output (true/false)
    DETAILED_ANALYSIS          Enable detailed analysis (true/false)
    GENERATE_FIXES             Generate fix suggestions (true/false)

EOF
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Setup environment
    setup_environment
    
    # Run validation phases
    check_tool_installations
    validate_tla_syntax
    
    if [[ "$DETAILED_ANALYSIS" == "true" ]]; then
        analyze_dependencies
        validate_configurations
    fi
    
    validate_proofs
    validate_model_checking
    validate_stateright
    
    if [[ "$DETAILED_ANALYSIS" == "true" ]]; then
        identify_gaps
    fi
    
    identify_blocking_issues
    establish_baseline_metrics
    generate_status_report
    
    # Final summary
    local end_time
    end_time=$(date +%s)
    local total_time=$((end_time - start_time))
    
    echo
    log_section "Validation Summary"
    echo "Total execution time: ${total_time}s"
    echo "Total checks performed: $total_checks"
    echo "Passed: $passed_checks"
    echo "Failed: $failed_checks"
    echo "Warnings: $warning_checks"
    
    if [[ "$failed_checks" -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}✓ All validation checks passed!${NC}"
        echo "The formal verification infrastructure appears to be in good condition."
    elif [[ "$failed_checks" -lt 5 ]]; then
        echo -e "${YELLOW}${BOLD}⚠ Minor issues found${NC}"
        echo "The infrastructure is mostly ready with some minor issues to address."
    else
        echo -e "${RED}${BOLD}✗ Significant issues found${NC}"
        echo "The infrastructure requires attention before proceeding with verification."
    fi
    
    echo
    echo "Detailed reports available in: $REPORTS_DIR"
    echo "Logs available in: $LOGS_DIR"
    
    # Exit with appropriate code
    if [[ "$failed_checks" -eq 0 ]]; then
        exit 0
    elif [[ "$failed_checks" -lt 5 ]]; then
        exit 1
    else
        exit 2
    fi
}

# Handle script interruption
cleanup() {
    log_warning "Validation interrupted"
    
    # Generate partial report if possible
    if [[ "$total_checks" -gt 0 ]]; then
        generate_status_report
    fi
    
    exit 130
}

trap cleanup SIGINT SIGTERM

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi