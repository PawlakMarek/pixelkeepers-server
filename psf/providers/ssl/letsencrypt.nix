{ lib, pkgs, registerProvider }:

registerProvider {
  name = "letsencrypt";
  contract_type = "ssl";
  version = "1.0.0";
  description = "Let's Encrypt ACME SSL certificate provider";
  
  capabilities = {
    domains = [ "*" ]; # Supports all domains
    protocols = [ "http-01" "dns-01" ];
    wildcard_support = true;
    auto_renewal = true;
  };
  
  configSchema = {
    email = lib.mkOption {
      type = lib.types.str;
      description = "Email address for ACME registration";
    };
    
    dns_provider = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "DNS provider for DNS-01 challenge";
    };
    
    staging = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Use Let's Encrypt staging environment";
    };
  };
  
  # Check if this provider can fulfill the request
  canFulfill = request: 
    request.contract_type == "ssl" && 
    request.payload.domain != null;
  
  # Fulfill the SSL certificate request
  fulfill = request: providerConfig:
    let
      domain = request.payload.domain;
      certName = builtins.replaceStrings ["."] ["_"] domain;
    in {
      config = {
        security.acme = {
          acceptTerms = true;
          defaults.email = providerConfig.email;
          defaults.server = if providerConfig.staging 
            then "https://acme-staging-v02.api.letsencrypt.org/directory"
            else "https://acme-v02.api.letsencrypt.org/directory";
          
          certs.${certName} = {
            domain = domain;
            extraDomainNames = request.payload.san_domains;
            dnsProvider = providerConfig.dns_provider;
            credentialsFile = "/run/secrets/acme-credentials";
          };
        };
        
        systemd.services.nginx.serviceConfig.SupplementaryGroups = [ "acme" ];
      };
      
      result = {
        contract_type = "ssl";
        payload = {
          cert_path = "/var/lib/acme/${certName}/cert.pem";
          key_path = "/var/lib/acme/${certName}/key.pem";
          ca_path = "/var/lib/acme/${certName}/chain.pem";
          reload_services = [ "nginx.service" ];
        };
        metadata = {
          provider_version = "1.0.0";
          cert_name = certName;
          renewal_timer = "acme-${certName}.timer";
        };
      };
    };
  
  # Validate provider configuration and request
  validate = request: providerConfig: 
    lib.optional (providerConfig.email == null) "ACME email must be configured" ++
    lib.optional (request.payload.domain == null) "Domain must be specified" ++
    lib.optional (providerConfig.dns_provider == null && lib.any (d: lib.hasPrefix "*." d) (request.payload.domain :: request.payload.san_domains)) 
      "DNS provider required for wildcard certificates";
}