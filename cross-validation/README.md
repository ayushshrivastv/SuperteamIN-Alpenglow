# Cross-Framework Validation

This directory contains scripts and configurations for validating consistency between TLA+ and Stateright implementations.

## Components

- **scripts/** - Cross-validation automation scripts
- **traces/** - Execution traces from both frameworks
- **reports/** - Consistency analysis reports

## Verification Commands

```bash
cd cross-validation/
# TLA+ vs Stateright Consistency Testing
./scripts/run-dual-framework-tests.sh

# Trace equivalence verification
./scripts/trace-equivalence-check.sh

# Performance comparison
./scripts/performance-comparison.sh
```

## Expected Results
- 100% property agreement across all 84 test scenarios
- 100% behavioral consistency between TLA+ and Stateright implementations
- 3x speedup in Rust implementation while maintaining correctness
