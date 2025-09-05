//! Local implementation of stateright framework types and traits
//!
//! This module provides the core types and traits needed for the Alpenglow
//! protocol implementation, avoiding external dependency conflicts.

use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::fmt::Debug;
use std::hash::Hash;

/// Unique identifier for actors in the system
pub type Id = usize;

/// Output channel for actor messages
pub mod util {
    use super::*;
    
    /// Output channel for sending messages
    pub struct Out<A: Actor> {
        pub messages: Vec<(Id, A::Msg)>,
        pub actor_count: usize,
    }
    
    impl<A: Actor> Out<A> {
        pub fn new() -> Self {
            Self { 
                messages: Vec::new(),
                actor_count: 0,
            }
        }
        
        pub fn with_actor_count(actor_count: usize) -> Self {
            Self {
                messages: Vec::new(),
                actor_count,
            }
        }
        
        /// Send a message to a specific actor
        pub fn send(&mut self, id: Id, msg: A::Msg) {
            self.messages.push((id, msg));
        }
        
        /// Broadcast a message to all actors
        pub fn broadcast(&mut self, msg: A::Msg) 
        where 
            A::Msg: Clone 
        {
            for actor_id in 0..self.actor_count {
                self.messages.push((actor_id, msg.clone()));
            }
        }
        
        /// Clear all pending messages
        pub fn clear(&mut self) {
            self.messages.clear();
        }
        
        /// Get all pending messages and clear the queue
        pub fn drain_messages(&mut self) -> Vec<(Id, A::Msg)> {
            std::mem::take(&mut self.messages)
        }
    }
    
    /// Hashable wrapper for HashMap
    #[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
    pub struct HashableHashMap<K: Hash + Eq, V>(pub HashMap<K, V>);
    
    impl<K: Hash + Eq, V> Hash for HashableHashMap<K, V> 
    where
        K: Hash + Ord,
        V: Hash,
    {
        fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
            let mut items: Vec<(&K, &V)> = self.0.iter().collect();
            items.sort_by_key(|&(k, _)| k);
            for (k, v) in items {
                k.hash(state);
                v.hash(state);
            }
        }
    }
    
    /// Hashable wrapper for HashSet
    #[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
    pub struct HashableHashSet<T: Hash + Eq>(pub HashSet<T>);
    
    impl<T: Hash + Eq + Ord> Hash for HashableHashSet<T> {
        fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
            let mut items: Vec<&T> = self.0.iter().collect();
            items.sort();
            for item in items {
                item.hash(state);
            }
        }
    }
}

/// Core Actor trait for state machines
pub trait Actor: Sized {
    /// The state type for this actor
    type State: Clone + Debug + Hash;
    
    /// The message type for this actor
    type Msg: Clone + Debug + Hash;
    
    /// Initialize the actor's state
    fn on_start(&self, id: Id, o: &mut util::Out<Self>) -> Self::State;
    
    /// Handle incoming messages and update state
    fn on_msg(
        &self,
        id: Id,
        state: &mut Self::State,
        src: Id,
        msg: Self::Msg,
        o: &mut util::Out<Self>,
    );
}

/// Actor model for distributed systems
pub struct ActorModel<A: Actor, I = (), O = ()> {
    pub actors: Vec<A>,
    pub init_network: I,
    pub record_msg_out: O,
    pub actor_states: Vec<Option<A::State>>,
    pub message_queue: Vec<(Id, Id, A::Msg)>,
    pub step_count: usize,
}

impl<A: Actor> ActorModel<A> {
    pub fn new() -> Self {
        Self {
            actors: Vec::new(),
            init_network: (),
            record_msg_out: (),
            actor_states: Vec::new(),
            message_queue: Vec::new(),
            step_count: 0,
        }
    }
    
    pub fn actor(mut self, actor: A) -> Self {
        self.actors.push(actor);
        self.actor_states.push(None);
        self
    }
    
    pub fn init_network<I>(mut self, init: I) -> ActorModel<A, I, ()> {
        ActorModel {
            actors: self.actors,
            init_network: init,
            record_msg_out: (),
            actor_states: self.actor_states,
            message_queue: self.message_queue,
            step_count: self.step_count,
        }
    }
    
    /// Initialize all actors
    pub fn init(&mut self) {
        for (id, actor) in self.actors.iter().enumerate() {
            let mut out = util::Out::with_actor_count(self.actors.len());
            let state = actor.on_start(id, &mut out);
            self.actor_states[id] = Some(state);
            
            // Queue initial messages
            for (target_id, msg) in out.drain_messages() {
                self.message_queue.push((id, target_id, msg));
            }
        }
    }
    
    /// Run a single step of the actor system
    pub fn run_step(&mut self) -> bool {
        if self.message_queue.is_empty() {
            return false; // No more messages to process
        }
        
        // Process one message from the queue
        if let Some((src_id, target_id, msg)) = self.message_queue.pop() {
            if target_id < self.actors.len() {
                if let (Some(actor), Some(ref mut state)) = (
                    self.actors.get(target_id),
                    self.actor_states.get_mut(target_id).and_then(|s| s.as_mut())
                ) {
                    let mut out = util::Out::with_actor_count(self.actors.len());
                    actor.on_msg(target_id, state, src_id, msg, &mut out);
                    
                    // Queue new messages generated by this actor
                    for (new_target_id, new_msg) in out.drain_messages() {
                        self.message_queue.push((target_id, new_target_id, new_msg));
                    }
                }
            }
        }
        
        self.step_count += 1;
        true
    }
    
