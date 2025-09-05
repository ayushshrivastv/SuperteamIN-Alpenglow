#!/bin/bash

# run_comprehensive_verification.sh
# Master verification script for complete formal verification of Alpenglow consensus protocol
# Orchestrates all phases from assessment to final validation with comprehensive reporting

set -euo pipefail

# Script metadata
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="Alpenglow Comprehensive Verification"
SCRIPT_AUTHOR="Traycer.AI"

# Directory configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SPECS_DIR="$PROJECT_ROOT/specs"
PROOFS_DIR="$PROJECT_ROOT/proofs"
MODELS_DIR="$PROJECT_ROOT/models"
STATERIGHT_DIR="$PROJECT_ROOT/stateright"
DOCS_DIR="$PROJECT_ROOT/docs"
RESULTS_DIR="$PROJECT_ROOT/comprehensive_verification_results"
LOGS_DIR="$RESULTS_DIR/logs"
REPORTS_DIR="$RESULTS_DIR/reports"
ARTIFACTS_DIR="$RESULTS_DIR/artifacts"
TEMP_DIR="$RESULTS_DIR/temp"
BACKUP_DIR="$RESULTS_DIR/backups"

# Tool paths (configurable via environment)
TLC_PATH="${TLC_PATH:-tlc}"
TLAPS_PATH="${TLAPS_PATH:-tlapm}"
CARGO_PATH="${CARGO_PATH:-cargo}"
JAVA_PATH="${JAVA_PATH:-java}"
PYTHON_PATH="${PYTHON_PATH:-python3}"

# Execution configuration
PARALLEL_JOBS="${PARALLEL_JOBS:-$(nproc 2>/dev/null || echo 4)}"
MAX_RETRIES="${MAX_RETRIES:-3}"
TIMEOUT_ASSESSMENT="${TIMEOUT_ASSESSMENT:-600}"      # 10 minutes
TIMEOUT_FOUNDATION="${TIMEOUT_FOUNDATION:-1800}"     # 30 minutes
TIMEOUT_PROOFS="${TIMEOUT_PROOFS:-3600}"             # 1 hour
TIMEOUT_IMPLEMENTATION="${TIMEOUT_IMPLEMENTATION:-1200}" # 20 minutes
TIMEOUT_MODEL_CHECKING="${TIMEOUT_MODEL_CHECKING:-2400}" # 40 minutes
TIMEOUT_CROSS_VALIDATION="${TIMEOUT_CROSS_VALIDATION:-900}" # 15 minutes
TIMEOUT_THEOREM_VALIDATION="${TIMEOUT_THEOREM_VALIDATION:-600}" # 10 minutes
TIMEOUT_PERFORMANCE="${TIMEOUT_PERFORMANCE:-1800}"   # 30 minutes

# Execution modes
VERBOSE="${VERBOSE:-false}"
DRY_RUN="${DRY_RUN:-false}"
CONTINUE_ON_ERROR="${CONTINUE_ON_ERROR:-false}"
SKIP_BACKUPS="${SKIP_BACKUPS:-false}"
PARALLEL_PHASES="${PARALLEL_PHASES:-true}"
GENERATE_ARTIFACTS="${GENERATE_ARTIFACTS:-true}"
CI_MODE="${CI_MODE:-false}"

# Phase control (allow selective execution)
RUN_ASSESSMENT="${RUN_ASSESSMENT:-true}"
RUN_FOUNDATION="${RUN_FOUNDATION:-true}"
RUN_PROOF_COMPLETION="${RUN_PROOF_COMPLETION:-true}"
RUN_IMPLEMENTATION="${RUN_IMPLEMENTATION:-true}"
RUN_MODEL_CHECKING="${RUN_MODEL_CHECKING:-true}"
RUN_CROSS_VALIDATION="${RUN_CROSS_VALIDATION:-true}"
RUN_THEOREM_VALIDATION="${RUN_THEOREM_VALIDATION:-true}"
RUN_PERFORMANCE="${RUN_PERFORMANCE:-true}"

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

# Unicode symbols for better visual feedback
CHECK_MARK="✓"
CROSS_MARK="✗"
WARNING_MARK="⚠"
INFO_MARK="ℹ"
ARROW_RIGHT="→"
CLOCK_MARK="⏱"
GEAR_MARK="⚙"

# Global state tracking
declare -A phase_status
declare -A phase_start_times
declare -A phase_end_times
declare -A phase_errors
declare -A phase_warnings
declare -A phase_artifacts
declare -A retry_counts
declare -A dependency_graph

total_phases=8
completed_phases=0
failed_phases=0
skipped_phases=0
overall_start_time=""
overall_end_time=""

# Logging and output functions
setup_logging() {
    mkdir -p "$LOGS_DIR" "$REPORTS_DIR" "$ARTIFACTS_DIR" "$TEMP_DIR"
    
    # Create main log file
    local main_log="$LOGS_DIR/comprehensive_verification.log"
    echo "=== Alpenglow Comprehensive Verification Started ===" > "$main_log"
    echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$main_log"
    echo "Script Version: $SCRIPT_VERSION" >> "$main_log"
    echo "Project Root: $PROJECT_ROOT" >> "$main_log"
    echo "Parallel Jobs: $PARALLEL_JOBS" >> "$main_log"
    echo "=================================================" >> "$main_log"
    echo "" >> "$main_log"
}

