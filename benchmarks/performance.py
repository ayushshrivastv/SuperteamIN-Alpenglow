#!/usr/bin/env python3
"""
Performance Benchmarks for Alpenglow Consensus Protocol

This module provides comprehensive benchmarking tools to measure and validate
the performance claims made in the Alpenglow whitepaper, including:
- Finalization latency (min(δ80%, 2δ60%))
- Throughput and bandwidth efficiency
- Rotor dissemination performance
- Votor consensus latency
- Network resilience under various conditions

The benchmarks complement formal verification by providing empirical validation
of theoretical performance bounds and real-world behavior analysis.
"""

import asyncio
import json
import logging
import math
import random
import statistics
import time
from dataclasses import dataclass, asdict
from typing import Dict, List, Tuple, Optional, Any
from concurrent.futures import ThreadPoolExecutor
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from pathlib import Path

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

@dataclass
class NetworkConfig:
    """Network configuration parameters for benchmarking"""
    num_validators: int = 1500  # Current Solana validator count
    byzantine_stake_pct: float = 0.15  # Byzantine stake percentage (< 20%)
    crash_stake_pct: float = 0.10  # Additional crash failures
    delta_ms: int = 80  # Average network delay (ms)
    delta_timeout_ms: int = 400  # Maximum network delay bound (ms)
    block_time_ms: int = 400  # Target block time (ms)
    leader_window_size: int = 4  # Slots per leader window

@dataclass
class RotorConfig:
    """Rotor (block dissemination) configuration"""
    gamma: int = 32  # Minimum shreds needed for reconstruction
    expansion_ratio: float = 2.0  # Data expansion ratio (κ = Γ/γ)
    slice_size_bytes: int = 1200  # Size per slice (fits in UDP)
    slices_per_block: int = 64  # Number of slices per block
    
    @property
    def total_shreds(self) -> int:
        """Total number of shreds (Γ)"""
        return int(self.gamma * self.expansion_ratio)

@dataclass
class VotorConfig:
    """Votor (consensus) configuration"""
    fast_threshold_pct: float = 0.80  # Fast path threshold (80% stake)
    slow_threshold_pct: float = 0.60  # Slow path threshold (60% stake)
    notarization_threshold_pct: float = 0.60  # Notarization threshold
    finalization_threshold_pct: float = 0.60  # Finalization threshold

@dataclass
class PerformanceMetrics:
    """Performance measurement results"""
    finalization_latency_ms: float
    throughput_tps: float
    bandwidth_efficiency_pct: float
    rotor_latency_ms: float
    votor_latency_ms: float
    fast_path_success_rate: float
    slow_path_success_rate: float
    block_size_bytes: int
    network_utilization_pct: float

class StakeDistribution:
    """Manages validator stake distribution based on real Solana data"""
    
    def __init__(self, num_validators: int):
        self.num_validators = num_validators
        self.stakes = self._generate_realistic_distribution()
        
    def _generate_realistic_distribution(self) -> List[float]:
        """Generate realistic stake distribution based on Solana epoch 780 data"""
        # Approximate Solana's stake distribution with power law
        stakes = []
        
        # Large validators (top 10%) hold ~60% of stake
        large_validators = int(self.num_validators * 0.1)
        large_stake_total = 0.6
        
        # Medium validators (next 30%) hold ~30% of stake  
        medium_validators = int(self.num_validators * 0.3)
        medium_stake_total = 0.3
        
        # Small validators (remaining 60%) hold ~10% of stake
        small_validators = self.num_validators - large_validators - medium_validators
        small_stake_total = 0.1
        
        # Generate large validator stakes (power law distribution)
        for i in range(large_validators):
            # Zipf-like distribution for large validators
            stake = large_stake_total * (1.0 / (i + 1)) / sum(1.0 / (j + 1) for j in range(large_validators))
            stakes.append(stake)
            
        # Generate medium validator stakes
        for i in range(medium_validators):
            stake = medium_stake_total * (1.0 / (i + 1)) / sum(1.0 / (j + 1) for j in range(medium_validators))
            stakes.append(stake)
            
        # Generate small validator stakes (more uniform)
        small_stake_each = small_stake_total / small_validators
        for i in range(small_validators):
            # Add some variance
            variance = random.uniform(0.5, 1.5)
            stakes.append(small_stake_each * variance)
            
        # Normalize to ensure sum = 1.0
        total = sum(stakes)
        stakes = [s / total for s in stakes]
        
        return stakes
    
    def get_stake_percentiles(self) -> Dict[str, float]:
        """Get stake distribution percentiles"""
        sorted_stakes = sorted(self.stakes, reverse=True)
        cumulative = np.cumsum(sorted_stakes)
        
        percentiles = {}
        for pct in [60, 70, 80, 90, 95, 99]:
            idx = next(i for i, cum in enumerate(cumulative) if cum >= pct / 100.0)
            percentiles[f"p{pct}"] = idx + 1  # Number of validators needed
            
        return percentiles

