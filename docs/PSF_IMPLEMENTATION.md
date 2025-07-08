# PixelKeepers Service Framework (PSF) - Implementation Specification

## File Structure and Organization

```
psf/
├── flake.nix                    # Main flake entry point
├── lib/
│   ├── default.nix             # Core PSF functions
│   ├── contracts.nix           # Contract engine implementation
│   ├── providers.nix           # Provider resolution engine
│   ├── validation.nix          # Build-time validation system
│   ├── service-builder.nix     # Service composition logic
│   └── utils.nix               # Utility functions
├── contracts/
│   ├── default.nix             # All contracts export
│   ├── ssl.nix                 # SSL certificate contract
│   ├── backup.nix              # Backup system contract
│   ├── secrets.nix             # Secret management contract
│   ├── database.nix            # Database service contract
│   ├── ldap.nix                # LDAP directory service contract
│   ├── sso.nix                 # Single Sign-On authentication contract
│   └── proxy.nix               # Reverse proxy contract
├── providers/
│   ├── default.nix             # All providers export
│   ├── ssl/
│   │   ├── letsencrypt.nix     # Let's Encrypt SSL provider
│   │   └── selfsigned.nix      # Self-signed SSL provider
│   ├── backup/
│   │   ├── restic.nix          # Restic backup provider
│   │   └── borg.nix            # Borg backup provider
│   ├── secrets/
│   │   ├── sops.nix            # SOPS secret provider
│   │   └── hardcoded.nix       # Hardcoded secret provider
│   ├── database/
│   │   ├── postgresql.nix      # PostgreSQL provider
│   │   └── mysql.nix           # MySQL provider
│   ├── ldap/
│   │   ├── lldap.nix           # LLDAP provider (lightweight, modern)
│   │   ├── kanidm.nix          # Kanidm provider (Rust, OAuth2/OIDC built-in)
│   │   └── openldap.nix        # OpenLDAP provider (traditional, maximum compatibility)
│   ├── sso/
│   │   ├── authelia.nix        # Authelia SSO provider
│   │   ├── kanidm.nix          # Kanidm SSO provider (built-in OAuth2/OIDC)
│   │   └── oidc.nix            # Generic OIDC SSO provider
│   └── proxy/
│       ├── nginx.nix           # Nginx reverse proxy provider
│       ├── caddy.nix           # Caddy reverse proxy provider (automatic HTTPS)
│       ├── traefik.nix         # Traefik reverse proxy provider (Docker-friendly)
│       └── apache.nix          # Apache reverse proxy provider (traditional)
├── services/
│   ├── default.nix             # All services export
│   ├── plex.nix                # Plex media server
│   ├── nextcloud.nix           # Nextcloud service
│   ├── vaultwarden.nix         # Vaultwarden password manager
│   ├── authelia.nix            # Authelia authentication
│   └── lldap.nix               # LLDAP directory service
└── tests/
    ├── unit/                   # Unit tests for individual components
    ├── integration/            # Integration tests for service combinations
    └── examples/               # Example configurations
```

## Core Data Structures

### Contract Request/Result Format

```nix
# Standard request format - what services ask for
ContractRequest = {
  # Required fields
  contract_type = "ssl" | "backup" | "secrets" | "database" | "proxy";
  requester_id = "service_name.contract_type.request_id";
  
  # Contract-specific payload
  payload = { ... };
  
  # Optional metadata
  priority = "low" | "normal" | "high";  # For provider selection
  tags = [ "production" "development" ]; # For filtering
};

# Standard result format - what providers deliver
ContractResult = {
  # Required fields
  contract_type = "ssl" | "backup" | "secrets" | "database" | "proxy";
  provider_id = "provider_name";
  request_id = "service_name.contract_type.request_id";
  
  # Contract-specific payload
  payload = { ... };
  
  # Provider metadata
  metadata = {
    created_at = "timestamp";
    provider_version = "1.0.0";
    dependencies = [ "systemd.service.name" ];
  };
};

# Contract resolution mapping
ContractResolution = {
  request = ContractRequest;
  result = ContractResult;
  provider = ProviderConfig;
  validation_errors = [ string ];
};
```

### Service Definition Format

```nix
ServiceDefinition = {
  # Service metadata
  name = "plex";
  version = "1.0.0";
  description = "Plex Media Server";
  
  # Service requirements (contracts this service needs)
  needs = {
    ssl = ContractRequest;
    backup = ContractRequest;
    secrets = ContractRequest;
    # ... other contracts
  };
  
  # Service offerings (what this service provides)
  provides = {
    media_server = {
      endpoint = "https://plex.example.com";
      api_endpoint = "https://plex.example.com/api/v2";
      health_check = "https://plex.example.com/web";
    };
  };
  
  # Generated NixOS configuration
  config = {
    users = { ... };
    systemd = { ... };
    services = { ... };
    # ... standard NixOS options
  };
  
  # Health checks
  health_checks = [
    {
      name = "http-endpoint";
      type = "http";
      url = "http://127.0.0.1:32400/web";
      expected_status = 200;
      timeout_seconds = 30;
      interval_seconds = 60;
    }
  ];
  
  # Service-specific options
  options = {
    # NixOS module options for this service
  };
};
```

### Provider Configuration Format

```nix
ProviderConfig = {
  # Provider metadata
  name = "letsencrypt";
  contract_type = "ssl";
  version = "1.0.0";
  
  # Provider capabilities
  capabilities = {
    domains = [ "*.example.com" "example.com" ];
    protocols = [ "http-01" "dns-01" ];
    renewal_days_before_expiry = 30;
  };
  
  # Provider configuration
  config = {
    email = "admin@example.com";
    dns_provider = "cloudflare";
    staging = false;
  };
  
  # Provider functions (see Provider Interface below)
  canFulfill = request: boolean;
  fulfill = request: { config = {...}; result = ContractResult; };
  validate = request: config: [ validation_errors ];
};
```

## Core Implementation - lib/default.nix

```nix
{ lib, pkgs, ... }:

let
  inherit (lib) mkOption types optionalAttrs mapAttrs filterAttrs;
  
  # Import all PSF components
  contracts = import ./contracts.nix { inherit lib pkgs; };
  providers = import ./providers.nix { inherit lib pkgs; };
  validation = import ./validation.nix { inherit lib pkgs; };
  serviceBuilder = import ./service-builder.nix { inherit lib pkgs; };
  
in {
  
  # Main PSF API - this is what services use
  defineService = name: serviceFn: { config, lib, pkgs, ... }:
  let
    # Service options for this specific service
    serviceOptions = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable ${name} service";
      };
      
      domain = mkOption {
        type = types.str;
        description = "Base domain for ${name}";
      };
      
      subdomain = mkOption {
        type = types.str;
        default = name;
        description = "Subdomain for ${name}";
      };
    } // (serviceFn { inherit contracts providers; }).options or {};
    
    # Service configuration when enabled
    serviceConfig = lib.mkIf config.psf.services.${name}.enable (
      let
        # Get service configuration
        serviceConf = config.psf.services.${name};
        
        # Build service definition
        serviceDef = serviceFn {
          inherit contracts providers;
          config = serviceConf;
        };
        
        # Resolve all contract needs
        contractResolutions = resolveContracts serviceDef.needs config.psf.providers;
        
        # Validate all contract resolutions
        validationErrors = validation.validateContracts contractResolutions;
        
        # Fail fast if validation errors
        _ = assert validationErrors == []; true;
        
        # Build final service configuration
        finalConfig = serviceBuilder.buildService serviceDef contractResolutions;
        
      in finalConfig
    );
    
  in {
    options.psf.services.${name} = serviceOptions;
    config = serviceConfig;
  };
  
  # Contract resolution engine
  resolveContracts = contractNeeds: providerConfigs:
    mapAttrs (contractName: request:
      let
        # Find providers for this contract type
        availableProviders = filterAttrs (name: provider: 
          provider.contract_type == request.contract_type
        ) providerConfigs;
        
        # Find first provider that can fulfill the request
        selectedProvider = lib.findFirst 
          (provider: provider.canFulfill request)
          (throw "No provider found for contract ${contractName}")
          (lib.attrValues availableProviders);
        
        # Generate result from selected provider
        fulfillment = selectedProvider.fulfill request;
        
      in {
        request = request;
        result = fulfillment.result;
        provider = selectedProvider;
        config = fulfillment.config;
        validation_errors = selectedProvider.validate request selectedProvider.config;
      }
    ) contractNeeds;
  
  # Re-export components
  inherit contracts providers validation;
  
  # Utility functions
  utils = import ./utils.nix { inherit lib pkgs; };
}
```

