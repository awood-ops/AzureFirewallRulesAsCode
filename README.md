# Azure Firewall Rules as Code using Bicep, Powershell and DevOps

## Getting Started: Hub Networking & Log Analytics

A solid foundation for every Azure project begins with monitoring. As a first step, provision a Log Analytics workspace using the provided script:

- **Script:** `scripts/New-LogAnalyticsWorkspace.ps1`
- **Purpose:** Creates a resource group and a basic Log Analytics workspace

### Environment Variables

For nearly every Azure build, environment variables are managed via an `.env` file. This can be imported locally or by the Azure DevOps runner.

- **Default location:** `config/prd/.env`
- **Multi-environment:** To deploy to multiple environments, create a new folder and populate its `.env` file accordingly.

**Required variables:**
```properties
ENVIRONMENT_CODE=""
WORKLOAD_CODE=""
LOCATION=""
COMPANY_CODE=""
SUBSCRIPTION_ID=""
LOG_ANALYTICS_SUBSCRIPTION_ID=""
LOG_ANALYTICS_RESOURCE_GROUP_NAME=""
LOG_ANALYTICS_WORKSPACE_NAME=""
VNET_ADDRESS_PREFIX="10.0.0.0/20"
FIREWALL_PREMIUM_ENABLED=""
DIAGNOSTICS_ENABLED=""
```

- **Local setup:** Use `scripts/Set-EnvParams.ps1` to import variables locally (this will force VS Code to close and re-open).
- **DevOps setup:** The pipeline will import variables in the "Import Environment Variables from File" step.

### Deploying the Hub Network

Once your environment is configured, you can build a conceptual Hub Network (hub-and-spoke, not VWAN). Feel free to amend parameters as needed—this setup will get you started.

- **Deploy:** Run `pipeline-scripts/Deploy-Infrastructure.ps1` to deploy the Hub.
- **Modules:** The script uses Azure Verified Modules and Azure Deployment Stacks for robust infrastructure provisioning.

If you deploy with the defaults, your hub networking should look like this:

![Hub Networking Output](images\image.png)

## Pull Request Validation

This repository includes automated CSV validation that runs on pull requests to ensure firewall rules are properly formatted before deployment.

**Quick Setup:**
1. Create the pipeline from `.azuredevops/PR-Validation.yaml`
2. Configure a branch policy on `main` to require the validation build
3. Complete setup guide: [docs/PR-Validation-Setup.md](docs/PR-Validation-Setup.md)

**What's Validated:**
- CSV formatting (quotes, delimiters)
- Priority conflicts
- IP/CIDR notation
- FQDN formats
- Protocols and ports
- Rule completeness

**PR Workflow:**
```
Developer → Create Branch → Edit CSV → Commit & Push
                                           ↓
                                      Create PR → Validation Runs
                                           ↓
                                    ✓ Pass → Can Merge
                                    ✗ Fail → Must Fix Errors
```

## Script Workflow: Export, Edit, and Deploy Firewall Rules

1. **Export Rules**
   - Use `Export-AzFirewallPolicyRules.ps1` to export rules from your Azure Firewall Policy.
   - The script creates a CSV file containing all rules.

2. **Edit Rules**
   - Open the CSV file and make any required changes to your firewall rules.

3. **Deploy Updated Rules**
   - Use `Invoke-DeployFirewallPolicyRules.ps1` to import the updated CSV file and deploy changes to your Azure Firewall Policy.


## Using the scripts

1. Edit the CSV file to make the changes you want, the csv is located at config\parameters\FirewallRules
2. Import the rules back into the Azure Firewall Policy using the `Invoke-DeployFirewallPolicyRules.ps1` script. This will import the updated CSV file and deploy it to the Azure Firewall Policy.

## Manual Example

```PowerShell
Connect-AzAccount

.\pipeline-scripts\Invoke-DeployFirewallPolicyRules.ps1
```

The script above will extract the parameters required from the bicepparam file to deploy the rules, although the following can be overridden

```properties
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
```

## Azure DevOps Example

To use in Azure DevOps, clone the repository and setup the pipeline in the .azuredevops folder with the name Deploy-Firewall-Rules.yaml
Update the service connection, ensure the env file mentioned above is updated with the required fields and run deploy

---

## Credits

This fork is built upon the great work of:
- [Will Moselhy](https://github.com/WillyMoselhy/AzureFirewallPolicyExportImport)
- [Justin Mendon](https://github.com/mendondev/AzureFirewallRulesAsCode)

---