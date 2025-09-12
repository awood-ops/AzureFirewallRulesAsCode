
// =============================
// Azure Firewall Hub Networking Main Bicep Module
// =============================
//
// This Bicep file defines the main deployment for the Azure Firewall hub networking solution.
// It includes parameters for resource naming, firewall configuration, networking, logging, and supporting services.
//
// Key sections:
//   - Cross-cutting parameters (naming, tags, location)
//   - Firewall and networking parameters
//   - Log Analytics and monitoring
//   - Supporting services (Key Vault, Managed Identity, etc.)
//   - Module deployments for NSGs, Firewall Policy, Hub Networking, etc.
//

targetScope = 'subscription'

// =============================
// Cross-Cutting Parameters
// =============================

@sys.description('Required. The Resource Names for the resources.')
param parResourceNames object

@sys.description('Location')
param parLocation string

@sys.description('The Tags')
param parTags object

@sys.description('The Tags for Supporting Services resources')
param parSupportingServicesTags object

@sys.description('Required. Enable or Disable the Diagnostic Settings for resources.')
param parDiagnosticsEnabled bool = true

// =============================
// Firewall Parameters
// =============================

@sys.description('The Firewall Policy SKU tier')
param parFirewallPolicySkuTier string

@sys.description('The flag to determine if Azure Firewall is enabled')
param parEnableAzureFirewall bool

@sys.description('The Azure Firewall SKU tier')
param parFirewallSkuTier string

@sys.description('The Azure Firewall Threat Intelligence Mode')
param parFirewallThreatIntelMode string

@sys.description('The Azure Firewall Intrusion Detection Mode')
param parFirewallIntrusionDetection object

@sys.description('The flag to determine if Azure Firewall DNS Proxy is enabled')
param parEnableFirewallDNSProxy bool

@sys.description('The flag to determine if SQL Redirect is allowed in Azure Firewall')
param parAllowFirewallSQLRedirect bool

@sys.description('The Azure Firewall Root Certificate ID for the Firewall Policy')
param parFirewallRootCertificateId string

@sys.description('The Azure Firewall Root Certificate Name for the Firewall Policy')
param parFirewallRootCertificateName string

// =============================
// Networking Parameters
// =============================

@sys.description('Hub Address Prefixes')
param parAddressPrefixes array

@sys.description('The flag to determine if VNet Flow Logs are enabled')
param parVnetFlowTimeoutInMinutes int

@sys.description('The subnets for the hub virtual network')
param parSubnets array

@sys.description('The flag to determine if Azure Bastion is enabled')
param parEnableBastion bool

// =============================
// Bastion Host Parameters
// =============================

@sys.description('The configuration for the Bastion host')
param parBastionHostConfig object

// =============================
// Log Analytics Workspace
// =============================

@sys.description('Required. The name of the Log Analytics workspace.')
param parLogAnalyticsWorkspaceName string

@sys.description('Required. The subscription id of the Log Analytics workspace.')
param parLogAnalyticsSubscriptionId string

@sys.description('Required. The resource group of the Log Analytics workspace.')
param parLogAnalyticsResourceGroupName string

// =============================
// Key Vault Parameters
// =============================

@sys.description('The Private Endpoint Subnet ID for Key Vault')
param parKeyVaultPrivateEndpointSubnetId string

var varKeyVaultAccessPolicies = [
    {
      objectId: modUserAssignedIdentity!.outputs.principalId
      permissions: {
        certificates: ['get', 'list']
        secrets: ['get', 'list']
      }
    }
  ]

// =============================
// Existing Resources
// =============================

resource resLogAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' existing = {
  name: parLogAnalyticsWorkspaceName
  scope: az.resourceGroup(parLogAnalyticsSubscriptionId, parLogAnalyticsResourceGroupName)
}

var varLogAnalyticsWorkspace = [
  {
    workspaceResourceId: resLogAnalyticsWorkspace.id
  }
]

// =============================
// Resource Group Module
// =============================

module modResourceGroup 'br/public:avm/res/resources/resource-group:0.4.1' = {
  name: 'resourceGroupDeployment'
  params: {
    name: parResourceNames.resourceGroup
    location: parLocation
    tags: parTags
  }
}

// =============================
// Firewall Policy
// =============================

module modFirewallPolicy 'br/public:avm/res/network/firewall-policy:0.3.1' = {
  scope: az.resourceGroup(parResourceNames.resourceGroup)
  name: 'firewallPolicyDeployment'
  params: {
    // Required parameters
    name: parResourceNames.firewallPolicy
    // Non-required parameters
    managedIdentities: parFirewallPolicySkuTier == 'Premium' ? {

      userAssignedResourceIds: [
        modUserAssignedIdentity!.outputs.resourceId
      ]
    } : null
    allowSqlRedirect: parAllowFirewallSQLRedirect
    location: parLocation
    enableProxy: parEnableFirewallDNSProxy
    tags: parTags
    threatIntelMode: parFirewallThreatIntelMode
    // Only include intrusionDetection if not Standard
    keyVaultSecretId: parFirewallRootCertificateId
    certificateName: parFirewallRootCertificateName
    tier: parFirewallPolicySkuTier
    // Conditional property assignment for intrusionDetection
    intrusionDetection: parFirewallPolicySkuTier != 'Standard' ? parFirewallIntrusionDetection : null
  }
  dependsOn: [
    modResourceGroup
  ]
}

