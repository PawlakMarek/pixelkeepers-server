{ lib, pkgs }:

let
  inherit (lib) mkMerge mapAttrs' nameValuePair;
  
  # Build final service configuration from service definition and contract resolutions
  buildService = serviceDef: contractResolutions:
    let
      # Extract NixOS configuration from all contract results
      contractConfigs = mapAttrs' (name: resolution:
        nameValuePair "${serviceDef.name}-${name}" resolution.config
      ) contractResolutions;
      
      # Merge service config with contract configs
      finalConfig = mkMerge [
        serviceDef.config
        (mkMerge (lib.attrValues contractConfigs))
      ];
      
    in finalConfig;
    
  # Build health check configuration
  buildHealthChecks = serviceDef: contractResolutions:
    let
      # Standard health checks from service definition
      serviceHealthChecks = serviceDef.health_checks or [];
      
      # Additional health checks from contract results
      contractHealthChecks = []; # TODO: Extract from contract results
      
    in {
      systemd.services."psf-healthcheck-${serviceDef.name}" = {
        description = "Health checks for ${serviceDef.name}";
        serviceConfig = {
          Type = "oneshot";
          User = "psf-healthcheck";
        };
        script = generateHealthCheckScript (serviceHealthChecks ++ contractHealthChecks);
      };
      
      systemd.timers."psf-healthcheck-${serviceDef.name}" = {
        description = "Timer for ${serviceDef.name} health checks";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "1m";
          OnUnitActiveSec = "5m";
          Persistent = true;
        };
      };
    };
    
  # Generate health check script
  generateHealthCheckScript = healthChecks:
    let
      checkCommands = map (check:
        if check.type == "http" then
          ''
            echo "Checking ${check.name}..."
            if ! ${pkgs.curl}/bin/curl -f -s --max-time ${toString check.timeout_seconds} "${check.url}" >/dev/null; then
              echo "ERROR: ${check.name} health check failed"
              exit 1
            fi
            echo "OK: ${check.name} is healthy"
          ''
        else ""
      ) healthChecks;
    in ''
      #!/bin/bash
      set -e
      ${lib.concatStringsSep "\n" checkCommands}
      echo "All health checks passed"
    '';

in {
  inherit buildService buildHealthChecks generateHealthCheckScript;
}