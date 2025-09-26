#!/bin/bash
# Author: Ayush Srivastava

#############################################################################
# Parallel Verification Script
# 
# Executes massive parallel verification across multiple workers with
# configurable timeout and resource management.
#############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESULTS_DIR="$PROJECT_ROOT/ci-cd/results/parallel"
LOG_DIR="$PROJECT_ROOT/ci-cd/logs/parallel"

# Default configuration
WORKERS=64
TIMEOUT=3600  # 1 hour default
MEMORY_LIMIT="8G"
VERBOSE=false

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

show_help() {
    cat << EOF
Alpenglow Parallel Verification Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --workers N         Number of parallel workers (default: 64)
    --timeout N         Timeout in seconds (default: 3600)
    --memory-limit SIZE Memory limit per worker (default: 8G)
    --verbose           Enable verbose output
    --help              Show this help message

EXAMPLES:
    $0 --workers 32 --timeout 1800
    $0 --workers 128 --memory-limit 16G --verbose
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --workers)
            WORKERS="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --memory-limit)
            MEMORY_LIMIT="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Create directories
mkdir -p "$RESULTS_DIR" "$LOG_DIR"

# Start timing
START_TIME=$(date +%s)

print_banner "Alpenglow Massive Parallel Verification"
print_info "Workers: $WORKERS"
print_info "Timeout: ${TIMEOUT}s ($(($TIMEOUT / 60))m)"
print_info "Memory limit per worker: $MEMORY_LIMIT"

# Verification job queue
VERIFICATION_JOBS=()

# Foundation layer jobs
VERIFICATION_JOBS+=("foundation:Types.tla:specs/Types.tla")
VERIFICATION_JOBS+=("foundation:Utils.tla:specs/Utils.tla")
VERIFICATION_JOBS+=("foundation:Crypto.tla:specs/Crypto.tla")

# Protocol layer jobs
VERIFICATION_JOBS+=("protocol:Network.tla:specs/Network.tla")
VERIFICATION_JOBS+=("protocol:Votor.tla:specs/Votor.tla")
VERIFICATION_JOBS+=("protocol:Rotor.tla:specs/Rotor.tla")
VERIFICATION_JOBS+=("protocol:VRF.tla:specs/VRF.tla")
VERIFICATION_JOBS+=("protocol:Stake.tla:specs/Stake.tla")

# Integration layer jobs
VERIFICATION_JOBS+=("integration:Alpenglow.tla:specs/Alpenglow.tla")
VERIFICATION_JOBS+=("integration:Integration.tla:specs/Integration.tla")
VERIFICATION_JOBS+=("integration:EconomicModel.tla:specs/EconomicModel.tla")

# Property verification jobs
VERIFICATION_JOBS+=("properties:Safety.tla:proofs/Safety.tla")
VERIFICATION_JOBS+=("properties:Liveness.tla:proofs/Liveness.tla")
VERIFICATION_JOBS+=("properties:Resilience.tla:proofs/Resilience.tla")
VERIFICATION_JOBS+=("properties:EconomicSafety.tla:proofs/EconomicSafety.tla")

# Model checking jobs for different configurations
MODEL_CONFIGS=("Small" "Medium" "LargeScale" "Adversarial" "Boundary" "EdgeCase" "Stress")
for config in "${MODEL_CONFIGS[@]}"; do
    VERIFICATION_JOBS+=("model:${config}.cfg:models/${config}.cfg")
done

# Stateright verification jobs
STATERIGHT_TESTS=("safety_properties" "liveness_properties" "byzantine_resilience" "cross_validation" "sampling_verification")
for test in "${STATERIGHT_TESTS[@]}"; do
    VERIFICATION_JOBS+=("stateright:${test}:stateright/tests/${test}.rs")
done

print_info "Total verification jobs: ${#VERIFICATION_JOBS[@]}"

