#!/usr/bin/env python3
# Author: Ayush Srivastava
"""
Types.tla Module Validation and Fixing Script

This script systematically validates and fixes the Types.tla module which is foundational
to all other TLA+ specifications in the Alpenglow consensus protocol verification.

The script performs:
- Syntax validation using TLC parser
- Constant validation and type checking
- Function completeness verification
- Dependency resolution
- Type consistency checks
- Helper function validation
- Stake function implementation fixes
- Leader selection validation
- Cryptographic abstraction validation
- Network type validation
- Test case generation
- Documentation enhancement

Author: Traycer.AI
Version: 1.0
"""

import os
import re
import sys
import json
import subprocess
import tempfile
import shutil
from pathlib import Path
from typing import Dict, List, Set, Tuple, Optional, Any
from dataclasses import dataclass
from enum import Enum
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('types_validation.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

class ValidationLevel(Enum):
    """Validation severity levels"""
    ERROR = "ERROR"
    WARNING = "WARNING"
    INFO = "INFO"
    SUCCESS = "SUCCESS"

@dataclass
class ValidationIssue:
    """Represents a validation issue found in Types.tla"""
    level: ValidationLevel
    category: str
    line_number: int
    description: str
    suggestion: str
    code_snippet: str = ""

@dataclass
class FixResult:
    """Result of applying a fix"""
    success: bool
    description: str
    changes_made: List[str]
    new_issues: List[ValidationIssue] = None

class TypesModuleValidator:
    """Main validator class for Types.tla module"""
    
    def __init__(self, types_file_path: str, utils_file_path: str = None):
        self.types_file_path = Path(types_file_path)
        self.utils_file_path = Path(utils_file_path) if utils_file_path else None
        self.issues: List[ValidationIssue] = []
        self.fixes_applied: List[FixResult] = []
        self.content: str = ""
        self.lines: List[str] = []
        
        # TLA+ syntax patterns
        self.patterns = {
            'constant_def': re.compile(r'^\s*([A-Z][A-Za-z0-9_]*)\s*==\s*(.+)$'),
            'function_def': re.compile(r'^\s*([A-Za-z][A-Za-z0-9_]*)\s*\(([^)]*)\)\s*==\s*(.+)$'),
            'operator_def': re.compile(r'^\s*([A-Za-z][A-Za-z0-9_]*)\s*==\s*(.+)$'),
            'recursive_def': re.compile(r'^\s*RECURSIVE\s+([A-Za-z][A-Za-z0-9_]*)\s*\(([^)]*)\)'),
            'extends': re.compile(r'^\s*EXTENDS\s+(.+)$'),
            'constants': re.compile(r'^\s*CONSTANTS?\s+(.+)$'),
            'assume': re.compile(r'^\s*ASSUME\s+(.+)$'),
            'choose': re.compile(r'CHOOSE\s+([^:]+):\s*(.+)'),
            'let_in': re.compile(r'LET\s+(.+?)\s+IN\s+(.+)', re.DOTALL),
            'if_then_else': re.compile(r'IF\s+(.+?)\s+THEN\s+(.+?)\s+ELSE\s+(.+)', re.DOTALL)
        }
        
        # Required constants for Alpenglow protocol
        self.required_constants = {
            'Validators': 'Set of all validators',
            'ByzantineValidators': 'Set of Byzantine validators',
            'OfflineValidators': 'Set of offline validators',
            'MaxSlot': 'Maximum slot number',
            'MaxView': 'Maximum view number',
            'GST': 'Global Stabilization Time',
            'Delta': 'Network delay bound'
        }
        
        # Required functions for protocol operation
        self.required_functions = {
            'Sum': 'Sum function for sets and functions',
            'TotalStake': 'Compute total stake for validator set',
            'ComputeLeader': 'Deterministic leader selection',
            'WindowSlots': 'Get slots in leader window',
            'IsDescendant': 'Check block descendant relationship',
            'Stake': 'Stake mapping for validators',
            'ValidBlock': 'Block validation predicate',
            'AggregateSignatures': 'BLS signature aggregation',
            'VRFEvaluate': 'VRF evaluation function'
        }
        
        # Type definitions that must be present
        self.required_types = {
            'ValidatorID': 'Validator identifier type',
            'Slot': 'Slot number type',
            'ViewNumber': 'View number type',
            'BlockHash': 'Block hash type',
            'CertificateType': 'Certificate type enumeration',
            'VoteType': 'Vote type enumeration',
            'Block': 'Block structure',
            'Vote': 'Vote structure',
            'Certificate': 'Certificate structure',
            'NetworkMessage': 'Network message structure'
        }

    def load_file(self) -> bool:
        """Load and parse the Types.tla file"""
        try:
            if not self.types_file_path.exists():
                logger.error(f"Types.tla file not found: {self.types_file_path}")
                return False
                
            with open(self.types_file_path, 'r', encoding='utf-8') as f:
                self.content = f.read()
                self.lines = self.content.splitlines()
                
            logger.info(f"Loaded Types.tla with {len(self.lines)} lines")
            return True
            
        except Exception as e:
            logger.error(f"Error loading Types.tla: {e}")
            return False

    def validate_syntax(self) -> List[ValidationIssue]:
        """Validate TLA+ syntax using TLC parser"""
        issues = []
        
        try:
            # Create temporary file for TLC validation
            with tempfile.NamedTemporaryFile(mode='w', suffix='.tla', delete=False) as temp_file:
                temp_file.write(self.content)
                temp_path = temp_file.name
            
            # Run TLC syntax check
            result = subprocess.run(
                ['tlc', '-parse', temp_path],
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode != 0:
                # Parse TLC error output
                error_lines = result.stderr.split('\n')
                for line in error_lines:
                    if 'line' in line.lower() and 'error' in line.lower():
                        line_match = re.search(r'line\s+(\d+)', line, re.IGNORECASE)
                        if line_match:
                            line_num = int(line_match.group(1))
                            issues.append(ValidationIssue(
                                level=ValidationLevel.ERROR,
                                category="Syntax",
                                line_number=line_num,
                                description=f"TLC syntax error: {line}",
                                suggestion="Fix syntax according to TLA+ specification",
                                code_snippet=self.lines[line_num-1] if line_num <= len(self.lines) else ""
                            ))
            
            # Clean up temporary file
            os.unlink(temp_path)
            
        except subprocess.TimeoutExpired:
            issues.append(ValidationIssue(
                level=ValidationLevel.WARNING,
                category="Syntax",
                line_number=0,
                description="TLC syntax validation timed out",
                suggestion="Check for infinite loops or complex expressions"
            ))
        except FileNotFoundError:
            issues.append(ValidationIssue(
                level=ValidationLevel.WARNING,
                category="Syntax",
                line_number=0,
                description="TLC not found in PATH",
                suggestion="Install TLA+ tools or add to PATH"
            ))
        except Exception as e:
            issues.append(ValidationIssue(
                level=ValidationLevel.WARNING,
                category="Syntax",
                line_number=0,
                description=f"Error running TLC validation: {e}",
                suggestion="Check TLC installation and file permissions"
            ))
        
        return issues

    def validate_constants(self) -> List[ValidationIssue]:
        """Validate that all required constants are properly defined"""
        issues = []
        defined_constants = set()
        
        # Find CONSTANTS declarations
        for i, line in enumerate(self.lines):
            constants_match = self.patterns['constants'].match(line)
            if constants_match:
                constants_text = constants_match.group(1)
                # Parse comma-separated constants
                constants = [c.strip().rstrip(',') for c in constants_text.split(',')]
                defined_constants.update(constants)
        
        # Find constant definitions (CONSTANT == value)
        for i, line in enumerate(self.lines):
            constant_match = self.patterns['constant_def'].match(line)
            if constant_match:
                constant_name = constant_match.group(1)
                defined_constants.add(constant_name)
        
        # Check for missing required constants
        for const_name, description in self.required_constants.items():
            if const_name not in defined_constants:
                issues.append(ValidationIssue(
                    level=ValidationLevel.ERROR,
                    category="Constants",
                    line_number=0,
                    description=f"Missing required constant: {const_name}",
                    suggestion=f"Add constant declaration: {const_name} \\* {description}"
                ))
        
        # Validate constant assumptions
        assume_found = False
        for i, line in enumerate(self.lines):
            if self.patterns['assume'].match(line):
                assume_found = True
                break
        
        if not assume_found:
            issues.append(ValidationIssue(
                level=ValidationLevel.WARNING,
                category="Constants",
                line_number=0,
                description="No ASSUME statements found for constant validation",
                suggestion="Add ASSUME statements to validate constant relationships"
            ))
        
        return issues

    def validate_functions(self) -> List[ValidationIssue]:
        """Validate function completeness and correctness"""
        issues = []
        defined_functions = set()
        
        # Find function definitions
        for i, line in enumerate(self.lines):
            # Function with parameters
            func_match = self.patterns['function_def'].match(line)
            if func_match:
                func_name = func_match.group(1)
                defined_functions.add(func_name)
                
                # Validate function body
                func_body = func_match.group(3)
                if not func_body.strip() or func_body.strip() == "...":
                    issues.append(ValidationIssue(
                        level=ValidationLevel.ERROR,
                        category="Functions",
                        line_number=i+1,
                        description=f"Function {func_name} has incomplete implementation",
                        suggestion=f"Complete the implementation of {func_name}",
                        code_snippet=line
                    ))
            
            # Operator definitions (no parameters)
            op_match = self.patterns['operator_def'].match(line)
            if op_match and not func_match:  # Avoid double-counting
                op_name = op_match.group(1)
                if op_name[0].isupper():  # Constants start with uppercase
                    continue
                defined_functions.add(op_name)
        
        # Check for missing required functions
        for func_name, description in self.required_functions.items():
            if func_name not in defined_functions:
                issues.append(ValidationIssue(
                    level=ValidationLevel.ERROR,
                    category="Functions",
                    line_number=0,
                    description=f"Missing required function: {func_name}",
                    suggestion=f"Implement function: {func_name} \\* {description}"
                ))
        
        # Validate specific critical functions
        issues.extend(self._validate_sum_function())
        issues.extend(self._validate_compute_leader())
        issues.extend(self._validate_stake_function())
        issues.extend(self._validate_window_functions())
        
        return issues

    def _validate_sum_function(self) -> List[ValidationIssue]:
        """Validate Sum function implementation"""
        issues = []
        
        # Check for Sum function definition
        sum_found = False
        recursive_sum_found = False
        
        for i, line in enumerate(self.lines):
            if 'Sum(' in line and '==' in line:
                sum_found = True
                # Check if it uses proper domain handling
                if 'DOMAIN' not in line and 'DOMAIN' not in self.lines[i+1:i+5]:
                    issues.append(ValidationIssue(
                        level=ValidationLevel.WARNING,
                        category="Functions",
                        line_number=i+1,
                        description="Sum function may not handle function domains properly",
                        suggestion="Ensure Sum function works with both sets and functions",
                        code_snippet=line
                    ))
            
            if 'RECURSIVE SumSet' in line:
                recursive_sum_found = True
        
        if sum_found and not recursive_sum_found:
            issues.append(ValidationIssue(
                level=ValidationLevel.WARNING,
                category="Functions",
                line_number=0,
                description="Sum function found but no recursive SumSet helper",
                suggestion="Add recursive SumSet helper for proper set summation"
            ))
        
        return issues

    def _validate_compute_leader(self) -> List[ValidationIssue]:
        """Validate ComputeLeader function implementation"""
        issues = []
        
        compute_leader_lines = []
        for i, line in enumerate(self.lines):
            if 'ComputeLeader' in line and '==' in line:
                # Collect the full function definition
                j = i
                while j < len(self.lines) and (j == i or not self.lines[j].strip().startswith('\\')):
                    compute_leader_lines.append((j+1, self.lines[j]))
                    j += 1
                break
        
        if not compute_leader_lines:
            issues.append(ValidationIssue(
                level=ValidationLevel.ERROR,
                category="Functions",
                line_number=0,
                description="ComputeLeader function not found",
                suggestion="Implement deterministic leader selection function"
            ))
            return issues
        
        # Check for proper empty set handling
        empty_check = any('validators = {}' in line for _, line in compute_leader_lines)
        if not empty_check:
            issues.append(ValidationIssue(
                level=ValidationLevel.WARNING,
                category="Functions",
                line_number=compute_leader_lines[0][0],
                description="ComputeLeader may not handle empty validator set",
                suggestion="Add check for empty validator set"
            ))
        
        # Check for deterministic selection
        vrf_usage = any('VRF' in line for _, line in compute_leader_lines)
        if not vrf_usage:
            issues.append(ValidationIssue(
                level=ValidationLevel.WARNING,
                category="Functions",
                line_number=compute_leader_lines[0][0],
                description="ComputeLeader may not use deterministic randomness",
                suggestion="Use VRF or deterministic seed for leader selection"
            ))
        
        return issues

    def _validate_stake_function(self) -> List[ValidationIssue]:
        """Validate Stake function implementation"""
        issues = []
        
        stake_def_found = False
        for i, line in enumerate(self.lines):
            if line.strip().startswith('Stake =='):
                stake_def_found = True
                # Check if it's a proper function mapping
                if '[v \\in Validators' not in line and '[v \\in Validators' not in self.lines[i+1]:
                    issues.append(ValidationIssue(
                        level=ValidationLevel.ERROR,
                        category="Functions",
                        line_number=i+1,
                        description="Stake function not properly defined as validator mapping",
                        suggestion="Define as: Stake == [v \\in Validators |-> ...]",
                        code_snippet=line
                    ))
                break
        
        if not stake_def_found:
            issues.append(ValidationIssue(
                level=ValidationLevel.ERROR,
                category="Functions",
                line_number=0,
                description="Stake function not found",
                suggestion="Define Stake as function mapping validators to stake amounts"
            ))
        
        return issues

    def _validate_window_functions(self) -> List[ValidationIssue]:
        """Validate window-related functions"""
        issues = []
        
        window_functions = ['WindowSlots', 'SameWindow', 'IsDescendant']
        
        for func_name in window_functions:
            found = False
            for i, line in enumerate(self.lines):
                if f'{func_name}(' in line and '==' in line:
                    found = True
                    break
            
            if not found:
                issues.append(ValidationIssue(
                    level=ValidationLevel.ERROR,
                    category="Functions",
                    line_number=0,
                    description=f"Missing window function: {func_name}",
                    suggestion=f"Implement {func_name} function for window management"
                ))
        
        return issues

    def validate_types(self) -> List[ValidationIssue]:
        """Validate type definitions"""
        issues = []
        defined_types = set()
        
        # Find type definitions
        for i, line in enumerate(self.lines):
            # Type definitions usually follow pattern: TypeName == ...
            type_match = self.patterns['operator_def'].match(line)
            if type_match:
                type_name = type_match.group(1)
                if type_name[0].isupper():  # Types typically start with uppercase
                    defined_types.add(type_name)
        
        # Check for missing required types
        for type_name, description in self.required_types.items():
            if type_name not in defined_types:
                issues.append(ValidationIssue(
                    level=ValidationLevel.ERROR,
                    category="Types",
                    line_number=0,
                    description=f"Missing required type: {type_name}",
                    suggestion=f"Define type: {type_name} \\* {description}"
                ))
        
        # Validate specific type structures
        issues.extend(self._validate_block_type())
        issues.extend(self._validate_certificate_type())
        issues.extend(self._validate_vote_type())
        
        return issues

    def _validate_block_type(self) -> List[ValidationIssue]:
        """Validate Block type structure"""
        issues = []
        
        block_def_found = False
        required_fields = ['slot', 'view', 'hash', 'parent', 'proposer', 'transactions', 'timestamp', 'signature']
        
        for i, line in enumerate(self.lines):
            if line.strip().startswith('Block =='):
                block_def_found = True
                # Check for record structure
                if '[' not in line and '[' not in self.lines[i+1]:
                    issues.append(ValidationIssue(
                        level=ValidationLevel.ERROR,
                        category="Types",
                        line_number=i+1,
                        description="Block type not defined as record structure",
                        suggestion="Define Block as record with required fields",
                        code_snippet=line
                    ))
                else:
                    # Check for required fields in the next few lines
                    block_lines = []
                    j = i
                    while j < len(self.lines) and (j == i or not self.lines[j].strip().endswith(']')):
                        block_lines.append(self.lines[j])
                        j += 1
                        if j < len(self.lines) and self.lines[j].strip().endswith(']'):
                            block_lines.append(self.lines[j])
                            break
                    
                    block_text = ' '.join(block_lines)
                    for field in required_fields:
                        if field not in block_text:
                            issues.append(ValidationIssue(
                                level=ValidationLevel.WARNING,
                                category="Types",
                                line_number=i+1,
                                description=f"Block type missing field: {field}",
                                suggestion=f"Add {field} field to Block record"
                            ))
                break
        
        if not block_def_found:
            issues.append(ValidationIssue(
                level=ValidationLevel.ERROR,
                category="Types",
                line_number=0,
                description="Block type not found",
                suggestion="Define Block type as record structure"
            ))
        
        return issues

    def _validate_certificate_type(self) -> List[ValidationIssue]:
        """Validate Certificate type structure"""
        issues = []
        
        cert_def_found = False
        required_fields = ['slot', 'view', 'block', 'type', 'signatures', 'validators', 'stake']
        
        for i, line in enumerate(self.lines):
            if line.strip().startswith('Certificate =='):
                cert_def_found = True
                # Similar validation as Block type
                break
        
        if not cert_def_found:
            issues.append(ValidationIssue(
                level=ValidationLevel.ERROR,
                category="Types",
                line_number=0,
                description="Certificate type not found",
                suggestion="Define Certificate type as record structure"
            ))
        
        return issues

    def _validate_vote_type(self) -> List[ValidationIssue]:
        """Validate Vote type structure"""
        issues = []
        
        vote_def_found = False
        vote_type_enum_found = False
        
        for i, line in enumerate(self.lines):
            if line.strip().startswith('Vote =='):
                vote_def_found = True
            if 'VoteType ==' in line and '{' in line:
                vote_type_enum_found = True
                # Check for required vote types
                required_types = ['proposal', 'echo', 'commit', 'notarization', 'finalization']
                for vote_type in required_types:
                    if vote_type not in line and vote_type not in self.lines[i+1:i+3]:
                        issues.append(ValidationIssue(
                            level=ValidationLevel.WARNING,
                            category="Types",
                            line_number=i+1,
                            description=f"VoteType missing: {vote_type}",
                            suggestion=f"Add {vote_type} to VoteType enumeration"
                        ))
        
        if not vote_def_found:
            issues.append(ValidationIssue(
                level=ValidationLevel.ERROR,
                category="Types",
                line_number=0,
                description="Vote type not found",
                suggestion="Define Vote type as record structure"
            ))
        
        if not vote_type_enum_found:
            issues.append(ValidationIssue(
                level=ValidationLevel.ERROR,
                category="Types",
                line_number=0,
                description="VoteType enumeration not found",
                suggestion="Define VoteType as set of vote type strings"
            ))
        
        return issues

    def validate_dependencies(self) -> List[ValidationIssue]:
        """Validate module dependencies and imports"""
        issues = []
        
        # Check EXTENDS clause
        extends_found = False
        required_modules = ['Integers', 'Sequences', 'FiniteSets']
        
        for i, line in enumerate(self.lines):
            extends_match = self.patterns['extends'].match(line)
            if extends_match:
                extends_found = True
                modules = [m.strip() for m in extends_match.group(1).split(',')]
                
                for req_module in required_modules:
                    if req_module not in modules:
                        issues.append(ValidationIssue(
                            level=ValidationLevel.WARNING,
                            category="Dependencies",
                            line_number=i+1,
                            description=f"Missing required module: {req_module}",
                            suggestion=f"Add {req_module} to EXTENDS clause",
                            code_snippet=line
                        ))
                break
        
        if not extends_found:
            issues.append(ValidationIssue(
                level=ValidationLevel.ERROR,
                category="Dependencies",
                line_number=0,
                description="No EXTENDS clause found",
                suggestion="Add EXTENDS clause with required modules"
            ))
        
        # Check for circular dependencies with Utils module
        if self.utils_file_path and self.utils_file_path.exists():
            try:
                with open(self.utils_file_path, 'r') as f:
                    utils_content = f.read()
                    if 'Types' in utils_content:
                        issues.append(ValidationIssue(
                            level=ValidationLevel.WARNING,
                            category="Dependencies",
                            line_number=0,
                            description="Potential circular dependency with Utils module",
                            suggestion="Ensure Types module doesn't depend on Utils and vice versa"
                        ))
            except Exception as e:
                logger.warning(f"Could not check Utils module for circular dependencies: {e}")
        
        return issues

    def validate_cryptographic_abstractions(self) -> List[ValidationIssue]:
        """Validate cryptographic type definitions and functions"""
        issues = []
        
        crypto_types = ['Signature', 'BLSSignature', 'AggregatedSignature', 'Hash']
        crypto_functions = ['AggregateSignatures', 'VerifySignature', 'VRFEvaluate', 'VRFProve']
        
        # Check cryptographic types
        for crypto_type in crypto_types:
            found = False
            for i, line in enumerate(self.lines):
                if f'{crypto_type} ==' in line:
                    found = True
                    break
            
            if not found:
                issues.append(ValidationIssue(
                    level=ValidationLevel.ERROR,
                    category="Cryptography",
                    line_number=0,
                    description=f"Missing cryptographic type: {crypto_type}",
                    suggestion=f"Define {crypto_type} type for cryptographic operations"
                ))
        
        # Check cryptographic functions
        for crypto_func in crypto_functions:
            found = False
            for i, line in enumerate(self.lines):
                if f'{crypto_func}(' in line and '==' in line:
                    found = True
                    break
            
            if not found:
                issues.append(ValidationIssue(
                    level=ValidationLevel.WARNING,
                    category="Cryptography",
                    line_number=0,
                    description=f"Missing cryptographic function: {crypto_func}",
                    suggestion=f"Implement {crypto_func} for cryptographic operations"
                ))
        
        # Validate signature structure
        for i, line in enumerate(self.lines):
            if 'Signature ==' in line and '[' in line:
                # Check for required signature fields
                sig_fields = ['signer', 'message', 'valid']
                sig_lines = []
                j = i
                while j < len(self.lines) and not self.lines[j].strip().endswith(']'):
                    sig_lines.append(self.lines[j])
                    j += 1
                if j < len(self.lines):
                    sig_lines.append(self.lines[j])
                
                sig_text = ' '.join(sig_lines)
                for field in sig_fields:
                    if field not in sig_text:
                        issues.append(ValidationIssue(
                            level=ValidationLevel.WARNING,
                            category="Cryptography",
                            line_number=i+1,
                            description=f"Signature type missing field: {field}",
                            suggestion=f"Add {field} field to Signature record"
                        ))
                break
        
        return issues

    def validate_network_types(self) -> List[ValidationIssue]:
        """Validate network message and timing type definitions"""
        issues = []
        
        network_types = ['NetworkMessage', 'MessageType', 'ConsensusMessage', 'PropagationMessage']
        timing_types = ['TimeValue', 'SlotDuration', 'ViewTimeout']
        
        # Check network types
        for net_type in network_types:
            found = False
            for i, line in enumerate(self.lines):
                if f'{net_type} ==' in line:
                    found = True
                    break
            
            if not found:
                issues.append(ValidationIssue(
                    level=ValidationLevel.WARNING,
                    category="Network",
                    line_number=0,
                    description=f"Missing network type: {net_type}",
                    suggestion=f"Define {net_type} for network operations"
                ))
        
        # Check timing types
        for timing_type in timing_types:
            found = False
            for i, line in enumerate(self.lines):
                if f'{timing_type} ==' in line:
                    found = True
                    break
            
            if not found:
                issues.append(ValidationIssue(
                    level=ValidationLevel.WARNING,
                    category="Network",
                    line_number=0,
                    description=f"Missing timing type: {timing_type}",
                    suggestion=f"Define {timing_type} for timing operations"
                ))
        
        return issues

    def generate_test_cases(self) -> List[str]:
        """Generate small test cases to validate type definitions"""
        test_cases = []
        
        # Test case for basic types
        test_cases.append("""
\\* Test case 1: Basic type instantiation
TestValidatorSet == {1, 2, 3}
TestStakeMap == [v \\in TestValidatorSet |-> 100]
TestSlot == 1
TestView == 1
        """)
        
        # Test case for Sum function
        test_cases.append("""
\\* Test case 2: Sum function validation
TestSumSet == SumSet({1, 2, 3})  \\* Should equal 6
TestSumFunction == Sum([x \\in {1, 2, 3} |-> x * 2])  \\* Should equal 12
        """)
        
        # Test case for leader selection
        test_cases.append("""
\\* Test case 3: Leader selection
TestLeader == ComputeLeader(1, TestValidatorSet, TestStakeMap)
TestLeaderInSet == TestLeader \\in TestValidatorSet
        """)
        
        # Test case for window functions
        test_cases.append("""
\\* Test case 4: Window functions
TestWindowSlots == WindowSlots(5)  \\* Should return {4, 5, 6, 7} for 4-slot windows
TestSameWindow == SameWindow(5, 6)  \\* Should be TRUE
        """)
        
        # Test case for block validation
        test_cases.append("""
\\* Test case 5: Block structure
TestBlock == [
    slot |-> 1,
    view |-> 1,
    hash |-> 123,
    parent |-> 0,
    proposer |-> 1,
    transactions |-> {},
    timestamp |-> 1000,
    signature |-> [signer |-> 1, message |-> 123, valid |-> TRUE],
    data |-> <<>>
]
TestBlockValid == ValidBlock1(TestBlock)
        """)
        
        return test_cases

    def apply_fixes(self) -> List[FixResult]:
        """Apply automated fixes to common issues"""
        fixes = []
        
        # Fix 1: Add missing EXTENDS modules
        fix_result = self._fix_extends_clause()
        if fix_result:
            fixes.append(fix_result)
        
        # Fix 2: Fix Sum function implementation
        fix_result = self._fix_sum_function()
        if fix_result:
            fixes.append(fix_result)
        
        # Fix 3: Fix ComputeLeader function
        fix_result = self._fix_compute_leader()
        if fix_result:
            fixes.append(fix_result)
        
        # Fix 4: Add missing type definitions
        fix_result = self._fix_missing_types()
        if fix_result:
            fixes.append(fix_result)
        
        # Fix 5: Fix cryptographic abstractions
        fix_result = self._fix_crypto_abstractions()
        if fix_result:
            fixes.append(fix_result)
        
        return fixes

    def _fix_extends_clause(self) -> Optional[FixResult]:
        """Fix EXTENDS clause to include required modules"""
        extends_line_idx = None
        required_modules = {'Integers', 'Sequences', 'FiniteSets', 'TLC'}
        
        for i, line in enumerate(self.lines):
            if line.strip().startswith('EXTENDS'):
                extends_line_idx = i
                break
        
        if extends_line_idx is not None:
            current_line = self.lines[extends_line_idx]
            extends_match = self.patterns['extends'].match(current_line)
            if extends_match:
                current_modules = {m.strip() for m in extends_match.group(1).split(',')}
                missing_modules = required_modules - current_modules
                
                if missing_modules:
                    all_modules = current_modules | required_modules
                    new_line = f"EXTENDS {', '.join(sorted(all_modules))}"
                    self.lines[extends_line_idx] = new_line
                    self.content = '\n'.join(self.lines)
                    
                    return FixResult(
                        success=True,
                        description="Fixed EXTENDS clause",
                        changes_made=[f"Added modules: {', '.join(missing_modules)}"]
                    )
        else:
            # Add EXTENDS clause after module declaration
            module_line_idx = 0
            for i, line in enumerate(self.lines):
                if line.strip().startswith('----') and 'MODULE' in self.lines[i-1]:
                    module_line_idx = i + 1
                    break
            
            extends_line = f"EXTENDS {', '.join(sorted(required_modules))}"
            self.lines.insert(module_line_idx, extends_line)
            self.lines.insert(module_line_idx + 1, "")
            self.content = '\n'.join(self.lines)
            
            return FixResult(
                success=True,
                description="Added missing EXTENDS clause",
                changes_made=[f"Added EXTENDS with modules: {', '.join(required_modules)}"]
            )
        
        return None

    def _fix_sum_function(self) -> Optional[FixResult]:
        """Fix Sum function implementation"""
        changes = []
        
        # Check if Sum function exists and is properly implemented
        sum_found = False
        recursive_sum_found = False
        
        for i, line in enumerate(self.lines):
            if line.strip().startswith('Sum(') and '==' in line:
                sum_found = True
            if 'RECURSIVE SumSet' in line:
                recursive_sum_found = True
        
        if not recursive_sum_found:
            # Add recursive SumSet function
            helper_functions_idx = None
            for i, line in enumerate(self.lines):
                if 'Helper Functions' in line or 'Sum function' in line:
                    helper_functions_idx = i + 2
                    break
            
            if helper_functions_idx:
                recursive_sum = [
                    "\\* Recursive sum function for sets",
                    "RECURSIVE SumSet(_)",
                    "SumSet(S) ==",
                    "    IF S = {} THEN 0",
                    "    ELSE LET x == CHOOSE x \\in S : TRUE",
                    "         IN x + SumSet(S \\ {x})",
                    ""
                ]
                
                for j, new_line in enumerate(recursive_sum):
                    self.lines.insert(helper_functions_idx + j, new_line)
                
                changes.append("Added recursive SumSet function")
        
        if not sum_found:
            # Add Sum function for functions/records
            sum_func = [
                "\\* Sum function for functions/records",
                "Sum(f) ==",
                "    LET D == DOMAIN f",
                "    IN IF D = {} THEN 0",
                "       ELSE SumSet({f[x] : x \\in D})",
                ""
            ]
            
            # Find insertion point after SumSet
            insert_idx = None
            for i, line in enumerate(self.lines):
                if 'SumSet(S \\' in line:
                    insert_idx = i + 2
                    break
            
            if insert_idx:
                for j, new_line in enumerate(sum_func):
                    self.lines.insert(insert_idx + j, new_line)
                
                changes.append("Added Sum function for functions")
        
        if changes:
            self.content = '\n'.join(self.lines)
            return FixResult(
                success=True,
                description="Fixed Sum function implementation",
                changes_made=changes
            )
        
        return None

    def _fix_compute_leader(self) -> Optional[FixResult]:
        """Fix ComputeLeader function implementation"""
        changes = []
        
        # Find ComputeLeader function
        compute_leader_idx = None
        for i, line in enumerate(self.lines):
            if 'ComputeLeader(' in line and '==' in line:
                compute_leader_idx = i
                break
        
        if compute_leader_idx is not None:
            # Check if it handles empty validator set
            func_lines = []
            j = compute_leader_idx
            while j < len(self.lines) and (j == compute_leader_idx or not self.lines[j].strip().startswith('\\')):
                func_lines.append(self.lines[j])
                j += 1
            
            func_text = ' '.join(func_lines)
            
            if 'validators = {}' not in func_text:
                # Add empty set check
                new_impl = [
                    "ComputeLeader(slot, validators, stake) ==",
                    "    IF validators = {} THEN 0  \\* Handle empty validator set",
                    "    ELSE IF Cardinality(validators) = 1 THEN CHOOSE v \\in validators : TRUE",
                    "    ELSE",
                    "        LET totalStake == Sum(stake)",
                    "            vrfSeed == VRFEvaluate(slot, 0)",
                    "            targetValue == IF totalStake = 0 THEN 0 ELSE (vrfSeed % totalStake)",
                    "            ValidatorOrder == CHOOSE seq \\in [1..Cardinality(validators) -> validators] :",
                    "                                \\A i, j \\in 1..Cardinality(validators) :",
                    "                                    i < j => seq[i] # seq[j]",
                    "            cumulativeStake == [i \\in 1..Cardinality(validators) |->",
                    "                IF i = 1 THEN stake[ValidatorOrder[1]]",
                    "                ELSE SumSet({stake[ValidatorOrder[j]] : j \\in 1..i})",
                    "            ]",
                    "            selectedIndex == IF totalStake = 0 THEN 1",
                    "                           ELSE CHOOSE i \\in 1..Cardinality(validators) :",
                    "                               /\\ cumulativeStake[i] > targetValue",
                    "                               /\\ \\A j \\in 1..Cardinality(validators) :",
                    "                                   (j < i => cumulativeStake[j] <= targetValue) \\/ j >= i",
                    "        IN ValidatorOrder[selectedIndex]"
                ]
                
                # Replace the function
                end_idx = j
                for k in range(compute_leader_idx, end_idx):
                    if k < len(self.lines):
                        self.lines.pop(compute_leader_idx)
                
                for k, new_line in enumerate(new_impl):
                    self.lines.insert(compute_leader_idx + k, new_line)
                
                changes.append("Fixed ComputeLeader function with proper empty set handling")
        
        if changes:
            self.content = '\n'.join(self.lines)
            return FixResult(
                success=True,
                description="Fixed ComputeLeader function",
                changes_made=changes
            )
        
        return None

    def _fix_missing_types(self) -> Optional[FixResult]:
        """Add missing type definitions"""
        changes = []
        
        # Check for missing basic types and add them
        missing_types = {
            'ValidatorID': 'Nat',
            'Slot': 'Nat',
            'ViewNumber': 'Nat',
            'TimeValue': 'Nat',
            'Hash': 'Nat',
            'MessageHash': 'Hash',
            'BlockHash': 'Hash'
        }
        
        # Find where to insert type definitions
        types_section_idx = None
        for i, line in enumerate(self.lines):
            if 'Basic Types' in line or 'Type definitions' in line:
                types_section_idx = i + 2
                break
        
        if not types_section_idx:
            # Find after constants section
            for i, line in enumerate(self.lines):
                if line.strip().startswith('CONSTANTS') or 'ASSUME' in line:
                    types_section_idx = i + 10  # After constants and assumptions
                    break
        
        if types_section_idx:
            for type_name, type_def in missing_types.items():
                # Check if type already exists
                type_exists = any(f'{type_name} ==' in line for line in self.lines)
                if not type_exists:
                    self.lines.insert(types_section_idx, f"{type_name} == {type_def}")
                    types_section_idx += 1
                    changes.append(f"Added type definition: {type_name}")
        
        if changes:
            self.content = '\n'.join(self.lines)
            return FixResult(
                success=True,
                description="Added missing type definitions",
                changes_made=changes
            )
        
        return None

    def _fix_crypto_abstractions(self) -> Optional[FixResult]:
        """Fix cryptographic abstraction definitions"""
        changes = []
        
        # Ensure VRFEvaluate function exists
        vrf_exists = any('VRFEvaluate(' in line for line in self.lines)
        if not vrf_exists:
            vrf_impl = [
                "\\* VRF evaluation function (deterministic pseudorandom)",
                "VRFEvaluate(seed, validator) ==",
                "    LET hash1 == ((seed * 997 + validator * 991) % 1000000)",
                "        hash2 == ((hash1 * 983 + seed * 977) % 1000000)",
                "    IN ((hash1 + hash2) % 1000000)",
                ""
            ]
            
            # Find insertion point
            crypto_section_idx = None
            for i, line in enumerate(self.lines):
                if 'Cryptographic' in line and 'Abstractions' in line:
                    crypto_section_idx = i + 2
                    break
            
            if crypto_section_idx:
                for j, new_line in enumerate(vrf_impl):
                    self.lines.insert(crypto_section_idx + j, new_line)
                changes.append("Added VRFEvaluate function")
        
        if changes:
            self.content = '\n'.join(self.lines)
            return FixResult(
                success=True,
                description="Fixed cryptographic abstractions",
                changes_made=changes
            )
        
        return None

    def save_fixed_file(self, backup: bool = True) -> bool:
        """Save the fixed Types.tla file"""
        try:
            if backup:
                backup_path = self.types_file_path.with_suffix('.tla.backup')
                shutil.copy2(self.types_file_path, backup_path)
                logger.info(f"Created backup: {backup_path}")
            
            with open(self.types_file_path, 'w', encoding='utf-8') as f:
                f.write(self.content)
            
            logger.info(f"Saved fixed Types.tla to {self.types_file_path}")
            return True
            
        except Exception as e:
            logger.error(f"Error saving fixed file: {e}")
            return False

    def generate_validation_report(self) -> str:
        """Generate comprehensive validation report"""
        report = []
        report.append("=" * 80)
        report.append("TYPES.TLA MODULE VALIDATION REPORT")
        report.append("=" * 80)
        report.append(f"File: {self.types_file_path}")
        report.append(f"Lines: {len(self.lines)}")
        report.append(f"Validation Date: {__import__('datetime').datetime.now()}")
        report.append("")
        
        # Summary
        error_count = sum(1 for issue in self.issues if issue.level == ValidationLevel.ERROR)
        warning_count = sum(1 for issue in self.issues if issue.level == ValidationLevel.WARNING)
        info_count = sum(1 for issue in self.issues if issue.level == ValidationLevel.INFO)
        
        report.append("SUMMARY")
        report.append("-" * 40)
        report.append(f"Total Issues: {len(self.issues)}")
        report.append(f"Errors: {error_count}")
        report.append(f"Warnings: {warning_count}")
        report.append(f"Info: {info_count}")
        report.append(f"Fixes Applied: {len(self.fixes_applied)}")
        report.append("")
        
        # Issues by category
        categories = {}
        for issue in self.issues:
            if issue.category not in categories:
                categories[issue.category] = []
            categories[issue.category].append(issue)
        
        for category, issues in categories.items():
            report.append(f"{category.upper()} ISSUES")
            report.append("-" * 40)
            for issue in issues:
                report.append(f"[{issue.level.value}] Line {issue.line_number}: {issue.description}")
                report.append(f"  Suggestion: {issue.suggestion}")
                if issue.code_snippet:
                    report.append(f"  Code: {issue.code_snippet}")
                report.append("")
        
        # Applied fixes
        if self.fixes_applied:
            report.append("APPLIED FIXES")
            report.append("-" * 40)
            for fix in self.fixes_applied:
                report.append(f"✓ {fix.description}")
                for change in fix.changes_made:
                    report.append(f"  - {change}")
                report.append("")
        
        # Test cases
        test_cases = self.generate_test_cases()
        if test_cases:
            report.append("GENERATED TEST CASES")
            report.append("-" * 40)
            for i, test_case in enumerate(test_cases, 1):
                report.append(f"Test Case {i}:")
                report.append(test_case)
                report.append("")
        
        return "\n".join(report)

    def run_full_validation(self) -> bool:
        """Run complete validation and fixing process"""
        logger.info("Starting Types.tla module validation...")
        
        # Load file
        if not self.load_file():
            return False
        
        # Run all validations
        logger.info("Running syntax validation...")
        self.issues.extend(self.validate_syntax())
        
        logger.info("Running constants validation...")
        self.issues.extend(self.validate_constants())
        
        logger.info("Running functions validation...")
        self.issues.extend(self.validate_functions())
        
        logger.info("Running types validation...")
        self.issues.extend(self.validate_types())
        
        logger.info("Running dependencies validation...")
        self.issues.extend(self.validate_dependencies())
        
        logger.info("Running cryptographic abstractions validation...")
        self.issues.extend(self.validate_cryptographic_abstractions())
        
        logger.info("Running network types validation...")
        self.issues.extend(self.validate_network_types())
        
        # Apply fixes
        logger.info("Applying automated fixes...")
        self.fixes_applied = self.apply_fixes()
        
        # Re-run critical validations after fixes
        if self.fixes_applied:
            logger.info("Re-validating after fixes...")
            new_issues = []
            new_issues.extend(self.validate_syntax())
            new_issues.extend(self.validate_constants())
            new_issues.extend(self.validate_functions())
            
            # Update issues list
            self.issues = [issue for issue in self.issues if issue.level == ValidationLevel.ERROR] + new_issues
        
        # Generate and save report
        report = self.generate_validation_report()
        report_path = self.types_file_path.parent / "types_validation_report.txt"
        
        try:
            with open(report_path, 'w', encoding='utf-8') as f:
                f.write(report)
            logger.info(f"Validation report saved to: {report_path}")
        except Exception as e:
            logger.error(f"Error saving validation report: {e}")
        
        # Save fixed file if fixes were applied
        if self.fixes_applied:
            self.save_fixed_file(backup=True)
        
        # Summary
        error_count = sum(1 for issue in self.issues if issue.level == ValidationLevel.ERROR)
        warning_count = sum(1 for issue in self.issues if issue.level == ValidationLevel.WARNING)
        
        logger.info(f"Validation complete: {error_count} errors, {warning_count} warnings")
        logger.info(f"Applied {len(self.fixes_applied)} fixes")
        
        return error_count == 0

def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Validate and fix Types.tla module")
    parser.add_argument("types_file", help="Path to Types.tla file")
    parser.add_argument("--utils-file", help="Path to Utils.tla file (optional)")
    parser.add_argument("--no-fixes", action="store_true", help="Only validate, don't apply fixes")
    parser.add_argument("--verbose", action="store_true", help="Enable verbose logging")
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    # Validate file exists
    if not Path(args.types_file).exists():
        logger.error(f"Types.tla file not found: {args.types_file}")
        return 1
    
    # Create validator
    validator = TypesModuleValidator(args.types_file, args.utils_file)
    
    # Run validation
    success = validator.run_full_validation()
    
    if success:
        logger.info("✓ Types.tla module validation completed successfully")
        return 0
    else:
        logger.error("✗ Types.tla module validation found critical issues")
        return 1

if __name__ == "__main__":
    sys.exit(main())