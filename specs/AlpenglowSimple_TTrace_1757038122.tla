---- MODULE AlpenglowSimple_TTrace_1757038122 ----
EXTENDS Sequences, TLCExt, Toolbox, AlpenglowSimple, Naturals, TLC, AlpenglowSimple_TEConstants

_expression ==
    LET AlpenglowSimple_TEExpression == INSTANCE AlpenglowSimple_TEExpression
    IN AlpenglowSimple_TEExpression!expression
----

_trace ==
    LET AlpenglowSimple_TETrace == INSTANCE AlpenglowSimple_TETrace
    IN AlpenglowSimple_TETrace!trace
----

_prop ==
    ~<>[](
        currentSlot = (2)
        /\
        votorVotedBlocks = ((v1 :> {1, 101, 201} @@ v2 :> {201} @@ v3 :> {101, 201}))
        /\
        votorFinalizedChain = ((v1 :> <<>> @@ v2 :> <<>> @@ v3 :> <<>>))
        /\
        messages = ({})
        /\
        votorView = ((v1 :> 1 @@ v2 :> 1 @@ v3 :> 1))
        /\
        clock = (10)
    )
----

_init ==
    /\ currentSlot = _TETrace[1].currentSlot
    /\ votorVotedBlocks = _TETrace[1].votorVotedBlocks
    /\ messages = _TETrace[1].messages
    /\ votorView = _TETrace[1].votorView
    /\ clock = _TETrace[1].clock
    /\ votorFinalizedChain = _TETrace[1].votorFinalizedChain
----

_next ==
    /\ \E i,j \in DOMAIN _TETrace:
        /\ \/ /\ j = i + 1
              /\ i = TLCGet("level")
        /\ currentSlot  = _TETrace[i].currentSlot
        /\ currentSlot' = _TETrace[j].currentSlot
        /\ votorVotedBlocks  = _TETrace[i].votorVotedBlocks
        /\ votorVotedBlocks' = _TETrace[j].votorVotedBlocks
        /\ messages  = _TETrace[i].messages
        /\ messages' = _TETrace[j].messages
        /\ votorView  = _TETrace[i].votorView
        /\ votorView' = _TETrace[j].votorView
        /\ clock  = _TETrace[i].clock
        /\ clock' = _TETrace[j].clock
        /\ votorFinalizedChain  = _TETrace[i].votorFinalizedChain
        /\ votorFinalizedChain' = _TETrace[j].votorFinalizedChain

\* Uncomment the ASSUME below to write the states of the error trace
\* to the given file in Json format. Note that you can pass any tuple
\* to `JsonSerialize`. For example, a sub-sequence of _TETrace.
    \* ASSUME
    \*     LET J == INSTANCE Json
    \*         IN J!JsonSerialize("AlpenglowSimple_TTrace_1757038122.json", _TETrace)

=============================================================================

 Note that you can extract this module `AlpenglowSimple_TEExpression`
  to a dedicated file to reuse `expression` (the module in the 
  dedicated `AlpenglowSimple_TEExpression.tla` file takes precedence 
  over the module `AlpenglowSimple_TEExpression` below).

---- MODULE AlpenglowSimple_TEExpression ----
EXTENDS Sequences, TLCExt, Toolbox, AlpenglowSimple, Naturals, TLC, AlpenglowSimple_TEConstants

expression == 
    [
        \* To hide variables of the `AlpenglowSimple` spec from the error trace,
        \* remove the variables below.  The trace will be written in the order
        \* of the fields of this record.
        currentSlot |-> currentSlot
        ,votorVotedBlocks |-> votorVotedBlocks
        ,messages |-> messages
        ,votorView |-> votorView
        ,clock |-> clock
        ,votorFinalizedChain |-> votorFinalizedChain
        
        \* Put additional constant-, state-, and action-level expressions here:
        \* ,_stateNumber |-> _TEPosition
        \* ,_currentSlotUnchanged |-> currentSlot = currentSlot'
        
        \* Format the `currentSlot` variable as Json value.
        \* ,_currentSlotJson |->
        \*     LET J == INSTANCE Json
        \*     IN J!ToJson(currentSlot)
        
        \* Lastly, you may build expressions over arbitrary sets of states by
        \* leveraging the _TETrace operator.  For example, this is how to
        \* count the number of times a spec variable changed up to the current
        \* state in the trace.
        \* ,_currentSlotModCount |->
        \*     LET F[s \in DOMAIN _TETrace] ==
        \*         IF s = 1 THEN 0
        \*         ELSE IF _TETrace[s].currentSlot # _TETrace[s-1].currentSlot
        \*             THEN 1 + F[s-1] ELSE F[s-1]
        \*     IN F[_TEPosition - 1]
    ]

