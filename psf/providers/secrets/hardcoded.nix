{ lib, pkgs, registerProvider }:

registerProvider {
  name = "hardcoded";
  contract_type = "secrets";
  version = "1.0.0";
  description = "Hardcoded secrets provider (for development/testing only)";
  
  capabilities = {
    formats = [ "plain" ];
    encryption = [];
    template_support = false;
    systemd_integration = true;
    warning = "NOT SUITABLE FOR PRODUCTION USE";
  };
  
  configSchema = {
    secrets = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Hardcoded secret values (NOT SECURE!)";
    };
    
    warn_on_use = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to show warnings when using hardcoded secrets";
    };
  };
  
  # Check if this provider can fulfill the request
  canFulfill = request: 
    request.contract_type == "secrets";
  
  # Fulfill the secrets request
  fulfill = request: providerConfig:
    let
      secretName = builtins.replaceStrings [" " "." "-"] ["_" "_" "_"] request.payload.description;
      secretPath = "/run/secrets/${secretName}";
      secretValue = providerConfig.secrets.${secretName} or "CHANGEME";
    in {
      config = {
        # Create secret file using systemd tmpfiles
        systemd.tmpfiles.rules = [
          "f ${secretPath} ${request.payload.mode} ${request.payload.owner} ${request.payload.group} - ${secretValue}"
        ];
        
        # Add warning to system
        warnings = lib.optionals providerConfig.warn_on_use [
          "SECURITY WARNING: Using hardcoded secrets provider for '${request.payload.description}' - NOT SUITABLE FOR PRODUCTION!"
        ];
        
        # Restart services when secrets change (though they won't with hardcoded)
        systemd.services = lib.listToAttrs (map (service: {
          name = service;
          value = {
            restartTriggers = [ secretValue ];
          };
        }) request.payload.restart_services);
      };
      
      result = {
        contract_type = "secrets";
        payload = {
          path = secretPath;
          env_var = null;
          systemd_credential = null;
        };
        metadata = {
          provider_version = "1.0.0";
          secret_name = secretName;
          warning = "HARDCODED SECRET - NOT SECURE";
        };
      };
    };
  
  # Validate provider configuration and request
  validate = request: providerConfig: 
    lib.optional (request.payload.description == null || request.payload.description == "") "Secret description cannot be empty" ++
    lib.optional (providerConfig.warn_on_use && builtins.length request.payload.restart_services > 0) 
      "WARNING: Using hardcoded secrets in production environment";
}