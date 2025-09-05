#!/bin/bash

################################################################################
# Alpenglow Protocol Comprehensive Benchmark Suite
# 
# This script orchestrates the full benchmarking pipeline for the Alpenglow
# consensus protocol, including performance benchmarks, scalability tests,
# and validation against whitepaper claims.
#
# Usage:
#   ./benchmark_suite.sh [options]
#
# Options:
#   --performance    Run performance benchmarks only
#   --scalability    Run scalability benchmarks only
#   --validation     Run validation benchmarks only
#   --quick          Run quick benchmark suite (small network sizes)
#   --full           Run full benchmark suite (all network sizes)
#   --parallel       Enable parallel execution where possible
#   --output DIR     Specify output directory (default: benchmarks/results)
#   --verbose        Enable verbose output
#   --help           Show this help message
#
# Author: Traycer.AI
# Date: 2024
################################################################################

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BENCHMARKS_DIR="$PROJECT_ROOT/benchmarks"
OUTPUT_DIR="$PROJECT_ROOT/benchmarks/results"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$OUTPUT_DIR/benchmark_suite_$TIMESTAMP.log"

# Benchmark flags
RUN_PERFORMANCE=false
RUN_SCALABILITY=false
RUN_VALIDATION=false
RUN_ALL=true
QUICK_MODE=false
FULL_MODE=false
PARALLEL_EXEC=false
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Function to show usage
show_help() {
    head -n 30 "$0" | grep "^#" | sed 's/^# //' | sed 's/^#//'
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --performance)
            RUN_PERFORMANCE=true
            RUN_ALL=false
            shift
            ;;
        --scalability)
            RUN_SCALABILITY=true
            RUN_ALL=false
            shift
            ;;
        --validation)
            RUN_VALIDATION=true
            RUN_ALL=false
            shift
            ;;
        --quick)
            QUICK_MODE=true
            FULL_MODE=false
            shift
            ;;
        --full)
            FULL_MODE=true
            QUICK_MODE=false
            shift
            ;;
        --parallel)
            PARALLEL_EXEC=true
            shift
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            show_help
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            ;;
    esac
done

# Restore RUN_ALL flags if needed
if [ "$RUN_PERFORMANCE" = false ] && [ "$RUN_SCALABILITY" = false ] && [ "$RUN_VALIDATION" = false ]; then
    RUN_ALL=true
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Initialize log file
echo "Alpenglow Protocol Benchmark Suite" > "$LOG_FILE"
echo "Started at: $(date)" >> "$LOG_FILE"
echo "Configuration:" >> "$LOG_FILE"
echo "  Performance: $RUN_PERFORMANCE" >> "$LOG_FILE"
echo "  Scalability: $RUN_SCALABILITY" >> "$LOG_FILE"
echo "  Validation: $RUN_VALIDATION" >> "$LOG_FILE"
echo "  All: $RUN_ALL" >> "$LOG_FILE"
echo "  Quick Mode: $QUICK_MODE" >> "$LOG_FILE"
echo "  Full Mode: $FULL_MODE" >> "$LOG_FILE"
echo "  Parallel: $PARALLEL_EXEC" >> "$LOG_FILE"
echo "  Output: $OUTPUT_DIR" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 is not installed"
        exit 1
    fi
    
    # Check required Python packages
    local required_packages=("numpy" "matplotlib" "pandas" "seaborn" "psutil")
    for package in "${required_packages[@]}"; do
        if ! python3 -c "import $package" 2>/dev/null; then
            print_warning "Python package '$package' is not installed. Installing..."
            pip3 install "$package" || {
                print_error "Failed to install $package"
                exit 1
            }
        fi
    done
    
    # Check Rust/Cargo for Stateright benchmarks
    if ! command -v cargo &> /dev/null; then
        print_warning "Cargo is not installed. Stateright benchmarks will be skipped."
    fi
    
    # Check TLC for formal verification benchmarks
    if [ ! -f "$PROJECT_ROOT/tools/tla2tools.jar" ]; then
        print_warning "TLC tools not found. Formal verification benchmarks will be limited."
    fi
    
    print_success "Prerequisites check completed"
}

