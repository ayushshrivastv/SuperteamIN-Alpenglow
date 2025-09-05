#!/bin/bash

#############################################################################
# Cleanup Script for Alpenglow Verification Project
#
# This script removes temporary files, old results, and cache files
# while preserving important specifications and proofs.
#
# Usage: ./clean.sh [OPTIONS]
#   --all       Remove all generated files including results
#   --cache     Remove only cache and temporary files
#   --results   Remove only old results (keep latest)
#   --confirm   Skip confirmation prompt
#############################################################################

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$PROJECT_DIR/results"
REPORTS_DIR="$PROJECT_DIR/reports"

# Default options
CLEAN_MODE="cache"
SKIP_CONFIRM=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            CLEAN_MODE="all"
            shift
            ;;
        --cache)
            CLEAN_MODE="cache"
            shift
            ;;
        --results)
            CLEAN_MODE="results"
            shift
            ;;
        --confirm)
            SKIP_CONFIRM=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--all|--cache|--results] [--confirm]"
            exit 1
            ;;
    esac
done

# Helper functions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

get_size() {
    local path=$1
    if [ -d "$path" ]; then
        du -sh "$path" 2>/dev/null | cut -f1
    else
        echo "0"
    fi
}

# Calculate sizes
calculate_sizes() {
    print_info "Calculating sizes..."
    
    CACHE_SIZE=0
    RESULTS_SIZE=0
    REPORTS_SIZE=0
    
    # Find all cache files
    CACHE_FILES=(
        $(find "$PROJECT_DIR" -name "*.tlacov" 2>/dev/null || true)
        $(find "$PROJECT_DIR" -name "states" -type d 2>/dev/null || true)
        $(find "$PROJECT_DIR" -name "*.old" 2>/dev/null || true)
        $(find "$PROJECT_DIR" -name "*.bak" 2>/dev/null || true)
        $(find "$PROJECT_DIR" -name ".DS_Store" 2>/dev/null || true)
        $(find "$PROJECT_DIR" -name "*.pyc" 2>/dev/null || true)
        $(find "$PROJECT_DIR" -name "__pycache__" -type d 2>/dev/null || true)
        $(find "$PROJECT_DIR" -name "*.swp" 2>/dev/null || true)
        $(find "$PROJECT_DIR" -name "*~" 2>/dev/null || true)
    )
    
    if [ -d "$RESULTS_DIR" ]; then
        RESULTS_SIZE=$(get_size "$RESULTS_DIR")
    fi
    
    if [ -d "$REPORTS_DIR" ]; then
        REPORTS_SIZE=$(get_size "$REPORTS_DIR")
    fi
    
    # Calculate cache size
    for file in "${CACHE_FILES[@]}"; do
        if [ -e "$file" ]; then
            size=$(du -sk "$file" 2>/dev/null | cut -f1)
            CACHE_SIZE=$((CACHE_SIZE + size))
        fi
    done
    CACHE_SIZE=$((CACHE_SIZE / 1024))  # Convert to MB
    
    echo
    echo "Space usage:"
    echo "  Cache files:  ${CACHE_SIZE} MB"
    echo "  Results:      $RESULTS_SIZE"
    echo "  Reports:      $REPORTS_SIZE"
    echo
}

# Clean cache files
clean_cache() {
    print_info "Cleaning cache and temporary files..."
    
    local count=0
    
    # Remove TLA+ coverage files
    find "$PROJECT_DIR" -name "*.tlacov" -delete 2>/dev/null && count=$((count + $(find "$PROJECT_DIR" -name "*.tlacov" 2>/dev/null | wc -l))) || true
    
    # Remove state directories
    find "$PROJECT_DIR" -name "states" -type d -exec rm -rf {} + 2>/dev/null && count=$((count + 1)) || true
    
    # Remove backup files
    find "$PROJECT_DIR" -name "*.old" -delete 2>/dev/null && count=$((count + $(find "$PROJECT_DIR" -name "*.old" 2>/dev/null | wc -l))) || true
    find "$PROJECT_DIR" -name "*.bak" -delete 2>/dev/null && count=$((count + $(find "$PROJECT_DIR" -name "*.bak" 2>/dev/null | wc -l))) || true
    
    # Remove OS files
    find "$PROJECT_DIR" -name ".DS_Store" -delete 2>/dev/null && count=$((count + $(find "$PROJECT_DIR" -name ".DS_Store" 2>/dev/null | wc -l))) || true
    find "$PROJECT_DIR" -name "Thumbs.db" -delete 2>/dev/null && count=$((count + $(find "$PROJECT_DIR" -name "Thumbs.db" 2>/dev/null | wc -l))) || true
    
    # Remove Python cache
    find "$PROJECT_DIR" -name "*.pyc" -delete 2>/dev/null && count=$((count + $(find "$PROJECT_DIR" -name "*.pyc" 2>/dev/null | wc -l))) || true
    find "$PROJECT_DIR" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null && count=$((count + 1)) || true
    
    # Remove editor swap files
    find "$PROJECT_DIR" -name "*.swp" -delete 2>/dev/null && count=$((count + $(find "$PROJECT_DIR" -name "*.swp" 2>/dev/null | wc -l))) || true
    find "$PROJECT_DIR" -name "*~" -delete 2>/dev/null && count=$((count + $(find "$PROJECT_DIR" -name "*~" 2>/dev/null | wc -l))) || true
    
    # Remove empty directories
    find "$PROJECT_DIR" -type d -empty -delete 2>/dev/null || true
    
    print_info "Removed $count cache files"
}