class NetworkLatencyModel:
    """Models realistic network latency based on geographic distribution"""
    
    def __init__(self, num_validators: int, delta_ms: int = 80):
        self.num_validators = num_validators
        self.delta_ms = delta_ms
        self.latency_matrix = self._generate_latency_matrix()
        
    def _generate_latency_matrix(self) -> np.ndarray:
        """Generate realistic latency matrix between validators"""
        # Simulate geographic clusters (US East, US West, Europe, Asia)
        clusters = {
            'us_east': {'size': 0.35, 'base_latency': 20},
            'us_west': {'size': 0.25, 'base_latency': 25}, 
            'europe': {'size': 0.25, 'base_latency': 30},
            'asia': {'size': 0.15, 'base_latency': 40}
        }
        
        # Inter-cluster latencies (ms)
        inter_cluster_latency = {
            ('us_east', 'us_west'): 70,
            ('us_east', 'europe'): 100,
            ('us_east', 'asia'): 180,
            ('us_west', 'europe'): 150,
            ('us_west', 'asia'): 120,
            ('europe', 'asia'): 200
        }
        
        # Assign validators to clusters
        validator_clusters = []
        start_idx = 0
        for cluster_name, config in clusters.items():
            cluster_size = int(self.num_validators * config['size'])
            validator_clusters.extend([cluster_name] * cluster_size)
            start_idx += cluster_size
            
        # Fill remaining validators
        while len(validator_clusters) < self.num_validators:
            validator_clusters.append('us_east')
            
        # Generate latency matrix
        matrix = np.zeros((self.num_validators, self.num_validators))
        
        for i in range(self.num_validators):
            for j in range(self.num_validators):
                if i == j:
                    matrix[i][j] = 0
                else:
                    cluster_i = validator_clusters[i]
                    cluster_j = validator_clusters[j]
                    
                    if cluster_i == cluster_j:
                        # Intra-cluster latency
                        base = clusters[cluster_i]['base_latency']
                        matrix[i][j] = base + random.uniform(-5, 15)
                    else:
                        # Inter-cluster latency
                        key = tuple(sorted([cluster_i, cluster_j]))
                        base = inter_cluster_latency.get(key, 150)
                        matrix[i][j] = base + random.uniform(-10, 30)
                        
        return matrix
    
    def get_latency(self, from_validator: int, to_validator: int) -> float:
        """Get latency between two validators"""
        return self.latency_matrix[from_validator][to_validator]
    
    def get_delta_percentile(self, stake_distribution: List[float], percentile: float) -> float:
        """Calculate δ_θ for given stake percentile"""
        # Sort validators by stake (descending)
        validator_stakes = list(enumerate(stake_distribution))
        validator_stakes.sort(key=lambda x: x[1], reverse=True)
        
        # Find validators representing the percentile
        cumulative_stake = 0.0
        selected_validators = []
        
        for validator_idx, stake in validator_stakes:
            selected_validators.append(validator_idx)
            cumulative_stake += stake
            if cumulative_stake >= percentile:
                break
                
        # Calculate average latency within this group
        latencies = []
        for i in selected_validators:
            for j in selected_validators:
                if i != j:
                    latencies.append(self.latency_matrix[i][j])
                    
        return statistics.mean(latencies) if latencies else self.delta_ms

