#!/bin/bash

#############################################################################
# Large-Scale Verification Script for Alpenglow Protocol
#
# This script runs large-scale verification using the LargeScale.cfg 
# configuration for networks with 20+ validators. It includes:
# - Advanced memory management for large state spaces
# - Parallel execution with worker coordination
# - Statistical model checking for tractable verification
# - Result aggregation and analysis
# - Resource monitoring and optimization
#
# Usage: ./large_scale_verify.sh [OPTIONS]
#   --memory SIZE                 JVM heap size (default: auto-detect)
#   --workers N                   Number of worker threads (default: auto)
#   --timeout SECONDS             Verification timeout (default: 7200)
#   --statistical                 Enable statistical model checking
#   --checkpoint-interval SECS    Checkpoint interval (default: 1800)
#   --output-dir DIR              Output directory (default: results/large_scale)
#   --resume CHECKPOINT           Resume from checkpoint
#   --memory-fraction FRACTION    TLC memory fraction (default: 0.8)
#   --disk-storage                Enable disk-based state storage
#   --profile                     Enable performance profiling
#############################################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MODELS_DIR="$PROJECT_DIR/models"
SPECS_DIR="$PROJECT_DIR/specs"
PROOFS_DIR="$PROJECT_DIR/proofs"

# Default configuration
MEMORY_SIZE=""
WORKERS=""
TIMEOUT=7200
STATISTICAL=false
CHECKPOINT_INTERVAL=1800
OUTPUT_DIR="$PROJECT_DIR/results/large_scale"
RESUME_CHECKPOINT=""
MEMORY_FRACTION=0.8
DISK_STORAGE=false
PROFILE=false
VERBOSE=false

# TLA+ Tools configuration
TLA_TOOLS_JAR="$PROJECT_DIR/tools/tla2tools.jar"
LARGE_SCALE_CONFIG="$MODELS_DIR/LargeScale.cfg"
ALPENGLOW_SPEC="$SPECS_DIR/Alpenglow.tla"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --memory)
            MEMORY_SIZE="$2"
            shift 2
            ;;
        --workers)
            WORKERS="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --statistical)
            STATISTICAL=true
            shift
            ;;
        --checkpoint-interval)
            CHECKPOINT_INTERVAL="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --resume)
            RESUME_CHECKPOINT="$2"
            shift 2
            ;;
        --memory-fraction)
            MEMORY_FRACTION="$2"
            shift 2
            ;;
        --disk-storage)
            DISK_STORAGE=true
            shift
            ;;
        --profile)
            PROFILE=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            echo "Large-Scale Verification Script for Alpenglow Protocol"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --memory SIZE                 JVM heap size (e.g., 32g, 64g)"
            echo "  --workers N                   Number of worker threads"
            echo "  --timeout SECONDS             Verification timeout (default: 7200)"
            echo "  --statistical                 Enable statistical model checking"
            echo "  --checkpoint-interval SECS    Checkpoint interval (default: 1800)"
            echo "  --output-dir DIR              Output directory"
            echo "  --resume CHECKPOINT           Resume from checkpoint"
            echo "  --memory-fraction FRACTION    TLC memory fraction (0.0-1.0)"
            echo "  --disk-storage                Enable disk-based state storage"
            echo "  --profile                     Enable performance profiling"
            echo "  --verbose                     Enable verbose output"
            echo "  --help                        Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Helper functions
print_header() {
    echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}${BOLD}  $1${NC}"
    echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════${NC}"
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_debug() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${CYAN}[DEBUG]${NC} $1"
    fi
}

