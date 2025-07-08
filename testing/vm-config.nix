# NixOS VM Configuration for PSF Testing
# This configuration creates a minimal VM environment for testing PSF framework
# deployment and service functionality before production deployment.

{ config, lib, pkgs, modulesPath, ... }:

let
  # Test user credentials
  testUser = "psftest";
  testPassword = "test123";  # Only for testing - never use in production
in

{
  imports = [
    (modulesPath + "/virtualisation/qemu-vm.nix")
    # PSF module will be imported by the flake
  ];

  # VM Configuration
  virtualisation = {
    # VM Resources
    memorySize = 4096;  # 4GB RAM
    cores = 2;          # 2 CPU cores
    diskSize = 20480;   # 20GB disk
    
    # Graphics and console
    graphics = false;   # Headless for automation
    
    # Networking
    forwardPorts = [
      { from = "host"; host.port = 2222; guest.port = 22; }    # SSH
      { from = "host"; host.port = 8080; guest.port = 80; }    # HTTP
      { from = "host"; host.port = 8443; guest.port = 443; }   # HTTPS
      { from = "host"; host.port = 5432; guest.port = 5432; }  # PostgreSQL
      { from = "host"; host.port = 3000; guest.port = 3000; }  # Test services
    ];
    
    # Shared directories for testing
    sharedDirectories = {
      psf-source = {
        source = toString ../psf;
        target = "/mnt/psf-source";
      };
      test-data = {
        source = toString ./data;
        target = "/mnt/test-data";
      };
    };
  };

  # Basic system configuration
  system.stateVersion = "25.05";
  
  # Boot configuration
  boot = {
    # Use systemd-boot for VMs
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    
    # Enable necessary kernel modules
    initrd.kernelModules = [ "virtio_net" "virtio_pci" "virtio_blk" "virtio_scsi" ];
  };

  # Network configuration
  networking = {
    hostName = "psf-test-vm";
    domain = "test.local";
    
    # Use DHCP for simplicity in VM
    useDHCP = true;
    
    # Firewall configuration for testing
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 80 443 5432 3000 ];
      allowedUDPPorts = [ 53 ];
    };
  };
  
  # Systemd network configuration
  systemd.network = {
    enable = true;
    networks."10-eth" = {
      matchConfig.Name = "eth*";
      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
      };
    };
  };

  # User management
  users = {
    # Disable mutable users for testing consistency
    mutableUsers = false;
    
    # Root user with production SSH key
    users.root = {
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGy3TwOBhm0B9JJOqTjKalSOT8n8PabTBk/nTdX8H9Nw h4wkeye@h4wkeye-dev"
      ];
    };
    
    # Test user with production SSH key
    users."${testUser}" = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      password = testPassword;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGy3TwOBhm0B9JJOqTjKalSOT8n8PabTBk/nTdX8H9Nw h4wkeye@h4wkeye-dev"
      ];
    };
  };

  # SSH configuration
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";  # Only for testing
      PasswordAuthentication = true;  # Only for testing
      PubkeyAuthentication = true;
    };
  };

  # Essential system packages
  environment.systemPackages = with pkgs; [
    # System utilities
    curl
    wget
    jq
    yq
    git
    
    # Network utilities
    netcat
    httpie
    dig
    
    # Monitoring and debugging
    htop
    iotop
    tcpdump
    strace
    
    # Text editors
    nano
    vim
    
    # Development tools
    nix-tree
    nixpkgs-fmt
    statix
  ];

  # Time and locale
  time.timeZone = "Europe/Warsaw";
  i18n.defaultLocale = "en_US.UTF-8";

  # Systemd configuration for testing
  systemd = {
    # Faster boot for testing
    extraConfig = ''
      DefaultTimeoutStopSec=10s
      DefaultTimeoutStartSec=10s
    '';
    
    # Enable systemd-resolved for consistent DNS
    services.systemd-resolved.enable = true;
  };

  # PSF Framework Configuration
  psf = {
    enable = true;
    domain = "test.local";
    
    # Configure test providers using existing PSF providers
    providers = {
      # SSL provider (self-signed for testing)
      selfsigned = {
        domain = "test.local";
      };
      
      # Database provider (PostgreSQL)
      postgresql = {
        version = "17";
        settings = {
          max_connections = "50";
          shared_buffers = "256MB";
        };
      };
      
      # Secrets provider (hardcoded for testing)
      hardcoded = {
        secrets = {
          test-secret = "test-value";
          db-password = "testdbpass123";
        };
      };
      
      # Backup provider (borg for testing)
      borg = {
        repository = "/var/lib/borg-backups";
        passphrase = "test-passphrase-123";
      };
      
      # Proxy provider (nginx)
      nginx = {
        enable = true;
      };
      
      # LDAP provider for authentication testing
      lldap = {
        domain = "test.local";
        adminPassword = "testadmin123";
      };
      
      # SSO provider for testing
      authelia = {
        domain = "test.local";
        jwtSecret = "test-jwt-secret-123";
      };
    };
    
    # Test services - these need to be properly defined PSF services
    services = {
      # These would be actual PSF services defined with defineService
      # For now, let's just enable the framework without specific services
    };
  };

  # Development tools
  programs = {
    # Enable nix-ld for running non-NixOS binaries
    nix-ld.enable = true;
    
    # Git configuration
    git = {
      enable = true;
      config = {
        init.defaultBranch = "main";
        user.name = "PSF Tester";
        user.email = "test@psf.test";
      };
    };
  };

  # Logging configuration
  services.journald = {
    extraConfig = ''
      SystemMaxUse=1G
      MaxRetentionSec=1week
    '';
  };

  # Automatic garbage collection
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
    };
    
    gc = {
      automatic = true;
      dates = "daily";
      options = "--delete-older-than 3d";
    };
  };
}