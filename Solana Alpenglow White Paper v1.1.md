> Solana Alpenglow Consensus Increased Bandwidth, Reduced Latency
>
> Quentin Kniep Jakub Sliwinski Roger Wattenhofer
>
> Anza
>
> White Paper v1.1, July 22, 2025
>
> Abstract
>
> In this paper we describe and analyze Alpenglow, a consensus protocol
> tailored for a global high-performance proof-of-stake blockchain.
>
> The voting component Votor finalizes blocks in a single round of
> voting if 80% of the stake is participating, and in two rounds if only
> 60% of the stake is responsive. These voting modes are performed
> concurrently, such that finalization takes min(δ80%,2δ60%) time after
> a block has been distributed.
>
> The fast block distribution component Rotor is based on erasure
> cod-ing. Rotor utilizes the bandwidth of participating nodes
> proportionally to their stake, alleviating the leader bottleneck for
> high throughput. As a result, total available bandwidth is used
> asymptotically optimally.
>
> Alpenglow features a distinctive “20+20” resilience, wherein the
> pro-tocol can tolerate harsh network conditions and an adversary
> controlling 20% of the stake. An additional 20% of the stake can be
> ofline if the network assumptions are stronger.
>
> 1 Introduction
>
> “I think there is a world market for maybe five computers.” – This
> quote is often attributed to Thomas J. Watson, president of IBM. It is
> disputed whether Watson ever said this, but it was certainly in the
> spirit of the time as similar quotes exist, e.g., by Howard H. Aiken.
> The quote was often made fun of in the last decades, but if we move
> one word, we can probably agree: “I think there is a market for maybe
> five world computers.”
>
> So, what is a world computer? In many ways a world computer is like a
> common desktop/laptop computer that takes commands (“transactions”) as
> input and then changes its bookkeeping (“internal state”) accordingly.
> A world computer provides a shared environment for users from all over
> the world. Moreover, a world computer itself is distributed over the
> entire world:
>
> 1
>
> Instead of just having a single processor, we have dozens, hundreds or
> thou-sands of processors, connected through the internet.
>
> Such a world computer has a big advantage over even the most advanced
> traditional computer: The world computer is much more fault tolerant,
> as it can survive a large number of crashes of individual components.
> Beyond that, no authority can corrupt the computer for other users. A
> world computer must survive even if some of its components are
> controlled by an evil botnet. The currently common name for such a
> world computer is blockchain.
>
> In this paper we present Alpenglow, a new blockchain protocol.
> Alpen-glow uses the Rotor protocol, which is an optimized and
> simplified variant of Solana’s data dissemination protocol Turbine
> \[Fou19\]. Turbine brought era-sure coded information dispersal
> \[CT05\] to permissionless blockchains. Rotor uses the total amount of
> available bandwidth provided by the nodes. Because of this, Rotor
> achieves an asymptotically optimal throughput. In contrast, consensus
> protocols that do not address the leader bandwidth bottleneck suf-fer
> from low throughput.
>
> The Votor consensus logic at the core of Alpenglow inherits the
> simplic-ity from the Simplex protocol line of work \[CP23; Sho24\] and
> translates it to a proof-of-stake context, resulting in natural
> support for rotating leaders without complicated view changes. In the
> common case, we achieve finality in a single round of voting, while a
> conservative two-round procedure is run concurrently as backup
> \[SSV25; Von+24\].
>
> 1.1 Alpenglow Overview
>
> First, let us provide a high-level description of Alpenglow. We are
> going to describe all the individual parts in detail in Section 2.
>
> Alpenglow runs on top of n computers, which we call nodes, where n can
> be in the thousands. This set of nodes is known and fixed over a
> period of time called an epoch. Any node can communicate with any
> other node in the set by sending a direct message.
>
> Alpenglow is a proof-of-stake blockchain, where each node has a known
> stake of cryptocurrency. The stake of a node signals how much the node
> contributes to the blockchain. If node v2 has twice the stake of node
> v1, node v2 will also earn twice the fees, and provide twice the
> outgoing network bandwidth.
>
> Time is partitioned into slots. Each time slot has a slot number and a
> designated leader from the set of nodes. Each leader will be in charge
> for a fixed amount of consecutive slots, known as the leader window. A
> threshold verifiable random function determines the leader schedule.
>
> While a node is the leader, it will receive all the new transactions,
> either directly from the users or relayed by other nodes. The leader
> will construct a block with these transactions. A block consists of
> slices for pipelining. The slices themselves consist of shreds for
> fault tolerance and balanced dispersal
>
> 2
>
> (Section 2.1). The leader incorporates the Rotor algorithm (Section
> 2.2), which is based on erasure coding, to disseminate the shreds. In
> essence, we want the nodes to utilize their total outgoing network
> bandwidth in a stake-fair way, and avoid the common pitfall of having
> a leader bottleneck. The leader will continuously send its shreds to
> relay nodes, which will in turn forward the shreds to all other nodes.
>
> As soon as a block is complete, the (next) leader will start building
> and disseminating the next block. Meanwhile, concurrently, every node
> eventually receives that newly constructed block. The shreds and
> slices of the incoming blocks are stored in the Blokstor (Section
> 2.3).
>
> Nodes will then vote on whether they support the block. We introduce
> different types of votes (and certificates of aggregated votes) in
> Section 2.4. These votes and certificates are stored in a local data
> structure called Pool (Section 2.5).
>
> With all the data structures in place, we discuss the voting algorithm
> Votor in Section 2.6: If the block is constructed correctly and
> arrives in time, a node will vote for the block. If a block arrives
> too late, a node will instead vote to skip the block (since either the
> leader cannot be trusted, or the network is unstable). If a
> super-majority of the total stake votes for a block, the block can be
> finalized immediately. However, if something goes wrong, an additional
> round of voting will decide whether or not to skip the block.
>
> In Section 2.7 we discuss the logic of creating blocks as a leader,
> and how to decide on where to append the newly created block.
>
> Finally, in Section 2.8 we discuss Repair – how a node can get missing
> shreds, slices or blocks from other peers. Repair is needed to help
> nodes to retrieve the content of an earlier block that they might have
> missed, which is now an ancestor of a finalized block. This completes
> the main parts of our discussion of the consensus algorithm.
>
> We proceed to prove the correctness of Alpenglow. First, we prove
> safety (we do not make fatal mistakes even if the network is
> unreliable, see Sec-tion 2.9), then liveness (we do make progress if
> the network is reliable, see Section 2.10). Finally, we also consider
> a scenario with a high number of crash failures in Section 2.11.
>
> While not directly essential for Alpenglow’s correctness, Section 3
> exam-ines various concepts that are important for Alpenglow’s
> understanding. First we describe our novel Rotor relay sampling
> algorithm in Section 3.1. Next, we explore how transactions are
> executed in Section 3.2.
>
> Then we move on to advanced failure handling. In Section 3.3 we
> consider how a node re-connects to Alpenglow after it lost contact,
> and how the sys-tem can “re-sync” when experiencing severe network
> outages. Then we add dynamic timeouts to resolve a crisis (Section
> 3.4).
>
> In the last part, we present potential choices for protocol parameters
> (Sec-tion 3.5). Based on these we show some measurement results; to
> better under-stand possible eficiency gains, we simulate Alpenglow
> with Solana’s current
>
> 3
>
> node and stake distribution, both for bandwidth (Section 3.6) and
> latency (Section 3.7).
>
> In the remainder of this section, we present some preliminaries which
> are necessary to understand the paper. We start out with a short
> discussion on security design goals in Section 1.2 and performance
> metrics in Section 1.3. In Section 1.4 we discuss how Alpenglow
> relates to other work on consensus. Finally we present the model
> assumptions (Section 1.5) and the cryptographic tools we use (Section
> 1.6).
>
> 1.2 Fault Tolerance
>
> Safety and security are the most important objectives of any consensus
> protocol. Typically, this involves achieving resilience against
> adversaries that control up to 33% of the stake \[PSL80\]. This 33%
> (also known as “3f + 1”) bound is everywhere in today’s world of
> fault-tolerant distributed systems.
>
> When discovering the fundamental result in 1980, Pease et al.
> considered systems where the number of nodes n was small. However,
> today’s blockchain systems consist of thousands of nodes! While the
> 33% bound of \[PSL80\] also holds for large n, attacking one or two
> nodes is not the same as attacking thousands. In a large scale
> proof-of-stake blockchain system, running a thou-sand malicious
> (“byzantine”) nodes would be a costly endeavor, as it would likely
> require billions of USD as staking capital. Even worse, misbehavior is
> often punishable, hence an attacker would lose all this staked
> capital.
>
> So, in a real large scale distributed blockchain system, we will
> probably see significantly less than 33% byzantines. Instead,
> realistic bad behavior often comes from machine misconfigurations,
> software bugs, and network or power outages. In other words, large
> scale faults are likely accidents rather than coordinated attacks.
>
> This attack model paradigm shift opens an opportunity to reconsider
> the classic 3f +1 bound. Alpenglow is based on the 5f +1 bound that
> has been introduced in \[DGV04\] and \[MA06\]. While being less
> tolerant to orthodox byzantine attacks, the 5f + 1 bound offers other
> advantages. Two rounds of voting are required for finalization if the
> adversary is strong. However, if the adversary possesses less stake,
> or does not misbehave all the time, it is possible for a correct 5f +1
> protocol to finalize a block in just a single round of voting.
>
> In Sections 2.9 and 2.10 we rely on Assumption 1 to show that our
> protocol is correct.
>
> Assumption 1 (fault tolerance). Byzantine nodes control less than 20%
> of the stake. The remaining nodes controlling more than 80% of stake
> are cor-rect.
>
> As we explain later, Alpenglow is partially-synchronous, and
> Assumption 1 is enough to ensure that even an adversary completely
> controlling the network
>
> 4
>
> (inspecting, delaying, and scheduling communication between correct
> nodes at will) cannot violate safety. A network outage or partition
> would simply cause the protocol to pause and continue as soon as
> communication is restored, without any incorrect outcome.
>
> However, if the network is not being attacked, or the adversary does
> not leveragesome networkadvantage,
> Alpenglowcantolerateanevenhighershare of nodes that simply crash. In
> Section 2.11 we intuitively explain the differ-ence between Assumption
> 1 and Assumption 2, and we sketch Alpenglow’s correctness under
> Assumption 2.
>
> Assumption 2 (extra crash tolerance). Byzantine nodes control less
> than 20% of the stake. Other nodes with up to 20% stake might crash.
> The re-maining nodes controlling more than 60% of the stake are
> correct.
>
> 1.3 Performance Metrics
>
> Alpenglow achieves the fastest possible consensus. In particular,
> after a block is distributed, our protocol finalizes the block in
> min(δ80%, 2δ60%) time. We will explain this formula in more detail in
> Section 1.5; in a nutshell, δθ is a network delay between a
> stake-weighted fraction θ of nodes. To achieve this finalization time,
> we run an 80% and a 60% majority consensus mechanism concurrently. A
> low-latency 60% majority cluster is likely to finish faster on the 2δ
> path, whereas more remote nodes may finish faster on the single δ
> path, hence min(δ80%,2δ60%). Having low latency is an important factor
> deciding the blockchain’s usability. Improving latency means
> establishing transaction finality faster, and providing users with
> results with minimal delay.
>
> Another common pain point of a blockchain is the system’s throughput,
> measured in transaction bytes per second or transactions per second.
> In terms of throughput, our protocol is using the total available
> bandwidth asymptot-ically optimally.
>
> After achieving the best possible results across these main
> performance metrics, it is also important to minimize protocol
> overhead, including com-putational requirements and other resource
> demands.
>
> Moreover, in Alpenglow, we strive for simplicity whenever possible.
> While simplicity is dificult to quantify, it remains a highly
> desirable property, be-cause simplicity makes it easier to reason
> about correctness and implemen-tation. A simple protocol can also be
> upgraded and optimized more conve-niently.
>
> 5
>
> 1.4 Related Work
>
> Different consensus protocols contribute different techniques to
> address different performance metrics. Some techniques can be
> translated from one protocol to another without compromise, while
> other techniques cannot. In the following we describe each protocol as
> it was originally published, and not what techniques could
> hypothetically be added to the protocol.
>
> Increase Bandwidth. In classic leader-based consensus protocols such
> as PBFT \[CL99\], Tendermint \[BKM18\] or HotStuff \[Yin+19\], at a
> given time one leader node is responsible for disseminating the
> proposed payload to all replicas. This bandwidth bottleneck can
> constitute a defining limitation on the throughput \[Dan+22; Mil+16;
> SDV19\].
>
> DAG protocols \[Dan+22; Spi+22\] are a prominent line of work focused
> on addressing this concern. In these protocols data dissemination is
> performed by all nodes. Unfortunately, protocols following the DAG
> approach exhibit a latency penalty \[Aru+25\]. Some DAG protocols
> \[Kei+22\] reduce the latency penalty by foregoing “certifying” the
> disseminated data. For example, in Mysticeti \[Bab+25\] the leader
> block can be confirmed in two rounds of voting, i.e., after
> disseminating the block and observing two block layers referencing
> this block (corresponding to 3 network delays, or 3δ). However, most
> of the data (all non-leader blocks) is ordered by the protocol when a
> leader block “certifying” the data is finalized. In other words, most
> of the throughput is confirmed with a latency of 5δ. Some researchers
> raise concerns that this technique impacts the robustness of the
> protocol \[Aru+24\].
>
> Another prominent technique used to alleviate the leader bottleneck
> for highthroughputinvolveserasurecoding\[CT05; Sho24; Yan+22\].
> Solana\[Fou19; Yak18\] pioneered this approach in blockchains. In this
> technique, the leader erasure-codes the payload into smaller
> fragments. The fragments are sent to different nodes, which in turn
> participate in disseminating the fragments, making the bandwidth use
> balanced. Alpenglow follows this line of work.
>
> A recent study \[LNS25\] proposes a framework to compare the impact of
> above-mentioned techniques on throughput and latency in a principled
> way. The study indicates that erasure coding of the payload
> (represented by DispersedSimplex \[Sho24\]) achieves better latency
> than DAG protocols.
>
> Reduce Latency. A long line of work proposes consensus protocols that
> can terminate after one round of voting, typically called fast or
> one-step consensus. This approach has received a lot of attention,
> e.g., \[DGV04; GV07; Kot+07; Kur02; Lam03; MA06; SR08\]. Protocols DGV
> \[DGV04\] and FaB Paxos \[MA06\] introduce a parametrized model with
> 3f+2p+1 replicas, where p ≥ 0. The parameter p describes the number of
> replicas that are not needed for the fast path. These protocols can
> terminate optimally fast in theory (2δ, or 2 network delays) under
> optimistic conditions. Liveness and safety issues of
>
> 6
>
> landmark papers were later pointed out \[Abr+17\], showcasing the
> complexity of the domain and thus posing the research question of fast
> consensus again. SBFT \[Gue+19\] addressed the correctness issues.
> SBFT can terminate after one round of voting, but is optimized for
> linear message complexity, therefore incurring higher latency.
>
> As pointed out by \[DGV04\], and later in \[KTZ21\] and \[Abr+21\],
> the lower bound of 3f + 2p + 1 actually only applies to a restricted
> type of protocol. These works prove the lower bound and show
> single-shot consensus protocols that use only 3f +2p∗ −1 replicas,
> with p∗ ≥ 1.
>
> Interestingly, in practice, one-step protocols might increase the
> finalization latency, as one-round finalization requires voting
> between n−p replicas, which could be slower than two rounds of voting
> between n−f −p replicas that are more concentrated in a geographic
> area. Banyan \[Von+24\] renewed interest in fast BFT protocols, as it
> performs a one-round and a two-round mechanism in parallel,
> guaranteeing the best possible latency.
>
> Concurrent Work. Kudzu \[SSV25\] is Alpenglow’s “academic sibling”
> with a simpler theoretical model. Like Alpenglow, Kudzu features high
> throughput via the previously mentioned technique of erasure coding,
> and one- and two-round parallel finalization paths. The differences
> between Alpenglow and Kudzu include:
>
> • Kudzu is specified in a permissioned model, while Alpenglow is a
> proof-of-stake protocol. In many protocols merely the voting weight of
> nodes would be impacted by this difference. However, disseminating
> erasure-coded data cannot be easily translated between these models.
>
> • Alpenglow features leader windows where the leader streams the data
> without interruption, improving throughput. Concurrent processing of
> slots allows block times to be shorter than the assumed latency bound
> (∆).
>
> • Alpenglow features fast leader handoff. When the leader is rotated,
> the next leader can start producing a block as soon as it has received
> the previous block.
>
> • With Assumption 3, Alpenglow features higher resilience to crash
> faults.
>
> • In Kudzu, due to the different model, nodes can vote as soon as they
> receive the first fragment of a block proposal, while in Alpenglow
> nodes vote after reconstructing a full proposal. In theory, the former
> is faster, while in practice, the difference is a fraction of one
> network delay.
>
> • The data expansion ratio associated with erasure coding can be
> freely set in Alpenglow. We suggest a ratio of 2, while in Kudzu the
> ratio needs to be higher.
>
> 7
>
> Follow-up Work. Hydrangea \[SKN25\] is a protocol proposed after
> Alpen-glow that parametrizes resilience to byzantine and crash faults
> in a way related to Alpenglow. The protocol requires n = 3f + 2c + k +
> 1, and tolerates f byzantine faults and c crash faults in partial
> synchrony. The number of nodes not needed for finalization in one
> round of voting is then p = ⌊<u>c+k</u>⌋. For ex-ample, to terminate
> in one round of voting among 80% of nodes, Hydrangea would set p = c =
> k = 20% and f = 13%, for a total of 33% of tolerated faulty nodes. In
> contrast, Alpenglow can tolerate f \< 20% and a total of 40% of faulty
> nodes, but needs Assumption 3 for fault rates higher than 20%.
>
> Hydrangea suffers from a bandwidth bottleneck at the leader and, in
> our view, remains underspecified for practical implementation.
> However, the parametrization is an interesting contribution than could
> also be applied to Alpenglow.
>
> 1.5 Model and Preliminaries
>
> Names. We introduce various objects of the form Name(x,y). This
> indi-cates some deterministic encoding of the object type “Name” and
> its param-eters x and y.
>
> Epoch. To allow for changing participants and other dynamics, the
> protocol rejuvenates itself in regular intervals. The time between two
> such changes is called an epoch. Epochs are numbered as e = 1,2,3,
> etc. The participants register/unregister two epochs earlier, i.e.,
> the participants (and their stake) of epoch e+1 are decided at the end
> of epoch e−1, i.e., a long enough time before epoch e+1 starts. This
> makes sure that everybody is in agreement on the current nodes and
> their stake at the beginning of epoch e+1.
>
> Node. We operate on n individual computers, which we call nodes v1,v2,
> ..., vn. The main jobs of these nodes are to send/relay messages and
> to validate blocks. Because of this, nodes are sometimes also called
> validators in the literature. While the set of nodes changes with
> every new epoch, as mentioned in the previous paragraph, the nodes are
> static and fixed during an epoch. The set of nodes is publicly known,
> i.e., each node knows how to contact (IP address and port number)
> every node vi. Each node has a public key, and all nodes know all
> public keys. The information of each node (public key, stake, IP
> address, port number, etc.) is announced and updated by including the
> information in a transaction on the blockchain. This guarantees that
> everybody has the same information. Currently, Solana has n ≈ 1,500
> nodes, but our protocol can in principle scale to higher numbers.
> However, for practical reasons it may be beneficial to bound n ≤ nmax.
>
> Message. Nodes communicate by exchanging authenticated messages. Our
> protocol never uses large messages. Specifically, all messages are
> less than
>
> 8
>
> 1,500 bytes \[Pos84\]. Because of this, we use UDP with
> authentication, so either QUIC-UDP or UDP with a pair-wise message
> authentication code (MAC). The symmetric keys used for this purpose
> are derived with a key exchange protocol using the public keys.
>
> Broadcast. Sometimes, a node needs to broadcast the same message to
> all (n − 1 other) nodes. The sender node simply loops over all other
> nodes and sends the message to one node after the other. Despite this
> loop, the total delay is dominated by the network delay. With a
> bandwidth of 1Gb/s, transmitting n = 1,500 shreds takes 18 ms (well
> below the average network delay of about 80 ms). To get to 80% of the
> total stake we need to reach n ≈ 150 nodes, which takes only about 2
> ms. Voting messages are shorter, and hence need even less time.
> Moreover, we can use a multicast primitive provided by an alternative
> network provider, e.g., DoubleZero \[FMW24\] or SCION \[Zha+11\].
>
> Stake. Each node vi has a known positive stake of cryptocurrency. We
> use ρi \> 0 to denote node vi’s fraction of the entire stake, i.e., ρi
> = 1. Each (fractional) stake ρi stays fixed during the epoch. The
> stake of a node signals how much the node contributes to the
> blockchain. If node v2 has twice the stake of node v1, node v2 will
> also earn roughly twice the fees. Moreover, node v2 also has twice the
> outgoing network bandwidth. However, all nodes need enough
> in-bandwidth to receive the blocks, and some minimum out-bandwidth to
> distribute blocks when they are a leader.
>
> Time. We assume that each node is equipped with a local system clock
> that is reasonably accurate, e.g., 50 ppm drift. We do not consider
> clock drift in our analysis, but it can be easily addressed by
> incorporating the assumed drift into timeout periods. Clocks do not
> need to be synchronized at all, as every node only uses its local
> system clock.
>
> Slot. Each epoch is partitioned into slots. A slot is a natural number
> asso-ciated with a block, and does not require timing agreements
> between nodes. The time period of a slot could start (and end) at a
> different local time for different nodes. Nevertheless, in normal
> network conditions the slots will become somewhat synchronized. During
> an epoch, the protocol will iterate through slots s = 1,2,...,L.
> Solana’s current parameter of L = 432,000 is possible, but much
> shorter epochs, e.g., L ≈ 18,000, could be advantageous, for instance
> to change stake more quickly. Each slot s is assigned a leader node,
> given by the deterministic function leader(s) (which is known before
> the epoch starts).
>
> Leader. Each slot has a designated leader from the set of nodes. Each
> leader will be in charge for a fixed amount of consecutive slots,
> known as the
>
> 9
>
> leader window. A threshold verifiable random function \[Dod02; MRV99\]
> is evaluated before each epoch to determine a publicly known leader
> schedule that defines which node is the leader in what slot.
>
> Timeout. Our protocol uses timeouts. Nodes set timeouts to make sure
> that the protocol does not get stuck waiting forever for some
> messages. For simplicity, timeouts are based on a global protocol
> parameter ∆, which is the maximum possible network delay between any
> two correct nodes when the network is in synchronous operation.
> However, timeout durations can be changed dynamically based on
> conditions, such that the protocol is correct irrespectively of the ∆
> exhibited by the network. For simplicity, we conser-vatively assume ∆
> to be a constant, e.g., ∆ ≈ 400 ms. Importantly, timeouts do not
> assume synchronized clocks. Instead, only short periods of time are
> measured locally by the nodes. Therefore, the absolute wall-clock time
> and clock skew have no significance to the protocol. Even extreme
> clock drift can be simply incorporated into the timeouts - e.g. to
> tolerate clock drift of 5%, the timeouts can simply be extended by 5%.
> As explained later, Alpenglow is partially-synchronous, so no timing-
> or clock-related errors can derail the protocol.
>
> Adversary. Some nodes can be byzantine in the sense that they can
> mis-behave in arbitrary ways. Byzantine nodes can for instance forget
> to send a message. They can also collude to attack the blockchain in a
> coordinated way. Some misbehavior (e.g. signing inconsistent
> information) may be a provable offense, while some other misbehavior
> cannot be punished, e.g., sending a message late could be due to an
> extraordinary network delay. As discussed in Assumption 1, we assume
> that all the byzantine nodes together own strictly less than 20% of
> the total stake. Up to an additional 20% of the stake may be crashed
> under the conditions described in Section 2.11. The remaining nodes
> are correct and follow the protocol. For simplicity, in our analysis
> (Sec-tions 2.9 to 2.11) we consider a static adversary over a period
> of one epoch.
>
> Asynchrony. We consider the partially synchronous network setting of
> Global Stabilization Time (GST) \[Con+24; DLS88\]. Messages sent
> between correct nodes will eventually arrive, but they may take
> arbitrarily long to arrive. We always guarantee safety, which means
> that irrespectively of ar-bitrary network delays (known as the
> asynchronous network model), correct nodes output the same blocks in
> the same order.
>
> Synchrony. However, we only guarantee liveness when the network is
> syn-chronous, and all messages are delivered quickly. In other words,
> correct nodes continue to make progress and output transactions in
> periods when messages between correct nodes are delivered “in time.”
> In the model of GST, synchrony simply corresponds to a global
> worst-case bound ∆ on mes-
>
> 10
>
> sage delivery. The GST model captures periods of synchrony and
> asynchrony by stating that before the unknown and arbitrary time GST
> (global stabi-lization time) messages can be arbitrarily delayed, but
> after time GST all previous and future messages m sent at time tm will
> arrive at the recipient at latest at time max(GST,tm)+∆.
>
> Network Delay. During synchrony, the protocol will rarely wait for a
> time-out. We model the actual message delay between correct nodes as
> δ, with δ ≪ ∆. The real message delay δ is variable and unknown.
> Naturally, δ is not part of the protocol, and will only be used for
> the latency analysis. In other words, the performance of
> optimistically responsive protocols such as Alpenglow in the common
> case depends only on δ and not the timeout bound ∆. As discussed in
> Section 1.3, we use δθ to indicate how long it takes a fraction θ of
> nodes to send each other messages. More precisely, let S be a set of
> nodes with cumulative stake at least θ. In one network delay δθ, each
> node in S sends a message to every node in S. If θ = 60% of the nodes
> are geographically close, then it is possible that 2δ60% is less time
> than δ80%, which needs only one network delay, but the involvement of
> 80% of the nodes.
>
> Correctness. The purpose of a blockchain is to produce a sequence of
> fi-nalized blocks containing transactions, so that all nodes output
> transactions in the same order. Every block is associated with a
> parent (starting at some notional genesis block). Finalized blocks
> form a single chain of parent-child links. When a block is finalized,
> all ancestors of the block are finalized as well.
>
> Our protocol orders blocks by associating them with natural numbered
> slots, where a child block has to have a higher slot number than its
> parent. For every slot, either some block produced by the leader might
> be finalized, or the protocol can yield a skip. The blocks in
> finalized slots are transmitted in-order to the execution layer of the
> protocol stack. Definition 14 describes the conditions for block
> finalization. The guarantees of our protocol can be stated as follows:
>
> • Safety. Suppose a correct node finalizes a block b in slot s. Then,
> if any correct node finalizes any block b′ in any slot s′ ≥ s, b′ is a
> descendant of b. (See also Theorem 1.)
>
> • Liveness. In any long enough period of network synchrony, correct
> nodes finalize new blocks produced by correct nodes. (See also
> Theo-rem 2.)
>
> 11
>
> 1.6 Cryptographic Techniques
>
> Hash Function. We have a collision-resistant hash function, e.g.,
> SHA256.
>
> Digital Signature. We have secure (non-forgeable) digital signatures.
> As stated earlier, each node knows the public key of every other node.
>
> Aggregate Signature. Signatures from different signers may be combined
> non-interactively to form an aggregate signature. Technically, we only
> require non-interactive multi-signatures, which only enable signatures
> over the same message to be aggregated. This can be implemented in
> various ways, e.g. based on BLS signatures \[Bon+03\]. Aggregate
> signatures allow certificates to fit into a short message as long as n
> ≤ nmax.
>
> Erasure Code. For integer parameters Γ ≥ γ ≥ 1, a (Γ,γ) erasure code
> encodes a bit string M of size m as a vector of Γ data pieces
> d1,...,dΓ of size m/γ + O(logΓ) each. The O(logΓ) overhead is needed
> to index each data piece. Erasure coding makes sure that any γ data
> pieces may be used to eficiently reconstruct M. The reconstruction
> algorithm also takes as input the length m of M, which we assume to be
> constant (achieved by padding smaller payloads).
>
> In our protocol, the payload of a slice will be encoded using a (Γ,γ)
> Reed-Solomon erasure code \[RS60\], which encodes a payload M as a
> vector d1,...,dΓ, where any γ di’s can be used to reconstruct M. The
> data expansion rate is κ = Γ/γ.
>
> Merkle Tree. A Merkle tree \[Mer79\] allows one party to commit to a
> vector of data (d1,...,dΓ) using a collision-resistant hash function
> by building a (full) binary tree where the leaves are the hashes of
> d1,...,dΓ. Each leaf hash is concatenated with a label that marks the
> hash as a leaf, and each internal node of the tree is the hash of its
> two children. The root r of the tree is the commitment.
>
> The validation path πi for position i ∈ {1,...,Γ} consists of the
> siblings of all nodes along the path in the tree from the hash of di
> to the root r. The root r together with the validation path πi can be
> used to prove that di is at position i of the Merkle tree with root r.
>
> The validation path is checked by recomputing the hashes along the
> cor-responding path in the tree, and by verifying that the recomputed
> root is equal to the given commitment r. If this verification is
> successful, we call di the data at position i with path πi for Merkle
> root r. The collision resistance
>
> of the hash function ensures that no data di = di can have a valid
> proof for position i in the Merkle tree.
>
> 12
>
> Encoding and Decoding. \[CT05\] The function encode takes as input a
> payload M of size m. It erasure codes M as (d1,...,dΓ) and builds a
> Merkle tree with root r where the leaves are the hashes of d1,...,dΓ.
> The root of the tree r is uniquely associated with M. It returns (r,
> {(di,πi)}i∈{1,...,Γ}), where each di is the data at position i with
> path πi for Merkle root r.
>
> The function decode takes as input (r, {(di,πi)}i∈I), where I is a
> subset of {1,...,Γ} of size γ, and each di (of correct length) is the
> data at position i with path πi for Merkle root r. Moreover, the
> decoding routine makes sure that the root r is correctly computed
> based on all Γ data pieces that correctly encode some message M′, or
> it fails. If it fails, it guarantees that no set of γ data pieces
> associated with r can be decoded, and that r was (provably)
> maliciously constructed.
>
> To ensure this pass/fail property, the decoding algorithm needs to
> check for each reconstructed data piece that it corresponds to the
> same root r. More
>
> precisely, decode reconstructs a message M′ from the data {di}i∈I.
> Then, it encodes M′ as a vector (d′ ,...,d′ ), and builds a Merkle
> tree with root r′ with the hashes of (d1,...,dΓ) as leaves. If r′ = r,
> decode returns M′, otherwise it fails.
>
> 2 The Alpenglow Protocol
>
> In this section we describe the Alpenglow protocol in detail.
>
> Blokstor Repair
>
> Pool block creation Rotor
>
> Votor broadcast
>
> Figure 1: Overview of components of Alpenglow and their interactions.
> Ar-rows show information flow: block data in the form of shreds
> (blue), internal events (green), and votes/certificates (red).
>
> 13
>
> 2.1 Shred, Slice, Block
>
> hash(b)
>
> r1 r2 ... rk

