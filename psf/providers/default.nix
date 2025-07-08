{ psfLib, pkgs, pkgs-full ? pkgs }:
let
  inherit (pkgs.lib) mkOption types;
  
  # Helper to register a provider - this ensures consistent interface
  registerProvider = providerDef: {
    inherit (providerDef) name contract_type version description;
    inherit (providerDef) capabilities configSchema;
    inherit (providerDef) canFulfill fulfill validate;
  };

in
rec {
  # SSL providers
  ssl = {
    letsencrypt = import ./ssl/letsencrypt.nix { inherit (pkgs) lib; inherit pkgs registerProvider; };
    selfsigned = import ./ssl/selfsigned.nix { inherit (pkgs) lib; inherit pkgs registerProvider; };
  };
  
  # Backup providers  
  backup = {
    restic = import ./backup/restic.nix { inherit (pkgs) lib; inherit pkgs registerProvider; };
    borg = import ./backup/borg.nix { inherit (pkgs) lib; inherit pkgs registerProvider; };
  };
  
  # Secrets providers
  secrets = {
    sops = import ./secrets/sops.nix { inherit (pkgs) lib; inherit pkgs registerProvider; };
    hardcoded = import ./secrets/hardcoded.nix { inherit (pkgs) lib; inherit pkgs registerProvider; };
  };
  
  # Database providers
  database = {
    postgresql = import ./database/postgresql.nix { inherit (pkgs) lib; inherit pkgs registerProvider; };
    mysql = import ./database/mysql.nix { inherit (pkgs) lib; inherit pkgs registerProvider; };
  };
  
  # LDAP providers
  ldap = {
    lldap = import ./ldap/lldap.nix { inherit (pkgs) lib; inherit pkgs registerProvider; };
    kanidm = import ./ldap/kanidm.nix { inherit (pkgs) lib; inherit pkgs registerProvider; };
    openldap = import ./ldap/openldap.nix { inherit (pkgs) lib; inherit pkgs registerProvider; };
  };
  
  # SSO providers
  sso = {
    authelia = import ./sso/authelia.nix { inherit (pkgs) lib; inherit pkgs registerProvider; };
    kanidm = import ./sso/kanidm.nix { inherit (pkgs) lib; inherit pkgs registerProvider; };
    oidc = import ./sso/oidc.nix { inherit (pkgs) lib; inherit pkgs registerProvider; };
  };
  
  # Proxy providers
  proxy = {
    nginx = import ./proxy/nginx.nix { inherit (pkgs) lib; inherit pkgs registerProvider; };
    caddy = import ./proxy/caddy.nix { inherit (pkgs) lib; inherit pkgs registerProvider; };
    traefik = import ./proxy/traefik.nix { inherit (pkgs) lib; inherit pkgs registerProvider; };
    apache = import ./proxy/apache.nix { inherit (pkgs) lib; inherit pkgs registerProvider; };
  };
  
  # All providers flattened for easy access
  allProviders = 
    builtins.attrValues ssl ++
    builtins.attrValues backup ++
    builtins.attrValues secrets ++
    builtins.attrValues database ++
    builtins.attrValues ldap ++
    builtins.attrValues sso ++
    builtins.attrValues proxy;
    
  # Providers by contract type
  byContractType = {
    ssl = ssl;
    backup = backup;
    secrets = secrets;
    database = database;
    ldap = ldap;
    sso = sso;
    proxy = proxy;
  };
}