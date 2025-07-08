{ lib, pkgs, registerProvider }:

let
  # Import mkResult from contracts
  mkResult = (import ../../lib/contracts.nix { inherit lib pkgs; }).mkResult;
in

registerProvider {
  name = "authelia";
  contract_type = "sso";
  version = "1.0.0";
  description = "Authelia authentication and authorization server with flexible database support";
  
  capabilities = {
    protocols = [ "oidc" "oauth2" ];
    mfa_support = true;
    ldap_integration = true;
    policy_engine = true;
    session_management = true;
    user_provisioning = false;
    group_management = false;
    password_reset = true;
    brute_force_protection = true;
    regulation = true;
    database_support = [ "postgresql" "mysql" "sqlite" ];
    ha_support = true; # When using external database
  };
  
  configSchema = {
    port = lib.mkOption {
      type = lib.types.port;
      default = 9091;
      description = "Authelia port";
    };
    
    domain = lib.mkOption {
      type = lib.types.str;
      description = "Authelia domain (e.g., auth.example.com)";
    };
    
    # Database configuration - will be overridden if database contract is available
    database_preference = lib.mkOption {
      type = lib.types.enum [ "auto" "postgresql" "mysql" "sqlite" ];
      default = "auto";
      description = "Preferred database type (auto = use PSF provider priority)";
    };
    
    # LDAP integration settings
    ldap_url = lib.mkOption {
      type = lib.types.str;
      description = "LDAP server URL";
    };
    
    ldap_base_dn = lib.mkOption {
      type = lib.types.str;
      description = "LDAP base DN";
    };
    
    ldap_user_base_dn = lib.mkOption {
      type = lib.types.str;
      description = "LDAP user base DN";
    };
    
    ldap_group_base_dn = lib.mkOption {
      type = lib.types.str;
      description = "LDAP group base DN";
    };
    
    ldap_bind_dn = lib.mkOption {
      type = lib.types.str;
      description = "LDAP bind DN";
    };
    
    ldap_bind_password_secret = lib.mkOption {
      type = lib.types.str;
      description = "Path to LDAP bind password secret";
    };
    
    # Authelia secrets
    jwt_secret_path = lib.mkOption {
      type = lib.types.str;
      description = "Path to JWT secret";
    };
    
    session_secret_path = lib.mkOption {
      type = lib.types.str;
      description = "Path to session secret";
    };
    
    storage_encryption_key_path = lib.mkOption {
      type = lib.types.str;
      description = "Path to storage encryption key";
    };
    
    issuer_private_key_path = lib.mkOption {
      type = lib.types.str;
      description = "Path to OIDC issuer private key";
    };
    
    # Additional configuration
    default_redirection_url = lib.mkOption {
      type = lib.types.str;
      default = "https://google.com";
      description = "Default redirection URL after authentication";
    };
    
    log_level = lib.mkOption {
      type = lib.types.enum [ "trace" "debug" "info" "warn" "error" ];
      default = "info";
      description = "Authelia log level";
    };
    
    # Session configuration
    session_expiration = lib.mkOption {
      type = lib.types.str;
      default = "1h";
      description = "Session expiration time";
    };
    
    session_inactivity = lib.mkOption {
      type = lib.types.str;
      default = "5m";
      description = "Session inactivity timeout";
    };
    
    # Security settings
    max_retries = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = "Maximum authentication retries";
    };
    
    ban_time = lib.mkOption {
      type = lib.types.str;
      default = "5m";
      description = "Ban time after max retries exceeded";
    };
  };
  
  canFulfill = request: 
    request.contract_type == "sso";
  
  fulfill = request: providerConfig:
    let
      # Determine if we should try to use a database contract
      use_database_contract = providerConfig.database_preference != "sqlite";
      
      # Build database contract request if needed
      database_request = lib.optionalAttrs use_database_contract {
        database = (import ../../contracts/database.nix { inherit lib pkgs; mkRequest = (import ../../lib/contracts.nix { inherit lib pkgs; }).mkRequest; mkResult = mkResult; }).mkRequest {
          type = if providerConfig.database_preference == "auto" then "postgresql" else providerConfig.database_preference;
          name = "authelia";
          user = "authelia";
          password_secret = "/run/secrets/authelia-db-password";
          extensions = lib.optionals (providerConfig.database_preference == "postgresql" || providerConfig.database_preference == "auto") [ "pg_stat_statements" ];
        };
      };
      
      # Mock needs structure for now - in real implementation this would come from contract resolution
      # For the provider implementation, we'll assume the contract system will provide this
      needs = database_request;
      
      # Determine storage configuration based on available database
      storage_config = 
        if needs ? database then
          # Use external database
          if needs.database.payload.type == "postgresql" then {
            postgres = {
              host = "127.0.0.1"; # Will be replaced by actual contract result
              port = 5432;
              database = "authelia";
              username = "authelia";
              password = "file://${needs.database.payload.password_secret}";
              sslmode = "disable";
              timeout = "5s";
            };
          }
          else if needs.database.payload.type == "mysql" then {
            mysql = {
              host = "127.0.0.1"; # Will be replaced by actual contract result
              port = 3306;
              database = "authelia";
              username = "authelia";
              password = "file://${needs.database.payload.password_secret}";
              timeout = "5s";
            };
          }
          else throw "Unsupported database type for Authelia: ${needs.database.payload.type}"
        else {
          # SQLite fallback
          local = {
            path = "/var/lib/authelia/db.sqlite3";
          };
        };
      
      # OIDC client configuration
      client_config = {
        id = request.payload.client_id;
        description = "PSF managed client: ${request.payload.client_id}";
        secret = "$pbkdf2-sha512$310000$c8p78n7pUMln0jzvd4aK4Q$JNRBzwAo0ek5qKn50cFzzvE9RXV88h1wJn5KGiHCy928YkuMSwr9pLAhUR9jGKX7aOGGssPzxQHdGCzJ8yB3ag"; # Example hash - should be generated
        redirect_uris = request.payload.redirect_uris;
        scopes = request.payload.scopes;
        grant_types = [ "authorization_code" "refresh_token" ];
        response_types = [ "code" ];
        authorization_policy = request.payload.access_policy;
      };
      
      # Extract domain from first redirect URI for access control
      first_redirect_uri = lib.head request.payload.redirect_uris;
      redirect_domain = lib.head (lib.tail (lib.splitString "://" first_redirect_uri));
      access_domain = lib.head (lib.splitString "/" redirect_domain);
      
      # Access control rule configuration
      access_control_rule = {
        domain = access_domain;
        policy = request.payload.access_policy;
      } // lib.optionalAttrs (request.payload.allowed_groups != []) {
        subject = map (group: "group:${group}") request.payload.allowed_groups;
      } // lib.optionalAttrs (request.payload.allowed_users != []) {
        subject = map (user: "user:${user}") request.payload.allowed_users;
      };
      
      # Database type for metadata
      database_type = 
        if needs ? database then needs.database.payload.type
        else "sqlite";
      
    in {
      # This will be passed back to PSF to indicate this provider needs a database contract
      needs = database_request;
      
      config = {
        services.authelia.instances.main = {
          enable = true;
          settings = {
            server = {
              host = "0.0.0.0";
              port = providerConfig.port;
            };
            
            log = {
              level = providerConfig.log_level;
              format = "text";
              file_path = "/var/lib/authelia/authelia.log";
            };
            
            totp = {
              issuer = providerConfig.domain;
            };
            
            authentication_backend = {
              ldap = {
                implementation = "custom";
                url = providerConfig.ldap_url;
                base_dn = providerConfig.ldap_base_dn;
                username_attribute = "uid";
                additional_users_dn = providerConfig.ldap_user_base_dn;
                users_filter = "(&({username_attribute}={input})(objectClass=person))";
                additional_groups_dn = providerConfig.ldap_group_base_dn;
                groups_filter = "(member={dn})";
                group_name_attribute = "cn";
                mail_attribute = "mail";
                display_name_attribute = "displayName";
                user = providerConfig.ldap_bind_dn;
                password = "file://${providerConfig.ldap_bind_password_secret}";
              };
            };
            
            access_control = {
              default_policy = "deny";
              rules = [ access_control_rule ];
            };
            
            session = {
              name = "authelia_session";
              domain = providerConfig.domain;
              secret = "file://${providerConfig.session_secret_path}";
              expiration = providerConfig.session_expiration;
              inactivity = providerConfig.session_inactivity;
              remember_me_duration = "1M";
            };
            
            regulation = {
              max_retries = providerConfig.max_retries;
              find_time = "2m";
              ban_time = providerConfig.ban_time;
            };
            
            # Dynamic storage configuration
            storage = storage_config // {
              encryption_key = "file://${providerConfig.storage_encryption_key_path}";
            };
            
            notifier = {
              disable_startup_check = true;
              filesystem = {
                filename = "/var/lib/authelia/notification.txt";
              };
            };
            
            identity_providers = {
              oidc = {
                hmac_secret = "file://${providerConfig.jwt_secret_path}";
                issuer_private_key = "file://${providerConfig.issuer_private_key_path}";
                access_token_lifespan = "1h";
                authorize_code_lifespan = "1m";
                id_token_lifespan = "1h";
                refresh_token_lifespan = "90m";
                clients = [ client_config ];
              };
            };
          };
        };
        
        # Ensure Authelia directories exist
        systemd.tmpfiles.rules = [
          "d /var/lib/authelia 0750 authelia authelia -"
        ];
        
        # User and group for Authelia
        users.users.authelia = {
          group = "authelia";
          isSystemUser = true;
          home = "/var/lib/authelia";
          createHome = true;
        };
        users.groups.authelia = {};
        
        # Database initialization service (only for external databases)
        systemd.services.authelia-db-init = lib.mkIf (database_type != "sqlite") {
          description = "Initialize Authelia database schema";
          after = [ "${database_type}.service" ];
          wantedBy = [ "authelia.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "authelia";
          };
          script = let
            initScript = pkgs.writeShellScript "authelia-db-init" ''
              set -e
              echo "Initializing Authelia database schema..."
              # Database schema initialization would happen here
              # Authelia handles this automatically on first run
              echo "Database initialization completed"
            '';
          in "${initScript}";
        };
      };
      
      result = mkResult "sso" {
        issuer_url = "https://${providerConfig.domain}/api/oidc";
        authorization_endpoint = "https://${providerConfig.domain}/api/oidc/authorization";
        token_endpoint = "https://${providerConfig.domain}/api/oidc/token";
        userinfo_endpoint = "https://${providerConfig.domain}/api/oidc/userinfo";
        client_secret_path = "/run/secrets/authelia-client-${request.payload.client_id}";
        auth_request_headers = {
          "X-Original-URL" = "$scheme://$http_host$request_uri";
          "X-Forwarded-Method" = "$request_method";
          "X-Forwarded-Proto" = "$scheme";
          "X-Forwarded-Host" = "$http_host";
          "X-Forwarded-Uri" = "$request_uri";
          "X-Forwarded-For" = "$proxy_add_x_forwarded_for";
        };
        nginx_auth_config = ''
          # Authelia authentication configuration
          auth_request /authelia;
          auth_request_set $user $upstream_http_remote_user;
          auth_request_set $groups $upstream_http_remote_groups;
          auth_request_set $name $upstream_http_remote_name;
          auth_request_set $email $upstream_http_remote_email;
          error_page 401 = @authelia_redirect;
          
          # Forward auth headers to backend
          proxy_set_header Remote-User $user;
          proxy_set_header Remote-Groups $groups;
          proxy_set_header Remote-Name $name;
          proxy_set_header Remote-Email $email;
          
          location /authelia {
            internal;
            proxy_pass http://127.0.0.1:${toString providerConfig.port}/api/verify;
            proxy_pass_request_body off;
            proxy_set_header Content-Length "";
            proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
            proxy_set_header X-Forwarded-Method $request_method;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $http_host;
            proxy_set_header X-Forwarded-Uri $request_uri;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          }
          
          location @authelia_redirect {
            return 302 https://${providerConfig.domain}/?rd=$request_uri;
          }
        '';
      } {
        provider_version = "1.0.0";
        authelia_port = providerConfig.port;
        client_id = request.payload.client_id;
        access_domain = access_domain;
        ldap_integration = true;
        database_type = database_type;
        ha_capable = database_type != "sqlite";
        uses_database_contract = database_type != "sqlite";
      };
    };
  
  validate = request: providerConfig:
    lib.optional (providerConfig.domain == null) "Authelia domain must be configured" ++
    lib.optional (providerConfig.ldap_url == null) "LDAP URL must be configured" ++
    lib.optional (providerConfig.ldap_base_dn == null) "LDAP base DN must be configured" ++
    lib.optional (providerConfig.ldap_user_base_dn == null) "LDAP user base DN must be configured" ++
    lib.optional (providerConfig.ldap_group_base_dn == null) "LDAP group base DN must be configured" ++
    lib.optional (providerConfig.ldap_bind_dn == null) "LDAP bind DN must be configured" ++
    lib.optional (providerConfig.ldap_bind_password_secret == null) "LDAP bind password secret must be configured" ++
    lib.optional (providerConfig.jwt_secret_path == null) "JWT secret path must be configured" ++
    lib.optional (providerConfig.session_secret_path == null) "Session secret path must be configured" ++
    lib.optional (providerConfig.storage_encryption_key_path == null) "Storage encryption key path must be configured" ++
    lib.optional (providerConfig.issuer_private_key_path == null) "OIDC issuer private key path must be configured" ++
    lib.optional (request.payload.client_id == null) "Client ID must be specified" ++
    lib.optional (builtins.length request.payload.redirect_uris == 0) "At least one redirect URI must be specified" ++
    lib.optional (!lib.elem request.payload.access_policy [ "bypass" "one_factor" "two_factor" ]) 
      "Access policy must be one of: bypass, one_factor, two_factor" ++
    lib.optional (providerConfig.port < 1 || providerConfig.port > 65535) "Port must be between 1 and 65535" ++
    lib.optional (!lib.elem providerConfig.database_preference [ "auto" "postgresql" "mysql" "sqlite" ])
      "Database preference must be one of: auto, postgresql, mysql, sqlite" ++
    lib.optional (!lib.elem providerConfig.log_level [ "trace" "debug" "info" "warn" "error" ])
      "Log level must be one of: trace, debug, info, warn, error" ++
    lib.optional (providerConfig.max_retries < 1) "Max retries must be greater than 0";
}