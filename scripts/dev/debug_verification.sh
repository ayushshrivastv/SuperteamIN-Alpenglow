#!/bin/bash

# debug_verification.sh
# Comprehensive debugging script for Alpenglow verification failures
# Provides systematic diagnosis and repair suggestions for common issues

set -euo pipefail

# Script metadata
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="Alpenglow Verification Debugger"
SCRIPT_AUTHOR="Traycer.AI"

# Directory configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
SPECS_DIR="$PROJECT_ROOT/specs"
PROOFS_DIR="$PROJECT_ROOT/proofs"
MODELS_DIR="$PROJECT_ROOT/models"
STATERIGHT_DIR="$PROJECT_ROOT/stateright"
SUBMISSION_DIR="$PROJECT_ROOT/submission"
LOGS_DIR="$PROJECT_ROOT/submission/verification_results/logs"
DEBUG_DIR="$PROJECT_ROOT/debug_output"

# Tool paths with fallback to downloaded JAR (Comment 6)
TLC_PATH="${TLC_PATH:-tlc}"
TLAPS_PATH="${TLAPS_PATH:-tlapm}"
CARGO_PATH="${CARGO_PATH:-cargo}"
JAVA_PATH="${JAVA_PATH:-java}"
TLA_JAR="$PROJECT_ROOT/tools/tla2tools.jar"

# Debug configuration
VERBOSE="${VERBOSE:-true}"
DETAILED_ANALYSIS="${DETAILED_ANALYSIS:-true}"
GENERATE_FIXES="${GENERATE_FIXES:-true}"
INTERACTIVE_MODE="${INTERACTIVE_MODE:-false}"
MEMORY_CHECK="${MEMORY_CHECK:-true}"
AUTO_APPLY_FIXES="${AUTO_APPLY_FIXES:-false}"  # Comment 6: Require explicit confirmation

# Color codes for enhanced output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Unicode symbols
CHECK_MARK="✓"
CROSS_MARK="✗"
WARNING_MARK="⚠"
INFO_MARK="ℹ"
GEAR_MARK="⚙"
MAGNIFY_MARK="🔍"
WRENCH_MARK="🔧"
LIGHTBULB_MARK="💡"

# Global state tracking
declare -A component_status
declare -A error_details
declare -A fix_suggestions
declare -A test_results
declare -A performance_metrics

# Logging functions
log_info() {
    echo -e "${BLUE}${INFO_MARK}${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}${CHECK_MARK}${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}${WARNING_MARK}${NC} $*" >&2
}

log_error() {
    echo -e "${RED}${CROSS_MARK}${NC} $*" >&2
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $*" >&2
    fi
}

log_highlight() {
    echo -e "${CYAN}${GEAR_MARK}${NC} ${BOLD}$*${NC}" >&2
}

log_fix() {
    echo -e "${GREEN}${LIGHTBULB_MARK}${NC} ${BOLD}Fix:${NC} $*" >&2
}

# User confirmation for auto-generated fixes (Comment 6)
confirm_fix_application() {
    local fix_description="$1"
    local fix_script="$2"
    
    if [[ "$AUTO_APPLY_FIXES" == "true" ]]; then
        log_info "Auto-applying fix: $fix_description"
        return 0
    fi
    
    echo
    log_warning "Auto-generated fix available: $fix_description"
    log_info "Fix script: $fix_script"
    echo -n "Apply this fix? [y/N]: "
    
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        read -r response
        case "$response" in
            [yY]|[yY][eE][sS])
                log_info "Applying fix..."
                return 0
                ;;
            *)
                log_info "Fix skipped by user"
                return 1
                ;;
        esac
    else
        log_info "Non-interactive mode - fix script generated but not applied"
        log_info "Run with --interactive to apply fixes interactively"
        return 1
    fi
}

# Tool availability check with JAR fallback (Comment 6)
check_tool_availability() {
    local tool_name="$1"
    local tool_path="$2"
    local jar_fallback="${3:-}"
    
    if command -v "$tool_path" &> /dev/null; then
        log_success "$tool_name found: $tool_path"
        return 0
    elif [[ -n "$jar_fallback" && -f "$jar_fallback" ]]; then
        log_warning "$tool_name CLI not found, using JAR: $jar_fallback"
        return 0
    else
        log_error "$tool_name not available (neither CLI nor JAR)"
        return 1
    fi
}

# Execute TLC with fallback to JAR
execute_tlc() {
    local args=("$@")
    
    if command -v "$TLC_PATH" &> /dev/null; then
        "$TLC_PATH" "${args[@]}"
    elif [[ -f "$TLA_JAR" ]]; then
        "$JAVA_PATH" -cp "$TLA_JAR" tlc2.TLC "${args[@]}"
    else
        log_error "Cannot execute TLC: neither CLI nor JAR available"
        return 1
    fi
}

# Execute TLAPS with availability check
execute_tlaps() {
    local args=("$@")
    
    if command -v "$TLAPS_PATH" &> /dev/null; then
        "$TLAPS_PATH" "${args[@]}"
    else
        log_error "TLAPS not available - formal proof verification limited"
        return 1
    fi
}

# Setup debug environment
setup_debug_environment() {
    mkdir -p "$DEBUG_DIR"/{logs,reports,fixes,analysis}
    
    # Check tool availability
    log_info "Checking tool availability..."
    check_tool_availability "Java" "$JAVA_PATH"
    check_tool_availability "TLC" "$TLC_PATH" "$TLA_JAR"
    check_tool_availability "TLAPS" "$TLAPS_PATH"
    check_tool_availability "Cargo" "$CARGO_PATH"
    
    local debug_log="$DEBUG_DIR/debug_session.log"
    cat > "$debug_log" << EOF
=== Alpenglow Verification Debug Session ===
Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Script Version: $SCRIPT_VERSION
Project Root: $PROJECT_ROOT
Debug Directory: $DEBUG_DIR
TLA JAR: $TLA_JAR
================================================

EOF
}

# Usage information
show_usage() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION

USAGE:
    $0 [OPTIONS] [COMPONENT]

DESCRIPTION:
    Comprehensive debugging tool for Alpenglow verification failures.
    Systematically diagnoses issues and provides actionable repair suggestions.

