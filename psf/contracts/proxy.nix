{ lib, pkgs, mkRequest, mkResult }:

{
  name = "proxy";
  version = "1.0.0";
  description = "Reverse proxy service contract";
  
  # Request schema - what services can ask for
  requestSchema = {
    domain = lib.mkOption {
      type = lib.types.str;
      description = "Domain to proxy";
    };
    
    upstream = lib.mkOption {
      type = lib.types.str;
      description = "Upstream server address (e.g., http://127.0.0.1:8080)";
    };
    
    ssl_config = lib.mkOption {
      type = lib.types.nullOr lib.types.attrs;
      default = null;
      description = "SSL configuration from SSL contract result";
    };
    
    auth_endpoint = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Authentication endpoint for auth_request";
    };
    
    additional_config = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Additional proxy-specific configuration";
    };
    
    websocket_support = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable WebSocket proxying support";
    };
    
    client_max_body_size = lib.mkOption {
      type = lib.types.str;
      default = "1M";
      description = "Maximum client request body size";
    };
  };
  
  # Result schema - what providers must deliver
  resultSchema = {
    domain = lib.mkOption {
      type = lib.types.str;
      description = "Configured domain";
    };
    
    upstream = lib.mkOption {
      type = lib.types.str;
      description = "Configured upstream";
    };
    
    ssl_enabled = lib.mkOption {
      type = lib.types.bool;
      description = "Whether SSL is enabled for this proxy";
    };
    
    config_reload_command = lib.mkOption {
      type = lib.types.str;
      description = "Command to reload proxy configuration";
    };
    
    health_check_url = lib.mkOption {
      type = lib.types.str;
      description = "URL to check proxy health";
    };
  };
  
  # Create proxy request
  mkRequest = { 
    domain, 
    upstream, 
    ssl_config ? null, 
    auth_endpoint ? null, 
    additional_config ? "",
    websocket_support ? false,
    client_max_body_size ? "1M"
  }:
    mkRequest "proxy" {
      inherit domain upstream ssl_config auth_endpoint additional_config websocket_support client_max_body_size;
    };
  
  # Validate proxy request
  validateRequest = request:
    assert request.payload.domain != null;
    assert request.payload.upstream != null;
    true;
    
  # Validate proxy result
  validateResult = result:
    assert result.payload.domain != null;
    assert result.payload.upstream != null;
    assert result.payload.config_reload_command != null;
    true;
}