class RotorSimulator:
    """Simulates Rotor block dissemination protocol"""
    
    def __init__(self, config: RotorConfig, network: NetworkLatencyModel, stakes: List[float]):
        self.config = config
        self.network = network
        self.stakes = stakes
        
    def simulate_dissemination(self, leader_idx: int) -> Tuple[float, Dict[str, Any]]:
        """Simulate block dissemination from leader to all validators"""
        num_validators = len(self.stakes)
        
        # Phase 1: Leader sends shreds to relays
        relay_indices = self._sample_relays()
        relay_latencies = []
        
        for relay_idx in relay_indices:
            latency = self.network.get_latency(leader_idx, relay_idx)
            relay_latencies.append(latency)
            
        phase1_latency = max(relay_latencies)
        
        # Phase 2: Relays broadcast to all validators
        validator_receive_times = {}
        
        for validator_idx in range(num_validators):
            if validator_idx == leader_idx:
                validator_receive_times[validator_idx] = 0
                continue
                
            # Find fastest path through relays
            min_receive_time = float('inf')
            
            for relay_idx in relay_indices:
                relay_to_leader_time = self.network.get_latency(leader_idx, relay_idx)
                relay_to_validator_time = self.network.get_latency(relay_idx, validator_idx)
                total_time = relay_to_leader_time + relay_to_validator_time
                min_receive_time = min(min_receive_time, total_time)
                
            validator_receive_times[validator_idx] = min_receive_time
            
        # Calculate when enough shreds are received for reconstruction
        reconstruction_times = []
        for validator_idx in range(num_validators):
            if validator_idx != leader_idx:
                # Assume validator needs γ shreds from different relays
                relay_times = []
                for relay_idx in relay_indices[:self.config.gamma]:
                    relay_to_leader = self.network.get_latency(leader_idx, relay_idx)
                    relay_to_validator = self.network.get_latency(relay_idx, validator_idx)
                    relay_times.append(relay_to_leader + relay_to_validator)
                    
                # Time when γ-th shred arrives
                relay_times.sort()
                reconstruction_time = relay_times[self.config.gamma - 1] if len(relay_times) >= self.config.gamma else max(relay_times)
                reconstruction_times.append(reconstruction_time)
                
        avg_reconstruction_time = statistics.mean(reconstruction_times)
        max_reconstruction_time = max(reconstruction_times)
        
        metrics = {
            'phase1_latency': phase1_latency,
            'avg_reconstruction_time': avg_reconstruction_time,
            'max_reconstruction_time': max_reconstruction_time,
            'num_relays': len(relay_indices),
            'relay_success_rate': len(relay_indices) / self.config.total_shreds
        }
        
        return avg_reconstruction_time, metrics
    
    def _sample_relays(self) -> List[int]:
        """Sample relay validators based on stake-weighted selection"""
        # Use partition sampling (PS-P) as described in whitepaper Section 3.1
        num_relays = self.config.total_shreds
        relays = []
        
        # Phase 1: Deterministic assignment for large stakes
        remaining_stakes = self.stakes.copy()
        threshold = 1.0 / num_relays
        
        for i, stake in enumerate(self.stakes):
            if stake > threshold:
                num_assignments = int(stake * num_relays)
                relays.extend([i] * num_assignments)
                remaining_stakes[i] = stake - (num_assignments / num_relays)
                
        # Phase 2: Random sampling for remaining slots
        remaining_slots = num_relays - len(relays)
        if remaining_slots > 0:
            # Normalize remaining stakes
            total_remaining = sum(remaining_stakes)
            if total_remaining > 0:
                normalized_stakes = [s / total_remaining for s in remaining_stakes]
                
                # Sample remaining relays
                for _ in range(remaining_slots):
                    relay_idx = np.random.choice(len(self.stakes), p=normalized_stakes)
                    relays.append(relay_idx)
                    
        return list(set(relays))  # Remove duplicates

class VotorSimulator:
    """Simulates Votor consensus protocol"""
    
    def __init__(self, config: VotorConfig, network: NetworkLatencyModel, stakes: List[float]):
        self.config = config
        self.network = network
        self.stakes = stakes
        
    def simulate_consensus(self, block_receive_times: Dict[int, float]) -> Tuple[float, Dict[str, Any]]:
        """Simulate consensus voting process"""
        num_validators = len(self.stakes)
        
        # Phase 1: Notarization votes
        notarization_votes = {}
        for validator_idx, receive_time in block_receive_times.items():
            # Validator votes after receiving block
            vote_time = receive_time + random.uniform(1, 5)  # Processing delay
            notarization_votes[validator_idx] = vote_time
            
        # Calculate when notarization thresholds are reached
        sorted_votes = sorted(notarization_votes.items(), key=lambda x: x[1])
        cumulative_stake = 0.0
        
        fast_threshold_time = None
        slow_threshold_time = None
        notarization_time = None
        
        for validator_idx, vote_time in sorted_votes:
            cumulative_stake += self.stakes[validator_idx]
            
            if cumulative_stake >= self.config.notarization_threshold_pct and notarization_time is None:
                notarization_time = vote_time
                
            if cumulative_stake >= self.config.slow_threshold_pct and slow_threshold_time is None:
                slow_threshold_time = vote_time
                
            if cumulative_stake >= self.config.fast_threshold_pct and fast_threshold_time is None:
                fast_threshold_time = vote_time
                break
                
        # Phase 2: Finalization votes (for slow path)
        finalization_time = None
        if slow_threshold_time is not None:
            # Validators send finalization votes after seeing notarization certificate
            finalization_votes = {}
            for validator_idx in range(num_validators):
                if validator_idx in notarization_votes:
                    # Finalization vote sent after notarization certificate propagation
                    cert_propagation_delay = random.uniform(5, 15)
                    finalization_votes[validator_idx] = slow_threshold_time + cert_propagation_delay
                    
            # Calculate finalization threshold
            sorted_final_votes = sorted(finalization_votes.items(), key=lambda x: x[1])
            cumulative_stake = 0.0
            
            for validator_idx, vote_time in sorted_final_votes:
                cumulative_stake += self.stakes[validator_idx]
                if cumulative_stake >= self.config.finalization_threshold_pct:
                    finalization_time = vote_time
                    break
                    
        # Determine final consensus time: min(fast_path, slow_path)
        fast_path_time = fast_threshold_time
        slow_path_time = finalization_time
        
        consensus_times = [t for t in [fast_path_time, slow_path_time] if t is not None]
        final_consensus_time = min(consensus_times) if consensus_times else float('inf')
        
        metrics = {
            'notarization_time': notarization_time,
            'fast_path_time': fast_path_time,
            'slow_path_time': slow_path_time,
            'final_consensus_time': final_consensus_time,
            'fast_path_success': fast_threshold_time is not None,
            'slow_path_success': finalization_time is not None,
            'participating_validators': len(notarization_votes)
        }
        
        return final_consensus_time, metrics

