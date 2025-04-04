# StackGuardian Workflow Step for Bicep

## Overview

The **Bicep Workflow Step** enables users to deploy Azure resources via Bicep templates using Azure CLI. This step is designed to automate the deployment process, ensuring that users can configure their deployment easily through the SG noCode, without needing to manually write or execute Bicep commands.

This workflow step works in conjunction with the **Azure Connector** in StackGuardian, which manages the authentication towards the targetted Azure environment.

---

## Step 1: Azure Authentication via Connector

Before deploying Azure resources, you must configure **Azure authentication** through StackGuardian's connector of kind **Azure**. The **Azure Connector** facilitates the secure connection to your Azure account, allowing StackGuardian to interact with your Azure resources on your behalf.

For detailed instructions on how to set up the Azure connector, refer to the official documentation: [Connect Azure with StackGuardian](https://docs.qa.stackguardian.io/docs/connectors/csp/azure/)

Once authentication is configured, StackGuardian will use these credentials to authorize and perform actions like deploying Bicep templates or managing Azure resources.

---

## Step 2: Configuration of the Bicep Workflow Step

The **Bicep Workflow Step** allows users to define their Azure deployment through a user-friendly form. The following configuration options will be presented based on the JSON Schema in your StackGuardian Workflow.

### 1. **Template File (`templateFile`)**

   - **Description**: Bicep Template File field is deprecated and will be permanently removed! Please specify the Bicep file path in the 'Working Directory' configuration of the template or Git Repository instead.

### 2. **Deployment Scope (`deploymentScope`)**

   - **Description**: The scope at which to deploy the Bicep template
   - **Type**: String
   - **Required**: Yes
   - **Options**:
     - **Subscription**: Deploy at subscription level (subscription ID retrieved from selected Cloud Connector)
     - **Resource Group**: Deploy at resource group level (resource group name must be provided via ARM_RESOURCE_GROUP environment variable in workflow settings)

### 3. **Deployment Mode (`deploymentMode`)**

   - **Description**: Specifies how resources should be deployed (required only when Deployment Scope is Resource Group)
   - **Type**: String
   - **Options**:
     - **Incremental**: Only new or modified resources will be deployed
     - **Complete**: Existing resources not in the template will be deleted
     - **What-if**: Simulates the deployment without making changes

### 4. **Azure Region (`location`)**

   - **Description**: The Azure region where the deployment will be executed. This is required when deploymentScope is Subscription.
   - **Type**: String
   - **Example Values**: 'eastus', 'westus2', 'centralus', 'northeurope', 'westeurope', 'germanywestcentral', 'germanynorth'

### 5. **Deployment Name (`deploymentName`)**

   - **Description**: An optional name for the deployment. If not provided, Azure will generate a default name.
   - **Type**: String
   - **Required**: No

### 6. **Additional Parameters (`additionalParameters`)**

   - **Description**: Additional parameters to append to the az deployment command.
   - **Type**: String
   - **Required**: No
   - **Example**: `"--debug"`

## Notes and Best Practices

1. Use the "What-if" deployment mode first to validate your changes before applying them.
2. Consider using "Incremental" mode for production deployments unless you specifically need to enforce a complete state match.
3. When deploying at Resource Group scope, ensure the ARM_RESOURCE_GROUP environment variable is set in workflow settings.
4. For subscription-level deployments, make sure to specify the target Azure region.

## Creating Your Own Workflow Step

For detailed instructions on how to create and customize your own workflow steps in StackGuardian, please refer to our [Workflow Steps Documentation](https://docs.stackguardian.io/docs/develop/library/workflow_step/). This will guide you through the process of creating and  integrating custom workflow steps into your StackGuardian Workflows.

## Configuring a StackGuardian Workflow

To create a workflow using this step, you can use the StackGuardian Workflow as Code feature. For more details on configuring workflows as code, refer to the [official documentation](https://docs.stackguardian.io/docs/deploy/workflows/create_workflow/json/#using-workflow-as-code).

### Example Workflow Configuration

```json
{
  "Approvers": [],
  "DeploymentPlatformConfig": [
    {
      "config": {
        "profileName": "Azure-Example",
        "integrationId": "/integrations/Azure-Example"
      },
      "kind": "AZURE_STATIC"
    }
  ],
  "WfType": "CUSTOM",
  "EnvironmentVariables": [
    {
      "config": {
        "textValue": "example-resource-group",
        "varName": "ARM_RESOURCE_GROUP"
      },
      "kind": "PLAIN_TEXT"
    }
  ],
  "VCSConfig": {
    "iacVCSConfig": {
      "useMarketplaceTemplate": false,
      "customSource": {
        "sourceConfigDestKind": "GITHUB_COM",
        "config": {
          "includeSubModule": false,
          "ref": "main",
          "gitCoreAutoCRLF": false,
          "auth": "/integrations/github_com",
          "workingDir": "main.bicep",
          "repo": "https://github.com/example/storageaccount",
          "isPrivate": true
        }
      }
    },
    "iacInputData": {
      "schemaType": "RAW_JSON",
      "data": {
        "storageAccount": "examplestorageaccount"
      }
    }
  },
  "Tags": [],
  "UserJobCPU": 512,
  "UserJobMemory": 1024,
  "RunnerConstraints": {
    "type": "shared"
  },
  "Description": "Example workflow for deploying Azure resources",
  "ResourceName": "deploy-storage-account",
  "WfStepsConfig": [
    {
      "name": "bicep",
      "mountPoints": [],
      "wfStepTemplateId": "/stackguardian/Bicep:3",
      "wfStepInputData": {
        "schemaType": "FORM_JSONSCHEMA",
        "data": {
          "resourceGroup": "example-resource-group",
          "deploymentMode": "Incremental",
          "location": "westeurope",
          "deploymentName": "storage-deployment",
          "deploymentScope": "group",
          "subscriptionId": "example-subscription"
        }
      },
      "approval": false,
      "timeout": 2100
    }
  ]
}
```

This JSON payload defines a workflow that deploys an Azure storage account using a Bicep template. It includes:
- **Deployment platform configuration**: Defines the Azure Cloud Connector.
- **VCS configuration**: Links the workflow to a GitHub repository.
- **Workflow steps**: Configures the Bicep deployment with necessary parameters.

For more advanced configurations and additional parameters, visit the [StackGuardian documentation](https://docs.stackguardian.io/docs/deploy/workflows/create_workflow/json/#using-workflow-as-code).
