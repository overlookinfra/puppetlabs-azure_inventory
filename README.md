# azure_inventory

#### Table of Contents

1. [Description](#description)
2. [Requirements](#requirements)
3. [Usage](#usage)

## Description

This module includes a Bolt plugin to generate Bolt targets from Azure VMs.

## Requirements

You will need a client ID and secret in order to authenticate with Azure. The simplest way to generate these is to use the [Azure CLI tool](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli).

Run `az ad sp create-for-rbac` and copy the `appId` and `password` fields. These correspond to the `client_id` and `client_secret` parameters to the task.

Alternatively, you can follow the instructions to [register a client application with Azure AD](https://docs.microsoft.com/en-us/rest/api/azure/#register-your-client-application-with-azure-ad).

You will also need to know your subscription ID and tenant ID. If you're using the Azure CLI, you can retrieve these with `az account show`. These will be in the `id` and `tenantId` fields respectively.

## Usage

The plugin supports looking up virtual machines and virtual machine scale sets. It supports several fields:

- `resource_group`: The resource group to filter by (optional)
- `scale_set`: The scale set to filter by (optional, requires that `resource_group` also be set)
- `location`: The location to filter by (optional)
- `tags`: A list of one or more tags to filter by (optional, tags are `name: value` pairs and instances must match all listed tags)

Accessing Azure resources requires credentials for signing all API requests. Each credential will be looked up from an environment variable if not set in the inventory config.

- `client_id`: The Azure client application ID (defaults to `$AZURE_CLIENT_ID`)
- `client_secret`: The Azure client application secret (defaults to `$AZURE_CLIENT_SECRET`)
- `tenant_id`: The Azure AD tenant ID (defaults to `$AZURE_TENANT_ID`)
- `subscription_id`: The Azure subscription ID (defaults to `$AZURE_SUBSCRIPTION_ID`)

Bolt will only target virtual machines and virtual machine scale sets that have a public IP address. The `uri` of the target will be set to the public IP address and the `name` will be set to either the fully qualified domain name if one exists or the instance name otherwise.

If `scale_set` is not provided, Bolt will not find VMs that are defined by a scale set.

### Examples

```yaml
# inventory.yaml
version: 2
groups:
  - name: azure-vms
    targets:
      - _plugin: azure_inventory
        tenant_id: xxxx-xxx-xxxx
        client_id: xxxx-xxx-xxxx
        client_secret: xxxx-xxx-xxxx
        subscription_id: xxxx-xxx-xxxx
        location: eastus
        resource_group: bolt
        tags:
          foo: bar
          baz: bak
  - name: azure-scale-sets
    targets:
      - _plugin: azure_inventory
        tenant_id: xxxx-xxx-xxxx
        client_id: xxxx-xxx-xxxx
        client_secret: xxxx-xxx-xxxx
        subscription_id: xxxx-xxx-xxxx
        location: eastus2
        resource_group: puppet
        scale_set: bolt
        tags:
          foo: bar
```