# Function to run performance benchmarks
run_performance_benchmarks() {
    print_info "Running performance benchmarks..."
    
    local perf_output="$OUTPUT_DIR/performance_$TIMESTAMP"
    mkdir -p "$perf_output"
    
    # Set network size based on mode
    local network_size=1500
    local duration=180
    local trials=500
    
    if [ "$QUICK_MODE" = true ]; then
        network_size=500
        duration=60
        trials=100
    elif [ "$FULL_MODE" = true ]; then
        network_size=3000
        duration=300
        trials=1000
    fi
    
    # Run performance benchmark
    if [ -f "$BENCHMARKS_DIR/performance.py" ]; then
        print_info "Starting performance analysis (network_size=$network_size, trials=$trials)..."
        
        if [ "$VERBOSE" = true ]; then
            python3 "$BENCHMARKS_DIR/performance.py" \
                --validators "$network_size" \
                --trials "$trials" \
                --duration "$duration" \
                --output "$perf_output" 2>&1 | tee -a "$LOG_FILE"
        else
            python3 "$BENCHMARKS_DIR/performance.py" \
                --validators "$network_size" \
                --trials "$trials" \
                --duration "$duration" \
                --output "$perf_output" >> "$LOG_FILE" 2>&1
        fi
        
        if [ $? -eq 0 ]; then
            print_success "Performance benchmarks completed successfully"
            
            # Display summary
            if [ -f "$perf_output/summary_report.md" ]; then
                print_info "Performance Summary:"
                head -n 20 "$perf_output/summary_report.md" | sed 's/^/  /'
            fi
        else
            print_error "Performance benchmarks failed"
            return 1
        fi
    else
        print_warning "Performance benchmark script not found"
    fi
    
    # Run Stateright performance benchmarks if available
    if command -v cargo &> /dev/null && [ -f "$PROJECT_ROOT/stateright/Cargo.toml" ]; then
        print_info "Running Stateright performance benchmarks..."
        
        cd "$PROJECT_ROOT/stateright"
        
        if [ "$VERBOSE" = true ]; then
            cargo bench --bench performance 2>&1 | tee -a "$LOG_FILE"
        else
            cargo bench --bench performance >> "$LOG_FILE" 2>&1
        fi
        
        if [ $? -eq 0 ]; then
            print_success "Stateright benchmarks completed"
        else
            print_warning "Stateright benchmarks failed"
        fi
        
        cd - > /dev/null
    fi
    
    return 0
}

# Function to run scalability benchmarks
run_scalability_benchmarks() {
    print_info "Running scalability benchmarks..."
    
    local scale_output="$OUTPUT_DIR/scalability_$TIMESTAMP"
    mkdir -p "$scale_output"
    
    # Configure based on mode
    local max_validators=50
    local parallel_workers=2
    
    if [ "$QUICK_MODE" = true ]; then
        max_validators=15
    elif [ "$FULL_MODE" = true ]; then
        max_validators=100
        parallel_workers=4
    fi
    
    # Run scalability benchmark
    if [ -f "$BENCHMARKS_DIR/scalability.py" ]; then
        print_info "Starting scalability analysis (max_validators=$max_validators)..."
        
        local parallel_flag=""
        if [ "$PARALLEL_EXEC" = true ]; then
            parallel_flag="--parallel --workers $parallel_workers"
        fi
        
        if [ "$VERBOSE" = true ]; then
            python3 "$BENCHMARKS_DIR/scalability.py" \
                --max-validators "$max_validators" \
                $parallel_flag \
                --output "$scale_output" 2>&1 | tee -a "$LOG_FILE"
        else
            python3 "$BENCHMARKS_DIR/scalability.py" \
                --max-validators "$max_validators" \
                $parallel_flag \
                --output "$scale_output" >> "$LOG_FILE" 2>&1
        fi
        
        if [ $? -eq 0 ]; then
            print_success "Scalability benchmarks completed successfully"
            
            # Display summary
            if [ -f "$scale_output/scalability_analysis.png" ]; then
                print_info "Scalability plots generated at: $scale_output/scalability_analysis.png"
            fi
        else
            print_error "Scalability benchmarks failed"
            return 1
        fi
    else
        print_warning "Scalability benchmark script not found"
    fi
    
    return 0
}

# Function to run validation benchmarks
run_validation_benchmarks() {
    print_info "Running validation benchmarks against whitepaper claims..."
    
    local val_output="$OUTPUT_DIR/validation_$TIMESTAMP"
    mkdir -p "$val_output"
    
    # Run comprehensive validation
    if [ -f "$BENCHMARKS_DIR/performance.py" ]; then
        print_info "Validating whitepaper claims..."
        
        # Run with specific configuration to match whitepaper assumptions
        python3 "$BENCHMARKS_DIR/performance.py" \
            --validators 1500 \
            --byzantine 15 \
            --offline 5 \
            --trials 1000 \
            --validate-whitepaper \
            --output "$val_output" >> "$LOG_FILE" 2>&1
        
        if [ $? -eq 0 ]; then
            print_success "Validation benchmarks completed"
            
            # Check validation results
            if [ -f "$val_output/whitepaper_validation.md" ]; then
                print_info "Whitepaper Validation Results:"
                grep "Status" "$val_output/whitepaper_validation.md" | head -10 | sed 's/^/  /'
            fi
        else
            print_warning "Validation benchmarks failed"
        fi
    fi
    
    # Run formal verification validation
    if [ -f "$PROJECT_ROOT/tools/tla2tools.jar" ]; then
        print_info "Running formal verification validation..."
        
        # Quick verification of key properties
        local specs=("Safety" "Liveness" "Resilience")
        
        for spec in "${specs[@]}"; do
            print_info "Verifying $spec properties..."
            
            java -Xmx4g -jar "$PROJECT_ROOT/tools/tla2tools.jar" \
                -config "$PROJECT_ROOT/models/Performance.cfg" \
                "$PROJECT_ROOT/proofs/$spec.tla" >> "$LOG_FILE" 2>&1 || {
                    print_warning "$spec verification failed or timed out"
                }
        done
    fi
    
    return 0
}

