
// =============================
// Firewall Hub Networking Parameter File
// =============================
//
// This file defines parameters and variables for deploying the Azure Firewall hub networking solution.
// It includes address space, subnet definitions, resource naming conventions, tags, nsg rules, and DNS zones.
//
// Key sections:
//   - Resource naming conventions and variables
//   - Subnet address and nsg configuration
//   - Bastion and Gateway settings
//   - DNS private zones for Private Endpoints
//   - nsg rules for Bastion, DNS Resolver, and Workload subnets
//
// Edit this file to customize your hub network deployment for your environment.
//

using '../../../modules/HubNetworking/modules/main.bicep'

// =============================
// Variables: Naming Conventions
// =============================

var varWorkloadCode = readEnvironmentVariable('WORKLOAD_CODE')
var varLocation = readEnvironmentVariable('LOCATION')
var varLocationShort = substring(varLocation, 0, 3)
var varEnvironmentCode = readEnvironmentVariable('ENVIRONMENT_CODE')
var varCompanyCode = readEnvironmentVariable('COMPANY_CODE')

// =============================
// Resource Names
// =============================

var varNamingConvention = '${varCompanyCode}-${varLocationShort}-${varEnvironmentCode}-${varWorkloadCode}'

param parResourceNames = {
  // Resource group and resource names for all major components
  resourceGroup:                                  toLower('rg-${varNamingConvention}-01')
  dnsResourceGroup:                               toLower('rg-${varNamingConvention}-02')
  supportingServicesResourceGroup:                toLower('rg-${varNamingConvention}-03')
  ipGroupsResourceGroup:                          toLower('rg-${varNamingConvention}-04')
  firewallPolicy:                                 toLower('afwpol-${varNamingConvention}-01')
  azureFirewall:                                  toLower('afw-${varNamingConvention}-01')
  azureFirewallPublicIP:                          toLower('pip-afw-${varNamingConvention}-01')
  bastion:                                        toLower('bas-${varNamingConvention}-01')
  vnet:                                           toLower('vnet-${varNamingConvention}-01')
  keyVault:                                       toLower('kv-${varNamingConvention}-01')
  keyvaultNic:                                    toLower('kv-${varNamingConvention}-01-vault-nic')
  keyvaultPep:                                    toLower('kv-${varNamingConvention}-01-vault-pep')
  keyvaultAsg:                                    toLower('kv-${varNamingConvention}-01-asg')
  userAssignedIdentity:                           toLower('kv-${varNamingConvention}-01-msi')
  subnet01:                                       toLower('snet-${varNamingConvention}-01')
  subnet02:                                       toLower('snet-${varNamingConvention}-02')
  subnet03:                                       toLower('snet-${varNamingConvention}-03')
}

// =============================
// Variables: Cross-Cutting Config
// =============================

// Azure region for deployment
param parLocation = readEnvironmentVariable('LOCATION')

param parDiagnosticsEnabled = bool(readEnvironmentVariable('DIAGNOSTICS_ENABLED'))

// Tags for all hub networking resources
param parTags = {
  'hidden-title': 'Hub Networking'
}

// Tags for supporting services resources
param parSupportingServicesTags = {
  'hidden-title': 'Hub Networking - Supporting Services'
}

// =============================
// Variables: Azure Firewall Configuration
// =============================

var varFirewallPremiumEnabled = bool(readEnvironmentVariable('FIREWALL_PREMIUM_ENABLED'))

// Azure Firewall Insights enabled
param parFirewallInsightsIsEnabled = bool(readEnvironmentVariable('FIREWALL_INSIGHTS_ENABLED'))

// Azure Firewall Policy SKU tier
param parFirewallPolicySkuTier = varFirewallPremiumEnabled ? 'Premium' : 'Standard'

// Enable Azure Firewall deployment
param parEnableAzureFirewall = true

// Azure Firewall SKU tier
param parFirewallSkuTier = varFirewallPremiumEnabled ? 'Premium' : 'Standard'

// Azure Firewall Threat Intelligence Mode
param parFirewallThreatIntelMode = 'Alert'

// Enable DNS Proxy on Azure Firewall
param parEnableFirewallDNSProxy = true

// Azure Firewall Intrusion Detection Mode
param parFirewallIntrusionDetection = {
      mode: 'Alert'
    }

// Reference the Azure Firewall root certificate from Key Vault
// Provide the full Key Vault secret URI (recommended for automation and clarity):
//   e.g. 'https://<your-keyvault-name>.vault.azure.net/secrets/Az-Firewall-Root/<secret-version>'
// If your Bicep expects just the secret name, use:
//   e.g. 'Az-Firewall-Root'
param parFirewallRootCertificateId = varFirewallPremiumEnabled ? 'https://${parResourceNames.keyVault}.vault.azure.net/secrets/Az-Firewall-Root-Pfx-Cert/' : ''

