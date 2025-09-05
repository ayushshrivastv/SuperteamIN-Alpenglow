## Project Overview

This project provides comprehensive formal verification of the Alpenglow consensus protocol, a next-generation blockchain consensus mechanism designed to achieve 100-150ms finalization times. We employ multiple verification approaches including TLA+ specifications, machine-checked proofs, Stateright cross-validation, and implementation validation tools to ensure the highest level of correctness guarantees.

The verification effort focuses on proving three critical properties:
- **Safety**: No two conflicting blocks can be finalized in the same slot
- **Liveness**: The protocol makes progress with >60% honest stake participation
- **Resilience**: Tolerates up to 20% Byzantine stake + 20% offline validators
