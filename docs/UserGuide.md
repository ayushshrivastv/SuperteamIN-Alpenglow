# Alpenglow Protocol Verification - User Guide

## Table of Contents
1. [Introduction](#introduction)
2. [Prerequisites](#prerequisites)
3. [Installation](#installation)
4. [Quick Start](#quick-start)
5. [Running Model Checks](#running-model-checks)
6. [Running Proof Verification](#running-proof-verification)
7. [Understanding Results](#understanding-results)
8. [Troubleshooting](#troubleshooting)

## Introduction

The Alpenglow Protocol Verification suite provides formal verification tools for validating the correctness of the Alpenglow consensus protocol. This includes:

- **Model Checking**: Exhaustive state space exploration using TLC
- **Theorem Proving**: Mathematical proofs using TLAPS
- **Automated Testing**: Comprehensive test scenarios

## Prerequisites

### Required Software
- Java 11 or higher
- Bash shell (Linux/macOS)
- 4GB+ RAM (8GB+ recommended for larger models)

### Optional Software
- TLAPS (for proof verification)
- Graphviz (for visualization)

## Installation

### Automatic Setup
Run the setup script to install all dependencies:

```bash
./scripts/setup.sh
```

This will:
1. Check Java installation
2. Install TLA+ tools
3. Install TLAPS (optional)
4. Set up project structure
5. Verify installation

### Manual Setup
If automatic setup fails, follow the manual installation guide in `docs/Installation.md`.

## Quick Start

### 1. Verify Installation
```bash
# Check syntax of all specifications
./scripts/syntax_check.sh

# Run smallest configuration
./scripts/check_model.sh Small
```

### 2. Run Full Verification
```bash
# Quick mode (small config + basic proofs)
./scripts/run_all.sh quick

# Full mode (all configs + all proofs)
./scripts/run_all.sh full
```

## Running Model Checks

### Individual Configurations

Run specific model configurations:

```bash
# Small configuration (quick verification)
./scripts/check_model.sh Small

# Medium configuration (standard verification)
./scripts/check_model.sh Medium

# Boundary testing
./scripts/check_model.sh Boundary

# Edge cases
./scripts/check_model.sh EdgeCase

# Network partition scenarios
./scripts/check_model.sh Partition
```

### Parallel Execution

Run multiple configurations in parallel for faster results:

```bash
# Run all configurations in parallel
./scripts/parallel_check.sh

# Run specific configurations
./scripts/parallel_check.sh --configs Small,Medium,Boundary

# Limit parallel jobs
./scripts/parallel_check.sh --max-parallel 2

# Set timeout per configuration
./scripts/parallel_check.sh --timeout 7200
```

### Configuration Details

| Configuration | Validators | States | Memory | Time |
|--------------|-----------|--------|--------|------|
| Small | 3 | ~10K | 2GB | 1-5 min |
| Medium | 5 | ~100K | 8GB | 10-30 min |
| Boundary | 3 | ~50K | 4GB | 5-15 min |
| EdgeCase | 3 | ~30K | 4GB | 5-10 min |
| Partition | 5 | ~200K | 8GB | 20-60 min |

## Running Proof Verification

### Individual Proofs

Verify specific proof modules:

```bash
# Safety properties
./scripts/verify_proofs.sh Safety

# Liveness properties
./scripts/verify_proofs.sh Liveness

# Resilience properties
./scripts/verify_proofs.sh Resilience

# All proofs
./scripts/verify_proofs.sh All
```

### Proof Options

```bash
# Verbose output
./scripts/verify_proofs.sh Safety --verbose

# Increase timeout
./scripts/verify_proofs.sh Liveness --timeout 120

# Use specific backend
./scripts/verify_proofs.sh Safety --method smt
```

## Understanding Results

### Model Checking Results

Results are saved to `results/model/` with the following structure:

```
results/model/session_TIMESTAMP/
├── Small_summary.txt       # Configuration summary
├── Small_coverage.html     # State coverage report
├── Small_trace.txt        # Execution trace (if errors)
└── Small.log              # Full TLC output
```

#### Key Metrics
- **States Generated**: Total states explored
- **Distinct States**: Unique states found
- **Queue Size**: Remaining states to explore
- **Coverage**: Percentage of state space covered

#### Success Criteria
- ✅ No invariant violations
- ✅ No deadlocks detected
- ✅ All temporal properties satisfied
- ✅ Coverage > 90% (for small configs)

### Proof Verification Results

Results are saved to `results/proofs/` with the following structure:

```
results/proofs/session_TIMESTAMP/
├── Safety/
│   ├── summary.txt        # Proof summary
│   ├── obligations.log    # Proof obligations
│   └── *.log             # Backend results
├── Liveness/
└── Resilience/
```

#### Success Criteria
- ✅ All proof obligations verified
- ✅ No failed obligations
- ✅ No timeout obligations

## Troubleshooting

### Common Issues

#### Out of Memory Error
```bash
# Increase Java heap size
export JAVA_OPTS="-Xmx16G"
./scripts/check_model.sh Medium
```

#### TLC Cannot Find Specification
```bash
# Ensure specs are in correct location
ls -la specs/*.tla

# Run syntax check first
./scripts/syntax_check.sh
```

#### Proof Verification Timeout
```bash
# Increase timeout and use combined backends
./scripts/verify_proofs.sh Safety --timeout 300 --method "zenon ls4 smt"
```

#### Model Checking Takes Too Long
```bash
# Use smaller configuration
./scripts/check_model.sh Small

# Or limit state space
# Edit models/Small.cfg and add stricter constraints
```

### Debug Mode

Enable debug output for detailed information:

```bash
# Model checking debug
TLC_DEBUG=1 ./scripts/check_model.sh Small

# Proof verification debug
./scripts/verify_proofs.sh debug Safety.tla
```

### Getting Help

1. Check the error logs in `results/` directory
2. Review the verification guide: `docs/VerificationGuide.md`
3. Consult the TLA+ documentation: https://lamport.azurewebsites.net/tla/tla.html

## Advanced Usage

### Custom Configurations

Create custom model configurations by copying and modifying existing ones:

```bash
cp models/Small.cfg models/Custom.cfg
# Edit models/Custom.cfg with your parameters
./scripts/check_model.sh Custom
```

### Continuous Integration

The project includes GitHub Actions workflows for automated verification:

- `.github/workflows/verify.yml` - On every push
- `.github/workflows/nightly.yml` - Nightly full verification

### Performance Tuning

For large-scale verification:

1. **Use SSD storage** for state files
2. **Allocate sufficient RAM** (2x state space size)
3. **Use parallel checking** for multiple configs
4. **Optimize TLC parameters**:
   - Increase workers: `-workers 16`
   - Use disk storage: `-metadir /path/to/ssd`
   - Enable checkpointing: `-checkpoint 10`

## Next Steps

1. **Explore the specifications** in `specs/`
2. **Review the proofs** in `proofs/`
3. **Analyze verification reports** in `results/`
4. **Customize configurations** in `models/`
5. **Contribute improvements** via pull requests

For more detailed information, see:
- [Verification Guide](VerificationGuide.md)
- [Development Guide](DevelopmentGuide.md)
- [API Reference](../Reference.md)
