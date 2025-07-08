{ lib, pkgs, registerProvider }:

let
  # Import mkResult from contracts
  mkResult = (import ../../lib/contracts.nix { inherit lib pkgs; }).mkResult;
in

registerProvider {
  name = "nginx";
  contract_type = "proxy";
  version = "1.0.0";
  description = "Nginx reverse proxy with SSL and authentication support";
  
  capabilities = {
    ssl_termination = true;
    http2_support = true;
    load_balancing = true;
    auth_request_support = true;
    websocket_support = true;
    static_files = true;
    compression = true;
    rate_limiting = true;
    config_reload = "graceful";
    max_body_size_configurable = true;
  };
  
  configSchema = {
    enable_http2 = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable HTTP/2 support";
    };
    
    client_max_body_size = lib.mkOption {
      type = lib.types.str;
      default = "100M";
      description = "Maximum client body size";
    };
    
    proxy_read_timeout = lib.mkOption {
      type = lib.types.str;
      default = "60s";
      description = "Proxy read timeout";
    };
    
    proxy_connect_timeout = lib.mkOption {
      type = lib.types.str;
      default = "60s";
      description = "Proxy connect timeout";
    };
    
    proxy_send_timeout = lib.mkOption {
      type = lib.types.str;
      default = "60s";
      description = "Proxy send timeout";
    };
    
    enable_compression = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable gzip compression";
    };
    
    compression_level = lib.mkOption {
      type = lib.types.int;
      default = 6;
      description = "Gzip compression level (1-9)";
    };
    
    enable_rate_limiting = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable rate limiting";
    };
    
    rate_limit = lib.mkOption {
      type = lib.types.str;
      default = "10r/s";
      description = "Rate limit (e.g., 10r/s, 100r/m)";
    };
    
    enable_access_log = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable access logging";
    };
    
    enable_error_log = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable error logging";
    };
    
    custom_headers = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Custom headers to add to all responses";
      example = {
        "X-Frame-Options" = "DENY";
        "X-Content-Type-Options" = "nosniff";
      };
    };
  };
  
  canFulfill = request: 
    request.contract_type == "proxy";
  
  fulfill = request: providerConfig:
    let
      domain = request.payload.domain;
      upstream = request.payload.upstream;
      ssl_config = request.payload.ssl_config or null;
      auth_endpoint = request.payload.auth_endpoint or null;
      additional_config = request.payload.additional_config or "";
      
      # SSL configuration
      ssl_enabled = ssl_config != null;
      
      # Rate limiting configuration
      rate_limit_config = lib.optionalString providerConfig.enable_rate_limiting ''
        limit_req_zone $binary_remote_addr zone=api:10m rate=${providerConfig.rate_limit};
      '';
      
      # Custom headers configuration
      custom_headers_config = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (name: value: "add_header ${name} \"${value}\" always;") providerConfig.custom_headers
      );
      
      # Security headers (always added)
      security_headers = ''
        # Security headers
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        
        # Custom headers
        ${custom_headers_config}
      '';
      
      # Authentication configuration
      auth_config = lib.optionalString (auth_endpoint != null) ''
        # Authentication via auth_request
        auth_request /auth;
        auth_request_set $user $upstream_http_remote_user;
        auth_request_set $groups $upstream_http_remote_groups;
        auth_request_set $name $upstream_http_remote_name;
        auth_request_set $email $upstream_http_remote_email;
        error_page 401 = @auth_redirect;
        
        # Forward auth headers
        proxy_set_header Remote-User $user;
        proxy_set_header Remote-Groups $groups;
        proxy_set_header Remote-Name $name;
        proxy_set_header Remote-Email $email;
      '';
      
      # Auth endpoints (if authentication is enabled)
      auth_locations = lib.optionalString (auth_endpoint != null) ''
        location /auth {
          internal;
          proxy_pass ${auth_endpoint}/api/verify;
          proxy_pass_request_body off;
          proxy_set_header Content-Length "";
          proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
          proxy_set_header X-Forwarded-Method $request_method;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Host $http_host;
          proxy_set_header X-Forwarded-Uri $request_uri;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
        
        location @auth_redirect {
          return 302 ${auth_endpoint}/?rd=$request_uri;
        }
      '';
      
      # Main proxy configuration
      proxy_config = ''
        # Proxy settings
        proxy_pass ${upstream};
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
        
        # Timeouts
        proxy_connect_timeout ${providerConfig.proxy_connect_timeout};
        proxy_send_timeout ${providerConfig.proxy_send_timeout};
        proxy_read_timeout ${providerConfig.proxy_read_timeout};
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        
        # Body size
        client_max_body_size ${providerConfig.client_max_body_size};
        
        ${auth_config}
        ${additional_config}
      '';
      
      # Virtual host configuration
      virtualHostConfig = {
        forceSSL = ssl_enabled;
        enableACME = ssl_enabled;
        
        # SSL configuration (if available)
      } // lib.optionalAttrs ssl_enabled {
        sslCertificate = ssl_config.cert_path;
        sslCertificateKey = ssl_config.key_path;
      } // {
        locations = {
          "/" = {
            extraConfig = proxy_config;
          };
        } // lib.optionalAttrs (auth_endpoint != null) {
          "/auth" = {
            extraConfig = ''internal; return 404;'';
          };
        };
        
        extraConfig = ''
          ${security_headers}
          
          # Compression
          ${lib.optionalString providerConfig.enable_compression ''
            gzip on;
            gzip_vary on;
            gzip_min_length 1024;
            gzip_comp_level ${toString providerConfig.compression_level};
            gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
          ''}
          
          # Rate limiting
          ${lib.optionalString providerConfig.enable_rate_limiting ''
            limit_req zone=api burst=20 nodelay;
          ''}
          
          # WebSocket upgrade mapping
          map $http_upgrade $connection_upgrade {
            default upgrade;
            '' close;
          }
          
          ${auth_locations}
        '';
      };
      
    in {
      config = {
        services.nginx = {
          enable = true;
          
          # Global nginx configuration
          appendHttpConfig = ''
            # Rate limiting zones
            ${rate_limit_config}
            
            # WebSocket upgrade mapping (global)
            map $http_upgrade $connection_upgrade {
              default upgrade;
              '' close;
            }
            
            # Logging format
            log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                           '$status $body_bytes_sent "$http_referer" '
                           '"$http_user_agent" "$http_x_forwarded_for"';
          '';
          
          # Virtual host configuration
          virtualHosts.${domain} = virtualHostConfig;
          
          # Common configuration
          commonHttpConfig = ''
            # Basic settings
            sendfile on;
            tcp_nopush on;
            tcp_nodelay on;
            keepalive_timeout 65;
            types_hash_max_size 2048;
            
            # Hide nginx version
            server_tokens off;
            
            # Client settings
            client_max_body_size ${providerConfig.client_max_body_size};
            
            # Logging
            ${lib.optionalString providerConfig.enable_access_log ''
              access_log /var/log/nginx/access.log main;
            ''}
            ${lib.optionalString providerConfig.enable_error_log ''
              error_log /var/log/nginx/error.log warn;
            ''}
          '';
        };
        
        # Open firewall for HTTP(S)
        networking.firewall.allowedTCPPorts = [ 80 ] ++ lib.optional ssl_enabled 443;
        
        # Log rotation
        services.logrotate.settings."/var/log/nginx/*.log" = {
          frequency = "daily";
          rotate = 30;
          compress = true;
          delaycompress = true;
          missingok = true;
          notifempty = true;
          create = "640 nginx nginx";
          postrotate = ''systemctl reload nginx.service'';
        };
      };
      
      result = mkResult "proxy" {
        domain = domain;
        upstream = upstream;
        ssl_enabled = ssl_enabled;
        auth_enabled = auth_endpoint != null;
        proxy_url = if ssl_enabled then "https://${domain}" else "http://${domain}";
        config_reload_command = "systemctl reload nginx";
        status_endpoint = "http://127.0.0.1/nginx_status";
        log_path = "/var/log/nginx";
      } {
        provider_version = "1.0.0";
        nginx_version = pkgs.nginx.version;
        http2_enabled = providerConfig.enable_http2;
        compression_enabled = providerConfig.enable_compression;
        rate_limiting_enabled = providerConfig.enable_rate_limiting;
        websocket_support = true;
        auth_method = if auth_endpoint != null then "auth_request" else "none";
        ssl_source = if ssl_enabled then "external" else "none";
      };
    };
  
  validate = request: providerConfig:
    lib.optional (request.payload.domain == null) "Domain must be specified" ++
    lib.optional (request.payload.upstream == null) "Upstream must be specified" ++
    lib.optional (!lib.hasPrefix "http://" request.payload.upstream && !lib.hasPrefix "https://" request.payload.upstream)
      "Upstream must be a valid HTTP/HTTPS URL" ++
    lib.optional (providerConfig.compression_level < 1 || providerConfig.compression_level > 9)
      "Compression level must be between 1 and 9" ++
    lib.optional (!lib.hasInfix "/" providerConfig.rate_limit && providerConfig.enable_rate_limiting)
      "Rate limit must be in format like '10r/s' or '100r/m'" ++
    lib.optional (builtins.match ".*[0-9]+[KMG]?B?" providerConfig.client_max_body_size == null)
      "Client max body size must be in format like '100M', '1G', etc." ++
    lib.optional (builtins.match ".*[0-9]+[sm]" providerConfig.proxy_read_timeout == null)
      "Proxy read timeout must be in format like '60s', '5m', etc.";
}