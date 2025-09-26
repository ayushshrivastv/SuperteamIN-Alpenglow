#!/usr/bin/env python3
# Author: Ayush Srivastava
"""
Fixed Theorem Mapping Generator for Alpenglow Consensus Protocol
"""

import os
import re
import json
import argparse
import logging
import hashlib
import datetime
from pathlib import Path
from typing import Dict, List, Set, Tuple, Optional, Any, Union
from dataclasses import dataclass, asdict, field
from collections import defaultdict
import csv

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

@dataclass
class VerificationStatus:
    tlaps_status: str = "unknown"
    tlc_status: str = "unknown"
    stateright_status: str = "unknown"
    last_verified: Optional[str] = None
    verification_time: Optional[float] = None
    proof_obligations_total: int = 0
    proof_obligations_complete: int = 0
    error_messages: List[str] = field(default_factory=list)

@dataclass
class EnhancedTheoremMapping:
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

class SimpleTheoremMappingGenerator:
    """Simplified theorem mapping generator"""
    
    def __init__(self, project_root: str):
        self.project_root = Path(project_root)
        
    def generate_mapping(self, whitepaper_path: str, specs_dir: str, 
                        proofs_dir: str, output_dir: str) -> MappingReport:
        """Generate theorem mapping"""
        logger.info("Starting theorem mapping generation")
        
        # Parse whitepaper
        whitepaper_theorems = self._parse_whitepaper(whitepaper_path)
        
        # Parse TLA+ files
        tla_theorems = self._parse_tla_files(specs_dir, proofs_dir)
        
        # Create basic mappings
        mappings = self._create_mappings(whitepaper_theorems, tla_theorems)
        
        # Generate report
        report = MappingReport(
            generation_timestamp=datetime.datetime.now().isoformat(),
            total_whitepaper_theorems=len(whitepaper_theorems),
            total_tla_theorems=len(tla_theorems),
            mapped_theorems=len(mappings),
            verification_summary={"total_mappings": len(mappings)},
            mappings=mappings,
            unmapped_whitepaper=[],
            unmapped_tla=[],
            cross_references={},
            statistics={}
        )
        
        # Generate outputs
        self._generate_outputs(report, output_dir)
        
        logger.info(f"Mapping generation complete: {len(mappings)} mappings")
        return report
    
    def _parse_whitepaper(self, whitepaper_path: str) -> Dict[str, WhitepaperTheorem]:
        """Parse whitepaper for theorems"""
        theorems = {}
        
        try:
            with open(whitepaper_path, 'r', encoding='utf-8') as f:
                content = f.read()
        except FileNotFoundError:
            logger.error(f"Whitepaper file not found: {whitepaper_path}")
            return {}
        
        # Extract theorems using regex
        theorem_pattern = r'Theorem\s+(\d+)\s*(?:\(([^)]+)\))?\s*[.:]?\s*(.+?)(?=\n\n|\nProof|\nLemma|\nTheorem|\n#|\Z)'
        
        for match in re.finditer(theorem_pattern, content, re.DOTALL | re.IGNORECASE):
            theorem_num = match.group(1)
            theorem_name = match.group(2) or f"Theorem {theorem_num}"
            statement = re.sub(r'\s+', ' ', match.group(3).strip())
            
            theorem_id = f"theorem_{theorem_num}"
            theorems[theorem_id] = WhitepaperTheorem(
                id=theorem_id,
                type="theorem",
                title=theorem_name,
                statement=statement,
                proof_sketch="",
                section="Unknown"
            )
        
        # Extract assumptions
        assumption_pattern = r'Assumption\s+(\d+)\s*(?:\(([^)]+)\))?\s*[.:]?\s*(.+?)(?=\n\n|\nProof|\nLemma|\nTheorem|\nAssumption|\n#|\Z)'
        
        for match in re.finditer(assumption_pattern, content, re.DOTALL | re.IGNORECASE):
            assumption_num = match.group(1)
            assumption_name = match.group(2) or f"Assumption {assumption_num}"
            statement = re.sub(r'\s+', ' ', match.group(3).strip())
            
            assumption_id = f"assumption_{assumption_num}"
            theorems[assumption_id] = WhitepaperTheorem(
                id=assumption_id,
                type="assumption",
                title=assumption_name,
                statement=statement,
                proof_sketch="",
                section="Unknown"
            )
        
        logger.info(f"Parsed {len(theorems)} mathematical statements from whitepaper")
        return theorems
    
    def _parse_tla_files(self, specs_dir: str, proofs_dir: str) -> Dict[str, TLATheorem]:
        """Parse TLA+ files for theorems"""
        theorems = {}
        
        # Get all TLA files
        spec_files = list(Path(specs_dir).rglob("*.tla"))
        proof_files = list(Path(proofs_dir).rglob("*.tla"))
        all_files = spec_files + proof_files
        
        logger.info(f"Found {len(all_files)} TLA+ files")
        
        for tla_file in all_files:
            try:
                with open(tla_file, 'r', encoding='utf-8') as f:
                    content = f.read()
            except Exception as e:
                logger.warning(f"Could not read {tla_file}: {e}")
                continue
            
            module_name = tla_file.stem
            
            # Extract THEOREM statements
            theorem_pattern = r'THEOREM\s+([A-Za-z_][A-Za-z0-9_]*)\s*==\s*(.+?)(?=\nPROOF|\nLEMMA|\nTHEOREM|\n====|\Z)'
            
            for match in re.finditer(theorem_pattern, content, re.DOTALL):
                theorem_name = match.group(1)
                statement = re.sub(r'\s+', ' ', match.group(2).strip())
                line_num = content[:match.start()].count('\n') + 1
                
                # Simple proof status detection
                proof_status = "unknown"
                if "PROOF" in content and "QED" in content:
                    proof_status = "complete"
                elif "PROOF" in content:
                    proof_status = "incomplete"
                
                theorem_id = f"{module_name}_{theorem_name}"
                theorems[theorem_id] = TLATheorem(
                    id=theorem_id,
                    name=theorem_name,
                    statement=statement,
                    proof_status=proof_status,
                    module=module_name,
                    line_number=line_num
                )
            
            # Extract LEMMA statements
            lemma_pattern = r'LEMMA\s+([A-Za-z_][A-Za-z0-9_]*)\s*==\s*(.+?)(?=\nPROOF|\nLEMMA|\nTHEOREM|\n====|\Z)'
            
            for match in re.finditer(lemma_pattern, content, re.DOTALL):
                lemma_name = match.group(1)
                statement = re.sub(r'\s+', ' ', match.group(2).strip())
                line_num = content[:match.start()].count('\n') + 1
                
                proof_status = "unknown"
                if "PROOF" in content and "QED" in content:
                    proof_status = "complete"
                elif "PROOF" in content:
                    proof_status = "incomplete"
                
                lemma_id = f"{module_name}_{lemma_name}"
                theorems[lemma_id] = TLATheorem(
                    id=lemma_id,
                    name=lemma_name,
                    statement=statement,
                    proof_status=proof_status,
                    module=module_name,
                    line_number=line_num
                )
        
        logger.info(f"Parsed {len(theorems)} TLA+ theorems/lemmas")
        return theorems
    
    def _create_mappings(self, whitepaper_theorems: Dict[str, WhitepaperTheorem],
                        tla_theorems: Dict[str, TLATheorem]) -> List[EnhancedTheoremMapping]:
        """Create mappings between whitepaper and TLA+ theorems"""
        mappings = []
        
        # Simple name-based matching
        for wp_id, wp_theorem in whitepaper_theorems.items():
            for tla_id, tla_theorem in tla_theorems.items():
                # Check for keyword matches
                if self._has_keyword_match(wp_theorem, tla_theorem):
                    status = VerificationStatus(
                        tlaps_status=tla_theorem.proof_status,
                        tlc_status="unknown",
                        stateright_status="unknown"
                    )
                    
                    mapping = EnhancedTheoremMapping(
                        whitepaper_id=wp_id,
                        tla_id=tla_id,
                        confidence=0.7,
                        mapping_type="keyword_based",
                        verification_status=status,
                        file_location=f"{tla_theorem.module}.tla",
                        line_range=(tla_theorem.line_number, tla_theorem.line_number + 5),
                        last_updated=datetime.datetime.now().isoformat()
                    )
                    mappings.append(mapping)
        
        return mappings
    
    def _has_keyword_match(self, wp_theorem: WhitepaperTheorem, tla_theorem: TLATheorem) -> bool:
        """Check if theorems have keyword matches"""
        wp_keywords = set(re.findall(r'\b\w+\b', wp_theorem.statement.lower()))
        tla_keywords = set(re.findall(r'\b\w+\b', tla_theorem.statement.lower()))
        
        # Key terms for Alpenglow
        important_keywords = {
            'safety', 'liveness', 'consensus', 'finalization', 'byzantine',
            'votor', 'rotor', 'certificate', 'vote', 'block', 'stake'
        }
        
        # Check for overlap in important keywords
        wp_important = wp_keywords & important_keywords
        tla_important = tla_keywords & important_keywords
        
        # If both have important keywords and some overlap
        if wp_important and tla_important and (wp_important & tla_important):
            return True
        
        # Check for direct name similarity
        if wp_theorem.type == "theorem" and "theorem" in tla_theorem.name.lower():
            return True
        
        return False
    
    def _generate_outputs(self, report: MappingReport, output_dir: str):
        """Generate output files"""
        output_path = Path(output_dir)
        output_path.mkdir(exist_ok=True)
        
        # Generate JSON output
        with open(output_path / "theorem_mapping.json", 'w') as f:
            json.dump(asdict(report), f, indent=2, default=str)
        
        # Generate CSV output
        with open(output_path / "theorem_mapping.csv", 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow([
                'Whitepaper ID', 'TLA+ ID', 'Confidence', 'Mapping Type',
                'TLAPS Status', 'TLC Status', 'Stateright Status',
                'File Location', 'Line Range'
            ])
            
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
                    f"{mapping.line_range[0]}-{mapping.line_range[1]}"
                ])
        
        # Generate Markdown output
        with open(output_path / "theorem_mapping.md", 'w') as f:
            f.write("# Alpenglow Theorem Mapping Report\n\n")
            f.write(f"Generated: {report.generation_timestamp}\n\n")
            
            f.write("## Summary\n\n")
            f.write(f"- **Total Whitepaper Theorems**: {report.total_whitepaper_theorems}\n")
            f.write(f"- **Total TLA+ Theorems**: {report.total_tla_theorems}\n")
            f.write(f"- **Mapped Theorems**: {report.mapped_theorems}\n")
            coverage = (report.mapped_theorems / report.total_whitepaper_theorems * 100) if report.total_whitepaper_theorems > 0 else 0
            f.write(f"- **Mapping Coverage**: {coverage:.1f}%\n\n")
            
            f.write("## Detailed Mappings\n\n")
            f.write("| Whitepaper ID | TLA+ ID | Confidence | Type | TLAPS Status | File |\n")
            f.write("|---------------|---------|------------|------|--------------|------|\n")
            
            for mapping in report.mappings:
                f.write(f"| {mapping.whitepaper_id} | {mapping.tla_id} | {mapping.confidence:.2f} | ")
                f.write(f"{mapping.mapping_type} | {mapping.verification_status.tlaps_status} | {mapping.file_location} |\n")
        
        # Generate simple HTML output
        with open(output_path / "theorem_mapping.html", 'w') as f:
            f.write("<!DOCTYPE html>\n<html>\n<head>\n")
            f.write("<title>Alpenglow Theorem Mapping Report</title>\n")
            f.write("<style>body{font-family:Arial,sans-serif;margin:40px}table{border-collapse:collapse;width:100%}th,td{border:1px solid #ddd;padding:8px;text-align:left}th{background-color:#f2f2f2}</style>\n")
            f.write("</head>\n<body>\n")
            f.write("<h1>Alpenglow Theorem Mapping Report</h1>\n")
            f.write(f"<p><strong>Generated:</strong> {report.generation_timestamp}</p>\n")
            f.write(f"<p><strong>Summary:</strong> {report.mapped_theorems} mappings from {report.total_whitepaper_theorems} whitepaper theorems to {report.total_tla_theorems} TLA+ theorems</p>\n")
            f.write("<table>\n<tr><th>Whitepaper ID</th><th>TLA+ ID</th><th>Confidence</th><th>TLAPS Status</th><th>File</th></tr>\n")
            
            for mapping in report.mappings:
                f.write(f"<tr><td>{mapping.whitepaper_id}</td><td>{mapping.tla_id}</td>")
                f.write(f"<td>{mapping.confidence:.2f}</td><td>{mapping.verification_status.tlaps_status}</td>")
                f.write(f"<td>{mapping.file_location}</td></tr>\n")
            
            f.write("</table>\n</body>\n</html>\n")

