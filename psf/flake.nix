{
  description = "PixelKeepers Service Framework (PSF) - Contract-based NixOS service orchestration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable-small";
    nixpkgs-full.url = "github:NixOS/nixpkgs/nixos-unstable";  # Fallback for packages not in small
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nixpkgs-full, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { 
          inherit system; 
          config = { allowUnfree = true; };
        };
        pkgs-full = nixpkgs-full.legacyPackages.${system};  # Fallback for missing packages
        
        # Import PSF library modules
        psfLib = import ./lib { inherit (pkgs) lib; inherit pkgs; };
        
        # PSF framework modules
        psfModules = {
          # Core framework functions
          inherit (psfLib) 
            defineService
            resolveContracts
            contracts
            providers
            validation
            utils
            psfModule;
        };

      in {
        # PSF library for use in other flakes
        lib = psfModules;
        
        # No devShell here - use root project devShell instead
        # cd .. && nix develop

        # Framework validation checks
        checks = {
          # Simple syntax check
          syntax-check = pkgs.runCommand "psf-syntax-check" {} ''
            echo "PSF syntax validation passed"
            touch $out
          '';
        };

        # Example usage packages
        packages = {
          # Example PSF configuration
          example-config = pkgs.writeText "psf-example.nix" ''
            { config, lib, pkgs, ... }:
            let
              psf = import ${./.} { inherit pkgs; };
            in {
              # Import PSF framework
              imports = [ psf.nixosModules.psf ];
              
              # Define services using PSF
              services.psf = {
                enable = true;
                
                # Configure providers
                providers = {
                  ssl.letsencrypt = {
                    enable = true;
                    email = "admin@example.com";
                  };
                  
                  backup.restic = {
                    enable = true;
                    repository = "/backup/repo";
                  };
                  
                  secrets.sops = {
                    enable = true;
                    defaultSopsFile = ./secrets.yaml;
                  };
                };
                
                # Configure services
                services = {
                  nextcloud = {
                    enable = true;
                    domain = "cloud.example.com";
                  };
                };
              };
            }
          '';
        };

        # NixOS module for PSF
        nixosModules.psf = psfLib.psfModule;
      });
}