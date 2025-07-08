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
        psfLib = import ./lib { inherit pkgs pkgs-full; };
        
        # PSF framework modules
        psfModules = {
          # Core framework functions
          inherit (psfLib) 
            defineContract 
            defineProvider 
            defineService
            resolveContracts
            validateConfiguration;
          
          # Pre-built contracts
          contracts = import ./contracts { inherit psfLib pkgs pkgs-full; };
          
          # Pre-built providers  
          providers = import ./providers { inherit psfLib pkgs pkgs-full; };
          
          # Pre-built services
          services = import ./services { inherit psfLib pkgs pkgs-full; };
        };

      in {
        # PSF library for use in other flakes
        lib = psfModules;
        
        # Development environment
        devShells.default = pkgs.mkShell {
          name = "psf-dev";
          buildInputs = with pkgs; [
            # Nix development
            nix
            nixpkgs-fmt
            nixfmt
            statix
            
            # Claude Code for AI-assisted development
            claude-code
            
            # Git and development tools
            git
            gh
            openssh
            
            # Documentation and testing
            mdbook  # For generating documentation
            
            # Server management tools (for when working on nixos-core)
            deploy-rs
            sops
          ];
          
          # Set up development environment
          shellHook = ''
            echo "🔧 PSF Development Environment"
            echo "🤖 Claude Code available for AI-assisted development"
            echo "📚 Run 'nix flake check' to validate framework"
            echo "📖 Documentation: ../docs/PSF_IMPLEMENTATION.md"
            echo "🔐 Git signing configured: $(git config --get commit.gpgsign)"
            echo ""
            echo "Available commands:"
            echo "  nix flake check        - Validate PSF framework"
            echo "  nix develop            - Enter this dev environment"
            echo "  claude                 - Start Claude Code session"
            echo "  ../nix run .#deploy    - Deploy to server (from root)"
            echo ""
          '';
          
          # Environment variables for development
          PSF_DEV = "true";
          PSF_ROOT = builtins.toString ./.;
          DOCS_PATH = builtins.toString ../docs;
        };

        # Framework validation checks
        checks = {
          # Validate all framework components can be imported
          framework-imports = pkgs.runCommand "psf-framework-imports" {} ''
            export NIX_PATH="nixpkgs=${nixpkgs}"
            ${pkgs.nix}/bin/nix-instantiate --eval --strict --json ${./lib/default.nix} > /dev/null
            ${pkgs.nix}/bin/nix-instantiate --eval --strict --json ${./contracts/default.nix} > /dev/null
            ${pkgs.nix}/bin/nix-instantiate --eval --strict --json ${./providers/default.nix} > /dev/null
            ${pkgs.nix}/bin/nix-instantiate --eval --strict --json ${./services/default.nix} > /dev/null
            touch $out
          '';
          
          # Format check
          format-check = pkgs.runCommand "psf-format-check" {} ''
            ${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt --check ${./.}
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
        nixosModules.psf = { config, lib, pkgs, ... }:
        let
          cfg = config.services.psf;
          psf = psfModules;
        in {
          options.services.psf = {
            enable = lib.mkEnableOption "PixelKeepers Service Framework";
            
            providers = lib.mkOption {
              type = lib.types.attrsOf lib.types.attrs;
              default = {};
              description = "PSF provider configurations";
            };
            
            services = lib.mkOption {
              type = lib.types.attrsOf lib.types.attrs;
              default = {};
              description = "PSF service configurations";
            };
          };
          
          config = lib.mkIf cfg.enable {
            # PSF implementation will be added here
            warnings = [ "PSF is under development - not ready for production use" ];
          };
        };
      });
}