# Solana Alpenglow Consensus
**Increased Bandwidth, Reduced Latency**

**Authors:** Quentin Kniep, Jakub Sliwinski, Roger Wattenhofer
**Organization:** Anza
**Version:** White Paper v1.1, July 22, 2025

---

## Abstract

In this paper we describe and analyze **Alpenglow**, a consensus protocol tailored for a global high-performance proof-of-stake blockchain.

- The voting component **Votor** finalizes blocks in a single round of voting if 80% of the stake is participating, and in two rounds if only 60% of the stake is responsive.
- These voting modes are performed concurrently, so finalization takes `min(δ80%, 2δ60%)` time after block distribution.
- The fast block distribution component **Rotor** is based on erasure coding. Rotor uses node bandwidth proportional to stake, alleviating the leader bottleneck.
- Alpenglow has a **20+20 resilience**: it tolerates an adversary with 20% stake, plus up to 20% additional stake offline under stronger assumptions.

---

## 1 Introduction

> “I think there is a world market for maybe five computers.” – attributed to Thomas J. Watson (IBM president).

If we adjust the quote slightly:
> “I think there is a market for maybe five world computers.”

A **world computer** is like a shared distributed computer:
- Takes **transactions** (commands) as input.
- Changes its **internal state** accordingly.
- Distributed across many processors worldwide.

Advantages:
- Fault tolerance (can survive crashes).
- No central authority can corrupt it.
- Must withstand adversaries controlling some nodes.
- This is the essence of a **blockchain**.

**Alpenglow protocol:**
- Based on **Rotor**, an optimized variant of Solana’s **Turbine** protocol.
- Uses **erasure-coded information dispersal** to achieve asymptotically optimal throughput.
- Core consensus logic **Votor** inherits simplicity from **Simplex protocols** and adapts to proof-of-stake.
- Finality achieved:
  - **Single round** (80% stake).
  - **Backup two-round** (60% stake).

---

### 1.1 Alpenglow Overview

- Runs on **n nodes**, known and fixed during an epoch.
- **Proof-of-stake**:
  - Each node has a known stake.
  - Rewards and bandwidth responsibilities scale with stake.
- **Time partitioned into slots**:
  - Each slot has a **leader** (determined by a VRF).
  - Leaders collect transactions, create blocks (sliced & shredded for distribution).
- **Rotor** disseminates data fairly across stake-weighted relays.
- **Blokstor** stores block data.
- Nodes **vote** (via Votor) to finalize or skip blocks.
- **Repair** protocol allows nodes to fetch missing data.

**Correctness Proof Outline:**
1. Safety → protocol avoids fatal mistakes.
2. Liveness → protocol makes progress under synchrony.
3. Extra crash-tolerance considered.

**Further Sections:**
- Rotor relay sampling (3.1).
- Transaction execution (3.2).
- Failure handling (3.3–3.4).
- Parameters & simulation results (3.5–3.7).

---

### 1.2 Fault Tolerance

- Traditional consensus: tolerate **< 33% Byzantine stake** (3f + 1).
- In large-scale PoS blockchains, 33% Byzantine stake is unrealistic (too costly).
- Most failures = crashes, misconfigurations, or network outages.

**Alpenglow assumptions:**
- **Assumption 1 (fault tolerance):** Byzantine < 20%, correct > 80%.
- **Assumption 2 (extra crash tolerance):** Byzantine < 20%, + up to 20% crashed, remaining > 60% correct.

---

### 1.3 Performance Metrics

- **Finalization time:**
  - `min(δ80%, 2δ60%)`
- **Throughput:**
  - Uses total bandwidth optimally.
- **Simplicity:**
  - Easier correctness reasoning, upgrades, and optimization.

---

### 1.4 Related Work

- **Leader bottleneck protocols**: PBFT, Tendermint, HotStuff.
- **DAG protocols**: high throughput but higher latency.
- **Erasure coding**: pioneered by Solana, used in Alpenglow.
- **One-round consensus protocols**: fast, but practical trade-offs exist.
- **Concurrent protocols**: Banyan, Kudzu (academic sibling to Alpenglow).
- **Follow-up protocols**: Hydrangea (extends resilience model).

---

### 1.5 Model and Preliminaries

