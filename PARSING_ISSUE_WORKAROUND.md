# TLA+ Parsing Issue Workaround

## Issue Summary
The TLA+ parser (SANY) encounters a `java.util.UnknownFormatConversionException: Conversion = 'i'` error when parsing the Types.tla module. This appears to be a bug in the parser where certain patterns in the code are misinterpreted as Java format strings.

## Root Cause
The error occurs in Types.tla despite:
1. All `%` characters in comments being replaced with "percent"
2. The modulo operator `%` being syntactically correct TLA+ code
3. The module parsing correctly in isolation for smaller test cases

The issue appears to be triggered by the combination of:
- The INSTANCE Utils declaration
- Complex expressions using the modulo operator
- The size/complexity of the Types.tla file

## Workaround Solutions

### 1. Simplified Specification (Implemented)
- Created `AlpenglowSimple.tla` - a minimal working specification
- Created `SimpleTest.cfg` - a basic configuration file
- Successfully runs TLC model checking (though finds property violations)

### 2. Split Types Module (Implemented)
- Created `TypesCore.tla` with core type definitions
- This module parses successfully without errors
- Can be used as a foundation for rebuilding the specification

### 3. Configuration File Fixes Applied
- Removed complex function definitions that TLC cannot parse
- Commented out Stake and LeaderFunction assignments
- Fixed SYMMETRY declarations
- Removed conflicting INIT/NEXT with SPECIFICATION

## Current Status

### Working:
- TLC model checker itself is functional
- Simplified specifications can be model checked
- TypesCore.tla module parses without errors

### Not Working:
- Original Types.tla module still has parsing errors
- Full Alpenglow.tla specification cannot be parsed due to Types.tla dependency
- Complex function constants in configuration files

## Next Steps

1. **Option A: Refactor Types.tla**
   - Split into multiple smaller modules
   - Isolate problematic patterns
   - Gradually rebuild functionality

2. **Option B: Upgrade TLC/Java**
   - Try newer version of TLA+ tools
   - Use different Java runtime
   - Report bug to TLA+ maintainers

3. **Option C: Simplify Specification**
   - Use AlpenglowSimple as base
   - Gradually add complexity
   - Avoid problematic patterns

## Testing Commands

### Test Simplified Specification:
```bash
cd specs
java -cp ../tools/tla2tools.jar tlc2.TLC -config ../models/SimpleTest.cfg AlpenglowSimple.tla
```

### Test TypesCore Module:
```bash
cd specs
java -cp ../tools/tla2tools.jar tla2sany.SANY TypesCore.tla
```

### Test Original (Still Fails):
```bash
cd specs
java -cp ../tools/tla2tools.jar tla2sany.SANY Types.tla
```

## Known Issues to Avoid

1. **In TLA+ Comments:**
   - Never use `%` followed by letters (interpreted as format specifiers)
   - Use "percent" instead of `%` symbol in comments

2. **In Configuration Files:**
   - Avoid multi-line function definitions
   - Use simple constant assignments
   - Comment out complex expressions

3. **In Module Structure:**
   - Keep modules under ~500 lines if possible
   - Minimize cross-module dependencies
   - Test parsing after each major addition
