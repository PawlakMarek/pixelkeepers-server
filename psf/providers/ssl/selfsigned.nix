{ lib, pkgs, registerProvider }:

registerProvider {
  name = "selfsigned";
  contract_type = "ssl";
  version = "1.0.0";
  description = "Self-signed SSL certificate provider";
  
  capabilities = {
    domains = [ "*" ]; # Supports all domains
    protocols = [ "self-signed" ];
    wildcard_support = true;
    auto_renewal = false;
  };
  
  configSchema = {
    ca_cert = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to CA certificate for signing";
    };
    
    key_size = lib.mkOption {
      type = lib.types.int;
      default = 2048;
      description = "RSA key size in bits";
    };
    
    validity_days = lib.mkOption {
      type = lib.types.int;
      default = 365;
      description = "Certificate validity in days";
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
      certDir = "/var/lib/selfsigned-certs/${certName}";
    in {
      config = {
        # Ensure OpenSSL is available system-wide
        environment.systemPackages = [ pkgs.openssl ];
        
        # Create self-signed certificate using systemd service
        systemd.services."selfsigned-cert-${certName}" = {
          description = "Generate self-signed certificate for ${domain}";
          wantedBy = [ "multi-user.target" ];
          before = [ "nginx.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            mkdir -p ${certDir}
            
            # Generate private key if it doesn't exist
            if [ ! -f ${certDir}/key.pem ]; then
              ${pkgs.openssl}/bin/openssl genrsa -out ${certDir}/key.pem ${toString providerConfig.key_size}
              chmod 600 ${certDir}/key.pem
            fi
            
            # Generate certificate if it doesn't exist
            if [ ! -f ${certDir}/cert.pem ]; then
              ${pkgs.openssl}/bin/openssl req -new -x509 \
                -key ${certDir}/key.pem \
                -out ${certDir}/cert.pem \
                -days ${toString providerConfig.validity_days} \
                -subj "/CN=${domain}" \
                -extensions v3_req \
                -config <(cat <<EOF
            [req]
            distinguished_name = req_distinguished_name
            req_extensions = v3_req
            
            [req_distinguished_name]
            
            [v3_req]
            subjectAltName = @alt_names
            
            [alt_names]
            DNS.1 = ${domain}
            ${lib.concatImapStringsSep "\n" (i: san: "DNS.${toString (i + 1)} = ${san}") request.payload.san_domains}
            EOF
            )
              chmod 644 ${certDir}/cert.pem
            fi
            
            # Create symlink for CA certificate (self-signed so same as cert)
            ln -sf ${certDir}/cert.pem ${certDir}/chain.pem
          '';
        };
        
        # Ensure certificate directory exists
        systemd.tmpfiles.rules = [
          "d ${certDir} 0755 root root -"
        ];
      };
      
      result = {
        contract_type = "ssl";
        payload = {
          cert_path = "${certDir}/cert.pem";
          key_path = "${certDir}/key.pem";
          ca_path = "${certDir}/chain.pem";
          reload_services = [ "nginx.service" ];
        };
        metadata = {
          provider_version = "1.0.0";
          cert_name = certName;
          self_signed = true;
        };
      };
    };
  
  # Validate provider configuration and request
  validate = request: providerConfig: 
    lib.optional (request.payload.domain == null) "Domain must be specified" ++
    lib.optional (providerConfig.key_size < 1024) "Key size must be at least 1024 bits" ++
    lib.optional (providerConfig.validity_days < 1) "Validity days must be positive";
}