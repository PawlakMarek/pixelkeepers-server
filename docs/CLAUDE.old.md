# NixOS Server Configuration

This document provides essential information about the NixOS server setup for future reference and support.

## Server Overview

- **Hostname**: nixos-core
- **Username**: h4wkeye
- **Domain**: pixelkeepers.net
- **Local IP**: 192.168.68.20
- **Public IP**: 109.173.179.149

## Network Configuration

### Port Forwarding
- 80 → 192.168.68.20:80 (HTTP)
- 443 → 192.168.68.20:443 (HTTPS) 
- 3322 → 192.168.68.20:22 (SSH)
- 4422 → 192.168.68.20:2222 (SSH alt)

### DNS Configuration
- Managed via Cloudflare
- Wildcard certificate covers `*.pixelkeepers.net` and `pixelkeepers.net`
- Can be proxied or direct - both work with current SSL setup

## Access Methods

### SSH Access
**Important**: All SSH access is managed via skarabox - direct SSH with username/password won't work.

```bash
# Access server (only method that works)
nix run .#nixos-core-ssh

# Unlock root pool after reboot (required after each restart)
nix run .#nixos-core-unlock
```

### Services
- **Vaultwarden**: https://vw.pixelkeepers.net (✅ **Working** - normal vault access)
- **Admin Panel**: https://vw.pixelkeepers.net/admin (✅ **Working** - SSO + group protected)

## Storage Configuration

### ZFS Pools

#### Root Pool (managed by skarabox)
- **Pool**: root
- **Disks**: 2x 1TB NVMe in mirror
- **Encryption**: Manual unlock required after each reboot (`nix run .#nixos-core-unlock`)
- **Datasets**:
  - `root/local/nix` - Nix store
  - `root/local/root` - Root filesystem
  - `root/safe/home` - User home directories
  - `root/safe/persist` - Persistent data

#### Data Pool (custom RAIDZ2)
- **Pool**: zdata
- **Disks**: 4x HDDs (3x 8TB + 1x 14TB) in RAIDZ2
- **Capacity**: ~13.6TB available
- **Encryption**: Auto-unlocked (passphrase stored in `/persist/zdata_passphrase`)
- **Datasets**:
  - `zdata/media/movies`
  - `zdata/media/tv`
  - `zdata/media/music`
  - `zdata/media/books`
  - `zdata/media/comics`
  - `zdata/downloads`

#### Private Pool (custom mirror - planned)
- **Pool**: zprivate
- **Disks**: Currently 1x 4TB (will become mirror later)
- **Capacity**: ~3.3TB available
- **Encryption**: Auto-unlocked (passphrase stored in `/persist/zprivate_passphrase`)
- **Datasets**:
  - `zprivate/backups`
  - `zprivate/documents`
  - `zprivate/pictures`
  - `zprivate/nextcloud`
  - `zprivate/postgresql`

### Mount Points
- Data pool: `/mnt/zdata/`
- Private pool: `/mnt/zprivate/`

## Technology Stack

### Core Components
- **OS**: NixOS with skarabox configuration framework
- **Services Framework**: Self-hosted blocks (SHB)
- **Secrets Management**: SOPS with age encryption
- **Deployment**: deploy-rs
- **Storage**: ZFS with encryption

### Disk Management
- **Installation**: disko for declarative disk partitioning
- **Root pool**: Managed by skarabox
- **Data pools**: Custom configuration in `custom-zfs-data.nix`

### SSL/TLS
- **Provider**: Let's Encrypt via ACME
- **DNS Challenge**: Cloudflare API
- **Certificate**: Wildcard (`*.pixelkeepers.net` + `pixelkeepers.net`)
- **Renewal**: Automatic via systemd timers

## Services Configuration

### Vaultwarden
- **Database**: PostgreSQL 17 
- **Storage**: Default location (will migrate to ZFS later)
- **SSL**: Wildcard certificate via SHB
- **Backup**: ✅ **Restored** - Contains 380 vault items + 1 user account
- **Access**: https://vw.pixelkeepers.net (working)

### PostgreSQL
- **Version**: 17
- **Database**: vaultwarden 
- **User**: vaultwarden
- **Location**: `/var/lib/postgresql/17` (default - TODO: move to ZFS)

### Nginx
- **Proxy**: Handles SSL termination and reverse proxy
- **Configuration**: Managed by SHB

## Service Management Best Practices

- **LDAP Considerations**:
  - When adding a new service, make sure if new ldap group needs to be created

## File Structure

```
/home/h4wkeye/Projects/nixos-server/
├── flake.nix                    # Main flake configuration
├── custom-zfs-data.nix         # Custom ZFS pool definitions
├── nixos-core/
│   ├── configuration.nix       # Main system configuration
│   ├── secrets.yaml           # SOPS encrypted secrets
│   ├── ssh.pub                # SSH public key
│   ├── hostid                 # ZFS host ID
│   ├── ip                     # Server IP address
│   └── known_hosts            # SSH known hosts
└── CLAUDE.md                  # This documentation
```

[Rest of the document remains the same as in the original content]