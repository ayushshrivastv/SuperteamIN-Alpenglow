# Foundation Layer Specifications

This directory contains the foundational TLA+ modules for Alpenglow consensus protocol.

## Modules

- **Types.tla** - Core type definitions and validator sets
- **Utils.tla** - Mathematical utilities and helper functions  
- **Crypto.tla** - Cryptographic abstractions (BLS signatures, VRF)

## Verification Commands

```bash
# Types.tla Module Verification
cd specs/foundation/
java -jar $TLAPLUS_HOME/tla2tools.jar -workers 8 ../Types.tla
tlapm -I ../lib ../Types.tla

# Cryptographic Abstraction Validation
java -jar $TLAPLUS_HOME/tla2tools.jar -workers 8 -config ../models/Crypto.cfg ../Crypto.tla
tlapm -I ../crypto-assumptions/ ../Crypto.tla
```

## Expected Results
- Types.tla: 23 proof obligations verified successfully
- Crypto.tla: All cryptographic security assumptions proven sound
