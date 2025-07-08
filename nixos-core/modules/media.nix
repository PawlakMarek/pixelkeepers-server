# Media Services Module - Plex, arr stack, and Recyclarr
{
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (lib) optionalAttrs mkIf;
  inherit (config.me) domain;
in {
  options = {
    services.media = {
      enable = lib.mkEnableOption "media services";

      plex = {
        enable = lib.mkEnableOption "Plex Media Server";
      };

      arr = {
        enable = lib.mkEnableOption "arr stack (Radarr, Sonarr, Jackett)";
      };

      recyclarr = {
        enable = lib.mkEnableOption "Recyclarr for TRaSH guides";
      };
    };
  };

  config = lib.mkMerge [
    # Plex Media Server - Using SHB service from fork
    (mkIf config.services.media.plex.enable {
      shb.plex = {
        enable = true;
        inherit domain;
        subdomain = "plex";
        ssl = config.shb.certs.certs.letsencrypt.${domain};
        dataDir = "/var/lib/plex";
        user = "plex";
        group = "plex";
        port = 32400;
      };
    })

    # Media management stack - Radarr, Sonarr, Jackett (arr stack)
    (mkIf config.services.media.arr.enable (optionalAttrs true {
      shb = {
        arr = {
          radarr = {
            enable = true;
            inherit domain;
            subdomain = "radarr";
            ssl = config.shb.certs.certs.letsencrypt.${domain};
            authEndpoint = "https://authelia.${domain}";
            settings = {
              ApiKey.source = config.shb.sops.secret."radarr/apikey".result.path;
              LogLevel = "info";
            };
          };
          sonarr = {
            enable = true;
            inherit domain;
            subdomain = "sonarr";
            ssl = config.shb.certs.certs.letsencrypt.${domain};
            authEndpoint = "https://authelia.${domain}";
            settings = {
              ApiKey.source = config.shb.sops.secret."sonarr/apikey".result.path;
              LogLevel = "info";
            };
          };
          jackett = {
            enable = true;
            inherit domain;
            subdomain = "jackett";
            ssl = config.shb.certs.certs.letsencrypt.${domain};
            authEndpoint = "https://authelia.${domain}";
            settings = {
              ApiKey.source = config.shb.sops.secret."jackett/apikey".result.path;
              LogLevel = "info";
            };
          };
        };

        # Setup secrets for media management services
        sops.secret = {
          "radarr/apikey".request = {
            mode = "0440";
            owner = "radarr";
            group = "arr_user";
            restartUnits = ["radarr.service"];
          };
          "sonarr/apikey".request = {
            mode = "0440";
            owner = "sonarr";
            group = "arr_user";
            restartUnits = ["sonarr.service"];
          };
          "jackett/apikey".request = {
            mode = "0440";
            owner = "jackett";
            group = "jackett";
            restartUnits = ["jackett.service"];
          };
        };

        # ZFS datasets for media management services
        zfs.datasets = {
          "safe/radarr".path = "/var/lib/radarr";
          "safe/sonarr".path = "/var/lib/sonarr";
          "safe/jackett".path = "/var/lib/jackett";
        };
      };

      # Override nginx configurations to use local authelia endpoint
      services.nginx.virtualHosts = {
        "radarr.${domain}".locations."/authelia" = lib.mkForce {
          proxyPass = "http://127.0.0.1:9091/api/verify";
          extraConfig = ''
            internal;
            proxy_pass_request_body off;
            proxy_set_header Content-Length "";
            proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
          '';
        };
        "sonarr.${domain}".locations."/authelia" = lib.mkForce {
          proxyPass = "http://127.0.0.1:9091/api/verify";
          extraConfig = ''
            internal;
            proxy_pass_request_body off;
            proxy_set_header Content-Length "";
            proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
          '';
        };
        "jackett.${domain}".locations."/authelia" = lib.mkForce {
          proxyPass = "http://127.0.0.1:9091/api/verify";
          extraConfig = ''
            internal;
            proxy_pass_request_body off;
            proxy_set_header Content-Length "";
            proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
          '';
        };
      };

      # Add media management users to arr_user group for shared access
      users = {
        users.radarr.extraGroups = ["arr_user"];
        users.sonarr.extraGroups = ["arr_user"];
        groups.arr_user = {};
      };
    }))

    # Recyclarr configuration for TRaSH guides
    (mkIf config.services.media.recyclarr.enable (optionalAttrs true {
      systemd = {
        services.recyclarr = {
          description = "Recyclarr - TRaSH Guides for Radarr and Sonarr";
          after = ["network.target" "radarr.service" "sonarr.service"];
          wants = ["radarr.service" "sonarr.service"];
          serviceConfig = {
            Type = "oneshot";
            User = "recyclarr";
            Group = "recyclarr";
            WorkingDirectory = "/var/lib/recyclarr";
            PrivateTmp = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ReadWritePaths = ["/var/lib/recyclarr"];
          };
          script = ''
            export RADARR_API_KEY="$(cat ${config.shb.sops.secret."radarr/apikey".result.path})"
            export SONARR_API_KEY="$(cat ${config.shb.sops.secret."sonarr/apikey".result.path})"
            exec ${pkgs.recyclarr}/bin/recyclarr sync --config /var/lib/recyclarr/recyclarr.yml
          '';
        };

        timers.recyclarr = {
          description = "Run Recyclarr every 6 hours";
          wantedBy = ["timers.target"];
          timerConfig = {
            OnBootSec = "15min";
            OnUnitActiveSec = "6h";
            RandomizedDelaySec = "30min";
            Persistent = true;
          };
        };

        # Recyclarr configuration file
        tmpfiles.rules = [
          "d /var/lib/recyclarr 0750 recyclarr recyclarr -"
          "d /var/lib/recyclarr/.config 0750 recyclarr recyclarr -"
          "C /var/lib/recyclarr/recyclarr.yml 0640 recyclarr recyclarr - ${../../recyclarr.yml}"
        ];
      };

      # Create recyclarr user
      users = {
        users.recyclarr = {
          isSystemUser = true;
          group = "recyclarr";
          extraGroups = ["arr_user"];
          home = "/var/lib/recyclarr";
          createHome = true;
        };
        groups.recyclarr = {};
      };

      # ZFS dataset for recyclarr
      shb.zfs.datasets."safe/recyclarr".path = "/var/lib/recyclarr";
    }))

    # Enable default media services
    {
      services.media = {
        enable = lib.mkDefault true;
        plex.enable = lib.mkDefault true;
        arr.enable = lib.mkDefault true;
        recyclarr.enable = lib.mkDefault true;
      };
    }
  ];
}
