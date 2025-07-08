{ lib, pkgs }:

let
  inherit (lib) mkOption types optionalAttrs mapAttrs filterAttrs;
  
  # Import all PSF components
  contracts = import ./contracts.nix { inherit lib pkgs; };
  providers = import ./providers.nix { inherit lib pkgs; };
  validation = import ./validation.nix { inherit lib pkgs; };
  serviceBuilder = import ./service-builder.nix { inherit lib pkgs; };
  
  # Contract resolution engine (defined first since it's used by defineService)
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
  
  # Re-export the resolveContracts function
  inherit resolveContracts;
  
  # Re-export components
  inherit contracts providers validation;
  
  # Utility functions
  utils = import ./utils.nix { inherit lib pkgs; };
  
  # PSF Module for NixOS
  psfModule = { config, lib, pkgs, ... }:
  let
    cfg = config.psf;
  in {
    options.psf = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable PixelKeepers Service Framework";
      };
      
      domain = mkOption {
        type = types.str;
        description = "Base domain for PSF services";
        example = "example.com";
      };
      
      # Provider preferences (tried in order)
      provider_priority = mkOption {
        type = types.attrsOf (types.listOf types.str);
        default = {
          ssl = [ "letsencrypt" "selfsigned" ];
          backup = [ "restic" "borg" ];
          secrets = [ "sops" "hardcoded" ];
          database = [ "postgresql" "mysql" ];
          ldap = [ "lldap" "kanidm" "openldap" ];
          sso = [ "authelia" "kanidm" "oidc" ];
          proxy = [ "nginx" "caddy" "traefik" "apache" ];
        };
        description = "Provider priority order for each contract type";
      };
      
      # Provider-specific global configuration
      providers = mkOption {
        type = types.attrsOf types.attrs;
        default = {};
        description = "Provider-specific configuration";
        example = {
          letsencrypt = {
            email = "admin@example.com";
            dns_provider = "cloudflare";
          };
          postgresql = {
            version = "17";
            port = 5432;
          };
        };
      };
      
      # Service configurations
      services = mkOption {
        type = types.attrsOf types.attrs;
        default = {};
        description = "Service-specific configuration";
      };
      
      # Validation settings
      validation = {
        build_time = mkOption {
          type = types.bool;
          default = true;
          description = "Enable build-time validation";
        };
        
        strict_mode = mkOption {
          type = types.bool;
          default = false;
          description = "Enable strict validation mode";
        };
      };
    };
    
    config = lib.mkIf cfg.enable {
      # Global PSF assertions
      assertions = lib.optionals cfg.validation.build_time [
        {
          assertion = cfg.domain != "";
          message = "PSF domain must be configured";
        }
        {
          assertion = (validation.buildTimeValidation cfg).errors == [];
          message = "PSF build-time validation failed: ${lib.concatStringsSep ", " (validation.buildTimeValidation cfg).errors}";
        }
      ];
      
      warnings = lib.optionals (!cfg.validation.build_time) [
        "PSF build-time validation is disabled - this may lead to runtime errors"
      ];
    };
  };
}