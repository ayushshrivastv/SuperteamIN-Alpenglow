#!/usr/bin/env python3

"""
Implementation Trace Translator

Converts real Alpenglow implementation traces to TLA+ format for conformance verification.
"""

import json
import argparse
import os
from pathlib import Path
from typing import Dict, List, Any
from datetime import datetime

class TraceTranslator:
    def __init__(self, input_dir: str, output_dir: str):
        self.input_dir = Path(input_dir)
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
    def translate_traces(self) -> bool:
        """Translate all traces from input directory to TLA+ format."""
        print(f"Translating traces from {self.input_dir} to {self.output_dir}")
        
        success_count = 0
        total_count = 0
        
        # Process each scenario directory
        for scenario_dir in self.input_dir.iterdir():
            if not scenario_dir.is_dir():
                continue
                
            print(f"Processing scenario: {scenario_dir.name}")
            
            # Collect all validator traces for this scenario
            validator_traces = []
            for trace_file in scenario_dir.glob("*.json"):
                try:
                    with open(trace_file, 'r') as f:
                        trace_data = json.load(f)
                        validator_traces.append(trace_data)
                        total_count += 1
                except Exception as e:
                    print(f"Error reading {trace_file}: {e}")
                    continue
            
            # Translate scenario traces to TLA+ format
            if validator_traces:
                tla_trace = self._translate_scenario(scenario_dir.name, validator_traces)
                output_file = self.output_dir / f"{scenario_dir.name}.tla"
                
                try:
                    with open(output_file, 'w') as f:
                        f.write(tla_trace)
                    print(f"Generated TLA+ trace: {output_file}")
                    success_count += len(validator_traces)
                except Exception as e:
                    print(f"Error writing {output_file}: {e}")
        
        print(f"Translation completed: {success_count}/{total_count} traces successful")
        return success_count == total_count
    
    def _translate_scenario(self, scenario_name: str, validator_traces: List[Dict]) -> str:
        """Translate a scenario's validator traces to TLA+ format."""
        
        # Extract events and sort by timestamp
        all_events = []
        for trace in validator_traces:
            validator_id = trace.get('validator_id', 'unknown')
            for event in trace.get('events', []):
                event['validator_id'] = validator_id
                all_events.append(event)
        
        # Sort events by timestamp
        all_events.sort(key=lambda x: x.get('timestamp', 0))
        
        # Generate TLA+ trace specification
        tla_content = f'''---------------------------- MODULE {scenario_name}_trace ----------------------------
(*
 * Translated execution trace for scenario: {scenario_name}
 * Generated on: {datetime.now().isoformat()}
 * Source: Real Alpenglow implementation traces
 *)

EXTENDS Integers, Sequences, FiniteSets
INSTANCE Alpenglow

CONSTANTS TraceLength
ASSUME TraceLength = {len(all_events)}

VARIABLES traceStep

TraceInit == traceStep = 0

TraceNext ==
    \\/ /\\ traceStep < TraceLength
       /\\ traceStep' = traceStep + 1
       /\\ CASE traceStep = 0 -> {self._translate_event(all_events[0] if all_events else {})}
'''
        
        # Add each event as a case
        for i, event in enumerate(all_events[1:], 1):
            tla_content += f'''            [] traceStep = {i} -> {self._translate_event(event)}
'''
        
        tla_content += '''            [] OTHER -> FALSE
    \\/ /\\ traceStep = TraceLength
       /\\ UNCHANGED <<traceStep>>

TraceSpec == TraceInit /\\ [][TraceNext]_<<traceStep>>

(*
 * Conformance properties - these should hold for valid implementation traces
 *)
ConformanceInvariant ==
    /\\ TypeOK
    /\\ Safety
    /\\ ChainConsistency

ConformanceLiveness ==
    /\\ Progress
    /\\ EventualFinalization

=============================================================================
'''
        
        return tla_content
    
    def _translate_event(self, event: Dict[str, Any]) -> str:
        """Translate a single event to TLA+ action."""
        event_type = event.get('type', 'unknown')
        validator_id = event.get('validator_id', 'unknown')
        
        if event_type == 'consensus_start':
            slot = event.get('slot', 1)
            view = event.get('view', 1)
            return f'''StartConsensus({validator_id}, {slot}, {view})'''
            
        elif event_type == 'vote_cast':
            slot = event.get('slot', 1)
            view = event.get('view', 1)
            block_hash = event.get('block_hash', '"unknown"')
            return f'''CastVote({validator_id}, {slot}, {view}, {block_hash})'''
            
        elif event_type == 'certificate_generated':
            slot = event.get('slot', 1)
            view = event.get('view', 1)
            cert_type = event.get('certificate_type', 'fast')
            return f'''GenerateCertificate({validator_id}, {slot}, {view}, "{cert_type}")'''
            
        else:
            return f'''UnknownEvent({validator_id}, "{event_type}")'''

def main():
    parser = argparse.ArgumentParser(description='Translate implementation traces to TLA+ format')
    parser.add_argument('--input', required=True, help='Input directory containing implementation traces')
    parser.add_argument('--output', required=True, help='Output directory for TLA+ traces')
    parser.add_argument('--verbose', action='store_true', help='Enable verbose output')
    
    args = parser.parse_args()
    
    if args.verbose:
        print(f"Input directory: {args.input}")
        print(f"Output directory: {args.output}")
    
    translator = TraceTranslator(args.input, args.output)
    
    if translator.translate_traces():
        print("✓ All traces translated successfully")
        exit(0)
    else:
        print("✗ Some traces failed to translate")
        exit(1)

if __name__ == '__main__':
    main()
