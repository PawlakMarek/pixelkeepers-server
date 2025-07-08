{ lib, pkgs, mkRequest, mkResult }:

{
  name = "backup";
  version = "1.0.0";
  description = "Backup service contract";
  
  # Request schema - what services can ask for
  requestSchema = {
    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "List of paths to backup";
    };
    
    excludes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of paths or patterns to exclude from backup";
    };
    
    schedule = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "Backup schedule (cron format or preset like 'daily', 'weekly')";
    };
    
    retention = lib.mkOption {
      type = lib.types.attrs;
      default = { daily = 7; weekly = 4; monthly = 12; };
      description = "Backup retention policy";
    };
  };
  
  # Result schema - what providers must deliver
  resultSchema = {
    backup_job_name = lib.mkOption {
      type = lib.types.str;
      description = "Name of the backup job";
    };
    
    repository_path = lib.mkOption {
      type = lib.types.str;
      description = "Path to backup repository";
    };
    
    service_name = lib.mkOption {
      type = lib.types.str;
      description = "Systemd service name for backup";
    };
    
    timer_name = lib.mkOption {
      type = lib.types.str;
      description = "Systemd timer name for scheduled backups";
    };
    
    restore_command = lib.mkOption {
      type = lib.types.str;
      description = "Command template for restoring from backup";
    };
  };
  
  # Create backup request
  mkRequest = { paths, excludes ? [], schedule ? "daily", retention ? { daily = 7; weekly = 4; monthly = 12; } }:
    mkRequest "backup" {
      inherit paths excludes schedule retention;
    };
  
  # Validate backup request
  validateRequest = request:
    assert request.payload.paths != null;
    assert builtins.isList request.payload.paths;
    assert builtins.length request.payload.paths > 0;
    true;
    
  # Validate backup result
  validateResult = result:
    assert result.payload.backup_job_name != null;
    assert result.payload.repository_path != null;
    assert result.payload.service_name != null;
    true;
}