||
||
||

> slice 1 slice 2
>
> block b

d1 d2 ... dΓ

> slice k
>
> Figure 2: Hierarchy of block data, visualizing the double-Merkle
> construction of the block hash. Each slice has a Merkle root hash ri,
> which are in turn the leaf nodes for the second Merkle tree, where the
> root corresponds to the block hash.
>
> Definition 1 (shred). A shred fits neatly in a UDP datagram. It has
> the form:
>
> (s,t,i,zt,rt,(di,πi),σt),
>
> where
>
> • s,t,i ∈ N are slot number, slice index, shred index, respectively,
>
> • zt ∈ {0,1} is a flag (see Definition 2 below),
>
> • di is the data at position i with path πi for Merkle root rt
> (Section 1.6),
>
> • σt is the signature of the object Slice(s,t,zt,rt) from the node
> leader(s).
>
> Definition 2 (slice). A slice is the input of Rotor, see Section 2.2.
> Given any γ of the Γ shreds, we can decode (Section 1.6) the slice. A
> slice has the form:
>
> s,t,zt,rt,Mt,σt ,
>
> where
>
> • s,t ∈ N are the slot number and slice index respectively,
>
> • zt ∈ {0,1} is a flag indicating the last slice index,
>
> • Mt is the decoding of the shred data {(di)}i∈I for Merkle root rt,
>
> • σt is the signature of the object Slice(s,t,zt,rt) from the node
> leader(s).
>
> 14
>
> Definition 3 (block). A block b is the sequence of all slices of a
> slot, for the purpose of voting and reaching consensus. A block is of
> the form:
>
> b = { s,t,zt,rt,Mt,σt}t∈{1,...,k},
>
> where zk = 1, zt = 0 for t \< k. The data of the block is the
> concatenation of all the slice data, i.e., M = (M1,M2,...,Mk). We
> define slot(b) = s. The block data M contains information about the
> slot slot(parent(b)) and hash hash(parent(b)) of the parent block of
> b. There are various limits on a block, for instance, each block can
> only have a bounded amount of bytes and a bounded amount of time for
> execution.
>
> Definition 4 (block hash). We define hash(b) of block b = {
> s,t,zt,rt,Mt, σt }t∈{1,...,k} as the root of a Merkle tree T where:
>
> • T is a complete, full binary tree with the smallest possible number
> of leaves m (with m being a power of 2) such that m ≥ k,
>
> • the first k leaves of T are r1,...,rk (each hash is concatenated
> with a label that marks the hash as a leaf),
>
> • the remaining leaves of T are ⊥.
>
> Definition 5 (ancestor and descendant). An ancestor of a block b is
> any block that can be reached from b by the parent links, i.e., b, b’s
> parent, b’s parent’s parent, and so on. If b′ is an ancestor of b, b
> is a descendant of b′. Note that b is its own ancestor and descendant.
>
> 2.2 Rotor
>
> Rotor is the block dissemination protocol of Alpenglow. The leader
> (sender) wants to broadcast some data (a block) to all other nodes.
> This procedure should have low latency, utilize the bandwidth of the
> network in a balanced way, and be resilient to transmission failures.
> The block should be produced and transmitted in a streaming manner,
> that is, the leader does not need to wait until the entire block is
> constructed.
>
> leader
>
> shred-1 relay shred-2 relay ... shred-Γ relay
>
> v1 v2 ... vn v1 v2 ... vn v1 v2 ... vn
>
> Figure 3: Basic structure of the Rotor data dissemination protocol.
>
> 15
>
> A leader uses multiple rounds of the Rotor protocol to broadcast a
> block. Each round considers the independent transmission of one slice
> of the block. The leader transmits each slice as soon as it is ready.
> This achieves pipelining of block production and transmission.
>
> For each slice, the leader generates Γ Reed-Solomon coding shreds and
> constructs a Merkle tree over their hashes and signs the root. Each
> coding shred includes the Merkle path along with the root signature.
> Each shred contains as much data and corresponding metadata as can fit
> into a single UDP datagram.
>
> Using Reed-Solomon erasure coding \[RS60\] ensures that, at the cost
> of sending more data, receiving any γ shreds is enough to reconstruct
> the slice (Section 1.6). After that, as an additional validity check,
> a receiver generates the (up to Γ −γ) missing shreds.
>
> For any given slice, the leader sends each shred directly to a
> corresponding node selected as shred relay. We sample relays for every
> slice. We use a novel sampling method which improves resilience. We
> describe our new method in detail in Section 3.1.
>
> Each relay then broadcasts its shred to all nodes that still need it,
> i.e., all nodes except for the leader and itself, in decreasing stake
> order. As a minor optimization, all shred relays send their shred to
> the next leader first. This slightly improves latency for the next
> leader, who most urgently needs the block.
>
> A shred’s authenticity needs to be checked to reconstruct the slice
> from γ of the shreds. To enable receivers to cheaply check
> authenticity of each shred individually, the leader builds a Merkle
> tree \[Mer79\] over all shreds of a slice, as described in Section
> 1.6. Each shred then includes its path in the tree and the leader’s
> signature of the root of the tree.
>
> When receiving the first shred of a slice, a node checks the validity
> of the Merkle path and the leader’s signature, and then stores the
> verified root. For any later shred, the receiving node only checks the
> validity of the Merkle path against the stored root.
>
> 16
>
> Average Rotor Latency (γ = 32) 120
>
> 100
>
> 80
>
> 60
>
> 40
>
> 20

