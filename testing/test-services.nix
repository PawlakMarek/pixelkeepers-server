# Test Services Configuration for PSF Framework
# This file defines minimal test services to validate PSF functionality

{ config, lib, pkgs, ... }:

{
  # Simple HTTP test service
  services.test-web = {
    enable = true;
    
    # Service configuration
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 -m http.server 3000";
      WorkingDirectory = "/var/lib/test-web";
      User = "test-web";
      Group = "test-web";
      Restart = "always";
      RestartSec = "5s";
    };
    
    # Create user and directories
    users.users.test-web = {
      isSystemUser = true;
      group = "test-web";
      home = "/var/lib/test-web";
      createHome = true;
    };
    
    users.groups.test-web = {};
    
    # Test content
    systemd.tmpfiles.rules = [
      "d /var/lib/test-web 0755 test-web test-web -"
      "f /var/lib/test-web/index.html 0644 test-web test-web - <!DOCTYPE html><html><head><title>PSF Test Service</title></head><body><h1>PSF Framework Test Service</h1><p>This is a test service running in the PSF testing environment.</p><p>Time: $(date)</p></body></html>"
    ];
  };

  # PostgreSQL test database setup
  services.postgresql = {
    ensureDatabases = [ "testdb" "psf_test" ];
    ensureUsers = [
      {
        name = "testuser";
        ensureDBOwnership = true;
      }
    ];
  };

  # Test health checks
  systemd.services.psf-health-check = {
    description = "PSF Framework Health Check";
    after = [ "network.target" "postgresql.service" "nginx.service" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "psf-health-check" ''
        set -e
        
        echo "=== PSF Health Check ==="
        
        # Check PostgreSQL
        ${pkgs.postgresql}/bin/psql -U postgres -c "SELECT version();" > /dev/null
        echo "✓ PostgreSQL responsive"
        
        # Check Nginx
        ${pkgs.curl}/bin/curl -s http://localhost/ > /dev/null
        echo "✓ Nginx responsive"
        
        # Check test web service
        ${pkgs.curl}/bin/curl -s http://localhost:3000/ > /dev/null
        echo "✓ Test web service responsive"
        
        echo "=== All PSF services healthy ==="
      '';
    };
    
    # Run health check every 5 minutes
    startAt = "*:0/5";
  };

  # Firewall rules for test services
  networking.firewall.allowedTCPPorts = [ 3000 ];
}