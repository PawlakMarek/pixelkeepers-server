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