Median Rotor Latency (γ = 32) 120

100

> 80
>
> 60
>
> 40
>
> 20
>
> 0
>
> 64 80 96 320 Total shreds (Γ)

0

> 64 80 96 320 Total shreds (Γ)
>
> Figure 4: Rotor latency for different data expansion ratios (and thus
> total numbers of shreds), all with γ = 32 data shreds using our
> sampling from Section 3.1. The red lines indicate the average/median
> network latency. With a high data expansion rate (κ = 10, hence Γ =
> 320) we pretty much achieve the single δ latency described in Lemma 8.
> All our simulation results use the current (epoch 780) Solana stake
> distribution. Network latency is inferred from public data.
> Computation and transmission delays are omitted.
>
> Definition 6. Given a slot s, we say that Rotor is successful if the
> leader of s is correct, and at least γ of the corresponding relays are
> correct.
>
> Resilience. If the conditions of Definition 6 are met, all correct
> nodes will receive the block distributed by the leader, as enough
> relays are correct. On the other hand, a faulty leader can simply not
> send any data, and Rotor will immediately fail. In the following we
> assume that the leader is correct. The following lemma shows that
> Rotor is likely to succeed if we over-provision the coding shreds by
> at least 67%.
>
> Lemma 7 (rotor resilience). Assume that the leader is correct, and
> that erasure coding over-provisioning is at least κ = Γ/γ \> 5/3. If γ
> → ∞, with probability 1, a slice is received correctly.
>
> Proof Sketch. We choose the relay nodes randomly, according to stake.
> The failure probability of each relay is less than 40% according to
> Section 1.2. The expected value of correct relays is then at least
> 60%·Γ \> 60%·5γ/3 = γ. So strictly more than γ shreds will arrive in
> expectation. With γ → ∞, applying an appropriate Chernoff bound, with
> probability 1 we will have at least γ shreds that correctly arrive at
> all nodes.
>
> 17
>
> Latency. The latency of Rotor is between δ and 2δ, depending on
> whether we make optimistic or pessimistic assumptions on various
> parameters.
>
> Lemma 8. (rotor latency) If Rotor succeeds, network latency of Rotor
> is at most 2δ. A high over-provisioning factor κ can reduce latency.
> In the extreme case with n → ∞ and κ → ∞, we can bring network latency
> down to δ. (See also Figure 4 for simulation results with Solana’s
> stake distribution.)
>
> Proof Sketch. Assuming a correct leader, all relays receive their
> shred in time δ directly from the leader. The correct relays then send
> their shred to the nodes in another time δ, so in time 2δ in total.
>
> If we over-provision the relays, chances are that many correct relays
> are geographically located between leader and the receiving node. In
> the extreme case with infinitely many relays, and some natural stake
> distribution assump-tions, there will be at least γ correct relays
> between any pair of leader and receiving node. If the relays are on
> the direct path between leader and re-ceiver, they do not add any
> overhead, and both legs of the trip just sum up to δ.
>
> Bandwidth. Both the leader and the shred relays are sampled by stake.
> As a result, in expectation each node has to transmit data
> proportional to their stake. This aligns well with the fact that
> staking rewards are also proportional to the nodes’ stake. If the
> available out-bandwidth is proportional to stake, it can be utilized
> perfectly apart from the overhead.
>
> Lemma 9 (bandwidth optimality). Assume a fixed leader sending data at
> rate βℓ ≤ β, where β is the average outgoing bandwidth across all
> nodes. Suppose any distribution of out-bandwidth and proportional node
> stake. Then, at every correct node, Rotor delivers block data at rate
> βℓ/κ in expectation. Up to the data expansion rate κ = Γ/γ, this is
> optimal.
>
> Proof. Node vi is chosen to be a shred relay in expectation Γρi times.
> Each shred relay receives data from the leader with bandwidth βℓ/Γ,
> because the leader splits its bandwidth across all shred relays.
> Hence, in expectation, node vi receives data from the leader at rate
> Γρi ·βℓ/Γ = ρiβℓ. Node vi needs to forward this data to n−2 nodes. So,
> in expectation, node vi needs to send data at rate ρiβℓ(n − 2). Node
> vi has outgoing bandwidth βi = nβρi, since outgoing bandwidth is
> proportional to stake (Section 1.5). Since βℓ ≤ β, we have ρiβℓ(n − 2)
> \< βi. Each node thus has enough outgoing bandwidth to support the
> data they need to send.
>
> Note that we cannot get above rate βℓ because the leader is the only
> one who knows the data. Likewise we cannot get above rate β, because
> all nodes need to receive the data, and the nodes can send with no
> more total rate than nβ. So apart from the data expansion factor κ, we
> are optimal.
>
> Note that any potential attacks on Rotor may only impact liveness, not
>
> 18
>
> safety, since the other parts of Alpenglow ensure safety even under
> asynchrony and rely on Rotor only for data dissemination.
>
> 2.3 Blokstor
>
> Blokstor collects and stores the first block received through Rotor in
> every slot, as described in Definition 10.
>
> Definition 10 (Blokstor). The Blokstor is a data structure managing
> the storage of slices disseminated by the protocol of Section 2.2.
> When a shred (s,t,i,zt,rt,(di,πi),σt) is received by a node, the node
> checks the following conditions. If the conditions are satisfied, the
> shred is added to the Blokstor:
>
> • the Blokstor does not contain a shred for indices (s,t,i) yet,
>
> • (di,πi) is the data with path for Merkle root rt at position i,
>
> • σt is the signature of the object Slice(s,t,zt,rt) from the node
> leader(s).
>
> Blokstor emits the event Block(slot(b),hash(b),hash(parent(b))) as
> input for Algorithm 1 when it receives the first complete block b for
> slot(b).
>
> In addition to storing the first block received for a given slot, the
> Blokstor can perform the repair procedure (Section 2.8) to collect
> some other block b and store it in the Blokstor. If a block is
> finalized according to Definition 14, Blokstor has to collect and
> store only this block in the given slot. Otherwise, before the event
> SafeToNotar(slot(b),hash(b)) of Definition 16 is emitted, b has to be
> stored in the Blokstor as well.
>
> 2.4 Votes and Certificates
>
> Next we describe the voting data structures and algorithms of
> Alpenglow. In a nutshell, if a leader gets at least 80% of the stake
> to vote for its block, the block is immediately finalized after one
> round of voting with a fast-finalization certificate. However, as soon
> as a node observes 60% of stake voting for a block, it issues its
> second-round vote. After 60% of stake voted for a block the second
> time, the block is also finalized. On the other hand, if enough stake
> considers the block late, a skip certificate can be produced, and the
> block proposal will be skipped.
>
> Definition 11 (messages). Alpenglow uses voting and certificate
> messages listed in Tables 5 and 6.
>
> 19

||
||
||
||
||
||
||
||

> Table 5: Alpenglow’s voting messages with respect to block b and slot
> s. Each object is signed by a signature σv of the voting node v.

||
||
||
||
||
||
||
||

