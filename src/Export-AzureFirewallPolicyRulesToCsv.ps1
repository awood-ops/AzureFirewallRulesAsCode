# Export-AzFirewallPolicyRulesToCsv.ps1
# -------------------------------------------------------------
# Exports Azure Firewall Policy rules to a CSV file, summarizing
# rule collection groups, rule collections, and individual rules.
# Resource IDs for IP groups are trimmed to just the group name.
#
# Parameters:
#   -FirewallPolicyId: Resource ID of the Azure Firewall Policy
#   -OutputCSVPath: Path to output CSV file
#
# Usage Example:
#   .\Export-AzFirewallPolicyRulesToCsv.ps1 -FirewallPolicyId '/subscriptions/xxx/resourceGroups/xxx/providers/Microsoft.Network/firewallPolicies/xxx' -OutputCSVPath '.\export\FirewallRules.csv'
# -------------------------------------------------------------

param (
    [Parameter(Mandatory = $true)]
    $FirewallPolicyId,

    [Parameter(Mandatory = $false)]
    $OutputCSVPath = '.\csv\FirewallRules.csv'
)

# Get the firewall policy object
$fwp = Get-AzFirewallPolicy -ResourceId $FirewallPolicyId

# Get all rule collection groups for the policy
$ruleCollectionGroups = $fwp.RuleCollectionGroups.Id | ForEach-Object { Get-AzFirewallPolicyRuleCollectionGroup -Name (($_ -split "/")[-1])-AzureFirewallPolicy $fwp }

# Build a summary of all rules
$policySummary = foreach ($group in $ruleCollectionGroups) {
    foreach ($ruleCollection in $group.Properties.RuleCollection) {
        foreach ($rule in $ruleCollection.Rules) {
            # Determine source type
            $rulePossibleSourceTypes = @( 'SourceAddresses', 'SourceIpGroups' )
            $ruleSourceType = $rulePossibleSourceTypes | ForEach-Object { if ($rule.$_) { $_ } }

            # Determine destination type and protocols
            switch ($rule.RuleType) {
                "ApplicationRule" {
                    $ruleProtocols = ($rule.protocols | ForEach-Object { "{0}:{1}" -f $_.ProtocolType, $_.Port }) -join ","
                    $rulePossibleDestinations = @( 'TargetFqdns', 'FqdnTags', 'WebCategories', 'TargetUrls' )
                }
                "NetworkRule" {
                    $ruleProtocols = $rule.Protocols -join ","
                    $rulePossibleDestinations = @( 'DestinationAddresses', 'DestinationFqdns', 'DestinationIpGroups')
                }
            }
            $ruleDestinationType = $rulePossibleDestinations | ForEach-Object { if ($rule.$_) { $_ } }

            # Trim resource ID for SourceIpGroups to just the group name
            $sourceValue = $rule.$ruleSourceType
            if ($ruleSourceType -eq 'SourceIpGroups' -and $sourceValue) {
                $sourceValue = @($sourceValue) | ForEach-Object {
                    if ($_ -match "/ipGroups/([^/]+)$") { $matches[1] } else { $_ }
                }
            }
            # Trim resource ID for DestinationIpGroups to just the group name
            $destinationValue = $rule.$ruleDestinationType
            if ($ruleDestinationType -eq 'DestinationIpGroups' -and $destinationValue) {
                $destinationValue = @($destinationValue) | ForEach-Object {
                    if ($_ -match "/ipGroups/([^/]+)$") { $matches[1] } else { $_ }
                }
            }
            [PSCustomObject]@{
                RuleCollectionGroup         = $group.Name
                RuleCollectionGroupPriority = $group.Properties.Priority
                RuleCollectionName          = $ruleCollection.Name
                RuleCollectionPriority      = $ruleCollection.Priority
                RuleCollectionAction        = $ruleCollection.Action.Type
                RuleCollectionType          = $ruleCollection.RuleCollectionType
                RuleType                    = $rule.RuleType
                RuleName                    = $rule.Name
                SourceType                  = $ruleSourceType
                Source                      = $sourceValue -join ","
                Protocols                   = $ruleProtocols
                TerminateTLS                = $rule.TerminateTLS
                DestinationPorts            = $rule.DestinationPorts -join ","
                DestinationType             = $ruleDestinationType
                Destination                 = $destinationValue -join ","
            }
        }
    }
}

# Export the summary to CSV
$policySummary | Export-Csv -Path $OutputCSVPath