- **Epochs**: participant sets fixed for duration.
- **Nodes**: validators with stake, keys, IPs.
- **Messages**: small (<1,500 bytes), authenticated (UDP/QUIC).
- **Stake**: proportional to bandwidth and rewards.
- **Slots**: mapped to leaders (by VRF).
- **Timeouts**: based on global ∆ (max network delay).
- **Adversary**: <20% Byzantine stake, +20% crash.
- **Correctness properties:**
  - Safety → all correct nodes agree on blocks.
  - Liveness → blocks finalized under synchrony.

---

### 1.6 Cryptographic Techniques

- **Hash functions** (SHA256).
- **Digital & aggregate signatures** (e.g., BLS).
- **Erasure codes** (Reed-Solomon).
- **Merkle trees** for data integrity proofs.

---

# 2 The Alpenglow Protocol

The Alpenglow protocol is composed of several components working together:

- **Rotor** → block dissemination (erasure coding).
- **Blokstor** → storage of block data.
- **Pool** → collects votes & certificates.
- **Votor** → voting & finalization logic.
- **Repair** → fetching missing slices/blocks.

---

## 2.1 Shred, Slice, Block

**Hierarchy:**
- **Shred** → smallest unit (fits in UDP datagram).
- **Slice** → group of shreds (decodable if ≥ γ are available).
- **Block** → sequence of slices for a slot.

**Definitions:**

- **Shred (s, t, i, zt, rt, (di, πi), σt):**
  - `s`: slot number
  - `t`: slice index
  - `i`: shred index
  - `zt`: flag (0/1 for last slice)
  - `rt`: Merkle root of slice
  - `(di, πi)`: data & Merkle path
  - `σt`: leader’s signature

- **Slice (s, t, zt, rt, Mt, σt):**
  - Decodable from any γ shreds.
  - `zt = 1` for last slice.

- **Block b:**
  - Sequence of slices `{slice1, …, slicek}`.
  - Block hash = Merkle root of slice roots.
  - Contains parent’s slot/hash info.

---

## 2.2 Rotor (Block Dissemination)

Goals:
- Low latency.
- Bandwidth use proportional to stake.
- Streaming (leader sends slices as they are ready).

**Process:**
1. Leader encodes each slice into Γ shreds using Reed-Solomon.
2. Builds Merkle tree over shreds, signs root.
3. Sends each shred to a **relay node**.
4. Relays forward shred to all others (prioritizing the next leader).

**Resilience:**
- Works if leader is correct & ≥ γ relays are correct.
- Over-provisioning factor `κ = Γ/γ > 5/3` ensures high probability of success.

**Latency:**
- Best case: δ (single network delay).
- Worst case: 2δ.

**Bandwidth Optimality:**
- Each node’s forwarding load is proportional to its stake.
- Achieves asymptotically optimal use of total bandwidth (minus erasure code overhead).

---

## 2.3 Blokstor (Block Storage)

- Stores the **first complete block** received for each slot.
- Verifies shred validity before storing.
- Emits event:
  - `Block(slot(b), hash(b), hash(parent(b)))`.
- Can fetch blocks via **Repair** if needed.
- On finalization: keeps only the finalized block for a slot.

---

## 2.4 Votes and Certificates

**Vote Types:**
- `NotarVote(slot, hash(b))` → vote to notarize block.
- `NotarFallbackVote(slot, hash(b))` → backup notarization.
- `SkipVote(s)` → vote to skip slot.
- `SkipFallbackVote(s)` → backup skip.
- `FinalVote(s)` → finalize.

**Certificate Types:**
- **Fast-Finalization Certificate:** ≥ 80% notar votes.
- **Notarization Certificate:** ≥ 60% notar votes.
- **Skip Certificate:** ≥ 60% skip votes.
- **Finalization Certificate:** ≥ 60% final votes.

---

## 2.5 Pool (Vote Storage)

- Each node maintains a **Pool** of votes & certificates.
- Stores:
  - First notar/skip vote per slot per node.
  - Up to 3 notar-fallback votes.
  - First skip-fallback vote.
  - First finalization vote.

**Certificates:**
- Constructed once enough votes are collected.
- Broadcast to all nodes.
- Stored in Pool.

**Finalization Rules:**
- Block is finalized if:
  - **Fast-finalized:** fast-finalization certificate observed.
  - **Slow-finalized:** finalization certificate observed.
- All ancestors of finalized block also finalized.

---

## 2.6 Votor (Voting Algorithm)

Purpose:
- Ensures blocks are notarized or skipped.
- Provides **one-round (80%)** or **two-round (60%)** finality.

