#!/usr/bin/env python3
"""
Enhanced Theorem Mapping Generator for Alpenglow Consensus Protocol

This script automatically generates comprehensive theorem-to-proof mappings between
the Alpenglow whitepaper and formal TLA+ specifications. It extends the existing
correspondence verification framework with enhanced parsing, verification status
checking, and multi-format output generation.

Features:
- Enhanced whitepaper parsing with improved theorem extraction
- TLA+ specification scanning with TLAPS proof status detection
- TLC model checking result integration
- Stateright cross-validation result parsing
- Multi-format output (Markdown, JSON, HTML)
- Incremental update support
- Cross-reference generation
- Verification timestamp tracking

Author: Traycer.AI
Date: 2024
"""

import os
import re
import json
import argparse
import logging
import subprocess
import hashlib
import datetime
from pathlib import Path
from typing import Dict, List, Set, Tuple, Optional, Any, Union
from dataclasses import dataclass, asdict, field
from collections import defaultdict
import xml.etree.ElementTree as ET
from jinja2 import Template
import yaml

# Import existing correspondence verification components
try:
    from proofs.verify_theorem_correspondence import (
        WhitepaperTheorem, TLATheorem, TheoremMapping, ValidationResult,
        WhitepaperParser, TLAParser, CorrespondenceMapper, CorrespondenceValidator
    )
