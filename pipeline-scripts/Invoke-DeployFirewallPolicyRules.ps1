# Invoke-DeployFirewallPolicyRules.ps1
# -------------------------------------------------------------
# Deploys Azure Firewall Policy rule collection groups from a CSV file.
# Extracts deployment parameters from a Bicep parameter file, expands IP group names
# to full resource IDs, supports custom resource groups per IP group, and deploys each
# rule collection group using a Bicep template.
#
# Parameters:
#   -SubscriptionId: Azure subscription ID (default from environment)
#   -ResourceGroupName: Resource group for deployment (extracted from parameter file)
#   -FirewallPolicyName: Name of the Azure Firewall Policy (extracted from parameter file)
#   -PolicyCsvPath: Path to the CSV file containing rules
#   -TemplateParameterFile: Path to the Bicep parameter file
#   -DefaultIpGroupResourceGroup: Default resource group for IP groups (extracted from parameter file)
#
# Usage Example:
#   .\Invoke-DeployFirewallPolicyRules.ps1 -SubscriptionId 'xxx' -PolicyCsvPath './config/custom-parameters/FirewallRules.csv' -TemplateParameterFile 'config/custom-parameters/main.bicepparam'
# -------------------------------------------------------------

param(
    [Parameter(Mandatory = $false)]
    $SubscriptionId = "$($env:SUBSCRIPTION_ID)",

    # These are extracted from the Bicep param file unless explicitly provided
    [Parameter(Mandatory = $false)]
    $ResourceGroupName,

    [Parameter(Mandatory = $false)]
    $FirewallPolicyName,

    [Parameter(Mandatory = $false)]
    $DefaultIpGroupResourceGroup,

    [Parameter(Mandatory = $false)]
    $PolicyCsvPath = '.\config\parameters\FirewallRules\FirewallRules-NoIPG.csv',

    [Parameter()]
    [String]$TemplateParameterFile = ".\config\parameters\HubNetworking\main.bicepparam"
)

# Validate required files exist
if (!(Test-Path $PolicyCsvPath)) {
    Write-Error "CSV file not found: $PolicyCsvPath"
    exit 1
}
if (!(Test-Path $TemplateParameterFile)) {
    Write-Error "Bicep parameter file not found: $TemplateParameterFile"
    exit 1
}

# Extract the resource group name, firewall policy name, and default IP group resource group from the parameter file
Write-Host "Reading resource group name from parameter file..."
$parameters = (bicep build-params $TemplateParameterFile --stdout | ConvertFrom-Json).parametersJson | ConvertFrom-Json

# If parameters are not provided, extract from the parameter file
if (-not $ResourceGroupName) {
    $ResourceGroupName = $parameters.parameters.parResourceNames.value.resourceGroup
}
if (-not $FirewallPolicyName) {
    $FirewallPolicyName = $parameters.parameters.parResourceNames.value.firewallPolicy
}
if (-not $DefaultIpGroupResourceGroup) {
    $DefaultIpGroupResourceGroup = $parameters.parameters.parResourceNames.value.ipGroupsResourceGroup
}

Write-Host "Resource group name extracted: $ResourceGroupName"
Write-Host "Firewall policy name extracted: $FirewallPolicyName"
Write-Host "Default IP group resource group extracted: $DefaultIpGroupResourceGroup"