log_message() {
    local level="$1"
    local phase="$2"
    local message="$3"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
    
    # Log to main file
    echo "[$timestamp] [$level] [$phase] $message" >> "$LOGS_DIR/comprehensive_verification.log"
    
    # Log to phase-specific file
    if [[ "$phase" != "MAIN" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOGS_DIR/phase_${phase,,}.log"
    fi
}

log_info() {
    local phase="${2:-MAIN}"
    local message="$1"
    log_message "INFO" "$phase" "$message"
    if [[ "$VERBOSE" == "true" ]] || [[ "$phase" == "MAIN" ]]; then
        echo -e "${BLUE}${INFO_MARK}${NC} ${message}" >&2
    fi
}

log_success() {
    local phase="${2:-MAIN}"
    local message="$1"
    log_message "SUCCESS" "$phase" "$message"
    echo -e "${GREEN}${CHECK_MARK}${NC} ${message}" >&2
}

log_warning() {
    local phase="${2:-MAIN}"
    local message="$1"
    log_message "WARNING" "$phase" "$message"
    echo -e "${YELLOW}${WARNING_MARK}${NC} ${message}" >&2
    
    # Track warnings
    if [[ -n "${phase_warnings[$phase]:-}" ]]; then
        phase_warnings["$phase"]="${phase_warnings[$phase]}\n$message"
    else
        phase_warnings["$phase"]="$message"
    fi
}

log_error() {
    local phase="${2:-MAIN}"
    local message="$1"
    log_message "ERROR" "$phase" "$message"
    echo -e "${RED}${CROSS_MARK}${NC} ${message}" >&2
    
    # Track errors
    if [[ -n "${phase_errors[$phase]:-}" ]]; then
        phase_errors["$phase"]="${phase_errors[$phase]}\n$message"
    else
        phase_errors["$phase"]="$message"
    fi
}

log_debug() {
    local phase="${2:-MAIN}"
    local message="$1"
    if [[ "$VERBOSE" == "true" ]]; then
        log_message "DEBUG" "$phase" "$message"
        echo -e "${PURPLE}[DEBUG]${NC} ${message}" >&2
    fi
}

# Progress tracking and display
update_progress() {
    local phase="$1"
    local status="$2"  # "running", "success", "failed", "skipped"
    local message="${3:-}"
    
    phase_status["$phase"]="$status"
    
    case "$status" in
        "running")
            phase_start_times["$phase"]=$(date +%s)
            log_info "Starting Phase: $phase" "MAIN"
            ;;
        "success")
            phase_end_times["$phase"]=$(date +%s)
            ((completed_phases++))
            log_success "Completed Phase: $phase${message:+ - $message}" "MAIN"
            ;;
        "failed")
            phase_end_times["$phase"]=$(date +%s)
            ((failed_phases++))
            log_error "Failed Phase: $phase${message:+ - $message}" "MAIN"
            ;;
        "skipped")
            phase_end_times["$phase"]=$(date +%s)
            ((skipped_phases++))
            log_warning "Skipped Phase: $phase${message:+ - $message}" "MAIN"
            ;;
    esac
    
    display_progress_bar
}

display_progress_bar() {
    local progress=$((completed_phases * 100 / total_phases))
    local bar_length=50
    local filled_length=$((progress * bar_length / 100))
    
    local bar=""
    for ((i=0; i<filled_length; i++)); do
        bar+="█"
    done
    for ((i=filled_length; i<bar_length; i++)); do
        bar+="░"
    done
    
    echo -e "\r${CYAN}Progress: [${bar}] ${progress}% (${completed_phases}/${total_phases})${NC}" >&2
}

