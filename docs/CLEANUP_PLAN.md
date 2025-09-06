# Alpenglow Formal Verification Project - Cleanup Plan

## Document Overview

This document serves as the comprehensive reference for cleaning up the Alpenglow formal verification project repository. The cleanup aims to transform the current development-heavy structure into a clean, production-ready codebase suitable for formal submission and long-term maintenance.

**Document Version**: 1.0  
**Created**: 2024  
**Purpose**: Guide the systematic cleanup of development artifacts while preserving all essential functionality  

---

## Current State Analysis

### Existing Directory Structure

The project currently contains the following major components:

```
/Users/ayushsrivastava/SuperteamIN/
├── specs/                          # TLA+ specifications (CORE - PRESERVE)
│   ├── Alpenglow.tla              # Main specification
│   ├── AlpenglowSimple.tla        # Simplified model
│   ├── Votor.tla                  # Consensus mechanism
│   ├── Rotor.tla                  # Data dissemination
│   └── *_TTrace_*.tla             # Generated trace files (CLEANUP)
├── proofs/                         # Mathematical proofs (CORE - PRESERVE)
├── implementation/                 # Rust production code (CORE - PRESERVE)
├── stateright/                     # Stateright model checker (CORE - PRESERVE)
├── models/                         # TLA+ configurations (CORE - PRESERVE)
├── docs/                          # Documentation (CORE - PRESERVE)
├── submission/                     # Formal submission package (CORE - PRESERVE)
├── ci/                            # CI/CD configuration (CORE - PRESERVE)
├── results/                       # Development artifacts (CLEANUP)
├── analysis/                      # Python analysis tools (CLEANUP)
├── benchmarks/                    # Performance tools (CLEANUP)
├── tools/                         # Development utilities (CLEANUP)
├── test_verification.sh           # Development script (REORGANIZE)
├── localverify.sh                 # Development script (REORGANIZE)
├── verify.sh                      # Development script (REORGANIZE)
├── run_tlc.sh                     # Development script (REORGANIZE)
├── run_build_diagnosis.sh         # Development script (REORGANIZE)
├── .gitignore                     # Version control (ENHANCE)
└── README.md                      # Project documentation (ENHANCE)
```

### Component Classification

**Core Production Components** (PRESERVE):
- `specs/` - TLA+ formal specifications
- `proofs/` - Mathematical proofs and theorems
- `implementation/` - Rust production implementation
- `stateright/` - Stateright model checker implementation
- `models/` - TLA+ configuration files
- `docs/` - Project documentation
- `submission/` - Formal submission package
- `ci/` - CI/CD pipeline configuration

**Development Artifacts** (CLEANUP):
- `results/` - Timestamped verification results
- `analysis/` - Python development tools
- `benchmarks/` - Performance analysis tools
- `tools/` - Development utilities
- `specs/*_TTrace_*.tla` - TLA+ execution traces

**Scripts** (REORGANIZE):
- Root-level shell scripts need organization into structured directories

---

## Target State Definition

### Clean Production Structure

The target structure organizes components by purpose and separates production code from development tools:

```
/Users/ayushsrivastava/SuperteamIN/
├── specs/                          # TLA+ specifications (cleaned)
├── proofs/                         # Mathematical proofs
├── implementation/                 # Rust production code
├── stateright/                     # Stateright model checker
├── models/                         # TLA+ configurations
├── scripts/                        # Organized scripts
│   ├── production/                 # Production deployment scripts
│   ├── ci/                         # CI/CD specific scripts
│   └── dev/                        # Development scripts (gitignored)
├── docs/                          # Documentation (updated)
├── submission/                     # Formal submission package (updated)
├── ci/                            # CI/CD configuration (updated)
├── .gitignore                     # Enhanced exclusion patterns
└── README.md                      # Comprehensive project overview
```

### Key Improvements

1. **Script Organization**: All scripts moved to `scripts/` with clear categorization
2. **Development Isolation**: Development tools separated and gitignored
3. **Clean Specifications**: TLA+ trace files removed from specs directory
4. **Enhanced Gitignore**: Comprehensive patterns to prevent future artifacts
5. **Updated Documentation**: All references updated to new structure
6. **CI Integration**: Pipeline updated to work with new organization

---

## Risk Assessment

### High-Risk Changes

**1. CI Pipeline Dependencies**
- **Risk**: CI pipeline extensively references scripts and directories being moved/removed
- **Impact**: Build failures, verification pipeline breakage
- **Mitigation**: 
  - Create missing scripts (`check_model.sh`, `verify_proofs.sh`, `parallel_check.sh`) before cleanup
  - Update CI configuration to use new script paths
  - Test CI pipeline in staging environment before production changes

