#!/usr/bin/env python3
"""
Automated Gap Analysis Tool for Solana Alpenglow Formal Verification

This tool compares the current implementation against the whitepaper requirements
and identifies missing or incomplete components. It generates reports similar to
docs/VerificationMapping.md but with automated analysis capabilities.

Author: Traycer.AI
Date: 2025
"""

import os
import re
import json
import argparse
from pathlib import Path
from typing import Dict, List, Tuple, Optional, Set
from dataclasses import dataclass, asdict
from enum import Enum
import hashlib
import datetime

class ImplementationStatus(Enum):
    """Status levels for implementation components"""
    FULLY_IMPLEMENTED = "✅ Implemented"
    PARTIALLY_IMPLEMENTED = "⚠️ Partially"
    NOT_IMPLEMENTED = "❌ Not Implemented"
    UNKNOWN = "❓ Unknown"

@dataclass
class Component:
    """Represents a protocol component with its implementation status"""
    name: str
    description: str
    status: ImplementationStatus
    location: Optional[str] = None
    notes: Optional[str] = None
    whitepaper_section: Optional[str] = None
    dependencies: List[str] = None
    
    def __post_init__(self):
        if self.dependencies is None:
            self.dependencies = []

@dataclass
class GapAnalysisResult:
    """Results of the gap analysis"""
    overall_completion: float
    total_components: int
    implemented_count: int
    partial_count: int
    missing_count: int
    components: List[Component]
    critical_gaps: List[str]
    recommendations: List[str]
    timestamp: str