// Name of the Azure Firewall root certificate in Key Vault
param parFirewallRootCertificateName = varFirewallPremiumEnabled ? 'Az-Firewall-Root-Pfx-Cert' : ''

// Allow SQL Redirect in Azure Firewall
param parAllowFirewallSQLRedirect = false

var varVnetAddressPrefix = readEnvironmentVariable('VNET_ADDRESS_PREFIX')

// Hub VNet address space (CIDR)
param parAddressPrefixes = [varVnetAddressPrefix]

// VNet flow log timeout in minutes
param parVnetFlowTimeoutInMinutes = 30

// =============================
// Subnet Definitions
// =============================
//
// Each subnet object defines:
//   - addressPrefix: Subnet CIDR (calculated from base address)
//   - name: Subnet name
//   - networkSecurityGroupResourceId: nsg resource ID (if applicable)
//   - securityRules: nsg rules (if applicable)
//   - tags: Resource tags
//   - delegation: (optional) Service delegation for DNS Resolver
//
param parSubnets = [
  {
    addressPrefix: cidrSubnet(parAddressPrefixes[0], 24, 0)
    name: parResourceNames.subnet01
    networkSecurityGroupResourceId: '/subscriptions/${readEnvironmentVariable('SUBSCRIPTION_ID')}/resourceGroups/${parResourceNames.resourceGroup}/providers/Microsoft.Network/networkSecurityGroups/${parResourceNames.subnet01}-nsg'
    securityRules: varWorkloadSubnetnsgRules
    tags: parTags
  }
  {
    addressPrefix: cidrSubnet(parAddressPrefixes[0], 25, 2)
    name: 'AzureFirewallSubnet'
    networkSecurityGroupResourceId: null
    securityRules: null
    tags: null
  }
  {
    addressPrefix: cidrSubnet(parAddressPrefixes[0], 25, 3)
    name: 'AzureFirewallManagementSubnet'
    networkSecurityGroupResourceId: null
    securityRules: null
    tags: null
  }
  {
    addressPrefix: cidrSubnet(parAddressPrefixes[0], 26, 8)
    name: 'AzureBastionSubnet'
    networkSecurityGroupResourceId: '/subscriptions/${readEnvironmentVariable('SUBSCRIPTION_ID')}/resourceGroups/${parResourceNames.resourceGroup}/providers/Microsoft.Network/networkSecurityGroups/AzureBastionSubnet-nsg'
    securityRules: varBastionnsgRules
    tags: parTags
  }
  {
    addressPrefix: cidrSubnet(parAddressPrefixes[0], 26, 9)
    name: 'GatewaySubnet'
    networkSecurityGroupResourceId: null
    securityRules: null
    tags: null
  }
  {
    addressPrefix: cidrSubnet(parAddressPrefixes[0], 27, 24)
    name: parResourceNames.subnet02
    delegation: 'Microsoft.Network/dnsResolvers'
    networkSecurityGroupResourceId: '/subscriptions/${readEnvironmentVariable('SUBSCRIPTION_ID')}/resourceGroups/${parResourceNames.resourceGroup}/providers/Microsoft.Network/networkSecurityGroups/${parResourceNames.subnet02}-nsg'
    securityRules: varDnsResolverInboundSubnetnsgRules
    tags: parTags
  }
  {
    addressPrefix: cidrSubnet(parAddressPrefixes[0], 27, 25)
    name: parResourceNames.subnet03
    delegation: 'Microsoft.Network/dnsResolvers'
    networkSecurityGroupResourceId: '/subscriptions/${readEnvironmentVariable('SUBSCRIPTION_ID')}/resourceGroups/${parResourceNames.resourceGroup}/providers/Microsoft.Network/networkSecurityGroups/${parResourceNames.subnet03}-nsg'
    securityRules: varDnsResolverOutboundSubnetnsgRules
    tags: parTags
  }
]

// Enable Azure Bastion deployment
param parEnableBastion = false

// Bastion host configuration
param parBastionHostConfig = {
      bastionHostName: parResourceNames.bastion
      disableCopyPaste: true
      enableFileCopy: false
      enableIpConnect: false
      enableShareableLink: false
      scaleUnits: 2
      skuName: 'Standard'
    }

// Log Analytics workspace name
param parLogAnalyticsWorkspaceName = readEnvironmentVariable('LOG_ANALYTICS_WORKSPACE_NAME')

// Log Analytics subscription ID
param parLogAnalyticsSubscriptionId = readEnvironmentVariable('LOG_ANALYTICS_SUBSCRIPTION_ID')

