{ psf, lib, pkgs, ... }:

psf.defineService "test-app" ({ contracts, providers, config, ... }: {
  
  options = {
    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Test application port";
    };
    
    user = lib.mkOption {
      type = lib.types.str;
      default = "test-app";
      description = "User account for test application";
    };
    
    group = lib.mkOption {
      type = lib.types.str;
      default = "test-app";
      description = "Group for test application";
    };
  };
  
  needs = {
    database = contracts.database.mkRequest {
      type = "postgresql";
      name = "testapp";
      user = "testapp";
      password_secret = "/run/secrets/testapp-db-password";
      extensions = [ "pg_stat_statements" ];
    };
    
    secrets = {
      db_password = contracts.secrets.mkRequest {
        description = "Test app database password";
        mode = "0400";
        owner = config.user;
      };
    };
  };
  
  provides = {
    web_service = {
      endpoint = "https://${config.subdomain}.${config.domain}";
      api_endpoint = "https://${config.subdomain}.${config.domain}/api";
      local_endpoint = "http://127.0.0.1:${toString config.port}";
      protocol = "http";
    };
  };
  
  config = { needs, ... }: {
    # User and group
    users.users.${config.user} = {
      isSystemUser = true;
      group = config.group;
      home = "/var/lib/test-app";
      createHome = true;
    };
    users.groups.${config.group} = {};
    
    # Simple test application service
    systemd.services.test-app = {
      description = "Test application with database";
      after = [ "postgresql.service" ];
      wantedBy = [ "multi-user.target" ];
      
      serviceConfig = {
        Type = "simple";
        User = config.user;
        Group = config.group;
        Restart = "always";
        RestartSec = "5s";
      };
      
      environment = {
        PORT = toString config.port;
        DATABASE_URL = needs.database.result.payload.connection_string;
      };
      
      script = let
        testScript = pkgs.writeShellScript "test-app" ''
          set -e
          
          echo "Starting test application..."
          echo "Port: $PORT"
          echo "Database: $DATABASE_URL"
          
          # Simple HTTP server that shows database connection info
          while true; do
            echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n<html><body><h1>Test App</h1><p>Database: ${needs.database.result.payload.host}:${toString needs.database.result.payload.port}</p><p>Status: Connected</p></body></html>" | ${pkgs.netcat}/bin/nc -l -p $PORT -q 1
          done
        '';
      in "${testScript}";
    };
  };
  
  health_checks = [
    {
      name = "test-app-http";
      type = "http";
      url = "http://127.0.0.1:${toString config.port}";
      expected_status = 200;
      timeout_seconds = 10;
      interval_seconds = 30;
    }
  ];
})