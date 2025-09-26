# Properties Layer Specifications

This directory contains the safety and liveness property specifications for Alpenglow.

## Modules

- **Safety.tla** - Safety properties and consensus safety verification
- **Liveness.tla** - Liveness properties and progress guarantees
- **Resilience.tla** - Byzantine fault tolerance properties

## Verification Commands

```bash
cd specs/properties/
# Consensus Safety Verification
java -jar $TLAPLUS_HOME/tla2tools.jar -workers 16 -config ../../models/Safety.cfg ../../proofs/Safety.tla

# Certificate uniqueness with SMT solver
tlapm ../../proofs/Safety.tla -I ../crypto/ --solver smt

# Byzantine resilience (20+20 model)
java -jar $TLAPLUS_HOME/tla2tools.jar -workers 16 -config ../../models/SafetyByzantine.cfg ../../proofs/Safety.tla

# Progress guarantee verification
java -jar $TLAPLUS_HOME/tla2tools.jar -workers 16 -config ../../models/Liveness.cfg ../../proofs/Liveness.tla

# Mathematical proof of bounded finalization
tlapm ../../proofs/Liveness.tla --theorem BoundedFinality
```

## Expected Results
- Safety: No conflicting finalization proven across all scenarios
- Liveness: Progress guarantee under partial synchrony with >60% honest participation
- Resilience: Safety maintained with 20% Byzantine + 20% offline validators
