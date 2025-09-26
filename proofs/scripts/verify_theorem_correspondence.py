#!/usr/bin/env python3
"""
Theorem Correspondence Verification Script

This script validates the correspondence between whitepaper theorems and TLA+ formalizations
for the Alpenglow consensus protocol. It ensures that formal verification actually addresses
the whitepaper claims by creating mappings, checking completeness, and generating reports.

Author: Traycer.AI
Date: 2024
"""

import os
import re
import json
import argparse
import logging
from pathlib import Path
from typing import Dict, List, Set, Tuple, Optional, Any
from dataclasses import dataclass, asdict
from collections import defaultdict
import hashlib
import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('theorem_correspondence.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

@dataclass
class WhitepaperTheorem:
    """Represents a theorem extracted from the whitepaper"""
    id: str
    type: str  # 'theorem', 'lemma', 'assumption', 'definition'
    title: str
    statement: str
    proof_sketch: str
    section: str
    page_number: Optional[int] = None
    dependencies: List[str] = None
    
    def __post_init__(self):
        if self.dependencies is None:
            self.dependencies = []

@dataclass
class TLATheorem:
    """Represents a theorem from TLA+ specifications"""
    id: str
    name: str
    statement: str
    proof_status: str  # 'complete', 'incomplete', 'missing', 'failed'
    module: str
    line_number: int
    dependencies: List[str] = None
    proof_obligations: List[str] = None
    
    def __post_init__(self):
        if self.dependencies is None:
            self.dependencies = []
        if self.proof_obligations is None:
            self.proof_obligations = []

@dataclass
class TheoremMapping:
    """Represents correspondence between whitepaper and TLA+ theorems"""
    whitepaper_id: str
    tla_id: str
    confidence: float  # 0.0 to 1.0
    mapping_type: str  # 'direct', 'partial', 'composite', 'derived'
    notes: str = ""
    validated: bool = False
    last_updated: str = ""

@dataclass
class ValidationResult:
    """Results of correspondence validation"""
    total_whitepaper_theorems: int
    total_tla_theorems: int
    mapped_theorems: int
    unmapped_whitepaper: List[str]
    unmapped_tla: List[str]
    inconsistent_mappings: List[str]
    completeness_score: float
    consistency_score: float
    quality_metrics: Dict[str, Any]

class WhitepaperParser:
    """Parses theorems and lemmas from the Alpenglow whitepaper"""
    
    def __init__(self, whitepaper_path: str):
        self.whitepaper_path = whitepaper_path
        self.theorems = {}
        self.section_map = {}
        
    def parse(self) -> Dict[str, WhitepaperTheorem]:
        """Extract all theorems, lemmas, and definitions from whitepaper"""
        logger.info(f"Parsing whitepaper: {self.whitepaper_path}")
        
        try:
            with open(self.whitepaper_path, 'r', encoding='utf-8') as f:
                content = f.read()
        except FileNotFoundError:
            logger.error(f"Whitepaper file not found: {self.whitepaper_path}")
            return {}
        
        # Extract sections for context
        self._extract_sections(content)
        
        # Extract theorems and lemmas
        self._extract_theorems(content)
        self._extract_lemmas(content)
        self._extract_assumptions(content)
        self._extract_definitions(content)
        
        logger.info(f"Extracted {len(self.theorems)} theorems/lemmas from whitepaper")
        return self.theorems
    
    def _extract_sections(self, content: str):
        """Extract section structure for context"""
        section_pattern = r'^(#{1,3})\s+(\d+(?:\.\d+)*)\s+(.+)$'
        current_section = ""
        
        for line_num, line in enumerate(content.split('\n'), 1):
            match = re.match(section_pattern, line.strip())
            if match:
                level = len(match.group(1))
                number = match.group(2)
                title = match.group(3)
                current_section = f"{number} {title}"
                self.section_map[line_num] = current_section
    
    def _extract_theorems(self, content: str):
        """Extract formal theorems"""
        # Pattern for "Theorem X (name): statement"
        theorem_pattern = r'Theorem\s+(\d+)\s*(?:\(([^)]+)\))?\s*[.:]?\s*(.+?)(?=\n\n|\nProof|\nLemma|\nTheorem|\nAssumption|\n#|\Z)'
        
        for match in re.finditer(theorem_pattern, content, re.DOTALL | re.IGNORECASE):
            theorem_num = match.group(1)
            theorem_name = match.group(2) or f"Theorem {theorem_num}"
            statement = match.group(3).strip()
            
            # Extract proof sketch if present
            proof_sketch = self._extract_proof_sketch(content, match.end())
            
            # Find section context
            section = self._find_section_context(content, match.start())
            
            theorem_id = f"theorem_{theorem_num}"
            self.theorems[theorem_id] = WhitepaperTheorem(
                id=theorem_id,
                type="theorem",
                title=theorem_name,
                statement=statement,
                proof_sketch=proof_sketch,
                section=section
            )
    
    def _extract_lemmas(self, content: str):
        """Extract lemmas"""
        # Pattern for "Lemma X (name): statement"
        lemma_pattern = r'Lemma\s+(\d+)\s*(?:\(([^)]+)\))?\s*[.:]?\s*(.+?)(?=\n\n|\nProof|\nLemma|\nTheorem|\nAssumption|\n#|\Z)'
        
        for match in re.finditer(lemma_pattern, content, re.DOTALL | re.IGNORECASE):
            lemma_num = match.group(1)
            lemma_name = match.group(2) or f"Lemma {lemma_num}"
            statement = match.group(3).strip()
            
            proof_sketch = self._extract_proof_sketch(content, match.end())
            section = self._find_section_context(content, match.start())
            
            lemma_id = f"lemma_{lemma_num}"
            self.theorems[lemma_id] = WhitepaperTheorem(
                id=lemma_id,
                type="lemma",
                title=lemma_name,
                statement=statement,
                proof_sketch=proof_sketch,
                section=section
            )
    
    def _extract_assumptions(self, content: str):
        """Extract assumptions"""
        assumption_pattern = r'Assumption\s+(\d+)\s*(?:\(([^)]+)\))?\s*[.:]?\s*(.+?)(?=\n\n|\nProof|\nLemma|\nTheorem|\nAssumption|\n#|\Z)'
        
        for match in re.finditer(assumption_pattern, content, re.DOTALL | re.IGNORECASE):
            assumption_num = match.group(1)
            assumption_name = match.group(2) or f"Assumption {assumption_num}"
            statement = match.group(3).strip()
            
            section = self._find_section_context(content, match.start())
            
            assumption_id = f"assumption_{assumption_num}"
            self.theorems[assumption_id] = WhitepaperTheorem(
                id=assumption_id,
                type="assumption",
                title=assumption_name,
                statement=statement,
                proof_sketch="",
                section=section
            )
    
    def _extract_definitions(self, content: str):
        """Extract key definitions"""
        definition_pattern = r'Definition\s+(\d+)\s*(?:\(([^)]+)\))?\s*[.:]?\s*(.+?)(?=\n\n|\nDefinition|\nLemma|\nTheorem|\n#|\Z)'
        
        for match in re.finditer(definition_pattern, content, re.DOTALL | re.IGNORECASE):
            def_num = match.group(1)
            def_name = match.group(2) or f"Definition {def_num}"
            statement = match.group(3).strip()
            
            section = self._find_section_context(content, match.start())
            
            def_id = f"definition_{def_num}"
            self.theorems[def_id] = WhitepaperTheorem(
                id=def_id,
                type="definition",
                title=def_name,
                statement=statement,
                proof_sketch="",
                section=section
            )
    
    def _extract_proof_sketch(self, content: str, start_pos: int) -> str:
        """Extract proof sketch following a theorem/lemma"""
        remaining_content = content[start_pos:]
        
        # Look for "Proof" or "Proof Sketch"
        proof_match = re.search(r'\n\s*Proof(?:\s+Sketch)?[.:]?\s*(.+?)(?=\n\n|\nLemma|\nTheorem|\nAssumption|\n#|\Z)', 
                               remaining_content, re.DOTALL | re.IGNORECASE)
        
        if proof_match:
            return proof_match.group(1).strip()
        return ""
    
    def _find_section_context(self, content: str, position: int) -> str:
        """Find the section containing the given position"""
        lines_before = content[:position].count('\n')
        
        # Find the most recent section
        for line_num in sorted(self.section_map.keys(), reverse=True):
            if line_num <= lines_before:
                return self.section_map[line_num]
        
        return "Unknown Section"

class TLAParser:
    """Parses theorems and proofs from TLA+ specification files"""
    
    def __init__(self, specs_dir: str):
        self.specs_dir = specs_dir
        self.theorems = {}
        
    def parse(self) -> Dict[str, TLATheorem]:
        """Parse all TLA+ files for theorems and lemmas"""
        logger.info(f"Parsing TLA+ specifications in: {self.specs_dir}")
        
        tla_files = list(Path(self.specs_dir).rglob("*.tla"))
        logger.info(f"Found {len(tla_files)} TLA+ files")
        
        for tla_file in tla_files:
            self._parse_tla_file(tla_file)
        
        logger.info(f"Extracted {len(self.theorems)} theorems from TLA+ files")
        return self.theorems
    
    def _parse_tla_file(self, file_path: Path):
        """Parse a single TLA+ file"""
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
        except Exception as e:
            logger.warning(f"Could not read {file_path}: {e}")
            return
        
        module_name = file_path.stem
        
        # Extract THEOREM statements
        self._extract_tla_theorems(content, module_name)
        
        # Extract LEMMA statements
        self._extract_tla_lemmas(content, module_name)
        
        # Extract proof obligations
        self._extract_proof_obligations(content, module_name)
    
    def _extract_tla_theorems(self, content: str, module: str):
        """Extract THEOREM statements from TLA+ content"""
        theorem_pattern = r'THEOREM\s+([A-Za-z_][A-Za-z0-9_]*)\s*==\s*(.+?)(?=\nPROOF|\nLEMMA|\nTHEOREM|\n====|\Z)'
        
        for line_num, line in enumerate(content.split('\n'), 1):
            if 'THEOREM' in line:
                # Find the complete theorem statement
                theorem_match = re.search(theorem_pattern, content[content.find(line):], re.DOTALL)
                if theorem_match:
                    theorem_name = theorem_match.group(1)
                    statement = theorem_match.group(2).strip()
                    
                    # Check proof status
                    proof_status = self._check_proof_status(content, theorem_name)
                    
                    # Extract dependencies
                    dependencies = self._extract_dependencies(statement)
                    
                    theorem_id = f"{module}_{theorem_name}"
                    self.theorems[theorem_id] = TLATheorem(
                        id=theorem_id,
                        name=theorem_name,
                        statement=statement,
                        proof_status=proof_status,
                        module=module,
                        line_number=line_num,
                        dependencies=dependencies
                    )
    
    def _extract_tla_lemmas(self, content: str, module: str):
        """Extract LEMMA statements from TLA+ content"""
        lemma_pattern = r'LEMMA\s+([A-Za-z_][A-Za-z0-9_]*)\s*==\s*(.+?)(?=\nPROOF|\nLEMMA|\nTHEOREM|\n====|\Z)'
        
        for line_num, line in enumerate(content.split('\n'), 1):
            if 'LEMMA' in line:
                lemma_match = re.search(lemma_pattern, content[content.find(line):], re.DOTALL)
                if lemma_match:
                    lemma_name = lemma_match.group(1)
                    statement = lemma_match.group(2).strip()
                    
                    proof_status = self._check_proof_status(content, lemma_name)
                    dependencies = self._extract_dependencies(statement)
                    
                    lemma_id = f"{module}_{lemma_name}"
                    self.theorems[lemma_id] = TLATheorem(
                        id=lemma_id,
                        name=lemma_name,
                        statement=statement,
                        proof_status=proof_status,
                        module=module,
                        line_number=line_num,
                        dependencies=dependencies
                    )
    
    def _extract_proof_obligations(self, content: str, module: str):
        """Extract proof obligations from TLA+ proofs"""
        # Look for proof steps and obligations
        proof_step_pattern = r'<(\d+)>(\d+)\.\s*(.+?)(?=\n\s*<|\nPROOF|\nQED|\Z)'
        
        for match in re.finditer(proof_step_pattern, content, re.DOTALL):
            level = match.group(1)
            step = match.group(2)
            obligation = match.group(3).strip()
            
            # Find the theorem this obligation belongs to
            theorem_context = self._find_theorem_context(content, match.start())
            if theorem_context and theorem_context in self.theorems:
                self.theorems[theorem_context].proof_obligations.append(f"<{level}>{step}: {obligation}")
    
    def _check_proof_status(self, content: str, theorem_name: str) -> str:
        """Determine the proof status of a theorem"""
        # Look for PROOF...QED block
        proof_pattern = rf'{theorem_name}\s*==.*?PROOF.*?QED'
        if re.search(proof_pattern, content, re.DOTALL):
            # Check for OMITTED or OBVIOUS
            if 'OMITTED' in content or 'OBVIOUS' in content:
                return 'incomplete'
            return 'complete'
        
        # Check for proof sketch or placeholder
        if f'{theorem_name}' in content and 'PROOF' in content:
            return 'incomplete'
        
        return 'missing'
    
    def _extract_dependencies(self, statement: str) -> List[str]:
        """Extract theorem dependencies from statement"""
        dependencies = []
        
        # Look for references to other theorems/lemmas
        ref_patterns = [
            r'BY\s+([A-Za-z_][A-Za-z0-9_]*)',
            r'USE\s+([A-Za-z_][A-Za-z0-9_]*)',
            r'([A-Za-z_][A-Za-z0-9_]*!)([A-Za-z_][A-Za-z0-9_]*)'
        ]
        
        for pattern in ref_patterns:
            matches = re.findall(pattern, statement)
            dependencies.extend([match if isinstance(match, str) else match[1] for match in matches])
        
        return list(set(dependencies))
    
    def _find_theorem_context(self, content: str, position: int) -> Optional[str]:
        """Find which theorem a proof obligation belongs to"""
        content_before = content[:position]
        
        # Look for the most recent THEOREM or LEMMA
        theorem_matches = list(re.finditer(r'(THEOREM|LEMMA)\s+([A-Za-z_][A-Za-z0-9_]*)', content_before))
        if theorem_matches:
            last_match = theorem_matches[-1]
            return last_match.group(2)
        
        return None

class CorrespondenceMapper:
    """Creates and manages mappings between whitepaper and TLA+ theorems"""
    
    def __init__(self):
        self.mappings = {}
        self.mapping_rules = self._initialize_mapping_rules()
    
    def _initialize_mapping_rules(self) -> Dict[str, Dict[str, float]]:
        """Initialize mapping rules with confidence scores"""
        return {
            # Direct name mappings
            'direct_name': {
                'theorem_1': ['WhitepaperTheorem1', 'SafetyTheorem', 'WhitepaperSafetyTheorem'],
                'theorem_2': ['WhitepaperTheorem2', 'LivenessTheorem', 'WhitepaperLivenessTheorem'],
                'lemma_20': ['WhitepaperLemma20', 'VoteUniqueness'],
                'lemma_21': ['WhitepaperLemma21', 'FastPathSafety'],
                'lemma_22': ['WhitepaperLemma22', 'VoteExclusivity'],
                'lemma_23': ['WhitepaperLemma23', 'BlockUniqueness'],
                'lemma_24': ['WhitepaperLemma24', 'CertificateUniqueness'],
                'lemma_25': ['WhitepaperLemma25', 'ChainConsistency'],
                'assumption_1': ['ByzantineAssumption', 'FaultTolerance'],
                'assumption_2': ['CrashTolerance', 'ExtraCrashTolerance'],
                'assumption_3': ['RotorNonEquivocation', 'NetworkAssumption']
            },
            
            # Keyword-based mappings
            'keyword_mapping': {
                'safety': ['Safety', 'Consistent', 'Agreement'],
                'liveness': ['Liveness', 'Progress', 'Termination'],
                'byzantine': ['Byzantine', 'Fault', 'Adversary'],
                'finalization': ['Finalized', 'Final', 'Commit'],
                'notarization': ['Notarized', 'Notar', 'Certificate'],
                'timeout': ['Timeout', 'Timer', 'Delay'],
                'rotor': ['Rotor', 'Dissemination', 'Broadcast'],
                'votor': ['Votor', 'Voting', 'Vote']
            }
        }
    
    def create_mappings(self, whitepaper_theorems: Dict[str, WhitepaperTheorem], 
                       tla_theorems: Dict[str, TLATheorem]) -> Dict[str, TheoremMapping]:
        """Create correspondence mappings between whitepaper and TLA+ theorems"""
        logger.info("Creating theorem correspondence mappings")
        
        mappings = {}
        
        # Direct name-based mappings
        for wp_id, wp_theorem in whitepaper_theorems.items():
            direct_matches = self._find_direct_matches(wp_id, wp_theorem, tla_theorems)
            for tla_id, confidence in direct_matches:
                mapping_id = f"{wp_id}_to_{tla_id}"
                mappings[mapping_id] = TheoremMapping(
                    whitepaper_id=wp_id,
                    tla_id=tla_id,
                    confidence=confidence,
                    mapping_type='direct',
                    last_updated=datetime.datetime.now().isoformat()
                )
        
        # Semantic similarity mappings
        for wp_id, wp_theorem in whitepaper_theorems.items():
            if not any(m.whitepaper_id == wp_id for m in mappings.values()):
                semantic_matches = self._find_semantic_matches(wp_theorem, tla_theorems)
                for tla_id, confidence in semantic_matches:
                    if confidence > 0.6:  # Threshold for semantic matches
                        mapping_id = f"{wp_id}_to_{tla_id}"
                        mappings[mapping_id] = TheoremMapping(
                            whitepaper_id=wp_id,
                            tla_id=tla_id,
                            confidence=confidence,
                            mapping_type='semantic',
                            last_updated=datetime.datetime.now().isoformat()
                        )
        
        self.mappings = mappings
        logger.info(f"Created {len(mappings)} theorem mappings")
        return mappings
    
    def _find_direct_matches(self, wp_id: str, wp_theorem: WhitepaperTheorem, 
                           tla_theorems: Dict[str, TLATheorem]) -> List[Tuple[str, float]]:
        """Find direct name-based matches"""
        matches = []
        
        # Check direct name mappings
        if wp_id in self.mapping_rules['direct_name']:
            for tla_name in self.mapping_rules['direct_name'][wp_id]:
                for tla_id, tla_theorem in tla_theorems.items():
                    if tla_name.lower() in tla_theorem.name.lower():
                        matches.append((tla_id, 0.95))
        
        return matches
    
    def _find_semantic_matches(self, wp_theorem: WhitepaperTheorem, 
                             tla_theorems: Dict[str, TLATheorem]) -> List[Tuple[str, float]]:
        """Find semantic similarity matches"""
        matches = []
        
        wp_keywords = self._extract_keywords(wp_theorem.statement + " " + wp_theorem.title)
        
        for tla_id, tla_theorem in tla_theorems.items():
            tla_keywords = self._extract_keywords(tla_theorem.statement + " " + tla_theorem.name)
            
            # Calculate keyword overlap
            common_keywords = wp_keywords.intersection(tla_keywords)
            if common_keywords:
                confidence = len(common_keywords) / max(len(wp_keywords), len(tla_keywords))
                if confidence > 0.3:
                    matches.append((tla_id, confidence))
        
        return sorted(matches, key=lambda x: x[1], reverse=True)
    
    def _extract_keywords(self, text: str) -> Set[str]:
        """Extract relevant keywords from theorem text"""
        # Convert to lowercase and extract words
        words = re.findall(r'\b[a-zA-Z]+\b', text.lower())
        
        # Filter for relevant keywords
        relevant_keywords = set()
        for category, keywords in self.mapping_rules['keyword_mapping'].items():
            for keyword in keywords:
                if keyword.lower() in words:
                    relevant_keywords.add(keyword.lower())
        
        # Add domain-specific terms
        domain_terms = {'block', 'slot', 'validator', 'stake', 'certificate', 'chain', 
                       'consensus', 'protocol', 'honest', 'malicious', 'network'}
        relevant_keywords.update(word for word in words if word in domain_terms)
        
        return relevant_keywords

class CorrespondenceValidator:
    """Validates the correspondence between whitepaper and TLA+ theorems"""
    
    def __init__(self):
        self.validation_rules = self._initialize_validation_rules()
    
    def _initialize_validation_rules(self) -> Dict[str, Any]:
        """Initialize validation rules and criteria"""
        return {
            'completeness_threshold': 0.8,  # 80% of whitepaper theorems should be mapped
            'consistency_threshold': 0.7,   # 70% confidence for valid mappings
            'critical_theorems': ['theorem_1', 'theorem_2'],  # Must be mapped
            'proof_status_weights': {
                'complete': 1.0,
                'incomplete': 0.5,
                'missing': 0.0,
                'failed': 0.0
            }
        }
    
    def validate(self, whitepaper_theorems: Dict[str, WhitepaperTheorem],
                tla_theorems: Dict[str, TLATheorem],
                mappings: Dict[str, TheoremMapping]) -> ValidationResult:
        """Perform comprehensive validation of theorem correspondence"""
        logger.info("Validating theorem correspondence")
        
        # Calculate basic metrics
        total_wp = len(whitepaper_theorems)
        total_tla = len(tla_theorems)
        
        # Find mapped and unmapped theorems
        mapped_wp_ids = {m.whitepaper_id for m in mappings.values()}
        mapped_tla_ids = {m.tla_id for m in mappings.values()}
        
        unmapped_wp = [wp_id for wp_id in whitepaper_theorems.keys() if wp_id not in mapped_wp_ids]
        unmapped_tla = [tla_id for tla_id in tla_theorems.keys() if tla_id not in mapped_tla_ids]
        
        # Check for inconsistent mappings
        inconsistent = self._find_inconsistent_mappings(mappings, whitepaper_theorems, tla_theorems)
        
        # Calculate scores
        completeness_score = len(mapped_wp_ids) / total_wp if total_wp > 0 else 0
        consistency_score = self._calculate_consistency_score(mappings, inconsistent)
        
        # Generate quality metrics
        quality_metrics = self._calculate_quality_metrics(
            whitepaper_theorems, tla_theorems, mappings
        )
        
        result = ValidationResult(
            total_whitepaper_theorems=total_wp,
            total_tla_theorems=total_tla,
            mapped_theorems=len(mapped_wp_ids),
            unmapped_whitepaper=unmapped_wp,
            unmapped_tla=unmapped_tla,
            inconsistent_mappings=inconsistent,
            completeness_score=completeness_score,
            consistency_score=consistency_score,
            quality_metrics=quality_metrics
        )
        
        logger.info(f"Validation complete: {completeness_score:.2%} completeness, {consistency_score:.2%} consistency")
        return result
    
    def _find_inconsistent_mappings(self, mappings: Dict[str, TheoremMapping],
                                  whitepaper_theorems: Dict[str, WhitepaperTheorem],
                                  tla_theorems: Dict[str, TLATheorem]) -> List[str]:
        """Find mappings that appear inconsistent"""
        inconsistent = []
        
        for mapping_id, mapping in mappings.items():
            # Check if confidence is too low
            if mapping.confidence < self.validation_rules['consistency_threshold']:
                inconsistent.append(f"{mapping_id}: Low confidence ({mapping.confidence:.2f})")
            
            # Check for type mismatches
            wp_theorem = whitepaper_theorems.get(mapping.whitepaper_id)
            tla_theorem = tla_theorems.get(mapping.tla_id)
            
            if wp_theorem and tla_theorem:
                if wp_theorem.type == 'theorem' and 'lemma' in tla_theorem.name.lower():
                    inconsistent.append(f"{mapping_id}: Type mismatch (theorem -> lemma)")
                elif wp_theorem.type == 'lemma' and 'theorem' in tla_theorem.name.lower():
                    inconsistent.append(f"{mapping_id}: Type mismatch (lemma -> theorem)")
        
        return inconsistent
    
    def _calculate_consistency_score(self, mappings: Dict[str, TheoremMapping], 
                                   inconsistent: List[str]) -> float:
        """Calculate overall consistency score"""
        if not mappings:
            return 0.0
        
        # Weight by confidence scores
        total_confidence = sum(m.confidence for m in mappings.values())
        avg_confidence = total_confidence / len(mappings)
        
        # Penalize for inconsistencies
        inconsistency_penalty = len(inconsistent) / len(mappings)
        
        return max(0.0, avg_confidence - inconsistency_penalty)
    
    def _calculate_quality_metrics(self, whitepaper_theorems: Dict[str, WhitepaperTheorem],
                                 tla_theorems: Dict[str, TLATheorem],
                                 mappings: Dict[str, TheoremMapping]) -> Dict[str, Any]:
        """Calculate detailed quality metrics"""
        metrics = {}
        
        # Proof completion metrics
        proof_statuses = [tla_theorems[m.tla_id].proof_status for m in mappings.values() 
                         if m.tla_id in tla_theorems]
        
        metrics['proof_completion'] = {
            status: proof_statuses.count(status) for status in 
            ['complete', 'incomplete', 'missing', 'failed']
        }
        
        # Critical theorem coverage
        critical_mapped = sum(1 for theorem_id in self.validation_rules['critical_theorems']
                            if any(m.whitepaper_id == theorem_id for m in mappings.values()))
        metrics['critical_coverage'] = critical_mapped / len(self.validation_rules['critical_theorems'])
        
        # Mapping type distribution
        mapping_types = [m.mapping_type for m in mappings.values()]
        metrics['mapping_types'] = {
            mtype: mapping_types.count(mtype) for mtype in 
            ['direct', 'semantic', 'partial', 'composite']
        }
        
        # Average confidence by type
        metrics['confidence_by_type'] = {}
        for mtype in ['direct', 'semantic', 'partial', 'composite']:
            type_mappings = [m for m in mappings.values() if m.mapping_type == mtype]
            if type_mappings:
                metrics['confidence_by_type'][mtype] = sum(m.confidence for m in type_mappings) / len(type_mappings)
        
        return metrics

class ReportGenerator:
    """Generates comprehensive reports on theorem correspondence"""
    
    def __init__(self, output_dir: str):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(exist_ok=True)
    
    def generate_reports(self, whitepaper_theorems: Dict[str, WhitepaperTheorem],
                        tla_theorems: Dict[str, TLATheorem],
                        mappings: Dict[str, TheoremMapping],
                        validation_result: ValidationResult):
        """Generate all correspondence reports"""
        logger.info("Generating correspondence reports")
        
        # Generate main validation report
        self._generate_validation_report(validation_result)
        
        # Generate traceability matrix
        self._generate_traceability_matrix(whitepaper_theorems, tla_theorems, mappings)
        
        # Generate gap analysis report
        self._generate_gap_analysis(whitepaper_theorems, tla_theorems, validation_result)
        
        # Generate progress report
        self._generate_progress_report(tla_theorems, mappings, validation_result)
        
        # Generate JSON data for automated processing
        self._generate_json_data(whitepaper_theorems, tla_theorems, mappings, validation_result)
        
        logger.info(f"Reports generated in {self.output_dir}")
    
    def _generate_validation_report(self, validation_result: ValidationResult):
        """Generate main validation report"""
        report_path = self.output_dir / "theorem_correspondence_report.md"
        
        with open(report_path, 'w') as f:
            f.write("# Theorem Correspondence Validation Report\n\n")
            f.write(f"Generated: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
            
            f.write("## Summary\n\n")
            f.write(f"- **Total Whitepaper Theorems**: {validation_result.total_whitepaper_theorems}\n")
            f.write(f"- **Total TLA+ Theorems**: {validation_result.total_tla_theorems}\n")
            f.write(f"- **Mapped Theorems**: {validation_result.mapped_theorems}\n")
            f.write(f"- **Completeness Score**: {validation_result.completeness_score:.2%}\n")
            f.write(f"- **Consistency Score**: {validation_result.consistency_score:.2%}\n\n")
            
            f.write("## Quality Metrics\n\n")
            f.write("### Proof Completion Status\n")
            for status, count in validation_result.quality_metrics['proof_completion'].items():
                f.write(f"- **{status.title()}**: {count}\n")
            
            f.write(f"\n### Critical Theorem Coverage\n")
            f.write(f"- **Coverage**: {validation_result.quality_metrics['critical_coverage']:.2%}\n")
            
            f.write("\n### Mapping Type Distribution\n")
            for mtype, count in validation_result.quality_metrics['mapping_types'].items():
                f.write(f"- **{mtype.title()}**: {count}\n")
            
            f.write("\n## Issues\n\n")
            if validation_result.unmapped_whitepaper:
                f.write("### Unmapped Whitepaper Theorems\n")
                for theorem_id in validation_result.unmapped_whitepaper:
                    f.write(f"- {theorem_id}\n")
                f.write("\n")
            
            if validation_result.unmapped_tla:
                f.write("### Unmapped TLA+ Theorems\n")
                for theorem_id in validation_result.unmapped_tla:
                    f.write(f"- {theorem_id}\n")
                f.write("\n")
            
            if validation_result.inconsistent_mappings:
                f.write("### Inconsistent Mappings\n")
                for issue in validation_result.inconsistent_mappings:
                    f.write(f"- {issue}\n")
    
    def _generate_traceability_matrix(self, whitepaper_theorems: Dict[str, WhitepaperTheorem],
                                    tla_theorems: Dict[str, TLATheorem],
                                    mappings: Dict[str, TheoremMapping]):
        """Generate traceability matrix"""
        matrix_path = self.output_dir / "traceability_matrix.md"
        
        with open(matrix_path, 'w') as f:
            f.write("# Theorem Traceability Matrix\n\n")
            f.write("| Whitepaper Theorem | TLA+ Theorem | Confidence | Type | Status |\n")
            f.write("|-------------------|--------------|------------|------|--------|\n")
            
            for mapping in mappings.values():
                wp_theorem = whitepaper_theorems.get(mapping.whitepaper_id, None)
                tla_theorem = tla_theorems.get(mapping.tla_id, None)
                
                wp_title = wp_theorem.title if wp_theorem else mapping.whitepaper_id
                tla_name = tla_theorem.name if tla_theorem else mapping.tla_id
                proof_status = tla_theorem.proof_status if tla_theorem else "unknown"
                
                f.write(f"| {wp_title} | {tla_name} | {mapping.confidence:.2f} | {mapping.mapping_type} | {proof_status} |\n")
    
    def _generate_gap_analysis(self, whitepaper_theorems: Dict[str, WhitepaperTheorem],
                             tla_theorems: Dict[str, TLATheorem],
                             validation_result: ValidationResult):
        """Generate gap analysis report"""
        gap_path = self.output_dir / "gap_analysis.md"
        
        with open(gap_path, 'w') as f:
            f.write("# Gap Analysis Report\n\n")
            
            f.write("## Missing TLA+ Formalizations\n\n")
            f.write("The following whitepaper theorems lack corresponding TLA+ formalizations:\n\n")
            
            for theorem_id in validation_result.unmapped_whitepaper:
                theorem = whitepaper_theorems.get(theorem_id)
                if theorem:
                    f.write(f"### {theorem.title} ({theorem_id})\n")
                    f.write(f"**Type**: {theorem.type}\n")
                    f.write(f"**Section**: {theorem.section}\n")
                    f.write(f"**Statement**: {theorem.statement[:200]}...\n\n")
            
            f.write("## Orphaned TLA+ Theorems\n\n")
            f.write("The following TLA+ theorems don't correspond to whitepaper claims:\n\n")
            
            for theorem_id in validation_result.unmapped_tla:
                theorem = tla_theorems.get(theorem_id)
                if theorem:
                    f.write(f"### {theorem.name} ({theorem_id})\n")
                    f.write(f"**Module**: {theorem.module}\n")
                    f.write(f"**Status**: {theorem.proof_status}\n")
                    f.write(f"**Statement**: {theorem.statement[:200]}...\n\n")
    
    def _generate_progress_report(self, tla_theorems: Dict[str, TLATheorem],
                                mappings: Dict[str, TheoremMapping],
                                validation_result: ValidationResult):
        """Generate progress tracking report"""
        progress_path = self.output_dir / "progress_report.md"
        
        with open(progress_path, 'w') as f:
            f.write("# Formal Verification Progress Report\n\n")
            
            # Overall progress
            total_proofs = len([t for t in tla_theorems.values() if any(m.tla_id == t.id for m in mappings.values())])
            complete_proofs = len([t for t in tla_theorems.values() 
                                 if t.proof_status == 'complete' and any(m.tla_id == t.id for m in mappings.values())])
            
            progress_pct = (complete_proofs / total_proofs * 100) if total_proofs > 0 else 0
            
            f.write(f"## Overall Progress: {progress_pct:.1f}%\n\n")
            f.write(f"- **Complete Proofs**: {complete_proofs}/{total_proofs}\n")
            f.write(f"- **Completeness Score**: {validation_result.completeness_score:.2%}\n")
            f.write(f"- **Consistency Score**: {validation_result.consistency_score:.2%}\n\n")
            
            # Progress by module
            f.write("## Progress by Module\n\n")
            module_progress = defaultdict(lambda: {'total': 0, 'complete': 0})
            
            for theorem in tla_theorems.values():
                if any(m.tla_id == theorem.id for m in mappings.values()):
                    module_progress[theorem.module]['total'] += 1
                    if theorem.proof_status == 'complete':
                        module_progress[theorem.module]['complete'] += 1
            
            for module, stats in module_progress.items():
                pct = (stats['complete'] / stats['total'] * 100) if stats['total'] > 0 else 0
                f.write(f"- **{module}**: {stats['complete']}/{stats['total']} ({pct:.1f}%)\n")
            
            # Next steps
            f.write("\n## Recommended Next Steps\n\n")
            
            if validation_result.unmapped_whitepaper:
                f.write("1. **Formalize Missing Theorems**: Create TLA+ formalizations for unmapped whitepaper theorems\n")
            
            incomplete_theorems = [t for t in tla_theorems.values() 
                                 if t.proof_status in ['incomplete', 'missing'] and 
                                 any(m.tla_id == t.id for m in mappings.values())]
            
            if incomplete_theorems:
                f.write("2. **Complete Proofs**: Focus on completing proofs for mapped theorems\n")
                for theorem in incomplete_theorems[:5]:  # Show top 5
                    f.write(f"   - {theorem.name} ({theorem.module})\n")
            
            if validation_result.inconsistent_mappings:
                f.write("3. **Resolve Inconsistencies**: Address mapping inconsistencies\n")
    
    def _generate_json_data(self, whitepaper_theorems: Dict[str, WhitepaperTheorem],
                          tla_theorems: Dict[str, TLATheorem],
                          mappings: Dict[str, TheoremMapping],
                          validation_result: ValidationResult):
        """Generate JSON data for automated processing"""
        data = {
            'whitepaper_theorems': {k: asdict(v) for k, v in whitepaper_theorems.items()},
            'tla_theorems': {k: asdict(v) for k, v in tla_theorems.items()},
            'mappings': {k: asdict(v) for k, v in mappings.items()},
            'validation_result': asdict(validation_result),
            'generated_at': datetime.datetime.now().isoformat()
        }
        
        json_path = self.output_dir / "correspondence_data.json"
        with open(json_path, 'w') as f:
            json.dump(data, f, indent=2)

def main():
    """Main entry point for the theorem correspondence verification script"""
    parser = argparse.ArgumentParser(description="Verify theorem correspondence between whitepaper and TLA+ specifications")
    parser.add_argument("--whitepaper", required=True, help="Path to the whitepaper markdown file")
    parser.add_argument("--specs-dir", required=True, help="Directory containing TLA+ specification files")
    parser.add_argument("--output-dir", default="./correspondence_reports", help="Output directory for reports")
    parser.add_argument("--update-mappings", action="store_true", help="Update existing mappings")
    parser.add_argument("--verbose", "-v", action="store_true", help="Enable verbose logging")
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    try:
        # Parse whitepaper theorems
        logger.info("Starting theorem correspondence verification")
        whitepaper_parser = WhitepaperParser(args.whitepaper)
        whitepaper_theorems = whitepaper_parser.parse()
        
        # Parse TLA+ theorems
        tla_parser = TLAParser(args.specs_dir)
        tla_theorems = tla_parser.parse()
        
        # Create correspondence mappings
        mapper = CorrespondenceMapper()
        mappings = mapper.create_mappings(whitepaper_theorems, tla_theorems)
        
        # Validate correspondence
        validator = CorrespondenceValidator()
        validation_result = validator.validate(whitepaper_theorems, tla_theorems, mappings)
        
        # Generate reports
        report_generator = ReportGenerator(args.output_dir)
        report_generator.generate_reports(whitepaper_theorems, tla_theorems, mappings, validation_result)
        
        # Print summary
        print(f"\n=== Theorem Correspondence Verification Complete ===")
        print(f"Whitepaper Theorems: {validation_result.total_whitepaper_theorems}")
        print(f"TLA+ Theorems: {validation_result.total_tla_theorems}")
        print(f"Mapped Theorems: {validation_result.mapped_theorems}")
        print(f"Completeness: {validation_result.completeness_score:.2%}")
        print(f"Consistency: {validation_result.consistency_score:.2%}")
        print(f"Reports generated in: {args.output_dir}")
        
        # Exit with appropriate code
        if validation_result.completeness_score < 0.8 or validation_result.consistency_score < 0.7:
            print("\nWARNING: Low completeness or consistency scores detected!")
            return 1
        
        return 0
        
    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return 1

if __name__ == "__main__":
    exit(main())