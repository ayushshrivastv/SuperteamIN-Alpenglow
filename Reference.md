<!-- Author: Ayush Srivastava -->

Explore the codebase and analysis how much we have acheived till now

The Challenge
Transform the mathematical theorems from the Alpenglow whitepaper into proofs using formal methods tools (TLA+ or Stateright). You must create abstract formal models and prove correctness properties in the paper.

Complete Formal Specification

1. Protocol modeling in TLA+ or Stateright covering:

Votor's dual voting paths (fast 80% vs slow 60% finalization)

Rotor's erasure-coded block propagation with stake-weighted relay sampling

Certificate generation, aggregation, and uniqueness properties

Timeout mechanisms and skip certificate logic

Leader rotation and window management

2. Machine-Verified Theorems
Safety Properties:

No two conflicting blocks can be finalized in the same slot

Chain consistency under up to 20% Byzantine stake

Certificate uniqueness and non-equivocation

Liveness Properties:

Progress guarantee under partial synchrony with >60% honest participation

Fast path completion in one round with >80% responsive stake

Bounded finalization time (min(δ₈₀%, 2δ₆₀%) as claimed in paper)

Resilience Properties:

Safety maintained with ≤20% Byzantine stake

Liveness maintained with ≤20% non responsive stake

Network partition recovery guarantees

3. Model Checking & Validation
Exhaustive verification for small configurations (4-10 nodes)

Statistical model checking for realistic network sizes

Resources
Alpenglow Whitepaper : https://drive.google.com/file/d/1Rlr3PdHsBmPahOInP6-Pl0bMzdayltdV/view

Accelerate Alpenglow Presentation Slides: https://disco.ethz.ch/members/wroger/AlpenglowPresentation.pdf

Alpenglow: A New Consensus for Solana : https://www.anza.xyz/blog/alpenglow-a-new-consensus-for-solana

Solana’s Great Consensus Rewrite: https://www.helius.dev/blog/alpenglow

Alpenglow Reference Implementation: https://github.com/qkniep/alpenglow/tree/main

Consensus on Solana: https://www.helius.dev/blog/consensus-on-solana

Scale or Die at Accelerate 2025: Introducing Alpenglow - Solana’s New Consensus: https://www.youtube.com/watch?v=x1sxtm-dvyE

Stateright: https://www.stateright.rs/title-page.html

TLA+: https://learntla.com/core/index.html
