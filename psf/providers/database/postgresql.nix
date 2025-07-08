{ lib, pkgs, registerProvider, mkResult }:

registerProvider {
  name = "postgresql";
  contract_type = "database";
  version = "1.0.0";
  description = "PostgreSQL database provider";
  
  capabilities = {
    database_types = [ "postgresql" ];
    extensions_support = true;
    backup_support = true;
    replication_support = true;
    connection_pooling = false; # Requires separate provider/service
    max_connections = 100;
  };
  
  configSchema = {
    version = lib.mkOption {
      type = lib.types.str;
      default = "17";
      description = "PostgreSQL version to use";
    };
    
    port = lib.mkOption {
      type = lib.types.port;
      default = 5432;
      description = "PostgreSQL port";
    };
    
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/postgresql";
      description = "PostgreSQL data directory";
    };
    
    listen_addresses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "127.0.0.1" ];
      description = "Addresses to listen on";
    };
    
    max_connections = lib.mkOption {
      type = lib.types.int;
      default = 100;
      description = "Maximum number of connections";
    };
    
    shared_buffers = lib.mkOption {
      type = lib.types.str;
      default = "128MB";
      description = "Shared buffers size";
    };
    
    enable_ssl = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable SSL connections";
    };
    
    ssl_cert_path = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "SSL certificate path";
    };
    
    ssl_key_path = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "SSL private key path";
    };
    
    backup_retention_days = lib.mkOption {
      type = lib.types.int;
      default = 7;
      description = "Number of days to retain backups";
    };
  };
  
  # Check if this provider can fulfill the request
  canFulfill = request: 
    request.contract_type == "database" && 
    request.payload.type == "postgresql";
  
  # Fulfill the database request
  fulfill = request: providerConfig:
    let
      dbName = request.payload.name;
      dbUser = request.payload.user;
      passwordSecret = request.payload.password_secret;
      extensions = request.payload.extensions;
      initialScript = request.payload.initial_script;
      
      # PostgreSQL package selection based on version
      postgresqlPackage = 
        if providerConfig.version == "17" then pkgs.postgresql_17
        else if providerConfig.version == "16" then pkgs.postgresql_16
        else if providerConfig.version == "15" then pkgs.postgresql_15
        else if providerConfig.version == "14" then pkgs.postgresql_14
        else if providerConfig.version == "13" then pkgs.postgresql_13
        else pkgs.postgresql_17; # Default to 17
      
      # Build extensions package if extensions are requested
      postgresqlWithExtensions = 
        if extensions != [] then
          postgresqlPackage.withPackages (ps: map (ext: 
            if ext == "postgis" then ps.postgis
            else if ext == "pg_cron" then ps.pg_cron
            else if ext == "timescaledb" then ps.timescaledb
            else if ext == "pg_stat_statements" then ps.pg_stat_statements
            else throw "Unsupported PostgreSQL extension: ${ext}"
          ) extensions)
        else postgresqlPackage;
      
      # Connection string components
      connectionString = "postgresql://${dbUser}:$(cat ${passwordSecret})@${lib.concatStringsSep "," providerConfig.listen_addresses}:${toString providerConfig.port}/${dbName}";
      socketConnectionString = "postgresql://${dbUser}:$(cat ${passwordSecret})@/${dbName}?host=/run/postgresql";
      
    in {
      config = {
        # PostgreSQL service configuration
        services.postgresql = {
          enable = true;
          package = postgresqlWithExtensions;
          port = providerConfig.port;
          dataDir = providerConfig.dataDir;
          
          settings = {
            listen_addresses = lib.concatStringsSep "," providerConfig.listen_addresses;
            max_connections = providerConfig.max_connections;
            shared_buffers = providerConfig.shared_buffers;
            
            # Enable SSL if requested
            ssl = providerConfig.enable_ssl;
            ssl_cert_file = lib.optionalString (providerConfig.ssl_cert_path != null) providerConfig.ssl_cert_path;
            ssl_key_file = lib.optionalString (providerConfig.ssl_key_path != null) providerConfig.ssl_key_path;
            
            # Enable extensions in shared_preload_libraries
            shared_preload_libraries = lib.concatStringsSep "," (
              lib.filter (ext: lib.elem ext [ "pg_stat_statements" "pg_cron" "timescaledb" ]) extensions
            );
            
            # Logging configuration
            log_destination = "stderr";
            log_line_prefix = "%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h ";
            log_statement = "mod";
            log_min_duration_statement = 1000;
          };
          
          # Authentication configuration
          authentication = ''
            # Allow local connections
            local all all trust
            
            # Allow connections from localhost
            host all all 127.0.0.1/32 md5
            host all all ::1/128 md5
            
            # Allow connections from configured addresses
            ${lib.concatMapStringsSep "\n" (addr: 
              "host all all ${addr}/32 md5"
            ) (lib.filter (addr: addr != "127.0.0.1" && addr != "localhost") providerConfig.listen_addresses)}
          '';
          
          # Database and user creation
          ensureDatabases = [ dbName ];
          ensureUsers = [
            {
              name = dbUser;
              ensureDBOwnership = true;
            }
          ];
        };
        
        # Create database user password
        systemd.services.postgresql-setup-${dbName} = {
          description = "Setup PostgreSQL database ${dbName}";
          after = [ "postgresql.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "postgres";
          };
          script = let
            setupScript = pkgs.writeShellScript "postgresql-setup-${dbName}" ''
              set -e
              
              # Wait for PostgreSQL to be ready
              while ! ${postgresqlWithExtensions}/bin/pg_isready -h /run/postgresql >/dev/null 2>&1; do
                echo "Waiting for PostgreSQL to start..."
                sleep 1
              done
              
              # Set user password
              if [ -f "${passwordSecret}" ]; then
                PASSWORD=$(cat "${passwordSecret}")
                ${postgresqlWithExtensions}/bin/psql -h /run/postgresql -d postgres -c \
                  "ALTER USER ${dbUser} WITH PASSWORD '$PASSWORD';" || true
              fi
              
              # Create extensions
              ${lib.concatMapStringsSep "\n" (ext: ''
                echo "Creating extension: ${ext}"
                ${postgresqlWithExtensions}/bin/psql -h /run/postgresql -d ${dbName} -c \
                  "CREATE EXTENSION IF NOT EXISTS ${ext};" || true
              '') extensions}
              
              # Run initial script if provided
              ${lib.optionalString (initialScript != null) ''
                if [ -f "${initialScript}" ]; then
                  echo "Running initial script: ${initialScript}"
                  ${postgresqlWithExtensions}/bin/psql -h /run/postgresql -d ${dbName} -f "${initialScript}" || true
                fi
              ''}
              
              echo "PostgreSQL database ${dbName} setup completed"
            '';
          in "${setupScript}";
        };
        
        # Backup configuration
        systemd.services.postgresql-backup-${dbName} = {
          description = "Backup PostgreSQL database ${dbName}";
          serviceConfig = {
            Type = "oneshot";
            User = "postgres";
          };
          script = let
            backupScript = pkgs.writeShellScript "postgresql-backup-${dbName}" ''
              set -e
              
              BACKUP_DIR="/var/lib/postgresql/backups"
              mkdir -p "$BACKUP_DIR"
              
              BACKUP_FILE="$BACKUP_DIR/${dbName}-$(date +%Y%m%d-%H%M%S).sql.gz"
              
              echo "Creating backup: $BACKUP_FILE"
              ${postgresqlWithExtensions}/bin/pg_dump -h /run/postgresql -d ${dbName} | \
                ${pkgs.gzip}/bin/gzip > "$BACKUP_FILE"
              
              # Clean up old backups
              find "$BACKUP_DIR" -name "${dbName}-*.sql.gz" -mtime +${toString providerConfig.backup_retention_days} -delete
              
              echo "Backup completed: $BACKUP_FILE"
            '';
          in "${backupScript}";
        };
        
        # Backup timer
        systemd.timers.postgresql-backup-${dbName} = {
          description = "Timer for PostgreSQL database ${dbName} backup";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "daily";
            Persistent = true;
            RandomizedDelaySec = "1h";
          };
        };
        
        # Ensure backup directory exists
        systemd.tmpfiles.rules = [
          "d /var/lib/postgresql/backups 0750 postgres postgres -"
        ];
      };
      
      result = mkResult "database" {
        connection_string = connectionString;
        host = lib.head providerConfig.listen_addresses;
        port = providerConfig.port;
        socket_path = "/run/postgresql";
        backup_command = "${postgresqlWithExtensions}/bin/pg_dump -h /run/postgresql -d ${dbName}";
        restore_command = "${postgresqlWithExtensions}/bin/psql -h /run/postgresql -d ${dbName}";
      } {
        provider_version = "1.0.0";
        postgresql_version = providerConfig.version;
        database_name = dbName;
        database_user = dbUser;
        socket_connection_string = socketConnectionString;
        extensions_enabled = extensions;
      };
    };
  
  # Validate provider configuration and request
  validate = request: providerConfig: 
    lib.optional (request.payload.name == null) "Database name must be specified" ++
    lib.optional (request.payload.user == null) "Database user must be specified" ++
    lib.optional (request.payload.password_secret == null) "Database password secret must be specified" ++
    lib.optional (providerConfig.enable_ssl && (providerConfig.ssl_cert_path == null || providerConfig.ssl_key_path == null)) 
      "SSL certificate and key paths required when SSL is enabled" ++
    lib.optional (providerConfig.max_connections < 1) "max_connections must be greater than 0" ++
    lib.optional (!lib.elem providerConfig.version [ "13" "14" "15" "16" "17" ]) 
      "Unsupported PostgreSQL version: ${providerConfig.version}";
}