COMPONENTS:
    environment     - Check tools, dependencies, and system resources
    rust           - Analyze Rust/Stateright compilation issues
    tlc            - Debug TLC model checking problems
    tlaps          - Diagnose TLAPS proof verification issues
    logs           - Analyze existing verification logs
    all            - Run complete diagnostic suite (default)

OPTIONS:
    --verbose, -v          Enable verbose diagnostic output
    --interactive, -i      Interactive mode with step-by-step guidance
    --no-fixes            Don't generate automatic fix suggestions
    --no-memory-check     Skip memory and resource analysis
    --detailed-analysis   Enable deep analysis of error patterns
    --output-dir DIR      Custom debug output directory
    --help, -h            Show this help message

EXAMPLES:
    $0                     # Full diagnostic suite
    $0 rust               # Focus on Rust compilation issues
    $0 tlc --interactive  # Interactive TLC debugging
    $0 logs --verbose     # Detailed log analysis

OUTPUT:
    Debug results are saved to: $DEBUG_DIR/
    - logs/           Detailed diagnostic logs
    - reports/        Summary reports and analysis
    - fixes/          Generated fix scripts and patches
    - analysis/       Deep analysis results

EOF
}

# System resource monitoring
check_system_resources() {
    log_highlight "Checking System Resources"
    
    local resource_report="$DEBUG_DIR/reports/system_resources.txt"
    
    cat > "$resource_report" << EOF
=== System Resource Analysis ===
Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

EOF
    
    # Memory analysis
    if command -v free &> /dev/null; then
        echo "=== Memory Usage ===" >> "$resource_report"
        free -h >> "$resource_report" 2>&1
        echo "" >> "$resource_report"
        
        local mem_usage
        mem_usage=$(free | awk 'NR==2{printf "%.1f", $3*100/$2}')
        if (( $(echo "$mem_usage > 80" | bc -l 2>/dev/null || echo 0) )); then
            log_warning "High memory usage detected: ${mem_usage}%"
            fix_suggestions["memory"]="Consider closing other applications or increasing system memory"
        else
            log_success "Memory usage acceptable: ${mem_usage}%"
        fi
        performance_metrics["memory_usage"]="$mem_usage"
    fi
    
    # Disk space analysis
    echo "=== Disk Usage ===" >> "$resource_report"
    df -h . >> "$resource_report" 2>&1
    echo "" >> "$resource_report"
    
    local disk_usage
    disk_usage=$(df . | awk 'NR==2{print $5}' | sed 's/%//')
    if [[ $disk_usage -gt 90 ]]; then
        log_warning "Low disk space: ${disk_usage}% used"
        fix_suggestions["disk"]="Free up disk space or move project to larger drive"
    else
        log_success "Disk space sufficient: ${disk_usage}% used"
    fi
    performance_metrics["disk_usage"]="$disk_usage"
    
    # CPU information
    if command -v nproc &> /dev/null; then
        local cpu_cores
        cpu_cores=$(nproc)
        echo "CPU Cores: $cpu_cores" >> "$resource_report"
        log_info "Available CPU cores: $cpu_cores"
        performance_metrics["cpu_cores"]="$cpu_cores"
    fi
    
    # Java heap size check
    if command -v "$JAVA_PATH" &> /dev/null; then
        echo "=== Java Configuration ===" >> "$resource_report"
        local java_version
        java_version=$("$JAVA_PATH" -version 2>&1 | head -1)
        echo "Java Version: $java_version" >> "$resource_report"
        
        # Check current Java heap settings
        local heap_info
        heap_info=$("$JAVA_PATH" -XX:+PrintFlagsFinal -version 2>&1 | grep -E "MaxHeapSize|InitialHeapSize" || echo "Heap info not available")
        echo "Heap Settings: $heap_info" >> "$resource_report"
        
        # Suggest heap size optimization
        local total_mem_gb
        if command -v free &> /dev/null; then
            total_mem_gb=$(free -g | awk 'NR==2{print $2}')
            if [[ $total_mem_gb -ge 8 ]]; then
                fix_suggestions["java_heap"]="Consider setting JAVA_OPTS='-Xmx4g -Xms2g' for better TLC performance"
            elif [[ $total_mem_gb -ge 4 ]]; then
                fix_suggestions["java_heap"]="Consider setting JAVA_OPTS='-Xmx2g -Xms1g' for TLC"
            fi
        fi
    fi
    
    log_success "System resource analysis completed"
    component_status["resources"]="checked"
}