**2. Cross-Component References**
- **Risk**: Rust tests, documentation, and submission package reference moved/deleted directories
- **Impact**: Test failures, broken documentation links, submission package issues
- **Mitigation**:
  - Comprehensive grep search for all references before making changes
  - Update all references atomically
  - Maintain submission package integrity with updated paths

**3. TLA+ Tool Dependencies**
- **Risk**: TLA+ specifications may have implicit dependencies on trace files or specific directory structure
- **Impact**: Model checking failures, proof verification issues
- **Mitigation**:
  - Verify TLA+ tools work with cleaned specs directory
  - Ensure trace files are truly temporary and can be safely removed
  - Test model checking pipeline after cleanup

### Medium-Risk Changes

**1. Development Workflow Disruption**
- **Risk**: Developers accustomed to current script locations and development tools
- **Impact**: Temporary productivity loss, confusion
- **Mitigation**:
  - Comprehensive documentation of new structure
  - Clear migration guide for developers
  - Preserve development tools in new organized locations

**2. External Tool Integration**
- **Risk**: External tools or scripts may reference old paths
- **Impact**: Integration failures
- **Mitigation**:
  - Document all external dependencies
  - Provide compatibility notes for external integrations

### Low-Risk Changes

**1. Development Artifact Removal**
- **Risk**: Loss of historical development data
- **Impact**: Inability to reference past verification runs
- **Mitigation**:
  - Archive important results before deletion
  - Ensure CI generates new results as needed

---

## Dependency Mapping

### Files Referencing Directories to be Modified/Removed

**CI Pipeline Dependencies**:
- `ci/verify_all.yml` → `scripts/check_model.sh` (MISSING - needs creation)
- `ci/verify_all.yml` → `benchmarks/` directory (conditional usage)
- `ci/verify_all.yml` → `results/ci/` paths

**Rust Test Dependencies**:
- `stateright/tests/integration_tests.rs:368` → `results/integration_tests_report_*.json`
- `stateright/tests/safety_properties.rs:652,890` → `results/` directory
- `stateright/tests/liveness_properties.rs:141` → `results/liveness_properties_report_*.json`
- `stateright/tests/cross_pipeline.rs:180` → `scripts/check_model.sh`

**Documentation Dependencies**:
- `docs/VerificationGuide.md` → script references
- `docs/DevelopmentGuide.md` → development workflow instructions
- `docs/CrossValidationGuide.md` → cross-validation script references
- `docs/VerificationMapping.md` → `scripts/verify_proofs.sh`, `scripts/parallel_check.sh`

**Submission Package Dependencies**:
- `submission/README.md` → script references
- `submission/ReproducibilityPackage.md` → verification script paths
- `submission/run_complete_verification.sh` → various script paths

**Analysis Tool Dependencies**:
- `analysis/coverage_report.py` → referenced by CI pipeline

### Missing Critical Scripts

The following scripts are referenced but don't exist and must be created:
1. `scripts/ci/check_model.sh` - Referenced extensively in CI pipeline
2. `scripts/ci/verify_proofs.sh` - Referenced in documentation
3. `scripts/ci/parallel_check.sh` - Referenced in documentation

---

## Validation Checklist

### Pre-Cleanup Validation

- [ ] **Backup Creation**: Create full repository backup
- [ ] **Dependency Audit**: Complete grep search for all file references
- [ ] **CI Pipeline Test**: Verify current CI pipeline works
- [ ] **Script Inventory**: Document all existing scripts and their purposes
- [ ] **External Dependencies**: Identify any external tools that reference the repository

### Phase 1: Enhancement Phase Validation

- [ ] **Gitignore Testing**: Verify enhanced .gitignore patterns work correctly
- [ ] **Development Workflow**: Test that development artifacts are properly excluded
- [ ] **CI Compatibility**: Ensure CI pipeline still functions with enhanced gitignore

### Phase 2: Migration Phase Validation

- [ ] **Script Organization**: Verify all scripts moved to correct locations
- [ ] **Permission Preservation**: Ensure executable permissions maintained
- [ ] **Path Updates**: Confirm all script references updated
- [ ] **CI Script Creation**: Verify missing CI scripts created and functional

### Phase 3: Cleanup Phase Validation

- [ ] **TLA+ Functionality**: Verify TLA+ model checking works after trace file removal
- [ ] **Rust Tests**: Confirm all Rust tests pass with updated paths
- [ ] **CI Pipeline**: Verify complete CI pipeline execution
- [ ] **Documentation Accuracy**: Confirm all documentation reflects new structure
- [ ] **Submission Package**: Verify submission package integrity maintained

### Post-Cleanup Validation

