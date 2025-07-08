{ lib, pkgs, registerProvider, mkResult }:

{
  postgresql = import ./postgresql.nix { inherit lib pkgs registerProvider mkResult; };
  mysql = import ./mysql.nix { inherit lib pkgs registerProvider mkResult; };
}