# Clean results
clean_results() {
    print_info "Cleaning old results..."
    
    if [ ! -d "$RESULTS_DIR" ]; then
        print_info "No results directory found"
        return
    fi
    
    # Keep only the 5 most recent results
    local KEEP_COUNT=5
    local TOTAL_COUNT=$(ls -1 "$RESULTS_DIR" 2>/dev/null | wc -l)
    
    if [ $TOTAL_COUNT -le $KEEP_COUNT ]; then
        print_info "Only $TOTAL_COUNT results found, keeping all"
        return
    fi
    
    local DELETE_COUNT=$((TOTAL_COUNT - KEEP_COUNT))
    print_warn "Removing $DELETE_COUNT old result directories"
    
    # Delete oldest results
    ls -1t "$RESULTS_DIR" | tail -n $DELETE_COUNT | while read dir; do
        rm -rf "$RESULTS_DIR/$dir"
        echo "  Removed: $dir"
    done
    
    print_info "Kept $KEEP_COUNT most recent results"
}

# Clean all
clean_all() {
    print_info "Cleaning all generated files..."
    
    # Clean cache first
    clean_cache
    
    # Remove all results
    if [ -d "$RESULTS_DIR" ]; then
        print_warn "Removing all results..."
        rm -rf "$RESULTS_DIR"
        print_info "Results directory removed"
    fi
    
    # Remove all reports
    if [ -d "$REPORTS_DIR" ]; then
        print_warn "Removing all reports..."
        rm -rf "$REPORTS_DIR"
        print_info "Reports directory removed"
    fi
    
    # Remove any generated documentation
    find "$PROJECT_DIR/docs" -name "*.pdf" -delete 2>/dev/null || true
    find "$PROJECT_DIR/docs" -name "*.html" -delete 2>/dev/null || true
    
    print_info "All generated files removed"
}

# Confirm action
confirm_action() {
    if [ "$SKIP_CONFIRM" == true ]; then
        return 0
    fi
    
    local message=$1
    echo -e "${YELLOW}$message${NC}"
    echo -n "Continue? [y/N]: "
    read -r response
    
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Show what will be cleaned
preview_clean() {
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Cleanup Preview${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo
    
    case "$CLEAN_MODE" in
        cache)
            echo "Will remove:"
            echo "  • TLA+ coverage files (*.tlacov)"
            echo "  • State directories"
            echo "  • Backup files (*.bak, *.old)"
            echo "  • OS cache files (.DS_Store)"
            echo "  • Python cache (__pycache__, *.pyc)"
            echo "  • Editor swap files (*.swp, *~)"
            echo "  • Empty directories"
            ;;
        results)
            echo "Will remove:"
            echo "  • Old verification results (keeping 5 most recent)"
            echo "  • Cache files"
            ;;
        all)
            echo "Will remove:"
            echo "  • All cache and temporary files"
            echo "  • All verification results"
            echo "  • All generated reports"
            echo "  • Generated documentation"
            echo
            echo -e "${YELLOW}⚠ Warning: This will remove ALL generated content${NC}"
            ;;
    esac
    echo
}

# Main execution
main() {
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Alpenglow Cleanup Utility${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo
    
    # Calculate current sizes
    calculate_sizes
    
    # Show preview
    preview_clean
    
    # Confirm action
    case "$CLEAN_MODE" in
        cache)
            if confirm_action "Remove cache and temporary files?"; then
                clean_cache
            else
                print_info "Cleanup cancelled"
                exit 0
            fi
            ;;
        results)
            if confirm_action "Remove old results?"; then
                clean_cache
                clean_results
            else
                print_info "Cleanup cancelled"
                exit 0
            fi
            ;;
        all)
            if confirm_action "Remove ALL generated files?"; then
                clean_all
            else
                print_info "Cleanup cancelled"
                exit 0
            fi
            ;;
    esac
    
    # Show space freed
    echo
    print_info "Cleanup complete!"
    
    # Recalculate sizes
    NEW_CACHE_SIZE=0
    NEW_CACHE_FILES=($(find "$PROJECT_DIR" -name "*.tlacov" -o -name "states" -type d 2>/dev/null || true))
    for file in "${NEW_CACHE_FILES[@]}"; do
        if [ -e "$file" ]; then
            size=$(du -sk "$file" 2>/dev/null | cut -f1)
            NEW_CACHE_SIZE=$((NEW_CACHE_SIZE + size))
        fi
    done
    NEW_CACHE_SIZE=$((NEW_CACHE_SIZE / 1024))
    
    FREED=$((CACHE_SIZE - NEW_CACHE_SIZE))
    if [ $FREED -gt 0 ]; then
        print_info "Space freed: ${FREED} MB"
    fi
}

# Run main
main
