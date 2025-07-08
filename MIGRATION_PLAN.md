# NixOS Server Migration Plan

## Overview
Transition from current hardware to target ZFS configuration with:
- **zroot**: 2x 1TB NVMe (mirror)
- **zdata**: RAIDZ2 with 4 drives (initially 3x8TB + 1x14TB, later 2x8TB + 1x14TB + 1x18TB)
- **zprivate**: Mirror with 2 drives (initially 1x4TB, later 1x4TB + 1x8TB)

## Current Hardware Inventory
- 3x 8TB HDDs (for zdata pool)
- 1x 14TB HDD (for zdata pool)
- 1x 4TB HDD (for zprivate pool)
- 1x 18TB HDD (disconnected, contains backup data)
- 2x 1TB NVMe (for zroot pool)

## Migration Steps

### Phase 1: Initial Setup
1. **Prepare Installation Media**
   ```bash
   # Generate ISO for installation
   nix run .#myskarabox-iso
   ```

2. **Hardware Configuration**
   - Generate `facter.json` on target hardware
   - Update IP configuration in `myskarabox/ip`
   - Configure SSH ports if needed

3. **Initial Installation**
   - Install with current 4-disk RAIDZ2 configuration
   - Initial zdata pool: 3x8TB + 1x14TB
   - Initial zprivate pool: 1x4TB (single disk)

### Phase 2: Data Migration
1. **Copy Backup Data**
   - Connect 18TB backup drive
   - Copy data from 18TB to zdata pool
   - Verify data integrity

2. **Replace Drive**
   - Replace one 8TB drive with 18TB drive
   - ZFS will resilver automatically
   - Final zdata pool: 2x8TB + 1x14TB + 1x18TB

3. **Expand zprivate Pool**
   - Add removed 8TB drive to zprivate pool
   - Convert zprivate from single disk to mirror
   - Final zprivate pool: 1x4TB + 1x8TB (mirror)

### Phase 3: Service Configuration
1. **Setup Self-Hosted Services**
   - Configure LDAP authentication
   - Setup monitoring stack
   - Configure backup to Hetzner Storage Box

2. **Media Services** (optional)
   - Jellyfin for media streaming
   - *arr stack for media management
   - Download management

## ZFS Pool Configurations

### Target zroot Pool (2x 1TB NVMe)
```
zroot (mirror)
├── reserved (500M)
├── local/root (/)
├── local/nix (/nix)
├── safe/home (/home)
└── safe/persist (/persist)
```

### Target zdata Pool (RAIDZ2)
```
zdata (raidz2: 2x8TB + 1x14TB + 1x18TB)
├── reserved (10G)
├── media/movies
├── media/tv
├── media/music
├── media/books
├── media/comics
└── downloads
```

### Target zprivate Pool (Mirror)
```
zprivate (mirror: 1x4TB + 1x8TB)
├── reserved (200G)
├── documents
├── pictures
└── backups
```

## Backup Strategy

### Local Backups
- ZFS snapshots (automatic)
- Cross-pool backup from zprivate to local backup dataset

### Remote Backups (Hetzner Storage Box)
**Included in backup:**
- `/mnt/zprivate` (all private data)
- `/home` (user data)
- `/persist` (system configuration)

**Excluded from backup:**
- `/mnt/zdata/media/*` (easily replaceable media)
- `/mnt/zdata/downloads` (temporary data)
- Cache directories

### Backup Schedule
- **Snapshots**: Frequent (15min), hourly, daily, weekly, monthly
- **Remote backup**: Daily to Hetzner Storage Box
- **Scrub**: Monthly on all pools

## Network Configuration

### Services Endpoints
- **Domain**: pixelkeepers.net
- **Monitoring**: monitoring.pixelkeepers.net
- **LDAP**: ldap.pixelkeepers.net
- **Media**: media.pixelkeepers.net (if configured)

### Backup Configuration
- **Repository**: ssh://u463365@u463365.your-storagebox.de:23/./backups
- **Encryption**: Borgbackup native encryption
- **Compression**: LZ4 for speed

## Prerequisites for Installation

1. **SOPS Secrets Configuration**
   - Update `myskarabox/secrets.yaml` with required passwords
   - Configure Hetzner Storage Box SSH key
   - Set LDAP admin password

2. **Network Configuration**
   - Set static IP in `myskarabox/ip`
   - Configure SSH ports in `myskarabox/ssh_port` and `myskarabox/ssh_boot_port`
   - Update domain configuration for pixelkeepers.net

3. **Hardware Preparation**
   - Verify disk device names match configuration
   - Ensure all drives are properly connected
   - Test hardware with nixos-facter

## Post-Installation Tasks

1. **Verify ZFS Health**
   ```bash
   zpool status
   zfs list
   ```

2. **Test Backups**
   ```bash
   # Test local snapshots
   zfs list -t snapshot
   
   # Test remote backup
   systemctl status borgbackup-job-hetzner
   ```

3. **Configure Additional Services**
   - Setup media streaming services
   - Configure download automation
   - Setup monitoring alerts

## Rollback Plan

If migration fails:
1. Boot from rescue media
2. Import existing ZFS pools
3. Restore from 18TB backup drive
4. Investigate and fix issues

## Notes

- This configuration uses custom ZFS layout overriding skarabox defaults
- RAIDZ2 provides protection against 2 disk failures
- Migration can be done incrementally with minimal downtime
- All critical data should be backed up before starting migration