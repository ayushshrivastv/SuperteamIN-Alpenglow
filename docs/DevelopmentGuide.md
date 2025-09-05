# Alpenglow Protocol Development Guide

## Table of Contents
1. [Project Structure](#project-structure)
2. [Development Workflow](#development-workflow)
3. [Writing Specifications](#writing-specifications)
4. [Adding Model Configurations](#adding-model-configurations)
5. [Writing Proofs](#writing-proofs)
6. [Testing Guidelines](#testing-guidelines)
7. [Code Style](#code-style)
8. [Contributing](#contributing)

## Project Structure

```
alpenglow/
├── specs/              # TLA+ specifications
│   ├── Alpenglow.tla  # Main protocol specification
│   ├── Votor.tla      # Voting component
│   ├── Rotor.tla      # Rotation component
│   ├── Types.tla      # Type definitions
│   ├── Network.tla    # Network model
│   ├── Crypto.tla     # Cryptographic abstractions
│   ├── Timing.tla     # Timing models
│   ├── Utils.tla      # Utility functions
│   └── Stake.tla      # Stake management
├── models/            # Model configurations
│   ├── Small.cfg      # Quick verification (3 validators)
│   ├── Medium.cfg     # Standard verification (5 validators)
│   ├── Boundary.cfg   # Boundary testing
│   ├── EdgeCase.cfg   # Edge case scenarios
│   └── Partition.cfg  # Network partition tests
├── proofs/            # TLAPS proofs
│   ├── Safety.tla     # Safety properties
│   ├── Liveness.tla   # Liveness properties
│   └── Resilience.tla # Fault tolerance
├── scripts/           # Automation scripts
│   ├── setup.sh       # Environment setup
│   ├── run_all.sh     # Master verification script
│   ├── check_model.sh # Model checking
│   ├── verify_proofs.sh # Proof verification
│   ├── parallel_check.sh # Parallel execution
│   ├── syntax_check.sh # Syntax validation
│   └── clean.sh       # Cleanup utility
├── docs/              # Documentation
│   ├── UserGuide.md
│   ├── DevelopmentGuide.md
│   └── VerificationGuide.md
└── results/           # Verification results
    ├── model/         # Model checking results
    └── proofs/        # Proof verification results
```

## Development Workflow

### 1. Setup Development Environment

```bash
# Clone repository
git clone <repository-url>
cd alpenglow

# Install dependencies
./scripts/setup.sh

# Verify installation
./scripts/syntax_check.sh
```

### 2. Development Cycle

1. **Make Changes**: Edit specifications, proofs, or configurations
2. **Syntax Check**: Validate TLA+ syntax
3. **Local Test**: Run small configuration
4. **Full Test**: Run comprehensive verification
5. **Document**: Update documentation
6. **Commit**: Push changes with descriptive message

```bash
# Edit files
vim specs/Alpenglow.tla

# Check syntax
./scripts/syntax_check.sh

# Quick test
./scripts/check_model.sh Small

# Full verification
./scripts/run_all.sh full

# Commit changes
git add .
git commit -m "feat: Add Byzantine fault detection to Votor"
git push
```

### 3. Branch Strategy

- `main`: Stable, verified code
- `develop`: Integration branch
- `feature/*`: New features
- `fix/*`: Bug fixes
- `experiment/*`: Experimental changes

## Writing Specifications

### TLA+ Best Practices

#### 1. Module Structure

```tla
---- MODULE ModuleName ----
EXTENDS Naturals, Sequences, FiniteSets
CONSTANTS /* parameters */
VARIABLES /* state variables */

\* Type definitions
TypeInvariant == ...

\* Initial state
Init == ...

\* State transitions
Next == ...

\* Specification
Spec == Init /\ [][Next]_vars

\* Properties
Safety == ...
Liveness == ...
====
```

#### 2. Naming Conventions

- **Modules**: PascalCase (e.g., `Alpenglow`, `Votor`)
- **Constants**: UPPER_CASE or PascalCase (e.g., `MAX_VALIDATORS`, `Validators`)
- **Variables**: camelCase (e.g., `currentSlot`, `votorView`)
- **Operators**: PascalCase for definitions, camelCase for actions
- **Predicates**: Descriptive names (e.g., `IsValidBlock`, `CanVote`)

#### 3. Documentation

```tla
\* ============================================================================
\* Module: ComponentName
\* Purpose: Brief description of component's role
\* Author: Your Name
\* Date: YYYY-MM-DD
\* ============================================================================

\* ----------------------------------------------------------------------------
\* SECTION: Type Definitions
\* ----------------------------------------------------------------------------

\* @type: Block
\* @desc: Represents a proposed block in the chain
\* @fields: slot - Natural number representing time slot
\*          parent - Hash of parent block
\*          data - Abstract block data
Block == [
    slot: Nat,
    parent: Hash,
    data: Data
]
```

#### 4. State Space Management

```tla
\* Use state constraints to limit exploration
StateConstraint ==
    /\ currentSlot <= 10  \* Limit time progression
    /\ \A v \in Validators: votorView[v] <= 5  \* Limit view changes
    /\ Cardinality(networkMessages) <= 50  \* Limit message buffer
```

## Adding Model Configurations

### Creating a New Configuration

1. **Copy Template**:
```bash
cp models/Small.cfg models/NewConfig.cfg
```

2. **Edit Configuration**:
```cfg
SPECIFICATION Spec
CONSTANTS
    Validators = {v1, v2, v3, v4}
    InitialStake = [v1 |-> 100, v2 |-> 100, v3 |-> 100, v4 |-> 100]
    Leader = v1
    K = 8
    N = 20
    GST = 10
    Delta = 1
    TimeoutDelta = 2

INVARIANTS
    TypeInvariant
    SafetyInvariant

PROPERTIES
    Progress
    Eventually

CONSTRAINT StateConstraint

INIT Init
NEXT Next
```

3. **Add to Scripts**:
Update `scripts/check_model.sh` and `scripts/run_all.sh` to include new configuration.

### Configuration Guidelines

- **Small**: 3-4 validators, minimal parameters for quick testing
- **Medium**: 5-7 validators, realistic parameters
- **Large**: 10+ validators, stress testing
- **Boundary**: Edge values (K=1, minimal timeouts)
- **EdgeCase**: Specific scenarios (all offline, Byzantine majority)

## Writing Proofs

### TLAPS Proof Structure

#### 1. Theorem Template

```tla
THEOREM SafetyTheorem ==
    ASSUME
        /\ TypeInvariant
        /\ Init
    PROVE
        []Safety
PROOF
    <1>1. Init => Safety
        BY InitImpliesSafety
    <1>2. Safety /\ Next => Safety'
        BY SafetyInductive
    <1>3. QED
        BY <1>1, <1>2, PTL
```

#### 2. Proof Levels

```tla
<1>  \* Top-level steps
<2>  \* Sub-steps
<3>  \* Sub-sub-steps
```

#### 3. Proof Tactics

- `BY`: Simple proof by existing facts
- `OBVIOUS`: Trivial proof
- `OMITTED`: Placeholder for future proof
- `USE`: Introduce assumptions
- `HIDE`: Hide definitions for solver

### Common Proof Patterns

#### Invariant Proof
```tla
LEMMA InvariantInductive ==
    TypeInvariant /\ Invariant /\ Next => Invariant'
PROOF
    <1> SUFFICES ASSUME TypeInvariant, Invariant, Next
                 PROVE Invariant'
        OBVIOUS
    <1> USE TypeInvariant, Invariant
    <1>1. CASE Action1
        BY <1>1 DEF Action1, Invariant
    <1>2. CASE Action2
        BY <1>2 DEF Action2, Invariant
    <1> QED
        BY <1>1, <1>2 DEF Next
```

## Testing Guidelines

### Unit Testing Specifications

Create small test specifications:

```tla
---- MODULE TestVotor ----
EXTENDS Votor

\* Test specific scenario
TestScenario ==
    /\ Validators = {v1, v2}
    /\ currentSlot = 0
    /\ votorView = [v1 |-> 0, v2 |-> 0]

TestProperty ==
    TestScenario => <>SomeProperty
====
```

### Integration Testing

Use configuration files for integration tests:

```cfg
\* TestIntegration.cfg
SPECIFICATION TestSpec
CONSTANTS
    \* Test-specific constants
INIT TestInit
NEXT TestNext
```

### Performance Testing

```bash
# Measure state space size
time ./scripts/check_model.sh Medium 2>&1 | grep "states generated"

# Profile memory usage
/usr/bin/time -v ./scripts/check_model.sh Large

# Parallel performance
time ./scripts/parallel_check.sh --configs Small,Medium,Large
```

## Code Style

### TLA+ Style Guide

1. **Indentation**: 4 spaces
2. **Line Length**: Max 80 characters
3. **Comments**: Use `\*` for single line, `(* *)` for multi-line
4. **Alignment**: Align similar expressions

```tla
\* Good alignment
ValidatorSet == {v1, v2, v3}
StakeMap     == [v1 |-> 100, v2 |-> 150, v3 |-> 200]
VotingPower  == [v1 |-> 25,  v2 |-> 30,  v3 |-> 45]
```

### Shell Script Style

1. **Shebang**: `#!/bin/bash`
2. **Error Handling**: `set -e` at minimum
3. **Variables**: `UPPER_CASE` for constants, `lower_case` for locals
4. **Functions**: `snake_case`
5. **Colors**: Use provided color codes

```bash
#!/bin/bash
set -e

# Constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Functions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}
```

## Contributing

### Submission Process

1. **Fork Repository**
2. **Create Feature Branch**
   ```bash
   git checkout -b feature/your-feature
   ```

3. **Make Changes**
   - Write code
   - Add tests
   - Update documentation

4. **Run Verification**
   ```bash
   ./scripts/run_all.sh full
   ```

5. **Commit with Conventional Commits**
   ```bash
   git commit -m "feat: Add new voting mechanism"
   ```

   Types:
   - `feat`: New feature
   - `fix`: Bug fix
   - `docs`: Documentation
   - `style`: Formatting
   - `refactor`: Code restructuring
   - `test`: Adding tests
   - `chore`: Maintenance

6. **Push and Create PR**
   ```bash
   git push origin feature/your-feature
   ```

### Pull Request Guidelines

#### PR Title
`type(scope): Brief description`

#### PR Description
```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Documentation update
- [ ] Performance improvement

## Testing
- [ ] Syntax check passes
- [ ] Small configuration passes
- [ ] Medium configuration passes
- [ ] Proofs verify (if applicable)

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] Tests added/updated
```

### Review Process

1. **Automated Checks**: CI/CD runs verification
2. **Code Review**: At least one maintainer review
3. **Testing**: Reviewer runs verification locally
4. **Merge**: Squash and merge to maintain clean history

## Debug Tips

### TLC Debugging

```bash
# Enable debug output
TLC_DEBUG=1 ./scripts/check_model.sh Small

# Generate state graph
java -cp ~/tla-tools/tla2tools.jar tlc2.TLC \
    -dump dot state.dot \
    specs/Alpenglow.tla

# Analyze specific trace
java -cp ~/tla-tools/tla2tools.jar tlc2.TLC \
    -simulate num=100 \
    specs/Alpenglow.tla
```

### TLAPS Debugging

```bash
# Interactive proof mode
./scripts/verify_proofs.sh debug Safety.tla

# Check specific obligation
tlapm --cleanfp --noproving Safety.tla

# Generate proof graph
tlapm --graph Safety.tla | dot -Tpng -o proof.png
```

### Performance Analysis

```bash
# Profile TLC execution
java -cp ~/tla-tools/tla2tools.jar \
    -XX:+PrintGCDetails \
    -Xloggc:gc.log \
    tlc2.TLC specs/Alpenglow.tla

# Analyze state space
./scripts/check_model.sh Medium -coverage 1

# Memory usage
jstat -gcutil <pid> 1000
```

## Resources

- [TLA+ Documentation](https://lamport.azurewebsites.net/tla/tla.html)
- [TLA+ Examples](https://github.com/tlaplus/Examples)
- [TLAPS Manual](https://tla.msr-inria.inria.fr/tlaps/content/Documentation/Manual.html)
- [Learn TLA+](https://learntla.com)
- [TLA+ Community](https://groups.google.com/g/tlaplus)