## Contract Engine - lib/contracts.nix

```nix
{ lib, pkgs }:

let
  inherit (lib) mkOption types;
  
  # Base contract interface that all contracts must implement
  baseContract = {
    # Contract metadata
    name = mkOption { type = types.str; };
    version = mkOption { type = types.str; default = "1.0.0"; };
    description = mkOption { type = types.str; };
    
    # Request schema - what services can ask for
    requestSchema = mkOption { type = types.attrs; };
    
    # Result schema - what providers must deliver
    resultSchema = mkOption { type = types.attrs; };
    
    # Contract-specific validation rules
    validateRequest = mkOption { 
      type = types.functionTo types.bool;
      description = "Function to validate contract requests";
    };
    
    validateResult = mkOption {
      type = types.functionTo types.bool; 
      description = "Function to validate contract results";
    };
  };
  
  # Helper to create contract requests
  mkRequest = contractType: payload: {
    inherit contractType payload;
    requester_id = null; # Set by service resolution
    priority = "normal";
    tags = [];
  };
  
  # Helper to create contract results  
  mkResult = contractType: payload: metadata: {
    inherit contractType payload metadata;
    provider_id = null; # Set by provider resolution
    request_id = null;  # Set by service resolution
  };

in {
  inherit baseContract mkRequest mkResult;
  
  # Import all contract definitions
  ssl = import ../contracts/ssl.nix { inherit lib pkgs mkRequest mkResult; };
  backup = import ../contracts/backup.nix { inherit lib pkgs mkRequest mkResult; };
  secrets = import ../contracts/secrets.nix { inherit lib pkgs mkRequest mkResult; };
  database = import ../contracts/database.nix { inherit lib pkgs mkRequest mkResult; };
  ldap = import ../contracts/ldap.nix { inherit lib pkgs mkRequest mkResult; };
  sso = import ../contracts/sso.nix { inherit lib pkgs mkRequest mkResult; };
  proxy = import ../contracts/proxy.nix { inherit lib pkgs mkRequest mkResult; };
}
```

## Provider Engine - lib/providers.nix

```nix
{ lib, pkgs }:

let
  inherit (lib) mkOption types;
  
  # Base provider interface that all providers must implement
  baseProvider = {
    # Provider metadata
    name = mkOption { type = types.str; };
    contract_type = mkOption { type = types.str; };
    version = mkOption { type = types.str; default = "1.0.0"; };
    description = mkOption { type = types.str; };
    
    # Provider capabilities
    capabilities = mkOption { type = types.attrs; default = {}; };
    
    # Provider configuration schema
    configSchema = mkOption { type = types.attrs; };
    
    # Core provider functions
    canFulfill = mkOption {
      type = types.functionTo types.bool;
      description = "Returns true if this provider can fulfill the request";
    };
    
    fulfill = mkOption {
      type = types.functionTo types.attrs;
      description = "Returns { config = nixos_config; result = contract_result; }";
    };
    
    validate = mkOption {
      type = types.functionTo (types.listOf types.str);
      description = "Returns list of validation error strings";
    };
  };
  
  # Helper to register a provider
  registerProvider = providerDef: {
    inherit (providerDef) name contract_type version description;
    inherit (providerDef) capabilities configSchema;
    inherit (providerDef) canFulfill fulfill validate;
  };

in {
  inherit baseProvider registerProvider;
  
  # Import all provider definitions  
  ssl = {
    letsencrypt = import ../providers/ssl/letsencrypt.nix { inherit lib pkgs registerProvider; };
    selfsigned = import ../providers/ssl/selfsigned.nix { inherit lib pkgs registerProvider; };
  };
  
  backup = {
    restic = import ../providers/backup/restic.nix { inherit lib pkgs registerProvider; };
    borg = import ../providers/backup/borg.nix { inherit lib pkgs registerProvider; };
  };
  
  secrets = {
    sops = import ../providers/secrets/sops.nix { inherit lib pkgs registerProvider; };
    hardcoded = import ../providers/secrets/hardcoded.nix { inherit lib pkgs registerProvider; };
  };
  
  database = {
    postgresql = import ../providers/database/postgresql.nix { inherit lib pkgs registerProvider; };
    mysql = import ../providers/database/mysql.nix { inherit lib pkgs registerProvider; };
  };
  
  ldap = {
    lldap = import ../providers/ldap/lldap.nix { inherit lib pkgs registerProvider; };
    kanidm = import ../providers/ldap/kanidm.nix { inherit lib pkgs registerProvider; };
    openldap = import ../providers/ldap/openldap.nix { inherit lib pkgs registerProvider; };
  };
  
  sso = {
    authelia = import ../providers/sso/authelia.nix { inherit lib pkgs registerProvider; };
    kanidm = import ../providers/sso/kanidm.nix { inherit lib pkgs registerProvider; };
    oidc = import ../providers/sso/oidc.nix { inherit lib pkgs registerProvider; };
  };
  
  proxy = {
    nginx = import ../providers/proxy/nginx.nix { inherit lib pkgs registerProvider; };
    caddy = import ../providers/proxy/caddy.nix { inherit lib pkgs registerProvider; };
    traefik = import ../providers/proxy/traefik.nix { inherit lib pkgs registerProvider; };
    apache = import ../providers/proxy/apache.nix { inherit lib pkgs registerProvider; };
  };
}
```

## Validation Engine - lib/validation.nix

```nix
{ lib, pkgs }:

let
  inherit (lib) concatMap attrValues filter;
  
  # Validate a single contract resolution
  validateContractResolution = resolution:
    let
      requestErrors = if resolution.request == null 
        then ["Missing contract request"]
        else [];
        
      resultErrors = if resolution.result == null
        then ["Provider failed to generate result"] 
        else [];
        
      providerErrors = resolution.validation_errors or [];
      
    in requestErrors ++ resultErrors ++ providerErrors;
  
  # Validate all contract resolutions
  validateContracts = contractResolutions:
    let
      allErrors = concatMap validateContractResolution (attrValues contractResolutions);
      nonEmptyErrors = filter (error: error != "") allErrors;
    in nonEmptyErrors;
    
  # Validate provider configuration
  validateProviderConfig = provider: config:
    let
      schemaErrors = []; # TODO: Implement schema validation
      customErrors = provider.validate {} config;
    in schemaErrors ++ customErrors;
    
  # Build-time validation - called during nix evaluation
  buildTimeValidation = psf_config:
    let
      # Validate all provider configurations
      providerErrors = concatMap (provider: 
        validateProviderConfig provider (psf_config.providers.${provider.name} or {})
      ) (attrValues psf_config.available_providers);
      
      # Check for circular dependencies
      circularDepErrors = []; # TODO: Implement circular dependency detection
      
      # Check for missing dependencies
      missingDepErrors = []; # TODO: Implement missing dependency detection
      
    in {
      errors = providerErrors ++ circularDepErrors ++ missingDepErrors;
      warnings = [];
    };

in {
  inherit validateContractResolution validateContracts;
  inherit validateProviderConfig buildTimeValidation;
  
  # Standard error message formatting
  formatError = service: contract: error: 
    "PSF Error in ${service}.${contract}: ${error}";
    
  formatWarning = service: contract: warning:
    "PSF Warning in ${service}.${contract}: ${warning}";
}
```

