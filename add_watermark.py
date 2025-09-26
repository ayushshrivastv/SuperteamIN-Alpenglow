#!/usr/bin/env python3
"""
Watermark Addition Script
Author: Ayush Srivastava
"""

import os
import re
from pathlib import Path
from typing import Dict, List

def get_watermark_for_file_type(file_extension: str) -> str:
    """Generate appropriate watermark comment for different file types"""
    
    watermarks = {
        '.py': '# Author: Ayush Srivastava\n',
        '.sh': '# Author: Ayush Srivastava\n',
        '.tla': '\\* Author: Ayush Srivastava\n',
        '.cfg': '\\* Author: Ayush Srivastava\n',
        '.md': '<!-- Author: Ayush Srivastava -->\n',
        '.dockerfile': '# Author: Ayush Srivastava\n',
        '.yml': '# Author: Ayush Srivastava\n',
        '.yaml': '# Author: Ayush Srivastava\n',
        '.json': '',  # JSON doesn't support comments
        '.csv': '',   # CSV doesn't support comments
        '.html': '<!-- Author: Ayush Srivastava -->\n',
        '.rs': '// Author: Ayush Srivastava\n',
        '.toml': '# Author: Ayush Srivastava\n'
    }
    
    return watermarks.get(file_extension.lower(), f'# Author: Ayush Srivastava\n')

def has_watermark(content: str) -> bool:
    """Check if file already has the watermark"""
    return 'Ayush Srivastava' in content

def add_watermark_to_file(file_path: Path) -> bool:
    """Add watermark to a single file"""
    try:
        # Skip binary files and certain directories
        skip_dirs = {'.git', '__pycache__', 'node_modules', '.pytest_cache', 'target'}
        if any(part in skip_dirs for part in file_path.parts):
            return False
            
        # Skip binary file extensions
        skip_extensions = {'.jar', '.png', '.jpg', '.jpeg', '.gif', '.pdf', '.zip', '.tar', '.gz'}
        if file_path.suffix.lower() in skip_extensions:
            return False
            
        # Read file content
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
        except UnicodeDecodeError:
            print(f"Skipping binary file: {file_path}")
            return False
            
        # Check if watermark already exists
        if has_watermark(content):
            print(f"Watermark already exists: {file_path}")
            return False
            
        # Get appropriate watermark
        watermark = get_watermark_for_file_type(file_path.suffix)
        if not watermark:
            print(f"No watermark format for: {file_path}")
            return False
            
        # Handle special cases
        new_content = content
        
        if file_path.suffix == '.py':
            # Add after shebang if present
            if content.startswith('#!'):
                lines = content.split('\n')
                shebang = lines[0]
                rest = '\n'.join(lines[1:])
                new_content = f"{shebang}\n{watermark}{rest}"
            else:
                new_content = f"{watermark}{content}"
                
        elif file_path.suffix == '.sh':
            # Add after shebang if present
            if content.startswith('#!'):
                lines = content.split('\n')
                shebang = lines[0]
                rest = '\n'.join(lines[1:])
                new_content = f"{shebang}\n{watermark}{rest}"
            else:
                new_content = f"{watermark}{content}"
                
        elif file_path.suffix in ['.tla', '.cfg']:
            # Add at the beginning for TLA+ files
            new_content = f"{watermark}{content}"
            
        elif file_path.suffix == '.md':
            # Add at the beginning for Markdown files
            new_content = f"{watermark}\n{content}"
            
        else:
            # Default: add at beginning
            new_content = f"{watermark}{content}"
        
        # Write updated content
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(new_content)
            
        print(f"Added watermark to: {file_path}")
        return True
        
    except Exception as e:
        print(f"Error processing {file_path}: {e}")
        return False

def main():
    """Main function to add watermarks to all files"""
    project_root = Path('.')
    
    # Get all files in the project
    all_files = []
    for file_path in project_root.rglob('*'):
        if file_path.is_file():
            all_files.append(file_path)
    
    print(f"Found {len(all_files)} files in project")
    
    # Process each file
    processed_count = 0
    skipped_count = 0
    
    for file_path in all_files:
        if add_watermark_to_file(file_path):
            processed_count += 1
        else:
            skipped_count += 1
    
    print(f"\nWatermark addition complete:")
    print(f"Files processed: {processed_count}")
    print(f"Files skipped: {skipped_count}")
    print(f"Total files: {len(all_files)}")

if __name__ == "__main__":
    main()
