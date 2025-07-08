{ lib, pkgs, mkRequest, mkResult }:

{
  name = "database";
  version = "1.0.0";
  description = "Database service contract";
  
  # Request schema - what services can ask for
  requestSchema = {
    type = lib.mkOption {
      type = lib.types.enum [ "postgresql" "mysql" "sqlite" ];
      description = "Database type";
    };
    
    name = lib.mkOption {
      type = lib.types.str;
      description = "Database name";
    };
    
    user = lib.mkOption {
      type = lib.types.str;
      description = "Database user";
    };
    
    password_secret = lib.mkOption {
      type = lib.types.str;
      description = "Path to database password secret";
    };
    
    extensions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Database extensions to enable (PostgreSQL only)";
    };
    
    initial_script = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Initial SQL script to run";
    };
  };
  
  # Result schema - what providers must deliver
  resultSchema = {
    connection_string = lib.mkOption {
      type = lib.types.str;
      description = "Database connection string";
    };
    
    host = lib.mkOption {
      type = lib.types.str;
      description = "Database host";
    };
    
    port = lib.mkOption {
      type = lib.types.int;
      description = "Database port";
    };
    
    socket_path = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Unix socket path for local connections";
    };
    
    backup_command = lib.mkOption {
      type = lib.types.str;
      description = "Command to backup this database";
    };
    
    restore_command = lib.mkOption {
      type = lib.types.str;
      description = "Command to restore this database";
    };
  };
  
  # Create database request
  mkRequest = { type, name, user, password_secret, extensions ? [], initial_script ? null }:
    mkRequest "database" {
      inherit type name user password_secret extensions initial_script;
    };
  
  # Validate database request
  validateRequest = request:
    assert request.payload.type != null;
    assert request.payload.name != null;
    assert request.payload.user != null;
    assert request.payload.password_secret != null;
    true;
    
  # Validate database result
  validateResult = result:
    assert result.payload.connection_string != null;
    assert result.payload.host != null;
    assert result.payload.port != null;
    true;
}