# System resource detection
detect_system_resources() {
    print_debug "Detecting system resources..."
    
    # Detect available memory
    if [ -z "$MEMORY_SIZE" ]; then
        if command -v free &> /dev/null; then
            # Linux
            local total_mem_kb=$(free -k | awk '/^Mem:/{print $2}')
            local total_mem_gb=$((total_mem_kb / 1024 / 1024))
            # Use 80% of available memory for large-scale verification
            MEMORY_SIZE="${total_mem_gb}g"
        elif command -v vm_stat &> /dev/null; then
            # macOS
            local page_size=$(vm_stat | grep "page size" | awk '{print $8}')
            local pages_free=$(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
            local pages_active=$(vm_stat | grep "Pages active" | awk '{print $3}' | sed 's/\.//')
            local pages_inactive=$(vm_stat | grep "Pages inactive" | awk '{print $3}' | sed 's/\.//')
            local total_mem_bytes=$(((pages_free + pages_active + pages_inactive) * page_size))
            local total_mem_gb=$((total_mem_bytes / 1024 / 1024 / 1024))
            MEMORY_SIZE="${total_mem_gb}g"
        else
            print_warn "Could not detect system memory, using default 16g"
            MEMORY_SIZE="16g"
        fi
    fi
    
    # Detect CPU cores
    if [ -z "$WORKERS" ]; then
        if command -v nproc &> /dev/null; then
            WORKERS=$(nproc)
        elif command -v sysctl &> /dev/null; then
            WORKERS=$(sysctl -n hw.ncpu)
        else
            WORKERS=4
        fi
        # Use 75% of cores for large-scale verification
        WORKERS=$((WORKERS * 3 / 4))
        [ $WORKERS -lt 1 ] && WORKERS=1
    fi
    
    print_info "Detected system resources:"
    print_info "  Memory allocation: $MEMORY_SIZE"
    print_info "  Worker threads: $WORKERS"
}

# Validate prerequisites
validate_prerequisites() {
    print_debug "Validating prerequisites..."
    
    # Check for Java
    if ! command -v java &> /dev/null; then
        print_error "Java is required but not installed"
        exit 1
    fi
    
    # Check Java version (TLA+ requires Java 8+)
    local java_version=$(java -version 2>&1 | head -1 | cut -d'"' -f2 | cut -d'.' -f1-2)
    if [[ $(echo "$java_version < 1.8" | bc -l) -eq 1 ]]; then
        print_error "Java 8 or higher is required (found: $java_version)"
        exit 1
    fi
    
    # Check for TLA+ tools
    if [ ! -f "$TLA_TOOLS_JAR" ]; then
        print_error "TLA+ tools not found at: $TLA_TOOLS_JAR"
        print_info "Please download tla2tools.jar from https://github.com/tlaplus/tlaplus/releases"
        exit 1
    fi
    
    # Check for configuration file
    if [ ! -f "$LARGE_SCALE_CONFIG" ]; then
        print_error "Large-scale configuration not found: $LARGE_SCALE_CONFIG"
        exit 1
    fi
    
    # Check for specification file
    if [ ! -f "$ALPENGLOW_SPEC" ]; then
        print_error "Alpenglow specification not found: $ALPENGLOW_SPEC"
        exit 1
    fi
    
    print_info "Prerequisites validated successfully"
}

# Setup output directory and logging
setup_output() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local session_dir="$OUTPUT_DIR/session_${timestamp}"
    
    mkdir -p "$session_dir"
    mkdir -p "$session_dir/checkpoints"
    mkdir -p "$session_dir/logs"
    mkdir -p "$session_dir/stats"
    
    # Set global session directory
    SESSION_DIR="$session_dir"
    
    # Setup logging
    LOG_FILE="$SESSION_DIR/logs/verification.log"
    STATS_FILE="$SESSION_DIR/stats/performance.json"
    
    print_info "Session directory: $SESSION_DIR"
    
    # Create initial stats file
    cat > "$STATS_FILE" << EOF
{
    "session_id": "session_${timestamp}",
    "start_time": "$(date -Iseconds)",
    "configuration": {
        "memory_size": "$MEMORY_SIZE",
        "workers": $WORKERS,
        "timeout": $TIMEOUT,
        "statistical": $STATISTICAL,
        "checkpoint_interval": $CHECKPOINT_INTERVAL,
        "memory_fraction": $MEMORY_FRACTION,
        "disk_storage": $DISK_STORAGE
    },
    "system_info": {
        "hostname": "$(hostname)",
        "os": "$(uname -s)",
        "arch": "$(uname -m)",
        "java_version": "$(java -version 2>&1 | head -1)"
    }
}
EOF
}

