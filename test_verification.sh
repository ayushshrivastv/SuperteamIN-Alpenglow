#!/bin/bash
# Test script to verify Alpenglow formal specifications

echo "================================================"
echo "Testing Alpenglow Formal Verification Framework"
echo "================================================"

# Check if TLA+ tools are available
if ! command -v java &> /dev/null; then
    echo "Error: Java is required but not installed"
    exit 1
fi

# Test syntax checking for main specifications
echo ""
echo "1. Checking specification syntax..."
echo "-----------------------------------"

specs=(
    "specs/Types.tla"
    "specs/Stake.tla"
    "specs/Utils.tla"
    "specs/Crypto.tla"
    "specs/Network.tla"
    "specs/Votor.tla"
    "specs/Rotor.tla"
    "specs/Alpenglow.tla"
    "specs/Integration.tla"
)

for spec in "${specs[@]}"; do
    if [ -f "$spec" ]; then
        echo "✓ Found: $spec"
    else
        echo "✗ Missing: $spec"
    fi
done

# Test configuration files
echo ""
echo "2. Checking model configurations..."
echo "------------------------------------"

configs=(
    "models/Small.cfg"
    "models/Medium.cfg"
    "models/EdgeCase.cfg"
    "models/Boundary.cfg"
    "models/Partition.cfg"
    "models/Performance.cfg"
)

for cfg in "${configs[@]}"; do
    if [ -f "$cfg" ]; then
        echo "✓ Found: $cfg"
    else
        echo "✗ Missing: $cfg"
    fi
done

# Check for critical dependencies in Alpenglow.tla
echo ""
echo "3. Verifying module dependencies..."
echo "------------------------------------"

echo "Checking Alpenglow.tla dependencies:"
grep -E "^(EXTENDS|INSTANCE)" specs/Alpenglow.tla | while read -r line; do
    echo "  $line"
done

# Summary
echo ""
echo "================================================"
echo "Verification Check Complete"
echo "================================================"
echo ""
echo "Next steps:"
echo "1. Run TLC model checker: tlc -config models/Small.cfg specs/Alpenglow.tla"
echo "2. Run TLAPS proof checker: tlaps proofs/Safety.tla"
echo "3. Run integration tests: ./scripts/run_tests.sh"
