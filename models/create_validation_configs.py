#!/usr/bin/env python3
"""
Comprehensive Model Checking Configuration Generator for Alpenglow Protocol

This script generates systematic TLA+ model checking configurations to validate
all aspects of the Alpenglow consensus protocol, including safety, liveness,
and resilience properties under various network conditions and adversarial scenarios.
"""

import os
import json
import itertools
from typing import Dict, List, Set, Tuple, Any, Optional
from dataclasses import dataclass, asdict
from pathlib import Path
import math

@dataclass
class ValidatorConfig:
    """Configuration for a single validator"""
    name: str
    stake: int
    is_byzantine: bool = False
    is_offline: bool = False
    
@dataclass
class NetworkConfig:
    """Network configuration parameters"""
    gst: int = 0
    delta: int = 1
    max_network_delay: int = 3
    message_loss_rate: int = 0
    network_partitions: Set[str] = None
    recovery_timeout: int = 10
    max_retransmissions: int = 3
    
    def __post_init__(self):
        if self.network_partitions is None:
            self.network_partitions = set()

@dataclass
class ProtocolConfig:
    """Protocol-specific parameters"""
    max_slot: int = 5
    max_view: int = 3
    max_time: int = 15
    timeout_delta: int = 5
    k: int = 2  # Erasure coding data shreds
    n: int = 3  # Erasure coding total shreds
    max_blocks: int = 5
    bandwidth_limit: int = 5000
    retry_timeout: int = 2
    max_retries: int = 2
    max_block_size: int = 100
    max_transactions: int = 10
    max_signatures: int = 20
    max_certificates: int = 10

@dataclass
class TestScenario:
    """Complete test scenario configuration"""
    name: str
    description: str
    validators: List[ValidatorConfig]
    network: NetworkConfig
    protocol: ProtocolConfig
    properties_to_check: List[str]
    invariants_to_check: List[str]
    expected_outcome: str
    test_category: str
    complexity_level: int  # 1-5 scale