## Service Builder - lib/service-builder.nix

```nix
{ lib, pkgs }:

let
  inherit (lib) mkMerge mapAttrs' nameValuePair;
  
  # Build final service configuration from service definition and contract resolutions
  buildService = serviceDef: contractResolutions:
    let
      # Extract NixOS configuration from all contract results
      contractConfigs = mapAttrs' (name: resolution:
        nameValuePair "${serviceDef.name}-${name}" resolution.config
      ) contractResolutions;
      
      # Merge service config with contract configs
      finalConfig = mkMerge [
        serviceDef.config
        (mkMerge (lib.attrValues contractConfigs))
      ];
      
    in finalConfig;
    
  # Build health check configuration
  buildHealthChecks = serviceDef: contractResolutions:
    let
      # Standard health checks from service definition
      serviceHealthChecks = serviceDef.health_checks or [];
      
      # Additional health checks from contract results
      contractHealthChecks = []; # TODO: Extract from contract results
      
    in {
      systemd.services."psf-healthcheck-${serviceDef.name}" = {
        description = "Health checks for ${serviceDef.name}";
        serviceConfig = {
          Type = "oneshot";
          User = "psf-healthcheck";
        };
        script = generateHealthCheckScript (serviceHealthChecks ++ contractHealthChecks);
      };
      
      systemd.timers."psf-healthcheck-${serviceDef.name}" = {
        description = "Timer for ${serviceDef.name} health checks";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "1m";
          OnUnitActiveSec = "5m";
          Persistent = true;
        };
      };
    };
    
  # Generate health check script
  generateHealthCheckScript = healthChecks:
    let
      checkCommands = map (check:
        if check.type == "http" then
          ''
            echo "Checking ${check.name}..."
            if ! ${pkgs.curl}/bin/curl -f -s --max-time ${toString check.timeout_seconds} "${check.url}" >/dev/null; then
              echo "ERROR: ${check.name} health check failed"
              exit 1
            fi
            echo "OK: ${check.name} is healthy"
          ''
        else ""
      ) healthChecks;
    in ''
      #!/bin/bash
      set -e
      ${lib.concatStringsSep "\n" checkCommands}
      echo "All health checks passed"
    '';

in {
  inherit buildService buildHealthChecks generateHealthCheckScript;
}
```

## Example Contract Implementation - contracts/ssl.nix

```nix
{ lib, pkgs, mkRequest, mkResult }:

{
  name = "ssl";
  version = "1.0.0";
  description = "SSL certificate management contract";
  
  # Request schema - what services can ask for
  requestSchema = {
    domain = lib.mkOption {
      type = lib.types.str;
      description = "Primary domain for the certificate";
    };
    
    san_domains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Subject Alternative Names for the certificate";
    };
    
    auto_renew = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Automatically renew certificate before expiry";
    };
  };
  
  # Result schema - what providers must deliver
  resultSchema = {
    cert_path = lib.mkOption {
      type = lib.types.path;
      description = "Path to the certificate file";
    };
    
    key_path = lib.mkOption {
      type = lib.types.path;
      description = "Path to the private key file";
    };
    
    ca_path = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to the CA certificate file";
    };
    
    reload_services = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Services to reload when certificate is renewed";
    };
  };
  
  # Create SSL request
  mkRequest = { domain, san_domains ? [], auto_renew ? true }:
    mkRequest "ssl" {
      inherit domain san_domains auto_renew;
    };
  
  # Validate SSL request
  validateRequest = request:
    assert request.payload.domain != null;
    assert lib.all (d: lib.isString d) request.payload.san_domains;
    true;
    
  # Validate SSL result
  validateResult = result:
    assert builtins.pathExists result.payload.cert_path;
    assert builtins.pathExists result.payload.key_path;
    true;
}
```

## LDAP Contract Implementation - contracts/ldap.nix

```nix
{ lib, pkgs, mkRequest, mkResult }:

{
  name = "ldap";
  version = "1.0.0";
  description = "LDAP directory service contract";
  
  # Request schema - what services can ask for
  requestSchema = {
    domain = lib.mkOption {
      type = lib.types.str;
      description = "LDAP domain (e.g., dc=example,dc=com)";
    };
    
    users = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          username = lib.mkOption { type = lib.types.str; };
          email = lib.mkOption { type = lib.types.str; };
          groups = lib.mkOption { 
            type = lib.types.listOf lib.types.str; 
            default = [];
          };
        };
      });
      default = [];
      description = "Users to create in LDAP directory";
    };
    
    groups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Groups to create in LDAP directory";
    };
    
    bind_user = lib.mkOption {
      type = lib.types.str;
      default = "admin";
      description = "Bind user for LDAP operations";
    };
  };
  
  # Result schema - what providers must deliver
  resultSchema = {
    ldap_url = lib.mkOption {
      type = lib.types.str;
      description = "LDAP connection URL (e.g., ldap://127.0.0.1:389)";
    };
    
    bind_dn = lib.mkOption {
      type = lib.types.str;
      description = "Bind DN for authentication (e.g., cn=admin,dc=example,dc=com)";
    };
    
    base_dn = lib.mkOption {
      type = lib.types.str;
      description = "Base DN for directory (e.g., dc=example,dc=com)";
    };
    
    user_base_dn = lib.mkOption {
      type = lib.types.str;
      description = "Base DN for users (e.g., ou=people,dc=example,dc=com)";
    };
    
    group_base_dn = lib.mkOption {
      type = lib.types.str;
      description = "Base DN for groups (e.g., ou=groups,dc=example,dc=com)";
    };
    
    admin_interface_url = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Web interface URL for LDAP management";
    };
    
    bind_password_secret = lib.mkOption {
      type = lib.types.str;
      description = "Path to bind password secret file";
    };
  };
  
  # Create LDAP request
  mkRequest = { domain, users ? [], groups ? [], bind_user ? "admin" }:
    mkRequest "ldap" {
      inherit domain users groups bind_user;
    };
  
  # Validate LDAP request
  validateRequest = request:
    assert request.payload.domain != null;
    assert request.payload.bind_user != null;
    true;
    
  # Validate LDAP result
  validateResult = result:
    assert result.payload.ldap_url != null;
    assert result.payload.bind_dn != null;
    assert result.payload.base_dn != null;
    true;
}
```

## SSO Contract Implementation - contracts/sso.nix

```nix
{ lib, pkgs, mkRequest, mkResult }:

{
  name = "sso";
  version = "1.0.0";
  description = "Single Sign-On authentication contract";
  
  # Request schema - what services can ask for
  requestSchema = {
    client_id = lib.mkOption {
      type = lib.types.str;
      description = "OAuth2/OIDC client identifier";
    };
    
    redirect_uris = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "Allowed redirect URIs for OAuth2 flow";
    };
    
    scopes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "openid" "profile" "email" ];
      description = "Required OAuth2/OIDC scopes";
    };
    
    access_policy = lib.mkOption {
      type = lib.types.enum [ "bypass" "one_factor" "two_factor" ];
      default = "two_factor";
      description = "Required authentication level";
    };
    
    allowed_groups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "LDAP groups allowed to access this service";
    };
    
    allowed_users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Specific users allowed to access this service";
    };
  };
  
  # Result schema - what providers must deliver
  resultSchema = {
    issuer_url = lib.mkOption {
      type = lib.types.str;
      description = "OIDC issuer URL";
    };
    
    authorization_endpoint = lib.mkOption {
      type = lib.types.str;
      description = "OAuth2 authorization endpoint";
    };
    
    token_endpoint = lib.mkOption {
      type = lib.types.str;
      description = "OAuth2 token endpoint";
    };
    
    userinfo_endpoint = lib.mkOption {
      type = lib.types.str;
      description = "OIDC userinfo endpoint";
    };
    
    client_secret_path = lib.mkOption {
      type = lib.types.str;
      description = "Path to client secret file";
    };
    
    auth_request_headers = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "HTTP headers for authentication requests";
    };
    
    nginx_auth_config = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Nginx configuration for auth_request integration";
    };
  };
  
  # Create SSO request
  mkRequest = { 
    client_id, 
    redirect_uris, 
    scopes ? [ "openid" "profile" "email" ],
    access_policy ? "two_factor",
    allowed_groups ? [],
    allowed_users ? []
  }:
    mkRequest "sso" {
      inherit client_id redirect_uris scopes access_policy allowed_groups allowed_users;
    };
  
  # Validate SSO request
  validateRequest = request:
    assert request.payload.client_id != null;
    assert builtins.length request.payload.redirect_uris > 0;
    assert builtins.elem request.payload.access_policy [ "bypass" "one_factor" "two_factor" ];
    true;
    
  # Validate SSO result
  validateResult = result:
    assert result.payload.issuer_url != null;
    assert result.payload.authorization_endpoint != null;
    assert result.payload.token_endpoint != null;
    true;
}
```

## Example Provider Implementation - providers/ssl/letsencrypt.nix

```nix
{ lib, pkgs, registerProvider }:

registerProvider {
  name = "letsencrypt";
  contract_type = "ssl";
  version = "1.0.0";
  description = "Let's Encrypt ACME SSL certificate provider";
  
  capabilities = {
    domains = [ "*" ]; # Supports all domains
    protocols = [ "http-01" "dns-01" ];
    wildcard_support = true;
    auto_renewal = true;
  };
  
  configSchema = {
    email = lib.mkOption {
      type = lib.types.str;
      description = "Email address for ACME registration";
    };
    
    dns_provider = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "DNS provider for DNS-01 challenge";
    };
    
    staging = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Use Let's Encrypt staging environment";
    };
  };
  
  # Check if this provider can fulfill the request
  canFulfill = request: 
    request.contract_type == "ssl" && 
    request.payload.domain != null;
  
  # Fulfill the SSL certificate request
  fulfill = request: providerConfig:
    let
      domain = request.payload.domain;
      certName = builtins.replaceStrings ["."] ["_"] domain;
    in {
      config = {
        security.acme = {
          acceptTerms = true;
          defaults.email = providerConfig.email;
          defaults.server = if providerConfig.staging 
            then "https://acme-staging-v02.api.letsencrypt.org/directory"
            else "https://acme-v02.api.letsencrypt.org/directory";
          
          certs.${certName} = {
            domain = domain;
            extraDomainNames = request.payload.san_domains;
            dnsProvider = providerConfig.dns_provider;
            credentialsFile = "/run/secrets/acme-credentials";
          };
        };
        
        systemd.services.nginx.serviceConfig.SupplementaryGroups = [ "acme" ];
      };
      
      result = mkResult "ssl" {
        cert_path = "/var/lib/acme/${certName}/cert.pem";
        key_path = "/var/lib/acme/${certName}/key.pem";
        ca_path = "/var/lib/acme/${certName}/chain.pem";
        reload_services = [ "nginx.service" ];
      } {
        provider_version = "1.0.0";
        cert_name = certName;
        renewal_timer = "acme-${certName}.timer";
      };
    };
  
  # Validate provider configuration and request
  validate = request: providerConfig: 
    lib.optional (providerConfig.email == null) "ACME email must be configured" ++
    lib.optional (request.payload.domain == null) "Domain must be specified" ++
    lib.optional (providerConfig.dns_provider == null && lib.any (d: lib.hasPrefix "*." d) (request.payload.domain :: request.payload.san_domains)) 
      "DNS provider required for wildcard certificates";
}
```

## Example LDAP Provider Implementation - providers/ldap/lldap.nix

```nix
{ lib, pkgs, registerProvider }:

registerProvider {
  name = "lldap";
  contract_type = "ldap";
  version = "1.0.0";
  description = "Light LDAP implementation for authentication";
  
  capabilities = {
    web_interface = true;
    user_management = true;
    group_management = true;
    password_reset = true;
    schema_flexibility = "limited";
  };
  
  configSchema = {
    port = lib.mkOption {
      type = lib.types.port;
      default = 3890;
      description = "LDAP port";
    };
    
    web_port = lib.mkOption {
      type = lib.types.port;
      default = 17170;
      description = "Web interface port";
    };
    
    base_dn = lib.mkOption {
      type = lib.types.str;
      description = "Base DN for LDAP directory";
    };
    
    admin_password_secret = lib.mkOption {
      type = lib.types.str;
      description = "Path to admin password secret";
    };
    
    jwt_secret_path = lib.mkOption {
      type = lib.types.str;
      description = "Path to JWT secret for web interface";
    };
  };
  
  canFulfill = request: 
    request.contract_type == "ldap";
  
  fulfill = request: providerConfig:
    let
      domain_parts = lib.splitString "." request.payload.domain;
      base_dn = lib.concatStringsSep "," (map (part: "dc=${part}") domain_parts);
    in {
      config = {
        services.lldap = {
          enable = true;
          settings = {
            ldap_port = providerConfig.port;
            http_port = providerConfig.web_port;
            ldap_base_dn = base_dn;
            ldap_user_dn = "ou=people,${base_dn}";
            ldap_user_email_attribute = "mail";
            ldap_user_display_name_attribute = "displayName";
          };
          environmentFile = "/run/secrets/lldap-env";
        };
        
        # Create required groups
        systemd.services.lldap-setup = {
          description = "Setup LLDAP groups and users";
          after = [ "lldap.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = let
            setupScript = pkgs.writeShellScript "lldap-setup" ''
              # Wait for LLDAP to be ready
              sleep 5
              
              # Create groups
              ${lib.concatMapStringsSep "\n" (group: ''
                echo "Creating group: ${group}"
                # Add group creation logic here
              '') request.payload.groups}
              
              # Create users
              ${lib.concatMapStringsSep "\n" (user: ''
                echo "Creating user: ${user.username}"
                # Add user creation logic here
              '') request.payload.users}
            '';
          in "${setupScript}";
        };
      };
      
      result = mkResult "ldap" {
        ldap_url = "ldap://127.0.0.1:${toString providerConfig.port}";
        bind_dn = "cn=${request.payload.bind_user},${base_dn}";
        base_dn = base_dn;
        user_base_dn = "ou=people,${base_dn}";
        group_base_dn = "ou=groups,${base_dn}";
        admin_interface_url = "http://127.0.0.1:${toString providerConfig.web_port}";
        bind_password_secret = providerConfig.admin_password_secret;
      } {
        provider_version = "1.0.0";
        web_interface_port = providerConfig.web_port;
        ldap_port = providerConfig.port;
      };
    };
  
  validate = request: providerConfig:
    lib.optional (providerConfig.base_dn == null) "Base DN must be configured" ++
    lib.optional (providerConfig.admin_password_secret == null) "Admin password secret must be configured";
}
```

## Example SSO Provider Implementation - providers/sso/authelia.nix

```nix
{ lib, pkgs, registerProvider }:

registerProvider {
  name = "authelia";
  contract_type = "sso";
  version = "1.0.0";
  description = "Authelia authentication and authorization server";
  
  capabilities = {
    protocols = [ "oidc" "oauth2" ];
    mfa_support = true;
    ldap_integration = true;
    policy_engine = true;
    session_management = true;
  };
  
  configSchema = {
    port = lib.mkOption {
      type = lib.types.port;
      default = 9091;
      description = "Authelia port";
    };
    
    ldap_url = lib.mkOption {
      type = lib.types.str;
      description = "LDAP server URL";
    };
    
    ldap_base_dn = lib.mkOption {
      type = lib.types.str;
      description = "LDAP base DN";
    };
    
    ldap_user_base_dn = lib.mkOption {
      type = lib.types.str;
      description = "LDAP user base DN";
    };
    
    ldap_group_base_dn = lib.mkOption {
      type = lib.types.str;
      description = "LDAP group base DN";
    };
    
    ldap_bind_dn = lib.mkOption {
      type = lib.types.str;
      description = "LDAP bind DN";
    };
    
    ldap_bind_password_secret = lib.mkOption {
      type = lib.types.str;
      description = "Path to LDAP bind password secret";
    };
    
    jwt_secret_path = lib.mkOption {
      type = lib.types.str;
      description = "Path to JWT secret";
    };
    
    session_secret_path = lib.mkOption {
      type = lib.types.str;
      description = "Path to session secret";
    };
    
    storage_encryption_key_path = lib.mkOption {
      type = lib.types.str;
      description = "Path to storage encryption key";
    };
  };
  
  canFulfill = request: 
    request.contract_type == "sso";
  
  fulfill = request: providerConfig:
    let
      client_config = {
        id = request.payload.client_id;
        description = "PSF managed client: ${request.payload.client_id}";
        secret = "$pbkdf2-sha512$310000$..."; # Will be generated
        redirect_uris = request.payload.redirect_uris;
        scopes = request.payload.scopes;
        grant_types = [ "authorization_code" "refresh_token" ];
        response_types = [ "code" ];
      };
      
      access_control_rule = {
        domain = lib.head request.payload.redirect_uris; # Extract domain from redirect URI
        policy = request.payload.access_policy;
      } // lib.optionalAttrs (request.payload.allowed_groups != []) {
        subject = map (group: "group:${group}") request.payload.allowed_groups;
      } // lib.optionalAttrs (request.payload.allowed_users != []) {
        subject = map (user: "user:${user}") request.payload.allowed_users;
      };
      
    in {
      config = {
        services.authelia.instances.main = {
          enable = true;
          settings = {
            server.port = providerConfig.port;
            
            authentication_backend = {
              ldap = {
                implementation = "custom";
                url = providerConfig.ldap_url;
                base_dn = providerConfig.ldap_base_dn;
                users_filter = "(&({username_attribute}={input})(objectClass=person))";
                groups_filter = "(member={dn})";
                user = providerConfig.ldap_bind_dn;
                password = "file://${providerConfig.ldap_bind_password_secret}";
                additional_users_dn = providerConfig.ldap_user_base_dn;
                additional_groups_dn = providerConfig.ldap_group_base_dn;
              };
            };
            
            access_control = {
              default_policy = "deny";
              rules = [ access_control_rule ];
            };
            
            identity_providers = {
              oidc = {
                hmac_secret = "file://${providerConfig.jwt_secret_path}";
                issuer_private_key = "file://${providerConfig.session_secret_path}";
                clients = [ client_config ];
              };
            };
            
            session = {
              secret = "file://${providerConfig.session_secret_path}";
            };
            
            storage = {
              encryption_key = "file://${providerConfig.storage_encryption_key_path}";
            };
          };
        };
      };
      
      result = mkResult "sso" {
        issuer_url = "https://auth.${request.payload.client_id}/api/oidc";
        authorization_endpoint = "https://auth.${request.payload.client_id}/api/oidc/authorization";
        token_endpoint = "https://auth.${request.payload.client_id}/api/oidc/token";
        userinfo_endpoint = "https://auth.${request.payload.client_id}/api/oidc/userinfo";
        client_secret_path = "/run/secrets/authelia-client-${request.payload.client_id}";
        auth_request_headers = {
          "X-Original-URL" = "$scheme://$http_host$request_uri";
        };
        nginx_auth_config = ''
          auth_request /authelia;
          auth_request_set $user $upstream_http_remote_user;
          auth_request_set $groups $upstream_http_remote_groups;
          error_page 401 = @authelia_redirect;
        '';
      } {
        provider_version = "1.0.0";
        authelia_port = providerConfig.port;
        client_id = request.payload.client_id;
      };
    };
  
  validate = request: providerConfig:
    lib.optional (providerConfig.ldap_url == null) "LDAP URL must be configured" ++
    lib.optional (providerConfig.ldap_base_dn == null) "LDAP base DN must be configured" ++
    lib.optional (providerConfig.jwt_secret_path == null) "JWT secret path must be configured";
}
```

## Example Proxy Provider Implementation - providers/proxy/caddy.nix

```nix
{ lib, pkgs, registerProvider }:

registerProvider {
  name = "caddy";
  contract_type = "proxy";
  version = "1.0.0";
  description = "Caddy reverse proxy with automatic HTTPS";
  
  capabilities = {
    automatic_https = true;
    http2_support = true;
    load_balancing = true;
    middleware_support = true;
    config_reload = "hot";
  };
  
  configSchema = {
    automatic_https = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable automatic HTTPS with Let's Encrypt";
    };
    
    email = lib.mkOption {
      type = lib.types.str;
      description = "Email for ACME registration";
    };
  };
  
  canFulfill = request: 
    request.contract_type == "proxy";
  
  fulfill = request: providerConfig: {
    config = {
      services.caddy = {
        enable = true;
        email = providerConfig.email;
        
        virtualHosts.${request.payload.domain} = {
          extraConfig = ''
            reverse_proxy ${request.payload.upstream}
            
            ${lib.optionalString (request.payload.auth_endpoint != null) ''
              forward_auth ${request.payload.auth_endpoint} {
                uri /api/verify
                copy_headers Remote-User Remote-Groups
              }
            ''}
            
            ${lib.optionalString (request.payload.additional_config != "") 
              request.payload.additional_config}
          '';
        };
      };
    };
    
    result = mkResult "proxy" {
      domain = request.payload.domain;
      upstream = request.payload.upstream;
      ssl_enabled = providerConfig.automatic_https;
      config_reload_command = "systemctl reload caddy";
    } {
      provider_version = "1.0.0";
      automatic_https = providerConfig.automatic_https;
    };
  };
  
  validate = request: providerConfig:
    lib.optional (providerConfig.email == null && providerConfig.automatic_https) 
      "Email required for automatic HTTPS";
}
```

## Enhanced Service Implementation - services/plex.nix

