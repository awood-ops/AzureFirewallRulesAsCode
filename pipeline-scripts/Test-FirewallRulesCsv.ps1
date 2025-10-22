# Test-FirewallRulesCsv.ps1
# -------------------------------------------------------------
# Validates Azure Firewall Policy rules CSV file for common issues:
#   - CSV format and required columns
#   - Priority conflicts within rule collection groups
#   - Valid CIDR notation for IP addresses
#   - Valid FQDN formats
#   - Valid port numbers and protocols
#   - Rule name uniqueness within collections
#   - Valid enum values for rule types and actions
#
# Parameters:
#   -PolicyCsvPath: Path to the CSV file containing rules
#   -Strict: Enable strict validation (fails on warnings)
#
# Usage Example:
#   .\Test-FirewallRulesCsv.ps1 -PolicyCsvPath './config/parameters/FirewallRules/FirewallRules.csv'
#   .\Test-FirewallRulesCsv.ps1 -PolicyCsvPath './config/parameters/FirewallRules/FirewallRules.csv' -Strict
# -------------------------------------------------------------

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$PolicyCsvPath = '.\config\parameters\FirewallRules\FirewallRules.csv',

    [Parameter(Mandatory = $false)]
    [switch]$Strict
)

# Validation counters
$script:ErrorCount = 0
$script:WarningCount = 0
$script:InfoCount = 0

# Helper function to write colored output
function Write-ValidationError {
    param([string]$Message, [int]$Line = 0)
    $script:ErrorCount++
    if ($Line -gt 0) {
        Write-Host "  [ERROR] Line $Line`: $Message" -ForegroundColor Red
    } else {
        Write-Host "  [ERROR] $Message" -ForegroundColor Red
    }
}

function Write-ValidationWarning {
    param([string]$Message, [int]$Line = 0)
    $script:WarningCount++
    if ($Line -gt 0) {
        Write-Host "  [WARN]  Line $Line`: $Message" -ForegroundColor Yellow
    } else {
        Write-Host "  [WARN]  $Message" -ForegroundColor Yellow
    }
}

function Write-ValidationInfo {
    param([string]$Message)
    $script:InfoCount++
    Write-Host "  [INFO]  $Message" -ForegroundColor Cyan
}

function Write-ValidationSuccess {
    param([string]$Message)
    Write-Host "  [OK]    $Message" -ForegroundColor Green
}

# Validate CIDR notation
function Test-CidrNotation {
    param([string]$Cidr)
    
    if ([string]::IsNullOrWhiteSpace($Cidr)) {
        return $false
    }
    
    # Check for CIDR format (e.g., 10.0.0.0/24)
    if ($Cidr -match '^(\d{1,3}\.){3}\d{1,3}/\d{1,2}$') {
        $parts = $Cidr -split '/'
        $ip = $parts[0]
        $prefix = [int]$parts[1]
        
        # Validate IP octets
        $octets = $ip -split '\.'
        foreach ($octet in $octets) {
            if ([int]$octet -lt 0 -or [int]$octet -gt 255) {
                return $false
            }
        }
        
        # Validate prefix length
        if ($prefix -lt 0 -or $prefix -gt 32) {
            return $false
        }
        
        return $true
    }
    
    # Check for single IP address (e.g., 10.0.0.1)
    if ($Cidr -match '^(\d{1,3}\.){3}\d{1,3}$') {
        $octets = $Cidr -split '\.'
        foreach ($octet in $octets) {
            if ([int]$octet -lt 0 -or [int]$octet -gt 255) {
                return $false
            }
        }
        return $true
    }
    
    return $false
}

# Validate FQDN format
function Test-FqdnFormat {
    param([string]$Fqdn)
    
    if ([string]::IsNullOrWhiteSpace($Fqdn)) {
        return $false
    }
    
    # Allow wildcards at the start
    if ($Fqdn -match '^\*\.') {
        $Fqdn = $Fqdn.Substring(2)
    }
    
    # Basic FQDN validation (alphanumeric, hyphens, dots)
    if ($Fqdn -match '^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$') {
        return $true
    }
    
    return $false
}

# Validate port number
function Test-PortNumber {
    param([string]$Port)
    
    if ([string]::IsNullOrWhiteSpace($Port)) {
        return $false
    }
    
    # Check if it's a valid port number (1-65535) or range
    if ($Port -match '^\d+$') {
        $portNum = [int]$Port
        return ($portNum -ge 1 -and $portNum -le 65535)
    }
    
    # Check if it's a port range (e.g., 80-443)
    if ($Port -match '^\d+-\d+$') {
        $parts = $Port -split '-'
        $start = [int]$parts[0]
        $end = [int]$parts[1]
        return ($start -ge 1 -and $start -le 65535 -and $end -ge 1 -and $end -le 65535 -and $start -lt $end)
    }
    
    return $false
}

# Main validation logic
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Azure Firewall Rules CSV Validator" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Check if file exists
if (!(Test-Path $PolicyCsvPath)) {
    Write-ValidationError "CSV file not found: $PolicyCsvPath"
    exit 1
}

Write-Host "Validating: $PolicyCsvPath`n" -ForegroundColor White

# Validate CSV formatting (check for malformed quotes)
Write-Host "Checking CSV formatting..." -ForegroundColor White
$rawLines = Get-Content -Path $PolicyCsvPath
$lineNum = 1
$formatErrors = 0
foreach ($line in $rawLines) {
    # Skip comment lines and empty lines
    if ($line -match '^\s*#' -or [string]::IsNullOrWhiteSpace($line)) {
        $lineNum++
        continue
    }
    
    # Check for unbalanced quotes on the line (most reliable check)
    $quoteCount = ($line.ToCharArray() | Where-Object { $_ -eq '"' }).Count
    if ($quoteCount % 2 -ne 0) {
        Write-ValidationError "Malformed CSV - unbalanced quotes detected" -Line $lineNum
        $formatErrors++
    }
    
    # Check for consecutive quotes that are NOT at field boundaries
    # Valid: "","" (two empty fields) or "word"," or ","word"
    # Invalid: "word""word" (missing comma between fields)
    if ($line -match '"[^"]+""[^",]') {
        Write-ValidationError "Malformed CSV - missing comma between fields (consecutive quotes detected)" -Line $lineNum
        $formatErrors++
    }
    
    # Check for common malformed patterns
    # Pattern 1: ,"word or ,word" but NOT within a quoted field
    # Split by valid quoted fields first to avoid false positives
    $testLine = $line
    # Remove all properly quoted fields temporarily
    $testLine = $testLine -replace '"[^"]*"', '""'
    
    # Now check for orphaned quotes after comma (missing opening quote)
    if ($testLine -match ',\s*([A-Za-z0-9_\-]+)"') {
        Write-ValidationError "Malformed CSV field - missing opening quote before '$($matches[1])'" -Line $lineNum
        $formatErrors++
    }
    
    # Check for orphaned quotes before comma (missing closing quote)
    if ($testLine -match '"([A-Za-z0-9_\-]+)\s*,') {
        Write-ValidationError "Malformed CSV field - missing closing quote after '$($matches[1])'" -Line $lineNum
        $formatErrors++
    }
    
    $lineNum++
}

# Exit early if CSV formatting errors found
if ($formatErrors -gt 0) {
    Write-Host "`nCSV formatting errors detected. Fix these issues before proceeding." -ForegroundColor Red
    Write-Host "CSV parsing will produce incorrect results with malformed fields.`n" -ForegroundColor Yellow
    exit 1
}

Write-ValidationSuccess "CSV formatting is valid"

# Import CSV
try {
    $csv = Import-Csv -Path $PolicyCsvPath -ErrorAction Stop
} catch {
    Write-ValidationError "Failed to parse CSV file: $_"
    exit 1
}

if ($csv.Count -eq 0) {
    Write-ValidationError "CSV file is empty"
    exit 1
}

Write-ValidationSuccess "CSV file loaded successfully ($($csv.Count) rows)"

# Required columns
$requiredColumns = @(
    'RuleCollectionGroup',
    'RuleCollectionGroupPriority',
    'RuleCollectionName',
    'RuleCollectionPriority',
    'RuleCollectionAction',
    'RuleCollectionType',
    'RuleType',
    'RuleName'
)

Write-Host "`n[1] Validating CSV Structure..." -ForegroundColor Cyan
$actualColumns = $csv[0].PSObject.Properties.Name
$missingColumns = $requiredColumns | Where-Object { $_ -notin $actualColumns }

if ($missingColumns) {
    foreach ($col in $missingColumns) {
        Write-ValidationError "Missing required column: $col"
    }
} else {
    Write-ValidationSuccess "All required columns present"
}