**Process Overview:**
1. Leader proposes block.
2. Nodes receive block via Rotor.
3. Nodes vote:
   - **NotarVote** if block valid & timely.
   - **SkipVote** if block late/untrustworthy.
4. Certificates are formed and broadcast.
5. If conditions met, block is **finalized**.

**Timeouts:**
- Nodes start timers upon `ParentReady` event.
- Parameters:
  - `∆block`: block production time.
  - `∆timeout`: network + slice dissemination buffer.

**States per slot:**
- `ParentReady`
- `Voted`, `VotedNotar`
- `BlockNotarized`
- `ItsOver` (final vote cast)
- `BadWindow` (skip/fallback cast)

**Finalization:**
- Fast path → notarization + finalization votes = finalized.
- Slow path → notarization fallback + skip fallback handled.

---

## 2.7 Block Creation (Leader Role)

- Leader builds blocks for its **leader window**.
- On receiving `ParentReady(s, hash(bp))`:
  - Safe to create block with parent `bp`.
- Optimization:
  - Leader may start building “optimistically” before parent certificate fully observed.
  - If wrong parent chosen, can switch once.

---

## 2.8 Repair (Fetching Missing Data)

Purpose: Recover missing slices/blocks.

**Functions:**
- `sampleNode()`: pick node by stake.
- `getSliceCount(hash(b), v)`: get number of slices.
- `getSliceHash(t, hash(b), v)`: get slice root.
- `getShred(s, t, i, rt, v)`: fetch missing shred.

**Process:**
- Query multiple nodes until enough valid data is reconstructed.
- Validate with Merkle proofs.

---

# 2.9 Safety

When we say a certificate *exists*, it means some correct node observed it.
When we say an ancestor block *exists*, it means following parent links leads to that block.

### Lemma 20 (Notarization or Skip)
- Each correct node casts exactly **one** notarization vote or skip vote per slot.

### Lemma 21 (Fast-Finalization Property)
If block **b** is fast-finalized:
1. No other block in same slot can be notarized.
2. No other block in same slot can be notarized-fallback.
3. No skip certificate can exist for that slot.

### Lemma 22
If a correct node casts a **FinalizationVote**, it never casts a notar-fallback or skip-fallback vote in that slot.

---

# 2.10 Liveness

Goal: ensure blocks continue to finalize when the network is synchronous.

- **ParentReady** ensures leader has a valid parent chain.
- Timeout mechanism ensures protocol does not stall.
- With >60% correct stake, progress is guaranteed.

### Theorem 1 (Safety)
If one correct node finalizes block **b** at slot **s**, then any block finalized later must be a descendant of **b**.

### Theorem 2 (Liveness)
During long enough synchronous periods, correct nodes finalize new blocks.

---

# 2.11 Crash Faults

Alpenglow tolerates **extra crash failures**:
- Byzantine < 20% stake.
- +20% stake may crash.
- Remaining 60% correct stake ensures safety and liveness.

Difference from Assumption 1:
- Assumption 1 → only Byzantine faults (<20%).
- Assumption 2 → adds crash tolerance (up to 40% faulty total).

---

# 3 Additional Concepts

These sections provide enhancements, optimizations, and advanced failure handling.

---

## 3.1 Rotor Relay Sampling

- Relays are chosen randomly, proportional to stake.
- Novel sampling method improves resilience and balances network load.
- Ensures with high probability enough correct relays are selected.

---

## 3.2 Transaction Execution

- Transactions executed once blocks finalized.
- Blocks delivered in chain order.
- Ensures deterministic state transitions across all nodes.

---

## 3.3 Node Reconnection & Resync

- If a node loses contact:
  - Can reconnect and **repair** missing blocks.
  - Uses certificates to verify latest finalized state.
- During network partitions/outages:
  - Protocol may pause.
  - Resumes safely once network stabilizes.

---

## 3.4 Dynamic Timeouts

- Timeout values can adjust dynamically to changing network conditions.
- Helps resolve crises caused by:
  - Network congestion.
  - Long message delays.
- Ensures protocol correctness without assuming a fixed ∆.

---

## 3.5 Protocol Parameters

Examples:
- Epoch length (e.g., L = 18,000 slots).
- Erasure code expansion factor κ (suggested κ = 2).
- Timeout bounds.
- Slot time.

---

## 3.6 Bandwidth Simulation

- Simulation with Solana’s current (epoch 780) node & stake distribution.
- Results show:
  - Bandwidth utilization asymptotically optimal.
  - Each node’s bandwidth load proportional to its stake.