// =============================
// NSG Module
// =============================

module modNSG 'br/public:avm/res/network/network-security-group:0.5.1' = [for subnet in parSubnets: if (subnet.name != 'AzureFirewallSubnet' && subnet.name != 'AzureFirewallManagementSubnet' && subnet.name != 'GatewaySubnet') {
  scope: az.resourceGroup(parResourceNames.resourceGroup)
  name: 'nsgDeployment-${subnet.name}'
  params: {
    name: '${subnet.name}-NSG'
    location: parLocation
    tags: subnet.tags
    securityRules: subnet.securityRules
    diagnosticSettings: parDiagnosticsEnabled ? varLogAnalyticsWorkspace : null
  }
  dependsOn: [
    modResourceGroup
  ]
}]

// =============================
// Hub Networking Module
// =============================

module modHubNetworking 'br/public:avm/ptn/network/hub-networking:0.5.0' = {
  scope: az.resourceGroup(parResourceNames.resourceGroup)
  name: 'hubNetworkingDeployment'
  params: {
    hubVirtualNetworks: {
      '${parResourceNames.vnet}': {
        addressPrefixes: parAddressPrefixes
        azureFirewallSettings: {
          azureFirewallName: parResourceNames.azureFirewall
          azureSkuTier: parFirewallSkuTier
          diagnosticSettings: parDiagnosticsEnabled ? varLogAnalyticsWorkspace : null
          location: parLocation
          publicIPAddressObject: {
            name: parResourceNames.azureFirewallPublicIP
          }
          threatIntelMode: parFirewallThreatIntelMode
          zones: [
            1
          ]
          firewallPolicyId: modFirewallPolicy.outputs.resourceId
        }
        diagnosticSettings: parDiagnosticsEnabled ? varLogAnalyticsWorkspace : null
        enableAzureFirewall: parEnableAzureFirewall
        enableBastion: parEnableBastion
        bastionHost: parBastionHostConfig
        enablePeering: false
        flowTimeoutInMinutes: parVnetFlowTimeoutInMinutes
        location: parLocation
        routes: [
          {
            name: 'defaultRoute'
            properties: {
              addressPrefix: '0.0.0.0/0'
              nextHopType: 'Internet'
            }
          }
        ]
        subnets: parSubnets
        tags: parTags
        vnetEncryption: false
        vnetEncryptionEnforcement: 'AllowUnencrypted'
      }
    }
    location: parLocation
  }
  dependsOn: [
    modResourceGroup
    modNSG
  ]
}

// =============================
// Supporting Services Resource Group Module
// =============================

module modSupportingServicesResourceGroup 'br/public:avm/res/resources/resource-group:0.4.1' = if (parFirewallSkuTier == 'Premium') {
  name: 'supportingServicesResourceGroupDeployment'
  params: {
    name: parResourceNames.supportingServicesResourceGroup
    location: parLocation
    tags: parSupportingServicesTags
  }
}

// =============================
// Key Vault Module
// =============================

module modUserAssignedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = if (parFirewallSkuTier == 'Premium') {
  scope: az.resourceGroup(parResourceNames.supportingServicesResourceGroup)
  name: 'userAssignedIdentityDeployment'
  params: {
    // Required parameters
    name: parResourceNames.userAssignedIdentity
    // Non-required parameters
    location: parLocation
    tags: parSupportingServicesTags
  }
  dependsOn: [
    modSupportingServicesResourceGroup
  ]
}

module modKeyVault 'br/public:avm/res/key-vault/vault:0.13.3' = if (parFirewallSkuTier == 'Premium') {
  scope: az.resourceGroup(parResourceNames.supportingServicesResourceGroup)
  name: 'keyVaultDeployment'
  params: {
    // Required parameters
    name: parResourceNames.keyVault
    // Non-required parameters
    location: parLocation
    tags: parSupportingServicesTags
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    enableSoftDelete: true
    enableRbacAuthorization: false
    enableVaultForDeployment: false
    enableVaultForDiskEncryption: false
    enableVaultForTemplateDeployment: true
    privateEndpoints: [
      {
        name: parResourceNames.keyvaultPep
        service: 'vault'
        subnetResourceId: parKeyVaultPrivateEndpointSubnetId
        customNetworkInterfaceName: parResourceNames.keyvaultNic
        applicationSecurityGroupResourceIds: [
          modKeyvaultAsg!.outputs.resourceId
        ]
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: resourceId(
                subscription().subscriptionId,
                parResourceNames.dnsResourceGroup,
                'Microsoft.Network/privateDnsZones',
                'privatelink.vaultcore.azure.net'
              )
            }
          ]
        }
      }
    ]
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: []
    }
    diagnosticSettings: parDiagnosticsEnabled ? varLogAnalyticsWorkspace : null
    accessPolicies: varKeyVaultAccessPolicies
  }
  dependsOn: [
    modSupportingServicesResourceGroup
    modResourceGroup
    modHubNetworking
  ]
}

module modKeyvaultAsg 'br/public:avm/res/network/application-security-group:0.2.1' = if (parFirewallSkuTier == 'Premium') {
  scope: az.resourceGroup(parResourceNames.supportingServicesResourceGroup)
  name: 'keyVaultAsgDeployment'
  params: {
    name: parResourceNames.keyVaultAsg
    location: parLocation
    tags: parSupportingServicesTags
  }
  dependsOn: [
    modSupportingServicesResourceGroup
  ]
}