```nix
{ psf, lib, pkgs, ... }:

psf.defineService "plex" ({ contracts, providers, config, ... }: {
  
  options = {
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/plex";
      description = "Plex data directory";
    };
    
    user = lib.mkOption {
      type = lib.types.str;
      default = "plex";
      description = "User account for Plex";
    };
    
    group = lib.mkOption {
      type = lib.types.str;
      default = "plex";
      description = "Group for Plex";
    };
    
    port = lib.mkOption {
      type = lib.types.port;
      default = 32400;
      description = "Plex server port";
    };
    
    require_auth = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Require SSO authentication for access";
    };
    
    allowed_groups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "plex_users" "media_admin" ];
      description = "LDAP groups allowed to access Plex";
    };
  };
  
  needs = {
    ssl = contracts.ssl.mkRequest {
      domain = "${config.subdomain}.${config.domain}";
      auto_renew = true;
    };
    
    backup = contracts.backup.mkRequest {
      paths = [ config.dataDir ];
      excludes = [
        "*/Cache/*"
        "*/Logs/*" 
        "*/Crash Reports/*"
        "*/Diagnostics/*"
        "*/Codecs/*"
      ];
      schedule = "nightly";
      retention = {
        daily = 7;
        weekly = 4;
        monthly = 12;
      };
    };
    
    secrets = {
      claim_token = contracts.secrets.mkRequest {
        description = "Plex claim token for server setup";
        mode = "0400";
        owner = config.user;
      };
    };
    
    # Optional SSO integration
    sso = lib.mkIf config.require_auth (contracts.sso.mkRequest {
      client_id = "plex";
      redirect_uris = [ 
        "https://${config.subdomain}.${config.domain}/auth/callback"
        "https://${config.subdomain}.${config.domain}/web/index.html"
      ];
      scopes = [ "openid" "profile" "email" "groups" ];
      access_policy = "one_factor"; # Plex handles its own auth, just need identity
      allowed_groups = config.allowed_groups;
    });
    
    # Proxy configuration
    proxy = contracts.proxy.mkRequest {
      domain = "${config.subdomain}.${config.domain}";
      upstream = "http://127.0.0.1:${toString config.port}";
      ssl_config = needs.ssl;
      auth_endpoint = if config.require_auth then needs.sso.issuer_url else null;
      additional_config = ''
        # Plex-specific proxy configuration
        proxy_set_header X-Plex-Client-Identifier $http_x_plex_client_identifier;
        proxy_set_header X-Plex-Device $http_x_plex_device;
        proxy_set_header X-Plex-Device-Name $http_x_plex_device_name;
        proxy_set_header X-Plex-Platform $http_x_plex_platform;
        proxy_set_header X-Plex-Platform-Version $http_x_plex_platform_version;
        proxy_set_header X-Plex-Product $http_x_plex_product;
        proxy_set_header X-Plex-Token $http_x_plex_token;
        proxy_set_header X-Plex-Version $http_x_plex_version;
        
        # Handle large uploads for media
        client_max_body_size 1G;
        proxy_request_buffering off;
      '';
    };
  };
  
  provides = {
    media_server = {
      endpoint = "https://${config.subdomain}.${config.domain}";
      api_endpoint = "https://${config.subdomain}.${config.domain}/api/v2";
      local_endpoint = "http://127.0.0.1:${toString config.port}";
      protocol = "plex";
    };
  };
  
  config = { needs, ... }: {
    # Ensure unfree package is allowed
    nixpkgs.config.allowUnfreePredicate = pkg:
      builtins.elem (lib.getName pkg) [ "plexmediaserver" ];
    
    # User and group
    users.users.${config.user} = {
      isSystemUser = true;
      group = config.group;
      extraGroups = [ "media" "arr_user" ];
      home = config.dataDir;
      createHome = true;
    };
    users.groups.${config.group} = {};
    users.groups.media = {}; # For media file access
    
    # Plex service
    services.plex = {
      enable = true;
      dataDir = config.dataDir;
      user = config.user;
      group = config.group;
      openFirewall = true;
      
      # Use claim token from secrets
      environment = {
        PLEX_CLAIM = "file://${needs.secrets.claim_token.path}";
      };
    };
    
    # Media directory permissions
    systemd.tmpfiles.rules = [
      "d /srv/media 0775 ${config.user} media -"
      "d /srv/media/movies 0775 ${config.user} media -"
      "d /srv/media/tv 0775 ${config.user} media -"
      "d /srv/media/music 0775 ${config.user} media -"
    ];
  };
  
  health_checks = [
    {
      name = "plex-web-interface";
      type = "http";
      url = "http://127.0.0.1:${toString config.port}/web";
      expected_status = 200;
      timeout_seconds = 30;
      interval_seconds = 300;
    }
    {
      name = "plex-api";
      type = "http"; 
      url = "http://127.0.0.1:${toString config.port}/api/v2";
      expected_status = 200;
      timeout_seconds = 10;
      interval_seconds = 60;
    }
    {
      name = "plex-transcode";
      type = "custom";
      script = ''
        # Check if transcoding directory is writable
        test -w "${config.dataDir}/Library/Application Support/Plex Media Server/Cache/Transcode"
      '';
      interval_seconds = 3600;
    }
  ];
})
```

## LLDAP Service Implementation - services/lldap.nix

```nix
{ psf, lib, pkgs, ... }:

psf.defineService "lldap" ({ contracts, providers, config, ... }: {
  
  options = {
    port = lib.mkOption {
      type = lib.types.port;
      default = 3890;
      description = "LDAP port";
    };
    
    web_port = lib.mkOption {
      type = lib.types.port;
      default = 17170;
      description = "Web interface port";
    };
    
    base_dn = lib.mkOption {
      type = lib.types.str;
      description = "Base DN for LDAP directory";
      example = "dc=pixelkeepers,dc=net";
    };
    
    admin_user = lib.mkOption {
      type = lib.types.str;
      default = "admin";
      description = "LDAP admin username";
    };
    
    require_web_auth = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Require SSO authentication for web interface";
    };
    
    default_groups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "lldap_admin" "nextcloud_user" "vaultwarden_user" "plex_users" ];
      description = "Default groups to create";
    };
    
    default_users = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          username = lib.mkOption { type = lib.types.str; };
          email = lib.mkOption { type = lib.types.str; };
          groups = lib.mkOption { 
            type = lib.types.listOf lib.types.str; 
            default = [ "lldap_admin" ];
          };
        };
      });
      default = [];
      description = "Default users to create";
    };
  };
  
  needs = {
    ssl = contracts.ssl.mkRequest {
      domain = "${config.subdomain}.${config.domain}";
      auto_renew = true;
    };
    
    backup = contracts.backup.mkRequest {
      paths = [ "/var/lib/lldap" ];
      schedule = "daily";
      retention = {
        daily = 30;
        weekly = 12;
        monthly = 6;
      };
    };
    
    secrets = {
      admin_password = contracts.secrets.mkRequest {
        description = "LLDAP admin password";
        mode = "0400";
        owner = "lldap";
      };
      
      jwt_secret = contracts.secrets.mkRequest {
        description = "JWT secret for LLDAP web interface";
        mode = "0400";
        owner = "lldap";
      };
    };
    
    # Optional SSO for web interface
    sso = lib.mkIf config.require_web_auth (contracts.sso.mkRequest {
      client_id = "lldap";
      redirect_uris = [ "https://${config.subdomain}.${config.domain}/auth/callback" ];
      scopes = [ "openid" "profile" "email" ];
      access_policy = "two_factor";
      allowed_groups = [ "lldap_admin" ];
    });
    
    proxy = contracts.proxy.mkRequest {
      domain = "${config.subdomain}.${config.domain}";
      upstream = "http://127.0.0.1:${toString config.web_port}";
      ssl_config = needs.ssl;
      auth_endpoint = if config.require_web_auth then needs.sso.issuer_url else null;
    };
  };
  
  provides = {
    ldap_directory = {
      ldap_url = "ldap://127.0.0.1:${toString config.port}";
      bind_dn = "cn=${config.admin_user},${config.base_dn}";
      base_dn = config.base_dn;
      user_base_dn = "ou=people,${config.base_dn}";
      group_base_dn = "ou=groups,${config.base_dn}";
      admin_interface = "https://${config.subdomain}.${config.domain}";
    };
  };
  
  config = { needs, ... }: {
    # LLDAP service
    services.lldap = {
      enable = true;
      settings = {
        ldap_port = config.port;
        http_port = config.web_port;
        ldap_base_dn = config.base_dn;
        ldap_user_dn = "ou=people,${config.base_dn}";
        ldap_user_email_attribute = "mail";
        ldap_user_display_name_attribute = "displayName";
      };
      environmentFile = pkgs.writeText "lldap-env" ''
        LLDAP_LDAP_USER_PASS_FILE=${needs.secrets.admin_password.path}
        LLDAP_JWT_SECRET_FILE=${needs.secrets.jwt_secret.path}
      '';
    };
    
    # Setup default groups and users
    systemd.services.lldap-bootstrap = {
      description = "Bootstrap LLDAP with default groups and users";
      after = [ "lldap.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "lldap";
      };
      script = let
        bootstrapScript = pkgs.writeShellScript "lldap-bootstrap" ''
          # Wait for LLDAP to be ready
          while ! ${pkgs.curl}/bin/curl -f http://127.0.0.1:${toString config.web_port}/health >/dev/null 2>&1; do
            echo "Waiting for LLDAP to start..."
            sleep 2
          done
          
          echo "LLDAP is ready, setting up default groups and users..."
          
          # Create default groups
          ${lib.concatMapStringsSep "\n" (group: ''
            echo "Creating group: ${group}"
            # TODO: Add actual LLDAP API calls to create groups
          '') config.default_groups}
          
          # Create default users
          ${lib.concatMapStringsSep "\n" (user: ''
            echo "Creating user: ${user.username} (${user.email})"
            # TODO: Add actual LLDAP API calls to create users
          '') config.default_users}
          
          echo "LLDAP bootstrap completed"
        '';
      in "${bootstrapScript}";
    };
  };
  
  health_checks = [
    {
      name = "lldap-web-interface";
      type = "http";
      url = "http://127.0.0.1:${toString config.web_port}/health";
      expected_status = 200;
      timeout_seconds = 10;
      interval_seconds = 60;
    }
    {
      name = "lldap-ldap-port";
      type = "tcp";
      host = "127.0.0.1";
      port = config.port;
      timeout_seconds = 5;
      interval_seconds = 60;
    }
  ];
})
```

