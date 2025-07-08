{ lib, pkgs, registerProvider, mkResult }:

registerProvider {
  name = "mysql";
  contract_type = "database";
  version = "1.0.0";
  description = "MySQL/MariaDB database provider";
  
  capabilities = {
    database_types = [ "mysql" ];
    extensions_support = false;
    backup_support = true;
    replication_support = true;
    connection_pooling = false;
    max_connections = 151;
  };
  
  configSchema = {
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.mariadb;
      description = "MySQL/MariaDB package to use";
    };
    
    port = lib.mkOption {
      type = lib.types.port;
      default = 3306;
      description = "MySQL port";
    };
    
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/mysql";
      description = "MySQL data directory";
    };
    
    bind_address = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address to bind to";
    };
    
    max_connections = lib.mkOption {
      type = lib.types.int;
      default = 151;
      description = "Maximum number of connections";
    };
    
    innodb_buffer_pool_size = lib.mkOption {
      type = lib.types.str;
      default = "128M";
      description = "InnoDB buffer pool size";
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
    request.payload.type == "mysql";
  
  # Fulfill the database request
  fulfill = request: providerConfig:
    let
      dbName = request.payload.name;
      dbUser = request.payload.user;
      passwordSecret = request.payload.password_secret;
      initialScript = request.payload.initial_script;
      
      # Connection string
      connectionString = "mysql://${dbUser}:$(cat ${passwordSecret})@${providerConfig.bind_address}:${toString providerConfig.port}/${dbName}";
      socketConnectionString = "mysql://${dbUser}:$(cat ${passwordSecret})@localhost/${dbName}?socket=/run/mysqld/mysqld.sock";
      
    in {
      config = {
        # MySQL/MariaDB service configuration
        services.mysql = {
          enable = true;
          package = providerConfig.package;
          port = providerConfig.port;
          dataDir = providerConfig.dataDir;
          bind = providerConfig.bind_address;
          
          settings = {
            mysqld = {
              max_connections = providerConfig.max_connections;
              innodb_buffer_pool_size = providerConfig.innodb_buffer_pool_size;
              
              # SSL configuration
              ssl = lib.mkIf providerConfig.enable_ssl "ON";
              ssl_cert = lib.mkIf (providerConfig.ssl_cert_path != null) providerConfig.ssl_cert_path;
              ssl_key = lib.mkIf (providerConfig.ssl_key_path != null) providerConfig.ssl_key_path;
              
              # Logging configuration
              general_log = "ON";
              general_log_file = "/var/log/mysql/general.log";
              slow_query_log = "ON";
              slow_query_log_file = "/var/log/mysql/slow.log";
              long_query_time = "2";
              
              # Security settings
              local_infile = "OFF";
              skip_show_database = "ON";
            };
          };
          
          # Database and user creation
          ensureDatabases = [ dbName ];
          ensureUsers = [
            {
              name = dbUser;
              ensurePermissions = {
                "${dbName}.*" = "ALL PRIVILEGES";
              };
            }
          ];
        };
        
        # Create database user password
        systemd.services.mysql-setup-${dbName} = {
          description = "Setup MySQL database ${dbName}";
          after = [ "mysql.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "mysql";
          };
          script = let
            setupScript = pkgs.writeShellScript "mysql-setup-${dbName}" ''
              set -e
              
              # Wait for MySQL to be ready
              while ! ${providerConfig.package}/bin/mysqladmin --socket=/run/mysqld/mysqld.sock ping >/dev/null 2>&1; do
                echo "Waiting for MySQL to start..."
                sleep 1
              done
              
              # Set user password
              if [ -f "${passwordSecret}" ]; then
                PASSWORD=$(cat "${passwordSecret}")
                ${providerConfig.package}/bin/mysql --socket=/run/mysqld/mysqld.sock -e \
                  "ALTER USER '${dbUser}'@'localhost' IDENTIFIED BY '$PASSWORD';" || true
              fi
              
              # Run initial script if provided
              ${lib.optionalString (initialScript != null) ''
                if [ -f "${initialScript}" ]; then
                  echo "Running initial script: ${initialScript}"
                  ${providerConfig.package}/bin/mysql --socket=/run/mysqld/mysqld.sock ${dbName} < "${initialScript}" || true
                fi
              ''}
              
              echo "MySQL database ${dbName} setup completed"
            '';
          in "${setupScript}";
        };
        
        # Backup configuration
        systemd.services.mysql-backup-${dbName} = {
          description = "Backup MySQL database ${dbName}";
          serviceConfig = {
            Type = "oneshot";
            User = "mysql";
          };
          script = let
            backupScript = pkgs.writeShellScript "mysql-backup-${dbName}" ''
              set -e
              
              BACKUP_DIR="/var/lib/mysql/backups"
              mkdir -p "$BACKUP_DIR"
              
              BACKUP_FILE="$BACKUP_DIR/${dbName}-$(date +%Y%m%d-%H%M%S).sql.gz"
              
              echo "Creating backup: $BACKUP_FILE"
              ${providerConfig.package}/bin/mysqldump --socket=/run/mysqld/mysqld.sock \
                --single-transaction --routines --triggers ${dbName} | \
                ${pkgs.gzip}/bin/gzip > "$BACKUP_FILE"
              
              # Clean up old backups
              find "$BACKUP_DIR" -name "${dbName}-*.sql.gz" -mtime +${toString providerConfig.backup_retention_days} -delete
              
              echo "Backup completed: $BACKUP_FILE"
            '';
          in "${backupScript}";
        };
        
        # Backup timer
        systemd.timers.mysql-backup-${dbName} = {
          description = "Timer for MySQL database ${dbName} backup";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "daily";
            Persistent = true;
            RandomizedDelaySec = "1h";
          };
        };
        
        # Ensure backup and log directories exist
        systemd.tmpfiles.rules = [
          "d /var/lib/mysql/backups 0750 mysql mysql -"
          "d /var/log/mysql 0750 mysql mysql -"
        ];
      };
      
      result = mkResult "database" {
        connection_string = connectionString;
        host = providerConfig.bind_address;
        port = providerConfig.port;
        socket_path = "/run/mysqld/mysqld.sock";
        backup_command = "${providerConfig.package}/bin/mysqldump --socket=/run/mysqld/mysqld.sock --single-transaction ${dbName}";
        restore_command = "${providerConfig.package}/bin/mysql --socket=/run/mysqld/mysqld.sock ${dbName}";
      } {
        provider_version = "1.0.0";
        mysql_package = providerConfig.package.name;
        database_name = dbName;
        database_user = dbUser;
        socket_connection_string = socketConnectionString;
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
    lib.optional (request.payload.extensions != []) "MySQL provider does not support extensions";
}