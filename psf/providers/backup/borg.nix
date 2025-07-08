{ lib, pkgs, registerProvider }:

registerProvider {
  name = "borg";
  contract_type = "backup";
  version = "1.0.0";
  description = "BorgBackup provider with deduplication and compression";
  
  capabilities = {
    incremental = true;
    deduplication = true;
    encryption = true;
    compression = true;
    cross_platform = true;
  };
  
  configSchema = {
    repository_base = lib.mkOption {
      type = lib.types.str;
      description = "Base path for backup repositories";
    };
    
    passphrase_file = lib.mkOption {
      type = lib.types.path;
      description = "Path to repository passphrase file";
    };
    
    encryption_mode = lib.mkOption {
      type = lib.types.str;
      default = "repokey";
      description = "Encryption mode (none, repokey, keyfile, repokey-blake2, keyfile-blake2)";
    };
    
    compression = lib.mkOption {
      type = lib.types.str;
      default = "lz4";
      description = "Compression algorithm (none, lz4, zlib, lzma, zstd)";
    };
    
    nice_level = lib.mkOption {
      type = lib.types.int;
      default = 15;
      description = "Nice level for backup process (lower priority)";
    };
    
    ionice_class = lib.mkOption {
      type = lib.types.str;
      default = "best-effort";
      description = "IO scheduling class (none, rt, best-effort, idle)";
    };
    
    ionice_priority = lib.mkOption {
      type = lib.types.int;
      default = 7;
      description = "IO priority (0-7, 7 is lowest)";
    };
    
    check_frequency = lib.mkOption {
      type = lib.types.str;
      default = "weekly";
      description = "How often to check repository integrity";
    };
    
    compact_frequency = lib.mkOption {
      type = lib.types.str;
      default = "monthly";
      description = "How often to compact repository";
    };
  };
  
  canFulfill = request: request.contract_type == "backup";
  
  fulfill = request: providerConfig:
    let
      # Generate unique job name from service name and contract type
      jobName = "borg-${request.requester_id or "backup"}";
      repoPath = "${providerConfig.repository_base}/${jobName}";
      
      # Convert schedule to systemd timer format
      timerConfig = if request.payload.schedule == "daily" then {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "1h";
      } else if request.payload.schedule == "weekly" then {
        OnCalendar = "weekly";
        Persistent = true;
        RandomizedDelaySec = "2h";
      } else if request.payload.schedule == "hourly" then {
        OnCalendar = "hourly";
        Persistent = true;
        RandomizedDelaySec = "10m";
      } else {
        OnCalendar = request.payload.schedule;
        Persistent = true;
        RandomizedDelaySec = "30m";
      };
      
      # Build exclude arguments
      excludeArgs = lib.concatMapStringsSep " " (exclude: "--exclude '${exclude}'") request.payload.excludes;
      
      # Build backup paths
      backupPaths = lib.concatStringsSep " " (map (path: "'${path}'") request.payload.paths);
      
      # Build prune arguments from retention policy
      pruneArgs = 
        lib.optionalString (request.payload.retention.daily or 0 > 0) "--keep-daily ${toString request.payload.retention.daily} " +
        lib.optionalString (request.payload.retention.weekly or 0 > 0) "--keep-weekly ${toString request.payload.retention.weekly} " +
        lib.optionalString (request.payload.retention.monthly or 0 > 0) "--keep-monthly ${toString request.payload.retention.monthly} " +
        lib.optionalString (request.payload.retention.yearly or 0 > 0) "--keep-yearly ${toString request.payload.retention.yearly}";
      
      # Generate archive name with timestamp
      archiveName = "{hostname}-{now:%Y-%m-%d-%H%M%S}";
      
    in {
      config = {
        # Install borgbackup package
        environment.systemPackages = [ pkgs.borgbackup ];
        
        # Create backup user and group
        users.users.borg = {
          isSystemUser = true;
          group = "borg";
          home = "/var/lib/borg";
          createHome = true;
        };
        users.groups.borg = {};
        
        # Create repository directory
        systemd.tmpfiles.rules = [
          "d ${providerConfig.repository_base} 0750 borg borg -"
          "d ${repoPath} 0750 borg borg -"
        ];
        
        # Repository initialization service
        systemd.services."${jobName}-init" = {
          description = "Initialize Borg repository for ${jobName}";
          serviceConfig = {
            Type = "oneshot";
            User = "borg";
            Group = "borg";
            RemainAfterExit = true;
          };
          environment = {
            BORG_REPO = repoPath;
            BORG_PASSPHRASE_FILE = toString providerConfig.passphrase_file;
            BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK = "yes";
            BORG_RELOCATED_REPO_ACCESS_IS_OK = "yes";
          };
          script = ''
            # Check if repository exists, initialize if not
            if ! ${pkgs.borgbackup}/bin/borg list >/dev/null 2>&1; then
              echo "Initializing Borg repository at ${repoPath}"
              ${pkgs.borgbackup}/bin/borg init --encryption=${providerConfig.encryption_mode}
            else
              echo "Repository already initialized"
            fi
          '';
          wantedBy = [ "multi-user.target" ];
        };
        
        # Main backup service
        systemd.services."${jobName}" = {
          description = "Borg backup job for ${jobName}";
          requires = [ "${jobName}-init.service" ];
          after = [ "${jobName}-init.service" ];
          
          serviceConfig = {
            Type = "oneshot";
            User = "borg";
            Group = "borg";
            Nice = providerConfig.nice_level;
            IOSchedulingClass = 
              if providerConfig.ionice_class == "none" then "0"
              else if providerConfig.ionice_class == "rt" then "1"
              else if providerConfig.ionice_class == "best-effort" then "2"
              else if providerConfig.ionice_class == "idle" then "3"
              else "2";
            IOSchedulingPriority = providerConfig.ionice_priority;
            PrivateTmp = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ReadWritePaths = [ 
              providerConfig.repository_base
              "/var/lib/borg"
            ] ++ request.payload.paths;
            ReadOnlyPaths = request.payload.paths;
          };
          
          environment = {
            BORG_REPO = repoPath;
            BORG_PASSPHRASE_FILE = toString providerConfig.passphrase_file;
            BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK = "yes";
            BORG_RELOCATED_REPO_ACCESS_IS_OK = "yes";
          };
          
          script = ''
            set -e
            
            echo "Starting backup job ${jobName}"
            echo "Repository: ${repoPath}"
            echo "Backup paths: ${backupPaths}"
            
            # Pre-backup repository check
            echo "Checking repository integrity..."
            ${pkgs.borgbackup}/bin/borg check --verify-data --show-rc
            
            # Perform backup
            echo "Starting backup..."
            ${pkgs.borgbackup}/bin/borg create \
              --verbose \
              --stats \
              --compression ${providerConfig.compression} \
              --checkpoint-interval 300 \
              ${excludeArgs} \
              "::${archiveName}" \
              ${backupPaths}
            
            # Prune old backups according to retention policy
            if [ -n "${pruneArgs}" ]; then
              echo "Pruning old backups..."
              ${pkgs.borgbackup}/bin/borg prune \
                --verbose \
                --stats \
                --list \
                ${pruneArgs}
            fi
            
            echo "Backup completed successfully"
          '';
          
          # Log output
          StandardOutput = "journal";
          StandardError = "journal";
        };
        
        # Timer for scheduled backups
        systemd.timers."${jobName}" = {
          description = "Timer for ${jobName} backup";
          wantedBy = [ "timers.target" ];
          timerConfig = timerConfig // {
            AccuracySec = "1h";
          };
        };
        
        # Repository check service
        systemd.services."${jobName}-check" = {
          description = "Check Borg repository integrity for ${jobName}";
          
          serviceConfig = {
            Type = "oneshot";
            User = "borg";
            Group = "borg";
            Nice = 19;
            IOSchedulingClass = "3"; # idle
          };
          
          environment = {
            BORG_REPO = repoPath;
            BORG_PASSPHRASE_FILE = toString providerConfig.passphrase_file;
            BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK = "yes";
            BORG_RELOCATED_REPO_ACCESS_IS_OK = "yes";
          };
          
          script = ''
            echo "Checking repository integrity for ${jobName}"
            ${pkgs.borgbackup}/bin/borg check --verify-data --show-rc
            echo "Repository check completed"
          '';
        };
        
        # Timer for repository checks
        systemd.timers."${jobName}-check" = {
          description = "Timer for ${jobName} repository check";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = providerConfig.check_frequency;
            Persistent = true;
            RandomizedDelaySec = "4h";
          };
        };
        
        # Repository compaction service
        systemd.services."${jobName}-compact" = {
          description = "Compact Borg repository for ${jobName}";
          
          serviceConfig = {
            Type = "oneshot";
            User = "borg";
            Group = "borg";
            Nice = 19;
            IOSchedulingClass = "3"; # idle
          };
          
          environment = {
            BORG_REPO = repoPath;
            BORG_PASSPHRASE_FILE = toString providerConfig.passphrase_file;
            BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK = "yes";
            BORG_RELOCATED_REPO_ACCESS_IS_OK = "yes";
          };
          
          script = ''
            echo "Compacting repository for ${jobName}"
            ${pkgs.borgbackup}/bin/borg compact --verbose
            echo "Repository compaction completed"
          '';
        };
        
        # Timer for repository compaction
        systemd.timers."${jobName}-compact" = {
          description = "Timer for ${jobName} repository compaction";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = providerConfig.compact_frequency;
            Persistent = true;
            RandomizedDelaySec = "6h";
          };
        };
      };
      
      result = {
        contract_type = "backup";
        payload = {
          backup_job_name = jobName;
          repository_path = repoPath;
          service_name = "${jobName}.service";
          timer_name = "${jobName}.timer";
          restore_command = "BORG_REPO=${repoPath} BORG_PASSPHRASE_FILE=${toString providerConfig.passphrase_file} ${pkgs.borgbackup}/bin/borg extract ::latest";
        };
        metadata = {
          provider_version = "1.0.0";
          repository_path = repoPath;
          backup_user = "borg";
          encryption_mode = providerConfig.encryption_mode;
          compression = providerConfig.compression;
          nice_level = providerConfig.nice_level;
          ionice_class = providerConfig.ionice_class;
          ionice_priority = providerConfig.ionice_priority;
          check_service = "${jobName}-check.service";
          check_timer = "${jobName}-check.timer";
          compact_service = "${jobName}-compact.service";
          compact_timer = "${jobName}-compact.timer";
        };
      };
    };
  
  validate = request: providerConfig:
    lib.optional (providerConfig.repository_base == null) "Repository base path must be configured" ++
    lib.optional (providerConfig.passphrase_file == null) "Passphrase file path must be configured" ++
    lib.optional (!lib.isString (toString providerConfig.passphrase_file) || toString providerConfig.passphrase_file == "") "Passphrase file path must be a non-empty string" ++
    lib.optional (!lib.elem providerConfig.encryption_mode ["none" "repokey" "keyfile" "repokey-blake2" "keyfile-blake2"]) "Encryption mode must be one of: none, repokey, keyfile, repokey-blake2, keyfile-blake2" ++
    lib.optional (!lib.elem providerConfig.compression ["none" "lz4" "zlib" "lzma" "zstd"]) "Compression must be one of: none, lz4, zlib, lzma, zstd" ++
    lib.optional (providerConfig.nice_level < 0 || providerConfig.nice_level > 19) "Nice level must be between 0 and 19" ++
    lib.optional (providerConfig.ionice_priority < 0 || providerConfig.ionice_priority > 7) "IO priority must be between 0 and 7" ++
    lib.optional (!lib.elem providerConfig.ionice_class ["none" "rt" "best-effort" "idle"]) "IO class must be one of: none, rt, best-effort, idle" ++
    lib.optional (builtins.length request.payload.paths == 0) "At least one backup path must be specified" ++
    lib.optional (!lib.all (path: lib.isString path && path != "") request.payload.paths) "All backup paths must be non-empty strings";
}