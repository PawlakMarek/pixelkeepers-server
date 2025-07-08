{ lib, pkgs, registerProvider }:

registerProvider {
  name = "sops";
  contract_type = "secrets";
  version = "1.0.0";
  description = "SOPS secrets management provider";
  
  capabilities = {
    formats = [ "yaml" "json" "env" ];
    encryption = [ "age" "gpg" ];
    template_support = true;
    systemd_integration = true;
  };
  
  configSchema = {
    default_file = lib.mkOption {
      type = lib.types.path;
      description = "Default SOPS secrets file";
    };
    
    age_key_file = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to age key file";
    };
    
    format = lib.mkOption {
      type = lib.types.enum [ "yaml" "json" "env" ];
      default = "yaml";
      description = "Default secrets file format";
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
    in {
      config = {
        # Enable SOPS module
        sops = {
          defaultSopsFile = providerConfig.default_file;
          defaultSopsFormat = providerConfig.format;
          
          age = lib.mkIf (providerConfig.age_key_file != null) {
            keyFile = providerConfig.age_key_file;
          };
          
          secrets.${secretName} = {
            mode = request.payload.mode;
            owner = request.payload.owner;
            group = request.payload.group;
            restartUnits = request.payload.restart_services;
          };
        };
      };
      
      result = {
        contract_type = "secrets";
        payload = {
          path = secretPath;
          env_var = null;
          systemd_credential = secretName;
        };
        metadata = {
          provider_version = "1.0.0";
          secret_name = secretName;
          sops_file = providerConfig.default_file;
        };
      };
    };
  
  # Validate provider configuration and request
  validate = request: providerConfig: 
    lib.optional (providerConfig.default_file == null) "Default SOPS file must be configured" ++
    lib.optional (!builtins.pathExists providerConfig.default_file) "SOPS file does not exist" ++
    lib.optional (request.payload.description == null || request.payload.description == "") "Secret description cannot be empty";
}