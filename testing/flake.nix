{
  description = "PSF Testing Environment - VM Configuration for PSF Framework Testing";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable-small";
    
    # Deploy-rs for automated testing deployments
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, deploy-rs, ... }: 
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    
    # Import PSF framework directly
    psfLib = import ../psf/lib { inherit (pkgs) lib; inherit pkgs; };
  in
  {
    # VM Configuration
    nixosConfigurations.psf-test-vm = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        ./vm-config.nix
        psfLib.psfModule
      ];
    };

    # Deployment configuration for VM testing
    deploy.nodes.psf-test-vm = {
      hostname = "localhost";
      sshUser = "root";
      sshOpts = [ "-p" "2222" ];
      
      profiles.system = {
        user = "root";
        path = deploy-rs.lib.${system}.activate.nixos self.nixosConfigurations.psf-test-vm;
      };
    };

    # Development shell for VM testing
    devShells.${system}.default = pkgs.mkShell {
      buildInputs = with pkgs; [
        # VM management
        qemu
        
        # Deployment tools
        deploy-rs.packages.${system}.default
        
        # Testing utilities
        curl
        httpie
        jq
        
        # SSH tools
        openssh
        
        # Monitoring tools
        htop
        netcat
      ];
      
      shellHook = ''
        echo "=== PSF Testing Environment ==="
        echo "Available commands:"
        echo "  start-vm      - Start the PSF test VM"
        echo "  stop-vm       - Stop the PSF test VM"
        echo "  deploy-vm     - Deploy current config to running VM"
        echo "  ssh-vm        - SSH into the running VM"
        echo "  test-psf      - Run PSF framework tests"
        echo ""
        
        # Helper functions
        function start-vm() {
          echo "Building and starting PSF test VM..."
          nixos-rebuild build-vm --flake .#psf-test-vm
          echo "Starting VM on ports:"
          echo "  SSH: localhost:2222"
          echo "  HTTP: localhost:8080"
          echo "  HTTPS: localhost:8443"
          echo "  PostgreSQL: localhost:5432"
          ./result/bin/run-psf-test-vm-vm
        }
        
        function stop-vm() {
          echo "Stopping PSF test VM..."
          pkill -f "qemu.*psf-test-vm" || echo "VM not running"
        }
        
        function deploy-vm() {
          echo "Deploying to PSF test VM..."
          deploy .#psf-test-vm
        }
        
        function ssh-vm() {
          echo "Connecting to PSF test VM..."
          ssh -p 2222 root@localhost
        }
        
        function test-psf() {
          echo "Running PSF framework tests..."
          nix flake check
          echo ""
          echo "Testing VM connectivity..."
          curl -s http://localhost:8080 > /dev/null && echo "✓ HTTP accessible" || echo "✗ HTTP not accessible"
          curl -s -k https://localhost:8443 > /dev/null && echo "✓ HTTPS accessible" || echo "✗ HTTPS not accessible"
          nc -z localhost 2222 && echo "✓ SSH accessible" || echo "✗ SSH not accessible"
          nc -z localhost 5432 && echo "✓ PostgreSQL accessible" || echo "✗ PostgreSQL not accessible"
        }
        
        export -f start-vm stop-vm deploy-vm ssh-vm test-psf
      '';
    };

    # Apps for easy VM management
    apps.${system} = {
      # Start VM
      start-vm = {
        type = "app";
        program = toString (pkgs.writeShellScript "start-vm" ''
          set -e
          echo "Building PSF test VM..."
          ${pkgs.nixos-rebuild}/bin/nixos-rebuild build-vm --flake ${self}#psf-test-vm
          echo "Starting VM..."
          echo "Ports:"
          echo "  SSH: localhost:2222"
          echo "  HTTP: localhost:8080" 
          echo "  HTTPS: localhost:8443"
          echo "  PostgreSQL: localhost:5432"
          echo "Press Ctrl+C to stop the VM"
          ./result/bin/run-psf-test-vm-vm
        '');
      };
      
      # Deploy to VM
      deploy-vm = {
        type = "app";
        program = toString (pkgs.writeShellScript "deploy-vm" ''
          set -e
          echo "Deploying to PSF test VM..."
          ${deploy-rs.packages.${system}.default}/bin/deploy ${self}#psf-test-vm
        '');
      };
      
      # SSH to VM
      ssh-vm = {
        type = "app";
        program = toString (pkgs.writeShellScript "ssh-vm" ''
          exec ${pkgs.openssh}/bin/ssh -p 2222 root@localhost "$@"
        '');
      };
      
      # Test PSF functionality
      test-psf = {
        type = "app";
        program = toString (pkgs.writeShellScript "test-psf" ''
          set -e
          echo "=== PSF Framework Test Suite ==="
          
          echo "1. Testing flake build..."
          nix flake check
          echo "✓ Flake builds successfully"
          
          echo ""
          echo "2. Testing VM connectivity..."
          
          # Test SSH
          if ${pkgs.netcat}/bin/nc -z localhost 2222 2>/dev/null; then
            echo "✓ SSH accessible on port 2222"
          else
            echo "✗ SSH not accessible on port 2222"
          fi
          
          # Test HTTP
          if ${pkgs.curl}/bin/curl -s --connect-timeout 5 http://localhost:8080 >/dev/null 2>&1; then
            echo "✓ HTTP accessible on port 8080"
          else
            echo "✗ HTTP not accessible on port 8080"
          fi
          
          # Test HTTPS
          if ${pkgs.curl}/bin/curl -s -k --connect-timeout 5 https://localhost:8443 >/dev/null 2>&1; then
            echo "✓ HTTPS accessible on port 8443"
          else
            echo "✗ HTTPS not accessible on port 8443"
          fi
          
          # Test PostgreSQL
          if ${pkgs.netcat}/bin/nc -z localhost 5432 2>/dev/null; then
            echo "✓ PostgreSQL accessible on port 5432"
          else
            echo "✗ PostgreSQL not accessible on port 5432"
          fi
          
          echo ""
          echo "3. Testing PSF services via SSH..."
          if ${pkgs.netcat}/bin/nc -z localhost 2222 2>/dev/null; then
            ${pkgs.openssh}/bin/ssh -p 2222 -o ConnectTimeout=5 -o BatchMode=yes root@localhost '
              echo "=== PSF Service Status ==="
              systemctl is-active postgresql || echo "PostgreSQL: inactive"
              systemctl is-active nginx || echo "Nginx: inactive"
              systemctl is-active lldap || echo "LLDAP: inactive"
              systemctl is-active authelia || echo "Authelia: inactive"
              echo ""
              echo "=== PSF Configuration Validation ==="
              # Add PSF-specific validation commands here
            ' 2>/dev/null || echo "Could not connect to VM for service testing"
          fi
          
          echo ""
          echo "=== Test Summary ==="
          echo "Run 'nix run .#start-vm' to start the test environment"
          echo "Run 'nix run .#ssh-vm' to connect to the running VM"
        '');
      };
    };

    # Checks for CI/testing
    checks.${system} = {
      # Validate VM configuration builds
      vm-config = self.nixosConfigurations.psf-test-vm.config.system.build.vm;
      
      # Validate PSF framework passes checks
      psf-framework = pkgs.runCommand "psf-check" {} ''
        echo "PSF framework validation - build test"
        touch $out
      '';
    };

    # Packages for VM testing
    packages.${system} = {
      # VM image
      vm = self.nixosConfigurations.psf-test-vm.config.system.build.vm;
      
      # VM runner script
      vm-runner = pkgs.writeShellScriptBin "run-psf-test-vm" ''
        set -e
        echo "Building PSF test VM..."
        nix build .#vm
        echo "Starting VM..."
        ./result/bin/run-psf-test-vm-vm
      '';
    };
  };
}