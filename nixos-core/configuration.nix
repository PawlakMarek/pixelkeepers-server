# This is a NixOS Module based on ibizaman's patterns.
{
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (lib) optionalAttrs;
  inherit (config.me) domain;
in {
  imports = [
    ../custom-zfs-data.nix
    ./modules/media.nix
  ];

  options = {
    me.domain = lib.mkOption {
      type = lib.types.str;
    };
  };

  config = lib.mkMerge [
    {
      shb.zfs.defaultPoolName = "root";
      # Use template for flake checks, real secrets for deployment
      sops.defaultSopsFile = if builtins.pathExists ./secrets.yaml 
        then ./secrets.yaml 
        else ./secrets.template.yaml;

      # Enable systemd debug logging for service unit validation
      systemd.extraConfig = ''
        LogLevel=debug
        DefaultTimeoutStopSec=30s
      '';

      # Allow unfree packages (needed for Plex)
      nixpkgs.config.allowUnfreePredicate = pkg:
        builtins.elem (lib.getName pkg) [
          "plexmediaserver"
        ];

      # Add useful debugging tools
      environment.systemPackages = with pkgs; [
        jq
        curl
        recyclarr
        # Add systemd debugging tools
        systemd
        util-linux
        # Add Python for thorough debugging
        python3
      ];

      # Debug: Print service names at build time
      warnings = [
        "DEBUG: Plex backup repository path: /srv/backup/plex"
        "DEBUG: Expected service name: restic-backups-plex"
      ];
    }
    {
      services.nginx.enable = true;
      shb.nginx.accessLog = true;
      networking.firewall.allowedTCPPorts = [80 443];
    }

    (optionalAttrs true {
      shb.certs.certs.letsencrypt.${domain} = {
        domain = "*.${domain}";
        group = "nginx";
        reloadServices = ["nginx.service"];
        adminEmail = "admin@${domain}";
        dnsProvider = "cloudflare";
        credentialsFile = config.sops.secrets."nixos-core/cloudflare/api-key".path;
      };

      # Cloudflare API key for Let's Encrypt DNS challenge
      sops.secrets."nixos-core/cloudflare/api-key" = {
        mode = "0400";
        owner = "nginx";
        group = "nginx";
      };
    })

    (optionalAttrs true {
      shb.ldap = {
        enable = true;
        inherit domain;
        subdomain = "ldap";
        ssl = config.shb.certs.certs.letsencrypt.${domain};
        ldapPort = 3890;
        webUIListenPort = 17170;
        dcdomain = "dc=pixelkeepers,dc=net";
        ldapUserPassword.result = config.shb.sops.secret."ldap/user_password".result;
        jwtSecret.result = config.shb.sops.secret."ldap/jwt_secret".result;
        debug = false;
      };
      shb.sops.secret."ldap/user_password".request = config.shb.ldap.ldapUserPassword.request;
      shb.sops.secret."ldap/jwt_secret".request = config.shb.ldap.jwtSecret.request;

      shb.zfs.datasets."safe/ldap".path = "/var/lib/private/lldap";
    })

    (optionalAttrs true {
      # Plex backup configuration using restic (testing simpler service name)
      shb.restic.instances.plex = {
        request = config.shb.plex.backup.request;
        settings = {
          enable = true;
          passphrase.result = config.shb.sops.secret."plex/backup/passphrase".result;
          repository = {
            path = "/srv/backup/plex";
            timerConfig = {
              OnBootSec = "15min";
              OnUnitActiveSec = "1h";
              RandomizedDelaySec = "7min";
            };
          };
          retention = {
            keep_within = "1d";
            keep_hourly = 24;
            keep_daily = 7;
            keep_weekly = 4;
            keep_monthly = 6;
          };
        };
      };
      shb.sops.secret."plex/backup/passphrase" = {
        request = config.shb.restic.instances.plex.settings.passphrase.request;
      };

      # Enable debug logging for systemd services
      systemd.services."restic-backups-plex" = {
        serviceConfig = {
          # Add debugging environment variables
          Environment = [
            "SYSTEMD_LOG_LEVEL=debug"
            "SYSTEMD_LOG_TARGET=journal"
          ];
        };
        # Force service to be created even if it fails validation
        overrideStrategy = "asDropin";
      };
    })

    (optionalAttrs true {
      # LDAP backup configuration
      shb.restic.instances.ldap-backup = {
        request = {
          user = "root";
          sourceDirectories = [
            "/var/lib/private/lldap/"
          ];
        };
        settings = {
          enable = true;
          passphrase.result = config.shb.sops.secret."ldap/backup/passphrase".result;
          repository = {
            path = "/srv/backup/ldap";
            timerConfig = {
              OnBootSec = "15min";
              OnUnitActiveSec = "1h";
              RandomizedDelaySec = "7min";
            };
          };
          retention = {
            keep_within = "1d";
            keep_hourly = 24;
            keep_daily = 7;
            keep_weekly = 4;
            keep_monthly = 6;
          };
        };
      };
      shb.sops.secret."ldap/backup/passphrase" = {
        request = config.shb.restic.instances.ldap-backup.settings.passphrase.request;
      };
    })

    (optionalAttrs true {
      shb.authelia = {
        enable = true;
        inherit domain;
        subdomain = "authelia";
        ssl = config.shb.certs.certs.letsencrypt.${domain};

        ldapHostname = "127.0.0.1";
        ldapPort = config.shb.ldap.ldapPort;
        dcdomain = config.shb.ldap.dcdomain;

        # Access control rules with 2FA requirement for all services
        rules = [
          {
            domain = "authelia.${domain}";
            policy = "bypass";
            resources = [
              "^/\\.well-known/.*"
              "^/api/oidc/.*"
            ];
          }
          # Vaultwarden admin - restrict to vaultwarden_admin group only
          {
            domain = "vw.${domain}";
            policy = "two_factor";
            resources = ["^/admin.*"];
            subject = ["group:vaultwarden_admin"];
          }
          # Vaultwarden main - allow normal access (bypass Authelia for main vault functionality)
          {
            domain = "vw.${domain}";
            policy = "bypass";
          }
          # Other specific services require 2FA
          {
            domain = "nextcloud.${domain}";
            policy = "two_factor";
          }
          {
            domain = "ldap.${domain}";
            policy = "two_factor";
            subject = ["group:lldap_admin"];
          }
          # Media management services - require 2FA
          {
            domain = "radarr.${domain}";
            policy = "two_factor";
          }
          {
            domain = "sonarr.${domain}";
            policy = "two_factor";
          }
          {
            domain = "jackett.${domain}";
            policy = "two_factor";
          }
        ];

        # SMTP configuration for email notifications (temporarily disabled due to systemd unit naming bug)
        # smtp = {
        #   host = "mail.pixelkeepers.net";
        #   port = 465;
        #   username = "admin@mail.pixelkeepers.net";
        #   password.result = config.shb.sops.secret."authelia/smtp_password".result;
        #   from_address = "admin@pixelkeepers.net";
        # };

        secrets = {
          jwtSecret.result = config.shb.sops.secret."authelia/jwt_secret".result;
          ldapAdminPassword.result = config.shb.sops.secret."authelia/ldap_admin_password".result;
          sessionSecret.result = config.shb.sops.secret."authelia/session_secret".result;
          storageEncryptionKey.result = config.shb.sops.secret."authelia/storage_encryption_key".result;
          identityProvidersOIDCHMACSecret.result = config.shb.sops.secret."authelia/hmac_secret".result;
          identityProvidersOIDCIssuerPrivateKey.result = config.shb.sops.secret."authelia/private_key".result;
        };
      };
      shb.sops.secret."authelia/jwt_secret".request = config.shb.authelia.secrets.jwtSecret.request;
      shb.sops.secret."authelia/ldap_admin_password" = {
        request = config.shb.authelia.secrets.ldapAdminPassword.request;
        settings.key = "ldap/user_password";
      };
      shb.sops.secret."authelia/session_secret".request = config.shb.authelia.secrets.sessionSecret.request;
      shb.sops.secret."authelia/storage_encryption_key".request = config.shb.authelia.secrets.storageEncryptionKey.request;
      shb.sops.secret."authelia/hmac_secret".request = config.shb.authelia.secrets.identityProvidersOIDCHMACSecret.request;
      shb.sops.secret."authelia/private_key".request = config.shb.authelia.secrets.identityProvidersOIDCIssuerPrivateKey.request;
      # shb.sops.secret."authelia/smtp_password".request = config.shb.authelia.smtp.password.request;

      shb.zfs.datasets."safe/authelia-${domain}" = config.shb.authelia.mount;
      shb.zfs.datasets."safe/authelia-redis" = config.shb.authelia.mountRedis;
    })

    (optionalAttrs true {
      shb.vaultwarden = {
        enable = true;
        inherit domain;
        subdomain = "vw";
        ssl = config.shb.certs.certs.letsencrypt.${domain};
        port = 8222;
        # Note: authEndpoint removed - using manual nginx + Authelia rules instead
        databasePassword.result = config.shb.sops.secret."vaultwarden/db".result;
      };
      shb.sops.secret."vaultwarden/db" = {
        request = config.shb.vaultwarden.databasePassword.request;
      };

      # Override nginx configuration to add selective Authelia protection
      services.nginx.virtualHosts."vw.${domain}".locations = lib.mkForce {
        # Main Vaultwarden - no auth, keep normal security headers
        "/" = {
          proxyPass = "http://127.0.0.1:8222";
          extraConfig = ''
            # Standard proxy headers
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_cache_bypass $http_upgrade;
          '';
        };
        # 2FA connector endpoints - remove X-Frame-Options for iframe compatibility
        "~ ^/(identity/connect/|two-factor)" = {
          proxyPass = "http://127.0.0.1:8222";
          extraConfig = ''
            # Remove X-Frame-Options header only for 2FA connector calls
            proxy_hide_header X-Frame-Options;

            # Standard proxy headers
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_cache_bypass $http_upgrade;
          '';
        };
        # Admin panel - protected by Authelia with group restriction
        "/admin" = {
          proxyPass = "http://127.0.0.1:8222";
          extraConfig = ''
            auth_request /authelia;
            auth_request_set $user $upstream_http_remote_user;
            auth_request_set $groups $upstream_http_remote_groups;

            # Redirect to Authelia login on authentication failure
            error_page 401 = @authelia_redirect;

            proxy_set_header X-Forwarded-User $user;
            proxy_set_header X-Forwarded-Groups $groups;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_cache_bypass $http_upgrade;
          '';
        };
        # Authelia redirect handler
        "@authelia_redirect" = {
          extraConfig = ''
            return 302 https://authelia.${domain}/?rd=$scheme://$http_host$request_uri;
          '';
        };
        # Authelia endpoint for auth_request
        "/authelia" = {
          proxyPass = "http://127.0.0.1:9091/api/verify";
          extraConfig = ''
            internal;
            proxy_pass_request_body off;
            proxy_set_header Content-Length "";
            proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
          '';
        };
      };

      # Override nginx configuration for LLDAP to add Authelia protection
      services.nginx.virtualHosts."ldap.${domain}".locations = {
        # All LLDAP paths - protected by Authelia with group restriction
        "/" = {
          proxyPass = lib.mkForce "http://127.0.0.1:17170";
          extraConfig = lib.mkForce ''
            auth_request /authelia-ldap;
            auth_request_set $user $upstream_http_remote_user;
            auth_request_set $groups $upstream_http_remote_groups;

            # Redirect to Authelia login on authentication failure
            error_page 401 = @authelia_redirect_ldap;

            proxy_set_header X-Forwarded-User $user;
            proxy_set_header X-Forwarded-Groups $groups;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_cache_bypass $http_upgrade;
          '';
        };
        # Authelia redirect handler for LLDAP
        "@authelia_redirect_ldap" = {
          extraConfig = ''
            return 302 https://authelia.${domain}/?rd=$scheme://$http_host$request_uri;
          '';
        };
        # Authelia endpoint for LLDAP auth_request
        "/authelia-ldap" = {
          proxyPass = "http://127.0.0.1:9091/api/verify";
          extraConfig = ''
            internal;
            proxy_pass_request_body off;
            proxy_set_header Content-Length "";
            proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
          '';
        };
      };

      shb.zfs.datasets."safe/vaultwarden" = config.shb.vaultwarden.mount;
      shb.zfs.datasets."safe/postgresql".path = "/var/lib/postgresql";

      # Override PostgreSQL package to use version 17 (to match backup)
      services.postgresql.package = pkgs.postgresql_17;

      # OIDC configuration - secure and properly validated
      services.nextcloud.settings."oidc_login_tls_verify" = lib.mkForce true;

      # OIDC attribute mapping - use proper display name from LDAP
      services.nextcloud.settings."oidc_login_attributes" = lib.mkForce {
        id = "preferred_username"; # Use username for user ID (alice, h4wkeye, etc.)
        name = "name"; # Use full name from LDAP (Marek Pawlak)
        mail = "email"; # Email from LDAP
        groups = "groups";
      };

      # Use userinfo endpoint for reliable claim processing
      services.nextcloud.settings."oidc_login_use_id_token" = lib.mkForce false;
    })

    (optionalAttrs true {
      # Vaultwarden backup configuration
      shb.restic.instances.vaultwarden-backup = {
        request = config.shb.vaultwarden.backup.request;
        settings = {
          enable = true;
          passphrase.result = config.shb.sops.secret."vaultwarden/backup/passphrase".result;
          repository = {
            path = "/srv/backup/vaultwarden";
            timerConfig = {
              OnBootSec = "15min";
              OnUnitActiveSec = "1h";
              RandomizedDelaySec = "7min";
            };
          };
          retention = {
            keep_within = "1d";
            keep_hourly = 24;
            keep_daily = 7;
            keep_weekly = 4;
            keep_monthly = 6;
          };
        };
      };
      shb.sops.secret."vaultwarden/backup/passphrase" = {
        request = config.shb.restic.instances.vaultwarden-backup.settings.passphrase.request;
      };
    })

    (optionalAttrs true {
      shb.zfs.datasets."safe/nextcloud".path = "/var/lib/nextcloud";
      shb.zfs.datasets."safe/redis-nextcloud".path = "/var/lib/redis-nextcloud";
      # Optional: Store Nextcloud user data on data pool
      # shb.zfs.datasets."nextcloud" = {
      #   poolName = "zdata";
      #   path = "/srv/nextcloud/data";
      # };
      shb.nextcloud = {
        enable = true;
        debug = true;
        inherit domain;
        subdomain = "nextcloud";
        ssl = config.shb.certs.certs.letsencrypt.${domain};
        defaultPhoneRegion = "PL";

        version = 30;
        dataDir = "/var/lib/nextcloud";
        adminPass.result = config.shb.sops.secret."nextcloud/adminpass".result;
        apps = {
          ldap = {
            enable = true;
            host = "127.0.0.1";
            port = config.shb.ldap.ldapPort;
            dcdomain = config.shb.ldap.dcdomain;
            adminName = "admin";
            adminPassword.result = config.shb.sops.secret."nextcloud/ldap_admin_password".result;
            userGroup = "nextcloud_user";
          };
          sso = {
            enable = true;
            endpoint = "https://${config.shb.authelia.subdomain}.${config.shb.authelia.domain}";
            clientID = "nextcloud";
            authorization_policy = "two_factor";

            secret.result = config.shb.sops.secret."nextcloud/sso/secret".result;
            secretForAuthelia.result = config.shb.sops.secret."authelia/nextcloud_sso_secret".result;

            fallbackDefaultAuth = false;
          };
        };
        # Chose static and small number of children to avoid too much I/O strain on hard drives.
        phpFpmPoolSettings = {
          "pm" = "static";
          "pm.max_children" = 50;
        };
      };
      systemd.services.postgresql.serviceConfig.Restart = "always";
      # Secret needed for services.nextcloud.config.adminpassFile.
      shb.sops.secret."nextcloud/adminpass" = {
        request = config.shb.nextcloud.adminPass.request;
      };
      shb.sops.secret."nextcloud/ldap_admin_password" = {
        request = config.shb.nextcloud.apps.ldap.adminPassword.request;
        settings.key = "ldap/user_password";
      };

      shb.sops.secret."nextcloud/sso/secret" = {
        request = config.shb.nextcloud.apps.sso.secret.request;
      };
      shb.sops.secret."authelia/nextcloud_sso_secret" = {
        request = config.shb.nextcloud.apps.sso.secretForAuthelia.request;
        settings.key = "nextcloud/sso/secret";
      };
    })

    (optionalAttrs true {
      # Nextcloud backup configuration
      shb.restic.instances.nextcloud-backup = {
        request = config.shb.nextcloud.backup.request;
        settings = {
          enable = true;
          passphrase.result = config.shb.sops.secret."nextcloud/backup/passphrase".result;
          repository = {
            path = "/srv/backup/nextcloud";
            timerConfig = {
              OnBootSec = "15min";
              OnUnitActiveSec = "1h";
              RandomizedDelaySec = "7min";
            };
          };
          retention = {
            keep_within = "1d";
            keep_hourly = 24;
            keep_daily = 7;
            keep_weekly = 4;
            keep_monthly = 6;
          };
        };
      };
      shb.sops.secret."nextcloud/backup/passphrase" = {
        request = config.shb.restic.instances.nextcloud-backup.settings.passphrase.request;
      };
    })

    # Custom ZFS dataset management for data pools (your custom disk setup)
    {
      # Ensure custom ZFS pool passphrases are available during boot
      boot.zfs.extraPools = ["zdata" "zprivate"];

      # Add nofail and noauto options to ALL custom ZFS datasets to prevent boot/deploy issues
      fileSystems = {
        "/mnt/zdata/media".options = ["nofail" "noauto"];
        "/mnt/zprivate/backups".options = ["nofail" "noauto"];
        "/mnt/zprivate/documents".options = ["nofail" "noauto"];
        "/mnt/zprivate/nextcloud".options = ["nofail" "noauto"];
        "/mnt/zprivate/pictures".options = ["nofail" "noauto"];
        "/mnt/zprivate/postgresql".options = ["nofail" "noauto"];
      };

      # Ensure ZFS datasets are created and mounted
      systemd.services.create-zfs-datasets = {
        description = "Create initial ZFS datasets and mount custom pools";
        wantedBy = ["multi-user.target"];
        after = ["zfs-mount.service" "zfs-import.target"];
        path = [pkgs.zfs];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          # Wait for ZFS pools to be available
          sleep 2

          # Create missing ZFS datasets if they don't exist
          zfs list zprivate/postgresql >/dev/null 2>&1 || {
            echo "Creating missing zprivate/postgresql dataset"
            zfs create -o recordsize=8K -o mountpoint=/mnt/zprivate/postgresql zprivate/postgresql
          }

          # Mount all custom ZFS datasets manually (since we used noauto)
          # Mount parent datasets first
          zfs mount zdata/media || true

          # Mount zprivate datasets
          zfs mount zprivate/backups || true
          zfs mount zprivate/documents || true
          zfs mount zprivate/nextcloud || true
          zfs mount zprivate/pictures || true
          zfs mount zprivate/postgresql || true

          # Create directories for media organization (now regular directories, not datasets)
          mkdir -p /mnt/zdata/media/downloads || true
          mkdir -p /mnt/zdata/media/movies || true
          mkdir -p /mnt/zdata/media/tv || true
          mkdir -p /mnt/zdata/media/music || true
          mkdir -p /mnt/zdata/media/books || true
          mkdir -p /mnt/zdata/media/comics || true

          # Set proper permissions for base directories
          chown h4wkeye:users /mnt/zdata || true
          chmod 755 /mnt/zdata || true
          chown -R h4wkeye:users /mnt/zprivate || true
          chmod -R 700 /mnt/zprivate || true  # More restrictive for private data

          # Set media permissions recursively (all directories on same dataset now)
          chown -R h4wkeye:arr_user /mnt/zdata/media || true
          chmod -R 775 /mnt/zdata/media || true
        '';
      };

      # ZFS auto-scrub
      services.zfs.autoScrub = {
        enable = true;
        interval = "monthly";
        pools = ["root" "zdata" "zprivate"];
      };

      # ZFS auto-snapshot
      services.zfs.autoSnapshot = {
        enable = true;
        frequent = 4; # 15-minute snapshots, keep 4
        hourly = 24; # hourly snapshots, keep 24
        daily = 7; # daily snapshots, keep 7
        weekly = 4; # weekly snapshots, keep 4
        monthly = 12; # monthly snapshots, keep 12
      };
    }
  ];
}
