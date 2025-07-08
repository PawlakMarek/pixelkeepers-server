# PixelKeepers NixOS Server & PSF Framework

This repository contains two interconnected projects:

1. **PSF (PixelKeepers Service Framework)** - A contract-based NixOS service orchestration framework
2. **nixos-core** - Production server configuration using the PSF framework

## Repository Structure

```
nixos-server/                     # Root monorepo
├── psf/                          # PSF framework (future standalone project)
│   ├── flake.nix                # PSF framework flake
│   ├── lib/                     # Core framework
│   ├── contracts/               # Contract definitions  
│   ├── providers/               # Provider implementations
│   ├── services/                # Service definitions
│   └── tests/                   # Framework tests
├── nixos-core/                  # Production server implementation
│   ├── configuration.nix        # Server configuration using PSF
│   ├── secrets.yaml            # SOPS secrets (gitignored)
│   ├── ssh.pub                 # Server SSH public key
│   └── modules/                # Server-specific modules
├── docs/                        # Shared documentation
│   ├── PSF_IMPLEMENTATION.md    # Technical specification
│   ├── CLAUDE.md               # Implementation workflow
│   └── CLAUDE.old.md           # Historic version
├── shb-fork/                   # SHB fork (legacy, to be deprecated)
├── flake.nix                   # Root flake coordinating both projects
└── README.md                   # This file
```

## Documentation

- **[PSF Implementation Specification](docs/PSF_IMPLEMENTATION.md)** - Complete technical specification
- **[Implementation Workflow](docs/CLAUDE.md)** - Development workflow and guidelines

## Git Workflow

### Branch Strategy

- `main` - Stable, production-ready code
- `develop` - Active development integration
- `psf/*` - PSF framework development branches
- `nixos-core/*` - Production server development branches

### Development Workflow

See [docs/CLAUDE.md](docs/CLAUDE.md) for detailed development workflows and git procedures.

## Quick Start

### Working on PSF Framework

```bash
cd psf
nix develop                       # Enter PSF development environment with Claude Code
nix flake check                   # Validate framework components
claude                           # Start Claude Code for AI-assisted development
```

**PSF Development Environment includes:**
- Claude Code for AI-assisted development
- Nix development tools (nixpkgs-fmt, statix, nixfmt)
- Git tools with SSH signing configured
- Server management tools (deploy-rs, sops)  
- Documentation tools (mdbook)
- Environment variables for PSF development

### Working on Production Server

```bash
cd nixos-core
nix flake check

# Deploy to server (from project root)
nix run .#deploy                  # Smart deploy (tries local, then remote)
nix run .#deploy-rs              # Local deployment only
nix run .#deploy-rs-remote       # Remote deployment only

# SSH access options (from project root)
nix run .#nixos-core-ssh          # Local network (192.168.68.20:22)
nix run .#nixos-core-ssh-remote   # Remote access (pixelkeepers.net:3322)
nix run .#nixos-core-ssh-boot     # Boot SSH local (192.168.68.20:2222)
nix run .#nixos-core-ssh-boot-remote # Boot SSH remote (pixelkeepers.net:4422)
nix run .#nixos-core-unlock       # Unlock root pool during boot
```

## Security

- Private SSH keys are gitignored
- SOPS secrets are gitignored
- Public keys and configurations are tracked