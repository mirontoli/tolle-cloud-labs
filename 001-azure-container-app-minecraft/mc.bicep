@description('Base string to be assigned to Azure Resources')
param baseName string = 'mc'

@description('The region where the resources will be deployed. If not specified, it will be the same as the resource groups region')
param location string = resourceGroup().location

@description('The CIDR of the entire virtual network.')
param vnetCidr string = '10.10.0.0/16'

@description('CIDR for Container Apps Environment')
param acaSubnetCidr string = '10.10.0.0/23'

@description('Suffix to be assigned to revisions of container apps.')
param now string = toLower(utcNow())

@description('Number of CPU cores assigned to the container app.')
@allowed([
  '0.5'
  '1.0'
  '1.5'
  '2.0'
])
param cpu string = '1.0'

@description('Memory allocated to the container app.')
@allowed([
  '1.0Gi'
  '2.0Gi'
  '3.0Gi'
  '4.0Gi'
])
param memory string = '2.0Gi'

@description('Docker image URL for Minecraft Edition by itzg.')
param containerImage string = 'docker.io/itzg/minecraft-server:latest'

@description('TCP port number for Minecraft server.')
param minecraftPort int = 25565

@description('Mount point of persistent storage.')
param volumeMountPoint string = '/data'

@description('The minimum number of replicas for the container app. If this value is set to 0, the container will stop after being idle for 5 minutes.')
@minValue(0)
@maxValue(1)
param minReplicas int = 0

@description('Storage Account SKU.')
@allowed([
  'Premium_LRS'
  'Standard_LRS'
])
param storageSKU string = 'Standard_LRS'

@description('The environment variables required to start a Minecraft server.')
param env array

output minecraftServerAddress string = containerApp.properties.configuration.ingress.fqdn

var omsName = 'log-${baseName}'
var acaName = 'acaenv-${baseName}'
var vnetName = 'vnet-${baseName}'
var acaSubnetName = 'snet-aca'
var fileShareName = 'mcdata'
var storageName = take('st${toLower(baseName)}${uniqueString(resourceGroup().id)}', 24)
var containerName = 'minecraft'

resource containerApp 'Microsoft.App/containerApps@2022-06-01-preview' = {
  name: containerName
  location: location
  properties: {
    managedEnvironmentId: containerAppEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      secrets: []
      registries: []
      ingress: {
        external: true
        exposedPort: minecraftPort
        targetPort: minecraftPort
        transport: 'tcp'
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
    }
    template: {
      revisionSuffix: now
      containers: [
        {
          image: containerImage
          name: containerName
          env: env
          args: []
          probes: []
          volumeMounts: [
            {
              volumeName: fileShareName
              mountPath: volumeMountPoint
            }
          ]
          resources: {
            cpu: any(cpu)
            memory: memory
          }
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: 1
        rules: []
      }
      volumes: [
        {
          storageType: 'AzureFile'
          name: fileShareName
          storageName: fileShareName
        }
      ]
    }
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-02-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetCidr
      ]
    }
    subnets: [
      {
        name: acaSubnetName
        properties: {
          addressPrefix: acaSubnetCidr
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
          ]
        }
      }
    ]
  }
}

resource acaSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-02-01' existing = {
  parent: virtualNetwork
  name: acaSubnetName
}

resource containerAppEnvironmentStorage 'Microsoft.App/managedEnvironments/storages@2023-04-01-preview' = {
  parent: containerAppEnvironment
  name: fileShareName
  properties: {
    azureFile: {
      accountName: storageAccount.name
      shareName: fileShareName
      accountKey: storageAccount.listKeys().keys[0].value
      accessMode: 'ReadWrite'
    }
  }
}

resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2023-04-01-preview' = {
  name: acaName
  location: location
  properties: {
    vnetConfiguration: {
      internal: false
      infrastructureSubnetId: acaSubnet.id
    }
    appLogsConfiguration: {
      destination: 'azure-monitor'
    }
  }
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: omsName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource containerAppEnvironmentDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: containerAppEnvironment
  name: omsName
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    metrics: []
    logs: [
      {
        enabled: true
        categoryGroup: 'allLogs'
      }
    ]
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageName
  location: location
  sku: {
    name: 'Standard_LRS' //Premium_LRS
  }
  kind: 'StorageV2' //FileStorage
  properties: {
    allowBlobPublicAccess: false
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      virtualNetworkRules: [
        {
          id: acaSubnet.id
          action: 'Allow'
        }
      ]
    }
    allowSharedKeyAccess: true
  }
}

resource storageAccountFile 'Microsoft.Storage/storageAccounts/fileServices@2022-09-01' existing = {
  name: 'default'
  parent: storageAccount
}

resource storageAccountFileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2022-09-01' = {
  parent: storageAccountFile
  name: fileShareName
  properties: {
    shareQuota: 100
  }
}
