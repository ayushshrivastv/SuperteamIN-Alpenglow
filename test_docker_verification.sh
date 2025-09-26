#!/bin/bash

echo "🐳 Testing Alpenglow Docker Verification Environment"
echo "=================================================="

# Test 1: Basic container functionality
echo "📋 Test 1: Container starts successfully"
if docker run --rm alpenglow-verification:latest echo "Container works!"; then
    echo "✅ PASS: Container starts and runs"
else
    echo "❌ FAIL: Container startup issue"
    exit 1
fi

# Test 2: Java environment
echo ""
echo "📋 Test 2: Java environment"
if docker run --rm alpenglow-verification:latest java -version 2>&1 | grep -q "openjdk"; then
    echo "✅ PASS: Java installed and working"
else
    echo "❌ FAIL: Java environment issue"
fi

# Test 3: Rust environment  
echo ""
echo "📋 Test 3: Rust environment"
if docker run --rm alpenglow-verification:latest rustc --version | grep -q "rustc"; then
    echo "✅ PASS: Rust installed and working"
else
    echo "❌ FAIL: Rust environment issue"
fi

# Test 4: TLA+ tools
echo ""
echo "📋 Test 4: TLA+ tools availability"
if docker run --rm alpenglow-verification:latest ls -la /opt/tla2tools.jar | grep -q "tla2tools.jar"; then
    echo "✅ PASS: TLA+ tools available"
else
    echo "❌ FAIL: TLA+ tools missing"
fi

# Test 5: Project files
echo ""
echo "📋 Test 5: Project files copied correctly"
TLA_COUNT=$(docker run --rm alpenglow-verification:latest find . -name "*.tla" | wc -l)
if [ "$TLA_COUNT" -gt 10 ]; then
    echo "✅ PASS: Project files copied ($TLA_COUNT TLA+ files found)"
else
    echo "❌ FAIL: Project files missing or incomplete"
fi

# Test 6: Verification scripts
echo ""
echo "📋 Test 6: Verification scripts executable"
if docker run --rm alpenglow-verification:latest test -x /home/verifier/alpenglow-verification/verify_environment.sh; then
    echo "✅ PASS: Verification scripts ready"
else
    echo "❌ FAIL: Verification scripts missing or not executable"
fi

# Test 7: Quick verification demo
echo ""
echo "📋 Test 7: Quick verification demo"
echo "Running verification demo in container..."
docker run --rm alpenglow-verification:latest /home/verifier/alpenglow-verification/run_verification_demo.sh > /tmp/docker_demo_output.log 2>&1

if grep -q "Verification demo complete" /tmp/docker_demo_output.log; then
    echo "✅ PASS: Verification demo runs successfully"
    echo "Demo output preview:"
    head -10 /tmp/docker_demo_output.log | sed 's/^/    /'
else
    echo "❌ FAIL: Verification demo issues"
    echo "Error output:"
    cat /tmp/docker_demo_output.log | tail -10 | sed 's/^/    /'
fi

echo ""
echo "🎯 Docker Environment Test Complete!"
echo "Ready for video demonstration? $(docker run --rm alpenglow-verification:latest echo 'YES!' 2>/dev/null || echo 'Check issues above')"