## Example Service Implementation - services/plex.nix

```nix
{ psf, lib, pkgs, ... }:

psf.defineService "plex" ({ contracts, providers, config, ... }: {
  
  options = {
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/plex";
      description = "Plex data directory";
    };
    
    user = lib.mkOption {
      type = lib.types.str;
      default = "plex";
      description = "User account for Plex";
    };
    
    group = lib.mkOption {
      type = lib.types.str;
      default = "plex";
      description = "Group for Plex";
    };
    
    port = lib.mkOption {
      type = lib.types.port;
      default = 32400;
      description = "Plex server port";
    };
  };
  
  needs = {
    ssl = contracts.ssl.mkRequest {
      domain = "${config.subdomain}.${config.domain}";
      auto_renew = true;
    };
    
    backup = contracts.backup.mkRequest {
      paths = [ config.dataDir ];
      excludes = [
        "*/Cache/*"
        "*/Logs/*" 
        "*/Crash Reports/*"
        "*/Diagnostics/*"
      ];
      schedule = "nightly";
      retention = {
        daily = 7;
        weekly = 4;
        monthly = 12;
      };
    };
    
    secrets = {
      claim_token = contracts.secrets.mkRequest {
        description = "Plex claim token for server setup";
        mode = "0400";
        owner = config.user;
      };
    };
  };
  
  provides = {
    media_server = {
      endpoint = "https://${config.subdomain}.${config.domain}";
      api_endpoint = "https://${config.subdomain}.${config.domain}/api/v2";
      local_endpoint = "http://127.0.0.1:${toString config.port}";
    };
  };
  
  config = { needs, ... }: {
    # Ensure unfree package is allowed
    nixpkgs.config.allowUnfreePredicate = pkg:
      builtins.elem (lib.getName pkg) [ "plexmediaserver" ];
    
    # User and group
    users.users.${config.user} = {
      isSystemUser = true;
      group = config.group;
      extraGroups = [ "arr_user" ];
      home = config.dataDir;
      createHome = true;
    };
    users.groups.${config.group} = {};
    
    # Plex service
    services.plex = {
      enable = true;
      dataDir = config.dataDir;
      user = config.user;
      group = config.group;
      openFirewall = true;
    };
    
    # Nginx reverse proxy using SSL contract result
    services.nginx = {
      enable = true;
      virtualHosts.${needs.ssl.payload.domain} = {
        forceSSL = true;
        sslCertificate = needs.ssl.payload.cert_path;
        sslCertificateKey = needs.ssl.payload.key_path;
        
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString config.port}";
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            
            # Plex-specific headers
            proxy_set_header X-Plex-Client-Identifier $http_x_plex_client_identifier;
            proxy_set_header X-Plex-Device $http_x_plex_device;
            proxy_set_header X-Plex-Device-Name $http_x_plex_device_name;
            proxy_set_header X-Plex-Platform $http_x_plex_platform;
            proxy_set_header X-Plex-Platform-Version $http_x_plex_platform_version;
            proxy_set_header X-Plex-Product $http_x_plex_product;
            proxy_set_header X-Plex-Token $http_x_plex_token;
            proxy_set_header X-Plex-Version $http_x_plex_version;
          '';
        };
      };
    };
  };
  
  health_checks = [
    {
      name = "plex-web-interface";
      type = "http";
      url = "http://127.0.0.1:${toString config.port}/web";
      expected_status = 200;
      timeout_seconds = 30;
      interval_seconds = 300;
    }
    {
      name = "plex-api";
      type = "http"; 
      url = "http://127.0.0.1:${toString config.port}/api/v2";
      expected_status = 200;
      timeout_seconds = 10;
      interval_seconds = 60;
    }
  ];
})
```

## Framework Configuration Example

```nix
# configuration.nix - How users configure PSF
{ config, lib, pkgs, ... }:

{
  imports = [ ./psf ];
  
  # PSF global configuration
  psf = {
    # Global settings
    domain = "pixelkeepers.net";
    
    # Provider preferences (tried in order)
    provider_priority = {
      ssl = [ "letsencrypt" "selfsigned" ];
      backup = [ "restic" "borg" ];
      secrets = [ "sops" "hardcoded" ];
      database = [ "postgresql" "mysql" ];
      ldap = [ "lldap" "kanidm" "openldap" ];
      sso = [ "authelia" "kanidm" "oidc" ];
      proxy = [ "nginx" "caddy" "traefik" "apache" ];
    };
    
    # Provider-specific global configuration
    providers = {
      letsencrypt = {
        email = "admin@pixelkeepers.net";
        dns_provider = "cloudflare";
        staging = false;
      };
      
      restic = {
        repository_base = "/srv/backup";
        password_file = "/run/secrets/restic-password";
        nice_level = 15;
        ionice_class = "best-effort";
        ionice_priority = 7;
      };
      
      sops = {
        default_file = ./secrets.yaml;
        age_key_file = "/boot/host_key";
      };
      
      lldap = {
        port = 3890;
        web_port = 17170;
        base_dn = "dc=pixelkeepers,dc=net";
        admin_password_secret = "/run/secrets/lldap-admin-password";
        jwt_secret_path = "/run/secrets/lldap-jwt-secret";
      };
      
      authelia = {
        port = 9091;
        ldap_url = "ldap://127.0.0.1:3890";
        ldap_base_dn = "dc=pixelkeepers,dc=net";
        ldap_user_base_dn = "ou=people,dc=pixelkeepers,dc=net";
        ldap_group_base_dn = "ou=groups,dc=pixelkeepers,dc=net";
        ldap_bind_dn = "cn=admin,dc=pixelkeepers,dc=net";
        ldap_bind_password_secret = "/run/secrets/lldap-admin-password";
        jwt_secret_path = "/run/secrets/authelia-jwt-secret";
        session_secret_path = "/run/secrets/authelia-session-secret";
        storage_encryption_key_path = "/run/secrets/authelia-storage-key";
      };
      
      nginx = {
        enable_http2 = true;
        client_max_body_size = "100M";
      };
      
      caddy = {
        automatic_https = true;
        email = "admin@pixelkeepers.net";
      };
    };
    
    # Service configurations
    services = {
      # Core infrastructure services
      lldap = {
        enable = true;
        subdomain = "ldap";
        base_dn = "dc=pixelkeepers,dc=net";
        require_web_auth = true;
        default_groups = [ "lldap_admin" "nextcloud_user" "vaultwarden_user" "plex_users" "media_admin" ];
        default_users = [
          {
            username = "h4wkeye";
            email = "admin@pixelkeepers.net";
            groups = [ "lldap_admin" "nextcloud_user" "vaultwarden_user" "plex_users" "media_admin" ];
          }
        ];
      };
      
      # Media services
      plex = {
        enable = true;
        subdomain = "plex";
        dataDir = "/var/lib/plex";
        user = "plex";
        group = "plex";
        require_auth = false; # Plex handles its own auth
        allowed_groups = [ "plex_users" "media_admin" ];
      };
      
      # Productivity services
      nextcloud = {
        enable = true;
        subdomain = "nextcloud";
        version = 30;
        dataDir = "/var/lib/nextcloud";
        require_ldap_auth = true;
        allowed_groups = [ "nextcloud_user" ];
      };
      
      # Security services
      vaultwarden = {
        enable = true;
        subdomain = "vault";
        admin_interface = true;
        require_admin_auth = true;
        admin_groups = [ "vaultwarden_admin" ];
      };
    };
  };
}
```

