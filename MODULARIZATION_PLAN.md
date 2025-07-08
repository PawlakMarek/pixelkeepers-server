# NixOS Configuration Modularization Plan

## Current State Analysis

The main `configuration.nix` file has grown to ~720 lines and contains multiple distinct service configurations. This creates maintainability challenges and makes it difficult to manage individual services.

## Proposed Module Structure

### 1. Core System Module (`modules/system.nix`)
- Base system configuration
- ZFS pool management
- Firewall rules
- Basic nginx setup
- User/group definitions

### 2. Authentication Module (`modules/auth.nix`)
- LDAP configuration (LLDAP)
- Authelia SSO setup
- Authentication rules and policies
- SSL certificate management

### 3. Media Services Module (`modules/media.nix`)
- Plex Media Server configuration
- arr stack (Radarr, Sonarr, Jackett)
- Recyclarr configuration
- Media-specific nginx configurations

### 4. Productivity Module (`modules/productivity.nix`)
- Nextcloud configuration
- Vaultwarden setup
- Related nginx overrides

### 5. Storage Module (`modules/storage.nix`)
- ZFS dataset definitions
- Custom pool configurations
- Mount point management
- Backup configurations (restic)

### 6. Secrets Module (`modules/secrets.nix`)
- SOPS secret definitions
- Secret request/result mappings
- Centralized secret management

## Implementation Strategy

### Phase 1: Extract Core Services
1. Create `modules/` directory
2. Extract Plex configuration to `modules/media.nix`
3. Extract authentication services to `modules/auth.nix`
4. Update main `configuration.nix` to import modules

### Phase 2: Storage and Backup
1. Move ZFS configurations to `modules/storage.nix`
2. Consolidate backup configurations
3. Clean up mount point definitions

### Phase 3: Secrets and Productivity
1. Extract all SOPS configurations to `modules/secrets.nix`
2. Move Nextcloud and Vaultwarden to `modules/productivity.nix`
3. Centralize nginx overrides

### Phase 4: Optimization
1. Create shared configuration patterns
2. Implement reusable functions for common patterns
3. Add module-level documentation
4. Validate all services work after modularization

## Module Interface Design

Each module should follow this pattern:

```nix
{ lib, config, pkgs, ... }: {
  options = {
    # Module-specific options
  };
  
  config = lib.mkIf config.services.moduleName.enable {
    # Module configuration
  };
}
```

## Benefits

1. **Maintainability**: Each service in its own file
2. **Reusability**: Modules can be conditionally enabled/disabled
3. **Clarity**: Clear separation of concerns
4. **Testing**: Easier to test individual components
5. **Documentation**: Better organized documentation per module

## File Structure After Modularization

```
nixos-core/
├── configuration.nix          # Main config (imports + domain setting)
├── secrets.yaml              # SOPS secrets
├── modules/
│   ├── system.nix            # Core system settings
│   ├── auth.nix              # LDAP + Authelia
│   ├── media.nix             # Plex + arr stack
│   ├── productivity.nix      # Nextcloud + Vaultwarden
│   ├── storage.nix           # ZFS + backups
│   └── secrets.nix           # SOPS configurations
└── ...
```

## Implementation Priority

1. **High Priority**: Media module (Plex + arr stack) - most complex
2. **Medium Priority**: Authentication module - critical for security
3. **Medium Priority**: Storage module - affects all services
4. **Low Priority**: Productivity module - self-contained services

## Success Criteria

- [ ] Main configuration.nix under 100 lines
- [ ] Each module under 200 lines
- [ ] All services functional after modularization
- [ ] Clear module boundaries and interfaces
- [ ] Improved documentation per module
- [ ] Easier to add new services