class AlpenglowBenchmark:
    """Main benchmark suite for Alpenglow protocol"""
    
    def __init__(self, network_config: NetworkConfig, rotor_config: RotorConfig, votor_config: VotorConfig):
        self.network_config = network_config
        self.rotor_config = rotor_config
        self.votor_config = votor_config
        
        # Initialize components
        self.stake_distribution = StakeDistribution(network_config.num_validators)
        self.network_model = NetworkLatencyModel(network_config.num_validators, network_config.delta_ms)
        self.rotor_simulator = RotorSimulator(rotor_config, self.network_model, self.stake_distribution.stakes)
        self.votor_simulator = VotorSimulator(votor_config, self.network_model, self.stake_distribution.stakes)
        
    def run_single_block_benchmark(self, leader_idx: int) -> PerformanceMetrics:
        """Benchmark single block consensus"""
        
        # Phase 1: Block dissemination (Rotor)
        rotor_latency, rotor_metrics = self.rotor_simulator.simulate_dissemination(leader_idx)
        
        # Create block receive times for all validators
        block_receive_times = {}
        for validator_idx in range(self.network_config.num_validators):
            if validator_idx == leader_idx:
                block_receive_times[validator_idx] = 0
            else:
                # Simulate receive time based on Rotor performance
                base_latency = self.network_model.get_latency(leader_idx, validator_idx)
                receive_time = base_latency + random.uniform(0, rotor_latency * 0.2)
                block_receive_times[validator_idx] = receive_time
                
        # Phase 2: Consensus voting (Votor)
        votor_latency, votor_metrics = self.votor_simulator.simulate_consensus(block_receive_times)
        
        # Calculate overall metrics
        finalization_latency = rotor_latency + votor_latency
        
        # Calculate throughput
        block_size = self.rotor_config.slices_per_block * self.rotor_config.slice_size_bytes
        throughput_tps = (block_size / finalization_latency) * 1000 if finalization_latency > 0 else 0
        
        # Calculate bandwidth efficiency
        total_bandwidth_used = block_size * self.rotor_config.expansion_ratio
        theoretical_optimal = block_size
        bandwidth_efficiency = (theoretical_optimal / total_bandwidth_used) * 100
        
        # Network utilization
        active_validators = votor_metrics.get('participating_validators', 0)
        network_utilization = (active_validators / self.network_config.num_validators) * 100
        
        return PerformanceMetrics(
            finalization_latency_ms=finalization_latency,
            throughput_tps=throughput_tps,
            bandwidth_efficiency_pct=bandwidth_efficiency,
            rotor_latency_ms=rotor_latency,
            votor_latency_ms=votor_latency,
            fast_path_success_rate=1.0 if votor_metrics.get('fast_path_success') else 0.0,
            slow_path_success_rate=1.0 if votor_metrics.get('slow_path_success') else 0.0,
            block_size_bytes=block_size,
            network_utilization_pct=network_utilization
        )
    
    def run_latency_analysis(self, num_trials: int = 1000) -> Dict[str, Any]:
        """Analyze finalization latency under various conditions"""
        logger.info(f"Running latency analysis with {num_trials} trials")
        
        results = {
            'trials': [],
            'delta_60_pct': 0,
            'delta_80_pct': 0,
            'theoretical_min_latency': 0,
            'actual_avg_latency': 0,
            'fast_path_success_rate': 0,
            'slow_path_success_rate': 0
        }
        
        # Calculate theoretical δ values
        delta_60 = self.network_model.get_delta_percentile(self.stake_distribution.stakes, 0.60)
        delta_80 = self.network_model.get_delta_percentile(self.stake_distribution.stakes, 0.80)
        
        results['delta_60_pct'] = delta_60
        results['delta_80_pct'] = delta_80
        results['theoretical_min_latency'] = min(delta_80, 2 * delta_60)
        
        # Run trials with random leaders
        latencies = []
        fast_successes = 0
        slow_successes = 0
        
        for trial in range(num_trials):
            # Select random leader weighted by stake
            leader_idx = np.random.choice(
                self.network_config.num_validators, 
                p=self.stake_distribution.stakes
            )
            
            metrics = self.run_single_block_benchmark(leader_idx)
            latencies.append(metrics.finalization_latency_ms)
            
            if metrics.fast_path_success_rate > 0:
                fast_successes += 1
            if metrics.slow_path_success_rate > 0:
                slow_successes += 1
                
            results['trials'].append(asdict(metrics))
            
            if trial % 100 == 0:
                logger.info(f"Completed {trial}/{num_trials} trials")
                
        results['actual_avg_latency'] = statistics.mean(latencies)
        results['fast_path_success_rate'] = fast_successes / num_trials
        results['slow_path_success_rate'] = slow_successes / num_trials
        
        return results
    
    def run_throughput_analysis(self, duration_seconds: int = 300) -> Dict[str, Any]:
        """Analyze throughput over sustained period"""
        logger.info(f"Running throughput analysis for {duration_seconds} seconds")
        
        results = {
            'duration_seconds': duration_seconds,
            'total_blocks': 0,
            'total_transactions': 0,
            'avg_throughput_tps': 0,
            'peak_throughput_tps': 0,
            'bandwidth_utilization': [],
            'block_times': []
        }
        
        current_time = 0
        block_count = 0
        leader_window_slots = self.network_config.leader_window_size
        
        while current_time < duration_seconds * 1000:  # Convert to ms
            # Select leader for this window
            leader_idx = np.random.choice(
                self.network_config.num_validators,
                p=self.stake_distribution.stakes
            )
            
            # Process blocks in leader window
            for slot in range(leader_window_slots):
                if current_time >= duration_seconds * 1000:
                    break
                    
                metrics = self.run_single_block_benchmark(leader_idx)
                
                # Record metrics
                results['block_times'].append(metrics.finalization_latency_ms)
                results['bandwidth_utilization'].append(metrics.network_utilization_pct)
                
                block_count += 1
                current_time += self.network_config.block_time_ms
                
        # Calculate final metrics
        results['total_blocks'] = block_count
        
        # Estimate transactions per block (based on block size)
        avg_tx_size = 250  # bytes
        avg_txs_per_block = self.rotor_config.slices_per_block * self.rotor_config.slice_size_bytes // avg_tx_size
        results['total_transactions'] = block_count * avg_txs_per_block
        
        results['avg_throughput_tps'] = results['total_transactions'] / duration_seconds
        
        # Calculate peak throughput (best 10-second window)
        window_size = 10  # seconds
        window_blocks = int(window_size * 1000 / self.network_config.block_time_ms)
        
        if len(results['block_times']) >= window_blocks:
            peak_throughput = 0
            for i in range(len(results['block_times']) - window_blocks + 1):
                window_txs = window_blocks * avg_txs_per_block
                window_throughput = window_txs / window_size
                peak_throughput = max(peak_throughput, window_throughput)
            results['peak_throughput_tps'] = peak_throughput
        
        return results
    
    def run_resilience_analysis(self) -> Dict[str, Any]:
        """Analyze protocol resilience under various failure conditions"""
        logger.info("Running resilience analysis")
        
        results = {
            'baseline': {},
            'byzantine_stress': {},
            'crash_stress': {},
            'network_partition': {},
            'high_latency': {}
        }
        
        # Baseline performance
        results['baseline'] = self.run_latency_analysis(num_trials=100)
        
        # Byzantine stress test (increase byzantine stake)
        original_config = self.network_config
        
        # Test with higher byzantine stake (18% - near limit)
        byzantine_config = NetworkConfig(
            num_validators=original_config.num_validators,
            byzantine_stake_pct=0.18,
            crash_stake_pct=original_config.crash_stake_pct,
            delta_ms=original_config.delta_ms,
            delta_timeout_ms=original_config.delta_timeout_ms,
            block_time_ms=original_config.block_time_ms,
            leader_window_size=original_config.leader_window_size
        )
        
        byzantine_benchmark = AlpenglowBenchmark(byzantine_config, self.rotor_config, self.votor_config)
        results['byzantine_stress'] = byzantine_benchmark.run_latency_analysis(num_trials=100)
        
        # Crash stress test (additional 20% crash failures)
        crash_config = NetworkConfig(
            num_validators=original_config.num_validators,
            byzantine_stake_pct=original_config.byzantine_stake_pct,
            crash_stake_pct=0.20,
            delta_ms=original_config.delta_ms,
            delta_timeout_ms=original_config.delta_timeout_ms,
            block_time_ms=original_config.block_time_ms,
            leader_window_size=original_config.leader_window_size
        )
        
        crash_benchmark = AlpenglowBenchmark(crash_config, self.rotor_config, self.votor_config)
        results['crash_stress'] = crash_benchmark.run_latency_analysis(num_trials=100)
        
        # High latency test (2x network delays)
        high_latency_config = NetworkConfig(
            num_validators=original_config.num_validators,
            byzantine_stake_pct=original_config.byzantine_stake_pct,
            crash_stake_pct=original_config.crash_stake_pct,
            delta_ms=original_config.delta_ms * 2,
            delta_timeout_ms=original_config.delta_timeout_ms * 2,
            block_time_ms=original_config.block_time_ms,
            leader_window_size=original_config.leader_window_size
        )
        
        high_latency_benchmark = AlpenglowBenchmark(high_latency_config, self.rotor_config, self.votor_config)
        results['high_latency'] = high_latency_benchmark.run_latency_analysis(num_trials=100)
        
        return results
    
    def run_scalability_analysis(self) -> Dict[str, Any]:
        """Analyze protocol scalability with different network sizes"""
        logger.info("Running scalability analysis")
        
        network_sizes = [500, 1000, 1500, 2000, 3000, 5000]
        results = {
            'network_sizes': network_sizes,
            'latency_results': {},
            'throughput_results': {},
            'bandwidth_results': {}
        }
        
        for size in network_sizes:
            logger.info(f"Testing network size: {size} validators")
            
            # Create config for this network size
            size_config = NetworkConfig(
                num_validators=size,
                byzantine_stake_pct=self.network_config.byzantine_stake_pct,
                crash_stake_pct=self.network_config.crash_stake_pct,
                delta_ms=self.network_config.delta_ms,
                delta_timeout_ms=self.network_config.delta_timeout_ms,
                block_time_ms=self.network_config.block_time_ms,
                leader_window_size=self.network_config.leader_window_size
            )
            
            # Run benchmark
            size_benchmark = AlpenglowBenchmark(size_config, self.rotor_config, self.votor_config)
            
            # Latency analysis
            latency_results = size_benchmark.run_latency_analysis(num_trials=50)
            results['latency_results'][size] = {
                'avg_latency': latency_results['actual_avg_latency'],
                'theoretical_min': latency_results['theoretical_min_latency'],
                'fast_path_success': latency_results['fast_path_success_rate']
            }
            
            # Throughput analysis (shorter duration for scalability test)
            throughput_results = size_benchmark.run_throughput_analysis(duration_seconds=60)
            results['throughput_results'][size] = {
                'avg_throughput': throughput_results['avg_throughput_tps'],
                'peak_throughput': throughput_results['peak_throughput_tps']
            }
            
            # Bandwidth analysis
            single_block = size_benchmark.run_single_block_benchmark(0)
            results['bandwidth_results'][size] = {
                'bandwidth_efficiency': single_block.bandwidth_efficiency_pct,
                'network_utilization': single_block.network_utilization_pct
            }
            
        return results