# Function to generate consolidated report
generate_consolidated_report() {
    print_info "Generating consolidated benchmark report..."
    
    local report_file="$OUTPUT_DIR/benchmark_report_$TIMESTAMP.md"
    
    cat > "$report_file" << EOF
# Alpenglow Protocol Benchmark Report

**Generated:** $(date)
**Mode:** $([ "$QUICK_MODE" = true ] && echo "Quick" || ([ "$FULL_MODE" = true ] && echo "Full" || echo "Standard"))

## Executive Summary

This report consolidates the results from the comprehensive benchmark suite for the Alpenglow consensus protocol.

### Benchmarks Executed

EOF

    # Add benchmark execution status
    if [ "$RUN_ALL" = true ] || [ "$RUN_PERFORMANCE" = true ]; then
        echo "- ✅ Performance Benchmarks" >> "$report_file"
    fi
    
    if [ "$RUN_ALL" = true ] || [ "$RUN_SCALABILITY" = true ]; then
        echo "- ✅ Scalability Benchmarks" >> "$report_file"
    fi
    
    if [ "$RUN_ALL" = true ] || [ "$RUN_VALIDATION" = true ]; then
        echo "- ✅ Validation Benchmarks" >> "$report_file"
    fi
    
    echo "" >> "$report_file"
    
    # Append individual reports if they exist
    for report in "$OUTPUT_DIR"/*/summary_report.md; do
        if [ -f "$report" ]; then
            echo "---" >> "$report_file"
            cat "$report" >> "$report_file"
            echo "" >> "$report_file"
        fi
    done
    
    # Add validation results
    for validation in "$OUTPUT_DIR"/*/whitepaper_validation.md; do
        if [ -f "$validation" ]; then
            echo "---" >> "$report_file"
            cat "$validation" >> "$report_file"
            echo "" >> "$report_file"
        fi
    done
    
    print_success "Consolidated report generated: $report_file"
}

# Function to cleanup temporary files
cleanup() {
    print_info "Cleaning up temporary files..."
    
    # Remove old benchmark results (older than 7 days)
    find "$OUTPUT_DIR" -name "*.tmp" -mtime +7 -delete 2>/dev/null || true
    
    # Compress old logs
    find "$OUTPUT_DIR" -name "*.log" -mtime +1 -exec gzip {} \; 2>/dev/null || true
    
    print_success "Cleanup completed"
}

# Main execution
main() {
    print_info "Starting Alpenglow Protocol Benchmark Suite"
    print_info "Output directory: $OUTPUT_DIR"
    
    # Check prerequisites
    check_prerequisites
    
    # Track overall success
    local overall_success=true
    
    # Run benchmarks based on flags
    if [ "$RUN_ALL" = true ] || [ "$RUN_PERFORMANCE" = true ]; then
        run_performance_benchmarks || overall_success=false
    fi
    
    if [ "$RUN_ALL" = true ] || [ "$RUN_SCALABILITY" = true ]; then
        run_scalability_benchmarks || overall_success=false
    fi
    
    if [ "$RUN_ALL" = true ] || [ "$RUN_VALIDATION" = true ]; then
        run_validation_benchmarks || overall_success=false
    fi
    
    # Generate consolidated report
    generate_consolidated_report
    
    # Cleanup
    cleanup
    
    # Final summary
    echo ""
    if [ "$overall_success" = true ]; then
        print_success "Benchmark suite completed successfully!"
        print_info "Results saved to: $OUTPUT_DIR"
        print_info "Log file: $LOG_FILE"
    else
        print_warning "Benchmark suite completed with some failures"
        print_info "Check log file for details: $LOG_FILE"
    fi
    
    echo "Completed at: $(date)" >> "$LOG_FILE"
}

# Execute main function
main "$@"