# Validate enum values
Write-Host "`n[2] Validating Enum Values..." -ForegroundColor Cyan
$validRuleTypes = @('ApplicationRule', 'NetworkRule', 'NatRule')
$validActions = @('Allow', 'Deny')
$validCollectionTypes = @('FirewallPolicyFilterRuleCollection', 'FirewallPolicyNatRuleCollection')
$validSourceTypes = @('SourceAddresses', 'SourceIpGroups')
$validDestinationTypes = @('TargetFqdns', 'DestinationAddresses', 'DestinationFqdns', 'DestinationIpGroups')
$validProtocols = @('Http', 'Https', 'Mssql', 'TCP', 'UDP', 'ICMP', 'Any')

$lineNum = 2  # Start at 2 (accounting for header row)
foreach ($row in $csv) {
    if (-not [string]::IsNullOrEmpty($row.RuleName)) {
        # Validate RuleType
        if ($row.RuleType -and $row.RuleType -notin $validRuleTypes) {
            Write-ValidationError "Invalid RuleType: '$($row.RuleType)'. Must be one of: $($validRuleTypes -join ', ')" -Line $lineNum
        }
        
        # Validate RuleCollectionAction
        if ($row.RuleCollectionAction -and $row.RuleCollectionAction -notin $validActions) {
            Write-ValidationError "Invalid RuleCollectionAction: '$($row.RuleCollectionAction)'. Must be one of: $($validActions -join ', ')" -Line $lineNum
        }
        
        # Validate RuleCollectionType
        if ($row.RuleCollectionType -and $row.RuleCollectionType -notin $validCollectionTypes) {
            Write-ValidationError "Invalid RuleCollectionType: '$($row.RuleCollectionType)'. Must be one of: $($validCollectionTypes -join ', ')" -Line $lineNum
        }
        
        # Validate SourceType
        if ($row.SourceType -and $row.SourceType -notin $validSourceTypes) {
            Write-ValidationError "Invalid SourceType: '$($row.SourceType)'. Must be one of: $($validSourceTypes -join ', ')" -Line $lineNum
        }
        
        # Validate DestinationType
        if ($row.DestinationType -and $row.DestinationType -notin $validDestinationTypes) {
            Write-ValidationError "Invalid DestinationType: '$($row.DestinationType)'. Must be one of: $($validDestinationTypes -join ', ')" -Line $lineNum
        }
    }
    $lineNum++
}

if ($script:ErrorCount -eq 0) {
    Write-ValidationSuccess "All enum values are valid"
}

# Check for priority conflicts
Write-Host "`n[3] Checking Priority Conflicts..." -ForegroundColor Cyan
$groups = $csv | Group-Object -Property RuleCollectionGroup

foreach ($group in $groups) {
    $groupName = $group.Name
    $collections = $group.Group | Group-Object -Property RuleCollectionName
    
    # Check RuleCollectionGroup priority consistency
    $groupPriorities = $group.Group.RuleCollectionGroupPriority | Select-Object -Unique
    if ($groupPriorities.Count -gt 1) {
        Write-ValidationError "RuleCollectionGroup '$groupName' has inconsistent priorities: $($groupPriorities -join ', ')"
    }
    
    # Check for duplicate rule collection priorities within the group
    $collectionPriorities = @{}
    foreach ($collection in $collections) {
        $collectionName = $collection.Name
        $priority = ($collection.Group | Select-Object -First 1).RuleCollectionPriority
        
        if ($collectionPriorities.ContainsKey($priority)) {
            Write-ValidationError "Priority conflict in group '$groupName': Collections '$($collectionPriorities[$priority])' and '$collectionName' both have priority $priority"
        } else {
            $collectionPriorities[$priority] = $collectionName
        }
        
        # Check for duplicate rule names within the collection
        $ruleNames = @{}
        foreach ($rule in $collection.Group) {
            if (-not [string]::IsNullOrEmpty($rule.RuleName)) {
                if ($ruleNames.ContainsKey($rule.RuleName)) {
                    Write-ValidationError "Duplicate rule name '$($rule.RuleName)' in collection '$collectionName'"
                } else {
                    $ruleNames[$rule.RuleName] = $true
                }
            }
        }
    }
}

if ($script:ErrorCount -eq 0) {
    Write-ValidationSuccess "No priority conflicts detected"
}

