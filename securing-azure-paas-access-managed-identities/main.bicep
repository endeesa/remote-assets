@description('The name of the storage account to create')
param storageAccountName string = 'myblobstore${uniqueString(resourceGroup().id)}'

@description('The name of the Cosmos DB account to create')
param cosmosDBAccountName string = 'mycosmosdb${uniqueString(resourceGroup().id)}'

@description('The name of the function app to create')
param functionAppName string = 'myfunctionapp${uniqueString(resourceGroup().id)}'

@description('The name of the key vault to create')
param keyVaultName string = 'mykeyvault-${uniqueString(resourceGroup().id)}'

@description('The name of the managed identity resource.')
param identityName string = 'myuseridentity-${uniqueString(resourceGroup().id)}'

@description('Whether the managed identity has contributor access on the resource group level')
param isRGContributor bool = false

@description('The name of the region to deploy resources to')
param location string = resourceGroup().location

param tags object = {
  Environment: 'Demo'
  Contact: 'info@mungana.com'
  Repo: 'https://github.com/rihonegroupdev/remote-assets/securing-azure-paas-access-managed-identities'
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: tags
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
    allowBlobPublicAccess: false
  }
}

resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: '${functionAppName}-plan'
  location: location
  sku: {
    name: 'Y1'
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp, linux'
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    reserved: true
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: 'Python|3.11'
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=core.windows.net'
        }
      ]
    }
  }
}

resource cosmosDb 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' = {
  name: cosmosDBAccountName
  location: location
  properties: {
    locations: [
      {
        locationName: location
      }
    ]
    databaseAccountOfferType: 'Standard'
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enablePurgeProtection: true
    sku: {
      family: 'A'
      name: 'standard'
    }
  }
}

// Assign automation roles
// Role Definitions Reference: https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles
resource resourceGroupAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (isRGContributor) {
  name: guid('${managedIdentity.name}-rg-control-access')
  scope: resourceGroup()
  properties: {
    description: 'Allow identity to perform automated management tasks on the resource group'
    principalType: 'ServicePrincipal'
    principalId: managedIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  }
}

resource storageAccountBlobAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid('${managedIdentity.name}-storage-blob-access')
  scope: storageAccount
  properties: {
    description: 'Allow identity to read and write blob data'
    principalType: 'ServicePrincipal'
    principalId: managedIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  }
}

resource storageAccountQueueAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid('${managedIdentity.name}-storage-queue-access')
  scope: storageAccount
  properties: {
    description: 'Allow identity to read and write queue messages'
    principalType: 'ServicePrincipal'
    principalId: managedIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
  }
}

resource cosmosDBDataAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid('${managedIdentity.name}-cosmosdb-data-access')
  scope: cosmosDb
  properties: {
    description: 'Allow identity to list containers, as well as read and write from CosmosDB'
    principalType: 'ServicePrincipal'
    principalId: managedIdentity.properties.principalId
    // https://learn.microsoft.com/en-us/azure/cosmos-db/how-to-setup-rbac#built-in-role-definitions
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00000000-0000-0000-0000-000000000002')
  }
}

resource keyVaultSecretsAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid('${managedIdentity.name}-kv-secrets-access')
  scope: keyVault
  properties: {
    description: 'Allow identity to read key vault secrets'
    principalType: 'ServicePrincipal'
    principalId: managedIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
  }
}