// Log Analytics resource group name
param parLogAnalyticsResourceGroupName = readEnvironmentVariable('LOG_ANALYTICS_RESOURCE_GROUP_NAME')


// Resource ID for the subnet used by Key Vault Private Endpoint
param parKeyVaultPrivateEndpointSubnetId = '/subscriptions/${readEnvironmentVariable('SUBSCRIPTION_ID')}/resourceGroups/${parResourceNames.resourceGroup}/providers/Microsoft.Network/virtualNetworks/${parResourceNames.vnet}/subnets/${parResourceNames.subnet01}'

// =============================
// nsg Rules
// =============================
//
// nsg rules for Bastion, DNS Resolver, and Workload subnets

var varBastionnsgRules = [
  {
    name: 'AllowHttpsInbound'
    properties: {
      description: 'Allow HTTPS inbound traffic to the Bastion host'
      protocol: 'Tcp'
      sourcePortRange: '*'
      destinationPortRange: '443'
      sourceAddressPrefix: 'Internet'
      destinationAddressPrefix: '*'
      access: 'Allow'
      direction: 'Inbound'
      priority: 120
      sourcePortRanges: []
      destinationPortRanges: []
      sourceAddressPrefixes: []
      destinationAddressPrefixes: []
    }
  }
  {
    name: 'AllowGatewayManagerInbound'
    properties: {
      description: 'Allow Gateway Manager inbound traffic to the Bastion host'
      protocol: 'Tcp'
      sourcePortRange: '*'
      destinationPortRange: '443'
      sourceAddressPrefix: 'GatewayManager'
      destinationAddressPrefix: '*'
      access: 'Allow'
      direction: 'Inbound'
      priority: 130
      sourcePortRanges: []
      destinationPortRanges: []
      sourceAddressPrefixes: []
      destinationAddressPrefixes: []
    }
  }
  {
    name: 'AllowAzureLoadBalancerInbound'
    properties: {
      description: 'Allow Azure Load Balancer inbound traffic to the Bastion host'
      protocol: 'Tcp'
      sourcePortRange: '*'
      destinationPortRange: '443'
      sourceAddressPrefix: 'AzureLoadBalancer'
      destinationAddressPrefix: '*'
      access: 'Allow'
      direction: 'Inbound'
      priority: 140
      sourcePortRanges: []
      destinationPortRanges: []
      sourceAddressPrefixes: []
      destinationAddressPrefixes: []
    }
  }
  {
    name: 'AllowBastionHostCommunication'
    properties: {
      description: 'Allow Bastion host communication with the Azure platform'
      protocol: '*'
      sourcePortRange: '*'
      destinationPortRange: ''
      sourceAddressPrefix: 'VirtualNetwork'
      destinationAddressPrefix: 'VirtualNetwork'
      access: 'Allow'
      direction: 'Inbound'
      priority: 150
      sourcePortRanges: []
      destinationPortRanges: ['8080', '5701']
      sourceAddressPrefixes: []
      destinationAddressPrefixes: []
    }
  }
  {
    name: 'AllowSshRdpOutbound'
    properties: {
      description: 'Allow SSH and RDP outbound traffic from the Bastion host'
      protocol: '*'
      sourcePortRange: '*'
      destinationPortRange: ''
      sourceAddressPrefix: '*'
      destinationAddressPrefix: 'VirtualNetwork'
      access: 'Allow'
      direction: 'Outbound'
      priority: 100
      sourcePortRanges: []
      destinationPortRanges: ['22', '3389']
      sourceAddressPrefixes: []
      destinationAddressPrefixes: []
    }
  }
  {
    name: 'AllowAzureCloudOutbound'
    properties: {
      description: 'Allow outbound traffic to Azure Cloud services'
      protocol: '*'
      sourcePortRange: '*'
      destinationPortRange: '443'
      sourceAddressPrefix: '*'
      destinationAddressPrefix: 'AzureCloud'
      access: 'Allow'
      direction: 'Outbound'
      priority: 110
      sourcePortRanges: []
      destinationPortRanges: []
      sourceAddressPrefixes: []
      destinationAddressPrefixes: []
    }
  }
  {
    name: 'AllowBastionCommunication'
    properties: {
      description: 'Allow Bastion host communication with the Azure platform'
      protocol: '*'
      sourcePortRange: '*'
      destinationPortRange: ''
      sourceAddressPrefix: 'VirtualNetwork'
      destinationAddressPrefix: 'VirtualNetwork'
      access: 'Allow'
      direction: 'Outbound'
      priority: 120
      sourcePortRanges: []
      destinationPortRanges: ['8080', '5701']
      sourceAddressPrefixes: []
      destinationAddressPrefixes: []
    }
  }
  {
    name: 'AllowHttpOutbound'
    properties: {
      description: 'Allow HTTP outbound traffic from the Bastion host'
      protocol: 'Tcp'
      sourcePortRange: '*'
      destinationPortRange: '80'
      sourceAddressPrefix: '*'
      destinationAddressPrefix: 'Internet'
      access: 'Allow'
      direction: 'Outbound'
      priority: 130
      sourcePortRanges: []
      destinationPortRanges: []
      sourceAddressPrefixes: []
      destinationAddressPrefixes: []
    }
  }
  {
    name: 'ImplicitDenyInbound'
    properties: {
      description: 'Implicit deny for all other inbound traffic'
      protocol: '*'
      sourcePortRange: '*'
      destinationPortRange: '*'
      sourceAddressPrefix: '*'
      destinationAddressPrefix: '*'
      access: 'Deny'
      direction: 'Inbound'
      priority: 4096
    }
  }
  {
    name: 'ImplicitDenyOutbound'
    properties: {
      description: 'Implicit deny for all other outbound traffic'
      protocol: '*'
      sourcePortRange: '*'
      destinationPortRange: '*'
      sourceAddressPrefix: '*'
      destinationAddressPrefix: '*'
      access: 'Deny'
      direction: 'Outbound'
      priority: 4096
    }
  }
]

