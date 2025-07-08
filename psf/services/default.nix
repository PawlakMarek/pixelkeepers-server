{ lib, pkgs }:

{
  test-app = import ./test-app.nix { inherit lib pkgs; };
}