# Environment validation with detailed diagnostics
debug_environment() {
    log_highlight "Debugging Environment Setup"
    
    local env_report="$DEBUG_DIR/reports/environment_analysis.txt"
    local missing_tools=()
    local tool_issues=()
    
    cat > "$env_report" << EOF
=== Environment Diagnostic Report ===
Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

EOF
    
    # Java diagnostics
    log_info "Checking Java installation..."
    if command -v "$JAVA_PATH" &> /dev/null; then
        local java_version
        java_version=$("$JAVA_PATH" -version 2>&1)
        echo "=== Java ===" >> "$env_report"
        echo "$java_version" >> "$env_report"
        echo "" >> "$env_report"
        
        local java_major
        java_major=$(echo "$java_version" | head -1 | sed -E 's/.*version "([0-9]+).*/\1/')
        if [[ $java_major -ge 11 ]]; then
            log_success "Java version compatible: $java_major"
        else
            log_warning "Java version may be too old: $java_major (recommend 11+)"
            tool_issues+=("java_version")
            fix_suggestions["java_version"]="Install OpenJDK 11 or later"
        fi
        component_status["java"]="available"
    else
        log_error "Java not found at: $JAVA_PATH"
        missing_tools+=("java")
        fix_suggestions["java_missing"]="Install OpenJDK: sudo apt-get install openjdk-11-jdk (Ubuntu) or brew install openjdk@11 (macOS)"
        component_status["java"]="missing"
    fi
    
    # TLC diagnostics
    log_info "Checking TLC installation..."
    if command -v "$TLC_PATH" &> /dev/null; then
        echo "=== TLC ===" >> "$env_report"
        local tlc_help
        if tlc_help=$(timeout 10 "$TLC_PATH" -help 2>&1); then
            echo "$tlc_help" | head -10 >> "$env_report"
            log_success "TLC is functional"
            component_status["tlc"]="available"
            
            # Test TLC with a simple specification
            log_debug "Testing TLC functionality..."
            local test_spec="$DEBUG_DIR/test_simple.tla"
            cat > "$test_spec" << 'EOF'
---- MODULE TestSimple ----
VARIABLE x
Init == x = 0
Next == x' = x + 1
Spec == Init /\ [][Next]_x
====
EOF
            
            if timeout 30 "$TLC_PATH" -config /dev/null "$test_spec" &>/dev/null; then
                log_success "TLC basic functionality test passed"
            else
                log_warning "TLC basic functionality test failed"
                tool_issues+=("tlc_function")
                fix_suggestions["tlc_function"]="TLC may have configuration issues. Try reinstalling TLA+ tools."
            fi
        else
            log_warning "TLC found but not responding properly"
            tool_issues+=("tlc_response")
            fix_suggestions["tlc_response"]="TLC installation may be corrupted. Reinstall TLA+ tools."
            component_status["tlc"]="problematic"
        fi
    else
        log_error "TLC not found at: $TLC_PATH"
        missing_tools+=("tlc")
        fix_suggestions["tlc_missing"]="Download TLA+ tools from https://github.com/tlaplus/tlaplus/releases"
        component_status["tlc"]="missing"
    fi
    
    # TLAPS diagnostics
    log_info "Checking TLAPS installation..."
    if command -v "$TLAPS_PATH" &> /dev/null; then
        echo "=== TLAPS ===" >> "$env_report"
        local tlaps_version
        if tlaps_version=$("$TLAPS_PATH" --version 2>&1); then
            echo "$tlaps_version" >> "$env_report"
            log_success "TLAPS is available"
            component_status["tlaps"]="available"
        else
            log_warning "TLAPS found but version check failed"
            tool_issues+=("tlaps_version")
            component_status["tlaps"]="problematic"
        fi
    else
        log_warning "TLAPS not found (optional for basic verification)"
        component_status["tlaps"]="missing"
        fix_suggestions["tlaps_missing"]="Install TLAPS from https://tla.msr-inria.inria.fr/tlaps/content/Download/Source.html"
    fi
    
    # Rust/Cargo diagnostics
    log_info "Checking Rust installation..."
    if command -v "$CARGO_PATH" &> /dev/null; then
        echo "=== Rust/Cargo ===" >> "$env_report"
        local rust_version
        rust_version=$("$CARGO_PATH" --version 2>&1)
        echo "$rust_version" >> "$env_report"
        echo "" >> "$env_report"
        
        log_success "Rust/Cargo is available"
        component_status["rust"]="available"
        
        # Check Rust toolchain
        if command -v rustc &> /dev/null; then
            local rustc_version
            rustc_version=$(rustc --version 2>&1)
            echo "Rust Compiler: $rustc_version" >> "$env_report"
        fi
    else
        log_error "Rust/Cargo not found at: $CARGO_PATH"
        missing_tools+=("rust")
        fix_suggestions["rust_missing"]="Install Rust from https://rustup.rs/"
        component_status["rust"]="missing"
    fi
    
    # Project structure validation
    log_info "Validating project structure..."
    echo "=== Project Structure ===" >> "$env_report"
    local missing_dirs=()
    local required_dirs=("$SPECS_DIR" "$PROOFS_DIR" "$MODELS_DIR" "$STATERIGHT_DIR")
    
    for dir in "${required_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            echo "✓ $(basename "$dir")/" >> "$env_report"
            log_debug "Found directory: $(basename "$dir")"
        else
            echo "✗ $(basename "$dir")/" >> "$env_report"
            missing_dirs+=("$(basename "$dir")")
            log_warning "Missing directory: $(basename "$dir")"
        fi
    done
    
    if [[ ${#missing_dirs[@]} -gt 0 ]]; then
        fix_suggestions["project_structure"]="Create missing directories: mkdir -p ${missing_dirs[*]}"
    fi
    
    # Generate environment fix script
    if [[ ${#missing_tools[@]} -gt 0 ]] || [[ ${#tool_issues[@]} -gt 0 ]]; then
        generate_environment_fix_script
    fi
    
    log_success "Environment diagnostic completed"
    component_status["environment"]="analyzed"
}

# Generate environment fix script
generate_environment_fix_script() {
    local fix_script="$DEBUG_DIR/fixes/fix_environment.sh"
    
    cat > "$fix_script" << 'EOF'
#!/bin/bash
# Auto-generated environment fix script

set -euo pipefail

echo "=== Alpenglow Environment Fix Script ==="
echo "This script will attempt to fix common environment issues."
echo ""

# Detect OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
else
    OS="unknown"
    echo "Warning: Unsupported OS type: $OSTYPE"
fi

EOF
    
    # Add Java installation
    if [[ " ${missing_tools[*]} " =~ " java " ]]; then
        cat >> "$fix_script" << 'EOF'
# Install Java
echo "Installing Java..."
if [[ "$OS" == "linux" ]]; then
    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y openjdk-11-jdk
    elif command -v yum &> /dev/null; then
        sudo yum install -y java-11-openjdk-devel
    fi
elif [[ "$OS" == "macos" ]]; then
    if command -v brew &> /dev/null; then
        brew install openjdk@11
    else
        echo "Please install Homebrew first: https://brew.sh/"
    fi
fi

EOF
    fi
    
    # Add TLC installation
    if [[ " ${missing_tools[*]} " =~ " tlc " ]]; then
        cat >> "$fix_script" << 'EOF'
# Install TLA+ Tools (including TLC)
echo "Installing TLA+ Tools..."
TLA_VERSION="1.8.0"
TLA_URL="https://github.com/tlaplus/tlaplus/releases/download/v${TLA_VERSION}/tla2tools.jar"
TLA_DIR="/opt/tlaplus"

sudo mkdir -p "$TLA_DIR"
sudo wget -O "$TLA_DIR/tla2tools.jar" "$TLA_URL"

# Create TLC wrapper script
sudo tee /usr/local/bin/tlc > /dev/null << 'TLCEOF'
#!/bin/bash
java -cp /opt/tlaplus/tla2tools.jar tlc2.TLC "$@"
TLCEOF

sudo chmod +x /usr/local/bin/tlc
echo "TLC installed to /usr/local/bin/tlc"

EOF
    fi
    
    # Add Rust installation
    if [[ " ${missing_tools[*]} " =~ " rust " ]]; then
        cat >> "$fix_script" << 'EOF'
# Install Rust
echo "Installing Rust..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source ~/.cargo/env
echo "Rust installed. Please restart your shell or run: source ~/.cargo/env"

EOF
    fi
    
    cat >> "$fix_script" << 'EOF'
echo ""
echo "Environment fix script completed!"
echo "Please restart your shell and re-run the verification."
EOF
    
    chmod +x "$fix_script"
    log_fix "Environment fix script generated: $fix_script"
}

# Rust compilation diagnostics
debug_rust_compilation() {
    log_highlight "Debugging Rust Compilation Issues"
    
    if [[ ! -d "$STATERIGHT_DIR" ]]; then
        log_error "Stateright directory not found: $STATERIGHT_DIR"
        component_status["rust"]="missing_project"
        return 1
    fi
    
    cd "$STATERIGHT_DIR"
    
    local rust_report="$DEBUG_DIR/reports/rust_analysis.txt"
    local compilation_log="$DEBUG_DIR/logs/rust_compilation.log"
    
    cat > "$rust_report" << EOF
=== Rust Compilation Diagnostic Report ===
Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Project Directory: $STATERIGHT_DIR

EOF
    
    # Check Cargo.toml
    log_info "Analyzing Cargo.toml..."
    if [[ -f "Cargo.toml" ]]; then
        echo "=== Cargo.toml Analysis ===" >> "$rust_report"
        echo "✓ Cargo.toml found" >> "$rust_report"
        
        # Extract dependencies
        local deps
        deps=$(grep -A 20 "^\[dependencies\]" Cargo.toml 2>/dev/null || echo "No dependencies section found")
        echo "Dependencies:" >> "$rust_report"
        echo "$deps" >> "$rust_report"
        echo "" >> "$rust_report"
        
        log_success "Cargo.toml found and analyzed"
    else
        log_error "Cargo.toml not found in $STATERIGHT_DIR"
        component_status["rust"]="invalid_project"
        return 1
    fi
    
    # Clean previous build artifacts
    log_info "Cleaning previous build artifacts..."
    cargo clean &>/dev/null || true
    
    # Attempt compilation with detailed error analysis
    log_info "Attempting compilation with detailed error reporting..."
    echo "=== Compilation Attempt ===" >> "$rust_report"
    
    local compile_success=false
    if cargo check --lib --verbose > "$compilation_log" 2>&1; then
        compile_success=true
        log_success "Rust compilation successful"
        component_status["rust"]="compiles"
    else
        log_warning "Rust compilation failed - analyzing errors..."
        component_status["rust"]="compilation_errors"
        
        # Detailed error analysis
        analyze_rust_errors "$compilation_log" "$rust_report"
    fi
    
    # Test compilation
    if [[ "$compile_success" == "true" ]]; then
        log_info "Running Rust tests..."
        local test_log="$DEBUG_DIR/logs/rust_tests.log"
        
        if cargo test --lib > "$test_log" 2>&1; then
            log_success "Rust tests passed"
            component_status["rust_tests"]="passed"
        else
            log_warning "Rust tests failed - analyzing test errors..."
            component_status["rust_tests"]="failed"
            analyze_rust_test_errors "$test_log" "$rust_report"
        fi
    fi
    
    cd - &>/dev/null
    log_success "Rust compilation diagnostic completed"
}

# Analyze Rust compilation errors
analyze_rust_errors() {
    local compilation_log="$1"
    local rust_report="$2"
    
    echo "=== Compilation Error Analysis ===" >> "$rust_report"
    
    # Extract and categorize errors
    local type_errors=()
    local missing_symbols=()
    local borrow_errors=()
    local other_errors=()
    
    while IFS= read -r line; do
        if echo "$line" | grep -q "mismatched types"; then
            type_errors+=("$line")
        elif echo "$line" | grep -q "cannot find"; then
            missing_symbols+=("$line")
        elif echo "$line" | grep -q "borrow"; then
            borrow_errors+=("$line")
        elif echo "$line" | grep -q "error\["; then
            other_errors+=("$line")
        fi
    done < "$compilation_log"
    
    # Analyze type mismatches (common BlockHash issue)
    if [[ ${#type_errors[@]} -gt 0 ]]; then
        echo "Type Mismatch Errors Found: ${#type_errors[@]}" >> "$rust_report"
        log_error "Found ${#type_errors[@]} type mismatch errors"
        
        # Check for specific BlockHash type confusion
        local blockhash_errors=0
        for error in "${type_errors[@]}"; do
            if echo "$error" | grep -q "expected.*u64.*found.*\[u8; 32\]"; then
                ((blockhash_errors++))
                echo "  BlockHash type confusion: $error" >> "$rust_report"
            elif echo "$error" | grep -q "expected.*\[u8; 32\].*found.*u64"; then
                ((blockhash_errors++))
                echo "  Reverse BlockHash confusion: $error" >> "$rust_report"
            fi
        done
        
        if [[ $blockhash_errors -gt 0 ]]; then
            log_error "Detected $blockhash_errors BlockHash type mismatches"
            fix_suggestions["blockhash_types"]="Fix BlockHash type usage in test functions"
            generate_blockhash_fix_script
        fi
    fi
    
    # Analyze missing symbols
    if [[ ${#missing_symbols[@]} -gt 0 ]]; then
        echo "Missing Symbol Errors: ${#missing_symbols[@]}" >> "$rust_report"
        log_error "Found ${#missing_symbols[@]} missing symbol errors"
        
        for error in "${missing_symbols[@]}"; do
            echo "  $error" >> "$rust_report"
        done
        
        fix_suggestions["missing_symbols"]="Check imports and module declarations"
    fi
    
    # Analyze borrow checker errors
    if [[ ${#borrow_errors[@]} -gt 0 ]]; then
        echo "Borrow Checker Errors: ${#borrow_errors[@]}" >> "$rust_report"
        log_error "Found ${#borrow_errors[@]} borrow checker errors"
        
        fix_suggestions["borrow_checker"]="Review ownership and lifetime patterns"
    fi
    
    # Copy full compilation log
    echo "" >> "$rust_report"
    echo "=== Full Compilation Log ===" >> "$rust_report"
    cat "$compilation_log" >> "$rust_report"
}

# Generate BlockHash type fix script
generate_blockhash_fix_script() {
    local fix_script="$DEBUG_DIR/fixes/fix_blockhash_types.sh"
    
    cat > "$fix_script" << 'EOF'
#!/bin/bash
# Auto-generated BlockHash type fix script

set -euo pipefail

echo "=== BlockHash Type Fix Script ==="
echo "This script will fix common BlockHash type mismatches in Rust tests."
echo ""

STATERIGHT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/stateright"
ROTOR_FILE="$STATERIGHT_DIR/src/rotor.rs"

if [[ ! -f "$ROTOR_FILE" ]]; then
    echo "Error: rotor.rs not found at $ROTOR_FILE"
    exit 1
fi

echo "Backing up original file..."
cp "$ROTOR_FILE" "$ROTOR_FILE.backup.$(date +%s)"

echo "Applying BlockHash type fixes..."

# Fix ErasureBlock::new calls in test functions
sed -i.tmp 's/ErasureBlock::new(\[1u8; 32\]/ErasureBlock::new(1u64/g' "$ROTOR_FILE"
sed -i.tmp 's/ErasureBlock::new(\[2u8; 32\]/ErasureBlock::new(2u64/g' "$ROTOR_FILE"

# Fix Shred::new_data calls in test functions
sed -i.tmp 's/Shred::new_data(\[1u8; 32\]/Shred::new_data(1u64/g' "$ROTOR_FILE"
sed -i.tmp 's/Shred::new_data(\[2u8; 32\]/Shred::new_data(2u64/g' "$ROTOR_FILE"

# Remove temporary file
rm -f "$ROTOR_FILE.tmp"

echo "BlockHash type fixes applied successfully!"
echo "Original file backed up as: $ROTOR_FILE.backup.*"
echo ""
echo "Please re-run the verification to test the fixes."
EOF
    
    chmod +x "$fix_script"
    log_fix "BlockHash type fix script generated: $fix_script"
}

# Analyze Rust test errors
analyze_rust_test_errors() {
    local test_log="$1"
    local rust_report="$2"
    
    echo "=== Test Error Analysis ===" >> "$rust_report"
    
    # Extract test failures
    local failed_tests=()
    while IFS= read -r line; do
        if echo "$line" | grep -q "test.*FAILED"; then
            failed_tests+=("$line")
        fi
    done < "$test_log"
    
    if [[ ${#failed_tests[@]} -gt 0 ]]; then
        echo "Failed Tests: ${#failed_tests[@]}" >> "$rust_report"
        for test in "${failed_tests[@]}"; do
            echo "  $test" >> "$rust_report"
        done
        
        log_error "Found ${#failed_tests[@]} failing tests"
        fix_suggestions["test_failures"]="Review test logic and fix failing assertions"
    fi
    
    # Copy full test log
    echo "" >> "$rust_report"
    echo "=== Full Test Log ===" >> "$rust_report"
    cat "$test_log" >> "$rust_report"
}

# TLC debugging with detailed analysis
debug_tlc_model_checking() {
    log_highlight "Debugging TLC Model Checking"
    
    local tlc_report="$DEBUG_DIR/reports/tlc_analysis.txt"
    
    cat > "$tlc_report" << EOF
=== TLC Model Checking Diagnostic Report ===
Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

EOF
    
    # Check TLA+ specifications
    log_info "Analyzing TLA+ specifications..."
    if [[ ! -d "$SPECS_DIR" ]]; then
        log_error "Specifications directory not found: $SPECS_DIR"
        component_status["tlc"]="missing_specs"
        return 1
    fi
    
    local spec_count=0
    local valid_specs=0
    local spec_errors=()
    
    echo "=== Specification Analysis ===" >> "$tlc_report"
    
    for spec in "$SPECS_DIR"/*.tla; do
        if [[ -f "$spec" ]]; then
            ((spec_count++))
            local spec_name
            spec_name=$(basename "$spec" .tla)
            
            log_info "Checking specification: $spec_name"
            
            local parse_log="$DEBUG_DIR/logs/tlc_parse_${spec_name}.log"
            if timeout 60 "$TLC_PATH" -parse "$spec" > "$parse_log" 2>&1; then
                ((valid_specs++))
                echo "✓ $spec_name: Valid syntax" >> "$tlc_report"
                log_success "Specification $spec_name has valid syntax"
            else
                echo "✗ $spec_name: Parse errors" >> "$tlc_report"
                log_error "Specification $spec_name has parse errors"
                spec_errors+=("$spec_name")
                
                # Analyze specific parse errors
                analyze_tla_parse_errors "$parse_log" "$spec_name" "$tlc_report"
            fi
        fi
    done
    
    echo "" >> "$tlc_report"
    echo "Specification Summary: $valid_specs/$spec_count valid" >> "$tlc_report"
    
    # Check model configurations
    log_info "Analyzing model configurations..."
    if [[ -d "$MODELS_DIR" ]]; then
        echo "=== Model Configuration Analysis ===" >> "$tlc_report"
        
        local config_count=0
        local valid_configs=0
        
        for config in "$MODELS_DIR"/*.cfg; do
            if [[ -f "$config" ]]; then
                ((config_count++))
                local config_name
                config_name=$(basename "$config" .cfg)
                
                log_info "Checking configuration: $config_name"
                
                # Basic configuration validation
                if grep -q "SPECIFICATION\|INIT\|NEXT" "$config"; then
                    ((valid_configs++))
                    echo "✓ $config_name: Valid structure" >> "$tlc_report"
                    
                    # Test model checking with minimal parameters
                    test_tlc_configuration "$config" "$config_name" "$tlc_report"
                else
                    echo "✗ $config_name: Invalid structure" >> "$tlc_report"
                    log_warning "Configuration $config_name has invalid structure"
                fi
            fi
        done
        
        echo "" >> "$tlc_report"
        echo "Configuration Summary: $valid_configs/$config_count valid" >> "$tlc_report"
    else
        log_warning "Models directory not found: $MODELS_DIR"
        component_status["tlc"]="missing_models"
    fi
    
    # Generate TLC debugging configurations
    generate_tlc_debug_configs
    
    log_success "TLC diagnostic completed"
    component_status["tlc"]="analyzed"
}

# Analyze TLA+ parse errors
analyze_tla_parse_errors() {
    local parse_log="$1"
    local spec_name="$2"
    local tlc_report="$3"
    
    echo "  Parse errors for $spec_name:" >> "$tlc_report"
    
    # Extract and categorize errors
    while IFS= read -r line; do
        if echo "$line" | grep -q "Lexical error"; then
            echo "    Lexical error: $line" >> "$tlc_report"
            fix_suggestions["tla_lexical"]="Check for invalid characters or tokens in $spec_name"
        elif echo "$line" | grep -q "Parse error"; then
            echo "    Parse error: $line" >> "$tlc_report"
            fix_suggestions["tla_parse"]="Check TLA+ syntax in $spec_name"
        elif echo "$line" | grep -q "Semantic error"; then
            echo "    Semantic error: $line" >> "$tlc_report"
            fix_suggestions["tla_semantic"]="Check variable declarations and operator definitions in $spec_name"
        fi
    done < "$parse_log"
}

# Test TLC configuration
test_tlc_configuration() {
    local config="$1"
    local config_name="$2"
    local tlc_report="$3"
    
    # Extract specification name
    local spec_name="Alpenglow"
    if grep -q "^SPECIFICATION" "$config"; then
        spec_name=$(grep "^SPECIFICATION" "$config" | awk '{print $2}')
    fi
    
    local spec_file="$SPECS_DIR/$spec_name.tla"
    if [[ ! -f "$spec_file" ]]; then
        echo "    ✗ Specification file not found: $spec_name.tla" >> "$tlc_report"
        return 1
    fi
    
    # Run quick TLC test
    local test_log="$DEBUG_DIR/logs/tlc_test_${config_name}.log"
    log_debug "Testing TLC configuration: $config_name"
    
    if timeout 120 "$TLC_PATH" -config "$config" -workers 1 -depth 3 "$spec_file" > "$test_log" 2>&1; then
        echo "    ✓ Quick model check passed" >> "$tlc_report"
        log_success "Configuration $config_name passed quick test"
    else
        local exit_code=$?
        echo "    ✗ Quick model check failed (exit code: $exit_code)" >> "$tlc_report"
        log_warning "Configuration $config_name failed quick test"
        
        # Analyze TLC errors
        analyze_tlc_errors "$test_log" "$config_name" "$tlc_report"
    fi
}

# Analyze TLC errors
analyze_tlc_errors() {
    local test_log="$1"
    local config_name="$2"
    local tlc_report="$3"
    
    echo "    TLC errors for $config_name:" >> "$tlc_report"
    
    if grep -q "Java heap space" "$test_log"; then
        echo "      Memory: Out of heap space" >> "$tlc_report"
        fix_suggestions["tlc_memory"]="Increase Java heap size: export JAVA_OPTS='-Xmx4g'"
    fi
    
    if grep -q "Deadlock" "$test_log"; then
        echo "      Model: Deadlock detected" >> "$tlc_report"
        fix_suggestions["tlc_deadlock"]="Add fairness conditions or review Next action in $config_name"
    fi
    
    if grep -q "Invariant.*violated" "$test_log"; then
        local violated_invariant
        violated_invariant=$(grep "Invariant.*violated" "$test_log" | head -1)
        echo "      Invariant: $violated_invariant" >> "$tlc_report"
        fix_suggestions["tlc_invariant"]="Review invariant definitions and model logic"
    fi
    
    if grep -q "Parse error" "$test_log"; then
        echo "      Syntax: Parse error in specification" >> "$tlc_report"
        fix_suggestions["tlc_syntax"]="Check TLA+ specification syntax"
    fi
}

# Generate TLC debugging configurations
generate_tlc_debug_configs() {
    local debug_config_dir="$DEBUG_DIR/configs"
    mkdir -p "$debug_config_dir"
    
    # Minimal debug configuration
    cat > "$debug_config_dir/TLC_Debug_Minimal.cfg" << 'EOF'
\* Minimal TLC configuration for debugging
SPECIFICATION Alpenglow
CONSTANTS
    N = 3
    F = 1
    MaxSlot = 3
    MaxEpoch = 2
INIT Init
NEXT Next
INVARIANT TypeInvariant
EOF
    
    # Memory-optimized configuration
    cat > "$debug_config_dir/TLC_Debug_Memory.cfg" << 'EOF'
\* Memory-optimized TLC configuration
SPECIFICATION Alpenglow
CONSTANTS
    N = 4
    F = 1
    MaxSlot = 5
    MaxEpoch = 3
INIT Init
NEXT Next
INVARIANT TypeInvariant
PROPERTY []<>Progress
EOF
    
    log_fix "TLC debug configurations generated in $debug_config_dir"
}

# TLAPS debugging
debug_tlaps_proofs() {
    log_highlight "Debugging TLAPS Proof Verification"
    
    if [[ ! -d "$PROOFS_DIR" ]]; then
        log_warning "Proofs directory not found: $PROOFS_DIR"
        component_status["tlaps"]="missing_proofs"
        return 0
    fi
    
    local tlaps_report="$DEBUG_DIR/reports/tlaps_analysis.txt"
    
    cat > "$tlaps_report" << EOF
=== TLAPS Proof Diagnostic Report ===
Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

EOF
    
    # Check proof modules
    log_info "Analyzing proof modules..."
    local proof_modules=()
    
    for proof in "$PROOFS_DIR"/*.tla; do
        if [[ -f "$proof" ]]; then
            local module
            module=$(basename "$proof" .tla)
            proof_modules+=("$module")
            
            log_info "Checking proof module: $module"
            
            # Check for proof obligations
            local obligations
            obligations=$(grep -c "THEOREM\|LEMMA" "$proof" 2>/dev/null || echo "0")
            echo "$module: $obligations proof obligations" >> "$tlaps_report"
            
            if [[ $obligations -gt 0 ]]; then
                # Test proof generation
                test_tlaps_module "$proof" "$module" "$tlaps_report"
            else
                log_warning "No proof obligations found in $module"
            fi
        fi
    done
    
    if [[ ${#proof_modules[@]} -eq 0 ]]; then
        log_warning "No proof modules found"
        component_status["tlaps"]="no_proofs"
    else
        log_success "Found ${#proof_modules[@]} proof modules"
        component_status["tlaps"]="analyzed"
    fi
}

# Test TLAPS module
test_tlaps_module() {
    local proof_file="$1"
    local module="$2"
    local tlaps_report="$3"
    
    if [[ ! -x "$TLAPS_PATH" ]]; then
        echo "  TLAPS not available for testing" >> "$tlaps_report"
        return 0
    fi
    
    local test_log="$DEBUG_DIR/logs/tlaps_test_${module}.log"
    
    # Generate proof obligations
    log_debug "Generating proof obligations for $module"
    if timeout 300 "$TLAPS_PATH" --cleanfp --nofp "$proof_file" > "$test_log" 2>&1; then
        local obligations
        obligations=$(grep -c "obligation" "$test_log" 2>/dev/null || echo "0")
        echo "  Generated $obligations obligations" >> "$tlaps_report"
        log_success "Generated $obligations proof obligations for $module"
    else
        echo "  Failed to generate obligations" >> "$tlaps_report"
        log_warning "Failed to generate proof obligations for $module"
        
        # Analyze TLAPS errors
        if grep -q "timeout" "$test_log"; then
            fix_suggestions["tlaps_timeout"]="Increase TLAPS timeout or simplify proofs in $module"
        elif grep -q "backend.*failed" "$test_log"; then
            fix_suggestions["tlaps_backend"]="Try different proof backends (zenon, ls4, smt) for $module"
        fi
    fi
}

# Log analysis
analyze_existing_logs() {
    log_highlight "Analyzing Existing Verification Logs"
    
    if [[ ! -d "$LOGS_DIR" ]]; then
        log_warning "Logs directory not found: $LOGS_DIR"
        component_status["logs"]="missing"
        return 0
    fi
    
    local log_analysis="$DEBUG_DIR/reports/log_analysis.txt"
    
    cat > "$log_analysis" << EOF
=== Log Analysis Report ===
Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Logs Directory: $LOGS_DIR

EOF
    
    # Find and analyze log files
    local log_files=()
    while IFS= read -r -d '' log_file; do
        log_files+=("$log_file")
    done < <(find "$LOGS_DIR" -name "*.log" -print0 2>/dev/null)
    
    if [[ ${#log_files[@]} -eq 0 ]]; then
        log_warning "No log files found in $LOGS_DIR"
        component_status["logs"]="empty"
        return 0
    fi
    
    log_info "Found ${#log_files[@]} log files"
    echo "Found ${#log_files[@]} log files:" >> "$log_analysis"
    
    # Analyze each log file
    for log_file in "${log_files[@]}"; do
        local log_name
        log_name=$(basename "$log_file")
        echo "" >> "$log_analysis"
        echo "=== $log_name ===" >> "$log_analysis"
        
        log_info "Analyzing log: $log_name"
        
        # Extract errors and warnings
        local errors
        errors=$(grep -i "error\|failed\|exception" "$log_file" 2>/dev/null | wc -l)
        local warnings
        warnings=$(grep -i "warning\|warn" "$log_file" 2>/dev/null | wc -l)
        
        echo "Errors: $errors" >> "$log_analysis"
        echo "Warnings: $warnings" >> "$log_analysis"
        
        if [[ $errors -gt 0 ]]; then
            echo "Error samples:" >> "$log_analysis"
            grep -i "error\|failed\|exception" "$log_file" 2>/dev/null | head -5 | sed 's/^/  /' >> "$log_analysis"
        fi
        
        # Look for specific patterns
        if grep -q "mismatched types" "$log_file" 2>/dev/null; then
            echo "  Pattern: Rust type mismatches detected" >> "$log_analysis"
            fix_suggestions["log_rust_types"]="Fix Rust type mismatches (likely BlockHash issues)"
        fi
        
        if grep -q "exit code 255" "$log_file" 2>/dev/null; then
            echo "  Pattern: TLC exit code 255 detected" >> "$log_analysis"
            fix_suggestions["log_tlc_255"]="TLC general error - check specifications and configurations"
        fi
        
        if grep -q "Java heap space" "$log_file" 2>/dev/null; then
            echo "  Pattern: Java memory issues detected" >> "$log_analysis"
            fix_suggestions["log_memory"]="Increase Java heap size for TLC"
        fi
    done
    
    log_success "Log analysis completed"
    component_status["logs"]="analyzed"
}

# Generate comprehensive diagnostic report
generate_diagnostic_report() {
    log_highlight "Generating Comprehensive Diagnostic Report"
    
    local main_report="$DEBUG_DIR/reports/diagnostic_summary.md"
    
    cat > "$main_report" << EOF
# Alpenglow Verification Diagnostic Report

**Generated:** $(date -u +"%Y-%m-%d %H:%M:%S UTC")  
**Script Version:** $SCRIPT_VERSION  
**Project Root:** $PROJECT_ROOT

## Executive Summary

This diagnostic report analyzes the Alpenglow verification system and identifies issues preventing successful verification.

## Component Status

| Component | Status | Issues Found |
|-----------|--------|--------------|
EOF
    
    # Add component status
    for component in environment rust tlc tlaps logs resources; do
        local status="${component_status[$component]:-not_checked}"
        local issues=""
        
        case "$status" in
            "available"|"compiles"|"passed"|"analyzed"|"checked")
                echo "| $component | ✅ OK | None |" >> "$main_report"
                ;;
            "missing"|"compilation_errors"|"failed"|"missing_specs"|"missing_proofs")
                echo "| $component | ❌ FAILED | Critical issues detected |" >> "$main_report"
                ;;
            "problematic"|"partial"|"missing_project")
                echo "| $component | ⚠️ WARNING | Minor issues detected |" >> "$main_report"
                ;;
            *)
                echo "| $component | ❓ UNKNOWN | Not checked |" >> "$main_report"
                ;;
        esac
    done
    
    cat >> "$main_report" << EOF

## Issues and Fixes

EOF
    
    # Add fix suggestions
    if [[ ${#fix_suggestions[@]} -gt 0 ]]; then
        echo "### Identified Issues" >> "$main_report"
        echo "" >> "$main_report"
        
        for issue in "${!fix_suggestions[@]}"; do
            echo "**$issue:**" >> "$main_report"
            echo "${fix_suggestions[$issue]}" >> "$main_report"
            echo "" >> "$main_report"
        done
    else
        echo "No specific issues identified." >> "$main_report"
        echo "" >> "$main_report"
    fi
    
    cat >> "$main_report" << EOF
## Performance Metrics

EOF
    
    # Add performance metrics
    if [[ ${#performance_metrics[@]} -gt 0 ]]; then
        for metric in "${!performance_metrics[@]}"; do
            echo "- **$metric:** ${performance_metrics[$metric]}" >> "$main_report"
        done
    else
        echo "No performance metrics collected." >> "$main_report"
    fi
    
    cat >> "$main_report" << EOF

## Generated Artifacts

- **Debug Directory:** $DEBUG_DIR
- **Detailed Reports:** $DEBUG_DIR/reports/
- **Fix Scripts:** $DEBUG_DIR/fixes/
- **Test Logs:** $DEBUG_DIR/logs/

## Next Steps

1. Review the component-specific reports in the reports/ directory
2. Execute any generated fix scripts in the fixes/ directory
3. Re-run the verification after applying fixes
4. Consult the troubleshooting guide for additional help

## Support

For additional support:
- Check the TroubleshootingGuide.md in the docs/ directory
- Review detailed logs in the debug_output/logs/ directory
- Run this script with --interactive for step-by-step guidance

---
*Generated by Alpenglow Verification Debugger v$SCRIPT_VERSION*
EOF
    
    log_success "Diagnostic report generated: $main_report"
}

# Interactive debugging mode
interactive_debugging() {
    log_highlight "Interactive Debugging Mode"
    
    echo ""
    echo "Welcome to the Alpenglow Verification Interactive Debugger!"
    echo "This mode will guide you through systematic troubleshooting."
    echo ""
    
    # Component selection
    echo "Which component would you like to debug?"
    echo "1) Environment (tools and dependencies)"
    echo "2) Rust compilation"
    echo "3) TLC model checking"
    echo "4) TLAPS proof verification"
    echo "5) Log analysis"
    echo "6) All components (recommended)"
    echo ""
    
    read -p "Enter your choice (1-6): " choice
    
    case "$choice" in
        1)
            debug_environment
            ;;
        2)
            debug_rust_compilation
            ;;
        3)
            debug_tlc_model_checking
            ;;
        4)
            debug_tlaps_proofs
            ;;
        5)
            analyze_existing_logs
            ;;
        6)
            debug_environment
            debug_rust_compilation
            debug_tlc_model_checking
            debug_tlaps_proofs
            analyze_existing_logs
            ;;
        *)
            log_error "Invalid choice. Running full diagnostic."
            debug_environment
            debug_rust_compilation
            debug_tlc_model_checking
            debug_tlaps_proofs
            analyze_existing_logs
            ;;
    esac
    
    echo ""
    echo "Interactive debugging completed!"
    echo "Check the generated reports and fix scripts in: $DEBUG_DIR"
}

# Main execution function
main() {
    local component="${1:-all}"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --interactive|-i)
                INTERACTIVE_MODE=true
                shift
                ;;
            --no-fixes)
                GENERATE_FIXES=false
                shift
                ;;
            --auto-apply-fixes)
                AUTO_APPLY_FIXES=true
                shift
                ;;
            --no-memory-check)
                MEMORY_CHECK=false
                shift
                ;;
            --detailed-analysis)
                DETAILED_ANALYSIS=true
                shift
                ;;
            --output-dir)
                DEBUG_DIR="$2"
                shift 2
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            environment|rust|tlc|tlaps|logs|all)
                component="$1"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Setup debug environment
    setup_debug_environment
    
    # Display header
    echo -e "${BOLD}${CYAN}"
    echo "=================================================================="
    echo "        Alpenglow Verification Debugger v$SCRIPT_VERSION"
    echo "=================================================================="
    echo -e "${NC}"
    echo "Debug Directory: $DEBUG_DIR"
    echo "Component: $component"
    echo "Verbose Mode: $VERBOSE"
    echo "Interactive Mode: $INTERACTIVE_MODE"
    echo ""
    
    # Run interactive mode if requested
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        interactive_debugging
        generate_diagnostic_report
        exit 0
    fi
    
    # Run system resource check if enabled
    if [[ "$MEMORY_CHECK" == "true" ]]; then
        check_system_resources
    fi
    
    # Execute debugging based on component
    case "$component" in
        environment)
            debug_environment
            ;;
        rust)
            debug_rust_compilation
            ;;
        tlc)
            debug_tlc_model_checking
            ;;
        tlaps)
            debug_tlaps_proofs
            ;;
        logs)
            analyze_existing_logs
            ;;
        all)
            debug_environment
            debug_rust_compilation
            debug_tlc_model_checking
            debug_tlaps_proofs
            analyze_existing_logs
            ;;
        *)
            log_error "Unknown component: $component"
            show_usage
            exit 1
            ;;
    esac
    
    # Generate comprehensive report
    generate_diagnostic_report
    
    # Final summary
    echo ""
    echo -e "${BOLD}${CYAN}=================================================================="
    echo "                    DEBUGGING COMPLETE"
    echo -e "==================================================================${NC}"
    echo ""
    echo "Debug Results: $DEBUG_DIR"
    echo "Main Report: $DEBUG_DIR/reports/diagnostic_summary.md"
    echo ""
    
    # Show fix suggestions
    if [[ ${#fix_suggestions[@]} -gt 0 ]]; then
        echo -e "${YELLOW}${WRENCH_MARK} Issues Found:${NC}"
        for issue in "${!fix_suggestions[@]}"; do
            echo -e "  ${LIGHTBULB_MARK} $issue: ${fix_suggestions[$issue]}"
        done
        echo ""
        echo -e "${GREEN}Check the fixes/ directory for automated repair scripts.${NC}"
    else
        echo -e "${GREEN}${CHECK_MARK} No critical issues detected!${NC}"
    fi
    
    echo ""
    echo "Next steps:"
    echo "1. Review the diagnostic report"
    echo "2. Apply suggested fixes"
    echo "3. Re-run verification"
    echo "4. Use --interactive mode for guided troubleshooting"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi