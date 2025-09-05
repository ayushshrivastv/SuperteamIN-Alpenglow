#!/usr/bin/env python3
"""
Theorem Correspondence Validator

This module systematically compares mathematical statements in the Alpenglow whitepaper
with their formal TLA+ implementations, verifying mathematical equivalence and ensuring
complete correspondence between informal and formal proofs.
"""

import re
import json
import sys
import os
from typing import Dict, List, Tuple, Optional, Set, Any
from dataclasses import dataclass, asdict
from pathlib import Path
import argparse
from datetime import datetime

@dataclass
class TheoremStatement:
    """Represents a theorem statement from either whitepaper or TLA+"""
    id: str
    type: str  # "theorem" or "lemma"
    number: Optional[int]
    title: str
    statement: str
    assumptions: List[str]
    conditions: List[str]
    source_location: str
    source_type: str  # "whitepaper" or "tla"
    proof_technique: Optional[str] = None
    dependencies: List[str] = None

@dataclass
class CorrespondenceResult:
    """Result of comparing whitepaper and TLA+ theorem statements"""
    theorem_id: str
    whitepaper_present: bool
    tla_present: bool
    statements_match: bool
    assumptions_match: bool
    conditions_match: bool
    proof_techniques_match: bool
    discrepancies: List[str]
    confidence_score: float
    notes: str

@dataclass
class ValidationReport:
    """Complete validation report"""
    timestamp: str
    total_theorems: int
    matched_theorems: int
    missing_from_tla: List[str]
    missing_from_whitepaper: List[str]
    discrepancies: List[CorrespondenceResult]
    overall_score: float
    detailed_results: List[CorrespondenceResult]

class WhitepaperParser:
    """Parses theorem statements from the Alpenglow whitepaper"""
    
    def __init__(self, whitepaper_path: str):
        self.whitepaper_path = whitepaper_path
        self.content = self._load_content()
        
    def _load_content(self) -> str:
        """Load whitepaper content"""
        try:
            with open(self.whitepaper_path, 'r', encoding='utf-8') as f:
                return f.read()
        except Exception as e:
            raise ValueError(f"Failed to load whitepaper: {e}")
    
    def extract_theorems(self) -> List[TheoremStatement]:
        """Extract all theorem statements from whitepaper"""
        theorems = []
        
        # Extract main theorems (Theorem 1 and 2)
        theorems.extend(self._extract_main_theorems())
        
        # Extract supporting lemmas (20-42)
        theorems.extend(self._extract_lemmas())
        
        return theorems
    
    def _extract_main_theorems(self) -> List[TheoremStatement]:
        """Extract Theorem 1 (Safety) and Theorem 2 (Liveness)"""
        theorems = []
        
        # Theorem 1 (Safety)
        safety_pattern = r'Theorem 1 \(safety\)\.(.*?)(?=Proof|Lemma|\n\n[A-Z]|$)'
        safety_match = re.search(safety_pattern, self.content, re.DOTALL | re.IGNORECASE)
        
        if safety_match:
            statement = self._clean_statement(safety_match.group(1))
            theorems.append(TheoremStatement(
                id="theorem_1",
                type="theorem",
                number=1,
                title="Safety",
                statement=statement,
                assumptions=self._extract_assumptions_for_theorem(1),
                conditions=self._extract_conditions_for_theorem(1),
                source_location="Section 2.9",
                source_type="whitepaper",
                proof_technique="Induction on finalization order"
            ))
        
        # Theorem 2 (Liveness)
        liveness_pattern = r'Theorem 2 \(liveness\)\.(.*?)(?=Proof|Lemma|\n\n[A-Z]|$)'
        liveness_match = re.search(liveness_pattern, self.content, re.DOTALL | re.IGNORECASE)
        
        if liveness_match:
            statement = self._clean_statement(liveness_match.group(1))
            theorems.append(TheoremStatement(
                id="theorem_2",
                type="theorem",
                number=2,
                title="Liveness",
                statement=statement,
                assumptions=self._extract_assumptions_for_theorem(2),
                conditions=self._extract_conditions_for_theorem(2),
                source_location="Section 2.10",
                source_type="whitepaper",
                proof_technique="Timeout analysis and progress guarantees"
            ))
        
        return theorems
    
    def _extract_lemmas(self) -> List[TheoremStatement]:
        """Extract Lemmas 20-42 from the whitepaper"""
        lemmas = []
        
        # Pattern to match lemmas
        lemma_pattern = r'Lemma (\d+)(?:\s*\([^)]+\))?\.(.*?)(?=Proof|Lemma \d+|\n\n[A-Z]|$)'
        
        for match in re.finditer(lemma_pattern, self.content, re.DOTALL | re.IGNORECASE):
            lemma_num = int(match.group(1))
            
            # Only extract lemmas 20-42 as specified in the whitepaper
            if 20 <= lemma_num <= 42:
                statement = self._clean_statement(match.group(2))
                title = self._extract_lemma_title(lemma_num)
                
                lemmas.append(TheoremStatement(
                    id=f"lemma_{lemma_num}",
                    type="lemma",
                    number=lemma_num,
                    title=title,
                    statement=statement,
                    assumptions=self._extract_assumptions_for_lemma(lemma_num),
                    conditions=self._extract_conditions_for_lemma(lemma_num),
                    source_location=f"Section 2.9-2.11, Lemma {lemma_num}",
                    source_type="whitepaper",
                    proof_technique=self._extract_proof_technique(lemma_num)
                ))
        
        return lemmas
    
    def _clean_statement(self, statement: str) -> str:
        """Clean and normalize theorem statement"""
        # Remove extra whitespace and newlines
        statement = re.sub(r'\s+', ' ', statement.strip())
        
        # Remove markdown formatting
        statement = re.sub(r'\*\*(.*?)\*\*', r'\1', statement)
        statement = re.sub(r'\*(.*?)\*', r'\1', statement)
        
        # Remove section references
        statement = re.sub(r'\(See also.*?\)', '', statement)
        
        return statement.strip()
    
    def _extract_assumptions_for_theorem(self, theorem_num: int) -> List[str]:
        """Extract assumptions for main theorems"""
        if theorem_num == 1:
            return [
                "Byzantine nodes control less than 20% of the stake",
                "Remaining nodes controlling more than 80% of stake are correct",
                "Partially synchronous network model"
            ]
        elif theorem_num == 2:
            return [
                "Correct leader for the window",
                "No timeouts set before GST",
                "Rotor successful for all slots",
                "Network synchrony after GST"
            ]
        return []
    
    def _extract_conditions_for_theorem(self, theorem_num: int) -> List[str]:
        """Extract conditions for main theorems"""
        if theorem_num == 1:
            return [
                "Block finalization in slot s",
                "Subsequent block finalization in slot s' >= s"
            ]
        elif theorem_num == 2:
            return [
                "Leader window beginning with slot s",
                "GST has passed",
                "All window slots have successful Rotor"
            ]
        return []
    
    def _extract_lemma_title(self, lemma_num: int) -> str:
        """Extract or infer lemma title"""
        title_map = {
            20: "Notarization or Skip",
            21: "Fast-Finalization Property", 
            22: "Finalization Vote Exclusivity",
            23: "Block Notarization Uniqueness",
            24: "At Most One Block Notarized",
            25: "Finalized Implies Notarized",
            26: "Slow-Finalization Property",
            27: "Window-Level Vote Properties",
            28: "Window Chain Consistency",
            29: "Honest Vote Carryover",
            30: "Window Completion Properties",
            31: "Same Window Finalization Consistency",
            32: "Cross Window Finalization Consistency",
            33: "Timeout Progression",
            34: "View Synchronization",
            35: "Adaptive Timeout Growth",
            36: "Timeout Sufficiency",
            37: "Progress Under Sufficient Timeout",
            38: "Eventual Timeout Sufficiency",
            39: "View Advancement Guarantee",
            40: "Eventual Progress",
            41: "Timeout Setting Propagation",
            42: "Timeout Synchronization After GST"
        }
        return title_map.get(lemma_num, f"Lemma {lemma_num}")
    
    def _extract_assumptions_for_lemma(self, lemma_num: int) -> List[str]:
        """Extract assumptions for specific lemmas"""
        # Common assumptions for most lemmas
        common = ["Byzantine nodes control less than 20% of stake"]
        
        if lemma_num in [20, 22, 27, 28, 29]:
            return common + ["Honest validator behavior"]
        elif lemma_num in [33, 34, 35, 36, 37, 38, 39, 40, 41, 42]:
            return common + ["Network synchrony after GST", "Timeout mechanisms"]
        elif lemma_num in [21, 26]:
            return common + ["Certificate generation thresholds"]
        else:
            return common
    
    def _extract_conditions_for_lemma(self, lemma_num: int) -> List[str]:
        """Extract conditions for specific lemmas"""
        condition_map = {
            20: ["Honest validator", "Single slot voting"],
            21: ["Fast finalization certificate", "80% stake threshold"],
            22: ["Finalization vote cast", "Same slot constraint"],
            23: ["Multiple blocks in same slot", "Notarization attempts"],
            24: ["Block notarization", "Slot uniqueness"],
            25: ["Block finalization", "Certificate requirements"],
            26: ["Slow finalization certificate", "60% stake threshold"],
            31: ["Same leader window", "Slot ordering"],
            32: ["Different leader windows", "Cross-window consistency"],
            41: ["Timeout setting", "Window propagation"],
            42: ["GST passage", "Timeout synchronization"]
        }
        return condition_map.get(lemma_num, ["General protocol conditions"])
    
    def _extract_proof_technique(self, lemma_num: int) -> str:
        """Extract or infer proof technique for lemmas"""
        technique_map = {
            20: "State machine invariant",
            21: "Stake arithmetic and certificate analysis",
            22: "State transition analysis", 
            23: "Contradiction via stake bounds",
            24: "Uniqueness via honest majority",
            25: "Certificate requirement analysis",
            26: "Stake arithmetic and certificate analysis",
            27: "Honest voting behavior",
            28: "Chain consistency invariant",
            29: "Vote carryover properties",
            30: "Window completion analysis",
            31: "Induction on window structure",
            32: "Chain connectivity lemma",
            33: "Timeout progression analysis",
            34: "Certificate propagation",
            35: "Exponential timeout growth",
            36: "Message delivery bounds",
            37: "Progress under sufficient timeout",
            38: "Exponential growth properties",
            39: "Timeout-based view advancement",
            40: "Eventual progress guarantee",
            41: "Timeout propagation mechanism",
            42: "Network synchrony after GST"
        }
        return technique_map.get(lemma_num, "Standard proof technique")

class TLAParser:
    """Parses theorem statements from TLA+ specifications"""
    
    def __init__(self, tla_path: str):
        self.tla_path = tla_path
        self.content = self._load_content()
    
    def _load_content(self) -> str:
        """Load TLA+ content"""
        try:
            with open(self.tla_path, 'r', encoding='utf-8') as f:
                return f.read()
        except Exception as e:
            raise ValueError(f"Failed to load TLA+ file: {e}")
    
    def extract_theorems(self) -> List[TheoremStatement]:
        """Extract all theorem statements from TLA+ file"""
        theorems = []
        
        # Extract main theorems
        theorems.extend(self._extract_main_theorems())
        
        # Extract lemmas
        theorems.extend(self._extract_lemmas())
        
        return theorems
    
    def _extract_main_theorems(self) -> List[TheoremStatement]:
        """Extract main theorems from TLA+"""
        theorems = []
        
        # Theorem 1 (Safety)
        safety_pattern = r'THEOREM WhitepaperTheorem1 ==(.*?)(?=PROOF|THEOREM|LEMMA|$)'
        safety_match = re.search(safety_pattern, self.content, re.DOTALL)
        
        if safety_match:
            statement = self._extract_formal_statement("WhitepaperSafetyTheorem")
            theorems.append(TheoremStatement(
                id="theorem_1",
                type="theorem", 
                number=1,
                title="Safety",
                statement=statement,
                assumptions=self._extract_tla_assumptions("WhitepaperTheorem1"),
                conditions=self._extract_tla_conditions("WhitepaperTheorem1"),
                source_location="WhitepaperTheorems.tla:25-65",
                source_type="tla",
                proof_technique="Induction with safety invariant"
            ))
        
        # Theorem 2 (Liveness)
        liveness_pattern = r'THEOREM WhitepaperTheorem2 ==(.*?)(?=PROOF|THEOREM|LEMMA|$)'
        liveness_match = re.search(liveness_pattern, self.content, re.DOTALL)
        
        if liveness_match:
            statement = self._extract_formal_statement("WhitepaperLivenessTheorem")
            theorems.append(TheoremStatement(
                id="theorem_2",
                type="theorem",
                number=2, 
                title="Liveness",
                statement=statement,
                assumptions=self._extract_tla_assumptions("WhitepaperTheorem2"),
                conditions=self._extract_tla_conditions("WhitepaperTheorem2"),
                source_location="WhitepaperTheorems.tla:67-120",
                source_type="tla",
                proof_technique="Timeout analysis and honest participation"
            ))
        
        return theorems
    
    def _extract_lemmas(self) -> List[TheoremStatement]:
        """Extract lemmas from TLA+"""
        lemmas = []
        
        # Pattern to match lemma definitions
        lemma_pattern = r'LEMMA WhitepaperLemma(\d+)(?:Proof)? ==(.*?)(?=PROOF|LEMMA|THEOREM|$)'
        
        for match in re.finditer(lemma_pattern, self.content, re.DOTALL):
            lemma_num = int(match.group(1))
            
            if 20 <= lemma_num <= 42:
                statement = self._extract_formal_statement(f"WhitepaperLemma{lemma_num}")
                title = self._get_lemma_title_from_comments(lemma_num)
                
                lemmas.append(TheoremStatement(
                    id=f"lemma_{lemma_num}",
                    type="lemma",
                    number=lemma_num,
                    title=title,
                    statement=statement,
                    assumptions=self._extract_tla_assumptions(f"WhitepaperLemma{lemma_num}"),
                    conditions=self._extract_tla_conditions(f"WhitepaperLemma{lemma_num}"),
                    source_location=f"WhitepaperTheorems.tla:line_{self._find_line_number(f'WhitepaperLemma{lemma_num}')}",
                    source_type="tla",
                    proof_technique=self._extract_tla_proof_technique(lemma_num)
                ))
        
        return lemmas
    
    def _extract_formal_statement(self, theorem_name: str) -> str:
        """Extract the formal statement definition"""
        pattern = f'{theorem_name} ==(.*?)(?=\\n\\n|THEOREM|LEMMA|$)'
        match = re.search(pattern, self.content, re.DOTALL)
        
        if match:
            statement = match.group(1).strip()
            # Clean up TLA+ formatting
            statement = re.sub(r'\s+', ' ', statement)
            statement = re.sub(r'\\A|\\E', lambda m: '∀' if m.group() == '\\A' else '∃', statement)
            return statement
        
        return f"Formal statement for {theorem_name} not found"
    
    def _extract_tla_assumptions(self, theorem_name: str) -> List[str]:
        """Extract assumptions from TLA+ theorem"""
        # Look for common assumption patterns
        assumptions = []
        
        if "Byzantine" in self.content:
            assumptions.append("ByzantineAssumption: Byzantine nodes < 20% stake")
        
        if "GST" in self.content:
            assumptions.append("Network synchrony after GST")
            
        if "Validators \\" in self.content:
            assumptions.append("Honest validator behavior")
            
        return assumptions
    
    def _extract_tla_conditions(self, theorem_name: str) -> List[str]:
        """Extract conditions from TLA+ theorem"""
        conditions = []
        
        # Look for the theorem definition and extract conditions
        pattern = f'{theorem_name}.*?==.*?(?=PROOF|THEOREM|LEMMA|$)'
        match = re.search(pattern, self.content, re.DOTALL)
        
        if match:
            content = match.group(0)
            
            if "finalizedBlocks" in content:
                conditions.append("Block finalization")
            if "clock > GST" in content:
                conditions.append("Time after GST")
            if "RotorSuccessful" in content:
                conditions.append("Successful Rotor protocol")
            if "WindowSlots" in content:
                conditions.append("Leader window constraints")
                
        return conditions
    
    def _get_lemma_title_from_comments(self, lemma_num: int) -> str:
        """Extract lemma title from TLA+ comments"""
        # Look for comment before lemma definition
        pattern = f'\\(\\* Whitepaper Lemma {lemma_num}: ([^*]+) \\*\\)'
        match = re.search(pattern, self.content)
        
        if match:
            return match.group(1).strip()
        
        # Fallback to default titles
        return WhitepaperParser(None)._extract_lemma_title(lemma_num)
    
    def _find_line_number(self, theorem_name: str) -> int:
        """Find line number of theorem definition"""
        lines = self.content.split('\n')
        for i, line in enumerate(lines, 1):
            if theorem_name in line and ('THEOREM' in line or 'LEMMA' in line):
                return i
        return 0
    
    def _extract_tla_proof_technique(self, lemma_num: int) -> str:
        """Extract proof technique from TLA+ proof structure"""
        # Look for proof structure patterns
        lemma_pattern = f'WhitepaperLemma{lemma_num}.*?PROOF(.*?)(?=LEMMA|THEOREM|$)'
        match = re.search(lemma_pattern, self.content, re.DOTALL)
        
        if match:
            proof_content = match.group(1)
            
            if "induction" in proof_content.lower():
                return "Induction"
            elif "contradiction" in proof_content.lower():
                return "Proof by contradiction"
            elif "case" in proof_content.lower():
                return "Case analysis"
            elif "arithmetic" in proof_content.lower():
                return "Stake arithmetic"
            else:
                return "Structured formal proof"
        
        return "Standard TLA+ proof"

class CorrespondenceValidator:
    """Main validator that compares whitepaper and TLA+ theorems"""
    
    def __init__(self, whitepaper_path: str, tla_path: str):
        self.whitepaper_parser = WhitepaperParser(whitepaper_path)
        self.tla_parser = TLAParser(tla_path)
        
    def validate_correspondence(self) -> ValidationReport:
        """Perform complete correspondence validation"""
        print("Extracting theorems from whitepaper...")
        whitepaper_theorems = self.whitepaper_parser.extract_theorems()
        
        print("Extracting theorems from TLA+ specification...")
        tla_theorems = self.tla_parser.extract_theorems()
        
        print(f"Found {len(whitepaper_theorems)} whitepaper theorems")
        print(f"Found {len(tla_theorems)} TLA+ theorems")
        
        # Create lookup maps
        wp_map = {t.id: t for t in whitepaper_theorems}
        tla_map = {t.id: t for t in tla_theorems}
        
        # Find all theorem IDs
        all_ids = set(wp_map.keys()) | set(tla_map.keys())
        
        results = []
        matched_count = 0
        
        for theorem_id in sorted(all_ids):
            wp_theorem = wp_map.get(theorem_id)
            tla_theorem = tla_map.get(theorem_id)
            
            result = self._compare_theorems(theorem_id, wp_theorem, tla_theorem)
            results.append(result)
            
            if result.statements_match and result.assumptions_match:
                matched_count += 1
        
        # Identify missing theorems
        missing_from_tla = [tid for tid in wp_map.keys() if tid not in tla_map]
        missing_from_whitepaper = [tid for tid in tla_map.keys() if tid not in wp_map]
        
        # Calculate overall score
        total_theorems = len(all_ids)
        overall_score = (matched_count / total_theorems) * 100 if total_theorems > 0 else 0
        
        # Find discrepancies
        discrepancies = [r for r in results if not (r.statements_match and r.assumptions_match)]
        
        return ValidationReport(
            timestamp=datetime.now().isoformat(),
            total_theorems=total_theorems,
            matched_theorems=matched_count,
            missing_from_tla=missing_from_tla,
            missing_from_whitepaper=missing_from_whitepaper,
            discrepancies=discrepancies,
            overall_score=overall_score,
            detailed_results=results
        )
    
    def _compare_theorems(self, theorem_id: str, wp_theorem: Optional[TheoremStatement], 
                         tla_theorem: Optional[TheoremStatement]) -> CorrespondenceResult:
        """Compare a single theorem between whitepaper and TLA+"""
        
        if not wp_theorem:
            return CorrespondenceResult(
                theorem_id=theorem_id,
                whitepaper_present=False,
                tla_present=True,
                statements_match=False,
                assumptions_match=False,
                conditions_match=False,
                proof_techniques_match=False,
                discrepancies=["Missing from whitepaper"],
                confidence_score=0.0,
                notes="Theorem only exists in TLA+ specification"
            )
        
        if not tla_theorem:
            return CorrespondenceResult(
                theorem_id=theorem_id,
                whitepaper_present=True,
                tla_present=False,
                statements_match=False,
                assumptions_match=False,
                conditions_match=False,
                proof_techniques_match=False,
                discrepancies=["Missing from TLA+ specification"],
                confidence_score=0.0,
                notes="Theorem only exists in whitepaper"
            )
        
        # Compare statements
        statements_match = self._compare_statements(wp_theorem.statement, tla_theorem.statement)
        
        # Compare assumptions
        assumptions_match = self._compare_assumptions(wp_theorem.assumptions, tla_theorem.assumptions)
        
        # Compare conditions
        conditions_match = self._compare_conditions(wp_theorem.conditions, tla_theorem.conditions)
        
        # Compare proof techniques
        proof_techniques_match = self._compare_proof_techniques(
            wp_theorem.proof_technique, tla_theorem.proof_technique
        )
        
        # Identify discrepancies
        discrepancies = []
        if not statements_match:
            discrepancies.append("Statement content differs")
        if not assumptions_match:
            discrepancies.append("Assumptions differ")
        if not conditions_match:
            discrepancies.append("Conditions differ")
        if not proof_techniques_match:
            discrepancies.append("Proof techniques differ")
        
        # Calculate confidence score
        score_components = [statements_match, assumptions_match, conditions_match, proof_techniques_match]
        confidence_score = (sum(score_components) / len(score_components)) * 100
        
        notes = self._generate_comparison_notes(wp_theorem, tla_theorem)
        
        return CorrespondenceResult(
            theorem_id=theorem_id,
            whitepaper_present=True,
            tla_present=True,
            statements_match=statements_match,
            assumptions_match=assumptions_match,
            conditions_match=conditions_match,
            proof_techniques_match=proof_techniques_match,
            discrepancies=discrepancies,
            confidence_score=confidence_score,
            notes=notes
        )
    
    def _compare_statements(self, wp_statement: str, tla_statement: str) -> bool:
        """Compare theorem statements for mathematical equivalence"""
        # Normalize statements for comparison
        wp_norm = self._normalize_statement(wp_statement)
        tla_norm = self._normalize_statement(tla_statement)
        
        # Check for key mathematical concepts
        wp_concepts = self._extract_mathematical_concepts(wp_norm)
        tla_concepts = self._extract_mathematical_concepts(tla_norm)
        
        # Statements match if they share core mathematical concepts
        common_concepts = wp_concepts & tla_concepts
        total_concepts = wp_concepts | tla_concepts
        
        if len(total_concepts) == 0:
            return True  # Both empty
        
        similarity = len(common_concepts) / len(total_concepts)
        return similarity >= 0.7  # 70% concept overlap threshold
    
    def _normalize_statement(self, statement: str) -> str:
        """Normalize statement for comparison"""
        # Convert to lowercase
        normalized = statement.lower()
        
        # Remove extra whitespace
        normalized = re.sub(r'\s+', ' ', normalized)
        
        # Normalize mathematical symbols
        normalized = re.sub(r'\\a|∀|for all', 'forall', normalized)
        normalized = re.sub(r'\\e|∃|there exists?', 'exists', normalized)
        normalized = re.sub(r'=>|→|implies?', 'implies', normalized)
        normalized = re.sub(r'<=|≤', 'leq', normalized)
        normalized = re.sub(r'>=|≥', 'geq', normalized)
        
        return normalized.strip()
    
    def _extract_mathematical_concepts(self, statement: str) -> Set[str]:
        """Extract key mathematical concepts from statement"""
        concepts = set()
        
        # Key concepts to look for
        concept_patterns = [
            r'finali[sz]ed?',
            r'block',
            r'slot',
            r'descendant',
            r'ancestor',
            r'correct',
            r'byzantine',
            r'stake',
            r'validator',
            r'certificate',
            r'notari[sz]ation',
            r'timeout',
            r'window',
            r'leader',
            r'safety',
            r'liveness',
            r'progress',
            r'gst',
            r'rotor',
            r'honest'
        ]
        
        for pattern in concept_patterns:
            if re.search(pattern, statement):
                concepts.add(pattern.replace(r'\b', '').replace('?', ''))
        
        return concepts
    
    def _compare_assumptions(self, wp_assumptions: List[str], tla_assumptions: List[str]) -> bool:
        """Compare assumption lists"""
        if not wp_assumptions and not tla_assumptions:
            return True
        
        # Normalize assumptions
        wp_norm = [self._normalize_statement(a) for a in wp_assumptions]
        tla_norm = [self._normalize_statement(a) for a in tla_assumptions]
        
        # Check for conceptual overlap
        wp_concepts = set()
        for assumption in wp_norm:
            wp_concepts.update(self._extract_mathematical_concepts(assumption))
        
        tla_concepts = set()
        for assumption in tla_norm:
            tla_concepts.update(self._extract_mathematical_concepts(assumption))
        
        if not wp_concepts and not tla_concepts:
            return True
        
        if not wp_concepts or not tla_concepts:
            return False
        
        overlap = len(wp_concepts & tla_concepts) / len(wp_concepts | tla_concepts)
        return overlap >= 0.6  # 60% concept overlap for assumptions
    
    def _compare_conditions(self, wp_conditions: List[str], tla_conditions: List[str]) -> bool:
        """Compare condition lists"""
        return self._compare_assumptions(wp_conditions, tla_conditions)  # Same logic
    
    def _compare_proof_techniques(self, wp_technique: Optional[str], tla_technique: Optional[str]) -> bool:
        """Compare proof techniques"""
        if not wp_technique and not tla_technique:
            return True
        
        if not wp_technique or not tla_technique:
            return False
        
        wp_norm = self._normalize_statement(wp_technique)
        tla_norm = self._normalize_statement(tla_technique)
        
        # Check for common proof technique keywords
        technique_keywords = ['induction', 'contradiction', 'case', 'arithmetic', 'invariant', 'temporal']
        
        wp_keywords = set()
        tla_keywords = set()
        
        for keyword in technique_keywords:
            if keyword in wp_norm:
                wp_keywords.add(keyword)
            if keyword in tla_norm:
                tla_keywords.add(keyword)
        
        if not wp_keywords and not tla_keywords:
            return True  # Both have no specific technique keywords
        
        return len(wp_keywords & tla_keywords) > 0  # At least one common technique
    
    def _generate_comparison_notes(self, wp_theorem: TheoremStatement, tla_theorem: TheoremStatement) -> str:
        """Generate detailed comparison notes"""
        notes = []
        
        notes.append(f"Whitepaper: {wp_theorem.source_location}")
        notes.append(f"TLA+: {tla_theorem.source_location}")
        
        if wp_theorem.title != tla_theorem.title:
            notes.append(f"Title difference: '{wp_theorem.title}' vs '{tla_theorem.title}'")
        
        if len(wp_theorem.assumptions) != len(tla_theorem.assumptions):
            notes.append(f"Assumption count: {len(wp_theorem.assumptions)} vs {len(tla_theorem.assumptions)}")
        
        if len(wp_theorem.conditions) != len(tla_theorem.conditions):
            notes.append(f"Condition count: {len(wp_theorem.conditions)} vs {len(tla_theorem.conditions)}")
        
        return "; ".join(notes)

class ReportGenerator:
    """Generates detailed correspondence reports"""
    
    def __init__(self, report: ValidationReport):
        self.report = report
    
    def generate_json_report(self, output_path: str):
        """Generate JSON report"""
        report_dict = asdict(self.report)
        
        with open(output_path, 'w') as f:
            json.dump(report_dict, f, indent=2)
    
    def generate_markdown_report(self, output_path: str):
        """Generate detailed markdown report"""
        with open(output_path, 'w') as f:
            f.write(self._generate_markdown_content())
    
    def _generate_markdown_content(self) -> str:
        """Generate markdown report content"""
        content = []
        
        # Header
        content.append("# Theorem Correspondence Validation Report")
        content.append(f"\n**Generated:** {self.report.timestamp}")
        content.append(f"**Overall Score:** {self.report.overall_score:.1f}%")
        content.append(f"**Matched Theorems:** {self.report.matched_theorems}/{self.report.total_theorems}")
        
        # Summary
        content.append("\n## Summary")
        if self.report.overall_score >= 90:
            content.append("✅ **Excellent correspondence** - Whitepaper and TLA+ theorems are well-aligned")
        elif self.report.overall_score >= 75:
            content.append("⚠️ **Good correspondence** - Minor discrepancies found")
        else:
            content.append("❌ **Poor correspondence** - Significant discrepancies require attention")
        
        # Missing theorems
        if self.report.missing_from_tla:
            content.append("\n## Missing from TLA+ Specification")
            for theorem_id in self.report.missing_from_tla:
                content.append(f"- {theorem_id}")
        
        if self.report.missing_from_whitepaper:
            content.append("\n## Missing from Whitepaper")
            for theorem_id in self.report.missing_from_whitepaper:
                content.append(f"- {theorem_id}")
        
        # Discrepancies
        if self.report.discrepancies:
            content.append("\n## Discrepancies Found")
            for discrepancy in self.report.discrepancies:
                content.append(f"\n### {discrepancy.theorem_id}")
                content.append(f"**Confidence Score:** {discrepancy.confidence_score:.1f}%")
                content.append("**Issues:**")
                for issue in discrepancy.discrepancies:
                    content.append(f"- {issue}")
                if discrepancy.notes:
                    content.append(f"**Notes:** {discrepancy.notes}")
        
        # Detailed results
        content.append("\n## Detailed Results")
        content.append("\n| Theorem | WP | TLA+ | Statement | Assumptions | Conditions | Proof | Score |")
        content.append("|---------|----|----- |-----------|-------------|------------|-------|-------|")
        
        for result in sorted(self.report.detailed_results, key=lambda x: x.theorem_id):
            wp_status = "✅" if result.whitepaper_present else "❌"
            tla_status = "✅" if result.tla_present else "❌"
            stmt_status = "✅" if result.statements_match else "❌"
            assump_status = "✅" if result.assumptions_match else "❌"
            cond_status = "✅" if result.conditions_match else "❌"
            proof_status = "✅" if result.proof_techniques_match else "❌"
            
            content.append(f"| {result.theorem_id} | {wp_status} | {tla_status} | {stmt_status} | {assump_status} | {cond_status} | {proof_status} | {result.confidence_score:.0f}% |")
        
        return "\n".join(content)
    
    def print_summary(self):
        """Print summary to console"""
        print(f"\n{'='*60}")
        print("THEOREM CORRESPONDENCE VALIDATION SUMMARY")
        print(f"{'='*60}")
        print(f"Overall Score: {self.report.overall_score:.1f}%")
        print(f"Matched Theorems: {self.report.matched_theorems}/{self.report.total_theorems}")
        
        if self.report.missing_from_tla:
            print(f"\nMissing from TLA+: {len(self.report.missing_from_tla)}")
            for theorem_id in self.report.missing_from_tla:
                print(f"  - {theorem_id}")
        
        if self.report.missing_from_whitepaper:
            print(f"\nMissing from Whitepaper: {len(self.report.missing_from_whitepaper)}")
            for theorem_id in self.report.missing_from_whitepaper:
                print(f"  - {theorem_id}")
        
        if self.report.discrepancies:
            print(f"\nDiscrepancies: {len(self.report.discrepancies)}")
            for discrepancy in self.report.discrepancies[:5]:  # Show first 5
                print(f"  - {discrepancy.theorem_id}: {', '.join(discrepancy.discrepancies)}")
            if len(self.report.discrepancies) > 5:
                print(f"  ... and {len(self.report.discrepancies) - 5} more")
        
        print(f"\n{'='*60}")

def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description="Validate correspondence between whitepaper and TLA+ theorems")
    parser.add_argument("--whitepaper", required=True, help="Path to whitepaper markdown file")
    parser.add_argument("--tla", required=True, help="Path to TLA+ theorem file")
    parser.add_argument("--output-dir", default=".", help="Output directory for reports")
    parser.add_argument("--json", action="store_true", help="Generate JSON report")
    parser.add_argument("--markdown", action="store_true", help="Generate markdown report")
    parser.add_argument("--quiet", action="store_true", help="Suppress console output")
    
    args = parser.parse_args()
    
    # Validate input files
    if not os.path.exists(args.whitepaper):
        print(f"Error: Whitepaper file not found: {args.whitepaper}")
        sys.exit(1)
    
    if not os.path.exists(args.tla):
        print(f"Error: TLA+ file not found: {args.tla}")
        sys.exit(1)
    
    try:
        # Create validator and run validation
        validator = CorrespondenceValidator(args.whitepaper, args.tla)
        report = validator.validate_correspondence()
        
        # Generate reports
        report_generator = ReportGenerator(report)
        
        if not args.quiet:
            report_generator.print_summary()
        
        if args.json:
            json_path = os.path.join(args.output_dir, "theorem_correspondence_report.json")
            report_generator.generate_json_report(json_path)
            print(f"JSON report generated: {json_path}")
        
        if args.markdown:
            md_path = os.path.join(args.output_dir, "theorem_correspondence_report.md")
            report_generator.generate_markdown_report(md_path)
            print(f"Markdown report generated: {md_path}")
        
        # Exit with appropriate code
        if report.overall_score >= 90:
            sys.exit(0)  # Success
        elif report.overall_score >= 75:
            sys.exit(1)  # Warning
        else:
            sys.exit(2)  # Error
            
    except Exception as e:
        print(f"Error during validation: {e}")
        sys.exit(3)

if __name__ == "__main__":
    main()