def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description="Generate theorem mappings for Alpenglow")
    parser.add_argument("--whitepaper", required=True, help="Path to the Alpenglow whitepaper")
    parser.add_argument("--specs-dir", required=True, help="Directory containing TLA+ specifications")
    parser.add_argument("--proofs-dir", required=True, help="Directory containing TLA+ proofs")
    parser.add_argument("--output-dir", default="./theorem_mapping_reports", help="Output directory")
    parser.add_argument("--project-root", default=".", help="Project root directory")
    
    args = parser.parse_args()
    
    try:
        generator = SimpleTheoremMappingGenerator(args.project_root)
        report = generator.generate_mapping(
            args.whitepaper,
            args.specs_dir,
            args.proofs_dir,
            args.output_dir
        )
        
        print(f"\n=== Theorem Mapping Generation Complete ===")
        print(f"Whitepaper Theorems: {report.total_whitepaper_theorems}")
        print(f"TLA+ Theorems: {report.total_tla_theorems}")
        print(f"Mapped Theorems: {report.mapped_theorems}")
        coverage = (report.mapped_theorems / report.total_whitepaper_theorems * 100) if report.total_whitepaper_theorems > 0 else 0
        print(f"Mapping Coverage: {coverage:.1f}%")
        print(f"Reports generated in: {args.output_dir}")
        
        return 0
        
    except Exception as e:
        logger.error(f"Error during theorem mapping generation: {e}")
        return 1

if __name__ == "__main__":
    exit(main())