> Table 6: Alpenglow’s certificate messages. Σ is the cumulative stake
> of the aggregated votes (σi)I⊆{1,...,n} in the certificate, i.e., Σ =
> i∈I ρi.
>
> 2.5 Pool
>
> Every node maintains a data structure called Pool. In its Pool, each
> node memorizes all votes and certificates for every slot.
>
> Definition 12 (storing votes). Pool stores received votes for every
> slot and every node as follows:
>
> • The first received notarization or skip vote,
>
> • up to 3 received notar-fallback votes,
>
> • the first received skip-fallback vote, and
>
> • the first received finalization vote.
>
> Definition 13 (certificates). Pool generates, stores and broadcasts
> certifi-cates:
>
> • When enough votes (see Table 6) are received, the respective
> certificate is generated.
>
> • When a received or constructed certificate is newly added to Pool,
> the certificate is broadcast to all other nodes.
>
> 20
>
> • A single (received or constructed) certificate of each type
> corresponding to the given block/slot is stored in Pool.
>
> Note that the conditions in Table 6 imply that if a correct node
> generated the Fast-Finalization Certificate, it also generated the
> Notarization Certifi-cate, which in turn implies it generated the
> Notar-Fallback Certificate.
>
> Definition 14 (finalization). We have two ways to finalize a block:
>
> • If a finalization certificate on slot s is in Pool, the unique
> notarized block in slot s is finalized (we call this slow-finalized).
>
> • If a fast-finalization certificate on block b is in Pool, the block
> b is final-ized (fast-finalized).
>
> Whenever a block is finalized (slow or fast), all ancestors of the
> block are finalized first.
>
> Definition 15 (Pool events). The following events are emitted as input
> for Algorithm 1:
>
> • BlockNotarized(slot(b),hash(b)): Pool holds a notarization
> certificate for block b.
>
> • ParentReady(s,hash(b)): Slot s is the first of its leader window,
> and Pool holds a notarization or notar-fallback certificate for a
> previous block b, and skip certificates for every slot s′ since b,
> i.e., for slot(b) \< s′ \< s.
>
> As we will see later (Lemmas 20 and 35), for every slot s, every
> cor-rect node will cast exactly one notarization or skip vote. After
> casting this initial vote, the node might emit events according to
> Definition 16 and cast additional votes.
>
> The event SafeToNotar(s,b) indicates that it is not possible that some
> block b′ = b could be fast-finalized (Definition 14) in slot s, and so
> it is safe to issue the notar-fallback vote for b.
>
> Similarly, SafeToSkip(s) indicates that it is not possible that any
> block in slot s could be fast-finalized (Definition 14), and so it is
> safe to issue the skip-fallback vote for s.
>
> Definition 16 (fallback events). Consider block b in slot s = slot(b).
> By notar(b) denote the cumulative stake of nodes whose notarization
> votes for block b are in Pool, and by skip(s) denote the cumulative
> stake of nodes whose skip votes for slot s are in Pool. Recall that by
> Definition 12 the stake of any node can be counted only once per slot.
> The following events are emitted as input for Algorithm 1:
>
> • SafeToNotar(s,hash(b)): The event is only issued if the node voted
> in
>
> 21
>
> slot s already, but not to notarize b. Moreover:
>
> notar(b) ≥ 40% or skip(s)+ notar(b) ≥ 60% and notar(b) ≥ 20% .
>
> If s is the first slot in the leader window, the event is emitted.
> Otherwise, block b is retrieved in the repair procedure (Section 2.8)
> first, in order to identify the parent of the block. Then, the event
> is emitted when Pool contains the notar-fallback certificate for the
> parent as well.
>
> • SafeToSkip(s): The event is only issued if the node voted in slot s
> al-ready, but not to skip s. Moreover:
>
> X
>
> skip(s)+ notar(b)−maxnotar(b) ≥ 40%. b b
>
> 2.6 Votor
>
> slow-finalization
>
> fast-finalization Leader sends notarization
>
> Relays send
>
> Notar. votes
>
> Final. votes
>
> Figure 7: Protocol overview: a full common case life cycle of a block
> in Alpenglow.
>
> The purpose of voting is to notarize and finalize blocks. Finalized
> blocks constitute a single chain of parent references and indicate the
> output of the protocol.
>
> The protocol ensures that for every slot, either a skip certificate is
> created, or some block b is notarized (or notarized-fallback), such
> that all ancestors of b are also notarized. Condition thresholds
> ensure that a malicious leader cannot prevent the creation of
> certificates needed for liveness. If many correct nodes produced
> notarization votes for the same block b, then all other correct nodes
> will make notar-fallback votes for b. Otherwise, all correct nodes
> will broadcast skip-fallback votes.
>
> By Definition 14, a node can finalize a block as soon as it observes
> enough notarization votes produced by other nodes immediately upon
> receiving a block. However, a lower participation threshold is
> required to make a nota-
>
> 22
>
> rization certificate. Then the node will send the finalization vote.
> Therefore, blocks are finalized after one round of voting among nodes
> with 80% of the stake, or two rounds of voting among nodes with 60% of
> the stake.
>
> Nodes have local clocks and emit timeout events. Whenever a node v’s
> Pool emits the event ParentReady(s,...), it starts timeout timers
> correspond-ing to all blocks of the leader window beginning with slot
> s. The timeouts are parametrized with two delays (pertaining to
> network synchrony):
>
> • ∆block: This denotes the protocol-specified block time.
>
> • ∆timeout: Denotes the rest of the possible delay (other than ∆block)
> be-tween setting the timeouts and receiving a correctly disseminated
> block. As a conservative global constant, ∆timeout can be set to (1∆ +
> 2∆) \> (time needed for the leader to observe the certificates) +
> (latency of slice dissemination through Rotor).
>
> Definition 17 (timeout). When a node v’s Pool emits the first event
> Parent-Ready(s,...), Timeout(i) events for the leader window beginning
> with s (for all i ∈ windowSlots(s)) are scheduled at the following
> times:
>
> Timeout(i) : clock()+∆timeout +(i−s+1) ·∆block.
>
> The timeouts are set to correspond to the latest possible time of
> receiving a block if the leader is correct and the network is
> synchronous. Timeouts can be optimized, e.g., by fine-grained ∆
> estimation or to address specific faults, such as crash faults.
>
> Note that ParentReady(s,...) is only emitted for the first slot s of a
> win-dow. Therefore, (i − s + 1) ≥ 1 and Timeout(i) is never scheduled
> to be emitted in the past.
>
> Definition 18 (Votor state). Votor (Algorithms 1 and 2) accesses state
> as-sociated with each slot. The state of every slot is initialized to
> the empty set: state ← \[∅,∅,...\]. The following objects can be
> permanently added to the state of any slot s:
>
> • ParentReady(hash(b)): Pool emitted the event ParentReady(s,hash(b)).
>
> • Voted: The node has cast either a notarization vote or a skip vote
> in slot s.
>
> • VotedNotar(hash(b)): The node has cast a notarization vote on block
> b in slot s.
>
> • BlockNotarized(hash(b)): Pool holds the notarization certificate for
> block b in slot s.
>
> • ItsOver: The node has cast the finalization vote in slot s, and will
> not cast any more votes in slot s.
>
> 23
>
> • BadWindow: The node has cast at least one of these votes in slot s:
> skip, skip-fallback, notar-fallback.
>
> Additionally, every slot can be associated with a pending block, which
> is initialized to bottom: pendingBlocks ← \[⊥,⊥,...\]. The
> pendingBlocks are blocks which will be revisited to call tryNotar(),
> as the tested condition might be met later.
>
> Algorithm 1 Votor, event loop, single-threaded
>
> 1: upon Block(s,hash,hashparent) do
>
> 2: if tryNotar(Block(s,hash,hashparent)) then 3: checkPendingBlocks()
>
> 4: else if Voted ∈ state\[s\] then
>
> 5: pendingBlocks\[s\] ← Block(s,hash,hashparent)
>
> 6: upon Timeout(s) do
>
> 7: if Voted ∈ state\[s\] then 8: trySkipWindow(s)
>
> 9: upon BlockNotarized(s,hash(b)) do
>
> 10: state\[s\] ← state\[s\]∪{BlockNotarized(hash(b))} 11:
> tryFinal(s,hash(b))
>
> 12: upon ParentReady(s,hash(b)) do
>
> 13: state\[s\] ← state\[s\]∪{ParentReady(hash(b))} 14:
> checkPendingBlocks()
>
> 15: setTimeouts(s) ▷ start timer for all slots in this window
>
> 16: upon SafeToNotar(s,hash(b)) do 17: trySkipWindow(s)
>
> 18: if ItsOver ∈ state\[s\] then
>
> 19: broadcast NotarFallbackVote(s,hash(b)) 20: state\[s\] ←
> state\[s\]∪{BadWindow}
>
> 21: upon SafeToSkip(s) do 22: trySkipWindow(s)
>
> 23: if ItsOver ∈ state\[s\] then
>
> 24: broadcast SkipFallbackVote(s) 25: state\[s\] ←
> state\[s\]∪{BadWindow}

▷ notar-fallback vote

