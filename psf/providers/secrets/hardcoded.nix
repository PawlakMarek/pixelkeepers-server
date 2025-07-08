{ lib, pkgs, registerProvider }:

registerProvider {
  name = "hardcoded";
  contract_type = "secrets";
  version = "1.0.0";
  description = "Hardcoded secrets provider (DEVELOPMENT/TESTING ONLY - NOT SECURE)";
  
  capabilities = {
    formats = [ "plain" ];
    encryption = [];
    template_support = false;
    systemd_integration = true;
    warning = "CRITICAL: NOT SUITABLE FOR PRODUCTION USE - SECURITY RISK";
    production_safe = false;
    security_level = "none";
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
    let
      # Detect if this is a production environment
      isProduction = 
        # Check for common production indicators
        (builtins.getEnv "PSF_ENVIRONMENT" == "production") ||
        (builtins.getEnv "NIXOS_ENVIRONMENT" == "production") ||
        (builtins.getEnv "NODE_ENV" == "production") ||
        # Check if we're running on a production domain
        (builtins.match ".*\\.(com|net|org|io)$" (builtins.getEnv "PSF_DOMAIN" or "") != null);
        
      # Check for explicit override
      allowOverride = builtins.getEnv "PSF_ALLOW_HARDCODED_SECRETS" == "true";
        
    in
      if isProduction && !allowOverride then
        throw ''
          FATAL: Hardcoded secrets provider cannot be used in production!
          
          Environment indicators suggest this is a production system:
          ${if builtins.getEnv "PSF_ENVIRONMENT" == "production" then "- PSF_ENVIRONMENT=production" else ""}
          ${if builtins.getEnv "NIXOS_ENVIRONMENT" == "production" then "- NIXOS_ENVIRONMENT=production" else ""}
          ${if builtins.getEnv "NODE_ENV" == "production" then "- NODE_ENV=production" else ""}
          ${if builtins.match ".*\\.(com|net|org|io)$" (builtins.getEnv "PSF_DOMAIN" or "") != null then "- Production domain detected: ${builtins.getEnv "PSF_DOMAIN"}" else ""}
          
          Please use a secure secrets provider like SOPS instead.
          
          To override this check for development/testing, set:
          export PSF_ALLOW_HARDCODED_SECRETS=true
          
          WARNING: Only use the override for development/testing environments!
        ''
      else
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
    let
      # Check for production indicators in validation too
      isProduction = 
        (builtins.getEnv "PSF_ENVIRONMENT" == "production") ||
        (builtins.getEnv "NIXOS_ENVIRONMENT" == "production") ||
        (builtins.getEnv "NODE_ENV" == "production") ||
        (builtins.match ".*\\.(com|net|org|io)$" (builtins.getEnv "PSF_DOMAIN" or "") != null);
      
      allowOverride = builtins.getEnv "PSF_ALLOW_HARDCODED_SECRETS" == "true";
    in
      lib.optional (request.payload.description == null || request.payload.description == "") "Secret description cannot be empty" ++
      lib.optional (isProduction && allowOverride) 
        "WARNING: Hardcoded secrets provider is being used in production with override - THIS IS NOT SECURE!" ++
      lib.optional (!isProduction) 
        "WARNING: Using hardcoded secrets provider - only suitable for development/testing" ++
      lib.optional (providerConfig.secrets.${builtins.replaceStrings [" " "." "-"] ["_" "_" "_"] request.payload.description} or "CHANGEME" == "CHANGEME")
        "WARNING: Secret '${request.payload.description}' is using default 'CHANGEME' value";
}