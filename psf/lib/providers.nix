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
  
  # Import mkResult from contracts
  mkResult = (import ./contracts.nix { inherit lib pkgs; }).mkResult;
  
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
  
  database = import ../providers/database { inherit lib pkgs registerProvider mkResult; };
  
  ldap = {
    lldap = import ../providers/ldap/lldap.nix { inherit lib pkgs registerProvider; };
    # kanidm = import ../providers/ldap/kanidm.nix { inherit lib pkgs registerProvider; };
    # openldap = import ../providers/ldap/openldap.nix { inherit lib pkgs registerProvider; };
  };
  
  sso = {
    authelia = import ../providers/sso/authelia.nix { inherit lib pkgs registerProvider; };
    # kanidm = import ../providers/sso/kanidm.nix { inherit lib pkgs registerProvider; };
    # oidc = import ../providers/sso/oidc.nix { inherit lib pkgs registerProvider; };
  };
  
  proxy = {
    nginx = import ../providers/proxy/nginx.nix { inherit lib pkgs registerProvider; };
    # caddy = import ../providers/proxy/caddy.nix { inherit lib pkgs registerProvider; };
    # traefik = import ../providers/proxy/traefik.nix { inherit lib pkgs registerProvider; };
    # apache = import ../providers/proxy/apache.nix { inherit lib pkgs registerProvider; };
  };
}