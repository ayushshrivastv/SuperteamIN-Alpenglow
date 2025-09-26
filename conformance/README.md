<!-- Author: Ayush Srivastava -->

# Implementation Conformance Testing

This directory contains scripts and tools for verifying that real Alpenglow protocol implementations conform to the formal TLA+ specification.

## Components

- **scripts/** - Conformance testing automation
- **traces/** - Real implementation execution traces
- **tla-traces/** - Translated traces for TLA+ verification

## Verification Process

1. **Trace Collection** - Collect execution traces from real Alpenglow implementations
2. **Trace Translation** - Convert implementation traces to TLA+ format
3. **Conformance Verification** - Verify traces conform to formal specification

## Commands

```bash
cd conformance/
# Collect implementation traces
./scripts/collect-implementation-traces.sh

# Translate traces to TLA+ format
python3 trace-translator.py --input traces/ --output tla-traces/

# Verify conformance
java -jar $TLAPLUS_HOME/tla2tools.jar TraceConformance.tla
```

## Expected Results
- Implementation traces collected successfully
- 100% trace conformance to formal specification
- No specification violations detected