---

## 3.7 Latency Simulation

- Simulation of Rotor latency with varying shred counts (Γ) and γ = 32.
- Results:
  - With high data expansion (κ = 10, Γ = 320), latency ≈ δ.
  - Matches theoretical analysis: `min(δ80%, 2δ60%)`.

---

# 4 Conclusion

Alpenglow introduces a **high-performance proof-of-stake consensus protocol** that:

- Achieves **fast finalization** in `min(δ80%, 2δ60%)` time.
- Uses **Rotor** (erasure-coded dissemination) to eliminate leader bandwidth bottlenecks.
- Provides **“20+20” resilience**: tolerates up to 20% Byzantine stake and an additional 20% crash faults under stronger assumptions.
- Keeps the protocol **simple and upgrade-friendly**, making reasoning about correctness and implementation easier.

**Key Contributions:**
1. **Concurrent voting modes** (80% fast path + 60% two-round fallback).
2. **Stake-proportional bandwidth use** via Rotor.
3. **Strong safety guarantees** under partial synchrony.
4. **Crash tolerance** beyond traditional 3f+1 bounds.

---

# References

- [PSL80] Pease, Shostak, Lamport. *Reaching Agreement in the Presence of Faults*. JACM, 1980.
- [CT05] Cachin, Tessaro. *Optimal Resilient Broadcast*. 2005.
- [Fou19] Solana Foundation. *Turbine: Data Propagation in Solana*. 2019.
- [DGV04] Dwork, Lynch, Vaandrager. *Consensus in the Presence of Partial Synchrony*. 2004.
- [MA06] Martin, Alvisi. *FaB Paxos: Fast Byzantine Agreement*. 2006.
- [Sho24] Shorter. *DispersedSimplex: Erasure Coding in Consensus*. 2024.
- [Von+24] Von et al. *Banyan Protocol*. 2024.
- [SSV25] S., S., V. *Kudzu Protocol*. 2025.
- [SKN25] S., K., N. *Hydrangea: Parametrized Resilience in Consensus*. 2025.
- [LNS25] L., N., S. *Comparing Throughput and Latency in Consensus Protocols*. 2025.

(*Note: references shortened for clarity — original paper includes full citations.*)

---

# Appendix (Model Recap)

**System Model:**
- Nodes = validators with known stake.
- Communication = authenticated UDP/QUIC messages (<1500 bytes).
- Time = partitioned into slots, grouped into epochs.
- Leaders = assigned deterministically via VRF.

**Adversary Model:**
- Byzantine < 20% stake.
- Crash faults up to additional 20%.
- Static adversary per epoch.

**Correctness Guarantees:**
- **Safety:** Never finalizes conflicting blocks.
- **Liveness:** Progress ensured under synchrony.

**Cryptographic Tools:**
- Collision-resistant hash (SHA256).
- Digital + aggregate signatures (BLS).
- Erasure codes (Reed-Solomon).
- Merkle trees for proofs of inclusion.

# In JSON

