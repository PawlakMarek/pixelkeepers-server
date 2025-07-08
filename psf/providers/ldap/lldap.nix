{ lib, pkgs, registerProvider }:

let
  # Import mkResult from contracts
  mkResult = (import ../../lib/contracts.nix { inherit lib pkgs; }).mkResult;
in

registerProvider {
  name = "lldap";
  contract_type = "ldap";
  version = "1.0.0";
  description = "Light LDAP implementation for authentication";
  
  capabilities = {
    web_interface = true;
    user_management = true;
    group_management = true;
    password_reset = true;
    schema_flexibility = "limited";
    max_users = 10000;
    protocols = [ "ldap" ];
    tls_support = false; # LLDAP doesn't support TLS natively
  };
  
  configSchema = {
    # Core LDAP configuration
    port = lib.mkOption {
      type = lib.types.port;
      default = 3890;
      description = "LDAP port";
    };
    
    base_dn = lib.mkOption {
      type = lib.types.str;
      description = "Base DN for LDAP directory";
      example = "dc=example,dc=com";
    };
    
    admin_password_secret = lib.mkOption {
      type = lib.types.str;
      description = "Path to admin password secret";
    };
    
    user_dn = lib.mkOption {
      type = lib.types.str;
      default = "ou=people";
      description = "User DN component (relative to base_dn)";
    };
    
    group_dn = lib.mkOption {
      type = lib.types.str;
      default = "ou=groups";
      description = "Group DN component (relative to base_dn)";
    };
    
    # Web interface configuration
    web_interface = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable web interface";
    };
    
    web_port = lib.mkOption {
      type = lib.types.port;
      default = 17170;
      description = "Web interface port";
    };
    
    jwt_secret_path = lib.mkOption {
      type = lib.types.str;
      description = "Path to JWT secret for web interface";
    };
    
    # SSL and proxy configuration
    ssl_enabled = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable SSL termination via reverse proxy";
    };
    
    domain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Domain for SSL certificate (required if ssl_enabled = true)";
    };
    
    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "ldap";
      description = "Subdomain for web interface";
    };
    
    # Authentication configuration
    auth_required = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Require SSO authentication for web interface";
    };
    
    allowed_groups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "lldap_admin" ];
      description = "Groups allowed to access web interface";
    };
    
    # Backup configuration
    backup_enabled = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable backup of LLDAP data";
    };
    
    backup_retention_days = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Number of days to retain backups";
    };
    
    # Monitoring
    monitoring_enabled = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable monitoring and metrics";
    };
  };
  
  canFulfill = request: 
    request.contract_type == "ldap";
  
  fulfill = request: providerConfig:
    let
      # Extract domain parts from the request to build base DN if not provided
      domain_parts = lib.splitString "." request.payload.domain;
      computed_base_dn = lib.concatStringsSep "," (map (part: "dc=${part}") domain_parts);
      base_dn = if providerConfig.base_dn != null then providerConfig.base_dn else computed_base_dn;
      
      # Construct full DNs
      user_base_dn = "${providerConfig.user_dn},${base_dn}";
      group_base_dn = "${providerConfig.group_dn},${base_dn}";
      bind_dn = "cn=${request.payload.bind_user},${base_dn}";
      
      # Determine full domain for SSL
      full_domain = if providerConfig.domain != null 
        then "${providerConfig.subdomain}.${providerConfig.domain}"
        else null;
      
      # Additional contracts this provider needs
      additional_contracts = 
        # SSL contract (if enabled)
        lib.optionalAttrs (providerConfig.ssl_enabled && full_domain != null) {
          ssl = (import ../../contracts/ssl.nix { inherit lib pkgs; mkRequest = (import ../../lib/contracts.nix { inherit lib pkgs; }).mkRequest; mkResult = mkResult; }).mkRequest {
            domain = full_domain;
            auto_renew = true;
          };
        } //
        # Backup contract (if enabled)
        lib.optionalAttrs providerConfig.backup_enabled {
          backup = (import ../../contracts/backup.nix { inherit lib pkgs; mkRequest = (import ../../lib/contracts.nix { inherit lib pkgs; }).mkRequest; mkResult = mkResult; }).mkRequest {
            paths = [ "/var/lib/lldap" ];
            schedule = "daily";
            retention = {
              daily = providerConfig.backup_retention_days;
              weekly = 4;
              monthly = 3;
            };
          };
        } //
        # SSO contract (if auth required)
        lib.optionalAttrs (providerConfig.auth_required && full_domain != null) {
          sso = (import ../../contracts/sso.nix { inherit lib pkgs; mkRequest = (import ../../lib/contracts.nix { inherit lib pkgs; }).mkRequest; mkResult = mkResult; }).mkRequest {
            client_id = "lldap-admin";
            redirect_uris = [ "https://${full_domain}/auth/callback" ];
            scopes = [ "openid" "profile" "email" ];
            access_policy = "two_factor";
            allowed_groups = providerConfig.allowed_groups;
          };
        } //
        # Proxy contract (if SSL enabled)
        lib.optionalAttrs (providerConfig.ssl_enabled && full_domain != null) {
          proxy = (import ../../contracts/proxy.nix { inherit lib pkgs; mkRequest = (import ../../lib/contracts.nix { inherit lib pkgs; }).mkRequest; mkResult = mkResult; }).mkRequest {
            domain = full_domain;
            upstream = "http://127.0.0.1:${toString providerConfig.web_port}";
            auth_endpoint = if providerConfig.auth_required then "https://auth.${providerConfig.domain}" else null;
            additional_config = ''
              # LLDAP-specific proxy settings
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header X-Forwarded-Host $host;
              proxy_read_timeout 300s;
              proxy_send_timeout 300s;
            '';
          };
        };
      
    in {
      # Return additional contracts this provider needs
      needs = additional_contracts;
      
      config = {
        # Core LLDAP service configuration
        services.lldap = {
          enable = true;
          settings = {
            ldap_port = providerConfig.port;
            http_port = lib.mkIf providerConfig.web_interface providerConfig.web_port;
            ldap_base_dn = base_dn;
            ldap_user_dn = user_base_dn;
            ldap_user_email_attribute = "mail";
            ldap_user_display_name_attribute = "displayName";
          };
          environmentFile = pkgs.writeText "lldap-env" ''
            LLDAP_LDAP_USER_PASS_FILE=${providerConfig.admin_password_secret}
            LLDAP_JWT_SECRET_FILE=${providerConfig.jwt_secret_path}
          '';
        };
        
        # Bootstrap users and groups
        systemd.services.lldap-bootstrap = {
          description = "Bootstrap LLDAP with default groups and users";
          after = [ "lldap.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "lldap";
          };
          script = let
            bootstrapScript = pkgs.writeShellScript "lldap-bootstrap" ''
              set -e
              
              # Wait for LLDAP to be ready
              echo "Waiting for LLDAP to start..."
              HEALTH_URL="http://127.0.0.1:${toString providerConfig.web_port}/health"
              while ! ${pkgs.curl}/bin/curl -f "$HEALTH_URL" >/dev/null 2>&1; do
                sleep 2
              done
              
              echo "LLDAP is ready, setting up default groups and users..."
              
              # Create default groups
              ${lib.concatMapStringsSep "\n" (group: ''
                echo "Creating group: ${group}"
                # TODO: Add actual LLDAP API calls to create groups
              '') request.payload.groups}
              
              # Create default users  
              ${lib.concatMapStringsSep "\n" (user: ''
                echo "Creating user: ${user.username} (${user.email})"
                # TODO: Add actual LLDAP API calls to create users
              '') request.payload.users}
              
              echo "LLDAP bootstrap completed"
            '';
          in "${bootstrapScript}";
        };
        
        # Monitoring (if enabled)
        services.prometheus.exporters.lldap = lib.mkIf providerConfig.monitoring_enabled {
          enable = true;
          port = 9389;
          listenAddress = "127.0.0.1";
        };
        
        # Firewall
        networking.firewall.allowedTCPPorts = [ providerConfig.port ] ++ 
          lib.optional providerConfig.web_interface providerConfig.web_port;
        
        # Log rotation
        services.logrotate.settings."/var/lib/lldap/lldap.log" = {
          frequency = "daily";
          rotate = 7;
          compress = true;
          delaycompress = true;
          missingok = true;
          notifempty = true;
          create = "640 lldap lldap";
          postrotate = "systemctl reload lldap.service";
        };
        
        # Users and groups
        users.users.lldap = {
          group = "lldap";
          isSystemUser = true;
          home = "/var/lib/lldap";
          createHome = true;
        };
        users.groups.lldap = {};
      };
      
      result = mkResult "ldap" {
        ldap_url = "ldap://127.0.0.1:${toString providerConfig.port}";
        bind_dn = bind_dn;
        base_dn = base_dn;
        user_base_dn = user_base_dn;
        group_base_dn = group_base_dn;
        admin_interface_url = if providerConfig.web_interface then 
          (if providerConfig.ssl_enabled && full_domain != null then "https://${full_domain}" else "http://127.0.0.1:${toString providerConfig.web_port}")
          else null;
        bind_password_secret = providerConfig.admin_password_secret;
      } {
        provider_version = "1.0.0";
        web_interface_enabled = providerConfig.web_interface;
        web_interface_port = providerConfig.web_port;
        ldap_port = providerConfig.port;
        ssl_enabled = providerConfig.ssl_enabled;
        auth_required = providerConfig.auth_required;
        backup_enabled = providerConfig.backup_enabled;
        monitoring_enabled = providerConfig.monitoring_enabled;
        computed_base_dn = computed_base_dn;
        users_to_create = builtins.length request.payload.users;
        groups_to_create = builtins.length request.payload.groups;
        full_domain = full_domain;
      };
    };
  
  validate = request: providerConfig:
    lib.optional (providerConfig.admin_password_secret == null) "Admin password secret path must be configured" ++
    lib.optional (providerConfig.jwt_secret_path == null) "JWT secret path must be configured" ++
    lib.optional (request.payload.domain == null) "Domain must be specified for LDAP base DN construction" ++
    lib.optional (request.payload.bind_user == null) "Bind user must be specified" ++
    lib.optional (providerConfig.port < 1 || providerConfig.port > 65535) "LDAP port must be between 1 and 65535" ++
    lib.optional (providerConfig.web_interface && (providerConfig.web_port < 1 || providerConfig.web_port > 65535)) "Web port must be between 1 and 65535" ++
    lib.optional (providerConfig.web_interface && providerConfig.port == providerConfig.web_port) "LDAP port and web port cannot be the same" ++
    lib.optional (providerConfig.ssl_enabled && providerConfig.domain == null) "Domain must be configured when SSL is enabled" ++
    lib.optional (providerConfig.ssl_enabled && !providerConfig.web_interface) "Web interface must be enabled when SSL is enabled" ++
    lib.optional (providerConfig.auth_required && !providerConfig.ssl_enabled) "SSL must be enabled when authentication is required" ++
    lib.optional (providerConfig.backup_retention_days < 1) "Backup retention days must be greater than 0" ++
    lib.optional (providerConfig.allowed_groups == [] && providerConfig.auth_required) "At least one allowed group must be specified when authentication is required";
}