# Build TLC command line
build_tlc_command() {
    local tlc_cmd="java"
    
    # JVM memory settings
    tlc_cmd="$tlc_cmd -Xmx$MEMORY_SIZE -Xms$MEMORY_SIZE"
    
    # JVM optimization flags for large-scale verification
    tlc_cmd="$tlc_cmd -XX:+UseG1GC"                    # G1 garbage collector for large heaps
    tlc_cmd="$tlc_cmd -XX:MaxGCPauseMillis=200"        # Limit GC pause time
    tlc_cmd="$tlc_cmd -XX:+UnlockExperimentalVMOptions"
    tlc_cmd="$tlc_cmd -XX:+UseStringDeduplication"     # Reduce memory usage
    tlc_cmd="$tlc_cmd -XX:+OptimizeStringConcat"       # String optimization
    
    if [ "$PROFILE" = true ]; then
        tlc_cmd="$tlc_cmd -XX:+FlightRecorder"
        tlc_cmd="$tlc_cmd -XX:StartFlightRecording=duration=3600s,filename=$SESSION_DIR/logs/profile.jfr"
    fi
    
    # TLA+ tools JAR
    tlc_cmd="$tlc_cmd -cp $TLA_TOOLS_JAR"
    
    # TLC main class
    tlc_cmd="$tlc_cmd tlc2.TLC"
    
    # TLC-specific options
    tlc_cmd="$tlc_cmd -workers $WORKERS"               # Number of worker threads
    tlc_cmd="$tlc_cmd -config $LARGE_SCALE_CONFIG"     # Configuration file
    
    if [ "$STATISTICAL" = true ]; then
        tlc_cmd="$tlc_cmd -simulate"                   # Statistical model checking
        tlc_cmd="$tlc_cmd -depth 50"                   # Maximum trace depth
    fi
    
    # Memory management
    tlc_cmd="$tlc_cmd -maxSetSize 1000000"             # Maximum set size
    tlc_cmd="$tlc_cmd -fpbits 3"                       # Fingerprint bits (memory vs collision trade-off)
    
    if [ "$DISK_STORAGE" = true ]; then
        tlc_cmd="$tlc_cmd -checkpoint $CHECKPOINT_INTERVAL" # Enable checkpointing
        tlc_cmd="$tlc_cmd -recover $SESSION_DIR/checkpoints" # Checkpoint directory
    fi
    
    # Resume from checkpoint if specified
    if [ -n "$RESUME_CHECKPOINT" ]; then
        tlc_cmd="$tlc_cmd -recover $RESUME_CHECKPOINT"
    fi
    
    # Verbose output if requested
    if [ "$VERBOSE" = true ]; then
        tlc_cmd="$tlc_cmd -verbose"
    fi
    
    # Specification file (must be last)
    tlc_cmd="$tlc_cmd $ALPENGLOW_SPEC"
    
    echo "$tlc_cmd"
}

# Monitor system resources during verification
monitor_resources() {
    local monitor_file="$SESSION_DIR/stats/resource_usage.csv"
    
    # Create CSV header
    echo "timestamp,cpu_percent,memory_mb,disk_io_read,disk_io_write" > "$monitor_file"
    
    while true; do
        local timestamp=$(date -Iseconds)
        local cpu_percent=""
        local memory_mb=""
        local disk_read=""
        local disk_write=""
        
        # Get CPU usage
        if command -v top &> /dev/null; then
            cpu_percent=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
        fi
        
        # Get memory usage
        if command -v free &> /dev/null; then
            memory_mb=$(free -m | awk '/^Mem:/{print $3}')
        fi
        
        # Get disk I/O (Linux only)
        if command -v iostat &> /dev/null; then
            local io_stats=$(iostat -d 1 1 | tail -1)
            disk_read=$(echo "$io_stats" | awk '{print $3}')
            disk_write=$(echo "$io_stats" | awk '{print $4}')
        fi
        
        echo "$timestamp,$cpu_percent,$memory_mb,$disk_read,$disk_write" >> "$monitor_file"
        sleep 30  # Monitor every 30 seconds
    done
}

