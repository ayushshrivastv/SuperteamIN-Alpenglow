<!-- Author: Ayush Srivastava -->

# Alpenglow Test Suite

This directory contains comprehensive tests for the Alpenglow formal verification framework.

## Structure

- **unit/**: Unit tests for individual components
- **integration/**: Integration tests for component interactions
- **property/**: Property-based tests for invariants
- **performance/**: Performance and stress tests
- **scripts/**: Test automation scripts

## Running Tests

### Unit Tests
```bash
cd unit/
./run_unit_tests.sh
```

### Integration Tests
```bash
cd integration/
./run_integration_tests.sh
```

### Property Tests
```bash
cd property/
./run_property_tests.sh
```

### Performance Tests
```bash
cd performance/
./run_performance_tests.sh
```

### All Tests
```bash
cd scripts/
./run_all_tests.sh
```

## Test Coverage

| Component | Unit | Integration | Property | Performance |
|-----------|------|-------------|----------|-------------|
| Votor | ✅ | ✅ | ✅ | ✅ |
| Rotor | ✅ | ✅ | ✅ | ✅ |
| Network | ✅ | ✅ | ✅ | ✅ |
| Integration | - | ✅ | ✅ | ✅ |

## Adding New Tests

1. Choose the appropriate directory based on test type
2. Follow the naming convention: `test_<component>_<feature>.tla`
3. Include test documentation in the file header
4. Update this README with new test coverage
