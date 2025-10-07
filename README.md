# Alpenglow Formal Verification

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![TLA+](https://img.shields.io/badge/TLA+-1.8.0-blue)](https://lamport.azurewebsites.net/tla/tla.html)
[![Stateright](https://img.shields.io/badge/Stateright-0.29.0-green)](https://github.com/stateright/stateright)
[![Java](https://img.shields.io/badge/Java-11+-orange)](https://adoptopenjdk.net/)
[![Rust](https://img.shields.io/badge/Rust-1.70+-red)](https://rustlang.org/)

## Formal Verification of Solana Alpenglow Consensus Protocol

Mathematical rigor meets blockchain innovation. This project transforms the theoretical foundations of Solana's Alpenglow consensus protocol into machine-verified mathematical proofs using formal methods.

Traditional blockchain consensus protocols rely on informal arguments and empirical testing. Alpenglow demands more. By applying formal verification techniques including TLA+ specifications and Stateright model checking, this project provides mathematical guarantees about the protocol's safety, liveness, and resilience properties.

[![Alpenglow Formal Verification](https://img.youtube.com/vi/nLAxTzorDZE/0.jpg)](https://youtu.be/nLAxTzorDZE?si=anxjiUg4fGaUVoFk)

No more crossing fingers and hoping the consensus works correctly. Every theorem from the Alpenglow whitepaper is now backed by machine-verified proofs that can be independently validated and extended. This represents a new standard for consensus protocol verification in the blockchain industry.

For detailed technical understanding of the formal specifications, refer to the [Specifications Documentation](./docs/specifications.md). For implementation details, see [Architecture Guide](./docs/architecture.md).

### Your Gateway to Mathematically Proven Consensus

<img src="docs/assets/alpenglow-architecture.png" width="700" alt="Alpenglow Consensus Architecture"/>

### Formal Methods: Proving Consensus Correctness at Scale

<img src="docs/assets/formal-verification-pipeline.png" width="700" alt="Formal Verification Pipeline"/>

## How It Actually Works

The Alpenglow consensus protocol operates through two distinct voting paths with different finalization thresholds. This dual-path approach enables both fast consensus under optimal conditions and robust consensus under adversarial conditions.

**Votor (Voting Component)**: Manages the dual voting mechanisms with fast path (80% threshold) for rapid finalization and slow path (60% threshold) for guaranteed progress under partial synchrony.

**Rotor (Relay Component)**: Implements erasure-coded block propagation with stake-weighted sampling, ensuring efficient and secure block distribution across the network.

**Certificate Management**: Handles aggregation, uniqueness verification, and timeout mechanisms with mathematically proven properties for non-equivocation and bounded finalization time.

## Getting Started

### Prerequisites

Ensure you have the following installed:

**Java 11+** for TLA+ tools execution and model checking operations. **TLA+ Tools** including TLC model checker and TLAPS proof system for formal verification. **Rust 1.70+** for Stateright integration and implementation verification. **Python 3.8+** for analysis and visualization tools. **Docker** (optional) for containerized verification environment.

### Installation

```bash
# Clone the repository
git clone https://github.com/ayushshrivastv/SuperteamIN-Alpenglow.git
cd SuperteamIN-Alpenglow

# TLA+ tools are already included in tools/tla2tools.jar
# Verify installation
java -cp tools/tla2tools.jar tlc2.TLC

# Install Rust dependencies
cd stateright && cargo build --release && cd ..
cd implementation && cargo build --release && cd ..
```

## Verification Commands

### Core Protocol Verification

**Votor (Voting Component)**
```bash
java -XX:+UseParallelGC -cp tools/tla2tools.jar tlc2.TLC specs/Votor.tla -config models/VotorCore.cfg
```

**Rotor (Block Propagation)**
```bash
java -XX:+UseParallelGC -cp tools/tla2tools.jar tlc2.TLC specs/RotorSimple.tla -config models/RotorSimpleTest.cfg
```

### Property Verification

**Safety and Liveness Properties**
```bash
java -XX:+UseParallelGC -Xmx2g -cp tools/tla2tools.jar tlc2.TLC specs/LivenessProperties.tla -config specs/LivenessProperties.cfg
```

### Multi-Node Configuration Testing

**3-Node Configuration**
```bash
java -XX:+UseParallelGC -jar tools/tla2tools.jar -config specs/LivenessProperties.cfg specs/LivenessProperties.tla
```

**5-Node Configuration**
```bash
java -XX:+UseParallelGC -jar tools/tla2tools.jar -config models/VotorCore.cfg specs/Votor.tla
```

**7-Node Resilience Testing**
```bash
java -XX:+UseParallelGC -jar tools/tla2tools.jar -config models/ResilienceTest.cfg specs/ResilienceSimple.tla
```

## Docker Deployment

Build and run the verification environment:

```bash
# Build the verification image
./build_verification.sh

# Run the verification environment
docker run --rm alpenglow-verification
```
## Project Structure

```
├── specs/                          # TLA+ formal specifications (36 files)
│   ├── Alpenglow.tla              # Complete protocol specification
│   ├── Votor.tla                  # Voting protocol specification
│   ├── Rotor.tla                  # Block propagation specification
│   ├── RotorSimple.tla            # Simplified Rotor model
│   ├── LivenessProperties.tla     # Liveness theorem proofs
│   ├── SafetyCore.tla             # Safety property proofs
│   ├── ResilienceSimple.tla       # Byzantine resilience testing
│   ├── AdaptiveTimeouts.tla       # Timeout mechanism verification
│   ├── EconomicModel.tla          # Economic incentive modeling
│   └── foundation/                # Foundational specifications
├── models/                        # TLA+ configuration files (43 files)
│   ├── VotorCore.cfg              # Core voting configuration
│   ├── RotorSimpleTest.cfg        # Block propagation test config
│   ├── ResilienceTest.cfg         # Byzantine resilience testing
│   ├── LivenessProperties.cfg     # Liveness property verification
│   ├── EndToEnd.cfg               # Complete protocol testing
│   ├── LargeScale.cfg             # Large-scale network testing
│   └── WhitepaperValidation.cfg   # Whitepaper theorem validation
├── stateright/                    # Stateright model checker (26 files)
│   ├── src/                       # Rust implementation models
│   ├── tests/                     # Model checking tests
│   └── Cargo.toml                 # Rust dependencies
├── implementation/                # Production Rust implementation (5 files)
│   ├── consensus/                 # Core consensus algorithms
│   ├── networking/                # P2P networking layer
│   └── benchmarks/                # Performance benchmarking
├── proofs/                        # Mathematical theorem proofs (17 files)
│   ├── safety/                    # Safety property proofs
│   ├── liveness/                  # Liveness property proofs
│   └── resilience/                # Byzantine resilience proofs
├── tools/                         # Verification tools
│   └── tla2tools.jar              # TLA+ model checker v1.8.0
├── scripts/                       # Automation scripts (12 files)
│   ├── ci/                        # CI/CD pipeline scripts
│   └── dev/                       # Development utilities
├── reports/                       # Verification reports (8 files)
├── theorem_mapping_reports/       # Theorem validation reports (5 files)
├── submission/                    # Formal submission package (10 files)
├── conformance/                   # Conformance testing (3 files)
├── cross-validation/              # Cross-validation testing (4 files)
├── tests/                         # Additional test suites (5 files)
├── ci/                           # CI/CD configuration
├── ci-cd/                        # Extended CI/CD setup (10 files)
├── explorations/                  # Research explorations (3 files)
├── examples/                      # Usage examples
├── Dockerfile                     # Containerized verification environment
├── Dockerfile.quick               # Quick verification setup
├── localverify.sh                 # Comprehensive local verification script
├── build_verification.sh          # Build verification tools
└── quick_local_test.sh            # Quick verification test
```
## The Technology Stack

**Formal Specification Layer**

TLA+ specifications provide comprehensive protocol modeling with over 36 formal specifications covering all aspects of the Alpenglow consensus mechanism. Mathematical theorems with machine-verified proofs establish safety, liveness, and resilience properties through rigorous formal verification. Stateright integration enables Rust-based model checking that bridges abstract specifications with concrete implementations.

**Verification Infrastructure**

Exhaustive model checking validates protocol correctness across all possible execution paths for small configurations. Statistical model checking scales verification to realistic network sizes while maintaining rigorous correctness guarantees. Continuous integration pipeline provides automated verification through comprehensive test suites and validation scripts.

**Implementation Validation**

Property-based testing ensures formal specification alignment with implementation behavior across all protocol components. Byzantine fault injection validates protocol resilience under adversarial conditions with systematic fault introduction. Performance benchmarking confirms theoretical bounds against empirical measurements using integrated analysis tools.

## Key Features

**Complete Formal Specification**

Protocol modeling covers Votor's dual voting paths with fast 80% and slow 60% finalization thresholds, ensuring both rapid consensus under optimal conditions and guaranteed progress under adversarial scenarios. Rotor's erasure-coded block propagation includes stake-weighted relay sampling for efficient network distribution. Certificate generation, aggregation, and uniqueness properties maintain consensus integrity across all network conditions. Timeout mechanisms and skip certificate logic provide robustness under network partitions and asynchronous conditions. Leader rotation and window management guarantee fair participation across all network participants.

**Machine-Verified Safety Properties**

No two conflicting blocks can be finalized in the same slot, ensuring fundamental consensus safety through mathematical proof verification. Chain consistency is maintained under up to 20% Byzantine stake through formal verification of fault tolerance mechanisms. Certificate uniqueness and non-equivocation guarantees prevent double-voting and maintain protocol integrity across all possible execution scenarios.

**Proven Liveness Properties**

Progress guarantee under partial synchrony with greater than 60% honest participation ensures forward progress even under adverse network conditions. Fast path completion in one round with greater than 80% responsive stake enables rapid consensus under optimal network conditions. Bounded finalization time follows the minimum of δ₈₀% and 2δ₆₀% as formally proven in the whitepaper specifications.

**Resilience Guarantees**

Safety is maintained with up to 20% Byzantine stake under worst-case adversarial scenarios through comprehensive formal verification. Liveness continues with up to 20% non-responsive stake ensuring continued operation under network stress conditions. Network partition recovery provides mathematical guarantees about protocol behavior during and after network splits with formal correctness proofs.

**License**: This project is licensed under the MIT License - see the [LICENSE](./LICENSE) file for details.


