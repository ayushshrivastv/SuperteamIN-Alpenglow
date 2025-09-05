#!/usr/bin/env python3
"""
Alpenglow Protocol Verification Coverage Report Generator

This tool generates comprehensive coverage reports showing which parts of the protocol
have been formally verified, which properties have been proven, and which scenarios
have been tested. It provides quantitative metrics on verification completeness.
"""

import os
import re
import json
import argparse
from pathlib import Path
from typing import Dict, List, Tuple, Set, Optional
from dataclasses import dataclass, asdict
from datetime import datetime
import subprocess
import sys

@dataclass
class ModuleStatus:
    """Status of a TLA+ module"""
    name: str
    exists: bool
    parsing: str  # "success", "partial", "failed", "missing"
    type_check: str  # "success", "partial", "failed", "blocked"
    symbol_resolution: str  # "success", "partial", "failed", "missing"
    proof_status: str  # "complete", "partial", "blocked", "missing"
    undefined_symbols: List[str]
    type_errors: List[str]
    missing_operators: List[str]
    proof_obligations: int
    completed_proofs: int

@dataclass
class PropertyStatus:
    """Status of a formal property"""
    name: str
    category: str  # "safety", "liveness", "temporal", "resilience"
    status: str  # "verified", "partial", "blocked", "missing"
    dependencies: List[str]
    blocking_issues: List[str]
    test_coverage: float  # 0.0 to 1.0

@dataclass
class ConfigurationStatus:
    """Status of a model checking configuration"""
    name: str
    syntax_valid: bool
    constants_defined: bool
    invariants_valid: bool
    can_execute: bool
    validators: int
    byzantine_percent: float
    offline_percent: float
    states_explored: int
    verification_time: Optional[float]
    memory_usage: Optional[str]

@dataclass
class CoverageMetrics:
    """Overall coverage metrics"""
    total_modules: int
    working_modules: int
    total_properties: int
    verified_properties: int
    total_configurations: int
    working_configurations: int
    symbol_resolution_rate: float
    type_consistency_rate: float
    proof_completion_rate: float
    overall_completion: float

class VerificationCoverageAnalyzer:
    """Analyzes verification coverage across the Alpenglow protocol"""
    
    def __init__(self, project_root: str):
        self.project_root = Path(project_root)
        self.specs_dir = self.project_root / "specs"
        self.proofs_dir = self.project_root / "proofs"
        self.models_dir = self.project_root / "models"
        self.docs_dir = self.project_root / "docs"
        
        # Known modules and their expected status
        self.expected_modules = {
            "Alpenglow.tla": {"category": "core", "critical": True},
            "Votor.tla": {"category": "consensus", "critical": True},
            "Rotor.tla": {"category": "propagation", "critical": True},
            "Network.tla": {"category": "network", "critical": True},
            "NetworkIntegration.tla": {"category": "integration", "critical": True},
            "Safety.tla": {"category": "proof", "critical": True},
            "Liveness.tla": {"category": "proof", "critical": True},
            "Resilience.tla": {"category": "proof", "critical": True},
            "Types.tla": {"category": "utility", "critical": True},
            "Utils.tla": {"category": "utility", "critical": True},
            "Crypto.tla": {"category": "utility", "critical": True},
            "Integration.tla": {"category": "integration", "critical": False},
            "EconomicModel.tla": {"category": "economic", "critical": False},
            "AdvancedNetwork.tla": {"category": "network", "critical": False}
        }
        
        # Known properties to verify
        self.expected_properties = {
            "Safety": {"category": "safety", "critical": True},
            "EventualProgress": {"category": "liveness", "critical": True},
            "FastPathFinalization": {"category": "liveness", "critical": True},
            "SlowPathFinalization": {"category": "liveness", "critical": True},
            "ViewSynchronization": {"category": "liveness", "critical": True},
            "ByzantineResilience": {"category": "resilience", "critical": True},
            "OfflineResilience": {"category": "resilience", "critical": True},
            "CombinedResilience": {"category": "resilience", "critical": True},
            "TypeInvariant": {"category": "safety", "critical": True},
            "VotingPowerConsistency": {"category": "safety", "critical": True}
        }
        
        # Known configurations
        self.expected_configurations = {
            "Small.cfg": {"validators": 3, "byzantine": 0, "offline": 0},
            "Test.cfg": {"validators": 4, "byzantine": 1, "offline": 0},
            "Medium.cfg": {"validators": 10, "byzantine": 2, "offline": 2},
            "EdgeCase.cfg": {"validators": 5, "byzantine": 1, "offline": 1},
            "EndToEnd.cfg": {"validators": 7, "byzantine": 1, "offline": 1},
            "LargeScale.cfg": {"validators": 20, "byzantine": 4, "offline": 4},
            "Performance.cfg": {"validators": 10, "byzantine": 0, "offline": 0},
            "Adversarial.cfg": {"validators": 15, "byzantine": 3, "offline": 0}
        }

    def analyze_module(self, module_path: Path) -> ModuleStatus:
        """Analyze a single TLA+ module"""
        module_name = module_path.name
        
        if not module_path.exists():
            return ModuleStatus(
                name=module_name,
                exists=False,
                parsing="missing",
                type_check="missing",
                symbol_resolution="missing",
                proof_status="missing",
                undefined_symbols=[],
                type_errors=[],
                missing_operators=[],
                proof_obligations=0,
                completed_proofs=0
            )
        
        # Read module content
        try:
            content = module_path.read_text()
        except Exception as e:
            return ModuleStatus(
                name=module_name,
                exists=True,
                parsing="failed",
                type_check="failed",
                symbol_resolution="failed",
                proof_status="failed",
                undefined_symbols=[f"Read error: {e}"],
                type_errors=[],
                missing_operators=[],
                proof_obligations=0,
                completed_proofs=0
            )
        
        # Analyze content
        undefined_symbols = self._find_undefined_symbols(content, module_name)
        type_errors = self._find_type_errors(content, module_name)
        missing_operators = self._find_missing_operators(content, module_name)
        proof_obligations, completed_proofs = self._analyze_proofs(content)
        
        # Determine status levels
        parsing = self._determine_parsing_status(content, undefined_symbols)
        type_check = self._determine_type_status(type_errors, undefined_symbols)
        symbol_resolution = self._determine_symbol_status(undefined_symbols, missing_operators)
        proof_status = self._determine_proof_status(proof_obligations, completed_proofs, undefined_symbols)
        
        return ModuleStatus(
            name=module_name,
            exists=True,
            parsing=parsing,
            type_check=type_check,
            symbol_resolution=symbol_resolution,
            proof_status=proof_status,
            undefined_symbols=undefined_symbols,
            type_errors=type_errors,
            missing_operators=missing_operators,
            proof_obligations=proof_obligations,
            completed_proofs=completed_proofs
        )

    def _find_undefined_symbols(self, content: str, module_name: str) -> List[str]:
        """Find undefined symbols in module content"""
        undefined = []
        
        # Known problematic symbols from verification report
        known_issues = {
            "Safety.tla": ["certificates", "RequiredStake", "FastCertificate", "SlowCertificate"],
            "Liveness.tla": ["MessageDelay", "EventualDelivery", "AllMessagesDelivered", 
                           "currentRotor", "FastCertificate", "SlowCertificate"],
            "Resilience.tla": ["SplitVotingAttack", "InsufficientStakeLemma", "CertificateCompositionLemma"],
            "Types.tla": ["TotalStakeSum", "StakeOfSet", "FastPathThreshold", "SlowPathThreshold"],
            "Alpenglow.tla": ["currentRotor"],
            "Network.tla": ["MessageDelay", "EventualDelivery", "PartialSynchrony"]
        }
        
        if module_name in known_issues:
            # Check if these symbols are actually defined
            for symbol in known_issues[module_name]:
                if symbol not in content or not re.search(rf'\b{symbol}\s*==', content):
                    undefined.append(symbol)
        
        # Look for EXTENDS/INSTANCE references to missing modules
        extends_pattern = r'EXTENDS\s+([A-Za-z0-9_, ]+)'
        instance_pattern = r'INSTANCE\s+([A-Za-z0-9_]+)'
        
        for match in re.finditer(extends_pattern, content):
            modules = [m.strip() for m in match.group(1).split(',')]
            for mod in modules:
                if mod not in ['TLC', 'Integers', 'Sequences', 'FiniteSets', 'Naturals']:
                    mod_path = self.specs_dir / f"{mod}.tla"
                    if not mod_path.exists():
                        undefined.append(f"Missing module: {mod}")
        
        for match in re.finditer(instance_pattern, content):
            mod = match.group(1).strip()
            if mod not in ['TLC', 'Integers', 'Sequences', 'FiniteSets', 'Naturals']:
                mod_path = self.specs_dir / f"{mod}.tla"
                if not mod_path.exists():
                    undefined.append(f"Missing module: {mod}")
        
        return undefined

    def _find_type_errors(self, content: str, module_name: str) -> List[str]:
        """Find type consistency errors"""
        errors = []
        
        # Known type issues from verification report
        if module_name == "Alpenglow.tla":
            if "messages" in content:
                # Check if messages is used both as set and function
                set_usage = re.search(r'messages\s*\in\s*SUBSET', content)
                func_usage = re.search(r'messages\[', content)
                if set_usage and func_usage:
                    errors.append("messages used as both set and function")
        
        if module_name == "Votor.tla":
            # Check for double-binding issues
            if "currentTime" in content and "clock" in content:
                errors.append("Potential double-binding of currentTime/clock")
        
        return errors

    def _find_missing_operators(self, content: str, module_name: str) -> List[str]:
        """Find references to missing operators"""
        missing = []
        
        # Look for operator calls that might not be defined
        operator_calls = re.findall(r'([A-Z][A-Za-z0-9_]*)\s*\(', content)
        operator_refs = re.findall(r'([A-Z][A-Za-z0-9_]*)\s*==', content)
        
        defined_operators = set(operator_refs)
        
        for op in operator_calls:
            if op not in defined_operators and op not in ['SUBSET', 'DOMAIN', 'UNION', 'LET']:
                # Check if it's defined in extended modules (simplified check)
                if op not in content:
                    missing.append(op)
        
        return list(set(missing))

    def _analyze_proofs(self, content: str) -> Tuple[int, int]:
        """Analyze proof obligations and completion"""
        # Count THEOREM statements
        theorems = len(re.findall(r'THEOREM\s+\w+', content))
        
        # Count LEMMA statements
        lemmas = len(re.findall(r'LEMMA\s+\w+', content))
        
        total_obligations = theorems + lemmas
        
        # Count completed proofs (those with actual proof content, not just stubs)
        proof_blocks = re.findall(r'PROOF.*?(?=THEOREM|LEMMA|====|$)', content, re.DOTALL)
        completed = 0
        
        for proof in proof_blocks:
            # Check if proof has substantial content (not just "BY DEF" or "OBVIOUS")
            if len(proof.strip()) > 20 and not re.match(r'PROOF\s+(BY\s+DEF|OBVIOUS)', proof.strip()):
                completed += 1
        
        return total_obligations, completed

    def _determine_parsing_status(self, content: str, undefined_symbols: List[str]) -> str:
        """Determine parsing status"""
        if not content.strip():
            return "failed"
        
        # Check for basic TLA+ structure
        if not re.search(r'----\s*MODULE', content):
            return "failed"
        
        if any("Missing module:" in sym for sym in undefined_symbols):
            return "partial"
        
        return "success"

    def _determine_type_status(self, type_errors: List[str], undefined_symbols: List[str]) -> str:
        """Determine type checking status"""
        if type_errors:
            return "failed"
        
        if undefined_symbols:
            return "blocked"
        
        return "success"

    def _determine_symbol_status(self, undefined_symbols: List[str], missing_operators: List[str]) -> str:
        """Determine symbol resolution status"""
        if undefined_symbols or missing_operators:
            if len(undefined_symbols) + len(missing_operators) > 5:
                return "failed"
            else:
                return "partial"
        
        return "success"

    def _determine_proof_status(self, obligations: int, completed: int, undefined_symbols: List[str]) -> str:
        """Determine proof completion status"""
        if undefined_symbols:
            return "blocked"
        
        if obligations == 0:
            return "missing"
        
        completion_rate = completed / obligations if obligations > 0 else 0
        
        if completion_rate >= 0.9:
            return "complete"
        elif completion_rate >= 0.5:
            return "partial"
        else:
            return "blocked"

    def analyze_property(self, property_name: str) -> PropertyStatus:
        """Analyze the status of a formal property"""
        # This would need to be enhanced with actual property checking
        # For now, use heuristics based on module analysis
        
        category = self.expected_properties.get(property_name, {}).get("category", "unknown")
        
        # Determine status based on related modules
        if property_name == "Safety":
            safety_module = self.analyze_module(self.proofs_dir / "Safety.tla")
            if safety_module.symbol_resolution == "success" and safety_module.proof_status == "complete":
                status = "verified"
            elif safety_module.exists:
                status = "partial"
            else:
                status = "missing"
        else:
            # Default heuristic
            status = "blocked"  # Most properties are currently blocked
        
        return PropertyStatus(
            name=property_name,
            category=category,
            status=status,
            dependencies=[],
            blocking_issues=[],
            test_coverage=0.0
        )

    def analyze_configuration(self, config_path: Path) -> ConfigurationStatus:
        """Analyze a model checking configuration"""
        config_name = config_path.name
        expected = self.expected_configurations.get(config_name, {})
        
        if not config_path.exists():
            return ConfigurationStatus(
                name=config_name,
                syntax_valid=False,
                constants_defined=False,
                invariants_valid=False,
                can_execute=False,
                validators=expected.get("validators", 0),
                byzantine_percent=expected.get("byzantine", 0),
                offline_percent=expected.get("offline", 0),
                states_explored=0,
                verification_time=None,
                memory_usage=None
            )
        
        try:
            content = config_path.read_text()
        except:
            return ConfigurationStatus(
                name=config_name,
                syntax_valid=False,
                constants_defined=False,
                invariants_valid=False,
                can_execute=False,
                validators=expected.get("validators", 0),
                byzantine_percent=expected.get("byzantine", 0),
                offline_percent=expected.get("offline", 0),
                states_explored=0,
                verification_time=None,
                memory_usage=None
            )
        
        # Analyze configuration content
        syntax_valid = self._check_config_syntax(content)
        constants_defined = self._check_constants_defined(content)
        invariants_valid = self._check_invariants_valid(content)
        
        return ConfigurationStatus(
            name=config_name,
            syntax_valid=syntax_valid,
            constants_defined=constants_defined,
            invariants_valid=invariants_valid,
            can_execute=syntax_valid and constants_defined and invariants_valid,
            validators=expected.get("validators", 0),
            byzantine_percent=expected.get("byzantine", 0),
            offline_percent=expected.get("offline", 0),
            states_explored=0,  # Would need to run TLC to get actual numbers
            verification_time=None,
            memory_usage=None
        )

    def _check_config_syntax(self, content: str) -> bool:
        """Check if configuration has valid TLC syntax"""
        # Look for common syntax errors mentioned in verification report
        if re.search(r'Stake\s*=\s*\[.*\|->.*\]', content):
            return False  # Invalid TLC syntax for functions
        
        return True

    def _check_constants_defined(self, content: str) -> bool:
        """Check if required constants are defined"""
        required_constants = ['Validators', 'Stake', 'InitialView']
        
        for const in required_constants:
            if const not in content:
                return False
        
        return True

    def _check_invariants_valid(self, content: str) -> bool:
        """Check if invariants reference valid operators"""
        # This is a simplified check
        if "INVARIANT" in content:
            # Check for references to undefined operators
            if "UndefinedOperator" in content:
                return False
        
        return True

    def calculate_metrics(self, modules: List[ModuleStatus], 
                         properties: List[PropertyStatus],
                         configurations: List[ConfigurationStatus]) -> CoverageMetrics:
        """Calculate overall coverage metrics"""
        
        # Module metrics
        total_modules = len(modules)
        working_modules = sum(1 for m in modules if m.parsing == "success" and m.symbol_resolution == "success")
        
        # Property metrics
        total_properties = len(properties)
        verified_properties = sum(1 for p in properties if p.status == "verified")
        
        # Configuration metrics
        total_configurations = len(configurations)
        working_configurations = sum(1 for c in configurations if c.can_execute)
        
        # Symbol resolution rate
        symbol_success = sum(1 for m in modules if m.symbol_resolution == "success")
        symbol_resolution_rate = symbol_success / total_modules if total_modules > 0 else 0
        
        # Type consistency rate
        type_success = sum(1 for m in modules if m.type_check == "success")
        type_consistency_rate = type_success / total_modules if total_modules > 0 else 0
        
        # Proof completion rate
        total_obligations = sum(m.proof_obligations for m in modules)
        completed_proofs = sum(m.completed_proofs for m in modules)
        proof_completion_rate = completed_proofs / total_obligations if total_obligations > 0 else 0
        
        # Overall completion (weighted average)
        weights = {
            'modules': 0.3,
            'properties': 0.3,
            'configurations': 0.2,
            'proofs': 0.2
        }
        
        module_rate = working_modules / total_modules if total_modules > 0 else 0
        property_rate = verified_properties / total_properties if total_properties > 0 else 0
        config_rate = working_configurations / total_configurations if total_configurations > 0 else 0
        
        overall_completion = (
            weights['modules'] * module_rate +
            weights['properties'] * property_rate +
            weights['configurations'] * config_rate +
            weights['proofs'] * proof_completion_rate
        )
        
        return CoverageMetrics(
            total_modules=total_modules,
            working_modules=working_modules,
            total_properties=total_properties,
            verified_properties=verified_properties,
            total_configurations=total_configurations,
            working_configurations=working_configurations,
            symbol_resolution_rate=symbol_resolution_rate,
            type_consistency_rate=type_consistency_rate,
            proof_completion_rate=proof_completion_rate,
            overall_completion=overall_completion
        )

    def generate_report(self, output_format: str = "text") -> str:
        """Generate comprehensive coverage report"""
        
        # Analyze all components
        modules = []
        for module_name in self.expected_modules:
            module_path = self.specs_dir / module_name
            if not module_path.exists():
                module_path = self.proofs_dir / module_name
            modules.append(self.analyze_module(module_path))
        
        properties = []
        for property_name in self.expected_properties:
            properties.append(self.analyze_property(property_name))
        
        configurations = []
        for config_name in self.expected_configurations:
            config_path = self.models_dir / config_name
            configurations.append(self.analyze_configuration(config_path))
        
        metrics = self.calculate_metrics(modules, properties, configurations)
        
        if output_format == "json":
            return self._generate_json_report(modules, properties, configurations, metrics)
        else:
            return self._generate_text_report(modules, properties, configurations, metrics)

    def _generate_text_report(self, modules: List[ModuleStatus], 
                             properties: List[PropertyStatus],
                             configurations: List[ConfigurationStatus],
                             metrics: CoverageMetrics) -> str:
        """Generate text format report"""
        
        report = []
        report.append("=" * 80)
        report.append("ALPENGLOW PROTOCOL VERIFICATION COVERAGE REPORT")
        report.append("=" * 80)
        report.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        report.append("")
        
        # Executive Summary
        report.append("EXECUTIVE SUMMARY")
        report.append("-" * 40)
        report.append(f"Overall Completion: {metrics.overall_completion:.1%}")
        report.append(f"Working Modules: {metrics.working_modules}/{metrics.total_modules} ({metrics.working_modules/metrics.total_modules:.1%})")
        report.append(f"Verified Properties: {metrics.verified_properties}/{metrics.total_properties} ({metrics.verified_properties/metrics.total_properties:.1%})")
        report.append(f"Working Configurations: {metrics.working_configurations}/{metrics.total_configurations} ({metrics.working_configurations/metrics.total_configurations:.1%})")
        report.append(f"Symbol Resolution Rate: {metrics.symbol_resolution_rate:.1%}")
        report.append(f"Type Consistency Rate: {metrics.type_consistency_rate:.1%}")
        report.append(f"Proof Completion Rate: {metrics.proof_completion_rate:.1%}")
        report.append("")
        
        # Module Analysis
        report.append("MODULE ANALYSIS")
        report.append("-" * 40)
        report.append(f"{'Module':<25} {'Parse':<8} {'Types':<8} {'Symbols':<8} {'Proofs':<8} {'Issues':<6}")
        report.append("-" * 80)
        
        for module in sorted(modules, key=lambda m: m.name):
            issues = len(module.undefined_symbols) + len(module.type_errors) + len(module.missing_operators)
            status_symbols = {
                "success": "✅", "partial": "⚠️", "failed": "❌", "missing": "❌", "blocked": "🚫"
            }
            
            parse_sym = status_symbols.get(module.parsing, "❓")
            type_sym = status_symbols.get(module.type_check, "❓")
            symbol_sym = status_symbols.get(module.symbol_resolution, "❓")
            proof_sym = status_symbols.get(module.proof_status, "❓")
            
            report.append(f"{module.name:<25} {parse_sym:<8} {type_sym:<8} {symbol_sym:<8} {proof_sym:<8} {issues:<6}")
        
        report.append("")
        
        # Critical Issues
        report.append("CRITICAL ISSUES")
        report.append("-" * 40)
        
        critical_modules = [m for m in modules if m.undefined_symbols or m.type_errors]
        if critical_modules:
            for module in critical_modules:
                report.append(f"\n{module.name}:")
                if module.undefined_symbols:
                    report.append(f"  Undefined symbols: {', '.join(module.undefined_symbols[:5])}")
                    if len(module.undefined_symbols) > 5:
                        report.append(f"  ... and {len(module.undefined_symbols) - 5} more")
                if module.type_errors:
                    report.append(f"  Type errors: {', '.join(module.type_errors)}")
                if module.missing_operators:
                    report.append(f"  Missing operators: {', '.join(module.missing_operators[:3])}")
                    if len(module.missing_operators) > 3:
                        report.append(f"  ... and {len(module.missing_operators) - 3} more")
        else:
            report.append("No critical issues found in module analysis.")
        
        report.append("")
        
        # Property Status
        report.append("PROPERTY VERIFICATION STATUS")
        report.append("-" * 40)
        report.append(f"{'Property':<25} {'Category':<12} {'Status':<10} {'Coverage':<8}")
        report.append("-" * 60)
        
        for prop in sorted(properties, key=lambda p: p.name):
            status_sym = {"verified": "✅", "partial": "⚠️", "blocked": "🚫", "missing": "❌"}.get(prop.status, "❓")
            coverage = f"{prop.test_coverage:.1%}" if prop.test_coverage > 0 else "0%"
            report.append(f"{prop.name:<25} {prop.category:<12} {status_sym:<10} {coverage:<8}")
        
        report.append("")
        
        # Configuration Status
        report.append("CONFIGURATION STATUS")
        report.append("-" * 40)
        report.append(f"{'Configuration':<20} {'Syntax':<8} {'Constants':<10} {'Invariants':<10} {'Executable':<10}")
        report.append("-" * 70)
        
        for config in sorted(configurations, key=lambda c: c.name):
            syntax_sym = "✅" if config.syntax_valid else "❌"
            const_sym = "✅" if config.constants_defined else "❌"
            inv_sym = "✅" if config.invariants_valid else "❌"
            exec_sym = "✅" if config.can_execute else "❌"
            
            report.append(f"{config.name:<20} {syntax_sym:<8} {const_sym:<10} {inv_sym:<10} {exec_sym:<10}")
        
        report.append("")
        
        # Recommendations
        report.append("RECOMMENDATIONS")
        report.append("-" * 40)
        
        if metrics.symbol_resolution_rate < 0.5:
            report.append("🔴 CRITICAL: Symbol resolution rate is very low. Focus on:")
            report.append("   - Creating missing modules (Utils.tla, Crypto.tla, NetworkIntegration.tla)")
            report.append("   - Defining undefined operators and symbols")
            report.append("   - Fixing module dependencies")
        
        if metrics.type_consistency_rate < 0.7:
            report.append("🟡 HIGH: Type consistency issues need attention:")
            report.append("   - Standardize variable types across modules")
            report.append("   - Fix double-binding issues")
            report.append("   - Resolve function vs set usage conflicts")
        
        if metrics.proof_completion_rate < 0.3:
            report.append("🟡 MEDIUM: Proof completion is low:")
            report.append("   - Complete theorem proof implementations")
            report.append("   - Replace proof stubs with actual logical arguments")
            report.append("   - Add missing lemmas and helper proofs")
        
        working_configs = sum(1 for c in configurations if c.can_execute)
        if working_configs == 0:
            report.append("🔴 CRITICAL: No working configurations available:")
            report.append("   - Fix syntax errors in .cfg files")
            report.append("   - Define required constants")
            report.append("   - Validate invariant references")
        
        report.append("")
        report.append("=" * 80)
        
        return "\n".join(report)

    def _generate_json_report(self, modules: List[ModuleStatus], 
                             properties: List[PropertyStatus],
                             configurations: List[ConfigurationStatus],
                             metrics: CoverageMetrics) -> str:
        """Generate JSON format report"""
        
        report_data = {
            "timestamp": datetime.now().isoformat(),
            "summary": asdict(metrics),
            "modules": [asdict(m) for m in modules],
            "properties": [asdict(p) for p in properties],
            "configurations": [asdict(c) for c in configurations],
            "recommendations": self._generate_recommendations(metrics, modules, configurations)
        }
        
        return json.dumps(report_data, indent=2)

    def _generate_recommendations(self, metrics: CoverageMetrics, 
                                 modules: List[ModuleStatus],
                                 configurations: List[ConfigurationStatus]) -> List[Dict]:
        """Generate actionable recommendations"""
        recommendations = []
        
        if metrics.symbol_resolution_rate < 0.5:
            recommendations.append({
                "priority": "critical",
                "category": "symbol_resolution",
                "title": "Fix undefined symbols",
                "description": "Multiple modules have undefined symbols preventing verification",
                "actions": [
                    "Create missing modules: Utils.tla, Crypto.tla, NetworkIntegration.tla",
                    "Define undefined operators in existing modules",
                    "Fix module dependency chains"
                ]
            })
        
        if metrics.type_consistency_rate < 0.7:
            recommendations.append({
                "priority": "high",
                "category": "type_consistency",
                "title": "Resolve type inconsistencies",
                "description": "Type errors are blocking model checking",
                "actions": [
                    "Standardize variable types across modules",
                    "Fix function vs set usage conflicts",
                    "Resolve parameter binding issues"
                ]
            })
        
        working_configs = sum(1 for c in configurations if c.can_execute)
        if working_configs == 0:
            recommendations.append({
                "priority": "critical",
                "category": "configurations",
                "title": "Fix configuration files",
                "description": "No working configurations available for model checking",
                "actions": [
                    "Fix TLC syntax errors in .cfg files",
                    "Define all required constants",
                    "Validate invariant references"
                ]
            })
        
        return recommendations


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description="Generate Alpenglow verification coverage report")
    parser.add_argument("project_root", help="Path to the Alpenglow project root")
    parser.add_argument("--format", choices=["text", "json"], default="text", 
                       help="Output format (default: text)")
    parser.add_argument("--output", "-o", help="Output file (default: stdout)")
    parser.add_argument("--verbose", "-v", action="store_true", 
                       help="Verbose output")
    
    args = parser.parse_args()
    
    if not os.path.exists(args.project_root):
        print(f"Error: Project root '{args.project_root}' does not exist", file=sys.stderr)
        sys.exit(1)
    
    try:
        analyzer = VerificationCoverageAnalyzer(args.project_root)
        report = analyzer.generate_report(args.format)
        
        if args.output:
            with open(args.output, 'w') as f:
                f.write(report)
            if args.verbose:
                print(f"Report written to {args.output}")
        else:
            print(report)
            
    except Exception as e:
        print(f"Error generating report: {e}", file=sys.stderr)
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()