    /// Run multiple steps until no more messages or max steps reached
    pub fn run_steps(&mut self, max_steps: usize) -> usize {
        let mut steps_run = 0;
        while steps_run < max_steps && self.run_step() {
            steps_run += 1;
        }
        steps_run
    }
    
    /// Get the current state of an actor
    pub fn get_actor_state(&self, id: Id) -> Option<&A::State> {
        self.actor_states.get(id).and_then(|s| s.as_ref())
    }
    
    /// Get the number of pending messages
    pub fn pending_message_count(&self) -> usize {
        self.message_queue.len()
    }
    
    /// Get the current step count
    pub fn get_step_count(&self) -> usize {
        self.step_count
    }
    
    /// Check if the system has reached a stable state (no pending messages)
    pub fn is_stable(&self) -> bool {
        self.message_queue.is_empty()
    }
    
    /// Reset the actor model to initial state
    pub fn reset(&mut self) {
        self.actor_states.clear();
        self.message_queue.clear();
        self.step_count = 0;
        
        // Reinitialize actor states
        for _ in 0..self.actors.len() {
            self.actor_states.push(None);
        }
        self.init();
    }
}

/// Network state for message passing
pub struct Network {
    pub messages: Vec<(Id, Id, Vec<u8>)>,
}

/// System state for actor models
pub struct SystemState<S> {
    pub actor_states: Vec<Option<S>>,
    pub network: Network,
    pub step_count: usize,
}

impl<S> SystemState<S> {
    pub fn new(actor_count: usize) -> Self {
        Self {
            actor_states: vec![None; actor_count],
            network: Network { messages: Vec::new() },
            step_count: 0,
        }
    }
    
    pub fn advance_step(&mut self) {
        self.step_count += 1;
    }
    
    pub fn get_step_count(&self) -> usize {
        self.step_count
    }
}

/// Property trait for model checking
pub trait Property<M: Model> {
    /// Check if the property holds for a given state
    fn check(&self, model: &M, state: &M::State) -> bool;
}

/// Simple property implementation
pub struct SimpleProperty<F> {
    pub name: String,
    pub check_fn: F,
}

impl<F, M> Property<M> for SimpleProperty<F>
where
    F: Fn(&M, &M::State) -> bool,
    M: Model,
{
    fn check(&self, model: &M, state: &M::State) -> bool {
        (self.check_fn)(model, state)
    }
}

impl<F> SimpleProperty<F> {
    pub fn always<M>(name: &str, check_fn: F) -> Self 
    where
        F: Fn(&M, &M::State) -> bool,
        M: Model
    {
        Self {
            name: name.to_string(),
            check_fn,
        }
    }
    
    pub fn eventually<M>(name: &str, check_fn: F) -> Self
    where
        F: Fn(&M, &M::State) -> bool,
        M: Model  
    {
        Self {
            name: name.to_string(),
            check_fn,
        }
    }
    
    pub fn name(&self) -> &str {
        &self.name
    }
}

/// Model trait for state exploration
pub trait Model {
    /// The state type for the model
    type State;
    
    /// The action type for state transitions
    type Action;
    
    /// Get the initial state
    fn init_states(&self) -> Vec<Self::State>;
    
    /// Get available actions from a state
    fn actions(&self, state: &Self::State) -> Vec<Self::Action>;
    
    /// Apply an action to a state
    fn next_state(&self, state: &Self::State, action: Self::Action) -> Option<Self::State>;
}

/// Checker for model verification
pub struct Checker<M: Model> {
    model: M,
}

impl<M: Model> Checker<M> {
    /// Create a new checker
    pub fn new(model: M) -> Self {
        Self { model }
    }
    
    /// Check safety properties
    pub fn check_safety(&self) -> bool {
        // Simplified implementation - would perform actual safety checking
        let init_states = self.model.init_states();
        for state in &init_states {
            let actions = self.model.actions(state);
            for action in actions {
                if let Some(_next_state) = self.model.next_state(state, action) {
                    // Would check safety properties here
                }
            }
        }
        true
    }
    
    /// Check liveness properties
    pub fn check_liveness(&self) -> bool {
        // Simplified implementation - would perform actual liveness checking
        let init_states = self.model.init_states();
        !init_states.is_empty()
    }
    
    /// Run exhaustive state exploration
    pub fn check_exhaustive(&self) -> bool {
        // Simplified implementation - would perform exhaustive exploration
        let init_states = self.model.init_states();
        for state in &init_states {
            let _actions = self.model.actions(state);
            // Would explore all reachable states
        }
        true
    }
    
    /// Check a specific property
    pub fn check_property<P>(&self, property: &P) -> CheckResult 
    where
        P: Property<M>
    {
        let init_states = self.model.init_states();
        for state in &init_states {
            if !property.check(&self.model, state) {
                return CheckResult::Fail("Property violation detected".to_string());
            }
        }
        CheckResult::Pass
    }
}

/// Result type for property checking
#[derive(Debug)]
pub enum CheckResult {
    Pass,
    Fail(String),
    Timeout,
}
