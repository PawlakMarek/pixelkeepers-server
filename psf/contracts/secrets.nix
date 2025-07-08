{ lib, pkgs, mkRequest, mkResult }:

{
  name = "secrets";
  version = "1.0.0";
  description = "Secrets management contract";
  
  # Request schema - what services can ask for
  requestSchema = {
    description = lib.mkOption {
      type = lib.types.str;
      description = "Human-readable description of the secret";
    };
    
    mode = lib.mkOption {
      type = lib.types.str;
      default = "0400";
      description = "File permissions for the secret";
    };
    
    owner = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "Owner of the secret file";
    };
    
    group = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "Group of the secret file";
    };
    
    restart_services = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Services to restart when secret changes";
    };
  };
  
  # Result schema - what providers must deliver
  resultSchema = {
    path = lib.mkOption {
      type = lib.types.path;
      description = "Path to the secret file";
    };
    
    env_var = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Environment variable name if secret is exposed as env var";
    };
    
    systemd_credential = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Systemd credential name if using LoadCredential";
    };
  };
  
  # Create secrets request
  mkRequest = { description, mode ? "0400", owner ? "root", group ? "root", restart_services ? [] }:
    mkRequest "secrets" {
      inherit description mode owner group restart_services;
    };
  
  # Validate secrets request
  validateRequest = request:
    assert request.payload.description != null;
    assert request.payload.mode != null;
    assert request.payload.owner != null;
    true;
    
  # Validate secrets result
  validateResult = result:
    assert result.payload.path != null;
    true;
}