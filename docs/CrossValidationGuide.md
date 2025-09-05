# Cross-Validation Guide for Alpenglow Protocol

This guide provides comprehensive documentation for the cross-validation system that validates the Alpenglow consensus protocol implementation between Rust (Stateright) and TLA+ formal specifications.

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Property Mapping System](#property-mapping-system)
4. [Verification Scripts](#verification-scripts)
5. [Integration Tests](#integration-tests)
6. [State Export Utility](#state-export-utility)
7. [Usage Examples](#usage-examples)
8. [Troubleshooting](#troubleshooting)
9. [Best Practices](#best-practices)
10. [Contributing](#contributing)

## Overview

The cross-validation system ensures consistency between two independent implementations of the Alpenglow protocol:

- **Rust Implementation**: Uses the Stateright model checker for exhaustive state space exploration
- **TLA+ Implementation**: Uses TLC (TLA+ model checker) for formal verification

### Key Features

- **Property Mapping**: Automatic translation between Rust and TLA+ property names
- **Enhanced Verification Scripts**: Support for dynamic constants, timeouts, and JSON output
- **Cross-Validation Pipeline**: Automated comparison of verification results
- **State Export**: Export representative states for cross-analysis
- **Integration Testing**: End-to-end tests for the complete pipeline

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Rust/Stateright │    │  Property Mapping │    │    TLA+/TLC     │
│   Implementation   │◄──►│      System      │◄──►│ Implementation  │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                        │                        │
         ▼                        ▼                        ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│ Stateright      │    │ Cross-Validation │    │ TLA+ Results    │
│ Results (JSON)  │───►│    Pipeline      │◄───│ (JSON)          │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                │
                                ▼
                    ┌──────────────────┐
                    │ Validation Report│
                    │ & Consistency    │
                    │ Analysis         │
                    └──────────────────┘
```

### Core Components

1. **Property Mapping (`scripts/property_mapping.json`)**: Defines correspondence between Rust and TLA+ properties
2. **Enhanced Verification Scripts**: `stateright_verify.sh` and `check_model.sh` with cross-validation support
3. **Integration Tests (`stateright/tests/cross_pipeline.rs`)**: End-to-end validation of the pipeline
4. **State Export Utility (`stateright/bin/export_states.rs`)**: Export states for cross-analysis
5. **Invariant Validation**: Complete implementation in all Rust state modules

## Property Mapping System

The property mapping system (`scripts/property_mapping.json`) provides bidirectional translation between Rust and TLA+ property names.

### Structure

```json
{
  "version": "1.0.0",
  "mappings": {
    "safety_properties": {
      "rust_to_tla": {
        "VotorSafety": "VotorSafetyInvariant",
        "NonEquivocation": "NonEquivocationProperty"
      },
      "tla_to_rust": {
        "VotorSafetyInvariant": "VotorSafety",
        "NonEquivocationProperty": "NonEquivocation"
      }
    },
    "liveness_properties": { /* ... */ },
    "type_invariants": { /* ... */ },
    "partial_synchrony_properties": { /* ... */ },
    "performance_properties": { /* ... */ }
  }
}
```

### Property Categories

- **Safety Properties**: Invariants that must always hold (e.g., no equivocation)
- **Liveness Properties**: Properties ensuring progress (e.g., eventual delivery)
- **Type Invariants**: Structural correctness properties
- **Partial Synchrony Properties**: Network timing and partition handling
- **Performance Properties**: Resource usage and efficiency constraints

## Verification Scripts

### Enhanced `stateright_verify.sh`

Orchestrates Stateright verification with optional TLA+ cross-validation.

#### Usage

```bash
./scripts/stateright_verify.sh [OPTIONS]

Options:
  --config CONFIG          Model configuration (small, medium, large)
  --cross-validate         Enable TLA+ cross-validation
  --parallel              Run verifications in parallel
  --timeout SECONDS       Set timeout (default: 1800)
  --report                Generate detailed HTML report
  --scenarios SCENARIOS   Comma-separated list of scenarios to test
```

#### Key Features

- **Property Mapping Integration**: Uses `property_mapping.json` for result correlation
- **Enhanced Cross-Validation**: Property-level consistency checking
- **JSON Output**: Structured results for automation
- **Parallel Execution**: Concurrent Stateright and TLA+ verification
- **Detailed Reporting**: HTML reports with cross-validation analysis

### Enhanced `check_model.sh`

TLA+ model checking with dynamic constants and cross-validation support.

#### Usage

```bash
./scripts/check_model.sh [CONFIG] [OPTIONS]

Configurations: Small, Medium, Boundary, EdgeCase, Partition

Enhanced Options:
  --constants KEY=VALUE,KEY2=VALUE2  Set dynamic TLA+ constants
  --json                             Generate JSON summary
  --cross-validate                   Enable cross-validation features
  --simulate                         Run in simulation mode
  --timeout SECONDS                  Set timeout (default: 3600)
```

#### Key Features

- **Dynamic Constants**: Runtime configuration of TLA+ constants
- **Property Mapping**: Integration with cross-validation system
- **Enhanced Result Parsing**: Detailed property-level analysis
- **JSON Output**: Structured results for cross-validation
- **Timeout Handling**: Graceful handling of long-running verifications

## Integration Tests

The integration test suite (`stateright/tests/cross_pipeline.rs`) provides end-to-end validation of the cross-validation pipeline.

### Test Configurations

```rust
// Small safety test
CrossValidationTestConfig {
    name: "small_safety",
    config: Config::small(),
    expected_properties: vec!["VotorSafety", "NonEquivocation"],
    timeout_seconds: 300,
    simulate_mode: false,
}

// Byzantine resilience test
CrossValidationTestConfig {
    name: "byzantine_resilience",
    config: Config::byzantine(),
    expected_properties: vec!["ByzantineResilience"],
    timeout_seconds: 900,
    simulate_mode: false,
}
```

### Running Tests

```bash
# Run basic cross-validation tests
cargo test --test cross_pipeline

# Run specific test (requires TLA+ tools)
cargo test --test cross_pipeline test_small_safety_cross_validation -- --ignored

# Run full test suite (long-running)
cargo test --test cross_pipeline test_full_cross_validation_suite -- --ignored
```

## State Export Utility

The state export utility (`stateright/bin/export_states.rs`) exports representative states from Stateright verification for TLA+ analysis.

### Usage

```bash
cargo run --bin export_states -- [OPTIONS]

Options:
  -c, --config CONFIG      Model configuration (small, medium, large, byzantine)
  -o, --output DIR         Output directory (default: ./exported_states)
  -f, --format FORMAT      Export format (json, tla, csv, all)
  -m, --mode MODE          Export mode (initial, violating, representative, traces)
  --max-states N           Maximum states to export (default: 100)
  -p, --properties PROPS   Filter by properties (comma-separated)
  --scenario SCENARIO      Scenario name for scenario mode
  --include-traces         Include execution traces
```

### Export Modes

- **Initial States**: Export initial states for TLA+ model initialization
- **Violating States**: Export states that violate specific properties
- **Representative States**: Export representative states from successful runs
- **Complete Traces**: Export complete execution traces
- **Scenario States**: Export states for specific scenarios

### Output Formats

- **JSON**: Structured data with full state information
- **TLA+**: TLA+ module format for direct import
- **CSV**: Tabular format for analysis tools
- **All**: Generate all formats

## Usage Examples

### Basic Cross-Validation

```bash
# Run small configuration with cross-validation
./scripts/stateright_verify.sh --config small --cross-validate

# Run with specific scenarios
./scripts/stateright_verify.sh --config medium --cross-validate \
  --scenarios safety,liveness,byzantine --report
```

### TLA+ Verification with Dynamic Constants

```bash
# Run with custom constants
./scripts/check_model.sh Small --constants N=4,F=1 --json --timeout 7200

# Run Byzantine scenario
./scripts/check_model.sh EdgeCase --constants BYZANTINE_NODES=2 \
  --cross-validate --json
```

### State Export for Analysis

```bash
# Export representative states as JSON
cargo run --bin export_states -- --config small --format json \
  --mode representative --max-states 50

# Export violating states for debugging
cargo run --bin export_states -- --config byzantine --format all \
  --mode violating --properties ByzantineResilience,VotorSafety

# Export TLA+ format for cross-validation
cargo run --bin export_states -- --config medium --format tla \
  --mode initial --max-states 10
```

### Integration Testing

```bash
# Run cross-validation integration tests
cargo test --test cross_pipeline test_cross_validation_pipeline_setup

# Run end-to-end test (requires TLA+ tools)
cargo test --test cross_pipeline test_small_safety_cross_validation -- --ignored
```

## Troubleshooting

### Common Issues

#### Property Mapping Not Found

```
Error: Property mapping file not found: scripts/property_mapping.json
```

**Solution**: Ensure `scripts/property_mapping.json` exists and is valid JSON.

#### TLA+ Tools Not Available

```
Warning: TLA+ tools not found. Cross-validation will be limited.
```

**Solution**: Install TLA+ tools and ensure `tla2tools.jar` is in `$HOME/tla-tools/`.

#### Timeout Issues

```
Warning: Model checking timed out after 3600s
```

**Solution**: Increase timeout or reduce model size:
```bash
./scripts/check_model.sh Small --timeout 7200
```

#### Inconsistent Results

```
Error: Inconsistencies detected in: safety, liveness
```

**Solution**: 
1. Check property mappings in `scripts/property_mapping.json`
2. Verify both implementations handle the same scenarios
3. Review counterexamples in result directories

### Debugging Steps

1. **Check Prerequisites**:
   ```bash
   # Verify TLA+ tools
   java -cp $HOME/tla-tools/tla2tools.jar tlc2.TLC -help
   
   # Verify Rust build
   cargo build --release
   ```

2. **Run Individual Components**:
   ```bash
   # Test Stateright only
   ./scripts/stateright_verify.sh --config small
   
   # Test TLA+ only
   ./scripts/check_model.sh Small --json
   ```

3. **Check Property Mapping**:
   ```bash
   # Validate JSON syntax
   jq empty scripts/property_mapping.json
   
   # Check mapping completeness
   jq '.mappings | keys' scripts/property_mapping.json
   ```

4. **Examine Results**:
   ```bash
   # Check latest results
   ls -la results/stateright/session_*/
   
   # View cross-validation report
   jq . results/stateright/session_*/cross_validation.json
   ```

## Best Practices

### Property Mapping Maintenance

1. **Keep Mappings Synchronized**: Update property mappings when adding new properties
2. **Use Descriptive Names**: Property names should clearly indicate their purpose
3. **Version Control**: Track changes to property mappings with version numbers
4. **Validate Mappings**: Regularly test that mappings are bidirectional and complete

### Verification Strategy

1. **Start Small**: Begin with small configurations before scaling up
2. **Incremental Testing**: Test individual properties before full suites
3. **Regular Cross-Validation**: Run cross-validation in CI/CD pipelines
4. **Document Differences**: Record and explain any expected differences between implementations

### Performance Optimization

1. **Use Appropriate Timeouts**: Set realistic timeouts based on configuration size
2. **Parallel Execution**: Use parallel mode for independent verifications
3. **Selective Testing**: Use property filters for focused testing
4. **Resource Monitoring**: Monitor memory and CPU usage during verification

### Result Analysis

1. **Automated Reporting**: Use JSON output for automated analysis
2. **Trend Tracking**: Monitor verification metrics over time
3. **Counterexample Analysis**: Systematically analyze violations and counterexamples
4. **Cross-Reference Results**: Compare results across different configurations

## Contributing

### Adding New Properties

1. **Implement in Rust**: Add property validation to appropriate state modules
2. **Implement in TLA+**: Add corresponding invariants/properties to TLA+ specs
3. **Update Property Mapping**: Add bidirectional mappings to `property_mapping.json`
4. **Add Tests**: Include property in integration test configurations
5. **Update Documentation**: Document the new property and its purpose

### Extending Verification Scripts

1. **Maintain Backward Compatibility**: Ensure existing functionality continues to work
2. **Add Command-Line Options**: Use consistent option naming and help text
3. **Update JSON Schema**: Maintain consistent JSON output format
4. **Test Integration**: Verify that changes work with the cross-validation pipeline

### Improving Property Mapping

1. **Add New Categories**: Extend mapping categories as needed
2. **Enhance Validation**: Add validation for mapping completeness and consistency
3. **Support Aliases**: Allow multiple names for the same property
4. **Add Metadata**: Include property descriptions and categories

### Performance Improvements

1. **Optimize State Space**: Reduce unnecessary state exploration
2. **Improve Parsing**: Optimize result parsing and analysis
3. **Enhance Caching**: Cache intermediate results where appropriate
4. **Parallel Processing**: Identify opportunities for parallelization

---

## Appendix

### Property Mapping Schema

```json
{
  "type": "object",
  "properties": {
    "version": {"type": "string"},
    "mappings": {
      "type": "object",
      "properties": {
        "safety_properties": {"$ref": "#/definitions/bidirectional_mapping"},
        "liveness_properties": {"$ref": "#/definitions/bidirectional_mapping"},
        "type_invariants": {"$ref": "#/definitions/bidirectional_mapping"},
        "partial_synchrony_properties": {"$ref": "#/definitions/bidirectional_mapping"},
        "performance_properties": {"$ref": "#/definitions/bidirectional_mapping"}
      }
    }
  },
  "definitions": {
    "bidirectional_mapping": {
      "type": "object",
      "properties": {
        "rust_to_tla": {"type": "object"},
        "tla_to_rust": {"type": "object"}
      }
    }
  }
}
```

### Exit Codes

- **0**: All verifications passed and are consistent
- **1**: Some verifications failed or inconsistencies detected
- **2**: Critical error (build failure, missing dependencies, timeout)
- **124**: Timeout occurred during verification

### File Structure

```
project/
├── scripts/
│   ├── property_mapping.json      # Property mappings
│   ├── stateright_verify.sh       # Enhanced Stateright verification
│   └── check_model.sh             # Enhanced TLA+ verification
├── stateright/
│   ├── tests/
│   │   └── cross_pipeline.rs      # Integration tests
│   ├── bin/
│   │   └── export_states.rs       # State export utility
│   └── src/
│       ├── lib.rs                 # TlaCompatible trait
│       ├── votor.rs               # Votor invariant validation
│       ├── rotor.rs               # Rotor invariant validation
│       └── network.rs             # Network invariant validation
├── results/
│   └── stateright/
│       └── session_*/             # Verification results
└── docs/
    └── CrossValidationGuide.md    # This guide
```

This comprehensive cross-validation system ensures that the Rust and TLA+ implementations of the Alpenglow protocol remain consistent and correct through automated verification and analysis.
