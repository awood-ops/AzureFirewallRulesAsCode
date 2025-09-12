
<##
        New-LogAnalyticsWorkspace.ps1

        This script automates the creation of a Log Analytics resource group and workspace in Azure.
        It prompts the user to confirm the current tenant and subscription before proceeding.

        Steps:
            1. Display the current tenant and subscription, and prompt for confirmation before deployment.
            2. Set the subscription context using the SubscriptionName variable.
            3. Create Log Analytics resource group in the selected subscription.
            4. Create Log Analytics workspace in the resource group.

        Parameters:
            -CompanyId: The company identifier used in resource naming (default: "zzz").
            -Location: The Azure region for resource deployment (default: "uksouth").
            -Environment: The environment code (default: "prd").
            -SubscriptionName: The subscription name to use for context (default: "Management").

        Usage:
            .\New-LogAnalyticsWorkspace.ps1 -CompanyId "abc" -Location "uksouth" -Environment "dev" -SubscriptionName "Management"
##>

param (
    [string]$CompanyId = "zzz",
    [string]$Location = "uksouth",
    [string]$Environment = "prd",
    [string]$SubscriptionName = "Management",
    [string]$ProjectCode = "logging"
)

if (-not $CompanyId -or -not $Location -or -not $Environment -or -not $SubscriptionName) {
    Write-Error "One or more required parameters are missing."
    exit 1
}


$locationshort = $Location.Substring(0,3).ToLower()
$namingconvention = "$CompanyId-$locationshort-$Environment-$ProjectCode"

Set-AzContext -Subscription $SubscriptionName

# Step 1: Prompt for current tenant and subscription, display, and ask for confirmation
$context = Get-AzContext
$tenantId = $context.Tenant.Id
$subscriptionId = $context.Subscription.Id
$subscriptionName = $context.Subscription.Name

Write-Host "Current Tenant: $tenantId"
Write-Host "Current Subscription: $subscriptionName ($subscriptionId)"

$confirmation = Read-Host "Do you want to deploy to this tenant and subscription? (Y/N)"
if ($confirmation -notin @('Y','y')) {
    Write-Host "Deployment cancelled by user."
    return
}


# Step 2: Create Log Analytics Resource Group
Set-AzContext -Subscription $SubscriptionName
try {
    $existingRg = Get-AzResourceGroup -Name "rg-$namingconvention-01" -ErrorAction SilentlyContinue
    if ($existingRg) {
        Write-Warning "Resource group 'rg-$namingconvention-01' already exists. Skipping creation..."
    } else {
        Write-Output "Resource group 'rg-$namingconvention-01' does not exist. Creating..."
        New-AzResourceGroup -Name "rg-$namingconvention-01" -Location $Location
        Write-Host "Resource group 'rg-$namingconvention-01' created successfully."
    }
} catch {
    Write-Error "Failed to create or check resource group 'rg-$namingconvention-01': $_"
    return
}



# Step 3: Create Log Analytics Workspace
try {
    $existingWorkspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName "rg-$namingconvention-01" -Name "log-$namingconvention-01" -ErrorAction SilentlyContinue
    if ($existingWorkspace) {
        Write-Warning "Log Analytics workspace 'log-$namingconvention-01' already exists. Skipping creation..."
    } else {
        Write-Output "Log Analytics workspace 'log-$namingconvention-01' does not exist. Creating..."
        New-AzOperationalInsightsWorkspace -ResourceGroupName "rg-$namingconvention-01" -Name "log-$namingconvention-01" -Location $Location
        Write-Host "Log Analytics workspace 'log-$namingconvention-01' created successfully."
    }
} catch {
    Write-Error "Failed to create or check Log Analytics workspace 'log-$namingconvention-01': $_"
    return
}