# Alpenglow Consensus Protocol - Formal Verification

A comprehensive formal verification project for the Solana Alpenglow consensus protocol, featuring TLA+ specifications, mathematical proofs, Rust implementations, and automated verification pipelines.

## Project Overview

This project provides formal verification of the Alpenglow consensus protocol through multiple complementary approaches:

- **TLA+ Specifications**: Formal mathematical models of the consensus protocol
- **Mathematical Proofs**: Rigorous proofs of safety and liveness properties
- **Rust Implementation**: Production-ready implementation with formal verification
- **Stateright Integration**: Model checking using the Stateright framework
- **Automated Verification**: Continuous integration pipeline for comprehensive testing

## Directory Structure

```
├── specs/                  # TLA+ formal specifications
├── proofs/                 # Mathematical proofs and theorems
├── implementation/         # Rust production implementation
├── stateright/            # Stateright model checker implementation
├── models/                # TLA+ configuration files
├── scripts/               # Organized scripts
│   ├── production/        # Production deployment scripts
│   ├── dev/              # Development and testing scripts
│   └── ci/               # CI/CD pipeline scripts
├── docs/                  # Comprehensive documentation
├── submission/            # Formal submission package
└── ci/                    # CI/CD configuration files
```

## Quick Start Guide

### Prerequisites

- **TLA+ Tools**: TLC model checker and TLAPS proof system
- **Rust**: Latest stable version with Cargo
- **Python**: 3.8+ for analysis tools
- **Java**: 11+ for TLA+ tools

### Running Verification

1. **Model Checking**:
   ```bash
   ./scripts/ci/check_model.sh Small
   ./scripts/ci/check_model.sh Medium --verbose
   ```

2. **Proof Verification**:
   ```bash
   ./scripts/ci/verify_proofs.sh all
   ./scripts/ci/verify_proofs.sh AlpenglowSafety
   ```

3. **Rust Implementation Tests**:
   ```bash
   cd implementation
   cargo test
   ```

4. **Stateright Model Checking**:
   ```bash
   cd stateright
   cargo test
   ```

### Development Workflow

For development and testing, use the scripts in `scripts/dev/`:

```bash
# Local verification
./scripts/dev/localverify.sh

# Test verification pipeline
./scripts/dev/test_verification.sh

# Run TLC with custom options
./scripts/dev/run_tlc.sh
```

## Script Organization

The `scripts/` directory is organized by purpose:

### Production Scripts (`scripts/production/`)
- Essential scripts for production deployment
- Version-controlled and maintained as core project components
- Used for official verification and deployment

### Development Scripts (`scripts/dev/`)
- Development and testing utilities
- Local verification and debugging tools
- Not included in production deployments

### CI/CD Scripts (`scripts/ci/`)
- Automated pipeline scripts
- Used by continuous integration system
- Essential for automated verification

## Development vs Production

### Production Components
- `specs/` - Core TLA+ specifications
- `proofs/` - Mathematical proofs
- `implementation/` - Production Rust code
- `scripts/production/` - Deployment scripts
- `docs/` - Official documentation

### Development Tools
- `scripts/dev/` - Development utilities
- Local verification scripts
- Debugging and analysis tools
- Performance benchmarking (when needed)

## CI/CD Integration

The automated verification pipeline runs:

1. **Model Checking**: Multiple configurations (Small, Medium, EdgeCase)
2. **Proof Verification**: All mathematical proofs
3. **Implementation Tests**: Rust unit and integration tests
4. **Cross-Validation**: Consistency checks between specifications
5. **Performance Analysis**: Scalability and performance metrics

### Pipeline Configuration

See `ci/verify_all.yml` for the complete CI configuration. The pipeline:

- Runs on multiple configurations in parallel
- Generates verification reports
- Handles timeouts and error conditions
- Provides detailed logging and artifacts

## Contributing Guidelines

To maintain the clean project structure:

### Adding New Features

1. **Specifications**: Add TLA+ specs to `specs/`
2. **Proofs**: Add mathematical proofs to `proofs/`
3. **Implementation**: Add Rust code to `implementation/`
4. **Tests**: Add tests in appropriate test directories

### Development Workflow

1. Use `scripts/dev/` for development tools
2. Test locally before submitting
3. Ensure CI pipeline passes
4. Update documentation as needed

### Script Guidelines

- **Production scripts**: Place in `scripts/production/`
- **Development tools**: Place in `scripts/dev/` (git-ignored)
- **CI scripts**: Place in `scripts/ci/`
- Always update documentation when adding scripts

### Code Quality

- Follow existing code conventions
- Add comprehensive tests
- Update relevant documentation
- Ensure CI pipeline compatibility

## Documentation

Comprehensive documentation is available in the `docs/` directory:

- `VerificationGuide.md` - Detailed verification instructions
- `DevelopmentGuide.md` - Development workflow and tools
- `CrossValidationGuide.md` - Cross-validation procedures
- `ProductionDeploymentGuide.md` - Production deployment guide

## License

[License information to be added]

## Contact

[Contact information to be added]
