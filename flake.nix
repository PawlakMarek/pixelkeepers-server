{
  description = "Ibizaman's config.";

  inputs = {
    # Legacy SHB system (being phased out)
    selfhostblocks.url = "path:./shb-fork";
    skarabox.url = "github:ibizaman/skarabox";
    skarabox.inputs.nixpkgs.follows = "selfhostblocks/nixpkgs";

    # Modern nixpkgs for PSF framework
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable-small";
    nixpkgs-full.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # Deployment and secrets
    deploy-rs.url = "github:serokell/deploy-rs";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs = {
    self,
    skarabox,
    selfhostblocks,
    sops-nix,
    deploy-rs,
    nixpkgs,
    nixpkgs-full,
    flake-utils,
  }: let
    system = "x86_64-linux";
    shbLib = selfhostblocks.lib.${system};

    shbNixpkgs = shbLib.patchedNixpkgs;

    shbPkgs = import shbNixpkgs {inherit system;};

    # Taken from https://github.com/serokell/deploy-rs?tab=readme-ov-file#overall-usage
    deployPkgs = import selfhostblocks.inputs.nixpkgs {
      inherit system;
      overlays = [
        deploy-rs.overlays.default
        (_self: super: {
          deploy-rs = {
            inherit (shbPkgs) deploy-rs;
            lib = super.deploy-rs.lib;
          };
        })
      ];
    };

    domain = "pixelkeepers.net";
    
    # PSF framework integration
    psfPkgs = import nixpkgs { 
      inherit system; 
      config = { allowUnfree = true; };
    };
    psfPkgs-full = nixpkgs-full.legacyPackages.${system};
    
    # Import PSF library
    psfLib = import ./psf/lib { inherit (psfPkgs) lib; pkgs = psfPkgs; };
    
  in {
    nixosModules.nixos-core = {
      imports = [
        skarabox.nixosModules.skarabox
        selfhostblocks.nixosModules.${system}.default
        sops-nix.nixosModules.default
        ({config, ...}: {
          skarabox.hostname = "nixos-core";
          skarabox.username = "h4wkeye";
          skarabox.hashedPasswordFile = config.sops.secrets."nixos-core/user/hashedPassword".path;
          skarabox.facter-config = ./nixos-core/facter.json;
          # Root pool configuration - mirror of 2x 1TB NVMe drives
          skarabox.disks.rootPool = {
            disk1 = "/dev/disk/by-id/nvme-PC711_NVMe_SK_hynix_1TB__AJ0CN64661240154T";
            disk2 = "/dev/disk/by-id/nvme-PC711_NVMe_SK_hynix_1TB__AJ0CN64661240154R";
            reservation = "500M";
          };
          # Disable skarabox data pool - using custom ZFS configuration
          skarabox.disks.dataPool = {
            enable = false;
          };
          skarabox.sshAuthorizedKeyFile = ./nixos-core/ssh.pub;
          skarabox.hostId = builtins.readFile ./nixos-core/hostid;
          # SSH ports for security
          skarabox.boot.sshPort = builtins.readFile ./nixos-core/ssh_boot_port;
          skarabox.sshPort = builtins.readFile ./nixos-core/ssh_port;
          # Hardware drivers
          boot.initrd.availableKernelModules = [
            # Add specific drivers if needed
          ];
          hardware.enableAllHardware = false;
          # SOPS configuration
          sops.defaultSopsFile = ./nixos-core/secrets.yaml;
          sops.age = {
            sshKeyPaths = ["/boot/host_key"];
          };
          sops.secrets."nixos-core/user/hashedPassword" = {
            neededForUsers = true;
          };
        })
        {
          me.domain = domain;
        }

        ./nixos-core/configuration.nix
      ];
    };

    # Used with nixos-anywere for installation.
    nixosConfigurations.nixos-core = shbNixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        self.nixosModules.nixos-core
        {
          nix.settings.trusted-public-keys = [
            "selfhostblocks.cachix.org-1:H5h6Uj188DObUJDbEbSAwc377uvcjSFOfpxyCFP7cVs="
          ];

          nix.settings.substituters = [
            "https://selfhostblocks.cachix.org"
          ];
        }
      ];
    };

    # Used with deploy-rs for updates (local network).
    deploy.nodes.nixos-core = {
      hostname = "192.168.68.20";
      sshUser = "h4wkeye";
      sshOpts = ["-o" "IdentitiesOnly=yes" "-i" "nixos-core/ssh"];
      activationTimeout = 600;
      profiles = {
        system = {
          user = "root";
          path = deployPkgs.deploy-rs.lib.activate.nixos self.nixosConfigurations.nixos-core;
        };
      };
    };

    # Used with deploy-rs for updates (remote via pixelkeepers.net:3322).
    deploy.nodes.nixos-core-remote = {
      hostname = "pixelkeepers.net";
      sshUser = "h4wkeye";
      sshOpts = ["-o" "IdentitiesOnly=yes" "-i" "nixos-core/ssh" "-p" "3322"];
      activationTimeout = 600;
      profiles = {
        system = {
          user = "root";
          path = deployPkgs.deploy-rs.lib.activate.nixos self.nixosConfigurations.nixos-core;
        };
      };
    };
    # From https://github.com/serokell/deploy-rs?tab=readme-ov-file#overall-usage
    checks = builtins.mapAttrs (_system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
    
    # PSF Framework exports
    lib = psfLib;
    nixosModules.psf = psfLib.psfModule;
    
    # Development environment
    devShells.${system}.default = psfPkgs.mkShell {
      name = "pixelkeepers-dev";
      buildInputs = with psfPkgs; [
        # Nix development tools
        nix
        nixpkgs-fmt
        nixfmt-classic
        statix
        
        # Git and development tools
        git
        gh
        openssh
        
        # Server management tools
        deployPkgs.deploy-rs.deploy-rs
        sops
        
        # Documentation tools
        mdbook
        
        # Development and debugging tools
        httpie  # Modern curl alternative
        curl    # Classic HTTP client
        jq      # JSON processor
        yq      # YAML processor
        netcat  # Network testing
      ];
      
      shellHook = ''
        echo "🏠 PixelKeepers Development Environment"
        echo ""
        echo "📁 Project Structure:"
        echo "   docs/               - Project documentation"
        echo "   psf/                - PSF framework development"
        echo "   nixos-core/         - Production server configuration"
        echo "   shb-fork/           - Legacy SHB (being phased out)"
        echo ""
        echo "📚 Essential Documentation:"
        echo "   docs/PSF_IMPLEMENTATION.md  - PSF technical specification"
        echo "   docs/CLAUDE.md              - Development workflow guide"
        echo ""
        echo "🔧 Available Commands:"
        echo "   nix run .#deploy           - Smart deploy (local then remote)"
        echo "   nix run .#nixos-core-ssh   - SSH to server (local/remote)"
        echo "   nix run .#sops             - Edit secrets"
        echo "   nix flake check            - Validate entire project"
        echo "   cd psf && nix flake check  - Validate PSF framework only"
        echo "   cd nixos-core && nix flake check - Validate server config only"
        echo ""
        echo "🤖 Claude Code available for AI-assisted development"
        echo "🔐 Git signing configured: $(git config --get commit.gpgsign)"
        echo ""
      '';
      
      # Environment variables
      PSF_ROOT = builtins.toString ./psf;
      NIXOS_CORE_ROOT = builtins.toString ./nixos-core;
      DOCS_PATH = builtins.toString ./docs;
      PROJECT_ROOT = builtins.toString ./.;
    };

    # Apps for server management
    apps.${system} = {
      sops = {
        type = "app";
        program = "${shbPkgs.sops}/bin/sops";
      };

      # SSH access to nixos-core (local network)
      nixos-core-ssh = {
        type = "app";
        program = "${shbPkgs.writeShellScript "nixos-core-ssh" ''
          exec ${shbPkgs.openssh}/bin/ssh -o IdentitiesOnly=yes -i ${./nixos-core/ssh} h4wkeye@192.168.68.20 "$@"
        ''}";
      };

      # SSH access to nixos-core (remote via pixelkeepers.net:3322)
      nixos-core-ssh-remote = {
        type = "app";
        program = "${shbPkgs.writeShellScript "nixos-core-ssh-remote" ''
          exec ${shbPkgs.openssh}/bin/ssh -o IdentitiesOnly=yes -i ${./nixos-core/ssh} -p 3322 h4wkeye@pixelkeepers.net "$@"
        ''}";
      };

      # SSH access to nixos-core boot/initrd (local 192.168.68.20:2222)
      nixos-core-ssh-boot = {
        type = "app";
        program = "${shbPkgs.writeShellScript "nixos-core-ssh-boot" ''
          exec ${shbPkgs.openssh}/bin/ssh -o IdentitiesOnly=yes -i ${./nixos-core/ssh} -p 2222 h4wkeye@192.168.68.20 "$@"
        ''}";
      };

      # SSH access to nixos-core boot/initrd (remote pixelkeepers.net:4422)
      nixos-core-ssh-boot-remote = {
        type = "app";
        program = "${shbPkgs.writeShellScript "nixos-core-ssh-boot-remote" ''
          exec ${shbPkgs.openssh}/bin/ssh -o IdentitiesOnly=yes -i ${./nixos-core/ssh} -p 4422 h4wkeye@pixelkeepers.net "$@"
        ''}";
      };

      # Unlock root pool during boot via initrd SSH (tries local, then remote)
      nixos-core-unlock = {
        type = "app";
        program = "${shbPkgs.writeShellScript "nixos-core-unlock" ''
          echo "Unlocking root pool via initrd boot SSH..."
          PASSPHRASE="$(${shbPkgs.sops}/bin/sops --decrypt --extract '[\"nixos-core\"][\"disks\"][\"rootPassphrase\"]' ${./nixos-core/secrets.yaml})"
          
          # Try local boot SSH first (192.168.68.20:2222)
          if ${shbPkgs.openssh}/bin/ssh -o ConnectTimeout=10 -o IdentitiesOnly=yes -i ${./nixos-core/ssh} -p 2222 h4wkeye@192.168.68.20 true 2>/dev/null; then
            echo "Using local boot SSH (192.168.68.20:2222)..."
            echo "$PASSPHRASE" | ${shbPkgs.openssh}/bin/ssh -o IdentitiesOnly=yes -i ${./nixos-core/ssh} -p 2222 h4wkeye@192.168.68.20 \
              "systemd-tty-ask-password-agent"
          else
            echo "Local boot SSH not available, trying remote (pixelkeepers.net:4422)..."
            echo "$PASSPHRASE" | ${shbPkgs.openssh}/bin/ssh -o IdentitiesOnly=yes -i ${./nixos-core/ssh} -p 4422 h4wkeye@pixelkeepers.net \
              "systemd-tty-ask-password-agent"
          fi
        ''}";
      };

      # Deploy using deploy-rs (local network)
      deploy-rs = {
        type = "app";
        program = "${deployPkgs.deploy-rs.deploy-rs}/bin/deploy";
      };

      # Deploy using deploy-rs (remote via pixelkeepers.net:3322)
      deploy-rs-remote = {
        type = "app";
        program = "${shbPkgs.writeShellScript "deploy-rs-remote" ''
          exec ${deployPkgs.deploy-rs.deploy-rs}/bin/deploy .#nixos-core-remote "$@"
        ''}";
      };

      # Smart deploy - tries local, falls back to remote
      deploy = {
        type = "app";
        program = "${shbPkgs.writeShellScript "deploy-smart" ''
          echo "🚀 Smart deployment - trying local network first..."
          
          # Test local network connectivity
          if ${shbPkgs.openssh}/bin/ssh -o ConnectTimeout=5 -o IdentitiesOnly=yes -i ${./nixos-core/ssh} h4wkeye@192.168.68.20 true 2>/dev/null; then
            echo "✅ Local network available, deploying locally..."
            exec ${deployPkgs.deploy-rs.deploy-rs}/bin/deploy .#nixos-core "$@"
          else
            echo "🌐 Local network not available, deploying remotely..."
            exec ${deployPkgs.deploy-rs.deploy-rs}/bin/deploy .#nixos-core-remote "$@"
          fi
        ''}";
      };

      # Get 2FA codes from filesystem notifications
      get-2fa-codes = {
        type = "app";
        program = "${shbPkgs.writeShellScript "get-2fa-codes" ''
          set -e

          USERNAME="$1"

          echo "🔍 Fetching 2FA codes from Authelia filesystem notifications..."
          echo ""

          # Try local network first, fall back to remote
          if ${shbPkgs.openssh}/bin/ssh -o ConnectTimeout=5 -o IdentitiesOnly=yes -i ${./nixos-core/ssh} h4wkeye@192.168.68.20 true 2>/dev/null; then
            ${shbPkgs.openssh}/bin/ssh -o IdentitiesOnly=yes -i ${./nixos-core/ssh} h4wkeye@192.168.68.20 "
          else
            echo "Local network not available, trying remote access..."
            ${shbPkgs.openssh}/bin/ssh -o IdentitiesOnly=yes -i ${./nixos-core/ssh} -p 3322 h4wkeye@pixelkeepers.net "
            set -e

            # Find the systemd private temp directory for Authelia (not Redis)
            AUTHELIA_TEMP_DIR=\$(find /tmp -name 'systemd-private-*authelia-authelia*' -type d 2>/dev/null | head -1)

            if [[ -z \"\$AUTHELIA_TEMP_DIR\" ]]; then
              echo '❌ No systemd private temp directory found'
              exit 1
            fi

            NOTIFICATION_DIR=\"\$AUTHELIA_TEMP_DIR/tmp\"

            if ! sudo test -d \"\$NOTIFICATION_DIR\"; then
              echo \"❌ Notification directory not found: \$NOTIFICATION_DIR\"
              exit 1
            fi

            echo \"📁 Checking: \$NOTIFICATION_DIR\"
            echo \"\"

            # Find all notification files (with sudo for systemd private directories)
            NOTIFICATION_FILES=\$(sudo find \"\$NOTIFICATION_DIR\" -type f 2>/dev/null | sort -t_ -k2 -nr)

            if [[ -z \"\$NOTIFICATION_FILES\" ]]; then
              echo '⚠️  No notification files found'
              echo '💡 Try triggering a 2FA setup first'
              exit 0
            fi

            echo \"📧 Found notification files:\"
            echo \"\"

            for file in \$NOTIFICATION_FILES; do
              if sudo test -f \"\$file\"; then
                echo \"📄 \$(basename \"\$file\") - \$(sudo stat -c '%y' \"\$file\" | cut -d. -f1)\"

                if [[ -n \"$USERNAME\" ]]; then
                  if sudo grep -q \"$USERNAME\" \"\$file\" 2>/dev/null; then
                    echo \"👤 Content for '$USERNAME':\"
                    echo \"\"
                    sudo cat \"\$file\"
                    echo \"\"
                    echo \"═══════════════════════════════════════\"
                  fi
                else
                  echo \"📝 Content:\"
                  echo \"\"
                  sudo cat \"\$file\"
                  echo \"\"
                  echo \"═══════════════════════════════════════\"
                fi
              fi
            done
          "

          echo ""
          echo "💡 Usage: nix run .#get-2fa-codes [username]"
        ''}";
      };
    };
  };
}