- [ ] **Full Verification Run**: Execute complete verification pipeline
- [ ] **Cross-Platform Testing**: Test on different development environments
- [ ] **Performance Verification**: Ensure no performance degradation
- [ ] **Developer Onboarding**: Test new developer setup process
- [ ] **External Integration**: Verify external tools still work

---

## Rollback Plan

### Immediate Rollback (Within 24 hours)

If critical issues are discovered immediately after cleanup:

1. **Git Revert**: Use git to revert to pre-cleanup state
   ```bash
   git log --oneline -10  # Find pre-cleanup commit
   git revert <commit-hash> --no-edit
   ```

2. **Backup Restoration**: If git revert insufficient, restore from backup
   ```bash
   cp -r /backup/SuperteamIN/* /Users/ayushsrivastava/SuperteamIN/
   ```

3. **CI Pipeline Reset**: Revert CI configuration to previous working state

### Partial Rollback (Specific Components)

If only certain changes cause issues:

1. **Script Rollback**: Restore scripts to original locations
   ```bash
   mv scripts/dev/* ./
   mv scripts/ci/check_model.sh ./scripts/
   ```

2. **Directory Restoration**: Recreate specific directories if needed
   ```bash
   mkdir -p results analysis benchmarks tools
   git checkout HEAD~1 -- results/ analysis/ benchmarks/ tools/
   ```

3. **Documentation Revert**: Restore original documentation
   ```bash
   git checkout HEAD~1 -- docs/ submission/
   ```

### Extended Rollback (After Development)

If issues discovered after extended development:

1. **Selective Restoration**: Restore only problematic components
2. **Hybrid Approach**: Keep beneficial changes, revert problematic ones
3. **Gradual Re-cleanup**: Re-apply cleanup in smaller, safer increments

### Rollback Validation

After any rollback:
- [ ] **CI Pipeline**: Verify CI pipeline functions correctly
- [ ] **All Tests**: Run complete test suite
- [ ] **Documentation**: Ensure documentation matches current state
- [ ] **Developer Workflow**: Verify development workflow works
- [ ] **External Integration**: Test external tool compatibility

---

## Implementation Phases

### Phase 1: Assessment and Enhancement (Low Risk)
1. Create this cleanup plan document
2. Enhance .gitignore with comprehensive patterns
3. Test enhanced gitignore with development workflow
4. Document current state thoroughly

### Phase 2: Script Organization (Medium Risk)
1. Create scripts directory structure
2. Create missing CI scripts (`check_model.sh`, `verify_proofs.sh`, `parallel_check.sh`)
3. Move existing scripts to appropriate locations
4. Update CI pipeline to use new script locations
5. Test CI pipeline with new structure

### Phase 3: Reference Updates (Medium Risk)
1. Update all Rust test file references
2. Update documentation references
3. Update submission package references
4. Test all updated references

### Phase 4: Cleanup Execution (High Risk)
1. Remove development artifact directories
2. Clean TLA+ trace files from specs
3. Update README with new structure
4. Final validation of all functionality

### Phase 5: Validation and Documentation (Low Risk)
1. Complete validation checklist
2. Update developer documentation
3. Create migration guide for external users
4. Archive cleanup plan for future reference

---

## Success Criteria

The cleanup will be considered successful when:

1. **Functionality Preserved**: All core verification functionality works identically
2. **CI Pipeline**: Complete CI pipeline executes successfully
3. **Clean Structure**: Repository has clear, organized structure
4. **Documentation**: All documentation is accurate and up-to-date
5. **Developer Experience**: New developers can easily understand and use the project
6. **Maintainability**: Future development artifacts won't accumulate in repository
7. **Submission Ready**: Formal submission package is clean and professional

---

## Notes and Considerations

### Development Workflow Impact
- Developers will need to adapt to new script locations
- Development tools moved to gitignored directories
- Clear documentation will minimize transition friction

### Future Maintenance
- Enhanced gitignore prevents future artifact accumulation
- Organized script structure makes maintenance easier
- Clear separation between production and development components

### External Dependencies
- External tools may need updates for new paths
- Documentation provides migration guidance
- Backward compatibility notes for external integrations

### Archive Strategy
- Important development artifacts should be archived before deletion
- Historical verification results can be preserved separately if needed
- Development tools can be maintained in separate development repository

---

## Conclusion

This cleanup plan provides a systematic approach to transforming the Alpenglow formal verification project from a development-heavy repository to a clean, production-ready codebase. The phased approach minimizes risk while ensuring all essential functionality is preserved and enhanced.

The plan prioritizes safety through comprehensive validation, clear rollback procedures, and incremental implementation. Upon completion, the project will have a professional structure suitable for formal submission, long-term maintenance, and easy onboarding of new contributors.