# Validate IP addresses and CIDR notation
Write-Host "`n[4] Validating IP Addresses and CIDR Notation..." -ForegroundColor Cyan
$lineNum = 2
foreach ($row in $csv) {
    if (-not [string]::IsNullOrEmpty($row.RuleName)) {
        # Validate Source addresses
        if ($row.SourceType -eq 'SourceAddresses' -and $row.Source) {
            $addresses = $row.Source -split ','
            foreach ($addr in $addresses) {
                $addr = $addr.Trim()
                if ($addr -ne '*' -and -not (Test-CidrNotation $addr)) {
                    Write-ValidationError "Invalid source IP/CIDR in rule '$($row.RuleName)': '$addr'" -Line $lineNum
                }
            }
        }
        
        # Validate Destination addresses
        if ($row.DestinationType -eq 'DestinationAddresses' -and $row.Destination) {
            $addresses = $row.Destination -split ','
            foreach ($addr in $addresses) {
                $addr = $addr.Trim()
                if ($addr -ne '*' -and -not (Test-CidrNotation $addr)) {
                    Write-ValidationError "Invalid destination IP/CIDR in rule '$($row.RuleName)': '$addr'" -Line $lineNum
                }
            }
        }
    }
    $lineNum++
}

if ($script:ErrorCount -eq 0) {
    Write-ValidationSuccess "All IP addresses and CIDR notations are valid"
}

# Validate FQDNs
Write-Host "`n[5] Validating FQDNs..." -ForegroundColor Cyan
$lineNum = 2
foreach ($row in $csv) {
    if (-not [string]::IsNullOrEmpty($row.RuleName)) {
        # Validate TargetFqdns
        if ($row.DestinationType -eq 'TargetFqdns' -and $row.Destination) {
            $fqdns = $row.Destination -split ','
            foreach ($fqdn in $fqdns) {
                $fqdn = $fqdn.Trim()
                if (-not (Test-FqdnFormat $fqdn)) {
                    Write-ValidationError "Invalid FQDN in rule '$($row.RuleName)': '$fqdn'" -Line $lineNum
                }
            }
        }
        
        # Validate DestinationFqdns
        if ($row.DestinationType -eq 'DestinationFqdns' -and $row.Destination) {
            $fqdns = $row.Destination -split ','
            foreach ($fqdn in $fqdns) {
                $fqdn = $fqdn.Trim()
                if (-not (Test-FqdnFormat $fqdn)) {
                    Write-ValidationError "Invalid destination FQDN in rule '$($row.RuleName)': '$fqdn'" -Line $lineNum
                }
            }
        }
    }
    $lineNum++
}

if ($script:ErrorCount -eq 0) {
    Write-ValidationSuccess "All FQDNs are valid"
}

# Validate protocols and ports
Write-Host "`n[6] Validating Protocols and Ports..." -ForegroundColor Cyan
$lineNum = 2
foreach ($row in $csv) {
    if (-not [string]::IsNullOrEmpty($row.RuleName)) {
        # Validate protocols for ApplicationRule
        if ($row.RuleType -eq 'ApplicationRule' -and $row.Protocols) {
            $protocols = $row.Protocols -split ','
            foreach ($proto in $protocols) {
                $proto = $proto.Trim()
                if ($proto -match '^([^:]+):(\d+)$') {
                    $protoType = $matches[1]
                    $port = $matches[2]
                    
                    if ($protoType -notin $validProtocols) {
                        Write-ValidationError "Invalid protocol type in rule '$($row.RuleName)': '$protoType'" -Line $lineNum
                    }
                    
                    if (-not (Test-PortNumber $port)) {
                        Write-ValidationError "Invalid port number in rule '$($row.RuleName)': '$port'" -Line $lineNum
                    }
                } else {
                    Write-ValidationError "Invalid protocol format in rule '$($row.RuleName)': '$proto'. Expected format: 'Protocol:Port'" -Line $lineNum
                }
            }
        }
        
        # Validate protocols for NetworkRule
        if ($row.RuleType -eq 'NetworkRule' -and $row.Protocols) {
            $protocols = $row.Protocols -split ','
            foreach ($proto in $protocols) {
                $proto = $proto.Trim()
                if ($proto -notin $validProtocols) {
                    Write-ValidationError "Invalid protocol in rule '$($row.RuleName)': '$proto'. Must be one of: $($validProtocols -join ', ')" -Line $lineNum
                }
            }
        }
        
        # Validate destination ports for NetworkRule
        if ($row.RuleType -eq 'NetworkRule' -and $row.DestinationPorts) {
            $ports = $row.DestinationPorts -split ','
            foreach ($port in $ports) {
                $port = $port.Trim()
                if ($port -ne '*' -and -not (Test-PortNumber $port)) {
                    Write-ValidationError "Invalid destination port in rule '$($row.RuleName)': '$port'" -Line $lineNum
                }
            }
        }
    }
    $lineNum++
}

