param (
  [Parameter()]
  [String]$Location = "$($env:LOCATION)",

  [Parameter()]
  [String]$SubscriptionId = "$($env:SUBSCRIPTION_ID)",

  [Parameter()]
  [String]$WorkloadCode = "$($env:WORKLOAD_CODE)",

  [Parameter()]
  [String]$TemplateFile = "modules\HubNetworking\modules\main.bicep",

  [Parameter()]
  [String]$TemplateParameterFile = ".\config\parameters\HubNetworking\main.bicepparam",

  [Parameter()]
  [Boolean]$WhatIfEnabled = [System.Convert]::ToBoolean($($env:IS_PULL_REQUEST))
)

# Define the environment code as a variable
$EnvironmentCode = $env:ENVIRONMENT_CODE

$StackName = "hubnetworking".ToLower()

# Get current user object ID
$CurrentUserId = (Get-AzContext).Account.Id

try {
    $CurrentUserObjectId = (Get-AzADUser -UserPrincipalName $CurrentUserId).Id
} catch {
    Write-Error "Failed to get current user object ID: $_"
    exit 1
}

# Parameters necessary for deployment
$StackInputObject = @{
  Name                          = $StackName
  Location                      = $Location
  TemplateFile                  = $TemplateFile
  TemplateParameterFile         = $TemplateParameterFile
  ActionOnUnmanage              = 'detachAll'
  DenySettingsMode              = 'DenyWriteAndDelete'
  DenySettingsExcludedPrincipal = $CurrentUserObjectId
  DenySettingsApplyToChildScopes = $true
  WhatIf                        = $WhatIfEnabled
  Verbose                       = $true
}

Select-AzSubscription -SubscriptionId $SubscriptionId

Write-Host "Creating or updating deployment stack: $StackName"
New-AzSubscriptionDeploymentStack @StackInputObject -Force