{
  "title": "Solana Alpenglow Consensus",
  "subtitle": "Increased Bandwidth, Reduced Latency",
  "authors": ["Quentin Kniep", "Jakub Sliwinski", "Roger Wattenhofer"],
  "organization": "Anza",
  "version": "White Paper v1.1",
  "date": "July 22, 2025",
  "abstract": {
    "description": "Alpenglow is a consensus protocol tailored for a global high-performance proof-of-stake blockchain.",
    "key_points": [
      "Votor finalizes blocks in one round if 80% stake participates, two rounds if 60% stake responds.",
      "Finalization time: min(δ80%, 2δ60%).",
      "Rotor uses erasure coding and stake-proportional bandwidth to alleviate leader bottleneck.",
      "20+20 resilience: tolerates 20% adversary stake plus up to 20% additional offline stake under stronger assumptions."
    ]
  },
  "sections": {
    "1 Introduction": {
      "quote": [
        "I think there is a world market for maybe five computers.",
        "I think there is a market for maybe five world computers."
      ],
      "world_computer": {
        "description": "A shared distributed computer",
        "properties": [
          "Takes transactions as input",
          "Changes internal state",
          "Distributed across many processors worldwide"
        ],
        "advantages": [
          "Fault tolerance",
          "No central authority can corrupt it",
          "Resists adversarial nodes"
        ]
      },
      "alpenglow_protocol": {
        "based_on": "Rotor (optimized variant of Solana’s Turbine)",
        "features": [
          "Erasure-coded information dispersal for optimal throughput",
          "Votor consensus logic inherits Simplex simplicity adapted to PoS",
          "Finality: single round (80%) or backup two-round (60%)"
        ]
      },
      "1.1 Alpenglow Overview": {
        "nodes": "n nodes, fixed per epoch",
        "proof_of_stake": "Stake determines rewards and bandwidth responsibilities",
        "time_slots": {
          "leaders": "Determined by VRF",
          "block_creation": "Leaders collect transactions, create blocks sliced & shredded",
          "rotor": "Disseminates data across stake-weighted relays",
          "blokstor": "Stores block data",
          "voting": "Nodes vote via Votor",
          "repair": "Fetch missing data"
        },
        "correctness_proof": ["Safety", "Liveness", "Extra crash tolerance"]
      },
      "1.2 Fault Tolerance": {
        "traditional_consensus": "<33% Byzantine stake",
        "alpenglow_assumptions": [
          "Assumption 1: Byzantine <20%, correct >80%",
          "Assumption 2: Byzantine <20%, + up to 20% crashed, remaining >60% correct"
        ]
      },
      "1.3 Performance Metrics": {
        "finalization_time": "min(δ80%, 2δ60%)",
        "throughput": "Uses total bandwidth optimally",
        "simplicity": "Easier reasoning and upgrades"
      },
      "1.4 Related Work": [
        "Leader bottleneck protocols: PBFT, Tendermint, HotStuff",
        "DAG protocols: high throughput but higher latency",
        "Erasure coding: pioneered by Solana",
        "One-round consensus protocols",
        "Concurrent protocols: Banyan, Kudzu",
        "Follow-up protocols: Hydrangea"
      ],
      "1.5 Model and Preliminaries": {
        "epochs": "Participant sets fixed",
        "nodes": "Validators with stake, keys, IPs",
        "messages": "Authenticated UDP/QUIC <1500 bytes",
        "stake": "Proportional to bandwidth and rewards",
        "slots": "Mapped to leaders (VRF)",
        "timeouts": "Based on global ∆",
        "adversary": "<20% Byzantine, +20% crash",
        "correctness": ["Safety", "Liveness"]
      },
      "1.6 Cryptographic Techniques": [
        "SHA256 hash functions",
        "Digital & aggregate signatures (BLS)",
        "Reed-Solomon erasure codes",
        "Merkle trees for data integrity"
      ]
    },
    "2 The Alpenglow Protocol": {
      "components": ["Rotor", "Blokstor", "Pool", "Votor", "Repair"],
      "2.1 ShredSliceBlock": {
        "shred": ["s", "t", "i", "zt", "rt", "(di, πi)", "σt"],
        "slice": ["s", "t", "zt", "rt", "Mt", "σt"],
        "block": "Sequence of slices, block hash = Merkle root of slice roots"
      },
      "2.2 Rotor": {
        "goals": ["Low latency", "Stake-proportional bandwidth", "Streaming"],
        "process": [
          "Leader encodes slice into Γ shreds",
          "Builds Merkle tree and signs root",
          "Sends shreds to relay nodes",
          "Relays forward to others"
        ],
        "resilience": "Works if leader correct & ≥γ relays correct",
        "latency": ["Best: δ", "Worst: 2δ"],
        "bandwidth_optimality": "Each node’s forwarding proportional to stake"
      },
      "2.3 Blokstor": {
        "storage": "First complete block per slot",
        "verification": "Shred validity",
        "events": ["Block(slot, hash(b), hash(parent(b))"],
        "repair": "Fetch blocks if needed",
        "finalization": "Keeps only finalized block"
      },
      "2.4 VotesCertificates": {
        "vote_types": ["NotarVote", "NotarFallbackVote", "SkipVote", "SkipFallbackVote", "FinalVote"],
        "certificate_types": ["Fast-Finalization", "Notarization", "Skip", "Finalization"]
      },
      "2.5 Pool": {
        "stores": ["First notar/skip vote per slot per node", "Up to 3 notar-fallback votes", "First skip-fallback vote", "First finalization vote"],
        "certificates": "Constructed once enough votes collected, broadcast to nodes",
        "finalization_rules": ["Fast-finalized: fast-finalization certificate observed", "Slow-finalized: finalization certificate observed"]
      },
      "2.6 Votor": {
        "purpose": "Ensure blocks notarized/skipped, supports one-round (80%) or two-round (60%) finality",
        "process": [
          "Leader proposes block",
          "Nodes receive block via Rotor",
          "Vote: NotarVote or SkipVote",
          "Certificates formed & broadcast",
          "Finalize block if conditions met"
        ],
        "timeouts": ["∆block", "∆timeout"],
        "states_per_slot": ["ParentReady", "Voted", "VotedNotar", "BlockNotarized", "ItsOver", "BadWindow"]
      },
      "2.7 BlockCreation": "Leader builds blocks for leader window, may optimize by optimistic creation",
      "2.8 Repair": {
        "purpose": "Recover missing slices/blocks",
        "functions": ["sampleNode()", "getSliceCount()", "getSliceHash()", "getShred()"],
        "process": "Query multiple nodes, validate with Merkle proofs"
      },
      "2.9 Safety": {
        "definitions": ["Certificate exists = observed by correct node", "Ancestor block exists = parent links lead to block"],
        "lemmas": [
          "Each node casts exactly one notarization/skip vote per slot",
          "Fast-Finalization property: prevents duplicate notar/fallback votes",
          "FinalizationVote never cast with fallback votes"
        ]
      },
      "2.10 Liveness": {
        "goal": "Ensure blocks finalize under synchrony",
        "mechanisms": ["ParentReady ensures valid parent chain", "Timeout ensures protocol progress"],
        "requirements": ">60% correct stake"
      },
      "2.11 CrashFaults": {
        "extra_tolerance": ["Byzantine <20%", "+20% crash stake allowed", "Remaining 60% ensures safety & liveness"]
      }
    },
    "3 Additional Concepts": {
      "3.1 RotorRelaySampling": "Relays chosen randomly proportional to stake",
      "3.2 TransactionExecution": "Executed after finalization, preserves deterministic state",
      "3.3 NodeReconnectionResync": "Repair missing blocks, resume safely after network issues",
      "3.4 DynamicTimeouts": "Adjusts to network conditions",
      "3.5 ProtocolParameters": ["Epoch length L", "Erasure code expansion κ", "Timeout bounds", "Slot time"],
      "3.6 BandwidthSimulation": "Results show optimal bandwidth proportional to stake",
      "3.7 LatencySimulation": "Rotor latency matches theory min(δ80%, 2δ60%)"
    },
    "4 Conclusion": {
      "summary": [
        "Fast finalization: min(δ80%, 2δ60%)",
        "Rotor eliminates leader bottleneck",
        "20+20 resilience: 20% Byzantine + 20% crash",
        "Simple, upgrade-friendly protocol"
      ],
      "key_contributions": [
        "Concurrent voting modes (80% fast + 60% two-round fallback)",
        "Stake-proportional bandwidth use",
        "Strong safety under partial synchrony",
        "Crash tolerance beyond traditional 3f+1"
      ]
    }
  },
  "references": [
    "[PSL80] Pease, Shostak, Lamport. Reaching Agreement in the Presence of Faults. JACM, 1980.",
    "[CT05] Cachin, Tessaro. Optimal Resilient Broadcast. 2005.",
    "[Fou19] Solana Foundation. Turbine: Data Propagation in Solana. 2019.",
    "[DGV04] Dwork, Lynch, Vaandrager. Consensus in the Presence of Partial Synchrony. 2004.",
    "[MA06] Martin, Alvisi. FaB Paxos: Fast Byzantine Agreement. 2006.",
    "[Sho24] Shorter. DispersedSimplex: Erasure Coding in Consensus. 2024.",
    "[Von+24] Von et al. Banyan Protocol. 2024.",
    "[SSV25] S., S., V. Kudzu Protocol. 2025.",
    "[SKN25] S., K., N. Hydrangea: Parametrized Resilience in Consensus. 2025.",
    "[LNS25] L., N., S. Comparing Throughput and Latency in Consensus Protocols. 2025."
  ],
  "appendix": {
    "system_model": {
      "nodes": "Validators with known stake",
      "communication": "Authenticated UDP/QUIC messages <1500 bytes",
      "time": "Partitioned into slots and epochs",
      "leaders": "Assigned via VRF"
    },
    "adversary_model": {
      "byzantine": "<20% stake",
      "crash": "Additional 20% stake",
      "static_per_epoch": true
    },
    "correctness_guarantees": ["Safety: no conflicting blocks", "Liveness: progress under synchrony"],
    "cryptographic_tools": ["SHA256", "BLS signatures", "Reed-Solomon codes", "Merkle trees"]
  }
}