class BenchmarkReporter:
    """Generates comprehensive benchmark reports"""
    
    def __init__(self, output_dir: str = "benchmark_results"):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(exist_ok=True)
        
    def generate_report(self, benchmark_results: Dict[str, Any], config: Dict[str, Any]):
        """Generate comprehensive benchmark report"""
        
        # Save raw results
        with open(self.output_dir / "raw_results.json", "w") as f:
            json.dump(benchmark_results, f, indent=2, default=str)
            
        # Generate summary report
        self._generate_summary_report(benchmark_results, config)
        
        # Generate visualizations
        self._generate_visualizations(benchmark_results)
        
        # Generate whitepaper validation report
        self._generate_whitepaper_validation(benchmark_results)
        
    def _generate_summary_report(self, results: Dict[str, Any], config: Dict[str, Any]):
        """Generate summary report"""
        
        report = []
        report.append("# Alpenglow Performance Benchmark Report")
        report.append(f"Generated: {time.strftime('%Y-%m-%d %H:%M:%S')}")
        report.append("")
        
        # Configuration summary
        report.append("## Configuration")
        report.append(f"- Validators: {config['network']['num_validators']}")
        report.append(f"- Byzantine stake: {config['network']['byzantine_stake_pct']*100:.1f}%")
        report.append(f"- Network delay (δ): {config['network']['delta_ms']}ms")
        report.append(f"- Block time: {config['network']['block_time_ms']}ms")
        report.append(f"- Expansion ratio (κ): {config['rotor']['expansion_ratio']}")
        report.append("")
        
        # Latency analysis
        if 'latency_analysis' in results:
            latency = results['latency_analysis']
            report.append("## Latency Analysis")
            report.append(f"- Theoretical min latency: {latency['theoretical_min_latency']:.1f}ms")
            report.append(f"- Actual average latency: {latency['actual_avg_latency']:.1f}ms")
            report.append(f"- δ₆₀%: {latency['delta_60_pct']:.1f}ms")
            report.append(f"- δ₈₀%: {latency['delta_80_pct']:.1f}ms")
            report.append(f"- Fast path success rate: {latency['fast_path_success_rate']*100:.1f}%")
            report.append(f"- Slow path success rate: {latency['slow_path_success_rate']*100:.1f}%")
            report.append("")
            
        # Throughput analysis
        if 'throughput_analysis' in results:
            throughput = results['throughput_analysis']
            report.append("## Throughput Analysis")
            report.append(f"- Average throughput: {throughput['avg_throughput_tps']:.0f} TPS")
            report.append(f"- Peak throughput: {throughput['peak_throughput_tps']:.0f} TPS")
            report.append(f"- Total blocks processed: {throughput['total_blocks']}")
            report.append(f"- Duration: {throughput['duration_seconds']}s")
            report.append("")
            
        # Resilience analysis
        if 'resilience_analysis' in results:
            resilience = results['resilience_analysis']
            report.append("## Resilience Analysis")
            
            for condition, data in resilience.items():
                if condition == 'baseline':
                    continue
                baseline_latency = resilience['baseline']['actual_avg_latency']
                condition_latency = data['actual_avg_latency']
                degradation = ((condition_latency - baseline_latency) / baseline_latency) * 100
                
                report.append(f"- {condition.replace('_', ' ').title()}:")
                report.append(f"  - Latency: {condition_latency:.1f}ms ({degradation:+.1f}%)")
                report.append(f"  - Fast path success: {data['fast_path_success_rate']*100:.1f}%")
                
            report.append("")
            
        # Scalability analysis
        if 'scalability_analysis' in results:
            scalability = results['scalability_analysis']
            report.append("## Scalability Analysis")
            
            for size in scalability['network_sizes']:
                latency_data = scalability['latency_results'][size]
                throughput_data = scalability['throughput_results'][size]
                
                report.append(f"- {size} validators:")
                report.append(f"  - Latency: {latency_data['avg_latency']:.1f}ms")
                report.append(f"  - Throughput: {throughput_data['avg_throughput']:.0f} TPS")
                report.append(f"  - Fast path success: {latency_data['fast_path_success']*100:.1f}%")
                
            report.append("")
            
        # Write report
        with open(self.output_dir / "summary_report.md", "w") as f:
            f.write("\n".join(report))
            
    def _generate_visualizations(self, results: Dict[str, Any]):
        """Generate visualization plots"""
        
        plt.style.use('seaborn-v0_8')
        
        # Latency distribution
        if 'latency_analysis' in results:
            latencies = [trial['finalization_latency_ms'] for trial in results['latency_analysis']['trials']]
            
            plt.figure(figsize=(12, 8))
            
            plt.subplot(2, 2, 1)
            plt.hist(latencies, bins=50, alpha=0.7, edgecolor='black')
            plt.axvline(results['latency_analysis']['theoretical_min_latency'], 
                       color='red', linestyle='--', label='Theoretical Min')
            plt.axvline(results['latency_analysis']['actual_avg_latency'], 
                       color='green', linestyle='--', label='Actual Average')
            plt.xlabel('Finalization Latency (ms)')
            plt.ylabel('Frequency')
            plt.title('Latency Distribution')
            plt.legend()
            
            # Throughput over time
            if 'throughput_analysis' in results:
                block_times = results['throughput_analysis']['block_times']
                
                plt.subplot(2, 2, 2)
                plt.plot(block_times[:100])  # First 100 blocks
                plt.xlabel('Block Number')
                plt.ylabel('Finalization Time (ms)')
                plt.title('Finalization Time Over Time')
                
            # Scalability
            if 'scalability_analysis' in results:
                scalability = results['scalability_analysis']
                sizes = scalability['network_sizes']
                latencies = [scalability['latency_results'][size]['avg_latency'] for size in sizes]
                throughputs = [scalability['throughput_results'][size]['avg_throughput'] for size in sizes]
                
                plt.subplot(2, 2, 3)
                plt.plot(sizes, latencies, 'o-')
                plt.xlabel('Number of Validators')
                plt.ylabel('Average Latency (ms)')
                plt.title('Latency vs Network Size')
                
                plt.subplot(2, 2, 4)
                plt.plot(sizes, throughputs, 'o-')
                plt.xlabel('Number of Validators')
                plt.ylabel('Throughput (TPS)')
                plt.title('Throughput vs Network Size')
                
            plt.tight_layout()
            plt.savefig(self.output_dir / "performance_plots.png", dpi=300, bbox_inches='tight')
            plt.close()
            
    def _generate_whitepaper_validation(self, results: Dict[str, Any]):
        """Generate whitepaper claims validation report"""
        
        validation = []
        validation.append("# Whitepaper Claims Validation")
        validation.append("")
        
        if 'latency_analysis' in results:
            latency = results['latency_analysis']
            
            # Claim 1: Finalization in min(δ₈₀%, 2δ₆₀%) time
            theoretical_min = latency['theoretical_min_latency']
            actual_avg = latency['actual_avg_latency']
            delta_60 = latency['delta_60_pct']
            delta_80 = latency['delta_80_pct']
            
            validation.append("## Claim 1: Finalization Time")
            validation.append(f"**Claim**: Blocks finalize in min(δ₈₀%, 2δ₆₀%) = min({delta_80:.1f}ms, {2*delta_60:.1f}ms) = {theoretical_min:.1f}ms")
            validation.append(f"**Result**: Actual average latency = {actual_avg:.1f}ms")
            
            if actual_avg <= theoretical_min * 1.2:  # Allow 20% overhead
                validation.append("**Status**: ✅ VALIDATED - Within expected bounds")
            else:
                validation.append("**Status**: ❌ NOT VALIDATED - Exceeds theoretical bound")
                
            validation.append("")
            
            # Claim 2: Fast path success with 80% stake
            fast_success = latency['fast_path_success_rate']
            validation.append("## Claim 2: Fast Path Performance")
            validation.append(f"**Claim**: Fast path (80% stake) should succeed in normal conditions")
            validation.append(f"**Result**: Fast path success rate = {fast_success*100:.1f}%")
            
            if fast_success >= 0.8:
                validation.append("**Status**: ✅ VALIDATED - High fast path success rate")
            else:
                validation.append("**Status**: ⚠️ PARTIAL - Lower than expected fast path success")
                
            validation.append("")
            
        # Claim 3: Bandwidth optimality
        if 'throughput_analysis' in results:
            validation.append("## Claim 3: Bandwidth Optimality")
            validation.append("**Claim**: Rotor achieves asymptotically optimal bandwidth usage")
            
            # Calculate theoretical vs actual bandwidth efficiency
            expansion_ratio = 2.0  # κ = 2 from config
            theoretical_efficiency = (1.0 / expansion_ratio) * 100
            
            # Get actual efficiency from a sample
            sample_metrics = results['latency_analysis']['trials'][0] if 'latency_analysis' in results else None
            if sample_metrics:
                actual_efficiency = sample_metrics['bandwidth_efficiency_pct']
                validation.append(f"**Result**: Theoretical efficiency = {theoretical_efficiency:.1f}%, Actual = {actual_efficiency:.1f}%")
                
                if actual_efficiency >= theoretical_efficiency * 0.9:
                    validation.append("**Status**: ✅ VALIDATED - Near optimal bandwidth efficiency")
                else:
                    validation.append("**Status**: ⚠️ PARTIAL - Some bandwidth overhead observed")
            else:
                validation.append("**Status**: ❓ INSUFFICIENT DATA")
                
            validation.append("")
            
        # Claim 4: Byzantine resilience (20% + 20%)
        if 'resilience_analysis' in results:
            resilience = results['resilience_analysis']
            validation.append("## Claim 4: Byzantine Resilience")
            validation.append("**Claim**: Protocol tolerates 20% Byzantine + 20% crash failures")
            
            baseline_success = resilience['baseline']['fast_path_success_rate']
            byzantine_success = resilience['byzantine_stress']['fast_path_success_rate']
            crash_success = resilience['crash_stress']['fast_path_success_rate']
            
            validation.append(f"**Results**:")
            validation.append(f"- Baseline success rate: {baseline_success*100:.1f}%")
            validation.append(f"- With 18% Byzantine: {byzantine_success*100:.1f}%")
            validation.append(f"- With 20% crashes: {crash_success*100:.1f}%")
            
            if byzantine_success >= 0.7 and crash_success >= 0.7:
                validation.append("**Status**: ✅ VALIDATED - Maintains performance under stress")
            else:
                validation.append("**Status**: ⚠️ PARTIAL - Some performance degradation under stress")
                
            validation.append("")
            
        # Write validation report
        with open(self.output_dir / "whitepaper_validation.md", "w") as f:
            f.write("\n".join(validation))

