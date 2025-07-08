{ lib, pkgs, registerProvider }:

registerProvider {
  name = "restic";
  contract_type = "backup";
  version = "1.0.0";
  description = "Restic backup provider with deduplication and encryption";
  
  capabilities = {
    incremental = true;
    deduplication = true;
    encryption = true;
    cloud_storage = true;
    compression = true;
  };
  
  configSchema = {
    repository_base = lib.mkOption {
      type = lib.types.str;
      description = "Base path for backup repositories";
    };
    
    password_file = lib.mkOption {
      type = lib.types.path;
      description = "Path to repository password file";
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
  };
  
  canFulfill = request: request.contract_type == "backup";
  
  fulfill = request: providerConfig:
    let
      # Generate unique job name from service name and contract type
      jobName = "restic-${request.requester_id or "backup"}";
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
      
      # Retention policy arguments
      retentionArgs = 
        lib.optionalString (request.payload.retention.daily or 0 > 0) "--keep-daily ${toString request.payload.retention.daily} " +
        lib.optionalString (request.payload.retention.weekly or 0 > 0) "--keep-weekly ${toString request.payload.retention.weekly} " +
        lib.optionalString (request.payload.retention.monthly or 0 > 0) "--keep-monthly ${toString request.payload.retention.monthly} " +
        lib.optionalString (request.payload.retention.yearly or 0 > 0) "--keep-yearly ${toString request.payload.retention.yearly}";
      
    in {
      config = {
        # Install restic package
        environment.systemPackages = [ pkgs.restic ];
        
        # Create backup user and group
        users.users.restic = {
          isSystemUser = true;
          group = "restic";
          home = "/var/lib/restic";
          createHome = true;
        };
        users.groups.restic = {};
        
        # Create repository directory
        systemd.tmpfiles.rules = [
          "d ${providerConfig.repository_base} 0750 restic restic -"
          "d ${repoPath} 0750 restic restic -"
        ];
        
        # Repository initialization service
        systemd.services."${jobName}-init" = {
          description = "Initialize Restic repository for ${jobName}";
          serviceConfig = {
            Type = "oneshot";
            User = "restic";
            Group = "restic";
            RemainAfterExit = true;
          };
          environment = {
            RESTIC_REPOSITORY = repoPath;
            RESTIC_PASSWORD_FILE = toString providerConfig.password_file;
          };
          script = ''
            # Check if repository exists, initialize if not
            if ! ${pkgs.restic}/bin/restic snapshots >/dev/null 2>&1; then
              echo "Initializing Restic repository at ${repoPath}"
              ${pkgs.restic}/bin/restic init
            else
              echo "Repository already initialized"
            fi
          '';
          wantedBy = [ "multi-user.target" ];
        };
        
        # Main backup service
        systemd.services."${jobName}" = {
          description = "Restic backup job for ${jobName}";
          requires = [ "${jobName}-init.service" ];
          after = [ "${jobName}-init.service" ];
          
          serviceConfig = {
            Type = "oneshot";
            User = "restic";
            Group = "restic";
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
              "/var/lib/restic"
            ] ++ request.payload.paths;
            ReadOnlyPaths = request.payload.paths;
          };
          
          environment = {
            RESTIC_REPOSITORY = repoPath;
            RESTIC_PASSWORD_FILE = toString providerConfig.password_file;
          };
          
          script = ''
            set -e
            
            echo "Starting backup job ${jobName}"
            echo "Repository: ${repoPath}"
            echo "Backup paths: ${backupPaths}"
            
            # Pre-backup check
            echo "Checking repository integrity..."
            if ! ${pkgs.restic}/bin/restic check --read-data-subset=5%; then
              echo "Repository check failed, attempting repair..."
              ${pkgs.restic}/bin/restic prune --max-repack-size 100M
            fi
            
            # Perform backup
            echo "Starting backup..."
            ${pkgs.restic}/bin/restic backup ${excludeArgs} \
              --verbose \
              --tag psf-backup \
              --tag ${jobName} \
              --host $(hostname) \
              ${backupPaths}
            
            # Clean up old backups according to retention policy
            if [ -n "${retentionArgs}" ]; then
              echo "Applying retention policy..."
              ${pkgs.restic}/bin/restic forget ${retentionArgs} --prune --verbose
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
          description = "Check Restic repository integrity for ${jobName}";
          
          serviceConfig = {
            Type = "oneshot";
            User = "restic";
            Group = "restic";
            Nice = 19;
            IOSchedulingClass = "3"; # idle
          };
          
          environment = {
            RESTIC_REPOSITORY = repoPath;
            RESTIC_PASSWORD_FILE = toString providerConfig.password_file;
          };
          
          script = ''
            echo "Checking repository integrity for ${jobName}"
            ${pkgs.restic}/bin/restic check --read-data-subset=10%
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
      };
      
      result = {
        contract_type = "backup";
        payload = {
          backup_job_name = jobName;
          repository_path = repoPath;
          service_name = "${jobName}.service";
          timer_name = "${jobName}.timer";
          restore_command = "RESTIC_REPOSITORY=${repoPath} RESTIC_PASSWORD_FILE=${toString providerConfig.password_file} ${pkgs.restic}/bin/restic restore latest --target";
        };
        metadata = {
          provider_version = "1.0.0";
          repository_path = repoPath;
          backup_user = "restic";
          nice_level = providerConfig.nice_level;
          ionice_class = providerConfig.ionice_class;
          ionice_priority = providerConfig.ionice_priority;
          check_service = "${jobName}-check.service";
          check_timer = "${jobName}-check.timer";
        };
      };
    };
  
  validate = request: providerConfig:
    lib.optional (providerConfig.repository_base == null) "Repository base path must be configured" ++
    lib.optional (providerConfig.password_file == null) "Password file path must be configured" ++
    lib.optional (!lib.isString (toString providerConfig.password_file) || toString providerConfig.password_file == "") "Password file path must be a non-empty string" ++
    lib.optional (providerConfig.nice_level < 0 || providerConfig.nice_level > 19) "Nice level must be between 0 and 19" ++
    lib.optional (providerConfig.ionice_priority < 0 || providerConfig.ionice_priority > 7) "IO priority must be between 0 and 7" ++
    lib.optional (!lib.elem providerConfig.ionice_class ["none" "rt" "best-effort" "idle"]) "IO class must be one of: none, rt, best-effort, idle" ++
    lib.optional (builtins.length request.payload.paths == 0) "At least one backup path must be specified" ++
    lib.optional (!lib.all (path: lib.isString path && path != "") request.payload.paths) "All backup paths must be non-empty strings";
}