#!/bin/bash

#############################################################################
# Real-time Monitoring Script for TLC Model Checking
#
# This script provides real-time monitoring and visualization of
# ongoing TLC model checking runs, including progress tracking,
# resource usage, and performance metrics.
#
# Usage: ./monitor.sh [PID or SESSION_DIR]
#############################################################################

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
UPDATE_INTERVAL=2  # seconds

# Parse arguments
TARGET="${1:-}"

if [ -z "$TARGET" ]; then
    echo "Usage: $0 [PID or SESSION_DIR]"
    echo "  PID: Process ID of running TLC"
    echo "  SESSION_DIR: Directory containing TLC output"
    exit 1
fi

# Helper functions
print_header() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${CYAN}         Alpenglow TLC Model Checking Monitor                  ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo
}

format_number() {
    printf "%'d" $1
}

format_time() {
    local seconds=$1
    printf "%02d:%02d:%02d" $((seconds/3600)) $((seconds%3600/60)) $((seconds%60))
}

get_progress_bar() {
    local current=$1
    local total=$2
    local width=30
    
    if [ "$total" -eq 0 ]; then
        local progress=0
    else
        local progress=$((current * width / total))
    fi
    
    printf "["
    for ((i=0; i<width; i++)); do
        if [ $i -lt $progress ]; then
            printf "█"
        else
            printf " "
        fi
    done
    printf "]"
}

# Monitor TLC process
monitor_process() {
    local PID=$1
    
    if ! ps -p $PID > /dev/null; then
        echo -e "${RED}Process $PID not found${NC}"
        exit 1
    fi
    
    # Find TLC output file
    local OUTPUT_FILE=$(lsof -p $PID 2>/dev/null | grep "\.log" | awk '{print $NF}' | head -1)
    
    if [ -z "$OUTPUT_FILE" ]; then
        echo -e "${YELLOW}Warning: Cannot find output file for PID $PID${NC}"
        OUTPUT_FILE="/tmp/tlc_monitor_$PID.log"
    fi
    
    echo "Monitoring PID: $PID"
    echo "Output file: $OUTPUT_FILE"
    
    monitor_output "$OUTPUT_FILE" "$PID"
}

# Monitor output file
monitor_output() {
    local OUTPUT_FILE=$1
    local PID=${2:-0}
    
    if [ ! -f "$OUTPUT_FILE" ]; then
        echo -e "${RED}Output file not found: $OUTPUT_FILE${NC}"
        exit 1
    fi
    
    local START_TIME=$(date +%s)
    local LAST_UPDATE=0
    
    while true; do
        print_header
        
        # Calculate runtime
        local CURRENT_TIME=$(date +%s)
        local RUNTIME=$((CURRENT_TIME - START_TIME))
        
        # Extract metrics from output
        local STATES_GENERATED=$(grep "states generated" "$OUTPUT_FILE" 2>/dev/null | tail -1 | grep -oE '[0-9]+' | head -1 || echo "0")
        local DISTINCT_STATES=$(grep "distinct states" "$OUTPUT_FILE" 2>/dev/null | tail -1 | grep -oE '[0-9]+' | head -1 || echo "0")
        local QUEUE_SIZE=$(grep "states on queue" "$OUTPUT_FILE" 2>/dev/null | tail -1 | grep -oE '[0-9]+' | head -1 || echo "0")
        local DEPTH=$(grep "search depth" "$OUTPUT_FILE" 2>/dev/null | tail -1 | grep -oE '[0-9]+' | head -1 || echo "0")
        
        # Calculate rates
        if [ $RUNTIME -gt 0 ]; then
            local STATES_PER_SEC=$((STATES_GENERATED / RUNTIME))
        else
            local STATES_PER_SEC=0
        fi
        
        # Check for errors
        local ERRORS=$(grep -c "Error:" "$OUTPUT_FILE" 2>/dev/null || echo "0")
        local WARNINGS=$(grep -c "Warning:" "$OUTPUT_FILE" 2>/dev/null || echo "0")
        
        # Display metrics
        echo -e "${CYAN}═══ Runtime ═══${NC}"
        echo -e "Elapsed: $(format_time $RUNTIME)"
        echo
        
        echo -e "${CYAN}═══ State Space ═══${NC}"
        echo -e "Generated:  $(format_number $STATES_GENERATED) states"
        echo -e "Distinct:   $(format_number $DISTINCT_STATES) states"
        echo -e "Queue:      $(format_number $QUEUE_SIZE) states"
        echo -e "Depth:      $DEPTH"
        echo -e "Rate:       $(format_number $STATES_PER_SEC) states/sec"
        echo
        
        # Progress estimation (rough)
        if [ $STATES_PER_SEC -gt 0 ] && [ $QUEUE_SIZE -gt 0 ]; then
            local EST_REMAINING=$((QUEUE_SIZE / STATES_PER_SEC))
            echo -e "${CYAN}═══ Progress ═══${NC}"
            echo -e "Estimated remaining: $(format_time $EST_REMAINING)"
            
            # Show progress bar
            local PROGRESS_PCT=$((DISTINCT_STATES * 100 / (DISTINCT_STATES + QUEUE_SIZE)))
            echo -n "Progress: "
            get_progress_bar $DISTINCT_STATES $((DISTINCT_STATES + QUEUE_SIZE))
            echo " ${PROGRESS_PCT}%"
            echo
        fi
        
        # System resources (if PID provided)
        if [ $PID -gt 0 ] && ps -p $PID > /dev/null 2>&1; then
            echo -e "${CYAN}═══ Resources ═══${NC}"
            
            # CPU usage
            local CPU=$(ps -p $PID -o %cpu= | tr -d ' ')
            echo -e "CPU:     ${CPU}%"
            
            # Memory usage
            local MEM=$(ps -p $PID -o rss= | awk '{printf "%.2f", $1/1024/1024}')
            echo -e "Memory:  ${MEM} GB"
            
            # Threads
            local THREADS=$(ps -p $PID -o nlwp= | tr -d ' ')
            echo -e "Threads: $THREADS"
            echo
        fi
        
        # Status indicators
        echo -e "${CYAN}═══ Status ═══${NC}"
        
        if [ $ERRORS -gt 0 ]; then
            echo -e "${RED}⚠ Errors: $ERRORS${NC}"
        else
            echo -e "${GREEN}✓ No errors${NC}"
        fi
        
        if [ $WARNINGS -gt 0 ]; then
            echo -e "${YELLOW}⚠ Warnings: $WARNINGS${NC}"
        fi
        
        # Check for completion
        if grep -q "Model checking completed" "$OUTPUT_FILE" 2>/dev/null; then
            echo
            echo -e "${GREEN}✓ Model checking completed!${NC}"
            
            # Show final results
            if grep -q "No error has been detected" "$OUTPUT_FILE" 2>/dev/null; then
                echo -e "${GREEN}✓ All properties satisfied${NC}"
            elif grep -q "Invariant .* is violated" "$OUTPUT_FILE" 2>/dev/null; then
                echo -e "${RED}✗ Invariant violation detected${NC}"
            elif grep -q "Temporal property .* is violated" "$OUTPUT_FILE" 2>/dev/null; then
                echo -e "${RED}✗ Temporal property violation detected${NC}"
            fi
            
            break
        fi
        
        # Check if process still running
        if [ $PID -gt 0 ] && ! ps -p $PID > /dev/null 2>&1; then
            echo
            echo -e "${YELLOW}Process terminated${NC}"
            break
        fi
        
        # Show last log lines
        echo
        echo -e "${CYAN}═══ Recent Output ═══${NC}"
        tail -5 "$OUTPUT_FILE" | sed 's/^/  /'
        
        # Update status
        echo
        echo -e "${CYAN}[Press Ctrl+C to stop monitoring]${NC}"
        
        sleep $UPDATE_INTERVAL
    done
}

# Monitor session directory
monitor_session() {
    local SESSION_DIR=$1
    
    if [ ! -d "$SESSION_DIR" ]; then
        echo -e "${RED}Session directory not found: $SESSION_DIR${NC}"
        exit 1
    fi
    
    # Find most recent TLC output
    local OUTPUT_FILE=$(find "$SESSION_DIR" -name "tlc_output.log" -o -name "*.log" | head -1)
    
    if [ -z "$OUTPUT_FILE" ]; then
        echo -e "${RED}No output files found in $SESSION_DIR${NC}"
        exit 1
    fi
    
    echo "Monitoring session: $SESSION_DIR"
    echo "Output file: $OUTPUT_FILE"
    
    monitor_output "$OUTPUT_FILE"
}

# Main execution
main() {
    # Determine target type
    if [[ "$TARGET" =~ ^[0-9]+$ ]]; then
        # It's a PID
        monitor_process "$TARGET"
    elif [ -d "$TARGET" ]; then
        # It's a directory
        monitor_session "$TARGET"
    elif [ -f "$TARGET" ]; then
        # It's a file
        monitor_output "$TARGET"
    else
        echo -e "${RED}Invalid target: $TARGET${NC}"
        echo "Target must be a PID, directory, or log file"
        exit 1
    fi
}

# Handle interrupts gracefully
trap 'echo -e "\n${YELLOW}Monitoring stopped${NC}"; exit 0' INT TERM

# Run main
main
