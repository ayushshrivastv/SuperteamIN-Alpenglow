#!/bin/bash
# Author: Ayush Srivastava
# Script to download and run TLC model checker

echo "Setting up TLC Model Checker..."

# Create tools directory if it doesn't exist
mkdir -p tools

# Check if TLA+ tools exist
if [ ! -f "tools/tla2tools.jar" ]; then
    echo "Downloading TLA+ tools..."
    curl -L -o tools/tla2tools.jar https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar
    if [ $? -ne 0 ]; then
        echo "Failed to download TLA+ tools"
        exit 1
    fi
fi

echo "Running TLC on Small configuration..."
echo "======================================="

# Run TLC with the Small configuration
java -cp tools/tla2tools.jar tlc2.TLC \
    -config models/Small.cfg \
    -workers auto \
    -cleanup \
    specs/Alpenglow.tla

echo ""
echo "TLC execution completed."
