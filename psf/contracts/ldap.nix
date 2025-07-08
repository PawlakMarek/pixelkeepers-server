{ lib, pkgs, mkRequest, mkResult }:

{
  name = "ldap";
  version = "1.0.0";
  description = "LDAP directory service contract";
  
  # Request schema - what services can ask for
  requestSchema = {
    domain = lib.mkOption {
      type = lib.types.str;
      description = "LDAP domain (e.g., dc=example,dc=com)";
    };
    
    users = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          username = lib.mkOption { type = lib.types.str; };
          email = lib.mkOption { type = lib.types.str; };
          groups = lib.mkOption { 
            type = lib.types.listOf lib.types.str; 
            default = [];
          };
        };
      });
      default = [];
      description = "Users to create in LDAP directory";
    };
    
    groups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Groups to create in LDAP directory";
    };
    
    bind_user = lib.mkOption {
      type = lib.types.str;
      default = "admin";
      description = "Bind user for LDAP operations";
    };
  };
  
  # Result schema - what providers must deliver
  resultSchema = {
    ldap_url = lib.mkOption {
      type = lib.types.str;
      description = "LDAP connection URL (e.g., ldap://127.0.0.1:389)";
    };
    
    bind_dn = lib.mkOption {
      type = lib.types.str;
      description = "Bind DN for authentication (e.g., cn=admin,dc=example,dc=com)";
    };
    
    base_dn = lib.mkOption {
      type = lib.types.str;
      description = "Base DN for directory (e.g., dc=example,dc=com)";
    };
    
    user_base_dn = lib.mkOption {
      type = lib.types.str;
      description = "Base DN for users (e.g., ou=people,dc=example,dc=com)";
    };
    
    group_base_dn = lib.mkOption {
      type = lib.types.str;
      description = "Base DN for groups (e.g., ou=groups,dc=example,dc=com)";
    };
    
    admin_interface_url = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Web interface URL for LDAP management";
    };
    
    bind_password_secret = lib.mkOption {
      type = lib.types.str;
      description = "Path to bind password secret file";
    };
  };
  
  # Create LDAP request
  mkRequest = { domain, users ? [], groups ? [], bind_user ? "admin" }:
    mkRequest "ldap" {
      inherit domain users groups bind_user;
    };
  
  # Validate LDAP request
  validateRequest = request:
    assert request.payload.domain != null;
    assert request.payload.bind_user != null;
    true;
    
  # Validate LDAP result
  validateResult = result:
    assert result.payload.ldap_url != null;
    assert result.payload.bind_dn != null;
    assert result.payload.base_dn != null;
    true;
}