# Worker function
run_verification_job() {
    local job="$1"
    local worker_id="$2"
    
    IFS=':' read -r category name path <<< "$job"
    
    local job_log="$LOG_DIR/worker_${worker_id}_${category}_${name}.log"
    local job_result="$RESULTS_DIR/worker_${worker_id}_${category}_${name}.json"
    
    local job_start=$(date +%s)
    
    case "$category" in
        "foundation"|"protocol"|"integration"|"properties")
            # TLA+ verification
            local full_path="$PROJECT_ROOT/$path"
            if [[ -f "$full_path" ]]; then
                if timeout "$TIMEOUT" java -Xmx"$MEMORY_LIMIT" -jar "$PROJECT_ROOT/tools/tla2tools.jar" \
                   -parse "$full_path" > "$job_log" 2>&1; then
                    
                    # Try TLAPS if available
                    if command -v tlapm &> /dev/null; then
                        if timeout "$TIMEOUT" tlapm "$full_path" >> "$job_log" 2>&1; then
                            local obligations=$(grep -c "obligation" "$job_log" 2>/dev/null || echo "0")
                            local proved=$(grep -c "proved" "$job_log" 2>/dev/null || echo "0")
                            local status="SUCCESS"
                        else
                            local obligations="0"
                            local proved="0"
                            local status="TLAPS_FAILED"
                        fi
                    else
                        local obligations="1"
                        local proved="1"
                        local status="SYNTAX_OK"
                    fi
                else
                    local obligations="0"
                    local proved="0"
                    local status="SYNTAX_ERROR"
                fi
            else
                local obligations="0"
                local proved="0"
                local status="FILE_NOT_FOUND"
            fi
            ;;
            
        "model")
            # TLC model checking
            local config_path="$PROJECT_ROOT/$path"
            local spec_name=$(basename "$name" .cfg)
            local spec_path="$PROJECT_ROOT/specs/${spec_name}.tla"
            
            if [[ -f "$config_path" ]] && [[ -f "$spec_path" ]]; then
                if timeout "$TIMEOUT" java -Xmx"$MEMORY_LIMIT" -jar "$PROJECT_ROOT/tools/tla2tools.jar" \
                   -config "$config_path" "$spec_path" > "$job_log" 2>&1; then
                    local states=$(grep "states generated" "$job_log" | grep -o '[0-9,]*' | tr -d ',' || echo "0")
                    local status="SUCCESS"
                    local obligations="1"
                    local proved="1"
                else
                    local states="0"
                    local status="MODEL_CHECK_FAILED"
                    local obligations="1"
                    local proved="0"
                fi
            else
                local status="CONFIG_NOT_FOUND"
                local obligations="0"
                local proved="0"
            fi
            ;;
            
        "stateright")
            # Stateright testing
            if (cd "$PROJECT_ROOT/stateright" && \
                timeout "$TIMEOUT" cargo test --release "$name" > "$job_log" 2>&1); then
                local status="SUCCESS"
                local obligations="1"
                local proved="1"
            else
                local status="TEST_FAILED"
                local obligations="1"
                local proved="0"
            fi
            ;;
    esac
    
    local job_end=$(date +%s)
    local job_time=$((job_end - job_start))
    
    # Write job result
    cat > "$job_result" << EOF
{
  "worker_id": $worker_id,
  "category": "$category",
  "name": "$name",
  "path": "$path",
  "status": "$status",
  "obligations": ${obligations:-0},
  "proved": ${proved:-0},
  "time_seconds": $job_time,
  "timestamp": "$(date -Iseconds)"
}
EOF
    
    if [[ "$VERBOSE" == "true" ]]; then
        echo "Worker $worker_id completed $category:$name in ${job_time}s ($status)"
    fi
}

# Export function for parallel execution
export -f run_verification_job
export PROJECT_ROOT TIMEOUT MEMORY_LIMIT LOG_DIR RESULTS_DIR VERBOSE

print_progress "Starting parallel verification with $WORKERS workers..."

# Run jobs in parallel using GNU parallel or xargs
if command -v parallel &> /dev/null; then
    printf '%s\n' "${VERIFICATION_JOBS[@]}" | \
    parallel -j "$WORKERS" --line-buffer run_verification_job {} {#}
else
    # Fallback to xargs if GNU parallel not available
    printf '%s\n' "${VERIFICATION_JOBS[@]}" | \
    nl -nln | \
    xargs -n 2 -P "$WORKERS" -I {} bash -c 'run_verification_job "$2" "$1"' _ {}
fi

# Collect and analyze results
print_progress "Collecting results from $WORKERS workers..."

TOTAL_JOBS=${#VERIFICATION_JOBS[@]}
SUCCESSFUL_JOBS=0
FAILED_JOBS=0
TOTAL_OBLIGATIONS=0
VERIFIED_OBLIGATIONS=0

for result_file in "$RESULTS_DIR"/*.json; do
    if [[ -f "$result_file" ]]; then
        status=$(jq -r '.status' "$result_file" 2>/dev/null || echo "UNKNOWN")
        obligations=$(jq -r '.obligations' "$result_file" 2>/dev/null || echo "0")
        proved=$(jq -r '.proved' "$result_file" 2>/dev/null || echo "0")
        
        TOTAL_OBLIGATIONS=$((TOTAL_OBLIGATIONS + obligations))
        VERIFIED_OBLIGATIONS=$((VERIFIED_OBLIGATIONS + proved))
        
        if [[ "$status" == "SUCCESS" ]]; then
            ((SUCCESSFUL_JOBS++))
        else
            ((FAILED_JOBS++))
        fi
    fi
done

# Calculate final statistics
END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))
SUCCESS_RATE=$((SUCCESSFUL_JOBS * 100 / TOTAL_JOBS))
OBLIGATION_RATE=$((VERIFIED_OBLIGATIONS * 100 / TOTAL_OBLIGATIONS))

# Generate comprehensive report
cat > "$RESULTS_DIR/parallel_verification_report.json" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "configuration": {
    "workers": $WORKERS,
    "timeout": $TIMEOUT,
    "memory_limit": "$MEMORY_LIMIT"
  },
  "results": {
    "total_time_seconds": $TOTAL_TIME,
    "total_jobs": $TOTAL_JOBS,
    "successful_jobs": $SUCCESSFUL_JOBS,
    "failed_jobs": $FAILED_JOBS,
    "job_success_rate": $SUCCESS_RATE,
    "total_obligations": $TOTAL_OBLIGATIONS,
    "verified_obligations": $VERIFIED_OBLIGATIONS,
    "obligation_success_rate": $OBLIGATION_RATE
  }
}
EOF

# Print final summary
print_banner "Parallel Verification Results"
print_info "Total time: ${TOTAL_TIME}s ($(($TOTAL_TIME / 60))m $(($TOTAL_TIME % 60))s)"
print_info "Workers used: $WORKERS"
print_info "Jobs completed: $SUCCESSFUL_JOBS/$TOTAL_JOBS ($SUCCESS_RATE%)"
print_info "Proof obligations: $VERIFIED_OBLIGATIONS/$TOTAL_OBLIGATIONS ($OBLIGATION_RATE%)"

if [[ $FAILED_JOBS -eq 0 ]]; then
    print_success "🎉 All parallel verification jobs completed successfully!"
    exit 0
else
    print_error "❌ $FAILED_JOBS jobs failed verification"
    print_info "Check individual worker logs in: $LOG_DIR"
    exit 1
fi