var varDnsResolverInboundSubnetnsgRules = [
  {
    name: 'AllowDnsResolverInbound'
    properties: {
      description: 'Allow inbound traffic to the DNS Resolver'
      protocol: 'Tcp'
      sourcePortRange: '*'
      destinationPortRange: '53'
      sourceAddressPrefix: '*'
      destinationAddressPrefix: '*'
      access: 'Allow'
      direction: 'Inbound'
      priority: 100
    }
  }
  {
    name: 'ImplicitDenyInbound'
    properties: {
      description: 'Implicit deny for all other inbound traffic'
      protocol: '*'
      sourcePortRange: '*'
      destinationPortRange: '*'
      sourceAddressPrefix: '*'
      destinationAddressPrefix: '*'
      access: 'Deny'
      direction: 'Inbound'
      priority: 4096
  }
}
{
   name: 'ImplicitDenyOutbound'
   properties: {
      description: 'Implicit deny for all other outbound traffic'
      protocol: '*'
      sourcePortRange: '*'
      destinationPortRange: '*'
      sourceAddressPrefix: '*'
      destinationAddressPrefix: '*'
      access: 'Deny'
      direction: 'Outbound'
      priority: 4096
    }
}
]

var varDnsResolverOutboundSubnetnsgRules = [
  {
    name: 'AllowDnsResolverOutbound'
    properties: {
      description: 'Allow outbound traffic from the DNS Resolver'
      protocol: 'Tcp'
      sourcePortRange: '*'
      destinationPortRange: '53'
      sourceAddressPrefix: '*'
      destinationAddressPrefix: '*'
      access: 'Allow'
      direction: 'Outbound'
      priority: 100
    }
  }
  {
    name: 'ImplicitDenyInbound'
    properties: {
      description: 'Implicit deny for all other inbound traffic'
      protocol: '*'
      sourcePortRange: '*'
      destinationPortRange: '*'
      sourceAddressPrefix: '*'
      destinationAddressPrefix: '*'
      access: 'Deny'
      direction: 'Inbound'
      priority: 4096
    }
  }
  {
    name: 'ImplicitDenyOutbound'
    properties: {
      description: 'Implicit deny for all other outbound traffic'
      protocol: '*'
      sourcePortRange: '*'
      destinationPortRange: '*'
      sourceAddressPrefix: '*'
      destinationAddressPrefix: '*'
      access: 'Deny'
      direction: 'Outbound'
      priority: 4096
    }
  }
]

var varWorkloadSubnetnsgRules = [
  {
    name: 'ImplicitDenyInbound'
    properties: {
      description: 'Implicit deny for all other inbound traffic'
      protocol: '*'
      sourcePortRange: '*'
      destinationPortRange: '*'
      sourceAddressPrefix: '*'
      destinationAddressPrefix: '*'
      access: 'Deny'
      direction: 'Inbound'
      priority: 4096
    }
  }
  {
    name: 'ImplicitDenyOutbound'
    properties: {
      description: 'Implicit deny for all other outbound traffic'
      protocol: '*'
      sourcePortRange: '*'
      destinationPortRange: '*'
      sourceAddressPrefix: '*'
      destinationAddressPrefix: '*'
      access: 'Deny'
      direction: 'Outbound'
      priority: 4096
    }
  }
]