class AlpenglowGapAnalyzer:
    """Main analyzer class for Alpenglow formal verification gaps"""
    
    def __init__(self, project_root: str):
        self.project_root = Path(project_root)
        self.specs_dir = self.project_root / "specs"
        self.proofs_dir = self.project_root / "proofs"
        self.models_dir = self.project_root / "models"
        self.scripts_dir = self.project_root / "scripts"
        self.docs_dir = self.project_root / "docs"
        self.stateright_dir = self.project_root / "stateright"
        self.implementation_dir = self.project_root / "implementation"
        self.benchmarks_dir = self.project_root / "benchmarks"
        
        # Whitepaper requirements extracted from the document
        self.whitepaper_requirements = self._load_whitepaper_requirements()
        
        # File patterns for different components
        self.file_patterns = {
            'tla_specs': ['*.tla'],
            'proofs': ['*.tla'],
            'configs': ['*.cfg'],
            'scripts': ['*.sh', '*.py'],
            'rust_code': ['*.rs', 'Cargo.toml'],
            'docs': ['*.md']
        }

    def _load_whitepaper_requirements(self) -> Dict[str, List[Dict]]:
        """Load requirements extracted from the Alpenglow whitepaper"""
        return {
            "votor_dual_paths": [
                {
                    "name": "Fast Path (≥80% stake)",
                    "description": "Single round finalization with 80% stake participation",
                    "section": "2.6",
                    "critical": True,
                    "expected_files": ["specs/Votor.tla"],
                    "expected_functions": ["FastPathVoting", "FastThreshold"]
                },
                {
                    "name": "Slow Path (≥60% stake)", 
                    "description": "Two round finalization with 60% stake participation",
                    "section": "2.6",
                    "critical": True,
                    "expected_files": ["specs/Votor.tla"],
                    "expected_functions": ["SlowPathVoting", "SlowThreshold"]
                },
                {
                    "name": "100ms fast finalization",
                    "description": "Fast path finalization within 100ms",
                    "section": "1.3",
                    "critical": True,
                    "expected_files": ["specs/Timing.tla"],
                    "expected_constants": ["FastPathTimeout"]
                },
                {
                    "name": "150ms slow finalization",
                    "description": "Slow path finalization within 150ms", 
                    "section": "1.3",
                    "critical": True,
                    "expected_files": ["specs/Timing.tla"],
                    "expected_constants": ["SlowPathTimeout"]
                },
                {
                    "name": "Certificate type differentiation",
                    "description": "Fast, Slow, and Skip certificate types",
                    "section": "2.4",
                    "critical": True,
                    "expected_files": ["specs/Types.tla", "specs/Votor.tla"],
                    "expected_types": ["FastCert", "SlowCert", "SkipCert"]
                }
            ],
            "rotor_erasure_coding": [
                {
                    "name": "Reed-Solomon erasure coding",
                    "description": "K-of-N reconstruction with Reed-Solomon codes",
                    "section": "2.2",
                    "critical": True,
                    "expected_files": ["specs/Rotor.tla"],
                    "expected_functions": ["ReedSolomonEncode", "ReedSolomonDecode"]
                },
                {
                    "name": "Stake-weighted relay sampling",
                    "description": "Proportional relay selection based on stake",
                    "section": "3.1",
                    "critical": True,
                    "expected_files": ["specs/Rotor.tla"],
                    "expected_functions": ["StakeWeightedSampling", "SelectRelays"]
                },
                {
                    "name": "Shred distribution",
                    "description": "UDP datagram-sized shred propagation",
                    "section": "2.1",
                    "critical": True,
                    "expected_files": ["specs/Rotor.tla"],
                    "expected_functions": ["ShredDistribution", "CreateShred"]
                },
                {
                    "name": "Block reconstruction",
                    "description": "Reconstruct blocks from K shreds",
                    "section": "2.2",
                    "critical": True,
                    "expected_files": ["specs/Rotor.tla"],
                    "expected_functions": ["ReconstructBlock", "ValidateShreds"]
                },
                {
                    "name": "Repair mechanism",
                    "description": "Request missing shreds from peers",
                    "section": "2.8",
                    "critical": False,
                    "expected_files": ["specs/Rotor.tla"],
                    "expected_functions": ["RepairRequest", "RepairResponse"]
                }
            ],
            "safety_properties": [
                {
                    "name": "No conflicting finalization",
                    "description": "Safety theorem preventing conflicting blocks",
                    "section": "2.9",
                    "critical": True,
                    "expected_files": ["proofs/Safety.tla"],
                    "expected_theorems": ["SafetyTheorem", "NoConflictingFinalization"]
                },
                {
                    "name": "Chain consistency",
                    "description": "Consistent chain across honest validators",
                    "section": "2.9",
                    "critical": True,
                    "expected_files": ["proofs/Safety.tla"],
                    "expected_theorems": ["ChainConsistency"]
                },
                {
                    "name": "Certificate uniqueness",
                    "description": "At most one certificate per slot/type",
                    "section": "2.9",
                    "critical": True,
                    "expected_files": ["proofs/Safety.tla"],
                    "expected_theorems": ["CertificateUniqueness"]
                },
                {
                    "name": "20% Byzantine tolerance",
                    "description": "Safety with up to 20% Byzantine nodes",
                    "section": "1.2",
                    "critical": True,
                    "expected_files": ["proofs/Resilience.tla"],
                    "expected_theorems": ["ByzantineTolerance", "MaxByzantineTheorem"]
                }
            ],
            "liveness_properties": [
                {
                    "name": "Progress with >60% honest",
                    "description": "Liveness theorem with honest majority",
                    "section": "2.10",
                    "critical": True,
                    "expected_files": ["proofs/Liveness.tla"],
                    "expected_theorems": ["ProgressTheorem", "LivenessGuarantee"]
                },
                {
                    "name": "Fast path with >80% stake",
                    "description": "Fast finalization with supermajority",
                    "section": "2.10",
                    "critical": True,
                    "expected_files": ["proofs/Liveness.tla"],
                    "expected_theorems": ["FastPathTheorem"]
                },
                {
                    "name": "Bounded finalization time",
                    "description": "Finalization within GST + Delta bound",
                    "section": "2.10",
                    "critical": True,
                    "expected_files": ["proofs/Liveness.tla"],
                    "expected_theorems": ["BoundedFinalization"]
                }
            ],
            "resilience_properties": [
                {
                    "name": "20+20 resilience model",
                    "description": "20% Byzantine + 20% offline tolerance",
                    "section": "1.2",
                    "critical": True,
                    "expected_files": ["proofs/Resilience.tla"],
                    "expected_theorems": ["Combined2020Resilience"]
                },
                {
                    "name": "Network partition recovery",
                    "description": "Recovery from network partitions",
                    "section": "3.3",
                    "critical": False,
                    "expected_files": ["specs/Network.tla", "proofs/Resilience.tla"],
                    "expected_functions": ["PartitionRecovery", "GST"]
                }
            ],
            "stateright_implementation": [
                {
                    "name": "Rust Stateright implementation",
                    "description": "Cross-validation with TLA+ specs",
                    "section": "N/A",
                    "critical": True,
                    "expected_files": ["stateright/src/lib.rs", "stateright/Cargo.toml"],
                    "expected_modules": ["votor", "rotor", "network"]
                },
                {
                    "name": "Cross-validation tests",
                    "description": "Tests comparing Stateright and TLA+ results",
                    "section": "N/A",
                    "critical": True,
                    "expected_files": ["stateright/tests/cross_validation.rs"],
                    "expected_functions": ["test_safety_properties", "test_liveness_properties"]
                }
            ],
            "economic_model": [
                {
                    "name": "Reward distribution",
                    "description": "Stake-proportional reward mechanism",
                    "section": "1.5",
                    "critical": False,
                    "expected_files": ["specs/EconomicModel.tla"],
                    "expected_functions": ["DistributeRewards", "CalculateStakeReward"]
                },
                {
                    "name": "Slashing conditions",
                    "description": "Penalties for Byzantine behavior",
                    "section": "1.2",
                    "critical": False,
                    "expected_files": ["specs/EconomicModel.tla"],
                    "expected_functions": ["SlashValidator", "DetectMisbehavior"]
                },
                {
                    "name": "Fee handling",
                    "description": "Transaction fee collection and distribution",
                    "section": "1.5",
                    "critical": False,
                    "expected_files": ["specs/EconomicModel.tla"],
                    "expected_functions": ["CollectFees", "DistributeFees"]
                }
            ],
            "advanced_features": [
                {
                    "name": "VRF leader selection",
                    "description": "Verifiable random function for leader rotation",
                    "section": "1.5",
                    "critical": False,
                    "expected_files": ["specs/VRF.tla"],
                    "expected_functions": ["VRFLeaderSelection", "VerifyVRF"]
                },
                {
                    "name": "4-slot leader windows",
                    "description": "Fixed 4-slot leadership periods",
                    "section": "1.5",
                    "critical": False,
                    "expected_files": ["specs/Votor.tla"],
                    "expected_constants": ["LeaderWindowSize"]
                },
                {
                    "name": "Dynamic timeouts",
                    "description": "Adaptive timeout mechanisms",
                    "section": "3.4",
                    "critical": False,
                    "expected_files": ["specs/Timing.tla"],
                    "expected_functions": ["AdaptiveTimeout", "ExtendTimeout"]
                }
            ]
        }

    def analyze_file_existence(self) -> Dict[str, bool]:
        """Check which expected files exist in the project"""
        file_status = {}
        
        for category, requirements in self.whitepaper_requirements.items():
            for req in requirements:
                if 'expected_files' in req:
                    for file_path in req['expected_files']:
                        full_path = self.project_root / file_path
                        file_status[file_path] = full_path.exists()
        
        return file_status

    def analyze_tla_specifications(self) -> Dict[str, Dict]:
        """Analyze TLA+ specification files for completeness"""
        tla_analysis = {}
        
        if not self.specs_dir.exists():
            return tla_analysis
            
        for tla_file in self.specs_dir.glob("*.tla"):
            analysis = self._analyze_tla_file(tla_file)
            tla_analysis[tla_file.name] = analysis
            
        return tla_analysis

    def _analyze_tla_file(self, file_path: Path) -> Dict:
        """Analyze a single TLA+ file"""
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
        except Exception as e:
            return {"error": f"Could not read file: {e}"}
            
        analysis = {
            "module_name": self._extract_module_name(content),
            "constants": self._extract_constants(content),
            "variables": self._extract_variables(content),
            "operators": self._extract_operators(content),
            "actions": self._extract_actions(content),
            "theorems": self._extract_theorems(content),
            "line_count": len(content.splitlines()),
            "has_init": "Init ==" in content,
            "has_next": "Next ==" in content,
            "extends": self._extract_extends(content)
        }
        
        return analysis

    def _extract_module_name(self, content: str) -> Optional[str]:
        """Extract module name from TLA+ content"""
        match = re.search(r'----\s*MODULE\s+(\w+)\s*----', content)
        return match.group(1) if match else None

    def _extract_constants(self, content: str) -> List[str]:
        """Extract CONSTANTS from TLA+ content"""
        constants = []
        in_constants = False
        
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('CONSTANTS'):
                in_constants = True
                # Extract constants from the same line
                const_part = line[9:].strip()
                if const_part:
                    constants.extend([c.strip() for c in const_part.split(',') if c.strip()])
            elif in_constants:
                if line.startswith('VARIABLES') or line.startswith('ASSUME') or line == '':
                    in_constants = False
                else:
                    constants.extend([c.strip() for c in line.split(',') if c.strip()])
                    
        return constants

    def _extract_variables(self, content: str) -> List[str]:
        """Extract VARIABLES from TLA+ content"""
        variables = []
        in_variables = False
        
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('VARIABLES'):
                in_variables = True
                var_part = line[9:].strip()
                if var_part:
                    variables.extend([v.strip() for v in var_part.split(',') if v.strip()])
            elif in_variables:
                if line.startswith('ASSUME') or line.startswith('Init') or line == '':
                    in_variables = False
                else:
                    variables.extend([v.strip() for v in line.split(',') if v.strip()])
                    
        return variables

    def _extract_operators(self, content: str) -> List[str]:
        """Extract operator definitions from TLA+ content"""
        operators = []
        for line in content.splitlines():
            line = line.strip()
            # Match operator definitions: Name(params) == ...
            match = re.match(r'(\w+)(?:\([^)]*\))?\s*==', line)
            if match and not line.startswith('\\*'):
                operators.append(match.group(1))
        return operators

    def _extract_actions(self, content: str) -> List[str]:
        """Extract action definitions from TLA+ content"""
        actions = []
        for line in content.splitlines():
            line = line.strip()
            # Actions typically end with apostrophe (primed variables)
            if "'" in line and "==" in line and not line.startswith('\\*'):
                match = re.match(r'(\w+)\s*==', line)
                if match:
                    actions.append(match.group(1))
        return actions

    def _extract_theorems(self, content: str) -> List[str]:
        """Extract theorem statements from TLA+ content"""
        theorems = []
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('THEOREM') or line.startswith('LEMMA'):
                # Extract theorem name
                match = re.search(r'(THEOREM|LEMMA)\s+(\w+)', line)
                if match:
                    theorems.append(match.group(2))
        return theorems

    def _extract_extends(self, content: str) -> List[str]:
        """Extract EXTENDS modules from TLA+ content"""
        extends = []
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('EXTENDS'):
                ext_part = line[7:].strip()
                extends.extend([e.strip() for e in ext_part.split(',') if e.strip()])
        return extends

    def analyze_proofs(self) -> Dict[str, Dict]:
        """Analyze proof files for theorem coverage"""
        proof_analysis = {}
        
        if not self.proofs_dir.exists():
            return proof_analysis
            
        for proof_file in self.proofs_dir.glob("*.tla"):
            analysis = self._analyze_tla_file(proof_file)
            proof_analysis[proof_file.name] = analysis
            
        return proof_analysis

    def analyze_stateright_implementation(self) -> Dict[str, any]:
        """Analyze Stateright Rust implementation"""
        stateright_analysis = {
            "exists": self.stateright_dir.exists(),
            "cargo_toml": (self.stateright_dir / "Cargo.toml").exists(),
            "src_dir": (self.stateright_dir / "src").exists(),
            "lib_rs": (self.stateright_dir / "src" / "lib.rs").exists(),
            "modules": [],
            "tests": [],
            "dependencies": []
        }
        
        if not stateright_analysis["exists"]:
            return stateright_analysis
            
        # Analyze Cargo.toml
        cargo_path = self.stateright_dir / "Cargo.toml"
        if cargo_path.exists():
            stateright_analysis["dependencies"] = self._analyze_cargo_dependencies(cargo_path)
            
        # Analyze source modules
        src_dir = self.stateright_dir / "src"
        if src_dir.exists():
            for rs_file in src_dir.glob("*.rs"):
                if rs_file.name != "lib.rs":
                    stateright_analysis["modules"].append(rs_file.stem)
                    
        # Analyze tests
        tests_dir = self.stateright_dir / "tests"
        if tests_dir.exists():
            for test_file in tests_dir.glob("*.rs"):
                stateright_analysis["tests"].append(test_file.stem)
                
        return stateright_analysis

    def _analyze_cargo_dependencies(self, cargo_path: Path) -> List[str]:
        """Extract dependencies from Cargo.toml"""
        dependencies = []
        try:
            with open(cargo_path, 'r') as f:
                content = f.read()
                
            in_dependencies = False
            for line in content.splitlines():
                line = line.strip()
                if line == "[dependencies]":
                    in_dependencies = True
                elif line.startswith("[") and line != "[dependencies]":
                    in_dependencies = False
                elif in_dependencies and "=" in line:
                    dep_name = line.split("=")[0].strip()
                    dependencies.append(dep_name)
        except Exception:
            pass
            
        return dependencies

    def check_requirement_implementation(self, requirement: Dict) -> Component:
        """Check if a specific requirement is implemented"""
        name = requirement["name"]
        description = requirement["description"]
        section = requirement.get("section", "N/A")
        
        # Check file existence
        files_exist = True
        missing_files = []
        
        if "expected_files" in requirement:
            for file_path in requirement["expected_files"]:
                full_path = self.project_root / file_path
                if not full_path.exists():
                    files_exist = False
                    missing_files.append(file_path)
        
        # Determine status based on file existence and content analysis
        if not files_exist:
            status = ImplementationStatus.NOT_IMPLEMENTED
            notes = f"Missing files: {', '.join(missing_files)}"
            location = None
        else:
            # Files exist, check content
            status, location, notes = self._analyze_requirement_content(requirement)
            
        return Component(
            name=name,
            description=description,
            status=status,
            location=location,
            notes=notes,
            whitepaper_section=section,
            dependencies=requirement.get("dependencies", [])
        )

    def _analyze_requirement_content(self, requirement: Dict) -> Tuple[ImplementationStatus, str, str]:
        """Analyze file content to determine implementation status"""
        expected_files = requirement.get("expected_files", [])
        expected_functions = requirement.get("expected_functions", [])
        expected_theorems = requirement.get("expected_theorems", [])
        expected_constants = requirement.get("expected_constants", [])
        expected_modules = requirement.get("expected_modules", [])
        
        found_items = []
        missing_items = []
        locations = []
        
        for file_path in expected_files:
            full_path = self.project_root / file_path
            if full_path.exists():
                locations.append(file_path)
                
                if file_path.endswith('.tla'):
                    analysis = self._analyze_tla_file(full_path)
                    
                    # Check for expected functions/operators
                    for func in expected_functions:
                        if func in analysis.get("operators", []):
                            found_items.append(f"function:{func}")
                        else:
                            missing_items.append(f"function:{func}")
                            
                    # Check for expected theorems
                    for theorem in expected_theorems:
                        if theorem in analysis.get("theorems", []):
                            found_items.append(f"theorem:{theorem}")
                        else:
                            missing_items.append(f"theorem:{theorem}")
                            
                    # Check for expected constants
                    for const in expected_constants:
                        if const in analysis.get("constants", []):
                            found_items.append(f"constant:{const}")
                        else:
                            missing_items.append(f"constant:{const}")
                            
                elif file_path.endswith('.rs'):
                    # Basic Rust file analysis
                    try:
                        with open(full_path, 'r') as f:
                            content = f.read()
                            
                        for func in expected_functions:
                            if f"fn {func}" in content or f"pub fn {func}" in content:
                                found_items.append(f"function:{func}")
                            else:
                                missing_items.append(f"function:{func}")
                    except Exception:
                        missing_items.extend([f"function:{f}" for f in expected_functions])
        
        # Check for expected modules in Stateright
        if expected_modules:
            stateright_analysis = self.analyze_stateright_implementation()
            for module in expected_modules:
                if module in stateright_analysis.get("modules", []):
                    found_items.append(f"module:{module}")
                else:
                    missing_items.append(f"module:{module}")
        
        # Determine status
        if not found_items and missing_items:
            status = ImplementationStatus.NOT_IMPLEMENTED
        elif found_items and missing_items:
            status = ImplementationStatus.PARTIALLY_IMPLEMENTED
        elif found_items and not missing_items:
            status = ImplementationStatus.FULLY_IMPLEMENTED
        else:
            status = ImplementationStatus.UNKNOWN
            
        location = ", ".join(locations) if locations else None
        notes = ""
        if found_items:
            notes += f"Found: {', '.join(found_items[:3])}{'...' if len(found_items) > 3 else ''}"
        if missing_items:
            if notes:
                notes += "; "
            notes += f"Missing: {', '.join(missing_items[:3])}{'...' if len(missing_items) > 3 else ''}"
            
        return status, location, notes

    def run_analysis(self) -> GapAnalysisResult:
        """Run complete gap analysis"""
        print("🔍 Starting Alpenglow Gap Analysis...")
        
        all_components = []
        
        # Analyze each category of requirements
        for category, requirements in self.whitepaper_requirements.items():
            print(f"  📋 Analyzing {category.replace('_', ' ').title()}...")
            
            for requirement in requirements:
                component = self.check_requirement_implementation(requirement)
                all_components.append(component)
        
        # Calculate statistics
        total_components = len(all_components)
        implemented_count = sum(1 for c in all_components if c.status == ImplementationStatus.FULLY_IMPLEMENTED)
        partial_count = sum(1 for c in all_components if c.status == ImplementationStatus.PARTIALLY_IMPLEMENTED)
        missing_count = sum(1 for c in all_components if c.status == ImplementationStatus.NOT_IMPLEMENTED)
        
        # Calculate completion percentage (partial counts as 0.5)
        completion_score = implemented_count + (partial_count * 0.5)
        overall_completion = (completion_score / total_components) * 100 if total_components > 0 else 0
        
        # Identify critical gaps
        critical_gaps = [
            c.name for c in all_components 
            if c.status == ImplementationStatus.NOT_IMPLEMENTED and 
            any(req.get("critical", False) for cat_reqs in self.whitepaper_requirements.values() 
                for req in cat_reqs if req["name"] == c.name)
        ]
        
        # Generate recommendations
        recommendations = self._generate_recommendations(all_components)
        
        return GapAnalysisResult(
            overall_completion=overall_completion,
            total_components=total_components,
            implemented_count=implemented_count,
            partial_count=partial_count,
            missing_count=missing_count,
            components=all_components,
            critical_gaps=critical_gaps,
            recommendations=recommendations,
            timestamp=datetime.datetime.now().isoformat()
        )

    def _generate_recommendations(self, components: List[Component]) -> List[str]:
        """Generate recommendations based on analysis results"""
        recommendations = []
        
        # Critical missing components
        critical_missing = [c for c in components if c.status == ImplementationStatus.NOT_IMPLEMENTED]
        if critical_missing:
            recommendations.append(
                f"🚨 Implement {len(critical_missing)} missing critical components: " +
                ", ".join([c.name for c in critical_missing[:3]]) +
                ("..." if len(critical_missing) > 3 else "")
            )
        
        # Stateright implementation
        stateright_components = [c for c in components if "stateright" in c.name.lower()]
        if any(c.status == ImplementationStatus.NOT_IMPLEMENTED for c in stateright_components):
            recommendations.append(
                "🦀 Complete Stateright Rust implementation for cross-validation (estimated 4 weeks)"
            )
        
        # Economic model
        economic_components = [c for c in components if "reward" in c.name.lower() or "slash" in c.name.lower() or "fee" in c.name.lower()]
        if any(c.status == ImplementationStatus.NOT_IMPLEMENTED for c in economic_components):
            recommendations.append(
                "💰 Implement economic model with rewards, slashing, and fees (estimated 2 weeks)"
            )
        
        # Partial implementations
        partial_components = [c for c in components if c.status == ImplementationStatus.PARTIALLY_IMPLEMENTED]
        if partial_components:
            recommendations.append(
                f"⚠️ Complete {len(partial_components)} partially implemented components"
            )
        
        # Advanced features
        advanced_missing = [c for c in components if c.status == ImplementationStatus.NOT_IMPLEMENTED and 
                          any(keyword in c.name.lower() for keyword in ["vrf", "timeout", "window"])]
        if advanced_missing:
            recommendations.append(
                "🔧 Implement advanced features: VRF leader selection, dynamic timeouts, 4-slot windows"
            )
        
        return recommendations

    def generate_report(self, result: GapAnalysisResult, output_format: str = "markdown") -> str:
        """Generate formatted report"""
        if output_format == "markdown":
            return self._generate_markdown_report(result)
        elif output_format == "json":
            return self._generate_json_report(result)
        else:
            raise ValueError(f"Unsupported output format: {output_format}")

    def _generate_markdown_report(self, result: GapAnalysisResult) -> str:
        """Generate markdown report"""
        report = f"""# Automated Gap Analysis Report: Alpenglow Formal Verification

**Generated:** {result.timestamp}  
**Overall Completion:** {result.overall_completion:.1f}%

## Executive Summary

This automated analysis compares the current implementation against the Alpenglow whitepaper requirements and identifies missing or incomplete components.

### Implementation Status: **{result.overall_completion:.1f}% Complete**

✅ **Fully Implemented**: {result.implemented_count} components  
⚠️ **Partially Implemented**: {result.partial_count} components  
❌ **Not Implemented**: {result.missing_count} components  

---

## Critical Gaps

"""
        
        if result.critical_gaps:
            for gap in result.critical_gaps:
                report += f"- ❌ **{gap}**\n"
        else:
            report += "🎉 No critical gaps identified!\n"
        
        report += "\n---\n\n## Component Analysis\n\n"
        
        # Group components by category
        categories = {}
        for component in result.components:
            # Determine category from component name/description
            category = self._categorize_component(component)
            if category not in categories:
                categories[category] = []
            categories[category].append(component)
        
        for category, components in categories.items():
            report += f"### {category}\n\n"
            report += "| Component | Status | Location | Notes |\n"
            report += "|-----------|--------|----------|-------|\n"
            
            for component in components:
                status_icon = component.status.value
                location = component.location or "N/A"
                notes = component.notes or ""
                report += f"| **{component.name}** | {status_icon} | `{location}` | {notes} |\n"
            
            report += "\n"
        
        report += "---\n\n## Recommendations\n\n"
        
        for i, recommendation in enumerate(result.recommendations, 1):
            report += f"{i}. {recommendation}\n"
        
        report += f"""
---

## Analysis Details

- **Total Components Analyzed**: {result.total_components}
- **Analysis Timestamp**: {result.timestamp}
- **Project Root**: {self.project_root}

### File Coverage Analysis

"""
        
        file_status = self.analyze_file_existence()
        existing_files = sum(1 for exists in file_status.values() if exists)
        total_expected = len(file_status)
        
        report += f"- **Expected Files**: {total_expected}\n"
        report += f"- **Existing Files**: {existing_files}\n"
        report += f"- **File Coverage**: {(existing_files/total_expected*100):.1f}%\n\n"
        
        report += "#### Missing Files\n\n"
        missing_files = [path for path, exists in file_status.items() if not exists]
        if missing_files:
            for file_path in missing_files:
                report += f"- `{file_path}`\n"
        else:
            report += "✅ All expected files are present!\n"
        
        return report

    def _categorize_component(self, component: Component) -> str:
        """Categorize component for reporting"""
        name_lower = component.name.lower()
        
        if "fast path" in name_lower or "slow path" in name_lower or "votor" in name_lower:
            return "Votor Dual-Path Consensus"
        elif "rotor" in name_lower or "erasure" in name_lower or "shred" in name_lower:
            return "Rotor Block Propagation"
        elif "safety" in name_lower or "conflicting" in name_lower:
            return "Safety Properties"
        elif "liveness" in name_lower or "progress" in name_lower:
            return "Liveness Properties"
        elif "resilience" in name_lower or "byzantine" in name_lower:
            return "Resilience Properties"
        elif "stateright" in name_lower or "rust" in name_lower:
            return "Stateright Implementation"
        elif "reward" in name_lower or "slash" in name_lower or "fee" in name_lower:
            return "Economic Model"
        else:
            return "Advanced Features"

    def _generate_json_report(self, result: GapAnalysisResult) -> str:
        """Generate JSON report"""
        return json.dumps(asdict(result), indent=2, default=str)

    def save_report(self, result: GapAnalysisResult, output_path: str, format: str = "markdown"):
        """Save report to file"""
        report_content = self.generate_report(result, format)
        
        output_file = Path(output_path)
        output_file.parent.mkdir(parents=True, exist_ok=True)
        
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(report_content)
        
        print(f"📄 Report saved to: {output_file}")