if ($script:ErrorCount -eq 0) {
    Write-ValidationSuccess "All protocols and ports are valid"
}

# Validate rule completeness
Write-Host "`n[7] Validating Rule Completeness..." -ForegroundColor Cyan
$lineNum = 2
foreach ($row in $csv) {
    if (-not [string]::IsNullOrEmpty($row.RuleName)) {
        # Check for required fields
        if ([string]::IsNullOrWhiteSpace($row.Source)) {
            Write-ValidationError "Rule '$($row.RuleName)' is missing Source" -Line $lineNum
        }
        
        if ([string]::IsNullOrWhiteSpace($row.Destination) -and $row.RuleType -ne 'NatRule') {
            Write-ValidationWarning "Rule '$($row.RuleName)' is missing Destination" -Line $lineNum
        }
        
        if ($row.RuleType -eq 'ApplicationRule' -and [string]::IsNullOrWhiteSpace($row.Protocols)) {
            Write-ValidationError "ApplicationRule '$($row.RuleName)' is missing Protocols" -Line $lineNum
        }
        
        if ($row.RuleType -eq 'NetworkRule' -and [string]::IsNullOrWhiteSpace($row.Protocols)) {
            Write-ValidationError "NetworkRule '$($row.RuleName)' is missing Protocols" -Line $lineNum
        }
        
        if ($row.RuleType -eq 'NetworkRule' -and [string]::IsNullOrWhiteSpace($row.DestinationPorts)) {
            Write-ValidationError "NetworkRule '$($row.RuleName)' is missing DestinationPorts" -Line $lineNum
        }
    }
    $lineNum++
}

if ($script:ErrorCount -eq 0) {
    Write-ValidationSuccess "All rules have required fields"
}

# Priority range validation
Write-Host "`n[8] Validating Priority Ranges..." -ForegroundColor Cyan
$lineNum = 2
foreach ($row in $csv) {
    if (-not [string]::IsNullOrEmpty($row.RuleName)) {
        # RuleCollectionGroup priority must be 100-65000
        if ($row.RuleCollectionGroupPriority) {
            try {
                $priority = [int]$row.RuleCollectionGroupPriority
                if ($priority -lt 100 -or $priority -gt 65000) {
                    Write-ValidationError "RuleCollectionGroup priority must be between 100-65000. Found: $priority in '$($row.RuleCollectionGroup)'" -Line $lineNum
                }
            } catch {
                Write-ValidationError "RuleCollectionGroup priority is not a valid number: '$($row.RuleCollectionGroupPriority)' in '$($row.RuleCollectionGroup)'" -Line $lineNum
            }
        }
        
        # RuleCollection priority must be 100-65000
        if ($row.RuleCollectionPriority) {
            try {
                $priority = [int]$row.RuleCollectionPriority
                if ($priority -lt 100 -or $priority -gt 65000) {
                    Write-ValidationError "RuleCollection priority must be between 100-65000. Found: $priority in '$($row.RuleCollectionName)'" -Line $lineNum
                }
            } catch {
                Write-ValidationError "RuleCollection priority is not a valid number: '$($row.RuleCollectionPriority)' in '$($row.RuleCollectionName)'" -Line $lineNum
            }
        }
    }
    $lineNum++
}

if ($script:ErrorCount -eq 0) {
    Write-ValidationSuccess "All priorities are within valid range (100-65000)"
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Validation Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Errors:   $script:ErrorCount" -ForegroundColor $(if ($script:ErrorCount -eq 0) { 'Green' } else { 'Red' })
Write-Host "Warnings: $script:WarningCount" -ForegroundColor $(if ($script:WarningCount -eq 0) { 'Green' } else { 'Yellow' })
Write-Host "Info:     $script:InfoCount" -ForegroundColor Cyan

if ($script:ErrorCount -eq 0 -and ($script:WarningCount -eq 0 -or -not $Strict)) {
    Write-Host "`n✓ Validation PASSED" -ForegroundColor Green
    exit 0
} elseif ($script:ErrorCount -eq 0 -and $Strict) {
    Write-Host "`n⚠ Validation PASSED with warnings (Strict mode)" -ForegroundColor Yellow
    Write-Host "  Re-run without -Strict to ignore warnings" -ForegroundColor Gray
    exit 1
} else {
    Write-Host "`n✗ Validation FAILED" -ForegroundColor Red
    Write-Host "  Please fix the errors above and try again" -ForegroundColor Gray
    exit 1
}