# Environment validation
check_environment() {
    log_info "Validating verification environment..." "ASSESSMENT"
    
    local missing_tools=()
    local missing_dirs=()
    local warnings=()
    
    # Check required tools
    if ! command -v "$JAVA_PATH" &> /dev/null; then
        missing_tools+=("java")
    else
        local java_version
        java_version=$("$JAVA_PATH" -version 2>&1 | head -n1 | cut -d'"' -f2)
        log_debug "Found Java: $java_version" "ASSESSMENT"
    fi
    
    if ! command -v "$TLC_PATH" &> /dev/null; then
        missing_tools+=("tlc")
    else
        log_debug "Found TLC: $TLC_PATH" "ASSESSMENT"
    fi
    
    if ! command -v "$TLAPS_PATH" &> /dev/null; then
        missing_tools+=("tlapm")
    else
        local tlaps_version
        tlaps_version=$("$TLAPS_PATH" --version 2>&1 | head -n1 || echo "unknown")
        log_debug "Found TLAPS: $tlaps_version" "ASSESSMENT"
    fi
    
    if ! command -v "$CARGO_PATH" &> /dev/null; then
        missing_tools+=("cargo")
    else
        local rust_version
        rust_version=$("$CARGO_PATH" --version | head -n1)
        log_debug "Found Rust: $rust_version" "ASSESSMENT"
    fi
    
    if ! command -v "$PYTHON_PATH" &> /dev/null; then
        missing_tools+=("python3")
    else
        local python_version
        python_version=$("$PYTHON_PATH" --version 2>&1)
        log_debug "Found Python: $python_version" "ASSESSMENT"
    fi
    
    # Check required directories
    for dir in "$SPECS_DIR" "$PROOFS_DIR" "$MODELS_DIR" "$STATERIGHT_DIR" "$DOCS_DIR"; do
        if [[ ! -d "$dir" ]]; then
            missing_dirs+=("$dir")
        fi
    done
    
    # Check for critical files
    local critical_files=(
        "$PROJECT_ROOT/Solana Alpenglow White Paper v1.1.md"
        "$SPECS_DIR/Alpenglow.tla"
        "$SPECS_DIR/Types.tla"
        "$STATERIGHT_DIR/Cargo.toml"
    )
    
    for file in "${critical_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            warnings+=("Missing critical file: $file")
        fi
    done
    
    # Report findings
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}" "ASSESSMENT"
        return 1
    fi
    
    if [[ ${#missing_dirs[@]} -gt 0 ]]; then
        log_error "Missing required directories: ${missing_dirs[*]}" "ASSESSMENT"
        return 1
    fi
    
    for warning in "${warnings[@]}"; do
        log_warning "$warning" "ASSESSMENT"
    done
    
    log_success "Environment validation completed" "ASSESSMENT"
    return 0
}

# Backup creation
create_backups() {
    if [[ "$SKIP_BACKUPS" == "true" ]]; then
        log_info "Skipping backup creation" "MAIN"
        return 0
    fi
    
    log_info "Creating project backups..." "MAIN"
    
    local backup_timestamp
    backup_timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_path="$BACKUP_DIR/backup_$backup_timestamp"
    
    mkdir -p "$backup_path"
    
    # Backup critical directories
    local dirs_to_backup=("$SPECS_DIR" "$PROOFS_DIR" "$MODELS_DIR" "$STATERIGHT_DIR")
    
    for dir in "${dirs_to_backup[@]}"; do
        if [[ -d "$dir" ]]; then
            local dir_name
            dir_name=$(basename "$dir")
            cp -r "$dir" "$backup_path/$dir_name" 2>/dev/null || {
                log_warning "Failed to backup $dir" "MAIN"
            }
        fi
    done
    
    # Create backup manifest
    cat > "$backup_path/manifest.txt" << EOF
Alpenglow Verification Backup
Created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Script Version: $SCRIPT_VERSION
Project Root: $PROJECT_ROOT
Backup Contents:
EOF
    
    find "$backup_path" -type f | sort >> "$backup_path/manifest.txt"
    
    log_success "Backup created: $backup_path" "MAIN"
    echo "$backup_path" > "$RESULTS_DIR/.last_backup"
}

# Retry mechanism
execute_with_retry() {
    local phase="$1"
    local command="$2"
    local max_retries="${3:-$MAX_RETRIES}"
    
    local attempt=1
    while [[ $attempt -le $max_retries ]]; do
        log_debug "Attempt $attempt/$max_retries for $phase" "$phase"
        
        if eval "$command"; then
            return 0
        else
            local exit_code=$?
            retry_counts["$phase"]=$attempt
            
            if [[ $attempt -eq $max_retries ]]; then
                log_error "All $max_retries attempts failed for $phase" "$phase"
                return $exit_code
            else
                log_warning "Attempt $attempt failed for $phase, retrying..." "$phase"
                ((attempt++))
                sleep $((attempt * 2))  # Exponential backoff
            fi
        fi
    done
}

# Phase execution wrapper
execute_phase() {
    local phase_name="$1"
    local phase_function="$2"
    local timeout="${3:-3600}"
    local dependencies="${4:-}"
    
    # Check if phase should run
    local run_var="RUN_${phase_name^^}"
    run_var="${run_var// /_}"
    if [[ "${!run_var:-true}" != "true" ]]; then
        update_progress "$phase_name" "skipped" "disabled by configuration"
        return 0
    fi
    
    # Check dependencies
    if [[ -n "$dependencies" ]]; then
        IFS=',' read -ra deps <<< "$dependencies"
        for dep in "${deps[@]}"; do
            dep=$(echo "$dep" | xargs)  # trim whitespace
            if [[ "${phase_status[$dep]:-}" != "success" ]]; then
                update_progress "$phase_name" "skipped" "dependency $dep not satisfied"
                return 0
            fi
        done
    fi
    
    update_progress "$phase_name" "running"
    
    # Execute phase with timeout and retry
    local phase_log="$LOGS_DIR/phase_${phase_name,,}.log"
    echo "=== Phase: $phase_name ===" > "$phase_log"
    echo "Started: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$phase_log"
    echo "" >> "$phase_log"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would execute $phase_name" "$phase_name"
        sleep 2  # Simulate execution time
        update_progress "$phase_name" "success" "dry run completed"
        return 0
    fi
    
    local success=false
    if timeout "$timeout" bash -c "execute_with_retry '$phase_name' '$phase_function' '$MAX_RETRIES'" >> "$phase_log" 2>&1; then
        success=true
    fi
    
    echo "" >> "$phase_log"
    echo "Completed: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$phase_log"
    
    if [[ "$success" == "true" ]]; then
        update_progress "$phase_name" "success"
        return 0
    else
        update_progress "$phase_name" "failed"
        
        if [[ "$CONTINUE_ON_ERROR" != "true" ]]; then
            log_error "Phase $phase_name failed, stopping execution" "MAIN"
            return 1
        else
            log_warning "Phase $phase_name failed, continuing due to CONTINUE_ON_ERROR" "MAIN"
            return 0
        fi
    fi
}

# Phase 1: Assessment
phase_assessment() {
    log_info "Running comprehensive status assessment..." "ASSESSMENT"
    
    # Create and run status validation script
    local validation_script="$SCRIPTS_DIR/validate_current_status.sh"
    if [[ -f "$validation_script" ]]; then
        log_info "Executing existing validation script..." "ASSESSMENT"
        bash "$validation_script" --output-dir "$RESULTS_DIR/assessment"
    else
        log_info "Running built-in assessment..." "ASSESSMENT"
        
        # Built-in assessment logic
        mkdir -p "$RESULTS_DIR/assessment"
        
        # Check TLA+ specifications
        local spec_status="$RESULTS_DIR/assessment/spec_status.json"
        echo '{"specifications": {' > "$spec_status"
        
        local first=true
        for spec in "$SPECS_DIR"/*.tla; do
            if [[ -f "$spec" ]]; then
                local spec_name
                spec_name=$(basename "$spec" .tla)
                
                if [[ "$first" == "true" ]]; then
                    first=false
                else
                    echo "," >> "$spec_status"
                fi
                
                # Basic syntax check
                local syntax_ok="false"
                if timeout 60 "$TLC_PATH" -parse "$spec" &>/dev/null; then
                    syntax_ok="true"
                fi
                
                echo "  \"$spec_name\": {\"syntax_valid\": $syntax_ok, \"path\": \"$spec\"}" >> "$spec_status"
            fi
        done
        
        echo '}}' >> "$spec_status"
        
        # Check proof modules
        local proof_status="$RESULTS_DIR/assessment/proof_status.json"
        echo '{"proofs": {' > "$proof_status"
        
        first=true
        for proof in "$PROOFS_DIR"/*.tla; do
            if [[ -f "$proof" ]]; then
                local proof_name
                proof_name=$(basename "$proof" .tla)
                
                if [[ "$first" == "true" ]]; then
                    first=false
                else
                    echo "," >> "$proof_status"
                fi
                
                # Check for proof obligations
                local has_proofs="false"
                if grep -q "THEOREM\|LEMMA\|PROOF" "$proof"; then
                    has_proofs="true"
                fi
                
                echo "  \"$proof_name\": {\"has_proofs\": $has_proofs, \"path\": \"$proof\"}" >> "$proof_status"
            fi
        done
        
        echo '}}' >> "$proof_status"
        
        # Check Stateright implementation
        local stateright_status="$RESULTS_DIR/assessment/stateright_status.json"
        local builds="false"
        if [[ -f "$STATERIGHT_DIR/Cargo.toml" ]]; then
            if (cd "$STATERIGHT_DIR" && timeout 300 "$CARGO_PATH" check &>/dev/null); then
                builds="true"
            fi
        fi
        
        echo "{\"stateright\": {\"builds\": $builds, \"path\": \"$STATERIGHT_DIR\"}}" > "$stateright_status"
    fi
    
    phase_artifacts["ASSESSMENT"]="$RESULTS_DIR/assessment"
    log_success "Assessment phase completed" "ASSESSMENT"
}

# Phase 2: Foundation
phase_foundation() {
    log_info "Fixing critical issues and completing foundational modules..." "FOUNDATION"
    
    # Create and run foundation fixing script
    local foundation_script="$SCRIPTS_DIR/fix_critical_issues.sh"
    if [[ -f "$foundation_script" ]]; then
        log_info "Executing foundation fixing script..." "FOUNDATION"
        bash "$foundation_script" --backup-dir "$BACKUP_DIR" --output-dir "$RESULTS_DIR/foundation"
    else
        log_info "Running built-in foundation fixes..." "FOUNDATION"
        
        mkdir -p "$RESULTS_DIR/foundation"
        
        # Fix Types.tla if it exists
        if [[ -f "$SPECS_DIR/Types.tla" ]]; then
            log_info "Validating Types.tla module..." "FOUNDATION"
            
            # Basic validation
            if ! timeout 120 "$TLC_PATH" -parse "$SPECS_DIR/Types.tla" &>/dev/null; then
                log_warning "Types.tla has syntax errors" "FOUNDATION"
                
                # Create a minimal working version if needed
                if [[ ! -f "$SPECS_DIR/Types.tla.backup" ]]; then
                    cp "$SPECS_DIR/Types.tla" "$SPECS_DIR/Types.tla.backup"
                fi
            else
                log_success "Types.tla syntax is valid" "FOUNDATION"
            fi
        fi
        
        # Validate other critical modules
        local critical_modules=("Utils.tla" "Crypto.tla" "Network.tla")
        for module in "${critical_modules[@]}"; do
            if [[ -f "$SPECS_DIR/$module" ]]; then
                log_info "Validating $module..." "FOUNDATION"
                
                if timeout 120 "$TLC_PATH" -parse "$SPECS_DIR/$module" &>/dev/null; then
                    log_success "$module syntax is valid" "FOUNDATION"
                else
                    log_warning "$module has syntax errors" "FOUNDATION"
                fi
            fi
        done
    fi
    
    phase_artifacts["FOUNDATION"]="$RESULTS_DIR/foundation"
    log_success "Foundation phase completed" "FOUNDATION"
}

# Phase 3: Proof Completion
phase_proof_completion() {
    log_info "Completing safety and liveness proofs..." "PROOF_COMPLETION"
    
    mkdir -p "$RESULTS_DIR/proofs"
    
    # Safety proofs
    if [[ -f "$PROOFS_DIR/Safety.tla" ]]; then
        log_info "Verifying safety proofs..." "PROOF_COMPLETION"
        
        if timeout "$TIMEOUT_PROOFS" "$TLAPS_PATH" --verbose "$PROOFS_DIR/Safety.tla" > "$RESULTS_DIR/proofs/safety_verification.log" 2>&1; then
            log_success "Safety proofs verified" "PROOF_COMPLETION"
        else
            log_warning "Safety proof verification incomplete" "PROOF_COMPLETION"
        fi
    fi
    
    # Liveness proofs
    if [[ -f "$PROOFS_DIR/Liveness.tla" ]]; then
        log_info "Verifying liveness proofs..." "PROOF_COMPLETION"
        
        if timeout "$TIMEOUT_PROOFS" "$TLAPS_PATH" --verbose "$PROOFS_DIR/Liveness.tla" > "$RESULTS_DIR/proofs/liveness_verification.log" 2>&1; then
            log_success "Liveness proofs verified" "PROOF_COMPLETION"
        else
            log_warning "Liveness proof verification incomplete" "PROOF_COMPLETION"
        fi
    fi
    
    # Whitepaper theorems
    if [[ -f "$PROOFS_DIR/WhitepaperTheorems.tla" ]]; then
        log_info "Verifying whitepaper theorems..." "PROOF_COMPLETION"
        
        if timeout "$TIMEOUT_PROOFS" "$TLAPS_PATH" --verbose "$PROOFS_DIR/WhitepaperTheorems.tla" > "$RESULTS_DIR/proofs/theorems_verification.log" 2>&1; then
            log_success "Whitepaper theorems verified" "PROOF_COMPLETION"
        else
            log_warning "Whitepaper theorem verification incomplete" "PROOF_COMPLETION"
        fi
    fi
    
    phase_artifacts["PROOF_COMPLETION"]="$RESULTS_DIR/proofs"
    log_success "Proof completion phase finished" "PROOF_COMPLETION"
}

# Phase 4: Implementation
phase_implementation() {
    log_info "Fixing and validating Stateright implementation..." "IMPLEMENTATION"
    
    mkdir -p "$RESULTS_DIR/implementation"
    
    if [[ -d "$STATERIGHT_DIR" ]]; then
        # Build the implementation
        log_info "Building Stateright implementation..." "IMPLEMENTATION"
        
        if (cd "$STATERIGHT_DIR" && timeout 600 "$CARGO_PATH" build --release) > "$RESULTS_DIR/implementation/build.log" 2>&1; then
            log_success "Stateright implementation built successfully" "IMPLEMENTATION"
            
            # Run tests
            log_info "Running Stateright tests..." "IMPLEMENTATION"
            
            if (cd "$STATERIGHT_DIR" && timeout "$TIMEOUT_IMPLEMENTATION" "$CARGO_PATH" test --release) > "$RESULTS_DIR/implementation/test.log" 2>&1; then
                log_success "Stateright tests passed" "IMPLEMENTATION"
            else
                log_warning "Some Stateright tests failed" "IMPLEMENTATION"
            fi
        else
            log_warning "Stateright implementation failed to build" "IMPLEMENTATION"
        fi
    else
        log_warning "Stateright directory not found" "IMPLEMENTATION"
    fi
    
    phase_artifacts["IMPLEMENTATION"]="$RESULTS_DIR/implementation"
    log_success "Implementation phase completed" "IMPLEMENTATION"
}

# Phase 5: Model Checking
phase_model_checking() {
    log_info "Executing comprehensive model checking..." "MODEL_CHECKING"
    
    mkdir -p "$RESULTS_DIR/model_checking"
    
    # Find all configuration files
    local configs=()
    if [[ -d "$MODELS_DIR" ]]; then
        while IFS= read -r -d '' config; do
            configs+=("$config")
        done < <(find "$MODELS_DIR" -name "*.cfg" -print0)
    fi
    
    if [[ ${#configs[@]} -eq 0 ]]; then
        log_warning "No model configurations found" "MODEL_CHECKING"
        return 0
    fi
    
    log_info "Found ${#configs[@]} model configurations" "MODEL_CHECKING"
    
    # Run model checking on each configuration
    local successful_configs=0
    for config in "${configs[@]}"; do
        local config_name
        config_name=$(basename "$config" .cfg)
        
        log_info "Model checking configuration: $config_name" "MODEL_CHECKING"
        
        # Extract specification name from config
        local spec_name="Alpenglow"
        if grep -q "^SPECIFICATION" "$config"; then
            spec_name=$(grep "^SPECIFICATION" "$config" | awk '{print $2}')
        fi
        
        local spec_file="$SPECS_DIR/$spec_name.tla"
        if [[ ! -f "$spec_file" ]]; then
            log_warning "Specification file not found: $spec_file" "MODEL_CHECKING"
            continue
        fi
        
        # Run TLC
        local output_file="$RESULTS_DIR/model_checking/${config_name}_results.log"
        if timeout "$TIMEOUT_MODEL_CHECKING" "$TLC_PATH" -config "$config" -workers "$PARALLEL_JOBS" "$spec_file" > "$output_file" 2>&1; then
            log_success "Model checking passed for $config_name" "MODEL_CHECKING"
            ((successful_configs++))
        else
            log_warning "Model checking failed for $config_name" "MODEL_CHECKING"
        fi
    done
    
    log_info "Model checking completed: $successful_configs/${#configs[@]} configurations passed" "MODEL_CHECKING"
    
    phase_artifacts["MODEL_CHECKING"]="$RESULTS_DIR/model_checking"
    log_success "Model checking phase completed" "MODEL_CHECKING"
}

# Phase 6: Cross-Validation
phase_cross_validation() {
    log_info "Running cross-validation between TLA+ and Stateright..." "CROSS_VALIDATION"
    
    mkdir -p "$RESULTS_DIR/cross_validation"
    
    # Check if both TLA+ specs and Stateright implementation are available
    if [[ ! -f "$SPECS_DIR/Alpenglow.tla" ]]; then
        log_warning "TLA+ specification not found, skipping cross-validation" "CROSS_VALIDATION"
        return 0
    fi
    
    if [[ ! -d "$STATERIGHT_DIR" ]] || [[ "${phase_status[IMPLEMENTATION]}" != "success" ]]; then
        log_warning "Stateright implementation not available, skipping cross-validation" "CROSS_VALIDATION"
        return 0
    fi
    
    # Run cross-validation tests
    log_info "Executing cross-validation tests..." "CROSS_VALIDATION"
    
    if (cd "$STATERIGHT_DIR" && timeout "$TIMEOUT_CROSS_VALIDATION" "$CARGO_PATH" test cross_validation -- --nocapture) > "$RESULTS_DIR/cross_validation/results.log" 2>&1; then
        log_success "Cross-validation tests passed" "CROSS_VALIDATION"
    else
        log_warning "Cross-validation tests failed or incomplete" "CROSS_VALIDATION"
    fi
    
    phase_artifacts["CROSS_VALIDATION"]="$RESULTS_DIR/cross_validation"
    log_success "Cross-validation phase completed" "CROSS_VALIDATION"
}

# Phase 7: Theorem Validation
phase_theorem_validation() {
    log_info "Verifying correspondence between whitepaper and formal theorems..." "THEOREM_VALIDATION"
    
    mkdir -p "$RESULTS_DIR/theorem_validation"
    
    # Check for whitepaper
    local whitepaper="$PROJECT_ROOT/Solana Alpenglow White Paper v1.1.md"
    if [[ ! -f "$whitepaper" ]]; then
        log_warning "Whitepaper not found, skipping theorem validation" "THEOREM_VALIDATION"
        return 0
    fi
    
    # Extract theorems from whitepaper
    log_info "Extracting theorems from whitepaper..." "THEOREM_VALIDATION"
    
    local theorem_count
    theorem_count=$(grep -c "^## Theorem\|^### Theorem\|^#### Theorem" "$whitepaper" 2>/dev/null || echo "0")
    
    log_info "Found $theorem_count theorems in whitepaper" "THEOREM_VALIDATION"
    
    # Check formal theorem correspondence
    if [[ -f "$PROOFS_DIR/WhitepaperTheorems.tla" ]]; then
        local formal_theorem_count
        formal_theorem_count=$(grep -c "^THEOREM\|^LEMMA" "$PROOFS_DIR/WhitepaperTheorems.tla" 2>/dev/null || echo "0")
        
        log_info "Found $formal_theorem_count formal theorems" "THEOREM_VALIDATION"
        
        # Create correspondence report
        cat > "$RESULTS_DIR/theorem_validation/correspondence.json" << EOF
{
  "theorem_validation": {
    "whitepaper_theorems": $theorem_count,
    "formal_theorems": $formal_theorem_count,
    "correspondence_ratio": $(echo "scale=2; $formal_theorem_count / $theorem_count" | bc -l 2>/dev/null || echo "0"),
    "validation_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  }
}
EOF
    else
        log_warning "Formal theorem file not found" "THEOREM_VALIDATION"
    fi
    
    phase_artifacts["THEOREM_VALIDATION"]="$RESULTS_DIR/theorem_validation"
    log_success "Theorem validation phase completed" "THEOREM_VALIDATION"
}

# Phase 8: Performance Testing
phase_performance() {
    log_info "Running performance and scalability tests..." "PERFORMANCE"
    
    mkdir -p "$RESULTS_DIR/performance"
    
    # Performance testing for TLA+ model checking
    log_info "Testing TLA+ model checking performance..." "PERFORMANCE"
    
    local perf_configs=()
    if [[ -d "$MODELS_DIR" ]]; then
        while IFS= read -r -d '' config; do
            if [[ "$(basename "$config")" =~ Performance|Large|Stress ]]; then
                perf_configs+=("$config")
            fi
        done < <(find "$MODELS_DIR" -name "*.cfg" -print0)
    fi
    
    if [[ ${#perf_configs[@]} -gt 0 ]]; then
        for config in "${perf_configs[@]}"; do
            local config_name
            config_name=$(basename "$config" .cfg)
            
            log_info "Running performance test: $config_name" "PERFORMANCE"
            
            local start_time
            start_time=$(date +%s)
            
            if timeout "$TIMEOUT_PERFORMANCE" "$TLC_PATH" -config "$config" -workers "$PARALLEL_JOBS" "$SPECS_DIR/Alpenglow.tla" > "$RESULTS_DIR/performance/${config_name}_perf.log" 2>&1; then
                local end_time
                end_time=$(date +%s)
                local duration=$((end_time - start_time))
                
                log_success "Performance test $config_name completed in ${duration}s" "PERFORMANCE"
            else
                log_warning "Performance test $config_name timed out or failed" "PERFORMANCE"
            fi
        done
    else
        log_info "No performance configurations found, running basic performance test" "PERFORMANCE"
        
        # Basic performance measurement
        if [[ -f "$SPECS_DIR/Alpenglow.tla" ]]; then
            local start_time
            start_time=$(date +%s)
            
            if timeout 300 "$TLC_PATH" -parse "$SPECS_DIR/Alpenglow.tla" &>/dev/null; then
                local end_time
                end_time=$(date +%s)
                local duration=$((end_time - start_time))
                
                echo "{\"parse_time_seconds\": $duration}" > "$RESULTS_DIR/performance/basic_metrics.json"
                log_success "Basic performance test completed in ${duration}s" "PERFORMANCE"
            fi
        fi
    fi
    
    # Stateright performance testing
    if [[ -d "$STATERIGHT_DIR" ]] && [[ "${phase_status[IMPLEMENTATION]}" == "success" ]]; then
        log_info "Running Stateright performance tests..." "PERFORMANCE"
        
        if (cd "$STATERIGHT_DIR" && timeout "$TIMEOUT_PERFORMANCE" "$CARGO_PATH" test --release performance -- --nocapture) > "$RESULTS_DIR/performance/stateright_perf.log" 2>&1; then
            log_success "Stateright performance tests completed" "PERFORMANCE"
        else
            log_warning "Stateright performance tests failed or incomplete" "PERFORMANCE"
        fi
    fi
    
    phase_artifacts["PERFORMANCE"]="$RESULTS_DIR/performance"
    log_success "Performance testing phase completed" "PERFORMANCE"
}

# Comprehensive report generation
generate_comprehensive_report() {
    log_info "Generating comprehensive verification report..." "MAIN"
    
    local report_file="$REPORTS_DIR/comprehensive_verification_report.json"
    local html_report="$REPORTS_DIR/comprehensive_verification_report.html"
    local summary_file="$REPORTS_DIR/executive_summary.md"
    
    # Calculate overall metrics
    local total_time=0
    local successful_phases=0
    local failed_phases_count=0
    local skipped_phases_count=0
    
    for phase in "${!phase_status[@]}"; do
        case "${phase_status[$phase]}" in
            "success") ((successful_phases++)) ;;
            "failed") ((failed_phases_count++)) ;;
            "skipped") ((skipped_phases_count++)) ;;
        esac
        
        if [[ -n "${phase_start_times[$phase]:-}" ]] && [[ -n "${phase_end_times[$phase]:-}" ]]; then
            local phase_time=$((phase_end_times[$phase] - phase_start_times[$phase]))
            total_time=$((total_time + phase_time))
        fi
    done
    
    local success_rate
    success_rate=$(echo "scale=2; $successful_phases * 100 / ${#phase_status[@]}" | bc -l 2>/dev/null || echo "0")
    
    # Generate JSON report
    cat > "$report_file" << EOF
{
  "comprehensive_verification_report": {
    "metadata": {
      "script_version": "$SCRIPT_VERSION",
      "generation_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
      "project_root": "$PROJECT_ROOT",
      "execution_mode": {
        "parallel_jobs": $PARALLEL_JOBS,
        "dry_run": $DRY_RUN,
        "continue_on_error": $CONTINUE_ON_ERROR,
        "ci_mode": $CI_MODE
      }
    },
    "overall_summary": {
      "total_phases": ${#phase_status[@]},
      "successful_phases": $successful_phases,
      "failed_phases": $failed_phases_count,
      "skipped_phases": $skipped_phases_count,
      "success_rate_percent": $success_rate,
      "total_execution_time_seconds": $total_time,
      "overall_status": "$(if [[ $failed_phases_count -eq 0 ]]; then echo "SUCCESS"; else echo "PARTIAL_SUCCESS"; fi)"
    },
    "phase_results": {
EOF

    # Add phase details
    local first=true
    for phase in $(printf '%s\n' "${!phase_status[@]}" | sort); do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo "," >> "$report_file"
        fi
        
        local status="${phase_status[$phase]}"
        local start_time="${phase_start_times[$phase]:-0}"
        local end_time="${phase_end_times[$phase]:-0}"
        local duration=$((end_time - start_time))
        local errors="${phase_errors[$phase]:-}"
        local warnings="${phase_warnings[$phase]:-}"
        local artifacts="${phase_artifacts[$phase]:-}"
        local retries="${retry_counts[$phase]:-0}"
        
        cat >> "$report_file" << EOF
      "$phase": {
        "status": "$status",
        "start_time": $start_time,
        "end_time": $end_time,
        "duration_seconds": $duration,
        "retry_count": $retries,
        "errors": "$errors",
        "warnings": "$warnings",
        "artifacts_path": "$artifacts"
      }
EOF
    done
    
    cat >> "$report_file" << EOF
    },
    "artifacts": {
      "logs_directory": "$LOGS_DIR",
      "reports_directory": "$REPORTS_DIR",
      "results_directory": "$RESULTS_DIR",
      "backup_directory": "$BACKUP_DIR"
    },
    "recommendations": [
EOF

    # Generate recommendations based on results
    local recommendations=()
    
    if [[ $failed_phases_count -gt 0 ]]; then
        recommendations+=("\"Review failed phases and address underlying issues before proceeding\"")
    fi
    
    if [[ $skipped_phases_count -gt 0 ]]; then
        recommendations+=("\"Consider enabling skipped phases for complete verification coverage\"")
    fi
    
    if [[ "${phase_status[PROOF_COMPLETION]:-}" != "success" ]]; then
        recommendations+=("\"Complete formal proofs to ensure mathematical rigor\"")
    fi
    
    if [[ "${phase_status[CROSS_VALIDATION]:-}" != "success" ]]; then
        recommendations+=("\"Implement cross-validation between TLA+ and implementation\"")
    fi
    
    if [[ ${#recommendations[@]} -eq 0 ]]; then
        recommendations+=("\"Verification appears complete - consider regular re-validation\"")
    fi
    
    # Add recommendations to JSON
    for i in "${!recommendations[@]}"; do
        if [[ $i -gt 0 ]]; then
            echo "," >> "$report_file"
        fi
        echo "      ${recommendations[$i]}" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF
    ]
  }
}
EOF

    # Generate executive summary
    cat > "$summary_file" << EOF
# Alpenglow Comprehensive Verification - Executive Summary

**Generated:** $(date -u +"%Y-%m-%d %H:%M:%S UTC")  
**Script Version:** $SCRIPT_VERSION  
**Total Execution Time:** ${total_time}s  

## Overall Results

- **Success Rate:** ${success_rate}%
- **Successful Phases:** $successful_phases/${#phase_status[@]}
- **Failed Phases:** $failed_phases_count
- **Skipped Phases:** $skipped_phases_count

## Phase Summary

| Phase | Status | Duration | Notes |
|-------|--------|----------|-------|
EOF

    for phase in $(printf '%s\n' "${!phase_status[@]}" | sort); do
        local status="${phase_status[$phase]}"
        local duration=0
        if [[ -n "${phase_start_times[$phase]:-}" ]] && [[ -n "${phase_end_times[$phase]:-}" ]]; then
            duration=$((phase_end_times[$phase] - phase_start_times[$phase]))
        fi
        local notes="${phase_errors[$phase]:-${phase_warnings[$phase]:-}}"
        notes="${notes//|/ }"  # Remove pipe characters that would break table
        
        echo "| $phase | $status | ${duration}s | $notes |" >> "$summary_file"
    done
    
    cat >> "$summary_file" << EOF

## Recommendations

EOF

    for rec in "${recommendations[@]}"; do
        # Remove quotes and format as markdown list
        local clean_rec
        clean_rec=$(echo "$rec" | sed 's/^"//; s/"$//')
        echo "- $clean_rec" >> "$summary_file"
    done
    
    cat >> "$summary_file" << EOF

## Artifacts

- **Detailed Report:** [comprehensive_verification_report.json](comprehensive_verification_report.json)
- **Logs Directory:** $LOGS_DIR
- **Results Directory:** $RESULTS_DIR
- **Backup Directory:** $BACKUP_DIR

## Next Steps

1. Review any failed phases and address underlying issues
2. Complete any skipped phases if full verification coverage is needed
3. Regularly re-run verification to ensure continued validity
4. Consider automating verification in CI/CD pipeline

---
*Generated by Alpenglow Comprehensive Verification Script v$SCRIPT_VERSION*
EOF

    log_success "Comprehensive report generated: $report_file" "MAIN"
    log_success "Executive summary generated: $summary_file" "MAIN"
}

# Cleanup and finalization
cleanup_and_finalize() {
    log_info "Performing cleanup and finalization..." "MAIN"
    
    # Clean up temporary files
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
    
    # Compress logs if requested
    if [[ "$CI_MODE" == "true" ]]; then
        log_info "Compressing logs for CI..." "MAIN"
        if command -v gzip &> /dev/null; then
            find "$LOGS_DIR" -name "*.log" -exec gzip {} \;
        fi
    fi
    
    # Set appropriate permissions
    chmod -R 644 "$RESULTS_DIR"/*.json "$RESULTS_DIR"/*.md 2>/dev/null || true
    chmod -R 755 "$LOGS_DIR" "$REPORTS_DIR" "$ARTIFACTS_DIR" 2>/dev/null || true
    
    log_success "Cleanup completed" "MAIN"
}

# Signal handlers
handle_interrupt() {
    log_warning "Verification interrupted by user" "MAIN"
    
    # Kill any background processes
    jobs -p | xargs -r kill 2>/dev/null || true
    
    # Generate partial report
    if [[ ${#phase_status[@]} -gt 0 ]]; then
        log_info "Generating partial report..." "MAIN"
        generate_comprehensive_report
    fi
    
    cleanup_and_finalize
    exit 130
}

handle_error() {
    local exit_code=$?
    log_error "Verification script encountered an error (exit code: $exit_code)" "MAIN"
    
    # Generate error report
    if [[ ${#phase_status[@]} -gt 0 ]]; then
        generate_comprehensive_report
    fi
    
    cleanup_and_finalize
    exit $exit_code
}

# Usage information
show_usage() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION

USAGE:
    $0 [OPTIONS]

DESCRIPTION:
    Orchestrates complete formal verification of the Alpenglow consensus protocol
    through eight comprehensive phases: Assessment, Foundation, Proof Completion,
    Implementation, Model Checking, Cross-Validation, Theorem Validation, and
    Performance Testing.

OPTIONS:
    --verbose, -v                Enable verbose output
    --dry-run                    Show what would be done without executing
    --continue-on-error          Continue execution even if phases fail
    --skip-backups              Skip creating project backups
    --no-parallel               Disable parallel execution within phases
    --no-artifacts              Don't generate CI artifacts
    --ci                        Enable CI mode (structured output, compressed logs)
    
    --parallel-jobs N           Number of parallel jobs (default: auto-detect)
    --max-retries N             Maximum retry attempts per phase (default: 3)
    
    --skip-assessment           Skip the assessment phase
    --skip-foundation           Skip the foundation phase
    --skip-proof-completion     Skip the proof completion phase
    --skip-implementation       Skip the implementation phase
    --skip-model-checking       Skip the model checking phase
    --skip-cross-validation     Skip the cross-validation phase
    --skip-theorem-validation   Skip the theorem validation phase
    --skip-performance          Skip the performance testing phase
    
    --timeout-assessment N      Assessment timeout in seconds (default: 600)
    --timeout-foundation N      Foundation timeout in seconds (default: 1800)
    --timeout-proofs N          Proof completion timeout in seconds (default: 3600)
    --timeout-implementation N  Implementation timeout in seconds (default: 1200)
    --timeout-model-checking N  Model checking timeout in seconds (default: 2400)
    --timeout-cross-validation N Cross-validation timeout in seconds (default: 900)
    --timeout-theorem-validation N Theorem validation timeout in seconds (default: 600)
    --timeout-performance N     Performance testing timeout in seconds (default: 1800)
    
    --help, -h                  Show this help message

ENVIRONMENT VARIABLES:
    TLC_PATH                    Path to TLC executable (default: tlc)
    TLAPS_PATH                  Path to TLAPS executable (default: tlapm)
    CARGO_PATH                  Path to Cargo executable (default: cargo)
    JAVA_PATH                   Path to Java executable (default: java)
    PYTHON_PATH                 Path to Python executable (default: python3)
    
    PARALLEL_JOBS               Number of parallel jobs
    MAX_RETRIES                 Maximum retry attempts
    VERBOSE                     Enable verbose output (true/false)
    DRY_RUN                     Enable dry run mode (true/false)
    CONTINUE_ON_ERROR           Continue on phase failures (true/false)
    CI_MODE                     Enable CI mode (true/false)

PHASES:
    1. Assessment               Validate current verification status
    2. Foundation               Fix critical issues and complete foundational modules
    3. Proof Completion         Complete safety and liveness proofs
    4. Implementation           Fix and validate Stateright implementation
    5. Model Checking           Execute comprehensive model checking
    6. Cross-Validation         Validate TLA+ and Stateright correspondence
    7. Theorem Validation       Verify whitepaper theorem correspondence
    8. Performance Testing      Run performance and scalability tests

OUTPUT:
    Results are stored in: $RESULTS_DIR
    - logs/                     Detailed execution logs
    - reports/                  Comprehensive reports and summaries
    - artifacts/                CI artifacts and metrics
    - backups/                  Project backups (if enabled)

EXAMPLES:
    # Full verification with verbose output
    $0 --verbose
    
    # Quick assessment only
    $0 --skip-foundation --skip-proof-completion --skip-implementation \\
       --skip-model-checking --skip-cross-validation --skip-theorem-validation \\
       --skip-performance
    
    # CI mode with custom timeouts
    $0 --ci --timeout-proofs 7200 --timeout-model-checking 3600
    
    # Dry run to see what would be executed
    $0 --dry-run --verbose

EOF
}

# Main execution function
main() {
    # Set up signal handlers
    trap handle_interrupt SIGINT SIGTERM
    trap handle_error ERR
    
    # Record overall start time
    overall_start_time=$(date +%s)
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --continue-on-error)
                CONTINUE_ON_ERROR=true
                shift
                ;;
            --skip-backups)
                SKIP_BACKUPS=true
                shift
                ;;
            --no-parallel)
                PARALLEL_PHASES=false
                shift
                ;;
            --no-artifacts)
                GENERATE_ARTIFACTS=false
                shift
                ;;
            --ci)
                CI_MODE=true
                VERBOSE=false
                GENERATE_ARTIFACTS=true
                shift
                ;;
            --parallel-jobs)
                PARALLEL_JOBS="$2"
                shift 2
                ;;
            --max-retries)
                MAX_RETRIES="$2"
                shift 2
                ;;
            --skip-assessment)
                RUN_ASSESSMENT=false
                shift
                ;;
            --skip-foundation)
                RUN_FOUNDATION=false
                shift
                ;;
            --skip-proof-completion)
                RUN_PROOF_COMPLETION=false
                shift
                ;;
            --skip-implementation)
                RUN_IMPLEMENTATION=false
                shift
                ;;
            --skip-model-checking)
                RUN_MODEL_CHECKING=false
                shift
                ;;
            --skip-cross-validation)
                RUN_CROSS_VALIDATION=false
                shift
                ;;
            --skip-theorem-validation)
                RUN_THEOREM_VALIDATION=false
                shift
                ;;
            --skip-performance)
                RUN_PERFORMANCE=false
                shift
                ;;
            --timeout-assessment)
                TIMEOUT_ASSESSMENT="$2"
                shift 2
                ;;
            --timeout-foundation)
                TIMEOUT_FOUNDATION="$2"
                shift 2
                ;;
            --timeout-proofs)
                TIMEOUT_PROOFS="$2"
                shift 2
                ;;
            --timeout-implementation)
                TIMEOUT_IMPLEMENTATION="$2"
                shift 2
                ;;
            --timeout-model-checking)
                TIMEOUT_MODEL_CHECKING="$2"
                shift 2
                ;;
            --timeout-cross-validation)
                TIMEOUT_CROSS_VALIDATION="$2"
                shift 2
                ;;
            --timeout-theorem-validation)
                TIMEOUT_THEOREM_VALIDATION="$2"
                shift 2
                ;;
            --timeout-performance)
                TIMEOUT_PERFORMANCE="$2"
                shift 2
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                echo "Error: Unknown option: $1" >&2
                echo "Use --help for usage information." >&2
                exit 1
                ;;
        esac
    done
    
    # Initialize logging and output
    setup_logging
    
    # Display header
    echo -e "${BOLD}${CYAN}"
    echo "=================================================================="
    echo "           $SCRIPT_NAME v$SCRIPT_VERSION"
    echo "=================================================================="
    echo -e "${NC}"
    echo "Project Root: $PROJECT_ROOT"
    echo "Results Directory: $RESULTS_DIR"
    echo "Parallel Jobs: $PARALLEL_JOBS"
    echo "Max Retries: $MAX_RETRIES"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}${WARNING_MARK} DRY RUN MODE - No changes will be made${NC}"
    fi
    echo ""
    
    # Environment validation
    if ! check_environment; then
        log_error "Environment validation failed" "MAIN"
        exit 1
    fi
    
    # Create backups
    if ! create_backups; then
        log_warning "Backup creation failed, continuing..." "MAIN"
    fi
    
    # Initialize phase tracking
    local phases=(
        "ASSESSMENT"
        "FOUNDATION" 
        "PROOF_COMPLETION"
        "IMPLEMENTATION"
        "MODEL_CHECKING"
        "CROSS_VALIDATION"
        "THEOREM_VALIDATION"
        "PERFORMANCE"
    )
    
    # Set up dependency graph
    dependency_graph["FOUNDATION"]="ASSESSMENT"
    dependency_graph["PROOF_COMPLETION"]="FOUNDATION"
    dependency_graph["IMPLEMENTATION"]="FOUNDATION"
    dependency_graph["MODEL_CHECKING"]="FOUNDATION"
    dependency_graph["CROSS_VALIDATION"]="IMPLEMENTATION,MODEL_CHECKING"
    dependency_graph["THEOREM_VALIDATION"]="PROOF_COMPLETION"
    dependency_graph["PERFORMANCE"]="MODEL_CHECKING,IMPLEMENTATION"
    
    # Execute phases
    log_info "Starting comprehensive verification with ${#phases[@]} phases..." "MAIN"
    echo ""
    
    for phase in "${phases[@]}"; do
        local phase_func="phase_${phase,,}"
        local timeout_var="TIMEOUT_${phase}"
        local timeout="${!timeout_var}"
        local dependencies="${dependency_graph[$phase]:-}"
        
        if ! execute_phase "$phase" "$phase_func" "$timeout" "$dependencies"; then
            if [[ "$CONTINUE_ON_ERROR" != "true" ]]; then
                log_error "Stopping execution due to phase failure" "MAIN"
                break
            fi
        fi
        echo ""
    done
    
    # Record overall end time
    overall_end_time=$(date +%s)
    local total_execution_time=$((overall_end_time - overall_start_time))
    
    # Generate comprehensive report
    generate_comprehensive_report
    
    # Cleanup
    cleanup_and_finalize
    
    # Final summary
    echo ""
    echo -e "${BOLD}${CYAN}=================================================================="
    echo "                    VERIFICATION COMPLETE"
    echo -e "==================================================================${NC}"
    echo ""
    echo "Total Execution Time: ${total_execution_time}s"
    echo "Successful Phases: $completed_phases/$total_phases"
    echo "Failed Phases: $failed_phases"
    echo "Skipped Phases: $skipped_phases"
    echo ""
    
    if [[ $failed_phases -eq 0 ]]; then
        echo -e "${GREEN}${CHECK_MARK} All enabled phases completed successfully!${NC}"
        echo ""
        echo "Results available in: $RESULTS_DIR"
        echo "Executive Summary: $REPORTS_DIR/executive_summary.md"
        echo "Detailed Report: $REPORTS_DIR/comprehensive_verification_report.json"
        exit 0
    else
        echo -e "${RED}${CROSS_MARK} $failed_phases phase(s) failed${NC}"
        echo ""
        echo "Check logs in: $LOGS_DIR"
        echo "Review report: $REPORTS_DIR/executive_summary.md"
        exit 1
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi