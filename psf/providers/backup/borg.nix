{ lib, pkgs, registerProvider }:

registerProvider {
  name = "borg";
  contract_type = "backup";
  version = "1.0.0";
  description = "BorgBackup provider";
  
  capabilities = {
    incremental = true;
    deduplication = true;
    encryption = true;
    compression = true;
  };
  
  configSchema = {
    repository_base = lib.mkOption {
      type = lib.types.str;
      description = "Base path for backup repositories";
    };
  };
  
  canFulfill = request: request.contract_type == "backup";
  
  fulfill = request: providerConfig: {
    config = {
      warnings = [ "Borg backup provider not yet implemented" ];
    };
    
    result = {
      contract_type = "backup";
      payload = {
        backup_job_name = "borg-backup";
        repository_path = "${providerConfig.repository_base}/repo";
        service_name = "borg-backup.service";
        timer_name = "borg-backup.timer";
        restore_command = "borg extract ::latest";
      };
      metadata = {
        provider_version = "1.0.0";
        implementation_status = "placeholder";
      };
    };
  };
  
  validate = request: providerConfig: [];
}