# Function to parse CSV and build rule collection group objects for deployment
function Get-RuleCollectionGroupParamsFromCsv {
    param (
        [string]$CsvPath,
        [string]$FirewallPolicyName
    )
    $csv = Import-Csv -Path $CsvPath
    $ruleCollectionGroupNames = $csv.RuleCollectionGroup | Sort-Object | Get-Unique

    foreach ($ruleCollectionGroup in $ruleCollectionGroupNames) {
        $groupPriority = [int]($csv | Where-Object { $_.RuleCollectionGroup -eq $ruleCollectionGroup } | Select-Object -First 1).RuleCollectionGroupPriority
        $ruleCollectionNames = ($csv | Where-Object { $_.RuleCollectionGroup -eq $ruleCollectionGroup } | Group-Object -Property RuleCollectionName).Name

        $ruleCollections = foreach ($ruleCollection in $ruleCollectionNames) {
            $ruleType = ($csv | Where-Object { $_.RuleCollectionGroup -eq $ruleCollectionGroup -and $_.RuleCollectionName -eq $ruleCollection } | Select-Object -First 1).RuleType
            $rulesRaw = foreach ($rule in ($csv | Where-Object { $_.RuleCollectionGroup -eq $ruleCollectionGroup -and $_.RuleCollectionName -eq $ruleCollection -and -Not [string]::IsNullOrEmpty($_.RuleName)})) {
                $ruleObject = @{
                    name     = $rule.RuleName
                    ruleType = $rule.RuleType
                }
                if ($rule.RuleType -eq 'ApplicationRule') {
                    # Map SourceType to correct property, build full resource ID for IP groups, support custom resource group per IP group
                    if ($rule.SourceType -eq 'SourceIpGroups' -and $rule.Source) {
                        # Strip full resource ID to just the group name if needed
                        $ipGroupsRaw = $rule.Source -split ","
                        $ipGroups = @()
                        foreach ($item in $ipGroupsRaw) {
                            $ipGroupStr = [string]$item
                            if ($ipGroupStr -match "/ipGroups/([^/]+)$") {
                                $ipGroups += $matches[1]
                            } else {
                                $ipGroups += $ipGroupStr.Trim()
                            }
                        }
                        $ipGroupResourceGroups = $null
                        if ($rule.PSObject.Properties['SourceIpGroupResourceGroup']) {
                            $ipGroupResourceGroups = $rule.SourceIpGroupResourceGroup -split ","
                        }
                        $ruleObject['sourceIpGroups'] = @()
                        for ($i = 0; $i -lt $ipGroups.Count; $i++) {
                            $ipGroupName = $ipGroups[$i].Trim()
                            if ($ipGroupResourceGroups -and $ipGroupResourceGroups.Count -ge ($i+1)) {
                                $ipGroupRg = $ipGroupResourceGroups[$i].Trim()
                            } else {
                                $ipGroupRg = $DefaultIpGroupResourceGroup
                            }
                            $ipGroupId = "/subscriptions/$SubscriptionId/resourceGroups/$ipGroupRg/providers/Microsoft.Network/ipGroups/$ipGroupName"
                            $ruleObject['sourceIpGroups'] += $ipGroupId
                        }
                    } elseif ($rule.SourceType -eq 'SourceAddresses' -and $rule.Source) {
                        $ruleObject['sourceAddresses'] = $rule.Source -split ","
                    } elseif ($rule.Source) {
                        $ruleObject['sourceAddresses'] = $rule.Source -split ","
                    }
                    # Add DestinationIpGroups support for ApplicationRule
                    if ($rule.DestinationType -eq 'DestinationIpGroups' -and $rule.Destination) {
                        $destIpGroupsRaw = $rule.Destination -split ","
                        $destIpGroups = @()
                        foreach ($item in $destIpGroupsRaw) {
                            $ipGroupStr = [string]$item
                            if ($ipGroupStr -match "/ipGroups/([^/]+)$") {
                                $destIpGroups += $matches[1]
                            } else {
                                $destIpGroups += $ipGroupStr.Trim()
                            }
                        }
                        $destIpGroupResourceGroups = $null
                        if ($rule.PSObject.Properties['DestinationIpGroupResourceGroup']) {
                            $destIpGroupResourceGroups = $rule.DestinationIpGroupResourceGroup -split ","
                        }
                        $ruleObject['destinationIpGroups'] = @()
                        for ($i = 0; $i -lt $destIpGroups.Count; $i++) {
                            $ipGroupName = $destIpGroups[$i].Trim()
                            if ($destIpGroupResourceGroups -and $destIpGroupResourceGroups.Count -ge ($i+1)) {
                                $ipGroupRg = $destIpGroupResourceGroups[$i].Trim()
                            } else {
                                $ipGroupRg = $DefaultIpGroupResourceGroup
                            }
                            $ipGroupId = "/subscriptions/$SubscriptionId/resourceGroups/$ipGroupRg/providers/Microsoft.Network/ipGroups/$ipGroupName"
                            $ruleObject['destinationIpGroups'] += $ipGroupId
                        }
                    } else {
                        if ($rule.DestinationType -eq 'TargetFqdns') {
                            $ruleObject['targetFqdns'] = $rule.Destination -split ","
                        }
                    }
                    $ruleObject['protocols'] = @(
                        foreach ($proto in $rule.Protocols -split ",") {
                            @{
                                protocolType = $proto.Split(":")[0]
                                port         = $proto.Split(":")[1]
                            }
                        }
                    )
                }
                elseif ($rule.RuleType -eq 'NetworkRule') {
                    # Expand IP group names to full resource IDs if SourceType is SourceIpGroups
                    if ($rule.SourceType -eq 'SourceIpGroups' -and $rule.Source) {
                        $ipGroupsRaw = $rule.Source -split ","
                        $ipGroups = @()
                        foreach ($item in $ipGroupsRaw) {
                            $ipGroupStr = [string]$item
                            if ($ipGroupStr -match "/ipGroups/([^/]+)$") {
                                $ipGroups += $matches[1]
                            } else {
                                $ipGroups += $ipGroupStr.Trim()
                            }
                        }
                        $ipGroupResourceGroups = $null
                        if ($rule.PSObject.Properties['SourceIpGroupResourceGroup']) {
                            $ipGroupResourceGroups = $rule.SourceIpGroupResourceGroup -split ","
                        }
                        $ruleObject['sourceIpGroups'] = @()
                        for ($i = 0; $i -lt $ipGroups.Count; $i++) {
                            $ipGroupName = $ipGroups[$i].Trim()
                            if ($ipGroupResourceGroups -and $ipGroupResourceGroups.Count -ge ($i+1)) {
                                $ipGroupRg = $ipGroupResourceGroups[$i].Trim()
                            } else {
                                $ipGroupRg = $DefaultIpGroupResourceGroup
                            }
                            $ipGroupId = "/subscriptions/$SubscriptionId/resourceGroups/$ipGroupRg/providers/Microsoft.Network/ipGroups/$ipGroupName"
                            $ruleObject['sourceIpGroups'] += $ipGroupId
                        }
                    } else {
                        $ruleObject['sourceAddresses'] = $rule.Source -split ","
                    }
                    if ($rule.DestinationType -eq 'DestinationIpGroups' -and $rule.Destination) {
                        $destIpGroupsRaw = $rule.Destination -split ","
                        $destIpGroups = @()
                        foreach ($item in $destIpGroupsRaw) {
                            $ipGroupStr = [string]$item
                            if ($ipGroupStr -match "/ipGroups/([^/]+)$") {
                                $destIpGroups += $matches[1]
                            } else {
                                $destIpGroups += $ipGroupStr.Trim()
                            }
                        }
                        $destIpGroupResourceGroups = $null
                        if ($rule.PSObject.Properties['DestinationIpGroupResourceGroup']) {
                            $destIpGroupResourceGroups = $rule.DestinationIpGroupResourceGroup -split ","
                        }
                        $ruleObject['destinationIpGroups'] = @()
                        for ($i = 0; $i -lt $destIpGroups.Count; $i++) {
                            $ipGroupName = $destIpGroups[$i].Trim()
                            if ($destIpGroupResourceGroups -and $destIpGroupResourceGroups.Count -ge ($i+1)) {
                                $ipGroupRg = $destIpGroupResourceGroups[$i].Trim()
                            } else {
                                $ipGroupRg = $DefaultIpGroupResourceGroup
                            }
                            $ipGroupId = "/subscriptions/$SubscriptionId/resourceGroups/$ipGroupRg/providers/Microsoft.Network/ipGroups/$ipGroupName"
                            $ruleObject['destinationIpGroups'] += $ipGroupId
                        }
                    } else {
                        # ...existing code for other destination types...
                        if ($rule.DestinationType -eq 'DestinationAddresses') {
                            $ruleObject['destinationAddresses'] = $rule.Destination -split ","
                        } elseif ($rule.DestinationType -eq 'DestinationFqdns') {
                            $ruleObject['destinationFqdns'] = $rule.Destination -split ","
                        }
                    }
                    $ruleObject['ipProtocols'] = $rule.Protocols -split ","
                    $ruleObject['destinationPorts'] = $rule.DestinationPorts -split ","
                }
                $ruleObject
            }
            # Ensure rules is always an array
            $rules = @()
            if ($rulesRaw -is [System.Collections.IEnumerable]) {
                foreach ($item in $rulesRaw) { $rules += ,$item }
            } elseif ($rulesRaw) {
                $rules = @($rulesRaw)
            }
            @{
                name               = $ruleCollection
                priority           = [int]($csv | Where-Object { $_.RuleCollectionGroup -eq $ruleCollectionGroup -and $_.RuleCollectionName -eq $ruleCollection } | Select-Object -First 1).RuleCollectionPriority
                ruleCollectionType = ($csv | Where-Object { $_.RuleCollectionGroup -eq $ruleCollectionGroup -and $_.RuleCollectionName -eq $ruleCollection } | Select-Object -First 1).RuleCollectionType
                action             = @{
                    type = ($csv | Where-Object { $_.RuleCollectionGroup -eq $ruleCollectionGroup -and $_.RuleCollectionName -eq $ruleCollection } | Select-Object -First 1).RuleCollectionAction
                }
                rules              = $rules
            }
        }
        # Ensure ruleCollections is always an array
        $ruleCollectionsArray = @()
        if ($ruleCollections -is [System.Collections.IEnumerable]) {
            foreach ($item in $ruleCollections) { $ruleCollectionsArray += ,$item }
        } elseif ($ruleCollections) {
            $ruleCollectionsArray = @($ruleCollections)
        }

        [PSCustomObject]@{
            firewallPolicyName = $FirewallPolicyName
            name              = $ruleCollectionGroup
            priority          = $groupPriority
            ruleCollections   = $ruleCollectionsArray
        }
    }
}

# Set the context to the target subscription
$null = Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop

# Parse the CSV and build deployment objects
$groups = Get-RuleCollectionGroupParamsFromCsv -CsvPath $PolicyCsvPath -FirewallPolicyName $FirewallPolicyName

# Deploy each rule collection group using the Bicep template
foreach ($group in $groups) {
    $timeStamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $deployParams = @{
        ResourceGroupName = $ResourceGroupName
        Name              = "FWRules-$($group.name)-$timeStamp"
        TemplateFile      = './modules/Firewall/modules/fwpolicyrulecollectiongroup.bicep'
        TemplateParameterObject = @{
            firewallPolicyName = $group.firewallPolicyName
            name              = $group.name
            priority          = $group.priority
            ruleCollections   = $group.ruleCollections
        }
    }
    New-AzResourceGroupDeployment @deployParams -Verbose
}