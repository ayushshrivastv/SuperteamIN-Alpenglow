# Alpenglow Protocol Verification Guide

## Table of Contents
1. [Introduction](#introduction)
2. [Quick Start](#quick-start)
3. [Verification Architecture](#verification-architecture)
4. [Running Verifications](#running-verifications)
5. [Understanding Results](#understanding-results)
6. [Troubleshooting](#troubleshooting)
7. [Advanced Topics](#advanced-topics)

## Introduction

The Alpenglow protocol verification suite provides comprehensive formal verification of the consensus protocol using TLA+ specifications, TLC model checking, and TLAPS theorem proving. This guide helps you understand and use the verification tools effectively.

### Key Components

- **Votor**: Dual-path consensus mechanism with fast and slow paths
- **Rotor**: Erasure-coded block propagation system
- **Formal Properties**: Safety, liveness, and resilience guarantees

### Verification Goals

1. **Safety**: No two honest validators finalize conflicting blocks
2. **Liveness**: Progress with >60% honest stake
3. **Resilience**: Tolerance to 20% Byzantine + 20% offline validators

## Quick Start

### Prerequisites

Install the verification environment:

```bash
# Run the setup script
./scripts/setup.sh

# Verify installation
./scripts/check_model.sh Small --help
```

### Basic Verification

Run a simple verification:

```bash
# Quick verification (small configuration)
./scripts/check_model.sh Small

# Full verification suite
./scripts/run_all.sh --quick
```

### Reading Results

Results are saved in the `results/` directory:

```bash
# View latest results
ls -la results/

# Monitor ongoing verification
./scripts/monitor.sh <SESSION_DIR>
```

## Verification Architecture

### Directory Structure

```
alpenglow-verification/
├── specs/           # TLA+ specifications
│   ├── Alpenglow.tla    # Main specification
│   ├── Types.tla        # Type definitions
│   ├── Network.tla      # Network model
│   ├── Votor.tla        # Consensus mechanism
│   └── Rotor.tla        # Block propagation
├── proofs/          # TLAPS proof files
│   ├── Safety.tla       # Safety proofs
│   ├── Liveness.tla     # Liveness proofs
│   └── Resilience.tla   # Resilience proofs
├── models/          # TLC configurations
│   ├── Small.cfg        # Quick verification
│   ├── Medium.cfg       # Standard verification
│   └── Stress.cfg       # Stress testing
├── scripts/         # Automation tools
└── docs/           # Documentation
```

### Specification Modules

#### Types Module
Defines the core data structures:
- Validators and stakes
- Blocks and certificates
- Messages and network state

#### Network Module
Models network behavior:
- Message delivery with delays
- Partial synchrony assumptions
- Network partitions and recovery

#### Votor Module
Implements consensus logic:
- Leader election
- Vote collection
- Fast and slow paths
- Timeout mechanisms

#### Rotor Module
Handles block propagation:
- Erasure coding
- Stake-weighted relay assignment
- Repair mechanisms

## Running Verifications

### Model Checking

#### Small Configuration
Best for quick checks and development:

```bash
./scripts/check_model.sh Small

# Configuration details:
# - 5 validators
# - 10 slots
# - Equal stake distribution
# - Exhaustive state exploration
```

#### Medium Configuration
Standard verification with Byzantine nodes:

```bash
./scripts/check_model.sh Medium

# Configuration details:
# - 10 validators
# - 2 Byzantine, 2 offline
# - 100 slots
# - Statistical model checking
```

#### Stress Configuration
Large-scale testing with attacks:

```bash
./scripts/check_model.sh Stress

# Configuration details:
# - 50 validators
# - 10 Byzantine, 10 offline
# - 1000 slots
# - Adversarial scenarios
```

### Proof Verification

Run TLAPS proof checking:

```bash
# Verify all proofs
./scripts/verify_proofs.sh All

# Verify specific proof module
./scripts/verify_proofs.sh Safety
./scripts/verify_proofs.sh Liveness
./scripts/verify_proofs.sh Resilience

# Interactive debugging
./scripts/verify_proofs.sh debug Safety.tla
```

### Automated Verification

Run the complete verification suite:

```bash
# Quick mode (small config + basic proofs)
./scripts/run_all.sh --quick

# Full mode (all configurations + all proofs)
./scripts/run_all.sh --full

# Parallel execution
./scripts/run_all.sh --full --parallel

# Generate HTML report
./scripts/run_all.sh --full --report
```

## Understanding Results

### Model Checking Output

#### Key Metrics
- **States Generated**: Total states explored
- **Distinct States**: Unique states found
- **Search Depth**: Maximum exploration depth
- **Queue Size**: Pending states to explore

#### Success Indicators
```
Model checking completed successfully
No violation found
All properties satisfied
```

#### Failure Indicators
```
Invariant violation detected
Temporal property violated
Deadlock reached
```

### Coverage Analysis

Coverage files (`*.tlacov`) show which parts of the specification were exercised:

```bash
# View coverage for a specific module
cat results/latest/Votor.tlacov

# Generate coverage report
python scripts/coverage_report.py results/latest/
```

### Proof Verification Results

#### Proof Obligations
- **Total**: Number of proof obligations generated
- **Verified**: Successfully proved obligations
- **Failed**: Obligations that couldn't be proved
- **Timeout**: Obligations that exceeded time limit

#### Backend Results
- **Zenon**: Automated theorem prover results
- **LS4**: Temporal logic prover results
- **SMT**: SAT solver results

## Troubleshooting

### Common Issues

#### Out of Memory
```bash
# Increase Java heap size
export JAVA_HEAP="-Xmx16G"
./scripts/check_model.sh Medium
```

#### Slow Verification
```bash
# Use more workers
./scripts/check_model.sh Medium -workers 8

# Use simulation instead of exhaustive search
./scripts/check_model.sh Medium -simulate
```

#### State Space Explosion
```bash
# Reduce constants in configuration
# Edit models/Medium.cfg:
MaxSlot = 50  # Reduce from 100
```

### Debug Options

#### Enable Detailed Output
```bash
./scripts/check_model.sh Small -terse false
```

#### Generate State Dumps
```bash
./scripts/check_model.sh Small -dump states.dump
```

#### Trace Counterexamples
```bash
# If verification fails, examine the trace
grep -A 50 "Error:" results/latest/tlc_output.log
```

## Advanced Topics

### Custom Configurations

Create a custom TLC configuration:

```tla
\* File: models/Custom.cfg
SPECIFICATION Spec
CONSTANTS
    NumValidators = 7
    MaxSlot = 20
    ByzantineValidators = {1, 2}
    OfflineValidators = {3}
    
INVARIANTS
    TypeInvariant
    SafetyInvariant
    CustomInvariant
    
PROPERTIES
    Liveness
    FastPathLiveness
```

### Property Definitions

#### Safety Properties
```tla
SafetyInvariant == 
    \A v1, v2 \in HonestValidators:
        \A b1, b2 \in FinalizedBlocks[v1] \cap FinalizedBlocks[v2]:
            b1.slot = b2.slot => b1 = b2
```

#### Liveness Properties
```tla
Liveness == 
    ResponsiveStake >= 60 =>
        []<>(FinalizedSlot' > FinalizedSlot)
```

#### Custom Properties
```tla
NoDoubleVoting ==
    \A v \in Validators:
        \A slot \in Slots:
            Cardinality(VotesAt(v, slot)) <= 1
```

### Performance Tuning

#### Symmetry Reduction
```tla
SYMMETRY ValidatorSymmetry
ValidatorSymmetry == Permutations(Validators)
```

#### State Constraints
```tla
CONSTRAINT StateConstraint
StateConstraint == 
    /\ Len(MessageQueue) <= 1000
    /\ CurrentSlot <= MaxSlot
```

#### Action Constraints
```tla
ACTION_CONSTRAINT ActionConstraint
ActionConstraint ==
    /\ NumByzantineActions < 100
    /\ NumTimeouts < 50
```

### Continuous Integration

The verification suite integrates with GitHub Actions:

```yaml
# .github/workflows/verify.yml
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
```

Workflows:
- **verify.yml**: Main verification on push/PR
- **nightly.yml**: Comprehensive nightly testing

### Extending the Verification

#### Adding New Properties

1. Define the property in `specs/Alpenglow.tla`:
```tla
NewProperty == 
    \* Your property definition
```

2. Add to configuration file:
```
PROPERTIES
    NewProperty
```

3. Run verification:
```bash
./scripts/check_model.sh Small
```

#### Adding Attack Scenarios

1. Create attack module in `specs/Attacks.tla`
2. Define Byzantine behavior
3. Include in main specification
4. Test with stress configuration

### Best Practices

1. **Start Small**: Always test with Small configuration first
2. **Incremental Verification**: Add properties gradually
3. **Monitor Resources**: Watch memory and CPU usage
4. **Save Results**: Archive important verification runs
5. **Document Changes**: Update specs when protocol changes

## Getting Help

### Resources

- [TLA+ Documentation](https://lamport.azurewebsites.net/tla/tla.html)
- [TLC Model Checker Guide](https://lamport.azurewebsites.net/tla/tlc.html)
- [TLAPS Proof System](https://tla.msr-inria.inria.fr/tlaps/content/Home.html)

### Support Channels

- GitHub Issues: Report bugs and request features
- Documentation: Check `/docs` for detailed guides
- Scripts Help: Run any script with `--help` flag

### Contributing

To contribute to the verification:

1. Fork the repository
2. Create a feature branch
3. Add tests for new properties
4. Ensure all verifications pass
5. Submit a pull request

## Appendix

### Glossary

- **TLA+**: Temporal Logic of Actions specification language
- **TLC**: Model checker for TLA+ specifications
- **TLAPS**: TLA+ Proof System for machine-checked proofs
- **GST**: Global Stabilization Time in partial synchrony
- **BFT**: Byzantine Fault Tolerance
- **SMT**: Satisfiability Modulo Theories solver

### Command Reference

```bash
# Setup and installation
./scripts/setup.sh              # Install dependencies

# Model checking
./scripts/check_model.sh [CONFIG] [OPTIONS]
./scripts/monitor.sh [PID|DIR]  # Monitor running verification

# Proof verification  
./scripts/verify_proofs.sh [PROOF] [OPTIONS]

# Automation
./scripts/run_all.sh [--quick|--full] [--parallel] [--report]

# Maintenance
./scripts/clean.sh [--all|--cache|--results]
```

### Configuration Templates

See `/models/` directory for configuration examples:
- `Small.cfg`: Development and quick testing
- `Medium.cfg`: Standard verification
- `Stress.cfg`: Comprehensive testing

---

*Last updated: November 2024*
*Version: 1.0.0*
