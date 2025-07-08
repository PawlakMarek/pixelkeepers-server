# Test configuration for database contract integration
{ lib, pkgs }:

let
  psf = import ../../lib { inherit lib pkgs; };
  
  # Test configuration that uses PostgreSQL database contract
  testConfig = {
    psf = {
      enable = true;
      domain = "test.local";
      
      providers = {
        postgresql = {
          version = "17";
          port = 5432;
          max_connections = 100;
          backup_retention_days = 7;
        };
        
        hardcoded = {
          secrets = {
            testapp-db-password = "test-password-123";
          };
        };
      };
      
      services = {
        test-app = {
          enable = true;
          subdomain = "test";
          port = 8080;
        };
      };
    };
  };
  
  # Evaluate the configuration
  evaluatedConfig = lib.evalModules {
    modules = [ 
      psf.psfModule
      testConfig 
    ];
  };
  
in {
  # Test that configuration evaluates without errors
  testConfigEvaluation = {
    expr = evaluatedConfig.config ? psf;
    expected = true;
  };
  
  # Test that PSF is enabled
  testPSFEnabled = {
    expr = evaluatedConfig.config.psf.enable;
    expected = true;
  };
  
  # Test that domain is configured
  testDomainConfigured = {
    expr = evaluatedConfig.config.psf.domain;
    expected = "test.local";
  };
  
  # Test that PostgreSQL provider is configured
  testPostgreSQLProvider = {
    expr = evaluatedConfig.config.psf.providers ? postgresql;
    expected = true;
  };
  
  # Test that test-app service is configured
  testAppService = {
    expr = evaluatedConfig.config.psf.services ? test-app;
    expected = true;
  };
}