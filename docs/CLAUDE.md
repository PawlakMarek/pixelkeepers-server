# PixelKeepers Service Framework (PSF) - Implementation Guide

This document provides instructions for Claude instances working on the PSF (PixelKeepers Service Framework) implementation.

## Overview

We are replacing SHB (Self-Hosted Blocks) with a custom-built framework called PSF. The framework uses a contract-based architecture for better reliability, debuggability, and maintainability.

## Essential Documents

### Primary Technical Specification
- **PSF_IMPLEMENTATION.md** - Complete technical specification with all implementation details
  - Contains exact file structures, data formats, function signatures
  - Includes contract definitions, provider implementations, and service examples
  - Memory-independent and complete enough for implementation from scratch

### Live Documentation (Updated During Implementation)
- **CLAUDE.md** - This file, provides workflow instructions
- **PSF_IMPLEMENTATION.md** - Technical specification (update as design evolves)

## Working Principles

### 1. Documentation-First Development
- **ALWAYS** read PSF_IMPLEMENTATION.md before starting any work
- **ALWAYS** update documentation when making design changes
- Keep documentation in sync with code implementation
- Document design decisions and rationale

### 2. Contract-Driven Architecture
- Services declare **what they need** (SSL, backup, secrets, LDAP, SSO)
- Providers deliver **how to fulfill** those needs
- Contracts define the **interface** between services and providers
- Follow the exact contract patterns defined in PSF_IMPLEMENTATION.md

### 3. Build-Time Validation
- Everything must be validated during `nix flake check`
- No runtime surprises or deployment failures
- Fail fast with clear error messages and actionable hints

## Current Project State

### Implementation Status
Check the implementation checklist in PSF_IMPLEMENTATION.md to understand current progress:
- Phase 1: Core Framework (check if lib/ components exist)
- Phase 2: Essential Contracts (check if contracts/ exist)
- Phase 3: Core Providers (check if providers/ exist)
- Phase 4: Core Services (check if services/ exist)

### File Structure
```
/home/h4wkeye/Projects/nixos-server/
├── docs/
│   ├── PSF_IMPLEMENTATION.md   # Main technical specification
│   ├── CLAUDE.md              # This workflow guide
│   └── CLAUDE.old.md          # Historic version
├── psf/                       # PSF framework implementation (when created)
│   ├── flake.nix              # PSF framework flake
│   ├── lib/                   # Core framework functions
│   ├── contracts/             # Contract definitions
│   ├── providers/             # Provider implementations
│   ├── services/              # Service definitions
│   └── tests/                 # Framework tests
├── nixos-core/                # Current NixOS configuration (legacy)
│   ├── configuration.nix      # Server configuration
│   ├── secrets.yaml          # SOPS secrets (gitignored)
│   ├── ssh.pub               # Server SSH public key
│   └── modules/              # Server-specific modules
├── shb-fork/                 # SHB fork (to be deprecated)
├── flake.nix                 # Root flake coordinating both projects
├── .gitignore                # Git ignore rules
└── README.md                 # Project overview
```

## Git Workflow

### Repository Organization

This is a **monorepo** containing two interconnected projects:
- **PSF** (`psf/`) - Framework development
- **nixos-core** (`nixos-core/`) - Production server configuration

### Branch Strategy

```
main                    # Stable, production-ready
├── develop            # Active development integration
├── psf/core          # PSF core framework development
├── psf/contracts     # PSF contract system development  
├── psf/providers     # PSF provider development
├── nixos-core/config # Production server configuration
└── nixos-core/migration # SHB to PSF migration work
```

### Starting New Work

#### For PSF Framework Development
```bash
# Create feature branch from develop
git checkout develop
git pull origin develop
git checkout -b psf/feature-name

# Work in psf/ directory
cd psf
# ... make changes ...

# Commit and push
git add psf/
git commit -m "psf: implement feature description

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"
git push origin psf/feature-name
```

#### For nixos-core Configuration
```bash
# Create feature branch from main (since this affects production)
git checkout main
git pull origin main
git checkout -b nixos-core/feature-name

# Work in nixos-core/ directory
cd nixos-core
# ... make changes ...

# Test before committing
nix flake check

# Commit and push
git add nixos-core/
git commit -m "nixos-core: configuration change description

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"
git push origin nixos-core/feature-name
```

### Documentation Updates

```bash
# Documentation changes can be made from any branch
git checkout develop  # or current feature branch
git add docs/
git commit -m "docs: update documentation

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

### Commit Message Conventions

#### PSF Framework
- `psf: implement SSL contract` - New framework features
- `psf: fix provider validation logic` - Bug fixes
- `psf: refactor contract interface` - Refactoring

#### nixos-core Configuration  
- `nixos-core: add Plex service configuration` - Service additions
- `nixos-core: migrate Nextcloud to PSF` - SHB migrations
- `nixos-core: update secrets management` - Configuration changes

#### Documentation
- `docs: update PSF implementation spec` - Specification updates
- `docs: add git workflow instructions` - Process documentation
- `docs: fix contract examples` - Documentation fixes

### Security Considerations

**Always verify .gitignore rules before committing:**
```bash
# Check what will be committed
git status
git diff --cached

# Verify no secrets are staged
git diff --cached --name-only | grep -E "(secrets|\.key|\.pem)"
```

**Protected files (automatically gitignored):**
- `nixos-core/ssh` - SSH private key
- `nixos-core/secrets.yaml` - SOPS secrets
- Any `*.key`, `*.pem` files

**Tracked files:**
- `nixos-core/ssh.pub` - SSH public key
- Configuration files without secrets

### Integration Workflow

#### Merging PSF Changes
```bash
# PSF changes go through develop branch
git checkout develop
git merge psf/feature-name
git push origin develop

