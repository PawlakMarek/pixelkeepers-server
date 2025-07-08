# PSF Testing Environment

This directory contains the testing infrastructure for the PixelKeepers Service Framework (PSF). The testing environment provides a complete virtual machine setup that mirrors the production environment for safe testing of PSF features and deployments.

## Overview

The testing environment consists of:
- **VM Configuration** (`vm-config.nix`) - Complete NixOS VM setup with PSF framework
- **Flake Definition** (`flake.nix`) - Build and deployment automation
- **Test Services** (`test-services.nix`) - Minimal services for functionality validation
- **Test Data** (`data/`) - Shared directory for test data and configurations

## Quick Start

### Prerequisites

- NixOS or Nix with flakes enabled
- QEMU for virtualization
- Minimum 8GB RAM and 20GB disk space

### Starting the Test Environment

1. **Enter the testing directory:**
   ```bash
   cd testing
   ```

2. **Enter development shell:**
   ```bash
   nix develop
   ```

3. **Start the VM:**
   ```bash
   start-vm
   # or alternatively:
   nix run .#start-vm
   ```

4. **Wait for VM to boot** (first boot may take several minutes for building)

5. **Test connectivity:**
   ```bash
   test-psf
   # or alternatively:
   nix run .#test-psf
   ```

### Accessing the VM

- **SSH Access:** `ssh-vm` or `ssh -p 2222 root@localhost`
- **HTTP:** http://localhost:8080
- **HTTPS:** https://localhost:8443 (self-signed certificate)
- **PostgreSQL:** localhost:5432

## VM Configuration Details

### System Specifications
- **OS:** NixOS 25.05
- **Memory:** 4GB RAM
- **Storage:** 20GB disk
- **CPU:** 2 cores
- **Network:** NAT with port forwarding

### Network Ports
| Service | Host Port | VM Port | Description |
|---------|-----------|---------|-------------|
| SSH | 2222 | 22 | SSH access to VM |
| HTTP | 8080 | 80 | Web services |
| HTTPS | 8443 | 443 | Secure web services |
| PostgreSQL | 5432 | 5432 | Database access |
| Test Service | 3000 | 3000 | Custom test service |

### User Accounts
- **root:** SSH key authentication (production SSH key)
- **psftest:** Test user with password `test123` and sudo access

### Installed PSF Providers
- **SSL:** Self-signed certificates for testing
- **Database:** PostgreSQL 17 with test databases
- **Secrets:** Hardcoded provider for testing
- **Backup:** Borg backup with local repository
- **Proxy:** Nginx reverse proxy
- **LDAP:** LLDAP for authentication testing
- **SSO:** Authelia for single sign-on testing

## Testing Procedures

### Framework Validation

1. **Build Test:**
   ```bash
   nix flake check
   ```
   Validates that all PSF components build correctly.

2. **Deployment Test:**
   ```bash
   deploy-vm
   ```
   Tests deployment to running VM.

3. **Service Health Check:**
   ```bash
   ssh-vm
   systemctl status psf-health-check
   ```

### Service Testing

1. **Web Services:**
   ```bash
   curl http://localhost:8080/
   curl -k https://localhost:8443/
   curl http://localhost:3000/  # Test service
   ```

2. **Database Testing:**
   ```bash
   ssh-vm
   sudo -u postgres psql -c "SELECT version();"
   sudo -u postgres psql -l  # List databases
   ```

3. **Authentication Testing:**
   ```bash
   # Test LLDAP web interface
   curl http://localhost:8080/lldap/
   
   # Test Authelia
   curl http://localhost:8080/authelia/
   ```

### PSF Contract Testing

Test individual contracts by SSH into the VM and checking services:

```bash
ssh-vm

# SSL Contract
ls -la /var/lib/acme/  # Check certificates

# Database Contract  
systemctl status postgresql
sudo -u postgres psql -c "\\l"  # List databases

# Backup Contract
systemctl status borgbackup-job-*
ls -la /var/lib/borg-backups/

# Proxy Contract
systemctl status nginx
nginx -t  # Test configuration

# LDAP Contract
systemctl status lldap
curl -s http://localhost:17170/health

# SSO Contract
systemctl status authelia
curl -s http://localhost:9091/api/health
```

## Development Workflow

### Making Changes

1. **Edit configuration files** in the testing directory
2. **Rebuild and deploy:**
   ```bash
   deploy-vm
   ```
3. **Test changes:**
   ```bash
   test-psf
   ```

### Adding New Services

1. Edit `vm-config.nix` to add PSF service configuration
2. Update `test-services.nix` for additional test services
3. Add new port forwarding if needed
4. Test deployment

### Debugging Issues

1. **Check VM logs:**
   ```bash
   ssh-vm
   journalctl -f  # Follow system logs
   journalctl -u <service-name>  # Specific service logs
   ```

2. **Check PSF validation:**
   ```bash
   ssh-vm
   # PSF-specific debugging commands will be added here
   ```

3. **Monitor resources:**
   ```bash
   ssh-vm
   htop  # System resources
   df -h  # Disk usage
   systemctl status  # Service status
   ```

## File Structure

```
testing/
├── README.md           # This documentation
├── flake.nix          # Build and deployment configuration
├── vm-config.nix      # Main VM configuration
├── test-services.nix  # Additional test services
└── data/              # Shared test data directory
    └── .gitkeep       # Keep directory in git
```

## Environment Variables

When in the development shell, these environment variables are available:
- `PWD` - Current testing directory
- Standard Nix environment variables

## Automation Scripts

Available in development shell:
- `start-vm` - Build and start the VM
- `stop-vm` - Stop the running VM
- `deploy-vm` - Deploy configuration to running VM
- `ssh-vm` - SSH into the VM
- `test-psf` - Run comprehensive PSF tests

## Troubleshooting

### Common Issues

1. **VM won't start:**
   - Check available memory (requires 4GB)
   - Ensure QEMU is available
   - Check for port conflicts

2. **SSH connection failed:**
   - Verify VM is running
   - Check port 2222 is not blocked
   - Wait for boot to complete

3. **Services not responding:**
   - Check service status with `systemctl status <service>`
   - Review logs with `journalctl -u <service>`
   - Verify firewall rules

4. **Build failures:**
   - Run `nix flake check` for detailed error messages
   - Check PSF framework syntax
   - Verify all required providers are available

### Performance Considerations

- First VM build will download and compile packages (20-30 minutes)
- Subsequent builds are faster due to Nix caching
- VM startup time: 1-2 minutes after building
- Consider increasing VM memory for complex testing

## Security Notes

⚠️ **This is a testing environment only!**

- Uses hardcoded passwords and secrets
- SSH root login enabled
- Self-signed certificates
- No production security measures
- Never use this configuration in production

## Integration with Production

The testing environment mirrors the production setup in:
- NixOS version (25.05)
- Nixpkgs version (nixos-unstable-small)
- PSF framework configuration
- Service architecture

Differences from production:
- Simplified networking (NAT instead of bridge)
- Test credentials instead of proper secrets
- Local storage instead of network storage
- No backup encryption or remote destinations

## Contributing

When adding new PSF features:

1. Add test configuration to `vm-config.nix`
2. Create validation tests in `test-services.nix`
3. Update this documentation
4. Test thoroughly before production deployment

## Support

For issues with the testing environment:
1. Check this documentation
2. Review PSF framework documentation
3. Check VM and service logs
4. Validate configuration with `nix flake check`