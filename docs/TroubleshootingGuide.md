# Alpenglow Mathematical Theorem Verifier - Troubleshooting Guide

## Table of Contents

1. [Quick Start Troubleshooting](#quick-start-troubleshooting)
2. [Common Issues and Solutions](#common-issues-and-solutions)
3. [Systematic Debugging Procedures](#systematic-debugging-procedures)
4. [Tool-Specific Guidance](#tool-specific-guidance)
5. [Error Code Reference](#error-code-reference)
6. [Performance Optimization](#performance-optimization)
7. [Log File Analysis](#log-file-analysis)
8. [Recovery Procedures](#recovery-procedures)
9. [Best Practices](#best-practices)
10. [Advanced Troubleshooting](#advanced-troubleshooting)

---

## Quick Start Troubleshooting

### 🚨 Emergency Checklist

If the verification system is completely failing, check these items first:

1. **Environment Check**
   ```bash
   # Verify all required tools are installed
   java -version
   tlc -help
   tlapm --version
   cargo --version
   ```

2. **Permission Check**
   ```bash
   # Ensure scripts are executable
   chmod +x ./scripts/dev/localverify.sh
   chmod +x ./submission/run_complete_verification.sh
   ```

3. **Clean State**
   ```bash
   # Remove any corrupted state
   rm -rf ./submission/verification_results/
   cd stateright && cargo clean
   ```

4. **Basic Syntax Check**
   ```bash
   # Quick TLA+ syntax validation
   tlc -parse specs/Alpenglow.tla
   ```

### 🎯 Most Common Issues (90% of problems)

| Issue | Quick Fix | Section |
|-------|-----------|---------|
| `./scripts/dev/localverify.sh` not found | Use `./submission/run_complete_verification.sh` instead | [Missing Scripts](#missing-scripts) |
| Rust type mismatch errors | Check `BlockHash` type usage in tests | [Rust Type Mismatches](#rust-type-mismatches) |
| TLC exit code 255 | Check Java memory settings and TLA+ syntax | [TLC Failures](#tlc-model-checking-failures) |
| Permission denied | Run `chmod +x` on script files | [Environment Issues](#environment-setup-issues) |
| Out of memory | Reduce model parameters or increase heap size | [Memory Issues](#memory-and-resource-issues) |

---

## Common Issues and Solutions

### Missing Scripts

**Problem**: User tries to run `./scripts/dev/localverify.sh` but it doesn't exist.

**Solution**:
```bash
# Use the main verification script instead
./submission/run_complete_verification.sh

# Or create the missing script structure
mkdir -p scripts/dev
# Then create localverify.sh as a wrapper to the main script
```

**Root Cause**: The documentation references a script that hasn't been created yet.

**Prevention**: Always verify script paths in documentation match actual file structure.

### Rust Type Mismatches

**Problem**: Compilation errors like:
```
error[E0308]: mismatched types
expected `u64`, found `[u8; 32]`
```

**Common Locations**:
- `stateright/src/rotor.rs` lines 2558, 2591, 2638
- Test functions using `ErasureBlock::new()` and `Shred::new_data()`

**Solution**:
```rust
// ❌ Wrong - using byte arrays
ErasureBlock::new([1u8; 32], 1, 0, vec![1, 2, 3, 4, 5, 6, 7, 8], 2, 3)
Shred::new_data([1u8; 32], 1, 1, vec![1, 2, 3])

// ✅ Correct - using u64
ErasureBlock::new(1u64, 1, 0, vec![1, 2, 3, 4, 5, 6, 7, 8], 2, 3)
Shred::new_data(1u64, 1, 1, vec![1, 2, 3])
```

**Root Cause**: `BlockHash` is defined as `u64` in `stateright/src/lib.rs`, but some tests use `[u8; 32]`.

**Prevention**: Use consistent type definitions and run `cargo check` frequently.

### TLC Model Checking Failures

**Problem**: TLC exits with code 255 or reports parsing errors.

**Common Symptoms**:
- "TLC encountered an error"
- "Parse error in specification"
- "Java heap space" errors
- "Deadlock detected"

**Solutions**:

1. **Memory Issues**:
   ```bash
   # Increase Java heap size
   export JAVA_OPTS="-Xmx8g -Xms4g"
   tlc -config models/WhitepaperValidation.cfg specs/Alpenglow.tla
   ```

2. **Syntax Errors**:
   ```bash
   # Check syntax first
   tlc -parse specs/Alpenglow.tla
   tlc -parse specs/Types.tla
   ```

3. **Configuration Issues**:
   ```tla
   \* Check your .cfg file has proper format
   SPECIFICATION Alpenglow
   CONSTANTS
       N = 4
       F = 1
   INVARIANT TypeInvariant
   ```

4. **Deadlock Issues**:
   ```bash
   # Run with deadlock detection disabled for debugging
   tlc -deadlock -config models/WhitepaperValidation.cfg specs/Alpenglow.tla
   ```

### Environment Setup Issues

**Problem**: Tools not found or wrong versions.

**Diagnosis**:
```bash
# Check tool availability and versions
which java && java -version
which tlc && tlc -help | head -5
which tlapm && tlapm --version
which cargo && cargo --version
echo $JAVA_HOME
echo $PATH
```

**Solutions**:

1. **Java Issues**:
   ```bash
   # Install OpenJDK 11 or later
   sudo apt-get install openjdk-11-jdk  # Ubuntu/Debian
   brew install openjdk@11              # macOS
   
   # Set JAVA_HOME
   export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
   ```

2. **TLA+ Tools**:
   ```bash
   # Download and install TLA+ tools
   wget https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar
   echo 'alias tlc="java -cp /path/to/tla2tools.jar tlc2.TLC"' >> ~/.bashrc
   
   # Install TLAPS
   # Follow instructions at https://tla.msr-inria.inria.fr/tlaps/content/Download/Source.html
   ```

3. **Rust/Cargo**:
   ```bash
   # Install Rust
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   source ~/.cargo/env
   ```

### Memory and Resource Issues

**Problem**: Verification runs out of memory or takes too long.

**Symptoms**:
- "Java heap space" errors
- Process killed by OS
- Verification hangs indefinitely

**Solutions**:

1. **Increase Memory Limits**:
   ```bash
   # For TLC
   export JAVA_OPTS="-Xmx16g -Xms8g"
   
   # For Rust compilation
   export CARGO_BUILD_JOBS=2  # Reduce parallel jobs
   ```

2. **Reduce Model Complexity**:
   ```tla
   \* In your .cfg file, use smaller constants
   CONSTANTS
       N = 3          \* Instead of 10
       F = 1          \* Instead of 3
       MaxSlot = 5    \* Instead of 100
   ```

3. **Use Incremental Verification**:
   ```bash
   # Verify components separately
   ./scripts/dev/quick_test.sh           # Fast syntax checks
   ./scripts/dev/debug_verification.sh   # Individual components
   ```

---

## Systematic Debugging Procedures

### Step-by-Step Diagnosis

#### Phase 1: Environment Validation

1. **Check Tool Availability**:
   ```bash
   echo "=== Tool Check ==="
   java -version 2>&1 | head -1
   tlc -help 2>&1 | head -1
   tlapm --version 2>&1 | head -1
   cargo --version 2>&1 | head -1
   echo "=== End Tool Check ==="
   ```

2. **Verify File Structure**:
   ```bash
   echo "=== File Structure Check ==="
   ls -la specs/
   ls -la proofs/
   ls -la models/
   ls -la stateright/src/
   echo "=== End File Structure Check ==="
   ```

3. **Test Basic Functionality**:
   ```bash
   echo "=== Basic Functionality Test ==="
   tlc -parse specs/Alpenglow.tla
   cd stateright && cargo check --lib
   echo "=== End Basic Functionality Test ==="
   ```

#### Phase 2: Component Isolation

1. **TLA+ Specifications**:
   ```bash
   # Test each specification individually
   for spec in specs/*.tla; do
       echo "Testing $spec..."
       tlc -parse "$spec" || echo "FAILED: $spec"
   done
   ```

2. **Rust Components**:
   ```bash
   # Test Rust compilation step by step
   cd stateright
   cargo check --lib                    # Library only
   cargo test --lib --no-run           # Compile tests
   cargo test test_erasure_encoding    # Specific test
   ```

3. **Model Configurations**:
   ```bash
   # Test each model configuration
   for cfg in models/*.cfg; do
       echo "Testing $cfg..."
       timeout 60 tlc -config "$cfg" specs/Alpenglow.tla || echo "FAILED: $cfg"
   done
   ```

#### Phase 3: Integration Testing

1. **Cross-Component Validation**:
   ```bash
   # Test TLA+ to Rust integration
   cd stateright
   cargo test --test integration_tests
   
   # Test model checking with Rust state
   cargo run --example tla_export
   ```

2. **End-to-End Verification**:
   ```bash
   # Run minimal verification
   ./submission/run_complete_verification.sh --skip-performance --timeout-proofs 300
   ```

### Debugging Decision Tree

```
Verification Failure
├── Environment Issues?
│   ├── Tools Missing → Install required tools
│   ├── Wrong Versions → Update to compatible versions
│   └── Permissions → Fix file permissions
├── Compilation Errors?
│   ├── Rust Type Errors → Fix type mismatches
│   ├── TLA+ Syntax → Check specification syntax
│   └── Missing Dependencies → Install/update dependencies
├── Runtime Failures?
│   ├── Memory Issues → Increase limits or reduce complexity
│   ├── Timeout → Increase timeouts or optimize
│   └── Logic Errors → Review algorithm implementation
└── Integration Issues?
    ├── TLA+/Rust Mismatch → Verify state correspondence
    ├── Configuration → Check model parameters
    └── Data Format → Validate serialization/deserialization
```

---

## Tool-Specific Guidance

### TLA+ and TLC Troubleshooting

#### Common TLA+ Issues

1. **Syntax Errors**:
   ```tla
   \* ❌ Common mistakes
   VARIABLE x, y, z,  \* Trailing comma
   
   \* ✅ Correct syntax
   VARIABLES x, y, z
   ```

2. **Type Errors**:
   ```tla
   \* ❌ Type mismatch
   x' = x + "string"
   
   \* ✅ Consistent types
   x' = x + 1
   ```

3. **Infinite State Space**:
   ```tla
   \* ❌ Unbounded
   Next == x' = x + 1
   
   \* ✅ Bounded
   Next == x' = IF x < 100 THEN x + 1 ELSE x
   ```

#### TLC Configuration Best Practices

1. **Memory Management**:
   ```bash
   # Set appropriate heap size
   export JAVA_OPTS="-Xmx8g -Xms4g -XX:+UseG1GC"
   ```

2. **Worker Configuration**:
   ```bash
   # Use appropriate number of workers
   tlc -workers $(nproc) -config model.cfg spec.tla
   ```

3. **Checkpoint Management**:
   ```bash
   # Enable checkpointing for long runs
   tlc -checkpoint 60 -config model.cfg spec.tla
   ```

#### TLAPS Proof Verification

1. **Backend Selection**:
   ```bash
   # Try different proof backends
   tlapm --method zenon proof.tla
   tlapm --method ls4 proof.tla
   tlapm --method smt proof.tla
   ```

2. **Timeout Management**:
   ```bash
   # Increase timeout for complex proofs
   tlapm --timeout 300 proof.tla
   ```

3. **Incremental Verification**:
   ```bash
   # Verify specific theorems
   tlapm --prove-only "TheoremName" proof.tla
   ```

### Rust and Stateright Troubleshooting

#### Common Rust Issues

1. **Borrow Checker Errors**:
   ```rust
   // ❌ Borrow checker issue
   let state = &mut self.state;
   let result = state.method1();
   state.method2(); // Error: already borrowed
   
   // ✅ Proper borrowing
   let result = self.state.method1();
   self.state.method2();
   ```

2. **Lifetime Issues**:
   ```rust
   // ❌ Lifetime error
   fn get_data(&self) -> &str {
       let temp = String::new();
       &temp // Error: doesn't live long enough
   }
   
   // ✅ Return owned data
   fn get_data(&self) -> String {
       String::new()
   }
   ```

3. **Type Conversion**:
   ```rust
   // ❌ Type mismatch
   let hash: [u8; 32] = 42; // Error
   
   // ✅ Proper conversion
   let hash: u64 = 42;
   // or
   let hash: [u8; 32] = [0; 32];
   ```

#### Stateright Debugging

1. **Actor State Issues**:
   ```rust
   // Enable debug logging
   env_logger::init();
   
   // Use debug assertions
   debug_assert!(state.is_valid());
   
   // Add tracing
   tracing::info!("State transition: {:?}", state);
   ```

2. **Message Handling**:
   ```rust
   // Validate message types
   match msg {
       Message::Valid(data) => { /* handle */ },
       _ => {
           eprintln!("Unexpected message: {:?}", msg);
           return;
       }
   }
   ```

3. **Property Verification**:
   ```rust
   // Add property checks
   impl Verifiable for MyState {
       fn verify(&self) -> Result<(), Error> {
           if !self.invariant_holds() {
               return Err(Error::InvariantViolation);
           }
           Ok(())
       }
   }
   ```

### Environment and Integration

#### Docker Environment

1. **Container Setup**:
   ```dockerfile
   FROM ubuntu:20.04
   RUN apt-get update && apt-get install -y \
       openjdk-11-jdk \
       curl \
       build-essential
   
   # Install Rust
   RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
   
   # Install TLA+ tools
   COPY tla2tools.jar /opt/tla2tools.jar
   RUN echo 'alias tlc="java -cp /opt/tla2tools.jar tlc2.TLC"' >> ~/.bashrc
   ```

2. **Volume Mounting**:
   ```bash
   docker run -v $(pwd):/workspace -w /workspace verification-env \
       ./submission/run_complete_verification.sh
   ```

#### CI/CD Integration

1. **GitHub Actions**:
   ```yaml
   name: Verification
   on: [push, pull_request]
   jobs:
     verify:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v2
         - name: Setup Java
           uses: actions/setup-java@v2
           with:
             java-version: '11'
         - name: Setup Rust
           uses: actions-rs/toolchain@v1
           with:
             toolchain: stable
         - name: Run Verification
           run: ./submission/run_complete_verification.sh
   ```

---

## Error Code Reference

### TLC Error Codes

| Code | Description | Common Causes | Solution |
|------|-------------|---------------|----------|
| 255 | General TLC Error | Syntax error, memory issue, invalid config | Check syntax, increase memory |
| 12 | Deadlock detected | Model has deadlock states | Add fairness conditions or fix logic |
| 13 | Invariant violation | Safety property violated | Review model logic |
| 75 | Parse error | TLA+ syntax error | Fix specification syntax |
| 150 | Out of memory | Insufficient heap space | Increase `-Xmx` setting |

### Rust Error Codes

| Error | Description | Common Causes | Solution |
|-------|-------------|---------------|----------|
| E0308 | Type mismatch | Wrong type used | Fix type annotations |
| E0382 | Use after move | Value moved | Use references or clone |
| E0502 | Cannot borrow | Borrowing conflict | Restructure borrows |
| E0277 | Trait not implemented | Missing trait impl | Implement required trait |
| E0425 | Cannot find value | Undefined variable | Define variable or import |

### Custom Error Codes

| Code | Component | Description | Solution |
|------|-----------|-------------|----------|
| ALP001 | Rotor | Non-equivocation violation | Check shred history |
| ALP002 | Consensus | Invalid block proposal | Verify proposer and slot |
| ALP003 | Network | Bandwidth limit exceeded | Reduce message size |
| ALP004 | Verification | TLA+ state mismatch | Sync state representations |
| ALP005 | Config | Invalid parameters | Check configuration values |

### Exit Codes

| Code | Meaning | Action |
|------|---------|--------|
| 0 | Success | Continue |
| 1 | General failure | Check logs |
| 2 | Configuration error | Fix config |
| 130 | Interrupted by user | Restart if needed |
| 137 | Killed (out of memory) | Increase memory |
| 139 | Segmentation fault | Check for bugs |

---

## Performance Optimization

### Memory Optimization

1. **TLC Memory Tuning**:
   ```bash
   # For large models
   export JAVA_OPTS="-Xmx32g -Xms16g -XX:+UseG1GC -XX:MaxGCPauseMillis=200"
   
   # For memory-constrained systems
   export JAVA_OPTS="-Xmx4g -Xms2g -XX:+UseSerialGC"
   ```

2. **Rust Memory Management**:
   ```rust
   // Use Box for large structures
   struct LargeState {
       data: Box<[u8; 1000000]>,
   }
   
   // Prefer iterators over collections
   let result: Vec<_> = items.iter()
       .filter(|x| x.is_valid())
       .collect();
   ```

3. **Model Size Reduction**:
   ```tla
   \* Use smaller constants for initial verification
   CONSTANTS
       SmallN = 3,     \* Instead of N = 10
       SmallF = 1,     \* Instead of F = 3
       MaxSteps = 10   \* Bound execution
   ```

### CPU Optimization

1. **Parallel Execution**:
   ```bash
   # Use all available cores
   tlc -workers $(nproc) -config model.cfg spec.tla
   
   # Rust parallel compilation
   export CARGO_BUILD_JOBS=$(nproc)
   ```

2. **Incremental Verification**:
   ```bash
   # Verify components separately
   ./scripts/dev/quick_test.sh      # Fast checks first
   ./scripts/dev/debug_verification.sh --component rotor
   ./scripts/dev/debug_verification.sh --component consensus
   ```

### Disk I/O Optimization

1. **Use SSD Storage**:
   ```bash
   # Move verification to SSD if available
   export TMPDIR=/path/to/ssd/tmp
   ```

2. **Reduce Logging**:
   ```bash
   # Minimal logging for performance runs
   ./submission/run_complete_verification.sh --verbose=false
   ```

---

## Log File Analysis

### Log File Locations

```
submission/verification_results/
├── logs/
│   ├── submission_verification.log     # Main log
│   ├── phases/
│   │   ├── environment.log            # Environment validation
│   │   ├── proofs.log                 # TLAPS verification
│   │   ├── model_checking.log         # TLC results
│   │   ├── performance.log            # Performance metrics
│   │   └── report.log                 # Report generation
│   ├── proofs/
│   │   ├── safety_verification.log    # Safety proofs
│   │   ├── liveness_verification.log  # Liveness proofs
│   │   └── resilience_verification.log # Resilience proofs
│   └── model_checking/
│       ├── WhitepaperValidation_results.log
│       └── DebugConfig_results.log
├── reports/
│   ├── executive_summary.md           # High-level results
│   ├── technical_report.json          # Detailed metrics
│   └── submission_package.json        # Package manifest
└── artifacts/
    ├── environment_validation.json    # Tool versions, etc.
    ├── proof_verification.json        # Proof results
    ├── model_checking.json           # Model check results
    └── performance_analysis.json      # Performance data
```

### Log Analysis Techniques

#### 1. Quick Status Check

```bash
# Check overall status
grep -E "(SUCCESS|ERROR|FAILED)" submission/verification_results/logs/submission_verification.log

# Count errors by phase
for phase in environment proofs model_checking performance report; do
    echo "$phase: $(grep -c ERROR submission/verification_results/logs/phases/$phase.log 2>/dev/null || echo 0) errors"
done
```

#### 2. Error Pattern Analysis

```bash
# Find common error patterns
grep -E "(error|Error|ERROR)" submission/verification_results/logs/submission_verification.log | \
    sed 's/.*ERROR.*\[\([^]]*\)\].*/\1/' | sort | uniq -c | sort -nr

# Find timeout issues
grep -i timeout submission/verification_results/logs/submission_verification.log

# Find memory issues
grep -E "(memory|heap|OutOfMemory)" submission/verification_results/logs/submission_verification.log
```

#### 3. Performance Analysis

```bash
# Extract timing information
grep -E "duration|time" submission/verification_results/artifacts/performance_analysis.json | \
    jq '.performance_analysis.benchmarks'

# Check bandwidth usage
jq '.performance_analysis.metrics.bandwidth_utilization' \
    submission/verification_results/artifacts/performance_analysis.json
```

#### 4. Proof Verification Analysis

```bash
# Check proof success rates
jq '.proof_verification.summary.overall_success_rate' \
    submission/verification_results/artifacts/proof_verification.json

# Find failed proof obligations
jq '.proof_verification.modules | to_entries[] | select(.value.status != "complete")' \
    submission/verification_results/artifacts/proof_verification.json
```

### Log Parsing Scripts

#### Extract Error Summary

```bash
#!/bin/bash
# extract_errors.sh - Extract and categorize errors

LOG_DIR="submission/verification_results/logs"
MAIN_LOG="$LOG_DIR/submission_verification.log"

echo "=== Error Summary ==="
echo "Total Errors: $(grep -c ERROR "$MAIN_LOG" 2>/dev/null || echo 0)"
echo "Total Warnings: $(grep -c WARNING "$MAIN_LOG" 2>/dev/null || echo 0)"
echo ""

echo "=== Errors by Phase ==="
for phase_log in "$LOG_DIR/phases"/*.log; do
    if [[ -f "$phase_log" ]]; then
        phase=$(basename "$phase_log" .log)
        errors=$(grep -c ERROR "$phase_log" 2>/dev/null || echo 0)
        echo "$phase: $errors errors"
    fi
done
echo ""

echo "=== Recent Errors ==="
tail -20 "$MAIN_LOG" | grep ERROR
```

#### Performance Report

```bash
#!/bin/bash
# performance_report.sh - Generate performance summary

PERF_FILE="submission/verification_results/artifacts/performance_analysis.json"

if [[ -f "$PERF_FILE" ]]; then
    echo "=== Performance Summary ==="
    echo "Overall Score: $(jq -r '.performance_analysis.metrics.overall_performance_score' "$PERF_FILE")"
    echo "Bandwidth Utilization: $(jq -r '.performance_analysis.metrics.bandwidth_utilization' "$PERF_FILE")%"
    echo "Memory Usage: $(jq -r '.performance_analysis.benchmarks.resource_usage.memory_usage_percent' "$PERF_FILE")%"
    echo "Scalability Rating: $(jq -r '.performance_analysis.metrics.scalability_rating' "$PERF_FILE")"
else
    echo "Performance analysis file not found"
fi
```

---

## Recovery Procedures

### Corrupted Verification State

#### Symptoms
- Verification hangs indefinitely
- Inconsistent results between runs
- "State file corrupted" errors
- Unexpected crashes

#### Recovery Steps

1. **Clean State Reset**:
   ```bash
   # Stop all verification processes
   pkill -f "tlc\|tlapm\|cargo"
   
   # Remove corrupted state
   rm -rf submission/verification_results/
   rm -rf stateright/target/
   
   # Clean TLC temporary files
   rm -rf /tmp/TLC_*
   rm -rf ~/.tlaplus/
   
   # Reset Rust cache
   cd stateright && cargo clean
   ```

2. **Incremental Recovery**:
   ```bash
   # Test environment first
   ./scripts/dev/debug_verification.sh --component environment
   
   # Test individual components
   ./scripts/dev/debug_verification.sh --component rust
   ./scripts/dev/debug_verification.sh --component tla
   
   # Run minimal verification
   ./submission/run_complete_verification.sh --skip-performance --timeout-proofs 300
   ```

3. **Backup Restoration**:
   ```bash
   # If you have backups
   cp -r backup/verification_results/ submission/
   
   # Verify backup integrity
   ./scripts/dev/quick_test.sh
   ```

### Tool Installation Recovery

#### Java Issues

```bash
# Remove corrupted Java installation
sudo apt-get remove --purge openjdk-*
sudo apt-get autoremove

# Clean install
sudo apt-get update
sudo apt-get install openjdk-11-jdk

# Verify installation
java -version
javac -version
echo $JAVA_HOME
```

#### TLA+ Tools Recovery

```bash
# Download fresh TLA+ tools
cd /tmp
wget https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar

# Install to standard location
sudo mkdir -p /opt/tlaplus
sudo cp tla2tools.jar /opt/tlaplus/

# Update shell configuration
echo 'export TLA_HOME=/opt/tlaplus' >> ~/.bashrc
echo 'alias tlc="java -cp $TLA_HOME/tla2tools.jar tlc2.TLC"' >> ~/.bashrc
source ~/.bashrc

# Test installation
tlc -help
```

#### Rust Recovery

```bash
# Uninstall Rust
rustup self uninstall

# Clean install
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env

# Update to latest
rustup update

# Verify installation
cargo --version
rustc --version
```

### File System Recovery

#### Permission Issues

```bash
# Fix script permissions
find . -name "*.sh" -exec chmod +x {} \;

# Fix directory permissions
chmod -R 755 scripts/
chmod -R 755 submission/

# Fix ownership if needed
sudo chown -R $USER:$USER .
```

#### Disk Space Issues

```bash
# Clean up space
rm -rf stateright/target/debug/
rm -rf stateright/target/release/
rm -rf /tmp/TLC_*
docker system prune -f  # If using Docker

# Check available space
df -h .
du -sh submission/verification_results/
```

---

## Best Practices

### Development Workflow

#### 1. Incremental Development

```bash
# Always start with quick tests
./scripts/dev/quick_test.sh

# Test individual components
./scripts/dev/debug_verification.sh --component rust
./scripts/dev/debug_verification.sh --component tla

# Full verification only when components pass
./submission/run_complete_verification.sh
```

#### 2. Version Control Integration

```bash
# Pre-commit hooks
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
# Run quick tests before commit
./scripts/dev/quick_test.sh || exit 1
EOF
chmod +x .git/hooks/pre-commit

# Branch protection
git config branch.main.pushRemote origin
git config branch.main.merge refs/heads/main
```

#### 3. Documentation Maintenance

```markdown
# Keep documentation in sync
- Update this guide when adding new error patterns
- Document new tool versions and compatibility
- Record solutions to novel problems
- Maintain example configurations
```

### Maintenance Procedures

#### Weekly Maintenance

```bash
#!/bin/bash
# weekly_maintenance.sh

echo "=== Weekly Verification System Maintenance ==="

# Update tools
rustup update
# Check for TLA+ tool updates manually

# Clean temporary files
rm -rf /tmp/TLC_*
rm -rf stateright/target/debug/

# Run full verification test
./submission/run_complete_verification.sh --dry-run

# Check disk usage
echo "Disk usage:"
du -sh submission/verification_results/ 2>/dev/null || echo "No results directory"

echo "=== Maintenance Complete ==="
```

#### Monthly Maintenance

```bash
#!/bin/bash
# monthly_maintenance.sh

echo "=== Monthly Verification System Maintenance ==="

# Deep clean
cargo clean
rm -rf ~/.cargo/registry/cache/

# Update dependencies
cd stateright && cargo update

# Run comprehensive tests
./submission/run_complete_verification.sh

# Archive old results
if [[ -d submission/verification_results ]]; then
    tar -czf "verification_results_$(date +%Y%m%d).tar.gz" submission/verification_results/
    echo "Results archived to verification_results_$(date +%Y%m%d).tar.gz"
fi

echo "=== Monthly Maintenance Complete ==="
```

### Configuration Management

#### Environment Configuration

```bash
# .env file for consistent environment
cat > .env << 'EOF'
# Java configuration
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export JAVA_OPTS="-Xmx8g -Xms4g -XX:+UseG1GC"

# TLA+ configuration
export TLA_HOME=/opt/tlaplus
export PATH=$TLA_HOME:$PATH

# Rust configuration
export CARGO_BUILD_JOBS=4
export RUST_BACKTRACE=1

# Verification configuration
export PARALLEL_JOBS=4
export TIMEOUT_PROOFS=3600
export TIMEOUT_MODEL_CHECKING=1800
EOF

# Load environment
source .env
```

#### Tool Version Management

```bash
# tool_versions.sh - Track and verify tool versions
cat > scripts/tool_versions.sh << 'EOF'
#!/bin/bash

echo "=== Tool Versions ==="
echo "Java: $(java -version 2>&1 | head -1)"
echo "TLC: $(tlc -help 2>&1 | head -1 | grep -o 'Version [0-9.]*' || echo 'Unknown')"
echo "TLAPS: $(tlapm --version 2>&1 | head -1 || echo 'Not installed')"
echo "Rust: $(rustc --version)"
echo "Cargo: $(cargo --version)"
echo "System: $(uname -a)"
echo "=== End Tool Versions ==="
EOF
chmod +x scripts/tool_versions.sh
```

### Quality Assurance

#### Automated Testing

```bash
# test_suite.sh - Comprehensive test suite
#!/bin/bash

set -e

echo "=== Alpenglow Verification Test Suite ==="

# Environment tests
echo "1. Testing environment..."
./scripts/tool_versions.sh
./scripts/dev/debug_verification.sh --component environment

# Syntax tests
echo "2. Testing syntax..."
for spec in specs/*.tla; do
    echo "  Checking $(basename "$spec")..."
    tlc -parse "$spec"
done

# Compilation tests
echo "3. Testing Rust compilation..."
cd stateright
cargo check --all-targets
cargo test --no-run
cd ..

# Integration tests
echo "4. Testing integration..."
./scripts/dev/quick_test.sh

# Performance tests
echo "5. Testing performance..."
timeout 300 ./submission/run_complete_verification.sh --skip-proofs --skip-model-checking

echo "=== All Tests Passed ==="
```

#### Continuous Integration

```yaml
# .github/workflows/verification.yml
name: Verification System CI

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 60
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Setup Java
      uses: actions/setup-java@v3
      with:
        distribution: 'temurin'
        java-version: '11'
    
    - name: Setup Rust
      uses: actions-rs/toolchain@v1
      with:
        toolchain: stable
        components: rustfmt, clippy
    
    - name: Cache dependencies
      uses: actions/cache@v3
      with:
        path: |
          ~/.cargo/registry
          ~/.cargo/git
          stateright/target
        key: ${{ runner.os }}-cargo-${{ hashFiles('**/Cargo.lock') }}
    
    - name: Install TLA+ tools
      run: |
        wget -q https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar
        echo 'alias tlc="java -cp $(pwd)/tla2tools.jar tlc2.TLC"' >> ~/.bashrc
    
    - name: Run test suite
      run: |
        source ~/.bashrc
        ./scripts/test_suite.sh
    
    - name: Run verification
      run: |
        source ~/.bashrc
        timeout 1800 ./submission/run_complete_verification.sh --timeout-proofs 600
    
    - name: Upload results
      uses: actions/upload-artifact@v3
      if: always()
      with:
        name: verification-results
        path: submission/verification_results/
```

---

## Advanced Troubleshooting

### Memory Profiling

#### Java Memory Analysis

```bash
# Enable detailed GC logging
export JAVA_OPTS="-Xmx8g -Xms4g -XX:+UseG1GC -XX:+PrintGC -XX:+PrintGCDetails -Xloggc:gc.log"

# Run with memory profiling
tlc -config models/WhitepaperValidation.cfg specs/Alpenglow.tla

# Analyze GC log
# Look for frequent full GCs or long pause times
grep "Full GC" gc.log | wc -l
grep "pause" gc.log | awk '{print $NF}' | sort -n | tail -10
```

#### Rust Memory Analysis

```bash
# Install memory profiler
cargo install cargo-profiler

# Profile memory usage
cd stateright
cargo profiler callgrind --bin verification_test

# Use valgrind for detailed analysis
valgrind --tool=massif cargo test test_erasure_encoding
```

### Performance Profiling

#### TLC Performance Analysis

```bash
# Enable TLC profiling
tlc -profile -config models/WhitepaperValidation.cfg specs/Alpenglow.tla

# Analyze state space exploration
grep -E "(states|transitions)" tlc_profile.txt

# Check for state explosion
grep "distinct states" tlc_profile.txt
```

#### Rust Performance Analysis

```bash
# Install profiling tools
cargo install cargo-flamegraph

# Generate flame graph
cd stateright
cargo flamegraph --bin verification_test

# Use perf for detailed analysis
perf record cargo test test_block_reconstruction
perf report
```

### Network and Distributed Debugging

#### Multi-Node Verification

```bash
# Distributed TLC setup
# Node 1 (master)
tlc -config models/WhitepaperValidation.cfg -workers 4 -masterport 10996 specs/Alpenglow.tla

# Node 2 (worker)
tlc -worker master_ip:10996 -workers 4
```

#### Container Debugging

```bash
# Debug container environment
docker run -it --rm -v $(pwd):/workspace verification-env bash

# Inside container
cd /workspace
./scripts/tool_versions.sh
./scripts/dev/debug_verification.sh --component environment
```

### State Space Analysis

#### TLC State Space Debugging

```tla
\* Add debugging operators to your specification
DebugState == 
    /\ PrintT("Current state: " \o ToString(vars))
    /\ TRUE

\* Add to Next action
Next == 
    /\ DebugState
    /\ (Action1 \/ Action2 \/ Action3)
```

#### Stateright Model Exploration

```rust
// Add state exploration debugging
impl Actor for DebugActor {
    fn on_msg(&self, id: Id, state: &mut Self::State, src: Id, msg: Self::Msg, o: &mut Out<Self>) {
        println!("Actor {}: received {:?} from {} in state {:?}", id, msg, src, state);
        
        // Your normal message handling
        self.handle_message(id, state, src, msg, o);
        
        // Verify invariants after each step
        if let Err(e) = state.verify() {
            panic!("Invariant violation: {:?}", e);
        }
    }
}
```

### Integration Debugging

#### TLA+ to Rust State Mapping

```rust
// Debug state export/import
impl TlaCompatible for MyState {
    fn export_tla_state(&self) -> String {
        let exported = serde_json::to_string_pretty(self).unwrap();
        println!("Exporting state: {}", exported);
        exported
    }
    
    fn import_tla_state(&mut self, state: &Self) -> AlpenglowResult<()> {
        println!("Importing state: {:?}", state);
        // Your import logic
        self.validate_imported_state()?;
        println!("Import successful");
        Ok(())
    }
}
```

#### Cross-Verification

```bash
# Compare TLA+ and Rust results
./scripts/dev/debug_verification.sh --component tla --export-state > tla_state.json
./scripts/dev/debug_verification.sh --component rust --export-state > rust_state.json

# Compare states
diff <(jq --sort-keys . tla_state.json) <(jq --sort-keys . rust_state.json)
```

---

## Conclusion

This troubleshooting guide provides comprehensive coverage of common issues and systematic approaches to debugging the Alpenglow Mathematical Theorem Verifier. Remember:

1. **Start Simple**: Use quick tests and incremental debugging
2. **Check Logs**: Always examine log files for detailed error information
3. **Isolate Components**: Test TLA+, Rust, and integration separately
4. **Document Solutions**: Add new issues and solutions to this guide
5. **Maintain Tools**: Keep all tools updated and properly configured

For additional support:
- Check the project's issue tracker
- Review recent commits for related fixes
- Consult tool-specific documentation
- Consider reaching out to the development team

**Remember**: Most verification failures are due to environment issues, type mismatches, or configuration problems. Following the systematic debugging procedures in this guide should resolve 95% of issues.

---

*Last updated: $(date)*
*Version: 1.0.0*