# When ready for production integration
git checkout main
git merge develop
git push origin main
```

#### Merging nixos-core Changes
```bash
# nixos-core changes go directly to main (production)
git checkout main
git merge nixos-core/feature-name
git push origin main
```

## Development Workflow

### Starting New Work
1. **Choose appropriate git branch** based on PSF vs nixos-core work
2. **Read docs/PSF_IMPLEMENTATION.md** completely to understand the current design
3. **Check existing code** in psf/ directory to understand implementation status
4. **Identify the specific task** from the implementation checklist
5. **Understand dependencies** - what needs to be implemented first

### Making Changes
1. **Follow exact patterns** defined in PSF_IMPLEMENTATION.md
2. **Use provided code examples** as templates
3. **Maintain consistency** with existing contract/provider interfaces
4. **Add proper error handling** with clear error messages

### Testing and Validation
1. **Build test** with `nix flake check` after every change
2. **Fix all warnings and errors** before proceeding
3. **Test contracts** work with multiple providers when possible
4. **Validate error messages** are helpful and actionable

### Documentation Updates
**ALWAYS update these documents when making changes:**

#### PSF_IMPLEMENTATION.md Updates
- Add new contracts to the contracts section
- Add new providers to the providers section
- Update code examples when interfaces change
- Update implementation checklist when completing tasks
- Add new error codes and messages to error handling section

#### CLAUDE.md Updates
- Update "Current Project State" when major milestones are reached
- Add new workflow instructions when processes change
- Update file structure when directories are added/changed
- Document new development patterns or conventions

## Implementation Guidelines

### Contract Implementation
- Use exact contract interface pattern from PSF_IMPLEMENTATION.md
- Include comprehensive validation functions
- Provide clear examples in contract documentation
- Follow naming conventions: contracts/<name>.nix

### Provider Implementation
- Use registerProvider helper function
- Implement all required interface functions (canFulfill, fulfill, validate)
- Include capability declarations
- Follow naming conventions: providers/<contract>/<provider>.nix

### Service Implementation
- Use psf.defineService pattern
- Declare all needs using contract requests
- Provide what the service offers to other services
- Include comprehensive health checks
- Follow naming conventions: services/<service>.nix

### Error Handling
- Use standardized error format from PSF_IMPLEMENTATION.md
- Provide specific error codes (PSF001, PSF002, etc.)
- Include actionable hints for fixing errors
- Test error conditions and messages

## Code Quality Standards

### File Organization
- Follow exact directory structure from PSF_IMPLEMENTATION.md
- Use consistent naming conventions
- Group related functionality logically
- Keep files focused and single-purpose

### Code Style
- Follow NixOS conventions and patterns
- Use clear, descriptive variable names
- Add comments only when business logic is complex
- Prefer explicit over implicit configurations

### Validation and Testing
- All code must pass `nix flake check`
- Include build-time validation for all contracts
- Test with multiple providers when available
- Validate error conditions and recovery

## Common Tasks

### Adding a New Contract
1. Create contracts/<name>.nix following the contract pattern
2. Add to contracts/default.nix exports
3. Add to lib/contracts.nix imports
4. Update PSF_IMPLEMENTATION.md with contract specification
5. Test with `nix flake check`

### Adding a New Provider
1. Create providers/<contract>/<provider>.nix following provider pattern
2. Add to providers/default.nix exports
3. Add to lib/providers.nix imports
4. Update PSF_IMPLEMENTATION.md with provider documentation
5. Test fulfillment with multiple contract requests

### Adding a New Service
1. Create services/<service>.nix following service pattern
2. Add to services/default.nix exports
3. Update PSF_IMPLEMENTATION.md with service example
4. Test service builds and validates correctly
5. Test service works with different provider combinations

### Migrating from SHB
1. Identify SHB service configuration in nixos-core/
2. Extract service requirements (SSL, backup, secrets, etc.)
3. Convert to PSF contract requests
4. Create PSF service definition
5. Test PSF service provides same functionality
6. Remove SHB service configuration
7. Update documentation

## Debugging and Troubleshooting

### Build Failures
1. Check `nix flake check` output for specific errors
2. Verify all imports and exports are correct
3. Check contract interface compliance
4. Validate provider canFulfill logic

### Contract Resolution Issues
1. Verify contract request format matches contract schema
2. Check provider canFulfill returns true for request
3. Validate provider configuration is complete
4. Check provider priority order in configuration

### Service Integration Issues
1. Verify service needs are properly declared
2. Check contract results are used correctly in service config
3. Validate health checks are appropriate
4. Test service isolation and dependencies

## Migration Timeline

We are migrating from SHB to PSF gradually:
1. **Current**: SHB-based services are running in production
2. **Implementation**: Building PSF framework alongside SHB
3. **Testing**: PSF services tested in parallel with SHB
4. **Migration**: One service at a time migration to PSF
5. **Completion**: SHB removal and cleanup

**Never break existing services during PSF development.**

## Communication Protocols

### When Stuck
- Re-read relevant sections of PSF_IMPLEMENTATION.md
- Check existing working examples in the specification
- Look for similar patterns in implemented code
- Ask for clarification on specific technical details

### When Making Design Changes
- Update PSF_IMPLEMENTATION.md with the new design
- Explain rationale for the change
- Update affected code examples
- Update implementation checklist if needed

### When Completing Milestones
- Update implementation checklist in PSF_IMPLEMENTATION.md
- Update "Current Project State" in CLAUDE.md
- Document any lessons learned or new patterns
- Prepare for next implementation phase

This is a live document - update it whenever workflow patterns change or new development procedures are established.