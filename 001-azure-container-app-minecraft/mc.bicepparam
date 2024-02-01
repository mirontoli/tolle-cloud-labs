using 'mc.bicep'

param baseName = 'minetolle'
param cpu = '1.0'
param memory = '2.0Gi'
param containerImage = 'docker.io/itzg/minecraft-server:latest'
//param containerImage = 'docker.io/marctv/minecraft-papermc-server:latest'
param minecraftPort = 25565
param volumeMountPoint = '/data'
param minReplicas = 0
// Standard_LRS does not support FileStorage
// https://learn.microsoft.com/en-us/rest/api/storagerp/srp_sku_types
param storageSKU = 'Premium_LRS'
param env = [
  {
    name: 'EULA'
    value: 'TRUE'

  }
  {
    name: 'UID'
    value: '0'
  }
  {
    name: 'GID'
    value: '0'
  }
  {
    name: 'MAX_PLAYERS'
    value: '5'
  }
  {
    name: 'MODE'
    value: 'survival'
  }
  {
    name: 'DIFFICULTY'
    value: 'normal'
  }
]
