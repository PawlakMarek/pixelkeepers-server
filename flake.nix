{
  description = "Ibizaman's config.";

  inputs = {
    selfhostblocks.url = "path:./shb-fork";

    skarabox.url = "github:ibizaman/skarabox";
    skarabox.inputs.nixpkgs.follows = "selfhostblocks/nixpkgs";

    deploy-rs.url = "github:serokell/deploy-rs";

    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs = {
    self,
    skarabox,
    selfhostblocks,
    sops-nix,
    deploy-rs,
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

    # Used with deploy-rs for updates.
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
    # From https://github.com/serokell/deploy-rs?tab=readme-ov-file#overall-usage
    checks = builtins.mapAttrs (_system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;

    # Apps for server management
    apps.${system} = {
      sops = {
        type = "app";
        program = "${shbPkgs.sops}/bin/sops";
      };

      # SSH access to nixos-core
      nixos-core-ssh = {
        type = "app";
        program = "${shbPkgs.writeShellScript "nixos-core-ssh" ''
          exec ${shbPkgs.openssh}/bin/ssh -o IdentitiesOnly=yes -i ${./nixos-core/ssh} h4wkeye@192.168.68.20 "$@"
        ''}";
      };

      # Unlock root pool after reboot
      nixos-core-unlock = {
        type = "app";
        program = "${shbPkgs.writeShellScript "nixos-core-unlock" ''
          echo "Unlocking root pool on nixos-core..."
          ${shbPkgs.openssh}/bin/ssh -o IdentitiesOnly=yes -i ${./nixos-core/ssh} h4wkeye@192.168.68.20 \
            "echo '$(${shbPkgs.sops}/bin/sops --decrypt --extract '[\"nixos-core\"][\"disks\"][\"rootPassphrase\"]' ${./nixos-core/secrets.yaml})' | sudo zfs load-key root"
        ''}";
      };

      # Deploy using deploy-rs
      deploy-rs = {
        type = "app";
        program = "${deployPkgs.deploy-rs.deploy-rs}/bin/deploy";
      };

      # Get 2FA codes from filesystem notifications
      get-2fa-codes = {
        type = "app";
        program = "${shbPkgs.writeShellScript "get-2fa-codes" ''
          set -e

          USERNAME="$1"

          echo "🔍 Fetching 2FA codes from Authelia filesystem notifications..."
          echo ""

          ${shbPkgs.openssh}/bin/ssh -o IdentitiesOnly=yes -i ${./nixos-core/ssh} h4wkeye@192.168.68.20 "
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