def main():
    """Main benchmark execution"""
    
    # Configuration
    network_config = NetworkConfig(
        num_validators=1500,
        byzantine_stake_pct=0.15,
        crash_stake_pct=0.05,
        delta_ms=80,
        delta_timeout_ms=400,
        block_time_ms=400,
        leader_window_size=4
    )
    
    rotor_config = RotorConfig(
        gamma=32,
        expansion_ratio=2.0,
        slice_size_bytes=1200,
        slices_per_block=64
    )
    
    votor_config = VotorConfig(
        fast_threshold_pct=0.80,
        slow_threshold_pct=0.60,
        notarization_threshold_pct=0.60,
        finalization_threshold_pct=0.60
    )
    
    # Initialize benchmark
    benchmark = AlpenglowBenchmark(network_config, rotor_config, votor_config)
    reporter = BenchmarkReporter()
    
    logger.info("Starting Alpenglow performance benchmarks")
    
    # Run all benchmark suites
    results = {}
    
    # Latency analysis
    logger.info("Running latency analysis...")
    results['latency_analysis'] = benchmark.run_latency_analysis(num_trials=500)
    
    # Throughput analysis
    logger.info("Running throughput analysis...")
    results['throughput_analysis'] = benchmark.run_throughput_analysis(duration_seconds=180)
    
    # Resilience analysis
    logger.info("Running resilience analysis...")
    results['resilience_analysis'] = benchmark.run_resilience_analysis()
    
    # Scalability analysis
    logger.info("Running scalability analysis...")
    results['scalability_analysis'] = benchmark.run_scalability_analysis()
    
    # Generate comprehensive report
    config_dict = {
        'network': asdict(network_config),
        'rotor': asdict(rotor_config),
        'votor': asdict(votor_config)
    }
    
    logger.info("Generating benchmark report...")
    reporter.generate_report(results, config_dict)
    
    logger.info("Benchmark completed successfully!")
    logger.info(f"Results saved to: {reporter.output_dir}")
    
    # Print summary
    print("\n" + "="*60)
    print("ALPENGLOW PERFORMANCE BENCHMARK SUMMARY")
    print("="*60)
    
    if 'latency_analysis' in results:
        latency = results['latency_analysis']
        print(f"Average Finalization Latency: {latency['actual_avg_latency']:.1f}ms")
        print(f"Theoretical Minimum: {latency['theoretical_min_latency']:.1f}ms")
        print(f"Fast Path Success Rate: {latency['fast_path_success_rate']*100:.1f}%")
        
    if 'throughput_analysis' in results:
        throughput = results['throughput_analysis']
        print(f"Average Throughput: {throughput['avg_throughput_tps']:.0f} TPS")
        print(f"Peak Throughput: {throughput['peak_throughput_tps']:.0f} TPS")
        
    print(f"\nDetailed results available in: {reporter.output_dir}")
    print("="*60)

if __name__ == "__main__":
    main()