def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description="Alpenglow Gap Analysis Tool")
    parser.add_argument("--project-root", default=".", help="Path to project root directory")
    parser.add_argument("--output", default="analysis/gap_analysis_report.md", help="Output file path")
    parser.add_argument("--format", choices=["markdown", "json"], default="markdown", help="Output format")
    parser.add_argument("--verbose", "-v", action="store_true", help="Verbose output")
    
    args = parser.parse_args()
    
    # Initialize analyzer
    analyzer = AlpenglowGapAnalyzer(args.project_root)
    
    # Run analysis
    result = analyzer.run_analysis()
    
    # Print summary
    print(f"\n📊 Analysis Complete!")
    print(f"Overall Completion: {result.overall_completion:.1f}%")
    print(f"Components: {result.implemented_count} ✅ | {result.partial_count} ⚠️ | {result.missing_count} ❌")
    
    if result.critical_gaps:
        print(f"Critical Gaps: {len(result.critical_gaps)}")
        if args.verbose:
            for gap in result.critical_gaps:
                print(f"  - {gap}")
    
    # Save report
    analyzer.save_report(result, args.output, args.format)
    
    # Print recommendations
    if result.recommendations:
        print(f"\n💡 Top Recommendations:")
        for i, rec in enumerate(result.recommendations[:3], 1):
            print(f"  {i}. {rec}")

if __name__ == "__main__":
    main()