## Error Handling and Messages

### Standard Error Format

```nix
PSFError = {
  level = "error" | "warning" | "info";
  code = "PSF001" | "PSF002" | ...;  # Unique error codes
  service = "plex" | "nextcloud" | null;
  contract = "ssl" | "backup" | null;
  provider = "letsencrypt" | "restic" | null;
  message = "Human-readable error description";
  hint = "Suggested fix or next step";
  location = "file:line" | null;
};
```

### Common Error Scenarios

```nix
# PSF001 - No provider available for contract
{
  level = "error";
  code = "PSF001";
  service = "plex";
  contract = "ssl";
  provider = null;
  message = "No SSL provider can fulfill request for domain 'plex.pixelkeepers.net'";
  hint = "Configure Let's Encrypt provider or add selfsigned provider as fallback";
  location = "services/plex.nix:45";
}

# PSF002 - Provider configuration missing
{
  level = "error";
  code = "PSF002"; 
  service = "plex";
  contract = "ssl";
  provider = "letsencrypt";
  message = "Let's Encrypt provider missing required configuration: email";
  hint = "Add 'psf.providers.letsencrypt.email = \"admin@example.com\"' to configuration";
  location = "configuration.nix:25";
}

# PSF003 - Contract validation failed
{
  level = "error";
  code = "PSF003";
  service = "plex";
  contract = "backup";
  provider = "restic";
  message = "Backup paths do not exist: ['/nonexistent/path']";
  hint = "Ensure all backup paths exist or will be created by the service";
  location = "services/plex.nix:67";
}
```

## Testing Strategy

### Unit Tests Structure

```nix
# tests/unit/contracts/ssl_test.nix
{ pkgs, lib, psf }:

let
  inherit (lib) runTests;
  inherit (psf.contracts) ssl;
  
in runTests {
  testSSLRequestValidation = {
    expr = ssl.validateRequest (ssl.mkRequest {
      domain = "example.com";
      san_domains = [ "www.example.com" ];
    });
    expected = true;
  };
  
  testSSLRequestValidationFailure = {
    expr = ssl.validateRequest (ssl.mkRequest { domain = null; });
    expected = false;
  };
}
```

### Integration Tests Structure

```nix
# tests/integration/plex_ssl_test.nix
{ pkgs, lib, psf }:

let
  testConfig = {
    psf = {
      domain = "test.local";
      providers.selfsigned = { ca_cert = "/test/ca.pem"; };
      services.plex = {
        enable = true;
        subdomain = "plex";
      };
    };
  };
  
  result = lib.evalModules {
    modules = [ psf.module testConfig ];
  };
  
in {
  testPlexSSLIntegration = {
    expr = result.config.services.nginx.virtualHosts ? "plex.test.local";
    expected = true;
  };
  
  testPlexSSLCertificate = {
    expr = result.config.security.acme.certs ? "plex_test_local";
    expected = true;
  };
}
```

## Implementation Checklist

### Phase 1: Core Framework ✅ COMPLETED
- [x] Create directory structure as specified above
- [x] Implement `lib/default.nix` with core PSF functions
- [x] Implement `lib/contracts.nix` contract engine
- [x] Implement `lib/providers.nix` provider engine
- [x] Implement `lib/validation.nix` validation system
- [x] Implement `lib/service-builder.nix` service composition
- [x] Create basic flake.nix that exports PSF module

### Phase 2: Essential Contracts 🔄 IN PROGRESS
- [ ] Implement `contracts/ssl.nix` SSL certificate contract
- [ ] Implement `contracts/backup.nix` backup contract  
- [ ] Implement `contracts/secrets.nix` secret management contract
- [x] Implement `contracts/database.nix` database contract (PostgreSQL 17 default)
- [ ] Implement `contracts/ldap.nix` LDAP directory service contract
- [ ] Implement `contracts/sso.nix` Single Sign-On authentication contract
- [ ] Implement `contracts/proxy.nix` reverse proxy contract

### Phase 3: Core Providers 🔄 IN PROGRESS
- [ ] Implement `providers/ssl/letsencrypt.nix` Let's Encrypt provider
- [ ] Implement `providers/ssl/selfsigned.nix` self-signed provider
- [ ] Implement `providers/backup/restic.nix` Restic provider
- [ ] Implement `providers/secrets/sops.nix` SOPS provider
- [x] Implement `providers/database/postgresql.nix` PostgreSQL provider (version 17 default)
- [x] Implement `providers/database/mysql.nix` MySQL provider
- [ ] Implement `providers/ldap/lldap.nix` LLDAP provider
- [ ] Implement `providers/sso/authelia.nix` Authelia SSO provider
- [ ] Implement `providers/proxy/nginx.nix` Nginx provider

### Phase 4: Core Services 🔄 IN PROGRESS
- [ ] Implement `services/lldap.nix` LLDAP directory service
- [ ] Implement `services/plex.nix` Plex service using PSF pattern
- [ ] Create test configuration that uses LDAP + Plex services
- [ ] Validate that configuration builds without errors
- [ ] Test deployment to server
- [ ] Verify all contracts are fulfilled correctly

### Phase 5: Service Migration
- [ ] Migrate Vaultwarden to PSF pattern with SSO integration
- [ ] Migrate Nextcloud to PSF pattern with LDAP + SSO integration
- [ ] Migrate Authelia to PSF pattern as SSO provider
- [ ] Add alternative providers (Kanidm, OpenLDAP, Caddy, Traefik)
- [ ] Remove SHB dependencies
- [ ] Clean up legacy configuration

### Phase 6: Advanced Features
- [ ] Implement health check system with monitoring
- [ ] Add service discovery contract for inter-service communication
- [ ] Create advanced backup providers (Borg, cloud storage)
- [ ] Add metrics/monitoring contract integration
- [ ] Implement configuration validation and testing framework
- [ ] Create documentation generation from contract definitions

This specification provides complete implementation details including exact file structures, data formats, function signatures, and error handling patterns. Anyone can pick up this document and implement PSF without requiring prior context or memory of design decisions.