{ lib, pkgs }:

let
  inherit (lib) mkOption types;
  
  # Utility functions for PSF framework
  
  # Generate unique IDs for contracts and providers
  generateId = prefix: name: timestamp:
    "${prefix}-${name}-${toString timestamp}";
  
  # Merge PSF configurations safely
  mergePSFConfigs = configs:
    lib.foldl' (acc: config:
      acc // config // {
        providers = (acc.providers or {}) // (config.providers or {});
        services = (acc.services or {}) // (config.services or {});
      }
    ) {} configs;
  
  # Extract domain from URL
  extractDomain = url:
    let
      withoutProtocol = lib.removePrefix "https://" (lib.removePrefix "http://" url);
      withoutPath = lib.head (lib.splitString "/" withoutProtocol);
    in withoutPath;
  
  # Build service FQDN
  buildFQDN = subdomain: domain:
    if subdomain == "" || subdomain == null then domain
    else "${subdomain}.${domain}";
  
  # Check if a port is in use (placeholder for future implementation)
  isPortInUse = port: false; # TODO: Implement actual port checking
  
  # Find available port starting from a base port
  findAvailablePort = basePort:
    let
      checkPort = port:
        if isPortInUse port then checkPort (port + 1)
        else port;
    in checkPort basePort;
  
  # Validate domain name format
  isValidDomain = domain:
    let
      domainRegex = "^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$";
    in builtins.match domainRegex domain != null;
  
  # Generate backup filename with timestamp
  generateBackupFilename = serviceName: extension:
    "${serviceName}-${builtins.toString (builtins.currentTime)}.${extension}";
  
  # Convert size string to bytes (e.g., "1GB" -> 1073741824)
  sizeStringToBytes = sizeStr:
    let
      matches = builtins.match "([0-9]+)([KMGT]?B?)" (lib.toUpper sizeStr);
      number = lib.toInt (lib.head matches);
      unit = lib.last matches;
      multiplier = 
        if unit == "KB" || unit == "K" then 1024
        else if unit == "MB" || unit == "M" then 1024 * 1024
        else if unit == "GB" || unit == "G" then 1024 * 1024 * 1024
        else if unit == "TB" || unit == "T" then 1024 * 1024 * 1024 * 1024
        else 1;
    in number * multiplier;
  
  # Generate secure random string (placeholder - would need actual implementation)
  generateRandomString = length: 
    builtins.substring 0 length (builtins.hashString "sha256" (toString (builtins.currentTime)));
  
  # Check if file exists and is readable
  fileExists = path:
    builtins.pathExists path;
  
  # Safe attribute access with default
  safeGetAttr = attrPath: default: obj:
    lib.attrByPath attrPath default obj;

in {
  inherit generateId mergePSFConfigs extractDomain buildFQDN;
  inherit isPortInUse findAvailablePort isValidDomain;
  inherit generateBackupFilename sizeStringToBytes generateRandomString;
  inherit fileExists safeGetAttr;
}