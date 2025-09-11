# Azure Firewall Rules as Code using Bicep, Powershell and DevOps

This fork is built upon the great work on of Will Moselhy - please check out his [GitHub repo](https://github.com/WillyMoselhy/AzureFirewallPolicyExportImport) and Justin Mendon - (https://github.com/mendondev/AzureFirewallRulesAsCode)

## Using the scripts

1. Export the rules from the Azure Firewall Policy using the `Export-AzFirewallPolicyRules.ps1` script. This will create a CSV file with the rules.
2. Edit the CSV file to make the changes you want.
3. Import the rules back into the Azure Firewall Policy using the `Invoke-DeployFirewallPolicyRules.ps1` script. This will import the updated CSV file and deploy it to the Azure Firewall Policy.

## Manual Example

```PowerShell
Connect-AzAccount

Export-AzureFirewallPolicyRules.ps1 -FirewallPolicyId "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/MyResourceGroup/providers/Microsoft.Network/azureFirewalls/MyFirewall/azureFirewallPolicies/MyFirewallPolicy"
# The CSV file by default will be saved under .\src\FirewallPolicies.csv, edit it then run the following part

Invoke-DeployFirewallPolicyRules.ps1 -SubscriptionId "00000000-0000-0000-0000-000000000000" -ResourceGroupName "MyResourceGroup" -FirewallPolicyName "MyFirewallPolicy"
```

For steps on how to configure this within DevOps, please visit my blog.