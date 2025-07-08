{ lib, pkgs }:

let
  inherit (lib) concatMap attrValues filter;
  
  # Validate a single contract resolution
  validateContractResolution = resolution:
    let
      requestErrors = if resolution.request == null 
        then ["Missing contract request"]
        else [];
        
      resultErrors = if resolution.result == null
        then ["Provider failed to generate result"] 
        else [];
        
      providerErrors = resolution.validation_errors or [];
      
    in requestErrors ++ resultErrors ++ providerErrors;
  
  # Validate all contract resolutions
  validateContracts = contractResolutions:
    let
      allErrors = concatMap validateContractResolution (attrValues contractResolutions);
      nonEmptyErrors = filter (error: error != "") allErrors;
    in nonEmptyErrors;
    
  # Validate provider configuration
  validateProviderConfig = provider: config:
    let
      schemaErrors = []; # TODO: Implement schema validation
      customErrors = provider.validate {} config;
    in schemaErrors ++ customErrors;
    
  # Build-time validation - called during nix evaluation
  buildTimeValidation = psf_config:
    let
      # Basic configuration validation
      basicErrors = lib.optionals (psf_config.domain == "") ["PSF domain must be configured"];
      
      # Check for circular dependencies
      circularDepErrors = []; # TODO: Implement circular dependency detection
      
      # Check for missing dependencies
      missingDepErrors = []; # TODO: Implement missing dependency detection
      
    in {
      errors = basicErrors ++ circularDepErrors ++ missingDepErrors;
      warnings = [];
    };

in {
  inherit validateContractResolution validateContracts;
  inherit validateProviderConfig buildTimeValidation;
  
  # Standard error message formatting
  formatError = service: contract: error: 
    "PSF Error in ${service}.${contract}: ${error}";
    
  formatWarning = service: contract: warning:
    "PSF Warning in ${service}.${contract}: ${warning}";
}