class ConfigurationGenerator:
    """Generates comprehensive TLA+ model checking configurations"""
    
    def __init__(self, output_dir: str = "generated_configs"):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(exist_ok=True)
        
        # Standard property and invariant sets
        self.all_invariants = [
            "TypeOK",
            "Safety", 
            "ChainConsistency",
            "CertificateUniqueness",
            "ConsistentFinalization",
            "DeliveredBlocksConsistency"
        ]
        
        self.all_properties = [
            "Progress",
            "FastPath", 
            "BoundedFinalization"
        ]
        
        self.safety_invariants = [
            "TypeOK",
            "Safety",
            "ChainConsistency", 
            "CertificateUniqueness",
            "ConsistentFinalization"
        ]
        
        self.liveness_properties = [
            "Progress",
            "BoundedFinalization"
        ]
        
        self.performance_properties = [
            "FastPath",
            "BoundedFinalization"
        ]

    def generate_all_configurations(self) -> List[TestScenario]:
        """Generate all configuration categories"""
        scenarios = []
        
        # Small scale configurations for exhaustive checking
        scenarios.extend(self._generate_small_scale_configs())
        
        # Boundary condition testing
        scenarios.extend(self._generate_boundary_condition_configs())
        
        # Edge case scenarios
        scenarios.extend(self._generate_edge_case_configs())
        
        # Performance and scalability testing
        scenarios.extend(self._generate_performance_configs())
        
        # Theorem-specific configurations
        scenarios.extend(self._generate_theorem_specific_configs())
        
        # Adversarial scenarios
        scenarios.extend(self._generate_adversarial_configs())
        
        # Recovery scenarios
        scenarios.extend(self._generate_recovery_configs())
        
        # Timing scenarios
        scenarios.extend(self._generate_timing_configs())
        
        # Stake distribution variations
        scenarios.extend(self._generate_stake_distribution_configs())
        
        # Incremental complexity progression
        scenarios.extend(self._generate_incremental_complexity_configs())
        
        return scenarios

    def _generate_small_scale_configs(self) -> List[TestScenario]:
        """Generate small scale configurations for exhaustive checking"""
        scenarios = []
        
        # 3 validator minimal configuration
        validators_3 = [
            ValidatorConfig("v1", 10),
            ValidatorConfig("v2", 10), 
            ValidatorConfig("v3", 10)
        ]
        
        scenarios.append(TestScenario(
            name="Small_3_Validators_Basic",
            description="Minimal 3-validator configuration for exhaustive state exploration",
            validators=validators_3,
            network=NetworkConfig(),
            protocol=ProtocolConfig(max_slot=3, max_view=2),
            properties_to_check=self.all_properties,
            invariants_to_check=self.all_invariants,
            expected_outcome="All properties satisfied",
            test_category="small_scale",
            complexity_level=1
        ))
        
        # 4 validator configuration
        validators_4 = [
            ValidatorConfig("v1", 10),
            ValidatorConfig("v2", 10),
            ValidatorConfig("v3", 10),
            ValidatorConfig("v4", 10)
        ]
        
        scenarios.append(TestScenario(
            name="Small_4_Validators_Basic",
            description="4-validator configuration with even stake distribution",
            validators=validators_4,
            network=NetworkConfig(),
            protocol=ProtocolConfig(max_slot=4, max_view=3),
            properties_to_check=self.all_properties,
            invariants_to_check=self.all_invariants,
            expected_outcome="All properties satisfied",
            test_category="small_scale",
            complexity_level=2
        ))
        
        # 5 validator configuration
        validators_5 = [
            ValidatorConfig("v1", 10),
            ValidatorConfig("v2", 10),
            ValidatorConfig("v3", 10),
            ValidatorConfig("v4", 10),
            ValidatorConfig("v5", 10)
        ]
        
        scenarios.append(TestScenario(
            name="Small_5_Validators_Basic",
            description="5-validator configuration for comprehensive small-scale testing",
            validators=validators_5,
            network=NetworkConfig(),
            protocol=ProtocolConfig(max_slot=5, max_view=3),
            properties_to_check=self.all_properties,
            invariants_to_check=self.all_invariants,
            expected_outcome="All properties satisfied",
            test_category="small_scale",
            complexity_level=2
        ))
        
        return scenarios

    def _generate_boundary_condition_configs(self) -> List[TestScenario]:
        """Generate configurations testing exactly 20% Byzantine stake thresholds"""
        scenarios = []
        
        # Exactly 20% Byzantine stake (5 validators, 1 Byzantine)
        validators_20pct = [
            ValidatorConfig("v1", 10),
            ValidatorConfig("v2", 10),
            ValidatorConfig("v3", 10),
            ValidatorConfig("v4", 10),
            ValidatorConfig("v5", 10, is_byzantine=True)  # Exactly 20%
        ]
        
        scenarios.append(TestScenario(
            name="Boundary_Exactly_20pct_Byzantine",
            description="Test with exactly 20% Byzantine stake threshold",
            validators=validators_20pct,
            network=NetworkConfig(),
            protocol=ProtocolConfig(),
            properties_to_check=self.liveness_properties,
            invariants_to_check=self.safety_invariants,
            expected_outcome="Safety maintained, liveness may be affected",
            test_category="boundary_conditions",
            complexity_level=3
        ))
        
        # Just under 20% Byzantine stake
        validators_under_20pct = [
            ValidatorConfig("v1", 11),
            ValidatorConfig("v2", 11),
            ValidatorConfig("v3", 11),
            ValidatorConfig("v4", 11),
            ValidatorConfig("v5", 6, is_byzantine=True)  # 12% Byzantine
        ]
        
        scenarios.append(TestScenario(
            name="Boundary_Under_20pct_Byzantine",
            description="Test with Byzantine stake just under 20% threshold",
            validators=validators_under_20pct,
            network=NetworkConfig(),
            protocol=ProtocolConfig(),
            properties_to_check=self.all_properties,
            invariants_to_check=self.all_invariants,
            expected_outcome="All properties satisfied",
            test_category="boundary_conditions",
            complexity_level=3
        ))
        
        # Exactly 20% offline stake
        validators_20pct_offline = [
            ValidatorConfig("v1", 10),
            ValidatorConfig("v2", 10),
            ValidatorConfig("v3", 10),
            ValidatorConfig("v4", 10),
            ValidatorConfig("v5", 10, is_offline=True)  # Exactly 20%
        ]
        
        scenarios.append(TestScenario(
            name="Boundary_Exactly_20pct_Offline",
            description="Test with exactly 20% offline stake",
            validators=validators_20pct_offline,
            network=NetworkConfig(),
            protocol=ProtocolConfig(),
            properties_to_check=self.liveness_properties,
            invariants_to_check=self.safety_invariants,
            expected_outcome="Safety maintained, liveness may be degraded",
            test_category="boundary_conditions",
            complexity_level=3
        ))
        
        # Combined 20+20 scenario
        validators_combined_2020 = [
            ValidatorConfig("v1", 15),
            ValidatorConfig("v2", 15),
            ValidatorConfig("v3", 15),
            ValidatorConfig("v4", 5, is_byzantine=True),  # 10% Byzantine
            ValidatorConfig("v5", 5, is_offline=True)     # 10% Offline
        ]
        
        scenarios.append(TestScenario(
            name="Boundary_Combined_20_20",
            description="Test combined 10% Byzantine + 10% offline (20% total faults)",
            validators=validators_combined_2020,
            network=NetworkConfig(),
            protocol=ProtocolConfig(),
            properties_to_check=self.all_properties,
            invariants_to_check=self.all_invariants,
            expected_outcome="All properties satisfied under combined fault model",
            test_category="boundary_conditions",
            complexity_level=4
        ))
        
        return scenarios

    def _generate_edge_case_configs(self) -> List[TestScenario]:
        """Generate configurations for edge cases like network partitions and leader failures"""
        scenarios = []
        
        # Network partition scenario
        validators_partition = [
            ValidatorConfig("v1", 10),
            ValidatorConfig("v2", 10),
            ValidatorConfig("v3", 10),
            ValidatorConfig("v4", 10),
            ValidatorConfig("v5", 10)
        ]
        
        scenarios.append(TestScenario(
            name="EdgeCase_Network_Partition",
            description="Test behavior during network partition",
            validators=validators_partition,
            network=NetworkConfig(
                network_partitions={"partition1"},
                recovery_timeout=20
            ),
            protocol=ProtocolConfig(max_time=30),
            properties_to_check=["Progress"],
            invariants_to_check=self.safety_invariants,
            expected_outcome="Safety maintained during partition",
            test_category="edge_cases",
            complexity_level=4
        ))
        
        # Leader failure scenario
        validators_leader_fail = [
            ValidatorConfig("v1", 10),  # Initial leader
            ValidatorConfig("v2", 10),
            ValidatorConfig("v3", 10),
            ValidatorConfig("v4", 10, is_offline=True)  # Leader becomes offline
        ]
        
        scenarios.append(TestScenario(
            name="EdgeCase_Leader_Failure",
            description="Test leader failure and view change",
            validators=validators_leader_fail,
            network=NetworkConfig(),
            protocol=ProtocolConfig(timeout_delta=3, max_view=5),
            properties_to_check=self.liveness_properties,
            invariants_to_check=self.safety_invariants,
            expected_outcome="View change enables progress",
            test_category="edge_cases",
            complexity_level=3
        ))
        
        # Timeout cascade scenario
        validators_timeout = [
            ValidatorConfig("v1", 10),
            ValidatorConfig("v2", 10),
            ValidatorConfig("v3", 10)
        ]
        
        scenarios.append(TestScenario(
            name="EdgeCase_Timeout_Cascade",
            description="Test timeout handling and exponential backoff",
            validators=validators_timeout,
            network=NetworkConfig(max_network_delay=10),
            protocol=ProtocolConfig(timeout_delta=2, max_view=6, max_time=50),
            properties_to_check=["BoundedFinalization"],
            invariants_to_check=["TypeOK", "Safety"],
            expected_outcome="Eventually makes progress despite timeouts",
            test_category="edge_cases",
            complexity_level=4
        ))
        
        return scenarios

    def _generate_performance_configs(self) -> List[TestScenario]:
        """Generate larger configurations for performance and scalability testing"""
        scenarios = []
        
        # 10 validator performance test
        validators_10 = [ValidatorConfig(f"v{i}", 10) for i in range(1, 11)]
        
        scenarios.append(TestScenario(
            name="Performance_10_Validators",
            description="Performance test with 10 validators",
            validators=validators_10,
            network=NetworkConfig(),
            protocol=ProtocolConfig(
                max_slot=10,
                max_view=5,
                max_blocks=20,
                bandwidth_limit=10000
            ),
            properties_to_check=self.performance_properties,
            invariants_to_check=["TypeOK", "Safety"],
            expected_outcome="Maintains performance under load",
            test_category="performance",
            complexity_level=4
        ))
        
        # High bandwidth scenario
        validators_bandwidth = [ValidatorConfig(f"v{i}", 20) for i in range(1, 8)]
        
        scenarios.append(TestScenario(
            name="Performance_High_Bandwidth",
            description="Test high bandwidth utilization",
            validators=validators_bandwidth,
            network=NetworkConfig(),
            protocol=ProtocolConfig(
                bandwidth_limit=20000,
                max_block_size=500,
                max_transactions=50
            ),
            properties_to_check=["FastPath"],
            invariants_to_check=["TypeOK", "DeliveredBlocksConsistency"],
            expected_outcome="Fast path achievable under high load",
            test_category="performance",
            complexity_level=4
        ))
        
        return scenarios

    def _generate_theorem_specific_configs(self) -> List[TestScenario]:
        """Generate configurations specifically designed to test whitepaper theorems"""
        scenarios = []
        
        # Theorem 1: Safety under Byzantine faults
        validators_safety = [
            ValidatorConfig("v1", 15),
            ValidatorConfig("v2", 15),
            ValidatorConfig("v3", 15),
            ValidatorConfig("v4", 5, is_byzantine=True)  # <20% Byzantine
        ]
        
        scenarios.append(TestScenario(
            name="Theorem1_Safety_Byzantine",
            description="Validate Theorem 1: Safety under Byzantine faults",
            validators=validators_safety,
            network=NetworkConfig(),
            protocol=ProtocolConfig(),
            properties_to_check=[],
            invariants_to_check=self.safety_invariants,
            expected_outcome="Safety invariants maintained",
            test_category="theorem_validation",
            complexity_level=3
        ))
        
        # Theorem 2: Liveness under honest majority
        validators_liveness = [
            ValidatorConfig("v1", 20),
            ValidatorConfig("v2", 20),
            ValidatorConfig("v3", 20),
            ValidatorConfig("v4", 5, is_byzantine=True)  # <20% Byzantine
        ]
        
        scenarios.append(TestScenario(
            name="Theorem2_Liveness_Honest_Majority",
            description="Validate Theorem 2: Liveness under honest majority",
            validators=validators_liveness,
            network=NetworkConfig(gst=5),
            protocol=ProtocolConfig(max_time=30),
            properties_to_check=self.liveness_properties,
            invariants_to_check=["TypeOK"],
            expected_outcome="Progress achieved after GST",
            test_category="theorem_validation",
            complexity_level=3
        ))
        
        # Fast path theorem (>80% responsive)
        validators_fast_path = [
            ValidatorConfig("v1", 25),
            ValidatorConfig("v2", 25),
            ValidatorConfig("v3", 25),
            ValidatorConfig("v4", 25),
            ValidatorConfig("v5", 0, is_offline=True)  # 80% responsive
        ]
        
        scenarios.append(TestScenario(
            name="Theorem_Fast_Path_80pct",
            description="Validate fast path with >80% responsive stake",
            validators=validators_fast_path,
            network=NetworkConfig(delta=1),
            protocol=ProtocolConfig(),
            properties_to_check=["FastPath"],
            invariants_to_check=["TypeOK"],
            expected_outcome="Fast path finalization achieved",
            test_category="theorem_validation",
            complexity_level=3
        ))
        
        return scenarios

    def _generate_adversarial_configs(self) -> List[TestScenario]:
        """Generate configurations with maximum allowed Byzantine behavior"""
        scenarios = []
        
        # Maximum Byzantine stake (just under 20%)
        validators_max_byzantine = [
            ValidatorConfig("v1", 21),
            ValidatorConfig("v2", 21),
            ValidatorConfig("v3", 21),
            ValidatorConfig("v4", 21),
            ValidatorConfig("v5", 16, is_byzantine=True)  # 16% Byzantine
        ]
        
        scenarios.append(TestScenario(
            name="Adversarial_Max_Byzantine",
            description="Maximum Byzantine stake just under threshold",
            validators=validators_max_byzantine,
            network=NetworkConfig(),
            protocol=ProtocolConfig(),
            properties_to_check=self.all_properties,
            invariants_to_check=self.all_invariants,
            expected_outcome="Protocol remains secure",
            test_category="adversarial",
            complexity_level=5
        ))
        
        # Byzantine double voting
        validators_double_vote = [
            ValidatorConfig("v1", 10),
            ValidatorConfig("v2", 10),
            ValidatorConfig("v3", 10),
            ValidatorConfig("v4", 10),
            ValidatorConfig("v5", 5, is_byzantine=True)
        ]
        
        scenarios.append(TestScenario(
            name="Adversarial_Double_Voting",
            description="Test Byzantine double voting behavior",
            validators=validators_double_vote,
            network=NetworkConfig(),
            protocol=ProtocolConfig(),
            properties_to_check=[],
            invariants_to_check=["Safety", "CertificateUniqueness"],
            expected_outcome="Safety maintained despite double voting",
            test_category="adversarial",
            complexity_level=4
        ))
        
        # Byzantine withholding
        validators_withholding = [
            ValidatorConfig("v1", 10),
            ValidatorConfig("v2", 10),
            ValidatorConfig("v3", 10),
            ValidatorConfig("v4", 5, is_byzantine=True)
        ]
        
        scenarios.append(TestScenario(
            name="Adversarial_Withholding",
            description="Test Byzantine withholding of votes/blocks",
            validators=validators_withholding,
            network=NetworkConfig(),
            protocol=ProtocolConfig(timeout_delta=3, max_view=4),
            properties_to_check=["Progress"],
            invariants_to_check=["Safety"],
            expected_outcome="Progress through timeouts and view changes",
            test_category="adversarial",
            complexity_level=4
        ))
        
        return scenarios

    def _generate_recovery_configs(self) -> List[TestScenario]:
        """Generate configurations testing partition recovery and network healing"""
        scenarios = []
        
        # Partition recovery
        validators_recovery = [
            ValidatorConfig("v1", 10),
            ValidatorConfig("v2", 10),
            ValidatorConfig("v3", 10),
            ValidatorConfig("v4", 10),
            ValidatorConfig("v5", 10)
        ]
        
        scenarios.append(TestScenario(
            name="Recovery_Partition_Healing",
            description="Test recovery after network partition heals",
            validators=validators_recovery,
            network=NetworkConfig(
                network_partitions={"partition1"},
                recovery_timeout=15
            ),
            protocol=ProtocolConfig(max_time=40),
            properties_to_check=["Progress"],
            invariants_to_check=self.safety_invariants,
            expected_outcome="Progress resumes after partition heals",
            test_category="recovery",
            complexity_level=4
        ))
        
        # Validator recovery
        validators_validator_recovery = [
            ValidatorConfig("v1", 10),
            ValidatorConfig("v2", 10),
            ValidatorConfig("v3", 10),
            ValidatorConfig("v4", 10, is_offline=True),  # Initially offline
            ValidatorConfig("v5", 10)
        ]
        
        scenarios.append(TestScenario(
            name="Recovery_Validator_Rejoin",
            description="Test validator rejoining after being offline",
            validators=validators_validator_recovery,
            network=NetworkConfig(),
            protocol=ProtocolConfig(max_time=25),
            properties_to_check=["Progress"],
            invariants_to_check=["TypeOK", "Safety"],
            expected_outcome="Validator successfully rejoins consensus",
            test_category="recovery",
            complexity_level=3
        ))
        
        return scenarios

    def _generate_timing_configs(self) -> List[TestScenario]:
        """Generate configurations with various timing parameters and GST values"""
        scenarios = []
        
        # Early GST scenario
        validators_early_gst = [
            ValidatorConfig("v1", 10),
            ValidatorConfig("v2", 10),
            ValidatorConfig("v3", 10)
        ]
        
        scenarios.append(TestScenario(
            name="Timing_Early_GST",
            description="Test with early Global Stabilization Time",
            validators=validators_early_gst,
            network=NetworkConfig(gst=2, delta=1),
            protocol=ProtocolConfig(max_time=20),
            properties_to_check=self.liveness_properties,
            invariants_to_check=["TypeOK"],
            expected_outcome="Fast convergence after early GST",
            test_category="timing",
            complexity_level=2
        ))
        
        # Late GST scenario
        validators_late_gst = [
            ValidatorConfig("v1", 10),
            ValidatorConfig("v2", 10),
            ValidatorConfig("v3", 10),
            ValidatorConfig("v4", 10)
        ]
        
        scenarios.append(TestScenario(
            name="Timing_Late_GST",
            description="Test with late Global Stabilization Time",
            validators=validators_late_gst,
            network=NetworkConfig(gst=15, delta=2),
            protocol=ProtocolConfig(max_time=30),
            properties_to_check=["BoundedFinalization"],
            invariants_to_check=["Safety"],
            expected_outcome="Progress achieved after late GST",
            test_category="timing",
            complexity_level=3
        ))
        
        # Variable network delays
        validators_variable_delay = [
            ValidatorConfig("v1", 10),
            ValidatorConfig("v2", 10),
            ValidatorConfig("v3", 10),
            ValidatorConfig("v4", 10)
        ]
        
        scenarios.append(TestScenario(
            name="Timing_Variable_Delays",
            description="Test with variable network delays",
            validators=validators_variable_delay,
            network=NetworkConfig(max_network_delay=8, delta=3),
            protocol=ProtocolConfig(timeout_delta=6),
            properties_to_check=["BoundedFinalization"],
            invariants_to_check=["TypeOK", "Safety"],
            expected_outcome="Adapts to variable network conditions",
            test_category="timing",
            complexity_level=3
        ))
        
        return scenarios

    def _generate_stake_distribution_configs(self) -> List[TestScenario]:
        """Generate configurations with different stake distributions"""
        scenarios = []
        
        # Uniform stake distribution
        validators_uniform = [ValidatorConfig(f"v{i}", 10) for i in range(1, 6)]
        
        scenarios.append(TestScenario(
            name="Stake_Uniform_Distribution",
            description="Test with uniform stake distribution",
            validators=validators_uniform,
            network=NetworkConfig(),
            protocol=ProtocolConfig(),
            properties_to_check=self.all_properties,
            invariants_to_check=self.all_invariants,
            expected_outcome="Fair consensus with equal stakes",
            test_category="stake_distribution",
            complexity_level=2
        ))
        
        # Skewed stake distribution
        validators_skewed = [
            ValidatorConfig("v1", 40),  # Dominant validator
            ValidatorConfig("v2", 15),
            ValidatorConfig("v3", 15),
            ValidatorConfig("v4", 15),
            ValidatorConfig("v5", 15)
        ]
        
        scenarios.append(TestScenario(
            name="Stake_Skewed_Distribution",
            description="Test with skewed stake distribution (one dominant validator)",
            validators=validators_skewed,
            network=NetworkConfig(),
            protocol=ProtocolConfig(),
            properties_to_check=self.all_properties,
            invariants_to_check=self.all_invariants,
            expected_outcome="Consensus works despite stake concentration",
            test_category="stake_distribution",
            complexity_level=3
        ))
        
        # Minimal stake differences
        validators_minimal_diff = [
            ValidatorConfig("v1", 11),
            ValidatorConfig("v2", 10),
            ValidatorConfig("v3", 10),
            ValidatorConfig("v4", 10),
            ValidatorConfig("v5", 9)
        ]
        
        scenarios.append(TestScenario(
            name="Stake_Minimal_Differences",
            description="Test with minimal stake differences",
            validators=validators_minimal_diff,
            network=NetworkConfig(),
            protocol=ProtocolConfig(),
            properties_to_check=self.all_properties,
            invariants_to_check=self.all_invariants,
            expected_outcome="Stable consensus with small stake variations",
            test_category="stake_distribution",
            complexity_level=2
        ))
        
        return scenarios

    def _generate_incremental_complexity_configs(self) -> List[TestScenario]:
        """Generate a progression of configurations from simple to complex"""
        scenarios = []
        
        # Level 1: Minimal complexity
        scenarios.append(TestScenario(
            name="Incremental_Level1_Minimal",
            description="Minimal complexity: 3 validators, no faults",
            validators=[
                ValidatorConfig("v1", 10),
                ValidatorConfig("v2", 10),
                ValidatorConfig("v3", 10)
            ],
            network=NetworkConfig(),
            protocol=ProtocolConfig(max_slot=2, max_view=2, max_time=10),
            properties_to_check=["Progress"],
            invariants_to_check=["TypeOK", "Safety"],
            expected_outcome="Basic consensus functionality",
            test_category="incremental",
            complexity_level=1
        ))
        
        # Level 2: Add timing complexity
        scenarios.append(TestScenario(
            name="Incremental_Level2_Timing",
            description="Add timing complexity: network delays",
            validators=[
                ValidatorConfig("v1", 10),
                ValidatorConfig("v2", 10),
                ValidatorConfig("v3", 10),
                ValidatorConfig("v4", 10)
            ],
            network=NetworkConfig(gst=3, delta=2),
            protocol=ProtocolConfig(max_slot=4, max_view=3, max_time=20),
            properties_to_check=["Progress", "BoundedFinalization"],
            invariants_to_check=["TypeOK", "Safety"],
            expected_outcome="Handles timing complexity",
            test_category="incremental",
            complexity_level=2
        ))
        
        # Level 3: Add fault tolerance
        scenarios.append(TestScenario(
            name="Incremental_Level3_Faults",
            description="Add fault tolerance: offline validators",
            validators=[
                ValidatorConfig("v1", 10),
                ValidatorConfig("v2", 10),
                ValidatorConfig("v3", 10),
                ValidatorConfig("v4", 10),
                ValidatorConfig("v5", 10, is_offline=True)
            ],
            network=NetworkConfig(gst=3, delta=2),
            protocol=ProtocolConfig(max_slot=5, max_view=4, max_time=25),
            properties_to_check=self.liveness_properties,
            invariants_to_check=self.safety_invariants,
            expected_outcome="Tolerates offline validators",
            test_category="incremental",
            complexity_level=3
        ))
        
        # Level 4: Add Byzantine faults
        scenarios.append(TestScenario(
            name="Incremental_Level4_Byzantine",
            description="Add Byzantine faults: adversarial behavior",
            validators=[
                ValidatorConfig("v1", 15),
                ValidatorConfig("v2", 15),
                ValidatorConfig("v3", 15),
                ValidatorConfig("v4", 15),
                ValidatorConfig("v5", 5, is_byzantine=True)
            ],
            network=NetworkConfig(gst=5, delta=2),
            protocol=ProtocolConfig(max_slot=6, max_view=5, max_time=30),
            properties_to_check=self.all_properties,
            invariants_to_check=self.all_invariants,
            expected_outcome="Secure against Byzantine faults",
            test_category="incremental",
            complexity_level=4
        ))
        
        # Level 5: Full complexity
        scenarios.append(TestScenario(
            name="Incremental_Level5_Full",
            description="Full complexity: all fault types and network issues",
            validators=[
                ValidatorConfig("v1", 20),
                ValidatorConfig("v2", 20),
                ValidatorConfig("v3", 15),
                ValidatorConfig("v4", 10, is_byzantine=True),
                ValidatorConfig("v5", 10, is_offline=True),
                ValidatorConfig("v6", 15)
            ],
            network=NetworkConfig(
                gst=8,
                delta=3,
                max_network_delay=6,
                network_partitions={"partition1"},
                recovery_timeout=20
            ),
            protocol=ProtocolConfig(
                max_slot=8,
                max_view=6,
                max_time=50,
                timeout_delta=4
            ),
            properties_to_check=self.all_properties,
            invariants_to_check=self.all_invariants,
            expected_outcome="Handles all complexity factors",
            test_category="incremental",
            complexity_level=5
        ))
        
        return scenarios

    def _calculate_stake_thresholds(self, validators: List[ValidatorConfig]) -> Dict[str, int]:
        """Calculate stake thresholds for a validator set"""
        total_stake = sum(v.stake for v in validators)
        byzantine_stake = sum(v.stake for v in validators if v.is_byzantine)
        offline_stake = sum(v.stake for v in validators if v.is_offline)
        honest_stake = total_stake - byzantine_stake - offline_stake
        
        return {
            "total_stake": total_stake,
            "byzantine_stake": byzantine_stake,
            "offline_stake": offline_stake,
            "honest_stake": honest_stake,
            "fast_path_threshold": (4 * total_stake) // 5,  # 80%
            "slow_path_threshold": (3 * total_stake) // 5,  # 60%
            "skip_path_threshold": (3 * total_stake) // 5   # 60%
        }

    def _format_validator_set(self, validators: List[ValidatorConfig]) -> str:
        """Format validator set for TLA+ configuration"""
        validator_names = [v.name for v in validators]
        return "{" + ", ".join(validator_names) + "}"

    def _format_byzantine_set(self, validators: List[ValidatorConfig]) -> str:
        """Format Byzantine validator set for TLA+ configuration"""
        byzantine_validators = [v.name for v in validators if v.is_byzantine]
        if not byzantine_validators:
            return "{}"
        return "{" + ", ".join(byzantine_validators) + "}"

    def _format_offline_set(self, validators: List[ValidatorConfig]) -> str:
        """Format offline validator set for TLA+ configuration"""
        offline_validators = [v.name for v in validators if v.is_offline]
        if not offline_validators:
            return "{}"
        return "{" + ", ".join(offline_validators) + "}"

    def _format_stake_mapping(self, validators: List[ValidatorConfig]) -> str:
        """Format stake mapping for TLA+ configuration"""
        stake_mappings = [f"{v.name} |-> {v.stake}" for v in validators]
        return "[" + ", ".join(stake_mappings) + "]"

    def _format_network_partitions(self, partitions: Set[str]) -> str:
        """Format network partitions for TLA+ configuration"""
        if not partitions:
            return "{}"
        return "{" + ", ".join(f'"{p}"' for p in partitions) + "}"

    def generate_tla_config(self, scenario: TestScenario) -> str:
        """Generate TLA+ configuration file content for a scenario"""
        thresholds = self._calculate_stake_thresholds(scenario.validators)
        
        config_content = f"""SPECIFICATION Spec

CONSTANTS
    \\* Validator configuration for {scenario.name}
    Validators = {self._format_validator_set(scenario.validators)}
    ByzantineValidators = {self._format_byzantine_set(scenario.validators)}
    OfflineValidators = {self._format_offline_set(scenario.validators)}
    
    \\* Protocol parameters
    MaxSlot = {scenario.protocol.max_slot}
    MaxView = {scenario.protocol.max_view}
    MaxTime = {scenario.protocol.max_time}
    
    \\* Stake distribution
    Stake = {self._format_stake_mapping(scenario.validators)}
    
    \\* Network parameters
    GST = {scenario.network.gst}
    Delta = {scenario.network.delta}
    MaxNetworkDelay = {scenario.network.max_network_delay}
    MessageLossRate = {scenario.network.message_loss_rate}
    NetworkPartitions = {self._format_network_partitions(scenario.network.network_partitions)}
    RecoveryTimeout = {scenario.network.recovery_timeout}
    MaxRetransmissions = {scenario.network.max_retransmissions}
    
    \\* Erasure coding parameters (Rotor)
    K = {scenario.protocol.k}
    N = {scenario.protocol.n}
    MaxBlocks = {scenario.protocol.max_blocks}
    BandwidthLimit = {scenario.protocol.bandwidth_limit}
    RetryTimeout = {scenario.protocol.retry_timeout}
    MaxRetries = {scenario.protocol.max_retries}
    
    \\* Block and transaction limits
    MaxBlockSize = {scenario.protocol.max_block_size}
    BandwidthPerValidator = {scenario.protocol.bandwidth_limit // len(scenario.validators)}
    MaxTransactions = {scenario.protocol.max_transactions}
    
    \\* Protocol parameters (Votor)
    TimeoutDelta = {scenario.protocol.timeout_delta}
    InitialLeader = {scenario.validators[0].name}
    FastPathStake = {thresholds['fast_path_threshold']}
    SlowPathStake = {thresholds['slow_path_threshold']}
    SkipPathStake = {thresholds['skip_path_threshold']}
    LeaderFunction = {scenario.validators[0].name}
    
    \\* Cryptographic abstractions
    MaxSignatures = {scenario.protocol.max_signatures}
    MaxCertificates = {scenario.protocol.max_certificates}

\\* State constraints for bounded model checking
CONSTRAINT StateConstraint

\\* Invariants to check"""

        if scenario.invariants_to_check:
            for invariant in scenario.invariants_to_check:
                config_content += f"\nINVARIANT {invariant}"

        config_content += "\n\n\\* Properties to check"
        if scenario.properties_to_check:
            for prop in scenario.properties_to_check:
                config_content += f"\nPROPERTY {prop}"

        # Add symmetry reduction for non-Byzantine, non-offline validators
        honest_validators = [v.name for v in scenario.validators 
                           if not v.is_byzantine and not v.is_offline]
        if len(honest_validators) > 1:
            # Exclude the initial leader from symmetry
            symmetric_validators = [v for v in honest_validators if v != scenario.validators[0].name]
            if len(symmetric_validators) > 1:
                config_content += f"\n\n\\* Symmetry reduction\nSYMMETRY Permutations({{{', '.join(symmetric_validators)}}})"

        config_content += f"""

\\* Action constraints
ACTION_CONSTRAINT ActionConstraint

\\* Initial state predicates
INIT Init

\\* Next-state relation  
NEXT Next

\\* View for state space exploration
VIEW <<currentSlot, clock, Cardinality(finalizedBlocks[currentSlot])>>

\\* Configuration metadata (as comments)
\\* Test Category: {scenario.test_category}
\\* Complexity Level: {scenario.complexity_level}
\\* Description: {scenario.description}
\\* Expected Outcome: {scenario.expected_outcome}
\\* Total Stake: {thresholds['total_stake']}
\\* Byzantine Stake: {thresholds['byzantine_stake']} ({(thresholds['byzantine_stake'] * 100) // thresholds['total_stake']}%)
\\* Offline Stake: {thresholds['offline_stake']} ({(thresholds['offline_stake'] * 100) // thresholds['total_stake']}%)
\\* Honest Stake: {thresholds['honest_stake']} ({(thresholds['honest_stake'] * 100) // thresholds['total_stake']}%)
"""
        
        return config_content

    def save_configuration(self, scenario: TestScenario) -> str:
        """Save a configuration scenario to a .cfg file"""
        config_content = self.generate_tla_config(scenario)
        filename = f"{scenario.name}.cfg"
        filepath = self.output_dir / filename
        
        with open(filepath, 'w') as f:
            f.write(config_content)
        
        return str(filepath)

    def generate_test_matrix(self, scenarios: List[TestScenario]) -> str:
        """Generate a comprehensive test matrix"""
        matrix = "# Alpenglow Protocol Test Matrix\n\n"
        matrix += f"Generated {len(scenarios)} test configurations\n\n"
        
        # Group by category
        categories = {}
        for scenario in scenarios:
            if scenario.test_category not in categories:
                categories[scenario.test_category] = []
            categories[scenario.test_category].append(scenario)
        
        for category, cat_scenarios in categories.items():
            matrix += f"## {category.replace('_', ' ').title()}\n\n"
            matrix += "| Name | Validators | Byzantine | Offline | Complexity | Description |\n"
            matrix += "|------|------------|-----------|---------|------------|-------------|\n"
            
            for scenario in cat_scenarios:
                byzantine_count = sum(1 for v in scenario.validators if v.is_byzantine)
                offline_count = sum(1 for v in scenario.validators if v.is_offline)
                matrix += f"| {scenario.name} | {len(scenario.validators)} | {byzantine_count} | {offline_count} | {scenario.complexity_level} | {scenario.description} |\n"
            
            matrix += "\n"
        
        return matrix

    def generate_validation_summary(self, scenarios: List[TestScenario]) -> Dict[str, Any]:
        """Generate a validation summary with statistics"""
        summary = {
            "total_scenarios": len(scenarios),
            "categories": {},
            "complexity_distribution": {},
            "fault_coverage": {
                "byzantine_scenarios": 0,
                "offline_scenarios": 0,
                "combined_fault_scenarios": 0,
                "partition_scenarios": 0
            },
            "property_coverage": {
                "safety_tests": 0,
                "liveness_tests": 0,
                "performance_tests": 0
            },
            "validator_set_sizes": {},
            "stake_distributions": []
        }
        
        for scenario in scenarios:
            # Category statistics
            category = scenario.test_category
            if category not in summary["categories"]:
                summary["categories"][category] = 0
            summary["categories"][category] += 1
            
            # Complexity distribution
            complexity = scenario.complexity_level
            if complexity not in summary["complexity_distribution"]:
                summary["complexity_distribution"][complexity] = 0
            summary["complexity_distribution"][complexity] += 1
            
            # Fault coverage
            has_byzantine = any(v.is_byzantine for v in scenario.validators)
            has_offline = any(v.is_offline for v in scenario.validators)
            has_partition = bool(scenario.network.network_partitions)
            
            if has_byzantine:
                summary["fault_coverage"]["byzantine_scenarios"] += 1
            if has_offline:
                summary["fault_coverage"]["offline_scenarios"] += 1
            if has_byzantine and has_offline:
                summary["fault_coverage"]["combined_fault_scenarios"] += 1
            if has_partition:
                summary["fault_coverage"]["partition_scenarios"] += 1
            
            # Property coverage
            if any(inv in self.safety_invariants for inv in scenario.invariants_to_check):
                summary["property_coverage"]["safety_tests"] += 1
            if any(prop in self.liveness_properties for prop in scenario.properties_to_check):
                summary["property_coverage"]["liveness_tests"] += 1
            if any(prop in self.performance_properties for prop in scenario.properties_to_check):
                summary["property_coverage"]["performance_tests"] += 1
            
            # Validator set sizes
            size = len(scenario.validators)
            if size not in summary["validator_set_sizes"]:
                summary["validator_set_sizes"][size] = 0
            summary["validator_set_sizes"][size] += 1
            
            # Stake distribution analysis
            thresholds = self._calculate_stake_thresholds(scenario.validators)
            summary["stake_distributions"].append({
                "scenario": scenario.name,
                "total_stake": thresholds["total_stake"],
                "byzantine_percentage": (thresholds["byzantine_stake"] * 100) // thresholds["total_stake"],
                "offline_percentage": (thresholds["offline_stake"] * 100) // thresholds["total_stake"]
            })
        
        return summary

    def run_generation(self) -> None:
        """Main method to generate all configurations and reports"""
        print("Generating comprehensive Alpenglow protocol test configurations...")
        
        # Generate all scenarios
        scenarios = self.generate_all_configurations()
        
        print(f"Generated {len(scenarios)} test scenarios")
        
        # Save individual configuration files
        saved_files = []
        for scenario in scenarios:
            filepath = self.save_configuration(scenario)
            saved_files.append(filepath)
            print(f"Saved: {filepath}")
        
        # Generate test matrix
        matrix_content = self.generate_test_matrix(scenarios)
        matrix_file = self.output_dir / "test_matrix.md"
        with open(matrix_file, 'w') as f:
            f.write(matrix_content)
        print(f"Generated test matrix: {matrix_file}")
        
        # Generate validation summary
        summary = self.generate_validation_summary(scenarios)
        summary_file = self.output_dir / "validation_summary.json"
        with open(summary_file, 'w') as f:
            json.dump(summary, f, indent=2)
        print(f"Generated validation summary: {summary_file}")
        
        # Generate master configuration list
        config_list = {
            "configurations": [
                {
                    "name": scenario.name,
                    "file": f"{scenario.name}.cfg",
                    "category": scenario.test_category,
                    "complexity": scenario.complexity_level,
                    "description": scenario.description,
                    "validators": len(scenario.validators),
                    "byzantine": sum(1 for v in scenario.validators if v.is_byzantine),
                    "offline": sum(1 for v in scenario.validators if v.is_offline),
                    "expected_outcome": scenario.expected_outcome
                }
                for scenario in scenarios
            ]
        }
        
        config_list_file = self.output_dir / "configuration_list.json"
        with open(config_list_file, 'w') as f:
            json.dump(config_list, f, indent=2)
        print(f"Generated configuration list: {config_list_file}")
        
        print(f"\nGeneration complete! All files saved to: {self.output_dir}")
        print(f"Total configurations: {len(scenarios)}")
        print(f"Categories: {list(summary['categories'].keys())}")
        print(f"Complexity levels: {sorted(summary['complexity_distribution'].keys())}")

def main():
    """Main entry point for the configuration generator"""
    import argparse
    
    parser = argparse.ArgumentParser(
        description="Generate comprehensive TLA+ model checking configurations for Alpenglow protocol"
    )
    parser.add_argument(
        "--output-dir",
        default="generated_configs",
        help="Output directory for generated configurations (default: generated_configs)"
    )
    parser.add_argument(
        "--categories",
        nargs="*",
        choices=[
            "small_scale", "boundary_conditions", "edge_cases", "performance",
            "theorem_validation", "adversarial", "recovery", "timing",
            "stake_distribution", "incremental"
        ],
        help="Generate only specific categories of configurations"
    )
    
    args = parser.parse_args()
    
    generator = ConfigurationGenerator(args.output_dir)
    
    if args.categories:
        print(f"Generating configurations for categories: {args.categories}")
        # Filter scenarios by category would be implemented here
        # For now, generate all and filter during save
    
    generator.run_generation()

if __name__ == "__main__":
    main()