except ImportError:
    # Fallback if import fails - define minimal required classes
    from dataclasses import dataclass
    from typing import List, Optional
    
    @dataclass
    class WhitepaperTheorem:
        id: str
        type: str
        title: str
        statement: str
        proof_sketch: str
        section: str
        page_number: Optional[int] = None
        dependencies: List[str] = field(default_factory=list)
    
    @dataclass
    class TLATheorem:
        id: str
        name: str
        statement: str
        proof_status: str
        module: str
        line_number: int
        dependencies: List[str] = field(default_factory=list)
        proof_obligations: List[str] = field(default_factory=list)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('theorem_mapping.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

@dataclass
class VerificationStatus:
    """Enhanced verification status with multiple verification methods"""
    tlaps_status: str = "unknown"  # complete, incomplete, missing, failed
    tlc_status: str = "unknown"    # verified, failed, timeout, not_applicable
    stateright_status: str = "unknown"  # passed, failed, not_implemented
    last_verified: Optional[str] = None
    verification_time: Optional[float] = None
    proof_obligations_total: int = 0
    proof_obligations_complete: int = 0
    error_messages: List[str] = field(default_factory=list)

@dataclass
class EnhancedTheoremMapping:
    """Enhanced theorem mapping with comprehensive verification information"""
    whitepaper_id: str
    tla_id: str
    confidence: float
    mapping_type: str
    verification_status: VerificationStatus
    file_location: str = ""
    line_range: Tuple[int, int] = (0, 0)
    cross_references: List[str] = field(default_factory=list)
    notes: str = ""
    last_updated: str = ""
    checksum: str = ""

@dataclass
class MappingReport:
    """Comprehensive mapping report structure"""
    generation_timestamp: str
    total_whitepaper_theorems: int
    total_tla_theorems: int
    mapped_theorems: int
    verification_summary: Dict[str, int]
    mappings: List[EnhancedTheoremMapping]
    unmapped_whitepaper: List[str]
    unmapped_tla: List[str]
    cross_references: Dict[str, List[str]]
    statistics: Dict[str, Any]

class EnhancedWhitepaperParser:
    """Enhanced parser for extracting theorems from the Alpenglow whitepaper"""
    
    def __init__(self, whitepaper_path: str):
        self.whitepaper_path = whitepaper_path
        self.theorems = {}
        self.section_map = {}
        self.cross_references = defaultdict(list)
        
    def parse(self) -> Dict[str, WhitepaperTheorem]:
        """Enhanced parsing with better theorem extraction and cross-reference detection"""
        logger.info(f"Enhanced parsing of whitepaper: {self.whitepaper_path}")
        
        try:
            with open(self.whitepaper_path, 'r', encoding='utf-8') as f:
                content = f.read()
        except FileNotFoundError:
            logger.error(f"Whitepaper file not found: {self.whitepaper_path}")
            return {}
        
        # Extract sections and build hierarchy
        self._extract_sections(content)
        
        # Extract all mathematical statements
        self._extract_theorems(content)
        self._extract_lemmas(content)
        self._extract_assumptions(content)
        self._extract_definitions(content)
        self._extract_corollaries(content)
        
        # Build cross-reference network
        self._extract_cross_references(content)
        
        logger.info(f"Enhanced extraction complete: {len(self.theorems)} mathematical statements")
        return self.theorems
    
    def _extract_sections(self, content: str):
        """Enhanced section extraction with hierarchy tracking"""
        section_pattern = r'^(#{1,4})\s+(\d+(?:\.\d+)*)\s+(.+)$'
        current_hierarchy = {}
        
        for line_num, line in enumerate(content.split('\n'), 1):
            match = re.match(section_pattern, line.strip())
            if match:
                level = len(match.group(1))
                number = match.group(2)
                title = match.group(3)
                
                # Update hierarchy
                current_hierarchy[level] = f"{number} {title}"
                # Clear deeper levels
                for deeper_level in range(level + 1, 5):
                    current_hierarchy.pop(deeper_level, None)
                
                # Build full section path
                section_path = " > ".join([current_hierarchy[l] for l in sorted(current_hierarchy.keys())])
                self.section_map[line_num] = section_path
    
    def _extract_theorems(self, content: str):
        """Enhanced theorem extraction with better pattern matching"""
        # Multiple patterns for theorem detection
        patterns = [
            r'Theorem\s+(\d+)\s*(?:\(([^)]+)\))?\s*[.:]?\s*(.+?)(?=\n\n|\nProof|\nLemma|\nTheorem|\nAssumption|\n#|\Z)',
            r'THEOREM\s+(\d+)\s*(?:\(([^)]+)\))?\s*[.:]?\s*(.+?)(?=\n\n|\nPROOF|\nLEMMA|\nTHEOREM|\n#|\Z)',
            r'Main\s+Theorem\s+(\d+)\s*(?:\(([^)]+)\))?\s*[.:]?\s*(.+?)(?=\n\n|\nProof|\Z)'
        ]
        
        for pattern in patterns:
            for match in re.finditer(pattern, content, re.DOTALL | re.IGNORECASE):
                theorem_num = match.group(1)
                theorem_name = match.group(2) or f"Theorem {theorem_num}"
                statement = self._clean_statement(match.group(3))
                
                proof_sketch = self._extract_proof_sketch(content, match.end())
                section = self._find_section_context(content, match.start())
                dependencies = self._extract_dependencies(statement)
                
                theorem_id = f"theorem_{theorem_num}"
                self.theorems[theorem_id] = WhitepaperTheorem(
                    id=theorem_id,
                    type="theorem",
                    title=theorem_name,
                    statement=statement,
                    proof_sketch=proof_sketch,
                    section=section,
                    dependencies=dependencies
                )
    
    def _extract_lemmas(self, content: str):
        """Enhanced lemma extraction with numbered and named lemmas"""
        patterns = [
            r'Lemma\s+(\d+)\s*(?:\(([^)]+)\))?\s*[.:]?\s*(.+?)(?=\n\n|\nProof|\nLemma|\nTheorem|\n#|\Z)',
            r'LEMMA\s+(\d+)\s*(?:\(([^)]+)\))?\s*[.:]?\s*(.+?)(?=\n\n|\nPROOF|\nLEMMA|\n#|\Z)',
            r'Lemma\s+([A-Za-z][A-Za-z0-9_]*)\s*(?:\(([^)]+)\))?\s*[.:]?\s*(.+?)(?=\n\n|\nProof|\Z)'
        ]
        
        for pattern in patterns:
            for match in re.finditer(pattern, content, re.DOTALL | re.IGNORECASE):
                lemma_id_raw = match.group(1)
                lemma_name = match.group(2) or f"Lemma {lemma_id_raw}"
                statement = self._clean_statement(match.group(3))
                
                proof_sketch = self._extract_proof_sketch(content, match.end())
                section = self._find_section_context(content, match.start())
                dependencies = self._extract_dependencies(statement)
                
                # Handle both numbered and named lemmas
                if lemma_id_raw.isdigit():
                    lemma_id = f"lemma_{lemma_id_raw}"
                else:
                    lemma_id = f"lemma_{lemma_id_raw.lower()}"
                
                self.theorems[lemma_id] = WhitepaperTheorem(
                    id=lemma_id,
                    type="lemma",
                    title=lemma_name,
                    statement=statement,
                    proof_sketch=proof_sketch,
                    section=section,
                    dependencies=dependencies
                )
    
    def _extract_corollaries(self, content: str):
        """Extract corollaries"""
        pattern = r'Corollary\s+(\d+)\s*(?:\(([^)]+)\))?\s*[.:]?\s*(.+?)(?=\n\n|\nProof|\nCorollary|\nLemma|\nTheorem|\n#|\Z)'
        
        for match in re.finditer(pattern, content, re.DOTALL | re.IGNORECASE):
            corollary_num = match.group(1)
            corollary_name = match.group(2) or f"Corollary {corollary_num}"
            statement = self._clean_statement(match.group(3))
            
            proof_sketch = self._extract_proof_sketch(content, match.end())
            section = self._find_section_context(content, match.start())
            dependencies = self._extract_dependencies(statement)
            
            corollary_id = f"corollary_{corollary_num}"
            self.theorems[corollary_id] = WhitepaperTheorem(
                id=corollary_id,
                type="corollary",
                title=corollary_name,
                statement=statement,
                proof_sketch=proof_sketch,
                section=section,
                dependencies=dependencies
            )
    
    def _extract_assumptions(self, content: str):
        """Extract assumptions from the whitepaper"""
        patterns = [
            r'Assumption\s+(\d+)\s*(?:\(([^)]+)\))?\s*[.:]?\s*(.+?)(?=\n\n|\nProof|\nLemma|\nTheorem|\nAssumption|\n#|\Z)',
            r'ASSUMPTION\s+(\d+)\s*(?:\(([^)]+)\))?\s*[.:]?\s*(.+?)(?=\n\n|\nPROOF|\nLEMMA|\nTHEOREM|\n#|\Z)'
        ]
        
        for pattern in patterns:
            for match in re.finditer(pattern, content, re.DOTALL | re.IGNORECASE):
                assumption_num = match.group(1)
                assumption_name = match.group(2) or f"Assumption {assumption_num}"
                statement = self._clean_statement(match.group(3))
                
                section = self._find_section_context(content, match.start())
                dependencies = self._extract_dependencies(statement)
                
                assumption_id = f"assumption_{assumption_num}"
                self.theorems[assumption_id] = WhitepaperTheorem(
                    id=assumption_id,
                    type="assumption",
                    title=assumption_name,
                    statement=statement,
                    proof_sketch="",
                    section=section,
                    dependencies=dependencies
                )
    
    def _extract_definitions(self, content: str):
        """Extract definitions from the whitepaper"""
        patterns = [
            r'Definition\s+(\d+)\s*(?:\(([^)]+)\))?\s*[.:]?\s*(.+?)(?=\n\n|\nProof|\nLemma|\nTheorem|\nDefinition|\n#|\Z)',
            r'DEFINITION\s+(\d+)\s*(?:\(([^)]+)\))?\s*[.:]?\s*(.+?)(?=\n\n|\nPROOF|\nLEMMA|\nTHEOREM|\n#|\Z)'
        ]
        
        for pattern in patterns:
            for match in re.finditer(pattern, content, re.DOTALL | re.IGNORECASE):
                definition_num = match.group(1)
                definition_name = match.group(2) or f"Definition {definition_num}"
                statement = self._clean_statement(match.group(3))
                
                section = self._find_section_context(content, match.start())
                dependencies = self._extract_dependencies(statement)
                
                definition_id = f"definition_{definition_num}"
                self.theorems[definition_id] = WhitepaperTheorem(
                    id=definition_id,
                    type="definition",
                    title=definition_name,
                    statement=statement,
                    proof_sketch="",
                    section=section,
                    dependencies=dependencies
                )
    
    def _extract_cross_references(self, content: str):
        """Extract cross-references between theorems and lemmas"""
        # Patterns for references
        ref_patterns = [
            r'(?:by|By|using|Using)\s+(?:Theorem|theorem)\s+(\d+)',
            r'(?:by|By|using|Using)\s+(?:Lemma|lemma)\s+(\d+)',
            r'(?:by|By|using|Using)\s+(?:Assumption|assumption)\s+(\d+)',
            r'(?:see|See)\s+(?:Theorem|theorem)\s+(\d+)',
            r'(?:see|See)\s+(?:Lemma|lemma)\s+(\d+)',
            r'(?:follows from|Follows from)\s+(?:Theorem|theorem)\s+(\d+)',
            r'(?:follows from|Follows from)\s+(?:Lemma|lemma)\s+(\d+)'
        ]
        
        for theorem_id, theorem in self.theorems.items():
            full_text = theorem.statement + " " + theorem.proof_sketch
            
            for pattern in ref_patterns:
                matches = re.findall(pattern, full_text, re.IGNORECASE)
                for match in matches:
                    if 'theorem' in pattern.lower():
                        ref_id = f"theorem_{match}"
                    elif 'lemma' in pattern.lower():
                        ref_id = f"lemma_{match}"
                    elif 'assumption' in pattern.lower():
                        ref_id = f"assumption_{match}"
                    else:
                        continue
                    
                    if ref_id in self.theorems:
                        self.cross_references[theorem_id].append(ref_id)
    
    def _clean_statement(self, statement: str) -> str:
        """Clean and normalize theorem statements"""
        # Remove extra whitespace and normalize
        statement = re.sub(r'\s+', ' ', statement.strip())
        
        # Remove markdown formatting
        statement = re.sub(r'\*\*([^*]+)\*\*', r'\1', statement)  # Bold
        statement = re.sub(r'\*([^*]+)\*', r'\1', statement)      # Italic
        statement = re.sub(r'`([^`]+)`', r'\1', statement)        # Code
        
        return statement
    
    def _extract_dependencies(self, statement: str) -> List[str]:
        """Extract theorem dependencies from statement text"""
        dependencies = []
        
        # Look for explicit references
        ref_patterns = [
            r'(?:Theorem|theorem)\s+(\d+)',
            r'(?:Lemma|lemma)\s+(\d+)',
            r'(?:Assumption|assumption)\s+(\d+)',
            r'(?:Definition|definition)\s+(\d+)'
        ]
        
        for pattern in ref_patterns:
            matches = re.findall(pattern, statement)
            for match in matches:
                if 'theorem' in pattern.lower():
                    dependencies.append(f"theorem_{match}")
                elif 'lemma' in pattern.lower():
                    dependencies.append(f"lemma_{match}")
                elif 'assumption' in pattern.lower():
                    dependencies.append(f"assumption_{match}")
                elif 'definition' in pattern.lower():
                    dependencies.append(f"definition_{match}")
        
        return list(set(dependencies))
    
    def _extract_proof_sketch(self, content: str, start_pos: int) -> str:
        """Enhanced proof sketch extraction"""
        remaining_content = content[start_pos:]
        
        # Multiple patterns for proof detection
        proof_patterns = [
            r'\n\s*Proof[.:]?\s*(.+?)(?=\n\n|\nLemma|\nTheorem|\nAssumption|\n#|\Z)',
            r'\n\s*Proof\s+Sketch[.:]?\s*(.+?)(?=\n\n|\nLemma|\nTheorem|\n#|\Z)',
            r'\n\s*Proof\s+Outline[.:]?\s*(.+?)(?=\n\n|\nLemma|\nTheorem|\n#|\Z)'
        ]
        
        for pattern in proof_patterns:
            proof_match = re.search(pattern, remaining_content, re.DOTALL | re.IGNORECASE)
            if proof_match:
                return self._clean_statement(proof_match.group(1))
        
        return ""
    
    def _find_section_context(self, content: str, position: int) -> str:
        """Enhanced section context finding with full hierarchy"""
        lines_before = content[:position].count('\n')
        
        # Find the most recent section
        for line_num in sorted(self.section_map.keys(), reverse=True):
            if line_num <= lines_before:
                return self.section_map[line_num]
        
        return "Unknown Section"

class EnhancedTLAParser:
    """Enhanced TLA+ parser with better proof status detection"""
    
    def __init__(self, specs_dir: str, proofs_dir: str):
        self.specs_dir = specs_dir
        self.proofs_dir = proofs_dir
        self.theorems = {}
        
    def parse(self) -> Dict[str, TLATheorem]:
        """Enhanced TLA+ parsing with proof status detection"""
        logger.info(f"Enhanced TLA+ parsing in: {self.specs_dir} and {self.proofs_dir}")
        
        # Parse specification files
        spec_files = list(Path(self.specs_dir).rglob("*.tla"))
        proof_files = list(Path(self.proofs_dir).rglob("*.tla"))
        
        all_files = spec_files + proof_files
        logger.info(f"Found {len(all_files)} TLA+ files")
        
        for tla_file in all_files:
            self._parse_tla_file(tla_file)
        
        logger.info(f"Enhanced extraction complete: {len(self.theorems)} TLA+ theorems")
        return self.theorems
    
    def _parse_tla_file(self, file_path: Path):
        """Enhanced TLA+ file parsing"""
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
        except Exception as e:
            logger.warning(f"Could not read {file_path}: {e}")
            return
        
        module_name = file_path.stem
        
        # Extract different types of statements
        self._extract_tla_theorems(content, module_name, str(file_path))
        self._extract_tla_lemmas(content, module_name, str(file_path))
        self._extract_tla_invariants(content, module_name, str(file_path))
        self._extract_tla_properties(content, module_name, str(file_path))
    
    def _extract_tla_theorems(self, content: str, module: str, file_path: str):
        """Enhanced THEOREM extraction with line numbers"""
        # Multiple patterns for theorem detection
        patterns = [
            r'THEOREM\s+([A-Za-z_][A-Za-z0-9_]*)\s*==\s*(.+?)(?=\nPROOF|\nLEMMA|\nTHEOREM|\n====|\Z)',
            r'THEOREM\s+([A-Za-z_][A-Za-z0-9_]*)\s*\n\s*(.+?)(?=\nPROOF|\nLEMMA|\nTHEOREM|\n====|\Z)'
        ]
        
        lines = content.split('\n')
        for line_num, line in enumerate(lines, 1):
            if 'THEOREM' in line:
                # Find the complete theorem statement
                for pattern in patterns:
                    theorem_match = re.search(pattern, content[content.find(line):], re.DOTALL)
                    if theorem_match:
                        theorem_name = theorem_match.group(1)
                        statement = self._clean_tla_statement(theorem_match.group(2))
                        
                        # Enhanced proof status detection
                        proof_status = self._check_enhanced_proof_status(content, theorem_name, line_num)
                        
                        # Extract dependencies and proof obligations
                        dependencies = self._extract_tla_dependencies(statement)
                        proof_obligations = self._extract_proof_obligations(content, theorem_name)
                        
                        theorem_id = f"{module}_{theorem_name}"
                        self.theorems[theorem_id] = TLATheorem(
                            id=theorem_id,
                            name=theorem_name,
                            statement=statement,
                            proof_status=proof_status,
                            module=module,
                            line_number=line_num,
                            dependencies=dependencies,
                            proof_obligations=proof_obligations
                        )
                        break
    
    def _extract_tla_lemmas(self, content: str, module: str, file_path: str):
        """Enhanced LEMMA extraction"""
        pattern = r'LEMMA\s+([A-Za-z_][A-Za-z0-9_]*)\s*==\s*(.+?)(?=\nPROOF|\nLEMMA|\nTHEOREM|\n====|\Z)'
        
        lines = content.split('\n')
        for line_num, line in enumerate(lines, 1):
            if 'LEMMA' in line:
                lemma_match = re.search(pattern, content[content.find(line):], re.DOTALL)
                if lemma_match:
                    lemma_name = lemma_match.group(1)
                    statement = self._clean_tla_statement(lemma_match.group(2))
                    
                    proof_status = self._check_enhanced_proof_status(content, lemma_name, line_num)
                    dependencies = self._extract_tla_dependencies(statement)
                    proof_obligations = self._extract_proof_obligations(content, lemma_name)
                    
                    lemma_id = f"{module}_{lemma_name}"
                    self.theorems[lemma_id] = TLATheorem(
                        id=lemma_id,
                        name=lemma_name,
                        statement=statement,
                        proof_status=proof_status,
                        module=module,
                        line_number=line_num,
                        dependencies=dependencies,
                        proof_obligations=proof_obligations
                    )
    
    def _extract_tla_invariants(self, content: str, module: str, file_path: str):
        """Extract invariant properties"""
        pattern = r'([A-Za-z_][A-Za-z0-9_]*Invariant)\s*==\s*(.+?)(?=\n\n|\n[A-Z]|\n====|\Z)'
        
        for match in re.finditer(pattern, content, re.DOTALL):
            invariant_name = match.group(1)
            statement = self._clean_tla_statement(match.group(2))
            
            line_num = content[:match.start()].count('\n') + 1
            
            invariant_id = f"{module}_{invariant_name}"
            self.theorems[invariant_id] = TLATheorem(
                id=invariant_id,
                name=invariant_name,
                statement=statement,
                proof_status="invariant",
                module=module,
                line_number=line_num,
                dependencies=[],
                proof_obligations=[]
            )
    
    def _extract_tla_properties(self, content: str, module: str, file_path: str):
        """Extract temporal properties"""
        pattern = r'([A-Za-z_][A-Za-z0-9_]*Property)\s*==\s*(.+?)(?=\n\n|\n[A-Z]|\n====|\Z)'
        
        for match in re.finditer(pattern, content, re.DOTALL):
            property_name = match.group(1)
            statement = self._clean_tla_statement(match.group(2))
            
            line_num = content[:match.start()].count('\n') + 1
            
            property_id = f"{module}_{property_name}"
            self.theorems[property_id] = TLATheorem(
                id=property_id,
                name=property_name,
                statement=statement,
                proof_status="property",
                module=module,
                line_number=line_num,
                dependencies=[],
                proof_obligations=[]
            )
    
    def _check_enhanced_proof_status(self, content: str, theorem_name: str, line_num: int) -> str:
        """Enhanced proof status detection with multiple indicators"""
        # Look for PROOF...QED block
        proof_pattern = rf'{theorem_name}\s*==.*?PROOF.*?QED'
        if re.search(proof_pattern, content, re.DOTALL):
            # Check for completion indicators
            if 'OMITTED' in content:
                return 'incomplete'
            elif 'OBVIOUS' in content:
                return 'trivial'
            elif 'BY' in content and 'DEF' in content:
                return 'complete'
            else:
                return 'incomplete'
        
        # Check for proof sketch or placeholder
        if f'{theorem_name}' in content and 'PROOF' in content:
            return 'incomplete'
        
        # Check for ASSUME/PROVE structure
        assume_prove_pattern = rf'{theorem_name}\s*==.*?ASSUME.*?PROVE'
        if re.search(assume_prove_pattern, content, re.DOTALL):
            return 'structured'
        
        return 'missing'
    
    def _clean_tla_statement(self, statement: str) -> str:
        """Clean TLA+ statements"""
        # Remove extra whitespace
        statement = re.sub(r'\s+', ' ', statement.strip())
        
        # Remove comments
        statement = re.sub(r'\\[*].*?[*]\\', '', statement, flags=re.DOTALL)
        
        return statement
    
    def _extract_tla_dependencies(self, statement: str) -> List[str]:
        """Extract TLA+ dependencies from statement"""
        dependencies = []
        
        # Look for references to other theorems/lemmas
        ref_patterns = [
            r'BY\s+([A-Za-z_][A-Za-z0-9_]*)',
            r'USE\s+([A-Za-z_][A-Za-z0-9_]*)',
            r'([A-Za-z_][A-Za-z0-9_]*!)([A-Za-z_][A-Za-z0-9_]*)',
            r'INSTANCE\s+([A-Za-z_][A-Za-z0-9_]*)'
        ]
        
        for pattern in ref_patterns:
            matches = re.findall(pattern, statement)
            for match in matches:
                if isinstance(match, tuple):
                    dependencies.append(match[1])
                else:
                    dependencies.append(match)
        
        return list(set(dependencies))
    
    def _extract_proof_obligations(self, content: str, theorem_name: str) -> List[str]:
        """Extract proof obligations from TLA+ proofs"""
        obligations = []
        
        # Look for proof steps
        proof_step_pattern = r'<(\d+)>(\d+)\.\s*(.+?)(?=\n\s*<|\nPROOF|\nQED|\Z)'
        
        # Find the theorem's proof section
        theorem_proof_pattern = rf'{theorem_name}\s*==.*?PROOF(.*?)QED'
        proof_match = re.search(theorem_proof_pattern, content, re.DOTALL)
        
        if proof_match:
            proof_content = proof_match.group(1)
            for match in re.finditer(proof_step_pattern, proof_content, re.DOTALL):
                level = match.group(1)
                step = match.group(2)
                obligation = match.group(3).strip()
                obligations.append(f"<{level}>{step}: {obligation}")
        
        return obligations

class VerificationStatusChecker:
    """Check verification status from multiple sources"""
    
    def __init__(self, project_root: str):
        self.project_root = Path(project_root)
        self.tlaps_results = {}
        self.tlc_results = {}
        self.stateright_results = {}
        
    def check_all_verification_status(self, theorems: Dict[str, TLATheorem]) -> Dict[str, VerificationStatus]:
        """Check verification status from all sources"""
        logger.info("Checking verification status from all sources")
        
        status_map = {}
        
        # Check TLAPS results
        self._check_tlaps_status()
        
        # Check TLC results
        self._check_tlc_status()
        
        # Check Stateright results
        self._check_stateright_status()
        
        # Combine results for each theorem
        for theorem_id, theorem in theorems.items():
            status = VerificationStatus()
            
            # TLAPS status
            if theorem_id in self.tlaps_results:
                status.tlaps_status = self.tlaps_results[theorem_id]['status']
                status.proof_obligations_total = self.tlaps_results[theorem_id].get('total_obligations', 0)
                status.proof_obligations_complete = self.tlaps_results[theorem_id].get('complete_obligations', 0)
                status.last_verified = self.tlaps_results[theorem_id].get('timestamp')
                status.verification_time = self.tlaps_results[theorem_id].get('verification_time')
                status.error_messages.extend(self.tlaps_results[theorem_id].get('errors', []))
            
            # TLC status
            if theorem_id in self.tlc_results:
                status.tlc_status = self.tlc_results[theorem_id]['status']
                if not status.last_verified:
                    status.last_verified = self.tlc_results[theorem_id].get('timestamp')
            
            # Stateright status
            if theorem_id in self.stateright_results:
                status.stateright_status = self.stateright_results[theorem_id]['status']
                if not status.last_verified:
                    status.last_verified = self.stateright_results[theorem_id].get('timestamp')
            
            status_map[theorem_id] = status
        
        return status_map
    
    def _check_tlaps_status(self):
        """Check TLAPS verification results"""
        tlaps_output_dir = self.project_root / "results" / "tlaps"
        
        if not tlaps_output_dir.exists():
            logger.warning(f"TLAPS output directory not found: {tlaps_output_dir}")
            return
        
        # Look for TLAPS output files
        for result_file in tlaps_output_dir.glob("*.xml"):
            self._parse_tlaps_xml(result_file)
        
        for result_file in tlaps_output_dir.glob("*.log"):
            self._parse_tlaps_log(result_file)
    
    def _parse_tlaps_xml(self, xml_file: Path):
        """Parse TLAPS XML output"""
        try:
            tree = ET.parse(xml_file)
            root = tree.getroot()
            
            for theorem_elem in root.findall('.//theorem'):
                theorem_name = theorem_elem.get('name', '')
                status = theorem_elem.get('status', 'unknown')
                
                obligations = theorem_elem.findall('.//obligation')
                total_obligations = len(obligations)
                complete_obligations = len([o for o in obligations if o.get('status') == 'proved'])
                
                timestamp = theorem_elem.get('timestamp')
                verification_time = float(theorem_elem.get('time', 0))
                
                errors = [e.text for e in theorem_elem.findall('.//error')]
                
                self.tlaps_results[theorem_name] = {
                    'status': status,
                    'total_obligations': total_obligations,
                    'complete_obligations': complete_obligations,
                    'timestamp': timestamp,
                    'verification_time': verification_time,
                    'errors': errors
                }
        except Exception as e:
            logger.warning(f"Could not parse TLAPS XML {xml_file}: {e}")
    
    def _parse_tlaps_log(self, log_file: Path):
        """Parse TLAPS log output"""
        try:
            with open(log_file, 'r') as f:
                content = f.read()
            
            # Extract theorem results from log
            theorem_pattern = r'Theorem\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(proved|failed|timeout)'
            
            for match in re.finditer(theorem_pattern, content, re.IGNORECASE):
                theorem_name = match.group(1)
                status = match.group(2).lower()
                
                if theorem_name not in self.tlaps_results:
                    self.tlaps_results[theorem_name] = {
                        'status': status,
                        'total_obligations': 0,
                        'complete_obligations': 0,
                        'timestamp': None,
                        'verification_time': 0,
                        'errors': []
                    }
        except Exception as e:
            logger.warning(f"Could not parse TLAPS log {log_file}: {e}")
    
    def _check_tlc_status(self):
        """Check TLC model checking results"""
        tlc_output_dir = self.project_root / "results" / "tlc"
        
        if not tlc_output_dir.exists():
            logger.warning(f"TLC output directory not found: {tlc_output_dir}")
            return
        
        # Look for TLC output files
        for result_file in tlc_output_dir.glob("*.out"):
            self._parse_tlc_output(result_file)
        
        for result_file in tlc_output_dir.glob("*.json"):
            self._parse_tlc_json(result_file)
    
    def _parse_tlc_output(self, output_file: Path):
        """Parse TLC output files"""
        try:
            with open(output_file, 'r') as f:
                content = f.read()
            
            # Extract model checking results
            if "Model checking completed" in content:
                status = "verified"
            elif "Error:" in content or "Invariant" in content and "violated" in content:
                status = "failed"
            elif "timeout" in content.lower():
                status = "timeout"
            else:
                status = "unknown"
            
            # Extract timestamp
            timestamp_match = re.search(r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', content)
            timestamp = timestamp_match.group(1) if timestamp_match else None
            
            # Use filename to identify the theorem/property
            theorem_name = output_file.stem
            
            self.tlc_results[theorem_name] = {
                'status': status,
                'timestamp': timestamp
            }
        except Exception as e:
            logger.warning(f"Could not parse TLC output {output_file}: {e}")
    
    def _parse_tlc_json(self, json_file: Path):
        """Parse TLC JSON results"""
        try:
            with open(json_file, 'r') as f:
                data = json.load(f)
            
            for result in data.get('results', []):
                theorem_name = result.get('property', '')
                status = result.get('status', 'unknown')
                timestamp = result.get('timestamp')
                
                self.tlc_results[theorem_name] = {
                    'status': status,
                    'timestamp': timestamp
                }
        except Exception as e:
            logger.warning(f"Could not parse TLC JSON {json_file}: {e}")
    
    def _check_stateright_status(self):
        """Check Stateright verification results"""
        stateright_output_dir = self.project_root / "stateright" / "target" / "test-results"
        
        if not stateright_output_dir.exists():
            logger.warning(f"Stateright output directory not found: {stateright_output_dir}")
            return
        
        # Look for Rust test output
        for result_file in stateright_output_dir.glob("*.json"):
            self._parse_stateright_json(result_file)
    
    def _parse_stateright_json(self, json_file: Path):
        """Parse Stateright test results"""
        try:
            with open(json_file, 'r') as f:
                data = json.load(f)
            
            for test_result in data.get('tests', []):
                test_name = test_result.get('name', '')
                status = 'passed' if test_result.get('passed', False) else 'failed'
                timestamp = test_result.get('timestamp')
                
                # Map test names to theorem names
                if 'theorem' in test_name.lower() or 'lemma' in test_name.lower():
                    self.stateright_results[test_name] = {
                        'status': status,
                        'timestamp': timestamp
                    }
        except Exception as e:
            logger.warning(f"Could not parse Stateright JSON {json_file}: {e}")

class EnhancedMappingGenerator:
    """Enhanced mapping generator with comprehensive features"""
    
    def __init__(self, project_root: str):
        self.project_root = Path(project_root)
        self.whitepaper_parser = None
        self.tla_parser = None
        self.verification_checker = None
        self.mapper = None
        
    def generate_comprehensive_mapping(self, whitepaper_path: str, specs_dir: str, 
                                     proofs_dir: str, output_dir: str) -> MappingReport:
        """Generate comprehensive theorem mapping"""
        logger.info("Starting comprehensive theorem mapping generation")
        
        # Initialize components
        self.whitepaper_parser = EnhancedWhitepaperParser(whitepaper_path)
        self.tla_parser = EnhancedTLAParser(specs_dir, proofs_dir)
        self.verification_checker = VerificationStatusChecker(self.project_root)
        
        # Parse theorems
        whitepaper_theorems = self.whitepaper_parser.parse()
        tla_theorems = self.tla_parser.parse()
        
        # Check verification status
        verification_status = self.verification_checker.check_all_verification_status(tla_theorems)
        
        # Create mappings
        if 'CorrespondenceMapper' in globals():
            self.mapper = CorrespondenceMapper()
            basic_mappings = self.mapper.create_mappings(whitepaper_theorems, tla_theorems)
        else:
            basic_mappings = self._create_basic_mappings(whitepaper_theorems, tla_theorems)
        
        # Enhance mappings with verification status
        enhanced_mappings = self._enhance_mappings(basic_mappings, verification_status, 
                                                 whitepaper_theorems, tla_theorems)
        
        # Generate cross-references
        cross_references = self._generate_cross_references(whitepaper_theorems, enhanced_mappings)
        
        # Calculate statistics
        statistics = self._calculate_statistics(enhanced_mappings, verification_status)
        
        # Create comprehensive report
        report = MappingReport(
            generation_timestamp=datetime.datetime.now().isoformat(),
            total_whitepaper_theorems=len(whitepaper_theorems),
            total_tla_theorems=len(tla_theorems),
            mapped_theorems=len(enhanced_mappings),
            verification_summary=self._summarize_verification_status(verification_status),
            mappings=enhanced_mappings,
            unmapped_whitepaper=self._find_unmapped_whitepaper(whitepaper_theorems, enhanced_mappings),
            unmapped_tla=self._find_unmapped_tla(tla_theorems, enhanced_mappings),
            cross_references=cross_references,
            statistics=statistics
        )
        
        # Generate outputs
        self._generate_all_outputs(report, output_dir)
        
        logger.info(f"Comprehensive mapping generation complete: {len(enhanced_mappings)} mappings")
        return report
    
    def _create_basic_mappings(self, whitepaper_theorems: Dict[str, WhitepaperTheorem],
                             tla_theorems: Dict[str, TLATheorem]) -> Dict[str, Any]:
        """Create basic mappings when CorrespondenceMapper is not available"""
        mappings = {}
        
        # Simple name-based matching
        for wp_id, wp_theorem in whitepaper_theorems.items():
            for tla_id, tla_theorem in tla_theorems.items():
                # Check for name similarity
                if self._names_similar(wp_theorem.title, tla_theorem.name):
                    mapping_id = f"{wp_id}_to_{tla_id}"
                    mappings[mapping_id] = {
                        'whitepaper_id': wp_id,
                        'tla_id': tla_id,
                        'confidence': 0.8,
                        'mapping_type': 'name_based'
                    }
        
        return mappings
    
    def _names_similar(self, name1: str, name2: str) -> bool:
        """Check if two names are similar"""
        name1_clean = re.sub(r'[^a-zA-Z0-9]', '', name1.lower())
        name2_clean = re.sub(r'[^a-zA-Z0-9]', '', name2.lower())
        
        # Check for common substrings
        if len(name1_clean) > 3 and name1_clean in name2_clean:
            return True
        if len(name2_clean) > 3 and name2_clean in name1_clean:
            return True
        
        return False
    
    def _enhance_mappings(self, basic_mappings: Dict[str, Any], 
                         verification_status: Dict[str, VerificationStatus],
                         whitepaper_theorems: Dict[str, WhitepaperTheorem],
                         tla_theorems: Dict[str, TLATheorem]) -> List[EnhancedTheoremMapping]:
        """Enhance basic mappings with verification status and additional information"""
        enhanced_mappings = []
        
        for mapping_id, mapping in basic_mappings.items():
            wp_id = mapping.get('whitepaper_id', '')
            tla_id = mapping.get('tla_id', '')
            
            # Get verification status
            status = verification_status.get(tla_id, VerificationStatus())
            
            # Get file location and line range
            tla_theorem = tla_theorems.get(tla_id)
            file_location = ""
            line_range = (0, 0)
            if tla_theorem:
                file_location = f"{tla_theorem.module}.tla"
                line_range = (tla_theorem.line_number, tla_theorem.line_number + 10)  # Estimate
            
            # Generate cross-references
            cross_refs = []
            wp_theorem = whitepaper_theorems.get(wp_id)
            if wp_theorem:
                cross_refs = wp_theorem.dependencies
            
            # Calculate checksum for change detection
            content = f"{wp_id}_{tla_id}_{status.tlaps_status}_{status.last_verified}"
            checksum = hashlib.md5(content.encode()).hexdigest()
            
            enhanced_mapping = EnhancedTheoremMapping(
                whitepaper_id=wp_id,
                tla_id=tla_id,
                confidence=mapping.get('confidence', 0.5),
                mapping_type=mapping.get('mapping_type', 'unknown'),
                verification_status=status,
                file_location=file_location,
                line_range=line_range,
                cross_references=cross_refs,
                notes="",
                last_updated=datetime.datetime.now().isoformat(),
                checksum=checksum
            )
            
            enhanced_mappings.append(enhanced_mapping)
        
        return enhanced_mappings
    
    def _generate_cross_references(self, whitepaper_theorems: Dict[str, WhitepaperTheorem],
                                 mappings: List[EnhancedTheoremMapping]) -> Dict[str, List[str]]:
        """Generate cross-reference network"""
        cross_refs = defaultdict(list)
        
        # Build mapping from whitepaper ID to TLA ID
        wp_to_tla = {m.whitepaper_id: m.tla_id for m in mappings}
        
        # Generate cross-references
        for wp_id, wp_theorem in whitepaper_theorems.items():
            for dep in wp_theorem.dependencies:
                if dep in wp_to_tla and wp_id in wp_to_tla:
                    cross_refs[wp_to_tla[wp_id]].append(wp_to_tla[dep])
        
        return dict(cross_refs)
    
    def _calculate_statistics(self, mappings: List[EnhancedTheoremMapping],
                            verification_status: Dict[str, VerificationStatus]) -> Dict[str, Any]:
        """Calculate comprehensive statistics"""
        stats = {}
        
        # Verification status distribution
        tlaps_status_counts = defaultdict(int)
        tlc_status_counts = defaultdict(int)
        stateright_status_counts = defaultdict(int)
        
        for mapping in mappings:
            status = mapping.verification_status
            tlaps_status_counts[status.tlaps_status] += 1
            tlc_status_counts[status.tlc_status] += 1
            stateright_status_counts[status.stateright_status] += 1
        
        stats['tlaps_status_distribution'] = dict(tlaps_status_counts)
        stats['tlc_status_distribution'] = dict(tlc_status_counts)
        stats['stateright_status_distribution'] = dict(stateright_status_counts)
        
        # Mapping type distribution
        mapping_type_counts = defaultdict(int)
        for mapping in mappings:
            mapping_type_counts[mapping.mapping_type] += 1
        stats['mapping_type_distribution'] = dict(mapping_type_counts)
        
        # Confidence distribution
        confidences = [m.confidence for m in mappings]
        if confidences:
            stats['confidence_stats'] = {
                'mean': sum(confidences) / len(confidences),
                'min': min(confidences),
                'max': max(confidences)
            }
        
        # Proof obligations statistics
        total_obligations = sum(m.verification_status.proof_obligations_total for m in mappings)
        complete_obligations = sum(m.verification_status.proof_obligations_complete for m in mappings)
        
        stats['proof_obligations'] = {
            'total': total_obligations,
            'complete': complete_obligations,
            'completion_rate': complete_obligations / total_obligations if total_obligations > 0 else 0
        }
        
        return stats
    
    def _summarize_verification_status(self, verification_status: Dict[str, VerificationStatus]) -> Dict[str, int]:
        """Summarize verification status across all methods"""
        summary = {
            'tlaps_complete': 0,
            'tlaps_incomplete': 0,
            'tlaps_missing': 0,
            'tlc_verified': 0,
            'tlc_failed': 0,
            'stateright_passed': 0,
            'stateright_failed': 0
        }
        
        for status in verification_status.values():
            if status.tlaps_status == 'complete':
                summary['tlaps_complete'] += 1
            elif status.tlaps_status == 'incomplete':
                summary['tlaps_incomplete'] += 1
            elif status.tlaps_status == 'missing':
                summary['tlaps_missing'] += 1
            
            if status.tlc_status == 'verified':
                summary['tlc_verified'] += 1
            elif status.tlc_status == 'failed':
                summary['tlc_failed'] += 1
            
            if status.stateright_status == 'passed':
                summary['stateright_passed'] += 1
            elif status.stateright_status == 'failed':
                summary['stateright_failed'] += 1
        
        return summary
    
    def _find_unmapped_whitepaper(self, whitepaper_theorems: Dict[str, WhitepaperTheorem],
                                mappings: List[EnhancedTheoremMapping]) -> List[str]:
        """Find unmapped whitepaper theorems"""
        mapped_wp_ids = {m.whitepaper_id for m in mappings}
        return [wp_id for wp_id in whitepaper_theorems.keys() if wp_id not in mapped_wp_ids]
    
    def _find_unmapped_tla(self, tla_theorems: Dict[str, TLATheorem],
                         mappings: List[EnhancedTheoremMapping]) -> List[str]:
        """Find unmapped TLA+ theorems"""
        mapped_tla_ids = {m.tla_id for m in mappings}
        return [tla_id for tla_id in tla_theorems.keys() if tla_id not in mapped_tla_ids]
    
    def _generate_all_outputs(self, report: MappingReport, output_dir: str):
        """Generate all output formats"""
        output_path = Path(output_dir)
        output_path.mkdir(parents=True, exist_ok=True)
        
        # Generate Markdown report
        self._generate_markdown_output(report, output_path / "theorem_mapping.md")
        
        # Generate JSON data
        self._generate_json_output(report, output_path / "theorem_mapping.json")
        
        # Generate HTML report
        self._generate_html_output(report, output_path / "theorem_mapping.html")
        
        # Generate CSV for spreadsheet analysis
        self._generate_csv_output(report, output_path / "theorem_mapping.csv")
        
        # Generate summary statistics
        self._generate_statistics_output(report, output_path / "mapping_statistics.json")
    
    def _generate_markdown_output(self, report: MappingReport, output_file: Path):
        """Generate Markdown report"""
        with open(output_file, 'w') as f:
            f.write("# Alpenglow Theorem Mapping Report\n\n")
            f.write(f"Generated: {report.generation_timestamp}\n\n")
            
            # Summary
            f.write("## Summary\n\n")
            f.write(f"- **Total Whitepaper Theorems**: {report.total_whitepaper_theorems}\n")
            f.write(f"- **Total TLA+ Theorems**: {report.total_tla_theorems}\n")
            f.write(f"- **Mapped Theorems**: {report.mapped_theorems}\n")
            f.write(f"- **Mapping Coverage**: {report.mapped_theorems / report.total_whitepaper_theorems * 100:.1f}%\n\n")
            
            # Verification Summary
            f.write("## Verification Status Summary\n\n")
            for method, count in report.verification_summary.items():
                f.write(f"- **{method.replace('_', ' ').title()}**: {count}\n")
            f.write("\n")
            
            # Detailed Mappings
            f.write("## Detailed Theorem Mappings\n\n")
            f.write("| Whitepaper ID | TLA+ ID | Confidence | Type | TLAPS | TLC | Stateright | File Location |\n")
            f.write("|---------------|---------|------------|------|-------|-----|------------|---------------|\n")
            
            for mapping in report.mappings:
                status = mapping.verification_status
                f.write(f"| {mapping.whitepaper_id} | {mapping.tla_id} | {mapping.confidence:.2f} | "
                       f"{mapping.mapping_type} | {status.tlaps_status} | {status.tlc_status} | "
                       f"{status.stateright_status} | {mapping.file_location} |\n")
            
            # Unmapped theorems
            if report.unmapped_whitepaper:
                f.write("\n## Unmapped Whitepaper Theorems\n\n")
                for theorem_id in report.unmapped_whitepaper:
                    f.write(f"- {theorem_id}\n")
            
            if report.unmapped_tla:
                f.write("\n## Unmapped TLA+ Theorems\n\n")
                for theorem_id in report.unmapped_tla:
                    f.write(f"- {theorem_id}\n")
    
    def _generate_json_output(self, report: MappingReport, output_file: Path):
        """Generate JSON data"""
        # Convert dataclasses to dictionaries
        report_dict = asdict(report)
        
        with open(output_file, 'w') as f:
            json.dump(report_dict, f, indent=2, default=str)
    
    def _generate_html_output(self, report: MappingReport, output_file: Path):
        """Generate HTML report"""
        html_template = """
<!DOCTYPE html>
<html>
<head>
    <title>Alpenglow Theorem Mapping Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .status-complete { color: green; font-weight: bold; }
        .status-incomplete { color: orange; font-weight: bold; }
        .status-missing { color: red; font-weight: bold; }
        .status-verified { color: green; }
        .status-failed { color: red; }
        .summary { background-color: #f9f9f9; padding: 20px; margin: 20px 0; }
    </style>
</head>
<body>
    <h1>Alpenglow Theorem Mapping Report</h1>
    <p><strong>Generated:</strong> {{ report.generation_timestamp }}</p>
    
    <div class="summary">
        <h2>Summary</h2>
        <ul>
            <li><strong>Total Whitepaper Theorems:</strong> {{ report.total_whitepaper_theorems }}</li>
            <li><strong>Total TLA+ Theorems:</strong> {{ report.total_tla_theorems }}</li>
            <li><strong>Mapped Theorems:</strong> {{ report.mapped_theorems }}</li>
            <li><strong>Mapping Coverage:</strong> {{ "%.1f"|format(report.mapped_theorems / report.total_whitepaper_theorems * 100) }}%</li>
        </ul>
    </div>
    
    <h2>Verification Status Summary</h2>
    <ul>
    {% for method, count in report.verification_summary.items() %}
        <li><strong>{{ method.replace('_', ' ').title() }}:</strong> {{ count }}</li>
    {% endfor %}
    </ul>
    
    <h2>Detailed Theorem Mappings</h2>
    <table>
        <thead>
            <tr>
                <th>Whitepaper ID</th>
                <th>TLA+ ID</th>
                <th>Confidence</th>
                <th>Type</th>
                <th>TLAPS Status</th>
                <th>TLC Status</th>
                <th>Stateright Status</th>
                <th>File Location</th>
                <th>Last Verified</th>
            </tr>
        </thead>
        <tbody>
        {% for mapping in report.mappings %}
            <tr>
                <td>{{ mapping.whitepaper_id }}</td>
                <td>{{ mapping.tla_id }}</td>
                <td>{{ "%.2f"|format(mapping.confidence) }}</td>
                <td>{{ mapping.mapping_type }}</td>
                <td class="status-{{ mapping.verification_status.tlaps_status }}">{{ mapping.verification_status.tlaps_status }}</td>
                <td class="status-{{ mapping.verification_status.tlc_status }}">{{ mapping.verification_status.tlc_status }}</td>
                <td class="status-{{ mapping.verification_status.stateright_status }}">{{ mapping.verification_status.stateright_status }}</td>
                <td>{{ mapping.file_location }}</td>
                <td>{{ mapping.verification_status.last_verified or 'Never' }}</td>
            </tr>
        {% endfor %}
        </tbody>
    </table>
    
    {% if report.unmapped_whitepaper %}
    <h2>Unmapped Whitepaper Theorems</h2>
    <ul>
    {% for theorem_id in report.unmapped_whitepaper %}
        <li>{{ theorem_id }}</li>
    {% endfor %}
    </ul>
    {% endif %}
    
    {% if report.unmapped_tla %}
    <h2>Unmapped TLA+ Theorems</h2>
    <ul>
    {% for theorem_id in report.unmapped_tla %}
        <li>{{ theorem_id }}</li>
    {% endfor %}
    </ul>
    {% endif %}
</body>
</html>
        """
        
        template = Template(html_template)
        html_content = template.render(report=report)
        
        with open(output_file, 'w') as f:
            f.write(html_content)
    
    def _generate_csv_output(self, report: MappingReport, output_file: Path):
        """Generate CSV for spreadsheet analysis"""
        import csv
        
        with open(output_file, 'w', newline='') as f:
            writer = csv.writer(f)
            
            # Header
            writer.writerow([
                'Whitepaper ID', 'TLA+ ID', 'Confidence', 'Mapping Type',
                'TLAPS Status', 'TLC Status', 'Stateright Status',
                'File Location', 'Line Range', 'Last Verified',
                'Proof Obligations Total', 'Proof Obligations Complete'
            ])
            
            # Data rows
            for mapping in report.mappings:
                status = mapping.verification_status
                writer.writerow([
                    mapping.whitepaper_id,
                    mapping.tla_id,
                    mapping.confidence,
                    mapping.mapping_type,
                    status.tlaps_status,
                    status.tlc_status,
                    status.stateright_status,
                    mapping.file_location,
                    f"{mapping.line_range[0]}-{mapping.line_range[1]}",
                    status.last_verified or '',
                    status.proof_obligations_total,
                    status.proof_obligations_complete
                ])
    
    def _generate_statistics_output(self, report: MappingReport, output_file: Path):
        """Generate detailed statistics"""
        with open(output_file, 'w') as f:
            json.dump(report.statistics, f, indent=2, default=str)

def main():
    """Main entry point for the enhanced theorem mapping generator"""
    parser = argparse.ArgumentParser(description="Generate comprehensive theorem-to-proof mappings for Alpenglow")
    parser.add_argument("--whitepaper", required=True, help="Path to the Alpenglow whitepaper markdown file")
    parser.add_argument("--specs-dir", required=True, help="Directory containing TLA+ specification files")
    parser.add_argument("--proofs-dir", required=True, help="Directory containing TLA+ proof files")
    parser.add_argument("--output-dir", default="./theorem_mapping_reports", help="Output directory for reports")
    parser.add_argument("--project-root", default=".", help="Project root directory")
    parser.add_argument("--incremental", action="store_true", help="Enable incremental updates")
    parser.add_argument("--verbose", "-v", action="store_true", help="Enable verbose logging")
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    try:
        # Initialize the enhanced mapping generator
        generator = EnhancedMappingGenerator(args.project_root)
        
        # Generate comprehensive mapping
        report = generator.generate_comprehensive_mapping(
            args.whitepaper,
            args.specs_dir,
            args.proofs_dir,
            args.output_dir
        )
        
        # Print summary
        print(f"\n=== Enhanced Theorem Mapping Generation Complete ===")
        print(f"Whitepaper Theorems: {report.total_whitepaper_theorems}")
        print(f"TLA+ Theorems: {report.total_tla_theorems}")
        print(f"Mapped Theorems: {report.mapped_theorems}")
        print(f"Mapping Coverage: {report.mapped_theorems / report.total_whitepaper_theorems * 100:.1f}%")
        print(f"TLAPS Complete: {report.verification_summary.get('tlaps_complete', 0)}")
        print(f"TLC Verified: {report.verification_summary.get('tlc_verified', 0)}")
        print(f"Stateright Passed: {report.verification_summary.get('stateright_passed', 0)}")
        print(f"Reports generated in: {args.output_dir}")
        
        # Check for completeness
        coverage = report.mapped_theorems / report.total_whitepaper_theorems if report.total_whitepaper_theorems > 0 else 0
        if coverage < 0.8:
            print(f"\nWARNING: Low mapping coverage ({coverage:.1%}). Consider adding more formal specifications.")
            return 1
        
        return 0
        
    except Exception as e:
        logger.error(f"Error during theorem mapping generation: {e}")
        return 1

if __name__ == "__main__":
    exit(main())