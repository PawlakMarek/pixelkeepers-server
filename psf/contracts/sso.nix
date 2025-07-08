{ lib, pkgs, mkRequest, mkResult }:

{
  name = "sso";
  version = "1.0.0";
  description = "Single Sign-On authentication contract";
  
  # Request schema - what services can ask for
  requestSchema = {
    client_id = lib.mkOption {
      type = lib.types.str;
      description = "OAuth2/OIDC client identifier";
    };
    
    redirect_uris = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "Allowed redirect URIs for OAuth2 flow";
    };
    
    scopes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "openid" "profile" "email" ];
      description = "Required OAuth2/OIDC scopes";
    };
    
    access_policy = lib.mkOption {
      type = lib.types.enum [ "bypass" "one_factor" "two_factor" ];
      default = "two_factor";
      description = "Required authentication level";
    };
    
    allowed_groups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "LDAP groups allowed to access this service";
    };
    
    allowed_users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Specific users allowed to access this service";
    };
  };
  
  # Result schema - what providers must deliver
  resultSchema = {
    issuer_url = lib.mkOption {
      type = lib.types.str;
      description = "OIDC issuer URL";
    };
    
    authorization_endpoint = lib.mkOption {
      type = lib.types.str;
      description = "OAuth2 authorization endpoint";
    };
    
    token_endpoint = lib.mkOption {
      type = lib.types.str;
      description = "OAuth2 token endpoint";
    };
    
    userinfo_endpoint = lib.mkOption {
      type = lib.types.str;
      description = "OIDC userinfo endpoint";
    };
    
    client_secret_path = lib.mkOption {
      type = lib.types.str;
      description = "Path to client secret file";
    };
    
    auth_request_headers = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "HTTP headers for authentication requests";
    };
    
    nginx_auth_config = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Nginx configuration for auth_request integration";
    };
  };
  
  # Create SSO request
  mkRequest = { 
    client_id, 
    redirect_uris, 
    scopes ? [ "openid" "profile" "email" ],
    access_policy ? "two_factor",
    allowed_groups ? [],
    allowed_users ? []
  }:
    mkRequest "sso" {
      inherit client_id redirect_uris scopes access_policy allowed_groups allowed_users;
    };
  
  # Validate SSO request
  validateRequest = request:
    assert request.payload.client_id != null;
    assert builtins.length request.payload.redirect_uris > 0;
    assert builtins.elem request.payload.access_policy [ "bypass" "one_factor" "two_factor" ];
    true;
    
  # Validate SSO result
  validateResult = result:
    assert result.payload.issuer_url != null;
    assert result.payload.authorization_endpoint != null;
    assert result.payload.token_endpoint != null;
    true;
}