=============================================================================



Parsing and semantic processing can take forever if the trace below is long.
 In this case, it is advised to uncomment the module below to deserialize the
 trace from a generated binary file.

\*
\*---- MODULE AlpenglowSimple_TETrace ----
\*EXTENDS IOUtils, AlpenglowSimple, TLC, AlpenglowSimple_TEConstants
\*
\*trace == IODeserialize("AlpenglowSimple_TTrace_1757038122.bin", TRUE)
\*
\*=============================================================================
\*

---- MODULE AlpenglowSimple_TETrace ----
EXTENDS AlpenglowSimple, TLC, AlpenglowSimple_TEConstants

trace == 
    <<
    ([currentSlot |-> 0,votorVotedBlocks |-> (v1 :> {} @@ v2 :> {} @@ v3 :> {}),votorFinalizedChain |-> (v1 :> <<>> @@ v2 :> <<>> @@ v3 :> <<>>),messages |-> {},votorView |-> (v1 :> 1 @@ v2 :> 1 @@ v3 :> 1),clock |-> 0]),
    ([currentSlot |-> 0,votorVotedBlocks |-> (v1 :> {} @@ v2 :> {} @@ v3 :> {}),votorFinalizedChain |-> (v1 :> <<>> @@ v2 :> <<>> @@ v3 :> <<>>),messages |-> {},votorView |-> (v1 :> 1 @@ v2 :> 1 @@ v3 :> 1),clock |-> 1]),
    ([currentSlot |-> 0,votorVotedBlocks |-> (v1 :> {1} @@ v2 :> {} @@ v3 :> {}),votorFinalizedChain |-> (v1 :> <<>> @@ v2 :> <<>> @@ v3 :> <<>>),messages |-> {},votorView |-> (v1 :> 1 @@ v2 :> 1 @@ v3 :> 1),clock |-> 1]),
    ([currentSlot |-> 0,votorVotedBlocks |-> (v1 :> {1} @@ v2 :> {} @@ v3 :> {}),votorFinalizedChain |-> (v1 :> <<>> @@ v2 :> <<>> @@ v3 :> <<>>),messages |-> {},votorView |-> (v1 :> 1 @@ v2 :> 1 @@ v3 :> 1),clock |-> 2]),
    ([currentSlot |-> 1,votorVotedBlocks |-> (v1 :> {1} @@ v2 :> {} @@ v3 :> {}),votorFinalizedChain |-> (v1 :> <<>> @@ v2 :> <<>> @@ v3 :> <<>>),messages |-> {},votorView |-> (v1 :> 1 @@ v2 :> 1 @@ v3 :> 1),clock |-> 2]),
    ([currentSlot |-> 1,votorVotedBlocks |-> (v1 :> {1, 101} @@ v2 :> {} @@ v3 :> {}),votorFinalizedChain |-> (v1 :> <<>> @@ v2 :> <<>> @@ v3 :> <<>>),messages |-> {},votorView |-> (v1 :> 1 @@ v2 :> 1 @@ v3 :> 1),clock |-> 2]),
    ([currentSlot |-> 1,votorVotedBlocks |-> (v1 :> {1, 101} @@ v2 :> {} @@ v3 :> {}),votorFinalizedChain |-> (v1 :> <<>> @@ v2 :> <<>> @@ v3 :> <<>>),messages |-> {},votorView |-> (v1 :> 1 @@ v2 :> 1 @@ v3 :> 1),clock |-> 3]),
    ([currentSlot |-> 1,votorVotedBlocks |-> (v1 :> {1, 101} @@ v2 :> {} @@ v3 :> {}),votorFinalizedChain |-> (v1 :> <<>> @@ v2 :> <<>> @@ v3 :> <<>>),messages |-> {},votorView |-> (v1 :> 1 @@ v2 :> 1 @@ v3 :> 1),clock |-> 4]),
    ([currentSlot |-> 1,votorVotedBlocks |-> (v1 :> {1, 101} @@ v2 :> {} @@ v3 :> {101}),votorFinalizedChain |-> (v1 :> <<>> @@ v2 :> <<>> @@ v3 :> <<>>),messages |-> {},votorView |-> (v1 :> 1 @@ v2 :> 1 @@ v3 :> 1),clock |-> 4]),
    ([currentSlot |-> 1,votorVotedBlocks |-> (v1 :> {1, 101} @@ v2 :> {} @@ v3 :> {101}),votorFinalizedChain |-> (v1 :> <<>> @@ v2 :> <<>> @@ v3 :> <<>>),messages |-> {},votorView |-> (v1 :> 1 @@ v2 :> 1 @@ v3 :> 1),clock |-> 5]),
    ([currentSlot |-> 1,votorVotedBlocks |-> (v1 :> {1, 101} @@ v2 :> {} @@ v3 :> {101}),votorFinalizedChain |-> (v1 :> <<>> @@ v2 :> <<>> @@ v3 :> <<>>),messages |-> {},votorView |-> (v1 :> 1 @@ v2 :> 1 @@ v3 :> 1),clock |-> 6]),
    ([currentSlot |-> 2,votorVotedBlocks |-> (v1 :> {1, 101} @@ v2 :> {} @@ v3 :> {101}),votorFinalizedChain |-> (v1 :> <<>> @@ v2 :> <<>> @@ v3 :> <<>>),messages |-> {},votorView |-> (v1 :> 1 @@ v2 :> 1 @@ v3 :> 1),clock |-> 6]),
    ([currentSlot |-> 2,votorVotedBlocks |-> (v1 :> {1, 101} @@ v2 :> {201} @@ v3 :> {101}),votorFinalizedChain |-> (v1 :> <<>> @@ v2 :> <<>> @@ v3 :> <<>>),messages |-> {},votorView |-> (v1 :> 1 @@ v2 :> 1 @@ v3 :> 1),clock |-> 6]),
    ([currentSlot |-> 2,votorVotedBlocks |-> (v1 :> {1, 101, 201} @@ v2 :> {201} @@ v3 :> {101}),votorFinalizedChain |-> (v1 :> <<>> @@ v2 :> <<>> @@ v3 :> <<>>),messages |-> {},votorView |-> (v1 :> 1 @@ v2 :> 1 @@ v3 :> 1),clock |-> 6]),
    ([currentSlot |-> 2,votorVotedBlocks |-> (v1 :> {1, 101, 201} @@ v2 :> {201} @@ v3 :> {101, 201}),votorFinalizedChain |-> (v1 :> <<>> @@ v2 :> <<>> @@ v3 :> <<>>),messages |-> {},votorView |-> (v1 :> 1 @@ v2 :> 1 @@ v3 :> 1),clock |-> 6]),
    ([currentSlot |-> 2,votorVotedBlocks |-> (v1 :> {1, 101, 201} @@ v2 :> {201} @@ v3 :> {101, 201}),votorFinalizedChain |-> (v1 :> <<>> @@ v2 :> <<>> @@ v3 :> <<>>),messages |-> {},votorView |-> (v1 :> 1 @@ v2 :> 1 @@ v3 :> 1),clock |-> 7]),
    ([currentSlot |-> 2,votorVotedBlocks |-> (v1 :> {1, 101, 201} @@ v2 :> {201} @@ v3 :> {101, 201}),votorFinalizedChain |-> (v1 :> <<>> @@ v2 :> <<>> @@ v3 :> <<>>),messages |-> {},votorView |-> (v1 :> 1 @@ v2 :> 1 @@ v3 :> 1),clock |-> 8]),
    ([currentSlot |-> 2,votorVotedBlocks |-> (v1 :> {1, 101, 201} @@ v2 :> {201} @@ v3 :> {101, 201}),votorFinalizedChain |-> (v1 :> <<>> @@ v2 :> <<>> @@ v3 :> <<>>),messages |-> {},votorView |-> (v1 :> 1 @@ v2 :> 1 @@ v3 :> 1),clock |-> 9]),
    ([currentSlot |-> 2,votorVotedBlocks |-> (v1 :> {1, 101, 201} @@ v2 :> {201} @@ v3 :> {101, 201}),votorFinalizedChain |-> (v1 :> <<>> @@ v2 :> <<>> @@ v3 :> <<>>),messages |-> {},votorView |-> (v1 :> 1 @@ v2 :> 1 @@ v3 :> 1),clock |-> 10])
    >>
----


=============================================================================

---- MODULE AlpenglowSimple_TEConstants ----
EXTENDS AlpenglowSimple

CONSTANTS v1, v2, v3

=============================================================================

---- CONFIG AlpenglowSimple_TTrace_1757038122 ----
CONSTANTS
    Validators = { v1 , v2 , v3 }
    ByzantineValidators = { }
    OfflineValidators = { }
    MaxSlot = 3
    MaxView = 2
    MaxTime = 10
    v1 = v1
    v2 = v2
    v3 = v3

PROPERTY
    _prop

CHECK_DEADLOCK
    \* CHECK_DEADLOCK off because of PROPERTY or INVARIANT above.
    FALSE

INIT
    _init

NEXT
    _next

CONSTANT
    _TETrace <- _trace

ALIAS
    _expression
=============================================================================
\* Generated on Fri Sep 05 07:38:44 IST 2025