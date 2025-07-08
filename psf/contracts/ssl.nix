{ lib, pkgs, mkRequest, mkResult }:

{
  name = "ssl";
  version = "1.0.0";
  description = "SSL certificate management contract";
  
  # Request schema - what services can ask for
  requestSchema = {
    domain = lib.mkOption {
      type = lib.types.str;
      description = "Primary domain for the certificate";
    };
    
    san_domains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Subject Alternative Names for the certificate";
    };
    
    auto_renew = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Automatically renew certificate before expiry";
    };
  };
  
  # Result schema - what providers must deliver
  resultSchema = {
    cert_path = lib.mkOption {
      type = lib.types.path;
      description = "Path to the certificate file";
    };
    
    key_path = lib.mkOption {
      type = lib.types.path;
      description = "Path to the private key file";
    };
    
    ca_path = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to the CA certificate file";
    };
    
    reload_services = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Services to reload when certificate is renewed";
    };
  };
  
  # Create SSL request
  mkRequest = { domain, san_domains ? [], auto_renew ? true }:
    mkRequest "ssl" {
      inherit domain san_domains auto_renew;
    };
  
  # Validate SSL request
  validateRequest = request:
    assert request.payload.domain != null;
    assert lib.all (d: lib.isString d) request.payload.san_domains;
    true;
    
  # Validate SSL result
  validateResult = result:
    assert builtins.pathExists result.payload.cert_path;
    assert builtins.pathExists result.payload.key_path;
    true;
}