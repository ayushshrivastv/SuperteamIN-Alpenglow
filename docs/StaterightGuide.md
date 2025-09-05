# Alpenglow Protocol Stateright Implementation Guide

## Table of Contents
1. [Introduction](#introduction)
2. [Quick Start](#quick-start)
3. [Rust Model Architecture](#rust-model-architecture)
4. [TLA+ to Rust Mapping](#tla-to-rust-mapping)
5. [Cross-Validation Methodology](#cross-validation-methodology)
6. [Development Environment Setup](#development-environment-setup)
7. [Running Stateright Model Checking](#running-stateright-model-checking)
8. [Interpreting Results](#interpreting-results)
9. [Debugging Stateright Models](#debugging-stateright-models)
10. [Performance Tuning](#performance-tuning)
11. [Property Checking Framework](#property-checking-framework)
12. [Extending the Implementation](#extending-the-implementation)
13. [Cross-Validation Workflows](#cross-validation-workflows)
14. [Troubleshooting](#troubleshooting)
15. [Best Practices](#best-practices)

## Introduction

The Alpenglow Stateright implementation provides a Rust-based model of the consensus protocol that exactly mirrors the TLA+ specifications. This enables cross-validation between formal specifications and executable models, increasing confidence in the correctness of both the protocol design and implementation.

### Why Stateright?

- **Executable Models**: Run the same state transitions as TLA+ specifications
- **Performance**: Faster exploration of large state spaces
- **Integration**: Direct integration with Rust production code
- **Cross-Validation**: Verify consistency between TLA+ and Rust models
- **Debugging**: Rich debugging capabilities with Rust tooling

### Key Benefits

1. **Dual Verification**: Both TLA+ and Rust models must agree
2. **Implementation Validation**: Rust model can guide production implementation
3. **Performance Analysis**: Measure actual execution performance
4. **Counterexample Analysis**: Rich debugging of protocol violations

## Quick Start

### Prerequisites

```bash
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env

# Install required tools
cargo install cargo-watch
cargo install flamegraph
```

### Basic Usage

```bash
# Navigate to Stateright implementation
cd stateright/

# Run basic model checking
cargo test test_safety_properties

# Run cross-validation
cargo test cross_validation

# Generate coverage report
cargo test --features coverage
```

### Quick Verification

```bash
# Run small configuration
./scripts/stateright_verify.sh --config small

# Compare with TLA+ results
./scripts/stateright_verify.sh --cross-validate
```

## Rust Model Architecture

### Core Structure

The Rust implementation follows a modular architecture that directly mirrors the TLA+ specification structure:

```rust
// Main model structure
pub struct AlpenglowModel {
    pub config: Config,
    pub state: AlpenglowState,
}

// State mirrors TLA+ state variables exactly
pub struct AlpenglowState {
    // Time and scheduling
    pub clock: TimeValue,
    pub current_slot: SlotNumber,
    pub current_rotor: ValidatorId,
    
    // Votor consensus state
    pub votor_view: HashMap<ValidatorId, ViewNumber>,
    pub votor_voted_blocks: HashMap<ValidatorId, HashMap<ViewNumber, HashSet<Block>>>,
    pub votor_generated_certs: HashMap<ViewNumber, HashSet<Certificate>>,
    
    // Rotor propagation state
    pub rotor_block_shreds: HashMap<BlockHash, HashMap<ValidatorId, HashSet<ErasureCodedPiece>>>,
    pub rotor_relay_assignments: HashMap<ValidatorId, Vec<u32>>,
    
    // Network state
    pub network_message_queue: HashSet<NetworkMessage>,
    pub network_partitions: HashSet<HashSet<ValidatorId>>,
}
```

### Module Organization

```
stateright/src/
├── lib.rs              # Main model and types
├── votor.rs            # Consensus logic
├── rotor.rs            # Block propagation
├── network.rs          # Network model
├── integration.rs      # End-to-end protocol
├── stateright/         # Local Stateright framework
└── tests/
    ├── cross_validation.rs  # TLA+ comparison tests
    ├── properties.rs        # Property checking
    └── scenarios.rs         # Specific test scenarios
```

### Type System Mapping

The Rust types exactly mirror TLA+ type definitions:

```rust
// TLA+ ValidatorId maps to Rust ValidatorId
pub type ValidatorId = u32;

// TLA+ Block record maps to Rust Block struct
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct Block {
    pub slot: SlotNumber,
    pub view: ViewNumber,
    pub hash: BlockHash,
    pub parent: BlockHash,
    pub proposer: ValidatorId,
    pub transactions: HashSet<Transaction>,
    pub timestamp: TimeValue,
    pub signature: Signature,
    pub data: Vec<u64>,
}

// TLA+ Vote record maps to Rust Vote struct
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct Vote {
    pub voter: ValidatorId,
    pub slot: SlotNumber,
    pub view: ViewNumber,
    pub block: BlockHash,
    pub vote_type: VoteType,
    pub signature: Signature,
    pub timestamp: TimeValue,
}
```

## TLA+ to Rust Mapping

### State Variables Mapping

| TLA+ Variable | Rust Field | Description |
|---------------|------------|-------------|
| `clock` | `state.clock` | Global time counter |
| `currentSlot` | `state.current_slot` | Current consensus slot |
| `votorView[v]` | `state.votor_view[v]` | View number per validator |
| `votorVotedBlocks[v][view]` | `state.votor_voted_blocks[v][view]` | Blocks voted by validator |
| `rotorBlockShreds[block][v]` | `state.rotor_block_shreds[block][v]` | Shreds held by validator |
| `networkMessages` | `state.network_message_queue` | Pending network messages |

### Action Mapping

| TLA+ Action | Rust Method | Description |
|-------------|-------------|-------------|
| `AdvanceClock` | `execute_action(AdvanceClock)` | Increment global clock |
| `ProposeBlock(v, view)` | `execute_votor_action(ProposeBlock{...})` | Validator proposes block |
| `CastVote(v, block, view)` | `execute_votor_action(CastVote{...})` | Validator casts vote |
| `ShredAndDistribute(leader, block)` | `execute_rotor_action(ShredAndDistribute{...})` | Leader shreds block |
| `DeliverMessage(msg)` | `execute_network_action(DeliverMessage{...})` | Network delivers message |

### Operator Mapping

```rust
// TLA+ IsLeaderForView(v, view) maps to Rust method
impl AlpenglowModel {
    fn is_leader_for_view(&self, validator: ValidatorId, view: ViewNumber) -> bool {
        self.compute_leader_for_view(view) == validator
    }
}

// TLA+ CanReconstruct(v, block) maps to Rust method
impl AlpenglowModel {
    fn can_reconstruct(&self, validator: ValidatorId, block_id: BlockHash) -> bool {
        self.state.rotor_block_shreds.get(&block_id)
            .and_then(|shreds| shreds.get(&validator))
            .map_or(false, |pieces| pieces.len() >= self.config.k as usize)
    }
}
```

### Invariant Mapping

```rust
// TLA+ TypeInvariant maps to Rust validation
impl AlpenglowState {
    pub fn type_invariant(&self, config: &Config) -> bool {
        // Validate all validators have views
        self.votor_view.len() == config.validator_count &&
        // Validate clock is non-negative
        self.clock >= 0 &&
        // Validate current slot is positive
        self.current_slot > 0
    }
}

// TLA+ SafetyInvariant maps to Rust property
pub fn safety_no_conflicting_finalization(state: &AlpenglowState) -> bool {
    state.finalized_blocks.values().all(|blocks| blocks.len() <= 1)
}
```

## Cross-Validation Methodology

### Validation Approach

The cross-validation process ensures that TLA+ and Rust models produce identical results:

1. **State Synchronization**: Both models start from identical initial states
2. **Action Equivalence**: Same actions produce same state transitions
3. **Property Verification**: Both models satisfy the same properties
4. **Trace Comparison**: Execution traces are compared step-by-step

### Validation Framework

```rust
#[cfg(test)]
mod cross_validation {
    use super::*;
    
    #[test]
    fn test_state_synchronization() {
        let config = Config::new().with_validators(3);
        let rust_state = AlpenglowState::init(&config);
        let tla_state = import_tla_initial_state("Small.cfg");
        
        assert_eq!(rust_state.clock, tla_state.clock);
        assert_eq!(rust_state.current_slot, tla_state.current_slot);
        assert_eq!(rust_state.votor_view, tla_state.votor_view);
    }
    
    #[test]
    fn test_action_equivalence() {
        let model = AlpenglowModel::new(Config::new().with_validators(3));
        let action = AlpenglowAction::AdvanceClock;
        
        let rust_result = model.execute_action(action.clone()).unwrap();
        let tla_result = execute_tla_action(&model.state, action);
        
        assert_eq!(rust_result, tla_result);
    }
}
```

### TLA+ Trace Import

```rust
// Import TLA+ counterexample traces
pub fn import_tlc_trace(trace_file: &str) -> Vec<AlpenglowAction> {
    let trace_content = std::fs::read_to_string(trace_file)?;
    let trace_lines: Vec<&str> = trace_content.lines().collect();
    
    let mut actions = Vec::new();
    for line in trace_lines {
        if let Some(action) = parse_tla_action(line) {
            actions.push(action);
        }
    }
    actions
}

// Replay TLA+ trace in Rust model
pub fn replay_tla_trace(model: &AlpenglowModel, actions: Vec<AlpenglowAction>) -> AlpenglowResult<AlpenglowState> {
    let mut current_state = model.state.clone();
    
    for action in actions {
        let temp_model = AlpenglowModel {
            config: model.config.clone(),
            state: current_state,
        };
        current_state = temp_model.execute_action(action)?;
    }
    
    Ok(current_state)
}
```

## Development Environment Setup

### Rust Environment

```bash
# Install Rust with latest stable toolchain
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env
rustup update stable

# Install development tools
cargo install cargo-watch      # Auto-rebuild on changes
cargo install cargo-expand     # Macro expansion
cargo install cargo-audit      # Security audit
cargo install flamegraph       # Performance profiling
cargo install cargo-tarpaulin  # Code coverage
```

### IDE Setup

#### VS Code Configuration

```json
// .vscode/settings.json
{
    "rust-analyzer.cargo.features": ["all"],
    "rust-analyzer.checkOnSave.command": "clippy",
    "rust-analyzer.cargo.loadOutDirsFromCheck": true,
    "files.watcherExclude": {
        "**/target/**": true
    }
}
```

#### Recommended Extensions

- `rust-analyzer`: Rust language server
- `CodeLLDB`: Debugging support
- `Better TOML`: Cargo.toml syntax highlighting
- `Error Lens`: Inline error display

### Project Setup

```bash
# Clone repository
git clone <repository-url>
cd alpenglow/stateright

# Install dependencies
cargo build

# Run tests to verify setup
cargo test

# Install pre-commit hooks
cargo install pre-commit
pre-commit install
```

### Dependencies

```toml
# Cargo.toml
[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
tokio = { version = "1.0", features = ["full"] }
tracing = "0.1"
tracing-subscriber = "0.3"
thiserror = "1.0"
anyhow = "1.0"

[dev-dependencies]
proptest = "1.0"
criterion = "0.5"
tempfile = "3.0"
```

## Running Stateright Model Checking

### Basic Model Checking

```bash
# Run all tests
cargo test

# Run specific test module
cargo test votor

# Run with output
cargo test -- --nocapture

# Run single test
cargo test test_safety_properties -- --exact
```

### Configuration Options

```rust
// Create custom configurations
let small_config = Config::new()
    .with_validators(3)
    .with_network_timing(10, 100);

let medium_config = Config::new()
    .with_validators(7)
    .with_byzantine_threshold(2)
    .with_network_timing(50, 500);

let stress_config = Config::new()
    .with_validators(20)
    .with_byzantine_threshold(6)
    .with_network_timing(100, 1000);
```

### Property Checking

```rust
// Run safety property checks
#[test]
fn test_safety_properties() {
    let config = Config::new().with_validators(4);
    let model = AlpenglowModel::new(config);
    
    // Check safety invariants
    let checker = Checker::new(&model);
    checker.assert_properties(vec![
        Property::always("safety", |state| {
            properties::safety_no_conflicting_finalization(state)
        }),
        Property::always("chain_consistency", |state| {
            properties::chain_consistency(state)
        }),
    ]);
}

// Run liveness property checks
#[test]
fn test_liveness_properties() {
    let config = Config::new().with_validators(4);
    let model = AlpenglowModel::new(config);
    
    let checker = Checker::new(&model);
    checker.assert_properties(vec![
        Property::eventually("progress", |state| {
            properties::liveness_eventual_progress(state)
        }),
    ]);
}
```

### Simulation Mode

```rust
// Run simulation instead of exhaustive checking
#[test]
fn test_simulation() {
    let config = Config::new().with_validators(10);
    let model = AlpenglowModel::new(config);
    
    let mut checker = Checker::new(&model);
    checker.simulate(1000); // Run 1000 random executions
    
    // Check properties hold in all simulations
    assert!(checker.all_properties_satisfied());
}
```

### Parallel Execution

```bash
# Run tests in parallel
cargo test --jobs 8

# Run with specific thread count
RUST_TEST_THREADS=4 cargo test
```

## Interpreting Results

### Test Output Format

```
running 5 tests
test cross_validation::test_state_synchronization ... ok
test properties::test_safety_properties ... ok
test properties::test_liveness_properties ... ok
test scenarios::test_byzantine_scenario ... FAILED
test scenarios::test_partition_scenario ... ok

failures:

---- scenarios::test_byzantine_scenario stdout ----
thread 'scenarios::test_byzantine_scenario' panicked at 'assertion failed: safety_property_holds'
```

### Property Violation Analysis

```rust
// Detailed property violation reporting
#[test]
fn test_with_detailed_output() {
    let config = Config::new().with_validators(4);
    let model = AlpenglowModel::new(config);
    
    let checker = Checker::new(&model);
    let result = checker.check_property("safety", |state| {
        if !properties::safety_no_conflicting_finalization(state) {
            eprintln!("Safety violation detected:");
            eprintln!("  Finalized blocks: {:?}", state.finalized_blocks);
            eprintln!("  Current slot: {}", state.current_slot);
            false
        } else {
            true
        }
    });
    
    assert!(result.is_ok(), "Safety property violated");
}
```

### State Space Statistics

```rust
// Collect exploration statistics
#[test]
fn test_state_space_analysis() {
    let config = Config::new().with_validators(3);
    let model = AlpenglowModel::new(config);
    
    let mut checker = Checker::new(&model);
    let stats = checker.explore_with_stats();
    
    println!("States explored: {}", stats.states_explored);
    println!("Unique states: {}", stats.unique_states);
    println!("Max depth: {}", stats.max_depth);
    println!("Exploration time: {:?}", stats.duration);
}
```

### Coverage Analysis

```bash
# Generate coverage report
cargo tarpaulin --out Html

# View coverage
open tarpaulin-report.html
```

## Debugging Stateright Models

### Debug Logging

```rust
use tracing::{info, debug, warn, error};

// Enable debug logging
#[test]
fn test_with_logging() {
    tracing_subscriber::fmt::init();
    
    let config = Config::new().with_validators(3);
    let model = AlpenglowModel::new(config);
    
    info!("Starting model checking with config: {:?}", model.config);
    
    // Model checking with debug output
    let checker = Checker::new(&model);
    checker.check_with_logging();
}
```

### State Inspection

```rust
// Custom debug output for states
impl std::fmt::Debug for AlpenglowState {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("AlpenglowState")
            .field("clock", &self.clock)
            .field("current_slot", &self.current_slot)
            .field("votor_view", &self.votor_view)
            .field("finalized_blocks_count", &self.finalized_blocks.len())
            .field("message_queue_size", &self.network_message_queue.len())
            .finish()
    }
}

// State validation helper
impl AlpenglowState {
    pub fn validate(&self, config: &Config) -> Result<(), String> {
        if self.votor_view.len() != config.validator_count {
            return Err(format!("Invalid votor_view size: {} != {}", 
                self.votor_view.len(), config.validator_count));
        }
        
        if self.current_slot == 0 {
            return Err("Current slot cannot be zero".to_string());
        }
        
        Ok(())
    }
}
```

### Breakpoint Debugging

```rust
// Use debugger breakpoints
#[test]
fn test_with_breakpoints() {
    let config = Config::new().with_validators(3);
    let mut model = AlpenglowModel::new(config);
    
    // Set breakpoint here in debugger
    let action = AlpenglowAction::AdvanceClock;
    
    // Step through action execution
    let result = model.execute_action(action);
    
    // Inspect result
    match result {
        Ok(new_state) => {
            // Breakpoint: examine new_state
            println!("New state: {:?}", new_state);
        },
        Err(error) => {
            // Breakpoint: examine error
            println!("Error: {:?}", error);
        }
    }
}
```

### Trace Generation

```rust
// Generate execution traces
pub struct TraceRecorder {
    trace: Vec<(AlpenglowState, AlpenglowAction)>,
}

impl TraceRecorder {
    pub fn new() -> Self {
        Self { trace: Vec::new() }
    }
    
    pub fn record(&mut self, state: AlpenglowState, action: AlpenglowAction) {
        self.trace.push((state, action));
    }
    
    pub fn save_trace(&self, filename: &str) -> std::io::Result<()> {
        let json = serde_json::to_string_pretty(&self.trace)?;
        std::fs::write(filename, json)
    }
}
```

## Performance Tuning

### Optimization Strategies

#### State Representation

```rust
// Use more efficient data structures
use std::collections::BTreeMap;
use indexmap::IndexMap;

// Replace HashMap with BTreeMap for deterministic iteration
pub type ValidatorMap<T> = BTreeMap<ValidatorId, T>;

// Use IndexMap for insertion-order preservation
pub type MessageQueue = IndexMap<MessageHash, NetworkMessage>;
```

#### Memory Management

```rust
// Use object pooling for frequently allocated objects
use std::sync::Arc;

#[derive(Clone)]
pub struct PooledBlock {
    inner: Arc<Block>,
}

// Implement Copy-on-Write semantics
impl PooledBlock {
    pub fn modify<F>(&mut self, f: F) 
    where F: FnOnce(&mut Block) 
    {
        if Arc::strong_count(&self.inner) > 1 {
            self.inner = Arc::new((*self.inner).clone());
        }
        f(Arc::make_mut(&mut self.inner));
    }
}
```

#### Parallel Execution

```rust
use rayon::prelude::*;

// Parallelize property checking
#[test]
fn test_parallel_properties() {
    let configs = vec![
        Config::new().with_validators(3),
        Config::new().with_validators(4),
        Config::new().with_validators(5),
    ];
    
    let results: Vec<_> = configs.par_iter().map(|config| {
        let model = AlpenglowModel::new(config.clone());
        let checker = Checker::new(&model);
        checker.check_all_properties()
    }).collect();
    
    assert!(results.iter().all(|r| r.is_ok()));
}
```

### Profiling

#### CPU Profiling

```bash
# Install flamegraph
cargo install flamegraph

# Profile specific test
cargo flamegraph --test properties -- test_safety_properties

# View flamegraph
open flamegraph.svg
```

#### Memory Profiling

```bash
# Use valgrind (Linux)
valgrind --tool=massif cargo test test_large_state_space

# Use heaptrack (Linux)
heaptrack cargo test test_memory_usage
```

#### Benchmarking

```rust
// Criterion benchmarks
use criterion::{black_box, criterion_group, criterion_main, Criterion};

fn benchmark_action_execution(c: &mut Criterion) {
    let config = Config::new().with_validators(4);
    let model = AlpenglowModel::new(config);
    
    c.bench_function("advance_clock", |b| {
        b.iter(|| {
            black_box(model.execute_action(AlpenglowAction::AdvanceClock))
        })
    });
}

criterion_group!(benches, benchmark_action_execution);
criterion_main!(benches);
```

### State Space Reduction

```rust
// Implement state constraints
impl AlpenglowModel {
    pub fn state_constraint(&self, state: &AlpenglowState) -> bool {
        // Limit exploration depth
        state.clock <= 100 &&
        // Limit message queue size
        state.network_message_queue.len() <= 50 &&
        // Limit view progression
        state.votor_view.values().all(|&view| view <= 10)
    }
}

// Use symmetry reduction
pub fn normalize_state(state: &mut AlpenglowState) {
    // Sort validators to break symmetry
    let mut sorted_validators: Vec<_> = state.votor_view.keys().copied().collect();
    sorted_validators.sort();
    
    // Renumber validators consistently
    let mut mapping = HashMap::new();
    for (new_id, &old_id) in sorted_validators.iter().enumerate() {
        mapping.insert(old_id, new_id as ValidatorId);
    }
    
    // Apply mapping to state
    state.apply_validator_mapping(&mapping);
}
```

## Property Checking Framework

### Property Definition

```rust
// Property trait for type safety
pub trait Property<State> {
    fn name(&self) -> &str;
    fn check(&self, state: &State) -> bool;
    fn description(&self) -> &str;
}

// Safety property implementation
pub struct SafetyProperty {
    name: String,
    checker: Box<dyn Fn(&AlpenglowState) -> bool>,
    description: String,
}

impl Property<AlpenglowState> for SafetyProperty {
    fn name(&self) -> &str { &self.name }
    fn description(&self) -> &str { &self.description }
    
    fn check(&self, state: &AlpenglowState) -> bool {
        (self.checker)(state)
    }
}

// Liveness property implementation
pub struct LivenessProperty {
    name: String,
    checker: Box<dyn Fn(&[AlpenglowState]) -> bool>,
    description: String,
}
```

### Built-in Properties

```rust
pub mod properties {
    use super::*;
    
    // Safety properties
    pub fn no_conflicting_finalization() -> SafetyProperty {
        SafetyProperty {
            name: "NoConflictingFinalization".to_string(),
            description: "No two conflicting blocks finalized in same slot".to_string(),
            checker: Box::new(|state| {
                state.finalized_blocks.values().all(|blocks| blocks.len() <= 1)
            }),
        }
    }
    
    pub fn certificate_validity(config: Config) -> SafetyProperty {
        SafetyProperty {
            name: "CertificateValidity".to_string(),
            description: "All certificates meet threshold requirements".to_string(),
            checker: Box::new(move |state| {
                state.votor_generated_certs.values()
                    .flat_map(|certs| certs.iter())
                    .all(|cert| match cert.cert_type {
                        CertificateType::Fast => cert.stake >= config.fast_path_threshold,
                        CertificateType::Slow => cert.stake >= config.slow_path_threshold,
                        CertificateType::Skip => cert.stake >= config.slow_path_threshold,
                    })
            }),
        }
    }
    
    // Liveness properties
    pub fn eventual_progress() -> LivenessProperty {
        LivenessProperty {
            name: "EventualProgress".to_string(),
            description: "Progress is eventually made".to_string(),
            checker: Box::new(|trace| {
                if trace.len() < 2 { return true; }
                let initial_slot = trace[0].current_slot;
                let final_slot = trace.last().unwrap().current_slot;
                final_slot > initial_slot
            }),
        }
    }
}
```

### Custom Property Creation

```rust
// Create custom safety property
pub fn create_custom_safety_property<F>(name: &str, description: &str, checker: F) -> SafetyProperty
where F: Fn(&AlpenglowState) -> bool + 'static
{
    SafetyProperty {
        name: name.to_string(),
        description: description.to_string(),
        checker: Box::new(checker),
    }
}

// Example usage
#[test]
fn test_custom_property() {
    let config = Config::new().with_validators(4);
    let model = AlpenglowModel::new(config);
    
    let custom_property = create_custom_safety_property(
        "NoEmptyBlocks",
        "All finalized blocks contain transactions",
        |state| {
            state.finalized_blocks.values()
                .flat_map(|blocks| blocks.iter())
                .all(|block| !block.transactions.is_empty())
        }
    );
    
    let checker = Checker::new(&model);
    checker.assert_property(custom_property);
}
```

### Property Composition

```rust
// Combine multiple properties
pub struct CompositeProperty {
    properties: Vec<Box<dyn Property<AlpenglowState>>>,
    name: String,
}

impl Property<AlpenglowState> for CompositeProperty {
    fn name(&self) -> &str { &self.name }
    fn description(&self) -> &str { "Composite of multiple properties" }
    
    fn check(&self, state: &AlpenglowState) -> bool {
        self.properties.iter().all(|prop| prop.check(state))
    }
}

// Create composite property
pub fn all_safety_properties(config: Config) -> CompositeProperty {
    CompositeProperty {
        name: "AllSafetyProperties".to_string(),
        properties: vec![
            Box::new(properties::no_conflicting_finalization()),
            Box::new(properties::certificate_validity(config)),
            Box::new(properties::chain_consistency()),
        ],
    }
}
```

## Extending the Implementation

### Adding New Components

#### 1. Define Component Module

```rust
// src/economic_model.rs
use crate::*;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct EconomicState {
    pub validator_rewards: HashMap<ValidatorId, StakeAmount>,
    pub slashed_stake: HashMap<ValidatorId, StakeAmount>,
    pub fee_pool: StakeAmount,
}

pub enum EconomicAction {
    DistributeRewards { validators: HashSet<ValidatorId> },
    SlashValidator { validator: ValidatorId, amount: StakeAmount },
    CollectFees { amount: StakeAmount },
}

impl EconomicState {
    pub fn init(config: &Config) -> Self {
        let mut validator_rewards = HashMap::new();
        let mut slashed_stake = HashMap::new();
        
        for validator in 0..config.validator_count {
            let validator_id = validator as ValidatorId;
            validator_rewards.insert(validator_id, 0);
            slashed_stake.insert(validator_id, 0);
        }
        
        Self {
            validator_rewards,
            slashed_stake,
            fee_pool: 0,
        }
    }
}
```

#### 2. Integrate with Main Model

```rust
// Update AlpenglowState
pub struct AlpenglowState {
    // ... existing fields ...
    pub economic_state: EconomicState,
}

// Update AlpenglowAction
pub enum AlpenglowAction {
    // ... existing variants ...
    Economic(EconomicAction),
}

// Update action execution
impl AlpenglowModel {
    fn execute_economic_action(&self, state: &mut AlpenglowState, action: EconomicAction) -> AlpenglowResult<()> {
        match action {
            EconomicAction::DistributeRewards { validators } => {
                let reward_per_validator = 100; // Simplified
                for validator in validators {
                    *state.economic_state.validator_rewards.entry(validator).or_insert(0) += reward_per_validator;
                }
            },
            EconomicAction::SlashValidator { validator, amount } => {
                *state.economic_state.slashed_stake.entry(validator).or_insert(0) += amount;
            },
            EconomicAction::CollectFees { amount } => {
                state.economic_state.fee_pool += amount;
            },
        }
        Ok(())
    }
}
```

#### 3. Add Component Tests

```rust
#[cfg(test)]
mod economic_tests {
    use super::*;
    
    #[test]
    fn test_reward_distribution() {
        let config = Config::new().with_validators(3);
        let mut model = AlpenglowModel::new(config);
        
        let action = AlpenglowAction::Economic(EconomicAction::DistributeRewards {
            validators: [0, 1, 2].iter().copied().collect(),
        });
        
        let new_state = model.execute_action(action).unwrap();
        
        // Verify rewards were distributed
        for validator in 0..3 {
            assert_eq!(new_state.economic_state.validator_rewards[&validator], 100);
        }
    }
}
```

### Adding New Properties

```rust
// Economic properties
pub fn stake_conservation(config: &Config) -> SafetyProperty {
    let total_initial_stake = config.total_stake;
    
    SafetyProperty {
        name: "StakeConservation".to_string(),
        description: "Total stake is conserved across all operations".to_string(),
        checker: Box::new(move |state| {
            let total_rewards: StakeAmount = state.economic_state.validator_rewards.values().sum();
            let total_slashed: StakeAmount = state.economic_state.slashed_stake.values().sum();
            let total_current = total_initial_stake + total_rewards - total_slashed + state.economic_state.fee_pool;
            
            total_current == total_initial_stake
        }),
    }
}
```

### Performance Extensions

```rust
// Add metrics collection
#[derive(Debug, Clone)]
pub struct PerformanceMetrics {
    pub action_counts: HashMap<String, u64>,
    pub execution_times: HashMap<String, Duration>,
    pub memory_usage: u64,
}

impl AlpenglowModel {
    pub fn execute_action_with_metrics(&mut self, action: AlpenglowAction) -> (AlpenglowResult<AlpenglowState>, PerformanceMetrics) {
        let start_time = Instant::now();
        let action_name = format!("{:?}", action);
        
        let result = self.execute_action(action);
        let execution_time = start_time.elapsed();
        
        let mut metrics = PerformanceMetrics {
            action_counts: HashMap::new(),
            execution_times: HashMap::new(),
            memory_usage: 0, // Would need actual memory measurement
        };
        
        *metrics.action_counts.entry(action_name.clone()).or_insert(0) += 1;
        metrics.execution_times.insert(action_name, execution_time);
        
        (result, metrics)
    }
}
```

## Cross-Validation Workflows

### Basic Cross-Validation

```bash
#!/bin/bash
# scripts/cross_validate.sh

set -e

echo "Starting cross-validation between TLA+ and Rust models..."

# Step 1: Run TLA+ model checking
echo "Running TLA+ verification..."
./scripts/check_model.sh Small > results/tla_results.log 2>&1

# Step 2: Run Rust model checking
echo "Running Rust verification..."
cd stateright
cargo test cross_validation > ../results/rust_results.log 2>&1
cd ..

# Step 3: Compare results
echo "Comparing results..."
python scripts/compare_results.py results/tla_results.log results/rust_results.log

echo "Cross-validation completed successfully!"
```

### Trace-Based Validation

```rust
// Import and replay TLA+ traces
#[test]
fn test_tla_trace_replay() {
    // Import TLA+ counterexample
    let trace_file = "results/latest/counterexample.tla";
    let tla_actions = import_tlc_trace(trace_file).unwrap();
    
    // Replay in Rust model
    let config = Config::new().with_validators(3);
    let model = AlpenglowModel::new(config);
    
    let final_state = replay_tla_trace(&model, tla_actions).unwrap();
    
    // Verify final state matches TLA+ result
    let expected_state = import_tla_final_state(trace_file).unwrap();
    assert_eq!(final_state, expected_state);
}
```

### Property Consistency Validation

```rust
#[test]
fn test_property_consistency() {
    let config = Config::new().with_validators(4);
    
    // Test same property in both models
    let rust_model = AlpenglowModel::new(config.clone());
    let tla_results = run_tla_property_check("SafetyInvariant", &config);
    
    let rust_checker = Checker::new(&rust_model);
    let rust_results = rust_checker.check_property("safety", |state| {
        properties::safety_no_conflicting_finalization(state)
    });
    
    // Both should agree on property satisfaction
    assert_eq!(tla_results.satisfied, rust_results.is_ok());
}
```

### Automated Cross-Validation Pipeline

```yaml
# .github/workflows/cross-validation.yml
name: Cross-Validation

on: [push, pull_request]

jobs:
  cross-validate:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2
    
    - name: Setup TLA+ Tools
      run: ./scripts/setup.sh
      
    - name: Setup Rust
      uses: actions-rs/toolchain@v1
      with:
        toolchain: stable
        
    - name: Run TLA+ Verification
      run: ./scripts/check_model.sh Small
      
    - name: Run Rust Verification
      run: |
        cd stateright
        cargo test
        
    - name: Cross-Validate Results
      run: ./scripts/cross_validate.sh
      
    - name: Upload Results
      uses: actions/upload-artifact@v2
      with:
        name: cross-validation-results
        path: results/
```

## Troubleshooting

### Common Issues

#### 1. State Synchronization Problems

**Problem**: Rust and TLA+ models have different initial states

**Solution**:
```rust
// Debug state initialization
#[test]
fn debug_state_init() {
    let config = Config::new().with_validators(3);
    let rust_state = AlpenglowState::init(&config);
    
    println!("Rust initial state:");
    println!("  clock: {}", rust_state.clock);
    println!("  current_slot: {}", rust_state.current_slot);
    println!("  votor_view: {:?}", rust_state.votor_view);
    
    // Compare with TLA+ initial state
    let tla_state = import_tla_initial_state("Small.cfg").unwrap();
    
    // Find differences
    if rust_state.clock != tla_state.clock {
        println!("Clock mismatch: Rust={}, TLA+={}", rust_state.clock, tla_state.clock);
    }
}
```

#### 2. Action Execution Differences

**Problem**: Same action produces different results

**Solution**:
```rust
// Debug action execution step by step
#[test]
fn debug_action_execution() {
    let config = Config::new().with_validators(3);
    let model = AlpenglowModel::new(config);
    let action = AlpenglowAction::AdvanceClock;
    
    println!("Before action: {:?}", model.state);
    
    let result = model.execute_action(action.clone());
    
    match result {
        Ok(new_state) => {
            println!("After action: {:?}", new_state);
            
            // Compare with TLA+ result
            let tla_result = execute_tla_action(&model.state, action);
            if new_state != tla_result {
                println!("Execution mismatch detected!");
                println!("Rust result: {:?}", new_state);
                println!("TLA+ result: {:?}", tla_result);
            }
        },
        Err(error) => {
            println!("Action failed: {:?}", error);
        }
    }
}
```

#### 3. Property Evaluation Differences

**Problem**: Property evaluates differently in Rust vs TLA+

**Solution**:
```rust
// Debug property evaluation
fn debug_property_evaluation(state: &AlpenglowState) -> bool {
    let result = properties::safety_no_conflicting_finalization(state);
    
    if !result {
        println!("Safety property violated!");
        println!("Finalized blocks: {:?}", state.finalized_blocks);
        
        // Check each slot for conflicts
        for (slot, blocks) in &state.finalized_blocks {
            if blocks.len() > 1 {
                println!("Conflict in slot {}: {:?}", slot, blocks);
            }
        }
    }
    
    result
}
```

#### 4. Performance Issues

**Problem**: Rust model checking is too slow

**Solutions**:

```rust
// 1. Use state constraints
impl AlpenglowModel {
    pub fn with_constraints(mut self) -> Self {
        self.config.max_slot = 10;  // Limit exploration
        self.config.max_view = 5;   // Limit view changes
        self
    }
}

// 2. Use simulation instead of exhaustive checking
#[test]
fn test_with_simulation() {
    let config = Config::new().with_validators(10);
    let model = AlpenglowModel::new(config);
    
    let mut checker = Checker::new(&model);
    checker.simulate(1000);  // Random exploration
}

// 3. Parallelize property checking
use rayon::prelude::*;

#[test]
fn test_parallel_properties() {
    let properties = vec![
        properties::no_conflicting_finalization(),
        properties::chain_consistency(),
        properties::certificate_validity(config.clone()),
    ];
    
    let results: Vec<_> = properties.par_iter().map(|prop| {
        // Check property in parallel
        check_property_on_model(prop, &model)
    }).collect();
    
    assert!(results.iter().all(|r| r.is_ok()));
}
```

### Debugging Tools

#### 1. State Diff Tool

```rust
pub fn diff_states(rust_state: &AlpenglowState, tla_state: &AlpenglowState) -> Vec<String> {
    let mut diffs = Vec::new();
    
    if rust_state.clock != tla_state.clock {
        diffs.push(format!("clock: {} vs {}", rust_state.clock, tla_state.clock));
    }
    
    if rust_state.current_slot != tla_state.current_slot {
        diffs.push(format!("current_slot: {} vs {}", rust_state.current_slot, tla_state.current_slot));
    }
    
    // Compare complex fields
    for validator in rust_state.votor_view.keys() {
        let rust_view = rust_state.votor_view.get(validator);
        let tla_view = tla_state.votor_view.get(validator);
        if rust_view != tla_view {
            diffs.push(format!("votor_view[{}]: {:?} vs {:?}", validator, rust_view, tla_view));
        }
    }
    
    diffs
}
```

#### 2. Trace Comparison Tool

```rust
pub fn compare_traces(rust_trace: &[AlpenglowState], tla_trace: &[AlpenglowState]) -> Result<(), String> {
    if rust_trace.len() != tla_trace.len() {
        return Err(format!("Trace length mismatch: {} vs {}", rust_trace.len(), tla_trace.len()));
    }
    
    for (i, (rust_state, tla_state)) in rust_trace.iter().zip(tla_trace.iter()).enumerate() {
        let diffs = diff_states(rust_state, tla_state);
        if !diffs.is_empty() {
            return Err(format!("State mismatch at step {}: {}", i, diffs.join(", ")));
        }
    }
    
    Ok(())
}
```

#### 3. Property Debugging

```rust
pub fn debug_property_failure<F>(state: &AlpenglowState, property: F, name: &str) 
where F: Fn(&AlpenglowState) -> bool
{
    if !property(state) {
        println!("Property '{}' failed on state:", name);
        println!("  Clock: {}", state.clock);
        println!("  Current slot: {}", state.current_slot);
        println!("  Finalized blocks: {}", state.finalized_blocks.len());
        println!("  Message queue size: {}", state.network_message_queue.len());
        
        // Save state for further analysis
        let state_json = serde_json::to_string_pretty(state).unwrap();
        std::fs::write(format!("debug_state_{}.json", name), state_json).unwrap();
    }
}
```

## Best Practices

### Code Organization

1. **Mirror TLA+ Structure**: Keep Rust modules aligned with TLA+ modules
2. **Type Safety**: Use strong typing to prevent invalid states
3. **Documentation**: Document mapping between TLA+ and Rust constructs
4. **Testing**: Comprehensive test coverage for all components

### Performance Guidelines

1. **State Constraints**: Always use appropriate state constraints
2. **Simulation**: Use simulation for large state spaces
3. **Profiling**: Regular performance profiling and optimization
4. **Parallel Execution**: Leverage parallelism where possible

### Cross-Validation Guidelines

1. **Frequent Validation**: Run cross-validation on every change
2. **Trace Preservation**: Save traces for debugging
3. **Property Consistency**: Ensure properties are equivalent
4. **Automated Testing**: Use CI/CD for continuous validation

### Debugging Guidelines

1. **Incremental Testing**: Test small changes incrementally
2. **State Inspection**: Use debug output liberally
3. **Trace Analysis**: Analyze execution traces for discrepancies
4. **Property Debugging**: Debug property failures systematically

---

*This guide provides comprehensive coverage of the Stateright implementation for the Alpenglow protocol. For additional help, refer to the main documentation or open an issue in the repository.*