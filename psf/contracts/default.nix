{ psfLib, pkgs, pkgs-full ? pkgs }:
let
  inherit (pkgs.lib) mkOption types;
  
  # Helper functions for creating contract requests and results
  mkRequest = contractType: payload: {
    contract_type = contractType;
    inherit payload;
    requester_id = null; # Set by service resolution
    priority = "normal";
    tags = [];
  };
  
  mkResult = contractType: payload: metadata: {
    inherit contractType payload metadata;
    provider_id = null; # Set by provider resolution
    request_id = null;  # Set by service resolution
  };

in
rec {
  # Import all contract definitions
  ssl = import ./ssl.nix { inherit (pkgs) lib; inherit pkgs mkRequest mkResult; };
  backup = import ./backup.nix { inherit (pkgs) lib; inherit pkgs mkRequest mkResult; };
  secrets = import ./secrets.nix { inherit (pkgs) lib; inherit pkgs mkRequest mkResult; };
  database = import ./database.nix { inherit (pkgs) lib; inherit pkgs mkRequest mkResult; };
  ldap = import ./ldap.nix { inherit (pkgs) lib; inherit pkgs mkRequest mkResult; };
  sso = import ./sso.nix { inherit (pkgs) lib; inherit pkgs mkRequest mkResult; };
  proxy = import ./proxy.nix { inherit (pkgs) lib; inherit pkgs mkRequest mkResult; };

  # All contracts list for easy iteration
  allContracts = [
    ssl
    backup
    secrets
    database
    ldap
    sso
    proxy
  ];
  
  # Contract registry by name
  byName = {
    inherit ssl backup secrets database ldap sso proxy;
  };
}