> ▷ skip-fallback vote
>
> 24
>
> Algorithm 2 Votor, helper functions
>
> 1: function windowSlots(s)
>
> 2: return array with slot numbers of the leader window with slot s
>
> 3: function setTimeouts(s) ▷ s is first slot of window 4: for i ∈
> windowSlots(s) do ▷ set timeouts for all slots 5: schedule event
> Timeout(i) at time clock()+∆timeout+(i−s+1)·∆block
>
> 6: ▷ Check if a notarization vote can be cast. ◁ 7: function
> tryNotar(Block(s,hash,hashparent))
>
> 8: if Voted ∈ state\[s\] then 9: return false
>
> 10: firstSlot ← (s is the first slot in leader window) ▷ boolean 11:
> if (firstSlot and ParentReady(hashparent) ∈ state\[s\]
>
> or (not firstSlot and VotedNotar(hashparent) ∈ state\[s−1\]) then
>
> 12: broadcast NotarVote(s,hash) ▷ notarization vote 13: state\[s\] ←
> state\[s\]∪{Voted,VotedNotar(hash)}
>
> 14: pendingBlocks\[s\] ← ⊥ ▷ won’t vote notar a second time 15:
> tryFinal(s,hash) ▷ maybe vote finalize as well 16: return true
>
> 17: return false
>
> 18: function tryFinal(s,hash(b))
>
> 19: if BlockNotarized(hash(b)) ∈ state\[s\] and VotedNotar(hash(b)) ∈
> state\[s\] and BadWindow ∈ state\[s\] then
>
> 20: broadcast FinalVote(s) ▷ finalization vote 21: state\[s\] ←
> state\[s\]∪{ItsOver}
>
> 22: function trySkipWindow(s)
>
> 23: for k ∈ windowSlots(s) do ▷ skip unvoted slots 24: if Voted ∈
> state\[k\] then
>
> 25: broadcast SkipVote(k) ▷ skip vote 26: state\[k\] ←
> state\[k\]∪{Voted,BadWindow}
>
> 27: pendingBlocks\[k\] ← ⊥ ▷ won’t vote notar after skip
>
> 28: function checkPendingBlocks()
>
> 29: for s : pendingBlocks\[s\] = ⊥ do ▷ iterate with increasing s 30:
> tryNotar(pendingBlocks\[s\])
>
> 25
>
> 2.7 Block Creation
>
> The leader v of the window beginning with slot s produces blocks for
> all slots windowSlots(s)inthewindow. Aftertheevent
> ParentReady(s,hash(bp)) is emitted, v can be sure that a block b in
> slot s with bp as its parent will be valid. In other words, other
> nodes will receive the certificates that resulted in v emitting
> ParentReady(hash(bp)), and emit this event themselves. As a result,
> all correct nodes will vote for b.
>
> In the common case, only one ParentReady(s,hash(bp)) will be emitted
> for a given s. Then, v has to build its block on top of bp and cannot
> “fork off” the chain in any way. If v emits many
> ParentReady(s,hash(bp)) events for different blocks bp (as a result of
> the previous leader misbehaving or network delays), v can build its
> block with any such bp as its parent.
>
> Algorithm 3 introduces an optimization where v starts building its
> block “optimistically” before any ParentReady(s,hash(bp)) is emitted.
> Usually v will receive some block bp in slot s − 1 first, then observe
> a certificate for bp after additional network delay, and only then
> emit ParentReady(s,hash(bp)). Algorithm 3 avoids this delay in the
> common case. If v started building a block with parent bp, but then
> only emits ParentReady(s,hash(b′ )) where
>
> bp = bp, v will then instead indicate bp as the parent of the block in
> the content of some slice t. In this case, slices 1,...,t − 1 are
> ignored for the
>
> purpose of execution.
>
> We allow changing the indicated parent of a block only once, and only
> in blocks in the first slot of a given window.
>
> When a leader already observed some ParentReady(s,...), the leader
> pro-duces all blocks of its leader window without delays. As a result,
> the first block b0 alwaysbuildsonsomeparent bp suchthat v emitted
> ParentReady(s,hash(bp)), b0 is the parent of the block b1 in slot s +
> 1, b1 is the parent of the block b2 in slot s+2, and so on.
>
> bk ParentReady(s,b1)
>
> b1 b2 b3 ··· bk
>
> bk ParentReady(s,b′ )
>
> b1 b2 b3 ··· bk
>
> b2 starts here with a different parent b′
>
> Figure 8: Handover between leader windows with k slices per block. The
> new leader starts to produce the first slice of its first block (b1)
> as soon as it received the last slice (bk) of the previous leader. The
> common case is on top and the case where leader switches parents at
> the bottom, see also Algorithm 3.
>
> 26
>
> Algorithm 3 Block creation for leader window starting with slot s
>
> 1: wait until block bp in slot s−1 received or ParentReady(hash(bp)) ∈
> state\[s\] 2: b ← generate a block with parent bp in slot s ▷ block
> being produced 3: t ← 1 ▷ slice index 4: while ParentReady(...) ∈
> state\[s\] do ▷ produce slices optimistically 5: Rotor(slice t of b)
>
> 6: t ← t+1
>
> 7: if ParentReady(hash(bp)) ∈ state\[s\] then ▷ change parent, reset
> block 8: bp ← any b′ such that ParentReady(hash(b′)) ∈ state\[s\]
>
> 9: b ← generate a block with parent bp in slot s starting with slice
> index t 10: start ← clock() ▷ some parent is ready, set timeout
>
> 11: while clock() \< start +∆block do ▷ produce rest of block in
> normal slot time 12: Rotor(slice t of b)
>
> 13: t ← t+1
>
> 14: for remaining slots of the window s′ = s+1,s +2,... do 15: b ←
> generate a block with parent b in slot s′
>
> 16: Rotor(b) over ∆block
>
> 2.8 Repair
>
> Repair is the process of retrieving a block with a given hash that is
> missing from Blokstor. After Pool obtains a certificate of signatures
> on Notar(slot(b),hash(b)) or NotarFallback(slot(b),hash(b)), the block
> b with hash hash(b) according to Definition 4 needs to be retrieved.
>
> Definition 19 (repair functions). The protocol supports functions for
> the repair process:
>
> • sampleNode(): Choose some node v at random based on stake.
>
> • getSliceCount(hash(b),v): Contact node v, which returns (k,rk,πk)
> where:
>
> – k is the number of slices of b as in Definition 4,
>
> – rk is the hash at position k with path πk for Merkle root hash(b).
>
> The requesting node needs to make sure rk is the last non-zero leaf of
> the Merkle tree with root hash(b). It verifies that the rightward
> intermediate hashes in πk correspond to empty sub-trees.
>
> • getSliceHash(t,hash(b),v): Contact node v, which returns (rt,πt)
> where rt is the hash at position t with path πt for Merkle root
> hash(b).
>
> • getShred(s,t,i,rt,v): Contact node v, which returns the shred
> (s,t,i,zt, rt,(di,πi),σt) as in Definition 1.
>
> 27
>
> The functions can fail verification of the data provided by v and
> return ⊥ (e.g. if invalid data is returned or v simply does not have
> the correct data to return).
>
> Algorithm 4 Repair block b with hash(b) in slot s
>
> 1: k ← ⊥
>
> 2: while k = ⊥ do ▷ find the number of slices k in b 3: (k,rk,πk) ←
> getSliceCount(hash(b),sampleNode())
>
> 4: for t = 1,...,k concurrently do
>
> 5: while rt = ⊥ do ▷ get slice hash rt if missing 6: (rt,πt) ←
> getSliceHash(t,hash(b),sampleNode())
>
> 7: for each shred index i concurrently do
>
> 8: while shred with indices s, t, i missing do ▷ get shred if missing
> 9: shred ← getShred(s,t,i,rt,sampleNode())
>
> 10: store shred if valid
>
> 2.9 Safety
>
> In the following analysis, whenever we say that a certificate exists,
> we mean that a correct node observed the certificate. Whenever we say
> that an ancestor b′ of a block b exists in some slot s = slot(b′), we
> mean that starting at block b and following the parent links in blocks
> with the given hash we reach block b′ in slot s = slot(b′).
>
> Lemma 20 (notarization or skip). A correct node exclusively casts only
> one notarization vote or skip vote per slot.
>
> Proof. Notarizationvotesandskipvotesareonlycastviafunctions tryNotar()
> and trySkipWindow() of Algorithm 2, respectively. Votes are only cast
> if Voted ∈ state\[s\]. After voting, the state is modified so that
> Voted ∈ state\[s\]. Therefore, a notarization or skip vote can only be
> cast once per slot by a correct node.
>
> Lemma 21 (fast-finalization property). If a block b is fast-finalized:
>
> \(i\) no other block b′ in the same slot can be notarized,
>
> \(ii\) no other block b′ in the same slot can be notarized-fallback,
>
> \(iii\) there cannot exist a skip certificate for the same slot.
>
> Proof. Suppose some correct node fast-finalized some block b in slot
> s. By Definition 14, nodes holding at least 80% of stake cast
> notarization votes for b. Recall (Assumption 1) that all byzantine
> nodes hold less than 20% of stake. Therefore, a set V of correct nodes
> holding more than 60% of stake cast notarization votes for b.
>
> 28
>
> \(i\) By Lemma 20, nodes in V cannot cast a skip vote or a
> notarization vote for a different block b′ = b. Therefore, the
> collective stake of nodes casting a notarization vote for b′ has to be
> smaller than 40%.
>
> \(ii\) Correct nodes only cast notar-fallback votes in Algorithm 1
> when Pool emits the event SafeToNotar. By Definition 16, a correct
> node emits SafeToNotar(s,hash(b′)), if either a) at least 40% of stake
> holders voted to notarize b′, or b) at least 60% of stake holders
> voted to notarize b′ or skip slot s. Only nodes v ∈/ V holding less
> than 40% of stake can vote to notarize b′ or skip slot s. Therefore,
> no correct nodes can vote to notar-fallback b′.
>
> \(iii\) Skip-fallback votes are only cast in Algorithm 1 by correct
> nodes if Pool emits the event SafeToSkip. By Definition 16, a correct
> node can emit SafeToSkip if at least 40% of stake have cast a skip
> vote or a notarization vote on b′ = b in slot s. Only nodes v ∈/ V
> holding less than 40% of stake can cast a skip vote or a notarization
> vote on b′ = b in slot s. Therefore, no correct nodes vote to
> skip-fallback, and no nodes in V vote to skip or skip-fallback slot s.
>
> Lemma 22. If a correct node v cast a finalization vote in slot s, then
> v did not cast a notar-fallback or skip-fallback vote in s.
>
> Proof. A correct node adds ItsOver to its state of slot s in line 21
> of Algo-rithm 2 when casting a finalization vote. Notar-fallback or
> skip-fallback votes can only be cast if ItsOver ∈ state\[s\] in lines
> 18 and 23 of Algorithm 1 respec-tively. Therefore, notar-fallback and
> skip-fallback votes cannot be cast by v in slot s after casting a
> finalization vote in slot s.
>
> On the other hand, a correct node adds BadWindow to its state of slot
> s when casting a notar-fallback or skip-fallback vote in slot s. A
> finalization vote can only be cast if BadWindow ∈ state\[s\] in line
> 19 of Algorithm 2. Therefore, a finalization vote cannot be cast by v
> in slot s after casting a notar-fallback and skip-fallback vote in
> slot s.
>
> Lemma 23. If correct nodes with more than 40% of stake cast
> notarization votes for block b in slot s, no other block can be
> notarized in slot s.
>
> Proof. Let V be the set of correct nodes that cast notarization votes
> for b. Suppose for contradiction some b′ = b in slot s is notarized.
> Since 60% of stake holders had to cast notarization votes for b′
> (Definition 11), there is a node v ∈ V that cast notarization votes
> for both b and b′, contradicting Lemma 20.
>
> Lemma 24. At most one block can be notarized in a given slot.
>
> Proof. Suppose a block b is notarized. Since 60% of stake holders had
> to cast notarization votes for b (Definition 11) and we assume all
> byzantine nodes hold less than 20% of stake, then correct nodes with
> more than 40% of stake cast notarization votes for b. By Lemma 23, no
> block b′ = b in the same slot can be notarized.
>
> 29
>
> Lemma 25. If a block is finalized by a correct node, the block is also
> notarized.
>
> Proof. If b was fast-finalized by some correct node, nodes with at
> least 80% of the stake cast their notarization votes for b. Since
> byzantine nodes possess less than 20% of stake, correct nodes with
> more than 60% of stake broadcast their notarization votes, and correct
> nodes will observe a notarization certificate for b.
>
> If b was slow-finalized by some correct node, nodes with at least 60%
> of stake cast their finalization vote for b (Def. 11 and 14),
> including some correct nodes. Correct nodes cast finalization votes
> only if BlockNotarized(hash(b)) ∈ state\[s\] in line 19 of Algorithm 2
> after they observe some notarization certifi-cate. By Lemma 24, this
> notarization certificate has to be for b.
>
> Lemma 26 (slow-finalization property). If a block b is slow-finalized:
>
> \(i\) no other block b′ in the same slot can be notarized,
>
> \(ii\) no other block b′ in the same slot can be notarized-fallback,
>
> \(iii\) there cannot exist a skip certificate for the same slot.
>
> Proof. Suppose some correct node slow-finalized some block b in slot
> s. By Definition 14, nodes holding at least 60% of stake cast
> finalization votes in slot s. Recall that we assume all byzantine
> nodes to hold less than 20% of stake. Therefore, a set V of correct
> nodes holding more than 40% of stake cast finalization votes in slot
> s. By condition in line 19 of Algorithm 2, nodes in V observed a
> notarization certificate for some block. By Lemma 24, all nodes in V
> observed a notarization certificate for the same block b, and because
> of the condition in line 19, all nodes in V previously cast a
> notarization vote for b. By Lemmas 20 and 22, all nodes in V cast no
> votes in slot s other than the notarization vote for b and the
> finalization vote. Since nodes in V hold more than 40% of stake, and
> every certificate requires at least 60% of stake holder votes, no skip
> certificate or certificate on another block b′ = b in slot s can be
> produced.
>
> Lemma 27. If there exists a notarization or notar-fallback certificate
> for block b, then some correct node cast its notarization vote for b.
>
> Proof. Suppose for contradiction no correct node cast its notarization
> vote for b. Since byzantine nodes possess less than 20% of stake,
> every correct node observed less than 20% of stake voting to notarize
> b. Both sub-conditions for emitting the event SafeToNotar(s,hash(b))
> by Definition 16 require observ-ing 20% of stake voting to notarize b.
> Therefore, no correct node emitted SafeToNotar(s,hash(b)). In
> Algorithm 1, emitting SafeToNotar(s,hash(b)) is the only trigger that
> might lead to casting a notar-fallback vote for b. There-fore, no
> correct node cast a notar-fallback vote for b. However, at least 60%
>
> 30
>
> of stake has to cast a notarization or notar-fallback vote for b for a
> certificate to exist (Definition 11), leading to a contradiction.
>
> Lemma 28. If a correct node v cast the notarization vote for block b
> in slot s = slot(b), then for every slot s′ ≤ s such that s′ ∈
> windowSlots(s), v cast the notarization vote for the ancestor b′ of b
> in slot s′ = slot(b′).
>
> Proof. If s is the first slot of the leader window, there are no slots
> s′ \< s in the same window. Since v voted for b in s we are done.
> Suppose s is not the first slot of the window.
>
> Due to the condition in line 11 of Algorithm 2, v had to evaluate the
> lat-ter leg of the condition (namely (not firstSlot and
> VotedNotar(hashparent) ∈ state\[s−1\]))to true
> tocastanotarizationvotefor b. Theobject VotedNotar(hash) is added to
> the state of slot s−1 only when casting a notarization vote on a block
> with the given hash in line 13. By induction, v cast notarization
> votes for ancestors of b in all slots s′ \< s in the same leader
> window.
>
> Lemma 29. Suppose a correct node v cast a notar-fallback vote for a
> block b in slot s that is not the first slot of the window, and b′ is
> the parent of b. Then, either some correct node cast a notar-fallback
> vote for b′, or correct nodes with more than 40% of stake cast
> notarization votes for b′.
>
> Proof. SafeToNotar conditions (Definition 16) require that v observed
> a nota-rization or notar-fallback certificate for b′, and so nodes
> with at least 60% of stake cast notarization or notar-fallback votes
> for b′. Since byzantine nodes possess less than 20% of stake, either
> correct nodes with more than 40% of stake cast notarization votes for
> b′, or some correct node cast a notar-fallback vote for b′.
>
> Lemma 30. Suppose a block b in slot s is notarized or
> notarized-fallback. Then, for every slot s′ ≤ s such that s′ ∈
> windowSlots(s), there is an ancestor b′ of b in slot s′. Moreover,
> either correct nodes with more than 40% of stake cast notarization
> votes for b′, or some correct node cast a notar-fallback vote for b′.
>
> Proof. By Lemma 27, some correct node voted for b. By Lemma 28, for
> every slot s′ ≤ s such that s′ ∈ windowSlots(s), there is an ancestor
> b′ of b in slot s′.
>
> Let b′ be the parent of b in slot s − 1. Suppose correct nodes with
> more than 40% of stake cast notarization votes for b′. Then, the
> result follows by Lemma 28 applied to each of these nodes.
>
> Otherwise, by Lemma 29, either some correct node cast a notar-fallback
> vote for b′, or correct nodes with more than 40% of stake cast
> notarization votes for b′. By induction, the result follows for all
> ancestors of b in the same leader window.
>
> 31
>
> Lemma 31. Suppose some correct node finalizes a block bi and bk is a
> block in the same leader window with slot(bi) ≤ slot(bk). If any
> correct node observes a notarization or notar-fallback certificate for
> bk, bk is a descendant of bi.
>
> Proof. Suppose bk is not a descendant of bi. By Lemmas 21 and 26,
> slot(bi) = slot(bk). Therefore, slot(bi) \< slot(bk) and bk is not in
> the first slot of the leader window. By Lemmas 27 and 25, some correct
> node v cast a notarization vote for bk. By Lemma 28, there is an
> ancestor of bk in every slot s′ \< slot(bk) in the same leader window.
>
> Let bj be the ancestor of bk in slot slot(bi) + 1. bk is not a
> descendant of
>
> bi, so the parent bi of bj in the same slot as bi is different from
> bi.
>
> By Lemma 30, either correct nodes with more than 40% of stake cast
>
> notarization votes for bj, or some correct node cast a notar-fallback
> vote for bj. If a correct node cast a notar-fallback vote for bj, by
> Definition 16, the parent bi of bj in the same slot as bi is
> notarized, or notarized-fallback. That would be a contradiction with
> Lemma 21 or 26. Otherwise, if correct nodes
>
> withmorethan40%ofstakecastnotarizationvotesfor bj, byLemma28, these
> nodes also cast notarization votes for bi, a contradiction with Lemma
> 23.
>
> Lemma 32. Suppose some correct node finalizes a block bi and bk is a
> block in a different leader window such that slot(bi) \< slot(bk). If
> any correct node observes a notarization or notar-fallback certificate
> for bk, bk is a descendant of bi.
>
> Proof. Let bj be the highest ancestor of bk such that slot(bi) ≤
> slot(bj) and bj is notarized or notarized-fallback. If bj is in the
> same leader window as bi, we are done by Lemma 31; assume bj is not in
> the same leader win-dow as bi. By Lemmas 27 and 28, some correct node
> v cast a notariza-tion vote for an ancestor bj of bj in the first slot
> s of the same leader win-dow. Due to the condition in line 11 of
> Algorithm 2, v had to evaluate
>
> the former leg of the condition (namely firstSlot and
> ParentReady(hash(b)) ∈ state\[s\]) to true (with s = slot(b′ )) to
> cast a notarization vote for bj, where b is the parent of bj.
> ParentReady(hash(b)) is added to state\[s\] only when
> ParentReady(s,hash(b)) is emitted. Note that by Definition 15, if a
> correct
>
> node has emitted ParentReady(s,hash(b)), then b is notarized or
> notarized-fallback. If slot(b) \< slot(bi), by Definition 15 Pool
> holds a skip certificate for slot(bi), contradicting Lemma 21 or 26.
> If slot(b) = slot(bi), since b is notarized or notarized-fallback,
> again Lemma 21 or 26 is violated. Due to choice of bj, slot(bi) \<
> slot(b) is also impossible.
>
> Theorem 1 (safety). If any correct node finalizes a block b in slot s
> and any correct node finalizes any block b′ in any slot s′ ≥ s, b′ is
> a descendant of b.
>
> Proof. By Lemma 25, b′ is also notarized. By Lemmas 31 and 32, b′ is a
> descendant of b.
>
> 32
>
> 2.10 Liveness
>
> Lemma 33. If a correct node emits the event ParentReady(s,...), then
> for every slot k in the leader window beginning with s the node will
> emit the event Timeout(k).
>
> Proof. The handler of event ParentReady(s,...) in line 12 of Algorithm
> 1 calls the function setTimeouts(s) which schedules the event
> Timeout(k) for every slot k of the leader window containing s (i.e., k
> ∈ windowSlots(s)).
>
> If a node scheduled the event Timeout(k), we say that it set the
> timeout for slot k.
>
> Since the function setTimeouts(s) is called only in the handler of the
> event ParentReady(s,...) in Algorithm 1, we can state the following
> corollary:
>
> Corollary 34. If a node sets a timeout for slot s, the node emitted an
> event ParentReady(s′,hash(b)), where s′ is the first slot of the
> leader window windowSlots(s).
>
> Lemma 35. If all correct nodes set the timeout for slot s, all correct
> nodes will cast a notarization vote or skip vote in slot s.
>
> Proof. Foranycorrectnodethatsetthetimeoutforslot s, thehandlerofevent
> Timeout(s) in line 6 of Algorithm 1 will call the function
> trySkipWindow(s), unless Voted ∈ state\[s\]. Next, either Voted ∈
> state\[s\] in line 24 of Algorithm 2, and the node casts a skip vote
> in slot s, or Voted ∈ state\[s\]. The object Voted is added to
> state\[s\] only when the node cast a notarization or skip vote in slot
> s, and therefore the node must have cast either vote.
>
> Lemma 36. If no set of correct nodes with more than 40% of stake cast
> their notarization votes for the same block in slot s, no correct node
> will add the object ItsOver to state\[s\].
>
> Proof. Object ItsOver is only added to state\[s\] in line 21 of
> Algorithm 2 after testingthat BlockNotarized(hash(b)) ∈ state\[s\].
> Theobject BlockNotarized(hash(b)) is only added to state\[s\] when the
> event BlockNotarized(s,hash(b)) is handled
>
> in Algorithm 1. By Definition 15, Pool needs to hold a notarization
> certificate for b to emit the event. The certificate requires that 60%
> of stake voted to notarize b (Def. 11). Since we assume that byzantine
> nodes hold less than 20% of stake, correct nodes with more than 40% of
> stake need to cast their notarization votes for the same block in slot
> s for any correct node to add the object ItsOver to state\[s\].
>
> Lemma 37. If all correct nodes set the timeout for slot s, either the
> skip certificate for s is eventually observed by all correct nodes, or
> correct nodes with more than 40% of stake cast notarization votes for
> the same block in slot s.
>
> 33
>
> Proof. Suppose no set of correct nodes with more than 40% of stake
> cast their notarization votes for the same block in slot s.
>
> Since all correct nodes set the timeout for slot s, by Lemma 35, all
> correct nodes will observe skip votes or notarization votes in slot s
> from a set S of correct nodes with at least 80% of stake (Assumption
> 1).
>
> Consider any correct node v ∈ S. As in Definition 16, by notar(b)
> denote the cumulative stake of nodes whose notarization votes for
> block b in slot s = slot(b) are in v’s Pool, and by skip(s) denote the
> cumulative stake of nodes whose skip votes for slot s are in Pool of
> v. Let w be the stake of nodes outside of S whose notarization or skip
> vote v observed. Then, after v received votes of nodes in S: skip(s) +
> notar(b) = 80% + w. Since no set of correct nodes with more than 40%
> of stake cast their notarization votes for the same block in slot s,
> maxb notar(b) ≤ 40%+ w. Therefore,
>
> X
>
> skip(s)+ notar(b)−maxnotar(b) = b b
>
> 80%+ w −maxnotar(b) ≥ b
>
> 80%+ w −(40%+ w) = 40%.
>
> Therefore, if v hasnotcastaskipvotefor s, v willemittheevent
> SafeToSkip(s). By Lemma 36, v will test that ItsOver ∈ state\[s\] in
> line 23 of Algorithm 1, and cast a skip-fallback vote for s.
>
> Therefore, all correct node will cast a skip or skip-fallback vote for
> s and observe a skip certificate for s.
>
> Lemma 38. If correct nodes with more than 40% of stake cast
> notarization votes for block b, all correct nodes will observe a
> notar-fallback certificate for b.
>
> Proof. Reason by induction on the difference between slot(b) and the
> first slot in windowSlots(slot(b)).
>
> Suppose slot(b) is the first slot in the window. Suppose for
> contradiction some correct node v will not cast a notarization or
> notar-fallback vote for b. Since v will observe the notarization votes
> of correct nodes with more than 40% of stake, by Definition 16 v will
> emit SafeToNotar(slot(b),hash(b)).
>
> The object ItsOver is added to state\[slot(b)\] in line 21 of
> Algorithm 2 after casting a finalization vote. The condition in line
> 19 ensures that v cast a notarization vote for a notarized block b′.
> However, by Lemma 23, there can be no such b′ = b in the same slot,
> and v has not cast the notarization vote for b.
>
> When triggered by SafeToNotar(slot(b),hash(b)), v will test that
> ItsOver ∈ state\[s\] in line 18 and cast the notar-fallback vote for
> b, a contradiction.
>
> Therefore, all correct nodes will cast a notarization or
> notar-fallback vote for b, and observe a notar-fallback certificate
> for b.
>
> 34
>
> Next, suppose slot(b) is not the first slot in the window and assume
> the induction hypothesis holds for the previous slot.
>
> Suppose for contradiction some correct node v will not cast a
> notarization or notar-fallback vote for b. Since v will observe the
> notarization votes of correct nodes with more than 40% of stake, by
> Definition 16 v will retrieve block b and identify its parent b′. By
> Lemma 28, the correct nodes that cast notarization votes for b also
> voted for b′, and slot(b′) = slot(b) − 1. By induction hypothesis, v
> will observe a notar-fallback certificate for b′, and emit
> SafeToNotar(slot(b),hash(b)). Identically to the argument above, v
> will cast the notar-fallback vote for b, causing a contradiction.
>
> Therefore, all correct nodes will cast a notarization or
> notar-fallback vote for b, and observe a notar-fallback certificate
> for b.
>
> Lemma 39. If all correct nodes set the timeouts for slots of the
> leader window windowSlots(s), then for every slot s′ ∈ windowSlots(s)
> all correct nodes will observe a notar-fallback certificate for b in
> slot s′ = slot(b), or a skip certificate for s′.
>
> Proof. Ifcorrectnodesobserveskipcertificatesinallslots s′ ∈
> windowSlots(s), we are done. Otherwise, let s′ ∈ windowSlots(s) be any
> slot for which a correct node will not observe a skip certificate. By
> Lemma 37, there is a block
>
> b in slot s′ = slot(b) such that correct nodes with more than 40% of
> stake cast the notarization vote for b. By Lemma 38, correct nodes
> will observe a notar-fallback certificate for b.
>
> Lemma 40. If all correct nodes set the timeouts for slots
> windowSlots(s), then all correct nodes will emit the event
> ParentReady(s+,...), where s+ \> s is the first slot of the following
> leader window.
>
> Proof. Consider two cases:
>
> \(i\) allcorrectnodesobserveskipcertificatesforallslotsin
> windowSlots(s);
>
> \(ii\) some correct node does not observe a skip certificate for some
> slot s′ ∈ windowSlots(s).
>
> \(i\) Consider some correct node v. By Corollary 34, v had emitted an
> event ParentReady(k,hash(b)), where k is the first slot of
> windowSlots(s). By Definition 15, there is a block b, such that v
> observed a notar-fallback certificate for b, and skip certificates for
> all slots i such that slot(b) \< i \< k. Since v will observe skip
> certificates for all slots in windowSlots(s), v will observe skip
> certificates for all slots i such that slot(b) \< i \< s+. By 15, v
>
> will emit ParentReady(s+,hash(b).
>
> \(ii\) Let s′ be the highest slot in windowSlots(s) for which some
> correct
>
> node v will not observe a skip certificate. By Lemma 39, v will
> observe a notar-fallback certificate for some block b in slot s′ =
> slot(b). By definition of
>
> 35
>
> s′, v will observe skip certificates for all slots i such that slot(b)
> \< i \< s+. By 15, v will emit ParentReady(s+,hash(b).
>
> Lemma 41. All correct nodes will set the timeouts for all slots.
>
> Proof. Follows by induction from Lemma 33 and Lemma 40.
>
> Lemma 42. Suppose it is after GST and the first correct node v set the
> timeout for the first slot s of a leader window windowSlots(s) at time
> t. Then, all correct nodes will emit some event ParentReady(s,hash(b))
> and set timeouts for slots in windowSlots(s) by time t+∆.
>
> Proof. By Corollary 34 and Definition 15, v observed a notar-fallback
> certifi-cate for some block b and skip certificates for all slots i
> such that slot(b) \< i \< s by time t. Since v is correct, it
> broadcast the certificates, which were also observed by all correct
> nodes by time t+∆. Therefore, all correct nodes emitted
> ParentReady(s,hash(b)) by time t + ∆ and set the timeouts for all
> slots in windowSlots(s).
>
> Theorem 2 (liveness). Let vℓ be a correct leader of a leader window
> be-ginning with slot s. Suppose no correct node set the timeouts for
> slots in windowSlots(s) before GST, and that Rotor is successful for
> all slots in windowSlots(s). Then, blocks produced by vℓ in all slots
> windowSlots(s) will be finalized by all correct nodes.
>
> Proof. The intuitive outline of the proof is as follows:
>
> \(1\) We calculate the time by which correct nodes receive blocks.
>
> \(2\) Suppose for contradiction some correct node v cast a skip vote.
> We argue that v cast a skip vote in every slot k′ ≥ k, k′ ∈
> windowSlots(s).
>
> \(3\) We consider different causes for the first skip vote cast by v.
> We determine that some Timeout(j) resulted in casting a skip vote by v
> before any SafeToNotar or SafeToSkip is emitted in the window.
>
> \(4\) We argue that Timeout(k) can only be emitted after v has already
> received a block and cast a notarization vote in slot k, a
> contradiction.
>
> \(1\) By Lemma 41, all correct nodes will set the timeouts for s. Let
> t be the time at which the first correct node sets the timeout for s.
> Since t ≥ GST, by Lemma 42, vℓ emitted ParentReady(s,hash(b)) for some
> b and added ParentReady(hash(b)) to state\[s\] in line 13 of Algorithm
> 1 by time t+∆. Con-ditions in lines 1 and 4 of Algorithm 3 imply that
> after ParentReady(hash(b)) ∈ state\[s\], vℓ proceeded to line 10 by
> time t+∆. According to lines 11 and 16, vℓ will finish transmission of
> a block bk in slot k ∈ windowSlots(s) by time t+∆+(k−s+1)·∆block.
> SinceRotorissuccessfulforslotsin windowSlots(s),
>
> 36
>
> correct nodes will receive the block in slot k ∈ windowSlots(s) by
> time t+3∆+(k −s+1) ·∆block.
>
> \(2\) Suppose for contradiction, some correct node v will not cast a
> nota-rization vote for some bk, and let k be the lowest such slot.
> Since vℓ is correct, the only valid block received by any party in
> slot k is bk, and v cannot cast a different notarization vote in slot
> k. By Lemma 35, v will cast a skip vote in slot k. Moreover, v cannot
> cast a notarization vote in any slot k′ \> k in the leader window, due
> to the latter leg of the condition in line 11 of Algorithm 2
>
> (i.e. not firstSlot and VotedNotar(hashparent) ∈ state\[k′ − 1\]).
> Therefore, v cast a skip vote in every slot k′ ≥ k, k′ ∈
> windowSlots(s).
>
> \(3\) Skip votes in slot k are cast by trySkipWindow(j) in Algorithm
> 2, where j ∈ windowSlots(s). The function trySkipWindow(j) is called
> af-ter handling SafeToNotar(j,...), SafeToSkip(j), or Timeout(j) in
> Algorithm 1. Let j be the slot such that the first skip vote of v for
> a slot in windowSlots(s) resultedfromhandling SafeToNotar(j,...),
> SafeToSkip(j), or Timeout(j). Con-sider the following cases:
>
> • SafeToNotar(j,...): If j \< k, by definition of k, all correct nodes
> cast notarization votes for bj. Therefore, SafeToNotar(j,...) cannot
> be emit-ted by a correct node. Therefore, j ≥ k. SafeToNotar(j,...)
> requires v to cast a skip vote in slot j first. Therefore, v cast a
> skip vote for slot j before emitting SafeToNotar(j,...), a
> contradiction.
>
> • SafeToSkip(j): Similarly to SafeToNotar, the event cannot be emitted
> by a correct node for j \< k, and requires that v cast some skip vote
> for slot j ≥ k before it is emitted, a contradiction.
>
> • Timeout(j): Due to the condition when handling the event in line 6
> of Algorithm 1, the event does not have any effect if v cast a
> notarization vote in slot j. Moreover, v cannot cast a notarization
> vote in slot j if Timeout(j) was emitted beforehand. Since v cast
> notarization votes in slots of the window lower than k, then j ≥ k.
> Since the event Timeout(j) is scheduled at a higher time for a higher
> slot in line 5 of Algorithm 2, the time at which Timeout(k) is emitted
> is the earliest possible time at which v cast the first skip vote in
> the window.
>
> \(4\) Since t is the time at which the first correct node set the
> timeout for slot s, v emitted Timeout(k) at time t′ ≥ t + ∆timeout +
> (k − s + 1) · ∆block ≥ t + 3∆ + (k − s + 1) · ∆block. However, as
> calculated above, v has received bi for all s ≤ i ≤ k by that time.
> Analogously to Lemma 42, v has also emitted ParentReady(s,hash(b)) and
> added ParentReady(hash(b)) to state\[s\], where b is the parent of bs.
> The condition in line 11 is satisfied when v calls
> tryNotar(Block(s,hash(bs),hash(b))), and v cast a notarization vote
> for bs. Since checkPendingBlocks() is called in lines 3 and 14 of
> Algorithm 1 when handling Block and ParentReady events, v cast a
> notarization vote for bi for all s ≤ i ≤ k by the time Timeout(k) is
> emitted, irrespectively of the
>
> 37
>
> order in which bi were received. This contradicts the choice of v as a
> node that did not cast a notarization vote for bk.
>
> Since for all k ∈ windowSlots(s) all correct nodes cast notarization
> votes for bk, all correct nodes will observe the fast-finalization
> certificate for bk and finalize bk.
>
> 2.11 Higher Crash Resilience
>
> In this section we sketch the intuition behind Alpenglow’s correctness
> in less adversarial network conditions, but with more crash faults.
>
> In harsh network conditions Alpenglow can be attacked by an adversary
> with over 20% of stake. However, such an attack requires careful
> orchestra-tion. Unintentional mistakes, crash faults and
> denial-of-service attacks (which are functionally akin to crash
> faults) have historically caused more problems for blockchain systems.
> In the rest of this section, we will consider Assump-tion 2 instead of
> Assumption 1. Additionally, Assumption 3 captures on a high level the
> attacker’s lesser control over the network.
>
> Assumption 3 (Rotor non-equivocation). If a correct node receives a
> full block b via Rotor (Section 2.2), any other correct node that
> receives a full block via Rotor for the same slot, receives the same
> block b.
>
> Note that crashed nodes are functionally equivalent to nodes
> exhibiting indefinite network delay. In Section 2.9 we have
> demonstrated that Alpenglow is safe with arbitrarily large network
> delays, which are possible in our model. Therefore, safety is ensured
> under Assumption 2.
>
> The reasoning behind liveness (Section 2.10) is affected by Assumption
> 2 whenever we argue that correct nodes will observe enough votes to
> trigger the conditions of Definition 16 (SafeToNotar and SafeToSkip).
> However, with the additional Assumption 3 that two correct nodes
> cannot reconstruct a different block in the same slot, either
> SafeToNotar or SafeToSkip has to be emitted by all correct nodes after
> they observe the votes of other correct nodes. If correct nodes with
> at least 20% of stake voted to notarize a block, then the condition:
>
> skip(s)+ notar(b) ≥ 60% and notar(b) ≥ 20%
>
> will be satisfied after votes of all correct nodes are observed.
> Otherwise,
>
> X
>
> skip(s)+ notar(b)−maxnotar(b) ≥ skip(s) ≥ 40% b b
>
> will be satisfied.
>
> Corollary 43. Theorem 2 holds under Assumptions 2 and 3 instead of
> As-sumption 1.
>
> 38
>
> Note that if the leader is correct or crashed, Assumption 3 is never
> vi-olated, as the leader would produce at most one block per slot.
> Therefore, crash-only faults amounting to less than 40% of stake are
> always tolerated.
>
> To conclude, we intuitively sketch the conditions in which Assumption
> 3 can be violated by an adversary distributing different blocks to
> different par-ties. If there are also many crash nodes in this
> scenario, correct nodes might not observe enough votes to emit
> SafeToNotar or SafeToSkip, and the protocol could get stuck.
>
> Suppose a malicious leader attempts to distribute two different blocks
> b and b′ such that some correct nodes reconstruct and vote for b,
> while other correct nodes reconstruct and vote for b′. If a correct
> node receives two shreds not belonging to the same block (having a
> different Merkle root for the same slice index) before being able to
> reconstruct the block, the node will not vote for the block.
> Therefore, network topology and sampling of Rotor relays determines
> the feasibility of distributing two different blocks to different
> correct nodes.
>
> Example 44. Consider two clusters of correct nodes A and B, such that
> the network latency within a cluster is negligible in relation to the
> network latency between A and B. Each A and B are comprised of nodes
> with 31% of stake. The adversary controls 18% of stake, and 20% of
> stake is crashed. The Rotor relays in A receive shreds for a block bA
> from a malicious leader, while Rotor relays in B receive shreds for a
> block bB. The Rotor relays controlled by the adversary forward shreds
> of bA to A, and shreds of bB to B. Due to the delay between A and B,
> nodes in A will reconstruct bA before observing any shred of bB.
> Similarly for B and bB. Assumption 3 is violated in this scenario.
>
> If the network topology has uniformly distributed nodes, it is harder
> to arrange for large groups to receive enough shreds of a slice of b
> before receiving any shreds of a corresponding slice of b′.
>
> 3 Beyond Consensus
>
> This section describes a few issues that are not directly in the core
> of the consensus protocol but deserve attention. We start with three
> issues (sampling, rewards, execution) closely related to consensus,
> then we move on to advanced failure handling, and we finish the
> section with bandwidth and latency simulation measurement results.
>
> 39
>
> 3.1 Smart Sampling
>
> To improve resilience of Rotor in practice, we use a novel committee
> sampling scheme. It is inspired by FA1 \[GKR23\] and improves upon
> FA1-IID. It takes the idea of reducing variance in the sampling
> further.
>
> Definition 45. Given a number of bins k and relative stakes 0 \<
> ρ1,...,ρn \< 1. A partitioning of these stakes is a mapping
>
> p : {1,...,k}×{1,...,n} → \[0,1\]R,
>
> such that:
>
> • stakes are fully assigned, i.e., ∀v ∈ {1,...,n} : Pb∈{1,...,k}
> p(b,v) = ρv,
>
> • bins are filled entirely, i.e., ∀b ∈ {1,...,k} : Pv∈{1,...,n} p(b,v)
> = 1/k.
>
> A procedure that for any number of bins k and relative stakes
> ρ1,...,ρn cal-culates a valid partitioning is called a partitioning
> algorithm.
>
> Definition 46. Our committee sampling scheme, called partition
> sampling or PS-P, is instantiated with a specific partitioning
> algorithm P. It then proceeds as follows to generate a single set of Γ
> samples:
>
> 1\. For each node with relative stake ρi \> 1/Γ, fill ⌊ρiΓ⌋ bins with
> that node. The remaining stake is ρ′ = ρi − ⌊ρiΓ⌋ \< 1/Γ. For all
> other nodes, the remaining stake is their original stake: ρi = ρi
>
> 2\. Calculate a partitioning for stakes ρ′ ,...,ρ′ into the remaining
> k = Γ− i∈\[n\]⌊ρiΓ⌋ bins according to P.
>
> 3\. From each bin, sample one node proportional to their stake.
>
> One simple example for a partitioning algorithm randomly orders nodes,
> and make cuts exactly after every 1/k relative stake. PS-P
> instantiated with this simple partitioning algorithm is already better
> than the published state of the art \[GKR23\]. However, this topic
> deserves more research.
>
> Next, we show that PS-P improves upon IID and FA1-IID. Let A denote
> the adversary and ρA the total stake they control, possibly spread
> over many nodes. Further, assume ρA \< γ/Γ = 1/κ and therefore γ \<
> ρAΓ.
>
> Lemma 47. For any stake distribution with ρi \< 1/Γ for all i ∈
> {1,...,n}, any partitioning algorithm P, adversary A being sampled at
> least γ times in PS-P is at most as likely as likely as in IID
> stake-weighted sampling.
>
> Proof. For any partitioning, in step 3 of Definition 46, the number of
> sam-ples for the adversary is Poisson binomial distributed, i.e., it
> is the number
>
> 40
>
> of successes in Γ independent Bernoulli trials (possibly with
> different prob-abilities). The success probability of each trial is
> the proportion of stake in each bin the adversary controls. Consider
> the case where A achieves to be packed equally in all Γ bins. In that
> case, the number of samples from the adversary follows the Binomial
> distribution with p = ρA. This is the same as for IID stake-weighted
> sampling. Also, the Binomial case is also known to be maximizing the
> variance for Poisson binomial distributions \[Hoe56\], thus maximizing
> the probability for the adversary to get sampled at least γ \< Γ
> times.
>
> Theorem 3. For any stake distribution, adversary A being sampled at
> least γ times in PS-P is at most as likely as in FA1-IID.
>
> Proof. Because of step 1 of in Definition 46, applying our scheme
> directly is equivalent to using FA1 with our scheme as the fallback
> scheme it is instan-tiated with. Therefore, together with Lemma 47,
> the statement follows.
>
> Finally, we practically analyze how this sampling scheme compares to
> regular stake-weighted IID sampling and FA1-IID on the current Solana
> stake distribution.
>
> Crashes (γ = 32,Γ = 64) 100
>
> 10−4
>
> 10−8
>
> 10−12
>
> 40% 30% 20% Crashed nodes (by stake)
>
> 40% Crashes (κ = 2) 100
>
> 10−4
>
> 10−8

10−12

> 64 128 256 Total shreds (Γ)
>
> Figure 9: Probabilities that Rotor is not successful when experiencing
> crash failures, when instantiated with PS-P (with fully randomized
> partitioning) compared to other sampling techniques. This assumes 64
> slices per block (Rotor is only successful for the block if it is
> successful for every slice).
>
> 41
>
> 3.2 Voting vs. Execution
>
> In Section 2, we omitted the execution of the blocks and the
> transactions therein. Currently, Solana uses the synchronous execution
> model described below.
>
> Eager (Synchronous) Execution. The leader executes the block before
> sending it, and all nodes execute the block before voting for it. With
> the slices being pipelined (the next slice is propagated while the
> previous slice is executed), this may add some time to the critical
> path, since we need to execute the last slice before we can send a
> notarization vote for the block.
>
> Lazy (Asynchronous) Execution. We can also vote on a block before
> executing it. We need to make sure that the Compute Units (CUs)
> reflect actual execution costs. This way the CU bounds on transactions
> and the whole block guarantee that blocks are executed timely. If CUs
> are unrealis-tically optimistic, this cannot work since execution
> delays may grow without bounds.
>
> Distributed Execution. Another active area of research is distributed
> ex-ecution, which is related to this discussion about execution model.
> In dis-tributed execution validators use multiple machines (co-located
> for minimal latency) for executing transactions. Ideally, in contrast
> to executions on a single machine, this allows the system to scale to
> higher transaction through-puts. It also allows nodes to respond to
> surges in trafic without always over-provisioning (this is called
> elasticity). Examples of this line of research are Pilotfish
> \[Kni+25\] and Stingray \[SSK25\].
>
> 3.3 Asynchrony in Practice
>
> In our model assumptions of Section 1.5 we assumed that delayed
> mes-sages are eventually delivered. While this is a standard model in
> distributed computing, in reality (as well as in the original
> formulation of partial syn-chrony with GST \[DLS88\]) messages might
> be lost. Note that we already allow asynchrony (arbitrarily long
> message delays), so our protocol is safe even if messages are dropped.
> In this section we discuss two mechanisms en-hancing Alpenglow to
> address network reality in practice, to restore liveness if the
> protocol makes no progress.
>
> Joining. Nodes might go ofline for a period of time and miss all of
> the messages delivered during that time. We note that if a rebooting
> or newly joining node observes a finalization of block b in slot s, it
> is not necessary to observe any vote or certificate messages for
> earlier slots. Due to safety (Theorem 1), any future block in a slot
> s′ ≥ s that might be finalized will be a descendant of b, and if any
> correct node emits the event ParentReady(s′,b′),
>
> 42
>
> b′ has to be a descendant of b.
>
> Rebooting or joining nodes need to observe a fast-finalization
> certificate for a block b in slot s, or a finalization certificate for
> s together with a notarization certificate for b in the same slot s.
> Block b can be retrieved with Repair Section 2.8. The parent of b can
> be identified and retrieved after b is stored, and so on. A practical
> implementation might retrieve any missing blocks for all slots in
> parallel, before verifying and repairing all ancestors of b.
>
> Standstill. Eventual delivery of messages needs to be ensured to
> guarantee liveness after GST. As noted above, if a correct node
> observes a finalization in slot s, no vote or certificate messages for
> slots earlier than s are needed for liveness. Lack of liveness can be
> detected simply by observing a period of time without new slots being
> finalized. After some parametrized amount of time, e.g., ∆standstill ≈
> 10 sec in which the highest finalized slot stays the same, correct
> nodes trigger a re-transmission routine. Then, nodes broadcast a
> finalization certificate for the highest slot observed (either a
> fast-finalization certificate for a block b in slot s, or a
> finalization certificate for s together with a notarization
> certificate for b in the same slot s). Moreover, for all higher slots
> s′ \> s, nodes broadcast observed certificates and own votes cast in
> these slots.
>
> 3.4 Dynamic Timeouts
>
> Alpenglow is defined in the partially synchronous model, but strictly
> speaking, epochs deviate from partial synchrony. For epoch changes to
> work, at least one block needs to be finalized in each epoch. A
> finalized block in epoch e makes sure that the previous epoch e−1
> ended with an agreed-upon state. This is important for setting the
> stage of epoch e + 1, i.e., to make sure that there is agreement on
> the nodes and their stake at the beginning of epoch e+1.
>
> Our solution is to extend timeouts if the situation looks dire. More
> precisely, if a node does not have a finalized block in ∆standstill ≈
> 10 sec of consecutive leader windows, the node will start extending
> its timeouts by ε ≈ 5% in every leader window.
>
> Note that the nodes do not need coordination in extending the
> timeouts. As soon as nodes see finalized blocks again, they can return
> to the standard timeouts immediately as described in Section 2.6. Also
> when returning to normal timeouts, no agreement or coordination is
> needed, and some nodes can still have longer timeouts without
> jeopardizing the correctness of the system.
>
> Increasing timeouts by ε ≈ 5% in every leader window results in
> expo-nential growth. With exponential growth, timeouts quickly become
> longer than any extraordinary network delay caused by any
> network/power disaster. Therefore, it can be guaranteed that we have a
> finalized slot in each epoch.
>
> 43
>
> 3.5 Protocol Parameters
>
> Throughout the document we have introduced various parameters. Ta-ble
> 10 shows how we set the parameters in our preliminary simulations.
> Test-ing is needed to ultimately decide these parameters.
>
> Some parameters are set implicitly, and will be different in every
> epoch. This includes in particular the parameter for the number of
> nodes n. Through-out this paper we used n ≈ 1,500 for the number of
> nodes. The reality at the time of writing is closer to n ≈ 1,300.

||
||
||
||
||
||
||
||
||
||

> Table 10: Protocol Parameters.
>
> 3.6 Bandwidth
>
> In this section we analyze the bandwidth usage of Alpenglow. Table 11
> lists the size of Votor-related messages. As a bandwidth optimization,
> only one of the finalization certificates should be broadcast
> (whichever is observed first). Then, in the common case, every node
> broadcasts a notarization vote, finalization vote, notarization
> certificate and one of the finalization certificates for every slot.
> If we account for the larger of the finalization certificates
> (fast-finalization), for n = 1,500, a node transmits (196 + 384 +
> 384 + 164) · 1,500 bytes for every 400 ms slot, which corresponds to
> 32.27 Mbit/s. The total
>
> 44
>
> outgoing bandwidth is plotted in Figure 12.
>
> Table 11: Estimation of message sizes in bytes for a network comprised
> of 1,500 nodes.
>
> Up-Bandwidth Usage Histogram for 500 Mbps Goodput
>
> 104
>
> 103
>
> 102
>
> 101
>
> 0 200 400 600 800 1,000 1,200 Validators (from small to large)
>
> Figure 12: Bandwidth usage to achieve consistent goodput of 500 Mbps,
> i.e., where the leader role requires sending at 1 Gbps for κ = 2.
>
> 45
>
> 3.7 Latency
>
> We simulated Alpenglow in a realistic environment. In particular, in
> our simulation, the stake distribution is the same as Solana’s stake
> distribution at the time of writing (epoch 780), and the latencies
> between nodes correspond to real-world latency measurements. Some
> possible time delays are not included in the simulation, in particular
> block execution time. Moreover, a different stake distribution would
> change our results.
>
> Figure 13 shows a latency histogram for the case when the block leader
> is located in Zurich, Switzerland, our location at the time of
> writing. The leader is fixed in Zurich, and each bar shows the average
> over 100,000 simulated executions. The Rotor relays are chosen
> randomly, according to stake. We plot simulated latencies to reach
> different stages of the Alpenglow protocol against the fraction of the
> network that arrived at that stage.
>
> • The green bars show the network latency. With the current node
> distri-bution of Solana, about 65% of Solana’s stake is within 50 ms
> network latency round-trip time) of Zurich. The long tail of stake has
> more than 200 ms network latency from Zurich. The network latency
> serves as a natural lower bound for our plot, e.g., if a node is 100
> ms from Zurich, then any protocol needs at least 100 ms to finalize a
> block at that node.
>
> • The yellow bars show the delay incurred by Rotor, the first stage of
> our protocol. More precisely, the yellow bars show when the nodes
> received γ shreds, enough to reconstruct a slice.
>
> • The red bars mark the point in time when a node has received
> nota-rization votes from at least 60% of the stake.
>
> • Finally, the blue bars show the actual finalization time. A node can
> finalize because they construct a fast-finalization certificate
> (having re-ceived 80% stake of the original notarization votes), or a
> finalization certificate (having received 60% of the finalization
> votes), or having received one of these certificates from a third
> party, whatever is first.
>
> 46
>
> Alpenglow Latency Histogram for Leader in Zurich 300
>
> 250
>
> 200
>
> 150
>
> 100
>
> 50
>
> 0
>
> 0 20 40 60 80 100 Validators reached \[% of stake\]
>
> Figure 13: For a fixed leader in Zurich with random relays we have:
> (i) the last node in the network finalizes in less than 270 ms, (ii)
> the median node finalizes almost as fast as the fastest ones, in
> roughly 115 ms.
>
> 300
>
> 250
>
> 200
>
> Alpenglow Latency Histogram for Random Leaders

Finalization

Notarization

Rotor

Network latency

> 150
>
> 100
>
> 50
>
> 0
>
> 0 20 40 60 80 100 Validators reached \[% of stake\]
>
> Figure 14: This plot is a generalized version of Figure 13, where the
> leader is chosen randomly according to stake. While Zurich is not “the
> center of the Solana universe,” it is more central than the average
> leader. Hence the numbers in this plot are a bit higher than in Figure
> 13, and the median finalization time is roughly 150 ms.
>
> 47
>
> Thanks. We thank the following people for their input: Ittai Abraham,
> Zeta Avarikioti, Emanuele Cesena, Igor Durovic, Yuval Efron, Pranav
> Garimidi, Sam Kim, Charlie Li, Carl Lin, Julian Loss, Zarko Milosevic,
> Gabriela Moreira, Karthik Narayan, Joachim Neu, Alexander Pyattaev,
> Ling Ren, Max Resnick, Tim Roughgarden, Ashwin Sekar, Victor Shoup,
> Philip Taffet, Yann Vonlan-then, Marko Vukoli´c, Josef Widder, Wen Xu,
> Anatoly Yakovenko, Haoran Yi, Yunhao Zhang.
>
> References
>
> \[Abr+21\]
>
> \[Abr+17\]
>
> \[Aru+24\]
>
> \[Aru+25\]
>
> \[Bab+25\]
>
> \[Bon+03\]
>
> \[BKM18\]
>
> \[CT05\]
>
> \[CL99\]

IttaiAbraham,KartikNayak,LingRen,andZhuolunXiang.“Good-case Latency of
Byzantine Broadcast: A Complete Categorization”. In: Proceedings of the
ACM Symposium on Principles of Distributed Computing (PODC). 2021, pages
331–341.

Ittai Abraham et al. “Revisiting fast practical byzantine fault
tol-erance”. In: arXiv preprint arXiv:1712.01367 (2017).

Balaji Arun, Zekun Li, Florian Suri-Payer, Sourav Das, and
Alexan-derSpiegelman. Shoal++: High Throughput DAG-BFT Can Be Fast!
[https://decentralizedthoughts.github.io/2024-06-12-shoalpp/.](https://decentralizedthoughts.github.io/2024-06-12-shoalpp/)
2024.

Balaji Arun, Zekun Li, Florian Suri-Payer, Sourav Das, and Alexan-der
Spiegelman. “Shoal++: High Throughput DAG BFT Can Be Fast and Robust!”
In: 22nd USENIX Symposium on Networked Sys-tems Design and
Implementation (NSDI). 2025.

Kushal Babel et al. “Mysticeti: Reaching the Latency Limits with
Uncertified DAGs”. In: 32nd Annual Network and Distributed Sys-tem
Security Symposium (NDSS). The Internet Society, 2025.

Dan Boneh, Craig Gentry, Ben Lynn, and Hovav Shacham. “Ag-gregate and
verifiably encrypted signatures from bilinear maps”. In: Advances in
Cryptology (Eurocrypt), Warsaw, Poland. Springer. 2003, pages 416–432.

Ethan Buchman, Jae Kwon, and Zarko Milosevic. The latest gossip on BFT
consensus. arXiv:1807.04938,
[http://arxiv.org/abs/](http://arxiv.org/abs/1807.04938)
[1807.04938.](http://arxiv.org/abs/1807.04938) 2018.

Christian Cachin and Stefano Tessaro. “Asynchronous verifiable
in-formation dispersal”. In: 24th IEEE Symposium on Reliable
Dis-tributed Systems (SRDS). IEEE. 2005, pages 191–201.

Miguel Castro and Barbara Liskov. “Practical Byzantine Fault
Tol-erance”. In: Proceedings of the Third Symposium on Operating
Sys-tems Design and Implementation (OSDI). New Orleans, Louisiana, USA,
1999, pages 173–186.

> 48
>
> \[CP23\]
>
> \[Con+24\]
>
> \[Dan+22\]
>
> \[Dod02\]
>
> \[DGV04\]
>
> \[DLS88\]
>
> \[FMW24\]
>
> \[Fou19\]
>
> \[GKR23\]
>
> \[GV07\]
>
> \[Gue+19\]

Benjamin Y. Chan and Rafael Pass. “Simplex Consensus: A Simple and Fast
Consensus Protocol”. In: Theory of Cryptography (TCC), Taipei, Taiwan.
Taipei, Taiwan: Springer-Verlag, 2023, pages 452– 479.

Andrei Constantinescu, Diana Ghinea, Jakub Sliwinski, and Roger
Wattenhofer. “Brief Announcement: Unifying Partial Synchrony”. In: 38th
International Symposium on Distributed Computing (DISC). 2024.

GeorgeDanezis,LefterisKokoris-Kogias,AlbertoSonnino,andAlex-ander
Spiegelman. “Narwhal and Tusk: a DAG-based mempool and eficient BFT
consensus”. In: Proceedings of the Seventeenth Euro-pean Conference on
Computer Systems (EuroSys). 2022, pages 34– 50.

Yevgeniy Dodis. “Eficient construction of (distributed) verifiable
random functions”. In: Public Key Cryptography (PKC), Miami, FL, USA.
Springer. 2002, pages 1–17.

Partha Dutta, Rachid Guerraoui, and Marko Vukolic. The Complex-ity of
Asynchronous Byzantine Consensus.
[https://infoscience.](https://infoscience.epfl.ch/server/api/core/bitstreams/19ce5930-31af-4489-9551-d5d014b8c1f1/content)
[epfl.ch/server/api/core/bitstreams/19ce5930-31af-4489-9551-d5d014b8c1f1/content.](https://infoscience.epfl.ch/server/api/core/bitstreams/19ce5930-31af-4489-9551-d5d014b8c1f1/content)
2004.

Cynthia Dwork, Nancy A. Lynch, and Larry J. Stockmeyer. “Con-sensus in
the Presence of Partial Synchrony”. In: J. ACM 35.2 (1988), pages
288–323.

Austin Federa, Andrew McConnell, and Mateo Ward. DoubleZero Protocol.
[https://doublezero.xyz/whitepaper.pdf.](https://doublezero.xyz/whitepaper.pdf)
2024.

Solana Foundation. Turbine–Solana’s Block Propagation Protocol Solves
the Scalability Trilemma.
[https://solana.com/news/](https://solana.com/news/turbine---solana-s-block-propagation-protocol-solves-the-scalability-trilemma)
[turbine---solana-s-block-propagation-protocol-solves-the-scalability-trilemma.](https://solana.com/news/turbine---solana-s-block-propagation-protocol-solves-the-scalability-trilemma)
2019.

Peter Gazi, Aggelos Kiayias, and Alexander Russell. “Fait Accom-pli
Committee Selection: Improving the Size-Security Tradeoff of Stake-Based
Committees”. In: ACM SIGSAC Conference on Com-puter and Communications
Security (CCS), Copenhagen, Denmark. ACM, 2023, pages 845–858.

Rachid Guerraoui and Marko Vukoli´c. “Refined Quorum Systems”. In:
Proceedings of the 26th Annual ACM Aymposium on Principles of
Distributed Computing (PODC). 2007, pages 119–128.

Guy Golan Gueta et al. “SBFT: A scalable and decentralized trust
infrastructure”. In: 49th Annual IEEE/IFIP International Confer-ence on
Dependable Systems and Networks (DSN). 2019, pages 568– 580.

> 49
>
> \[Hoe56\]
>
> \[Kei+22\]
>
> \[Kni+25\]
>
> \[Kot+07\]
>
> \[Kur02\]
>
> \[KTZ21\]
>
> \[Lam03\]
>
> \[LNS25\]
>
> \[MA06\]
>
> \[Mer79\]
>
> \[MRV99\]
>
> \[Mil+16\]
>
> \[PSL80\]

Wassily Hoeffding. “On the distribution of the number of successes in
independent trials”. In: The Annals of Mathematical Statistics (1956),
pages 713–721.

Idit Keidar, Oded Naor, Ouri Poupko, and Ehud Shapiro. “Cor-dial miners:
Fast and eficient consensus for every eventuality”. In: arXiv:2205.09174
(2022).

Quentin Kniep, Lefteris Kokoris-Kogias, Alberto Sonnino, Igor
Za-blotchi, and Nuda Zhang. “Pilotfish: Distributed Execution for
Scal-able Blockchains”. In: Financial Cryptography and Data Security
(FC), Miyakojima, Japan. Apr. 2025.

Ramakrishna Kotla, Lorenzo Alvisi, Mike Dahlin, Allen Clement, and
Edmund Wong. “Zyzzyva: speculative byzantine fault toler-ance”. In:
Proceedings of 21st Symposium on Operating Systems Principles (SOSP).
2007, pages 45–58.

Klaus Kursawe. “Optimistic byzantine agreement”. In: 21st IEEE Symposium
on Reliable Distributed Systems (DSN). IEEE. 2002, pages 262–267.

Petr Kuznetsov, Andrei Tonkikh, and Yan X Zhang. “Revisiting Op-timal
Resilience of Fast Byzantine Consensus”. In: Proceedings of the ACM
Symposium on Principles of Distributed Computing (PODC). Virtual Event,
Italy, 2021, pages 343–353.

Leslie Lamport. “Lower Bounds for Asynchronous Consensus”. In: Future
Directions in Distributed Computing: Research and Position Papers. 2003,
pages 22–23.

Andrew Lewis-Pye, Kartik Nayak, and Nibesh Shrestha. The Pipes Model for
Latency and Throughput Analysis. Cryptology ePrint Ar-chive, Paper
2025/1116. 2025. url:
[https://eprint.iacr.org/](https://eprint.iacr.org/2025/1116)
[2025/1116.](https://eprint.iacr.org/2025/1116)

J-P Martin and Lorenzo Alvisi. “Fast byzantine consensus”. In: IEEE
Transactions on Dependable and Secure Computing (2006), pages 202–215.

Ralph Charles Merkle. Secrecy, Authentication, and Public Key Sys-tems.
Stanford University, 1979.

Silvio Micali, Michael Rabin, and Salil Vadhan. “Verifiable random
functions”. In: 40th Annual Symposium on Foundations of Com-puter
Science (FOCS). IEEE. 1999, pages 120–130.

Andrew Miller, Yu Xia, Kyle Croman, Elaine Shi, and Dawn Song. “The
Honey Badger of BFT Protocols”. In: Proceedings of the ACM SIGSAC
Conference on Computer and Communications Security (CCS). 2016, pages
31–42.

Marshall C. Pease, Robert E. Shostak, and Leslie Lamport. “Reach-ing
Agreement in the Presence of Faults”. In: J. ACM 27.2 (1980), pages
228–234.

> 50
>
> \[Pos84\]
>
> \[RS60\]
>
> \[Sho24\]
>
> \[SSV25\]
>
> \[SKN25\]
>
> \[SR08\]
>
> \[Spi+22\]
>
> \[SSK25\]
>
> \[SDV19\]
>
> \[Von+24\]
>
> \[Yak18\]
>
> \[Yan+22\]
>
> \[Yin+19\]

Jon Postel. Standard for the Interchange of Ethernet Frames. RFC 894.
Apr. 1984.

Irving S Reed and Gustave Solomon. “Polynomial codes over certain finite
fields”. In: Journal of the society for industrial and applied
mathematics 8.2 (1960), pages 300–304.

Victor Shoup. “Sing a Song of Simplex”. In: 38th International
Sym-posium on Distributed Computing (DISC). Volume 319. Leibniz
In-ternational Proceedings in Informatics. Dagstuhl, Germany, 2024,
37:1–37:22.

Victor Shoup, Jakub Sliwinski, and Yann Vonlanthen. “Kudzu: Fast and
Simple High-Throughput BFT”. In: arXiv:2505.08771 (2025).

Nibesh Shrestha, Aniket Kate, and Kartik Nayak. “Hydrangea: Op-timistic
Two-Round Partial Synchrony with One-Third Fault Re-silience”. In:
Cryptology ePrint Archive (2025).

Yee Jiun Song and Robbert van Renesse. “Bosco: One-step byzan-tine
asynchronous consensus”. In: International Symposium on Dis-tributed
Computing (DISC). Springer. 2008, pages 438–450.

Alexander Spiegelman, Neil Giridharan, Alberto Sonnino, and Lef-teris
Kokoris-Kogias. “Bullshark: DAG BFT protocols made practi-cal”. In:
Proceedings of the ACM SIGSAC Conference on Computer and Communications
Security (CCS). 2022, pages 2705–2718.

Srivatsan Sridhar, Alberto Sonnino, and Lefteris Kokoris-Kogias.
“Stingray: Fast Concurrent Transactions Without Consensus”. In: arXiv
preprint arXiv:2501.06531 (2025).

Chrysoula Stathakopoulou, Tudor David, and Marko Vukolic.
“Mir-BFT:High-ThroughputBFTforBlockchains”.In: arXiv:1906.05552 (2019).

Yann Vonlanthen, Jakub Sliwinski, Massimo Albarello, and Roger
Wattenhofer. “Banyan: Fast Rotating Leader BFT”. In: 25th ACM
International Middleware Conference, Hong Kong, China.Dec.2024.

Anatoly Yakovenko. Solana: A new architecture for a high perfor-mance
blockchain v0.8.13.
[https://solana.com/solana-whitepape](https://solana.com/solana-whitepaper.pdf)r.
[pdf.](https://solana.com/solana-whitepaper.pdf) 2018.

Lei Yang, Seo Jin Park, Mohammad Alizadeh, Sreeram Kannan, and David
Tse. “DispersedLedger: High-Throughput Byzantine
Consen-susonVariableBandwidthNetworks”.In: 19th USENIX Symposium on
Networked Systems Design and Implementation (NSDI). Renton, WA, Apr.
2022, pages 493–512.

Maofan Yin, Dahlia Malkhi, Michael K Reiter, Guy Golan Gueta, and Ittai
Abraham. “HotStuff: BFT Consensus with Linearity and Responsiveness”.
In: Proceedings of the ACM Symposium on Prin-ciples of Distributed
Computing (PODC). 2019, pages 347–356.

> 51
>
> \[Zha+11\] Xin Zhang et al. “SCION: Scalability, Control, and
> Isolation on Next-Generation Networks”. In: IEEE Symposium on Security
> and Privacy (S&P). 2011, pages 212–227.
>
> 52
