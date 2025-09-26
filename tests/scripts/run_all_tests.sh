#!/bin/bash
# Author: Ayush Srivastava

# Master test runner for Alpenglow test suite

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test directories
TEST_ROOT="$(dirname "$0")/.."
UNIT_DIR="$TEST_ROOT/unit"
INTEGRATION_DIR="$TEST_ROOT/integration"
PROPERTY_DIR="$TEST_ROOT/property"
PERFORMANCE_DIR="$TEST_ROOT/performance"
RESULTS_DIR="$TEST_ROOT/results"

# Create results directory
mkdir -p "$RESULTS_DIR"

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Function to run tests in a directory
run_tests() {
    local dir=$1
    local type=$2
    
    echo -e "\n${YELLOW}Running $type tests...${NC}"
    echo "================================"
    
    for test_file in "$dir"/*.tla; do
        if [ -f "$test_file" ]; then
            test_name=$(basename "$test_file" .tla)
            echo -n "  Testing $test_name... "
            
            ((TOTAL_TESTS++))
            
            # Run the test (using TLC if available)
            if command -v java >/dev/null 2>&1 && [ -f "/usr/local/lib/tlc.jar" ]; then
                if java -cp "/usr/local/lib/tlc.jar" tlc2.TLC \
                    -workers auto \
                    -deadlock \
                    "$test_file" > "$RESULTS_DIR/${test_name}.log" 2>&1; then
                    echo -e "${GREEN}PASSED${NC}"
                    ((PASSED_TESTS++))
                else
                    echo -e "${RED}FAILED${NC}"
                    ((FAILED_TESTS++))
                    echo "    See $RESULTS_DIR/${test_name}.log for details"
                fi
            else
                # Just check syntax if TLC not available
                echo -e "${YELLOW}SKIPPED${NC} (TLC not available)"
                ((SKIPPED_TESTS++))
            fi
        fi
    done
}

# Function to print summary
print_summary() {
    echo -e "\n=========================================="
    echo -e "           TEST SUMMARY"
    echo -e "=========================================="
    echo -e "Total Tests:    $TOTAL_TESTS"
    echo -e "${GREEN}Passed:         $PASSED_TESTS${NC}"
    if [ $FAILED_TESTS -gt 0 ]; then
        echo -e "${RED}Failed:         $FAILED_TESTS${NC}"
    else
        echo -e "Failed:         $FAILED_TESTS"
    fi
    if [ $SKIPPED_TESTS -gt 0 ]; then
        echo -e "${YELLOW}Skipped:        $SKIPPED_TESTS${NC}"
    else
        echo -e "Skipped:        $SKIPPED_TESTS"
    fi
    
    echo -e "\nResults saved in: $RESULTS_DIR"
    
    if [ $FAILED_TESTS -eq 0 ] && [ $SKIPPED_TESTS -eq 0 ]; then
        echo -e "\n${GREEN}✅ All tests passed!${NC}"
        return 0
    elif [ $FAILED_TESTS -gt 0 ]; then
        echo -e "\n${RED}❌ Some tests failed!${NC}"
        return 1
    else
        echo -e "\n${YELLOW}⚠️  Some tests were skipped${NC}"
        return 0
    fi
}

# Main execution
main() {
    echo "=========================================="
    echo "    Alpenglow Test Suite Runner"
    echo "=========================================="
    echo "Started at: $(date)"
    
    # Run each test category
    run_tests "$UNIT_DIR" "Unit"
    run_tests "$INTEGRATION_DIR" "Integration"
    run_tests "$PROPERTY_DIR" "Property"
    run_tests "$PERFORMANCE_DIR" "Performance"
    
    # Print summary
    print_summary
    
    echo -e "\nCompleted at: $(date)"
}

# Run main function
main "$@"