# Parse TLC output for statistics
parse_tlc_output() {
    local output_file="$1"
    local stats_output="$SESSION_DIR/stats/tlc_stats.json"
    
    if [ ! -f "$output_file" ]; then
        return
    fi
    
    # Extract key statistics from TLC output
    local states_generated=$(grep -oE '[0-9,]+ states generated' "$output_file" | tail -1 | grep -oE '[0-9,]+' | tr -d ',')
    local distinct_states=$(grep -oE '[0-9,]+ distinct states found' "$output_file" | tail -1 | grep -oE '[0-9,]+' | tr -d ',')
    local queue_size=$(grep -oE 'Queue size: [0-9,]+' "$output_file" | tail -1 | grep -oE '[0-9,]+' | tr -d ',')
    local completion_time=$(grep -oE 'Model checking completed\. No error has been found\.' "$output_file")
    local violations=$(grep -c "Invariant .* is violated" "$output_file" || echo "0")
    local deadlocks=$(grep -c "Deadlock reached" "$output_file" || echo "0")
    
    # Calculate verification rate
    local verification_rate=""
    if [ -n "$states_generated" ] && [ -n "$START_TIME" ]; then
        local current_time=$(date +%s)
        local elapsed_time=$((current_time - START_TIME))
        if [ $elapsed_time -gt 0 ]; then
            verification_rate=$((states_generated / elapsed_time))
        fi
    fi
    
    # Create statistics JSON
    cat > "$stats_output" << EOF
{
    "states_generated": ${states_generated:-0},
    "distinct_states": ${distinct_states:-0},
    "queue_size": ${queue_size:-0},
    "verification_rate_per_second": ${verification_rate:-0},
    "violations_found": ${violations:-0},
    "deadlocks_found": ${deadlocks:-0},
    "completed_successfully": $([ -n "$completion_time" ] && echo "true" || echo "false"),
    "last_updated": "$(date -Iseconds)"
}
EOF
}

# Generate comprehensive report
generate_report() {
    local report_file="$SESSION_DIR/verification_report.md"
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    
    cat > "$report_file" << EOF
# Large-Scale Verification Report

## Session Information
- **Session ID**: $(basename "$SESSION_DIR")
- **Start Time**: $(date -d "@$START_TIME" 2>/dev/null || date -r "$START_TIME")
- **End Time**: $(date -d "@$end_time" 2>/dev/null || date -r "$end_time")
- **Duration**: $(printf '%02d:%02d:%02d' $((duration/3600)) $((duration%3600/60)) $((duration%60)))

## Configuration
- **Memory Allocation**: $MEMORY_SIZE
- **Worker Threads**: $WORKERS
- **Timeout**: $TIMEOUT seconds
- **Statistical Mode**: $STATISTICAL
- **Checkpoint Interval**: $CHECKPOINT_INTERVAL seconds
- **Memory Fraction**: $MEMORY_FRACTION
- **Disk Storage**: $DISK_STORAGE

## Verification Results
EOF

    # Add TLC statistics if available
    if [ -f "$SESSION_DIR/stats/tlc_stats.json" ]; then
        echo "### TLC Statistics" >> "$report_file"
        echo '```json' >> "$report_file"
        cat "$SESSION_DIR/stats/tlc_stats.json" >> "$report_file"
        echo '```' >> "$report_file"
        echo "" >> "$report_file"
    fi
    
    # Add resource usage summary
    if [ -f "$SESSION_DIR/stats/resource_usage.csv" ]; then
        echo "### Resource Usage" >> "$report_file"
        echo "- **Peak Memory Usage**: $(tail -n +2 "$SESSION_DIR/stats/resource_usage.csv" | cut -d',' -f3 | sort -n | tail -1) MB" >> "$report_file"
        echo "- **Average CPU Usage**: $(tail -n +2 "$SESSION_DIR/stats/resource_usage.csv" | cut -d',' -f2 | awk '{sum+=$1; count++} END {if(count>0) print sum/count; else print 0}')%" >> "$report_file"
        echo "" >> "$report_file"
    fi
    
    # Add log file references
    echo "## Log Files" >> "$report_file"
    echo "- **Main Log**: \`logs/verification.log\`" >> "$report_file"
    echo "- **TLC Output**: \`logs/tlc_output.log\`" >> "$report_file"
    echo "- **Error Log**: \`logs/error.log\`" >> "$report_file"
    if [ "$PROFILE" = true ]; then
        echo "- **Performance Profile**: \`logs/profile.jfr\`" >> "$report_file"
    fi
    echo "" >> "$report_file"
    
    echo "## Files Generated" >> "$report_file"
    echo "- Configuration: \`$LARGE_SCALE_CONFIG\`" >> "$report_file"
    echo "- Specification: \`$ALPENGLOW_SPEC\`" >> "$report_file"
    if [ "$DISK_STORAGE" = true ]; then
        echo "- Checkpoints: \`checkpoints/\`" >> "$report_file"
    fi
    
    print_info "Verification report generated: $report_file"
}

