# Stateright Implementation Guide for Alpenglow Protocol

## Table of Contents
1. [Introduction](#introduction)
2. [Prerequisites](#prerequisites)
3. [Installation & Setup](#installation--setup)
4. [Architecture Overview](#architecture-overview)
5. [Implementation Structure](#implementation-structure)
6. [Getting Started](#getting-started)
7. [Cross-Validation with TLA+](#cross-validation-with-tla)
8. [Running Verification](#running-verification)
9. [Understanding Results](#understanding-results)
10. [Advanced Usage](#advanced-usage)
11. [Troubleshooting](#troubleshooting)
12. [Contributing](#contributing)

## Introduction

The Stateright implementation provides a Rust-based formal verification framework for the Alpenglow consensus protocol. This implementation serves as a critical cross-validation tool against our TLA+ specifications, offering:

- **Actor-based modeling** of Alpenglow components (Votor, Rotor, Network)
- **Property-based verification** using Rust's type system and Stateright's model checker
- **Performance benchmarking** with concrete implementations
- **Implementation validation** to ensure formal models match real-world code

### Why Stateright for Alpenglow?

1. **Cross-Validation**: Provides independent verification of TLA+ models
2. **Implementation Fidelity**: Closer to actual Rust implementation than abstract TLA+
3. **Performance Analysis**: Enables concrete performance measurements
4. **Developer Accessibility**: Uses familiar Rust syntax and tooling

## Prerequisites

### Required Software
- **Rust 1.70+** with Cargo
- **Git** for version control
- **4GB+ RAM** (8GB+ recommended for larger models)
- **Multi-core CPU** (recommended for parallel verification)

### Optional Software
- **Graphviz** for state space visualization
- **Flamegraph** for performance profiling
- **Criterion** for benchmarking

### Background Knowledge
- Basic understanding of Rust programming
- Familiarity with actor model concepts
- Knowledge of consensus protocols (helpful but not required)
- Understanding of formal verification principles

## Installation & Setup

### 1. Clone and Setup
```bash
# Navigate to the Alpenglow project root
cd /path/to/SuperteamIN

# Install Rust dependencies for Stateright
cd stateright
cargo build --release

# Run initial tests
cargo test
```

### 2. Verify Installation
```bash
# Check that Stateright examples work
cargo run --example simple_consensus check 3

# Verify Alpenglow components compile
cargo check --all-features
```

### 3. Environment Setup
```bash
# Set environment variables for optimal performance
export RUST_LOG=info
export STATERIGHT_WORKERS=8  # Adjust based on CPU cores
export STATERIGHT_MAX_DEPTH=1000
```

## Architecture Overview

The Stateright implementation mirrors the TLA+ specification structure:

```
stateright/
├── src/
│   ├── lib.rs              # Main library exports
│   ├── votor.rs            # Dual-path consensus (Votor)
│   ├── rotor.rs            # Block propagation (Rotor)
│   ├── network.rs          # Network layer with partial synchrony
│   └── integration.rs      # End-to-end integration
├── tests/
│   └── cross_validation.rs # TLA+ cross-validation tests
├── examples/
│   ├── simple_node.rs      # Basic Alpenglow node
│   └── network_simulation.rs # Multi-node simulation
└── benches/
    └── performance.rs      # Performance benchmarks
```

### Component Mapping

| TLA+ Specification | Stateright Implementation | Purpose |
|-------------------|---------------------------|---------|
| `specs/Votor.tla` | `src/votor.rs` | Dual-path consensus voting |
| `specs/Rotor.tla` | `src/rotor.rs` | Erasure-coded block propagation |
| `specs/Network.tla` | `src/network.rs` | Network model with GST |
| `specs/Integration.tla` | `src/integration.rs` | Complete protocol integration |

## Implementation Structure

### Core Types

```rust
// From src/lib.rs
pub use votor::{VotorActor, VotorState, Vote, Certificate};
pub use rotor::{RotorActor, RotorState, Block, Shred};
pub use network::{NetworkActor, Message, NodeId};
pub use integration::{AlpenglowNode, AlpenglowCluster};

// Key data structures
#[derive(Clone, Debug, PartialEq)]
pub struct Vote {
    pub slot: u64,
    pub block_hash: Hash,
    pub voter: NodeId,
    pub stake: u64,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Certificate {
    pub cert_type: CertificateType,  // Fast, Slow, Skip
    pub slot: u64,
    pub block_hash: Hash,
    pub total_stake: u64,
    pub signatures: Vec<Signature>,
}
```

### Actor Model Implementation

Each component is implemented as a Stateright actor:

```rust
// Example from src/votor.rs
impl Actor for VotorActor {
    type Msg = VotorMessage;
    type State = VotorState;

    fn on_start(&self, id: Id, o: &mut Out<Self>) -> Self::State {
        VotorState::new(id, self.config.clone())
    }

    fn on_msg(&self, id: Id, state: &mut Self::State, 
              src: Id, msg: Self::Msg, o: &mut Out<Self>) {
        match msg {
            VotorMessage::ProposeBlock(block) => {
                self.handle_block_proposal(state, block, o);
            }
            VotorMessage::Vote(vote) => {
                self.handle_vote(state, vote, o);
            }
            VotorMessage::Timeout => {
                self.handle_timeout(state, o);
            }
        }
    }
}
```

## Getting Started

### 1. Basic Example

Create a simple Alpenglow node:

```rust
// examples/simple_node.rs
use alpenglow_stateright::*;
use stateright::*;

fn main() {
    let mut checker = AlpenglowCluster::new(3)  // 3 validators
        .checker()
        .spawn_dfs()
        .target_max_depth(100);

    // Check safety properties
    checker = checker.assert_properties(vec![
        Property::always("safety", |_, state| {
            // No conflicting certificates in same slot
            !has_conflicting_certificates(state)
        }),
        Property::sometimes("liveness", |_, state| {
            // Eventually makes progress
            state.finalized_slots.len() > 0
        }),
    ]);

    checker.assert_properties();
    println!("Verification completed successfully!");
}
```

### 2. Running the Example

```bash
# Run basic verification
cargo run --example simple_node

# Run with specific parameters
cargo run --example simple_node -- --validators 5 --max-depth 200

# Enable detailed logging
RUST_LOG=debug cargo run --example simple_node
```

### 3. Network Simulation

```rust
// examples/network_simulation.rs
use alpenglow_stateright::*;

fn main() {
    let cluster = AlpenglowCluster::new(5)
        .with_byzantine_nodes(1)  // 20% Byzantine
        .with_network_partitions(true)
        .with_message_delays(0..100);  // 0-100ms delays

    let mut checker = cluster.checker()
        .spawn_bfs()  // Breadth-first search
        .target_max_depth(500);

    // Verify resilience properties
    checker.assert_properties(vec![
        Property::always("byzantine_safety", |_, state| {
            // Safety maintained with ≤20% Byzantine nodes
            verify_byzantine_safety(state, 0.2)
        }),
        Property::eventually("partition_recovery", |_, state| {
            // Network partitions eventually heal
            state.network.is_connected()
        }),
    ]);

    checker.assert_properties();
}
```

## Cross-Validation with TLA+

### Validation Strategy

The Stateright implementation validates against TLA+ specifications through:

1. **Property Equivalence**: Same safety/liveness properties in both models
2. **Trace Comparison**: Execution traces should be consistent
3. **Invariant Checking**: Same invariants hold in both implementations
4. **Performance Correlation**: Performance characteristics should align

### Running Cross-Validation

```bash
# Run comprehensive cross-validation suite
cargo test cross_validation --release

# Run specific validation tests
cargo test test_votor_cross_validation
cargo test test_rotor_cross_validation
cargo test test_integration_cross_validation

# Generate comparison reports
cargo test cross_validation -- --nocapture > validation_report.txt
```

### Cross-Validation Tests

```rust
// tests/cross_validation.rs
#[test]
fn test_votor_dual_path_consistency() {
    // Test that Stateright Votor produces same results as TLA+ Votor
    let tla_results = load_tla_traces("votor_dual_path.json");
    let stateright_results = run_votor_simulation(VotorConfig::dual_path());
    
    assert_traces_equivalent(tla_results, stateright_results);
}

#[test]
fn test_safety_property_equivalence() {
    // Verify same safety properties hold in both models
    let stateright_violations = check_stateright_safety();
    let tla_violations = load_tla_safety_results();
    
    assert_eq!(stateright_violations.len(), 0);
    assert_eq!(tla_violations.len(), 0);
}

#[test]
fn test_performance_correlation() {
    // Verify performance characteristics align
    let stateright_metrics = benchmark_stateright_performance();
    let tla_metrics = load_tla_performance_metrics();
    
    assert_performance_correlation(stateright_metrics, tla_metrics, 0.1);
}
```

## Running Verification

### Basic Verification Commands

```bash
# Quick verification (small state space)
cargo run --bin verify -- --config small

# Comprehensive verification (larger state space)
cargo run --bin verify -- --config comprehensive

# Specific component verification
cargo run --bin verify -- --component votor
cargo run --bin verify -- --component rotor
cargo run --bin verify -- --component integration

# Performance benchmarking
cargo run --bin verify -- --benchmark --duration 60s
```

### Verification Configurations

```toml
# stateright/configs/small.toml
[verification]
validators = 3
max_depth = 100
max_duration = "5m"
properties = ["safety", "liveness"]

[network]
message_delay_range = [0, 10]
partition_probability = 0.1
byzantine_ratio = 0.0

# stateright/configs/comprehensive.toml
[verification]
validators = 7
max_depth = 1000
max_duration = "30m"
properties = ["safety", "liveness", "byzantine_resilience"]

[network]
message_delay_range = [0, 100]
partition_probability = 0.2
byzantine_ratio = 0.2
```

### Parallel Verification

```bash
# Run verification in parallel
./scripts/stateright_verify.sh --parallel --workers 8

# Distributed verification across multiple machines
./scripts/distributed_verify.sh --nodes node1,node2,node3
```

## Understanding Results

### Verification Output

```
Alpenglow Stateright Verification Results
========================================

Configuration: comprehensive
Validators: 7
Max Depth: 1000
Duration: 28m 34s

State Space Exploration:
- States Generated: 2,847,392
- Distinct States: 1,923,847
- Max Depth Reached: 847
- Coverage: 94.2%

Property Verification:
✅ Safety: PASSED (0 violations)
✅ Liveness: PASSED (0 violations)  
✅ Byzantine Resilience: PASSED (0 violations)
⚠️  Performance: WARNING (some slow paths detected)

Performance Metrics:
- Average Finalization Time: 127ms
- Fast Path Success Rate: 89.3%
- Slow Path Success Rate: 10.7%
- Bandwidth Efficiency: 94.1%

Cross-Validation Status:
✅ TLA+ Consistency: PASSED
✅ Property Equivalence: PASSED
✅ Trace Correlation: 98.7%
```

### Result Analysis

#### Success Indicators
- ✅ **No Property Violations**: All safety and liveness properties hold
- ✅ **High Coverage**: >90% state space coverage
- ✅ **TLA+ Consistency**: Results match TLA+ verification
- ✅ **Performance Targets**: Meets latency and throughput requirements

#### Warning Indicators
- ⚠️ **Partial Coverage**: <90% state space coverage
- ⚠️ **Performance Issues**: Slow finalization or low throughput
- ⚠️ **Trace Divergence**: <95% correlation with TLA+ traces

#### Failure Indicators
- ❌ **Property Violations**: Safety or liveness failures
- ❌ **Inconsistent Results**: Disagreement with TLA+ verification
- ❌ **Timeout/OOM**: Verification couldn't complete

### Debugging Failures

```bash
# Generate detailed trace for failed property
cargo run --bin verify -- --debug --property safety --trace-file failure.json

# Visualize state space around failure
cargo run --bin visualize -- --input failure.json --output failure.svg

# Compare with TLA+ counterexample
./scripts/compare_traces.sh failure.json tla_counterexample.json
```

## Advanced Usage

### Custom Properties

Define custom properties for verification:

```rust
// src/properties.rs
use stateright::*;

pub fn alpenglow_properties() -> Vec<Property<AlpenglowState>> {
    vec![
        // Safety: No conflicting certificates
        Property::always("no_conflicts", |_, state| {
            !has_conflicting_certificates(state)
        }),
        
        // Liveness: Progress with >60% honest stake
        Property::eventually("progress_60", |_, state| {
            if honest_stake_ratio(state) > 0.6 {
                state.finalized_slots.len() > 0
            } else {
                true  // Property doesn't apply
            }
        }),
        
        // Fast path: Finalization with >80% stake
        Property::sometimes("fast_path", |_, state| {
            if honest_stake_ratio(state) > 0.8 {
                state.last_finalization_time < Duration::from_millis(100)
            } else {
                true
            }
        }),
        
        // Byzantine resilience: Safety with ≤20% Byzantine
        Property::always("byzantine_safety", |_, state| {
            if byzantine_ratio(state) <= 0.2 {
                verify_safety_invariants(state)
            } else {
                true  // Outside resilience bounds
            }
        }),
    ]
}
```

### Performance Profiling

```bash
# Profile verification performance
cargo run --bin verify --features profiling -- --profile

# Generate flamegraph
cargo flamegraph --bin verify -- --config comprehensive

# Memory usage analysis
valgrind --tool=massif cargo run --bin verify -- --config small
```

### State Space Optimization

```rust
// Implement symmetry reduction
impl Symmetry for AlpenglowState {
    fn representative(&self) -> Self {
        // Reduce state space by normalizing equivalent states
        let mut normalized = self.clone();
        normalized.normalize_node_ids();
        normalized.sort_pending_messages();
        normalized
    }
}

// Use abstraction for large state spaces
impl Abstraction for AlpenglowState {
    type AbstractState = AbstractAlpenglowState;
    
    fn abstract_state(&self) -> Self::AbstractState {
        AbstractAlpenglowState {
            finalized_count: self.finalized_slots.len(),
            pending_votes: self.pending_votes.len(),
            network_health: self.network.health_score(),
        }
    }
}
```

## Troubleshooting

### Common Issues

#### Out of Memory
```bash
# Reduce state space
cargo run --bin verify -- --max-depth 100 --max-states 1000000

# Use disk-based storage
cargo run --bin verify -- --disk-storage /tmp/stateright

# Enable state compression
cargo run --bin verify -- --compress-states
```

#### Slow Verification
```bash
# Use parallel workers
cargo run --bin verify -- --workers 16

# Enable optimizations
cargo run --release --bin verify

# Use symmetry reduction
cargo run --bin verify -- --symmetry-reduction
```

#### Property Violations
```bash
# Get detailed counterexample
cargo run --bin verify -- --debug --counterexample-file violation.json

# Minimize counterexample
cargo run --bin minimize -- --input violation.json --output minimal.json

# Compare with TLA+ results
./scripts/analyze_violation.sh violation.json
```

#### Cross-Validation Failures
```bash
# Check TLA+ trace format
./scripts/validate_tla_traces.sh

# Regenerate TLA+ traces
cd ../specs && ./scripts/generate_traces.sh

# Debug trace differences
cargo test cross_validation -- --nocapture --debug
```

### Debug Mode

Enable comprehensive debugging:

```bash
# Full debug output
RUST_LOG=debug,stateright=trace cargo run --bin verify

# Component-specific debugging
RUST_LOG=alpenglow::votor=debug cargo run --bin verify

# Save debug traces
cargo run --bin verify -- --debug --save-traces debug_traces/
```

### Performance Tuning

```bash
# Optimize for verification speed
export STATERIGHT_WORKERS=16
export STATERIGHT_BATCH_SIZE=10000
export STATERIGHT_MEMORY_LIMIT=32GB

# Optimize for memory usage
export STATERIGHT_COMPRESS=true
export STATERIGHT_DISK_STORAGE=/fast/ssd/path
export STATERIGHT_GC_INTERVAL=100000
```

## Contributing

### Development Workflow

1. **Fork and Clone**
   ```bash
   git clone https://github.com/your-fork/SuperteamIN.git
   cd SuperteamIN/stateright
   ```

2. **Create Feature Branch**
   ```bash
   git checkout -b feature/stateright-enhancement
   ```

3. **Implement Changes**
   ```bash
   # Make your changes
   cargo test
   cargo clippy
   cargo fmt
   ```

4. **Run Verification**
   ```bash
   # Ensure all tests pass
   cargo test --all-features
   ./scripts/stateright_verify.sh --quick
   ```

5. **Submit Pull Request**
   - Include verification results
   - Update documentation
   - Add tests for new features

### Code Style

Follow Rust best practices:

```rust
// Use descriptive names
fn handle_vote_message(state: &mut VotorState, vote: Vote) -> Result<(), VotorError> {
    // Implementation
}

// Document public APIs
/// Handles a vote message in the Votor consensus protocol.
/// 
/// # Arguments
/// * `state` - Current Votor state
/// * `vote` - Vote to process
/// 
/// # Returns
/// * `Ok(())` if vote processed successfully
/// * `Err(VotorError)` if vote is invalid
pub fn process_vote(state: &mut VotorState, vote: Vote) -> Result<(), VotorError> {
    // Implementation
}

// Use proper error handling
#[derive(Debug, thiserror::Error)]
pub enum VotorError {
    #[error("Invalid vote: {0}")]
    InvalidVote(String),
    #[error("Insufficient stake: got {got}, need {need}")]
    InsufficientStake { got: u64, need: u64 },
}
```

### Testing Guidelines

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use stateright::*;

    #[test]
    fn test_votor_fast_path() {
        let mut cluster = AlpenglowCluster::new(5);
        cluster.set_honest_stake_ratio(0.9);  // >80% for fast path
        
        let checker = cluster.checker()
            .spawn_dfs()
            .target_max_depth(50);
            
        checker.assert_properties(vec![
            Property::sometimes("fast_finalization", |_, state| {
                state.last_finalization_time < Duration::from_millis(100)
            })
        ]);
    }

    #[test]
    fn test_cross_validation_consistency() {
        // Ensure Stateright results match TLA+ results
        let stateright_result = run_stateright_verification();
        let tla_result = load_tla_verification_result();
        
        assert_eq!(stateright_result.safety_violations, 0);
        assert_eq!(tla_result.safety_violations, 0);
        assert_traces_equivalent(stateright_result.traces, tla_result.traces);
    }
}
```

### Documentation Standards

- **API Documentation**: All public functions must have rustdoc comments
- **Examples**: Include usage examples in documentation
- **Integration**: Update this guide when adding new features
- **Cross-References**: Link to relevant TLA+ specifications

---

## Conclusion

The Stateright implementation provides a powerful complement to our TLA+ formal verification, offering:

- **Implementation-level verification** with concrete Rust code
- **Cross-validation** to ensure model consistency
- **Performance analysis** with real-world metrics
- **Developer-friendly** verification using familiar Rust tooling

By following this guide, you can effectively use the Stateright implementation to verify the Alpenglow protocol, validate against TLA+ specifications, and contribute to the formal verification ecosystem.

For additional support:
- Review the [TLA+ specifications](../specs/) for formal models
- Check the [verification reports](../docs/VerificationReport.md) for current status
- Consult the [implementation guide](../docs/ImplementationGuide.md) for production deployment
- Join the discussion in GitHub issues for questions and improvements

**Next Steps:**
1. Run the basic examples to familiarize yourself with the system
2. Execute cross-validation tests to verify TLA+ consistency
3. Experiment with custom properties and configurations
4. Contribute improvements and report any issues found

The Stateright implementation is a critical component of our comprehensive formal verification strategy, providing the implementation bridge between abstract formal models and production-ready consensus protocols.