# Cleanup function
cleanup() {
    print_debug "Cleaning up..."
    
    # Kill resource monitor if running
    if [ -n "$MONITOR_PID" ]; then
        kill $MONITOR_PID 2>/dev/null || true
    fi
    
    # Kill TLC process if running
    if [ -n "$TLC_PID" ]; then
        print_warn "Terminating TLC process..."
        kill -TERM $TLC_PID 2>/dev/null || true
        sleep 5
        kill -KILL $TLC_PID 2>/dev/null || true
    fi
    
    # Generate final report
    if [ -n "$SESSION_DIR" ]; then
        generate_report
    fi
}

# Set up signal handlers
trap cleanup EXIT INT TERM

# Main verification function
run_verification() {
    print_header "Large-Scale Verification Execution"
    
    # Build TLC command
    local tlc_command=$(build_tlc_command)
    print_info "TLC Command: $tlc_command"
    
    # Start resource monitoring in background
    monitor_resources &
    MONITOR_PID=$!
    print_debug "Started resource monitor (PID: $MONITOR_PID)"
    
    # Start verification
    print_info "Starting large-scale verification..."
    print_info "Network size: 25 validators (20 honest, 5 Byzantine)"
    print_info "Expected state space: Large (using statistical sampling)"
    print_info "Timeout: $TIMEOUT seconds"
    
    START_TIME=$(date +%s)
    
    # Run TLC with timeout and capture output
    local tlc_output="$SESSION_DIR/logs/tlc_output.log"
    local tlc_error="$SESSION_DIR/logs/error.log"
    
    if timeout $TIMEOUT bash -c "$tlc_command" > "$tlc_output" 2> "$tlc_error"; then
        print_info "Verification completed successfully"
        VERIFICATION_SUCCESS=true
    else
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            print_warn "Verification timed out after $TIMEOUT seconds"
        else
            print_error "Verification failed with exit code: $exit_code"
        fi
        VERIFICATION_SUCCESS=false
    fi
    
    # Parse results
    parse_tlc_output "$tlc_output"
    
    # Show summary
    if [ -f "$SESSION_DIR/stats/tlc_stats.json" ]; then
        local stats=$(cat "$SESSION_DIR/stats/tlc_stats.json")
        local states_generated=$(echo "$stats" | grep -o '"states_generated": [0-9]*' | cut -d':' -f2 | tr -d ' ')
        local violations=$(echo "$stats" | grep -o '"violations_found": [0-9]*' | cut -d':' -f2 | tr -d ' ')
        
        print_info "States generated: $states_generated"
        print_info "Violations found: $violations"
        
        if [ "$violations" -eq 0 ] && [ "$VERIFICATION_SUCCESS" = true ]; then
            print_info "✓ Large-scale verification PASSED"
        else
            print_warn "✗ Large-scale verification found issues"
        fi
    fi
}

# Main execution
main() {
    print_header "Alpenglow Large-Scale Verification"
    print_info "Verifying networks with 20+ validators using statistical model checking"
    echo
    
    # Setup
    detect_system_resources
    validate_prerequisites
    setup_output
    
    # Log configuration
    {
        echo "Large-Scale Verification Session: $(date)"
        echo "Configuration:"
        echo "  Memory: $MEMORY_SIZE"
        echo "  Workers: $WORKERS"
        echo "  Timeout: $TIMEOUT"
        echo "  Statistical: $STATISTICAL"
        echo "  Disk Storage: $DISK_STORAGE"
        echo "  Profile: $PROFILE"
        echo ""
    } | tee "$LOG_FILE"
    
    # Run verification
    run_verification
    
    # Generate final report
    generate_report
    
    print_header "Verification Complete"
    print_info "Session directory: $SESSION_DIR"
    print_info "Full results and logs available in the session directory"
    
    # Exit with appropriate code
    if [ "$VERIFICATION_SUCCESS" = true ]; then
        exit 0
    else
        exit 1
    fi
}

# Execute main function
main "$@"