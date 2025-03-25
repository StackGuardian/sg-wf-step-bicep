#!/usr/bin/env bash

set -e

log_date() {
  printf "[%s]" "$(date +'%Y-%m-%dT%H:%M:%S%z')"
}

err() {
  printf "\n--- ERROR ---"
  printf "\n\u001b[38;5;196m%s" "$1" >&2
  printf "\n_____________\n"
  exit 1
}

info() {
  printf "\n--- INFO ---"
  printf "\n\u001b[32m%s" "$1"
  printf "\n____________\n"
}

debug() { #{{{
  printf "\n[SG_DEBUG] %s\n" "$1"
}

warn() {
  printf "\n--- WARNING ---"
  printf "\n\u001b[33m%s\u001b[0m" "$1"
  printf "\n_______________\n"
}

print_cmd() {
  printf "\n--- COMMAND ---"
  printf "\n\u001b[33m%s" "$1"
  printf "\n_______________\n"
}

parse_variables() {
  # templateFile refers to the Azure Bicep template file
  templateFile="${LOCAL_IAC_SOURCE_CODE_DIR%/}"
  workflowStepInputParams=$(echo "${BASE64_WORKFLOW_STEP_INPUT_VARIABLES}" | base64 -d -i -)
  mountedArtifactsDir="${LOCAL_ARTIFACTS_DIR}"
  # BASE64_IAC_INPUT_VARIABLES
  workflowIACInputVariables=$(echo "${BASE64_IAC_INPUT_VARIABLES}" | base64 -d -i -)
}

# Function to handle Azure login and validation
azure_login() {
  info "Authenticating with Azure CLI"
  # Check if all required Azure environment variables are set
  if [[ -z "${ARM_CLIENT_ID}" || -z "${ARM_CLIENT_SECRET}" ||
    -z "${ARM_TENANT_ID}" || -z "${ARM_SUBSCRIPTION_ID}" ]]; then
    err "One or more Azure environment variables are missing (ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID)"
  fi

  # Log in to Azure using a service principal
  az login --service-principal -u "${ARM_CLIENT_ID}" -p "${ARM_CLIENT_SECRET}" --tenant "${ARM_TENANT_ID}" &>/dev/null
  if [[ $? -ne 0 ]]; then
    err "Failed to authenticate with Azure. Please check your Cloud Connector configuration."
  fi

  # Set the Azure subscription context
  az account set --subscription "${ARM_SUBSCRIPTION_ID}" &>/dev/null
}

# # Function to create a resource group if it doesn't exist
# create_resource_group() {
#   local resourceGroup=$1
#   local location=$2
#   # Check if the resource group exists and create it if not
#   if ! az group exists --name "${resourceGroup}" >/dev/null 2>&1; then
#     info "Creating resource group ${resourceGroup} in ${location}"
#     az group create --name "${resourceGroup}" --location "${location}" >/dev/null 2>&1
#   else
#     info "Resource group ${resourceGroup} exists. Using existing resource group ${resourceGroup}."
#   fi
# }

# Helper function to build deployment command
build_az_command() {
  local base_cmd="$1"
  local output_file="values-iac-json-input.json"

  # If input variables exist, process and add them to the command
  if [[ -n "${workflowIACInputVariables}" ]]; then
    echo "${workflowIACInputVariables}" | jq 'to_entries | reduce .[] as $item ({}; . + {($item.key): {"value": $item.value}})' >"${output_file}"
    base_cmd="${base_cmd} --parameters @${output_file}"
  fi

  # Append additional parameters if provided
  if [[ -n "${additionalParameters}" && "${additionalParameters}" != "null" ]]; then
    base_cmd="${base_cmd} ${additionalParameters}"
  fi

  echo "${base_cmd}"
}

# Function to process and merge JSON parts into sg.workflow_run_facts.json
process_json_part() {
  local jsonOutput="$1"
  local jsonKey="$2"
  local filePath="${mountedArtifactsDir}/sg.workflow_run_facts.json"

  # Validate JSON output
  if [[ -z "$jsonOutput" || "$jsonOutput" == "[]" ]] || ! jq -e . <<<"$jsonOutput" >/dev/null 2>&1; then
    debug "Skipping update: No valid JSON data for '${jsonKey}'."
    return
  fi

  # Ensure the JSON file exists and is valid; otherwise, initialize as '{}'
  if [ ! -f "$filePath" ] || [ ! -s "$filePath" ] || ! jq -e . "$filePath" >/dev/null 2>&1; then
    echo "{}" >"$filePath"
  fi

  # Update JSON file with new key-value pair
  if jq --arg key "$jsonKey" --argjson newValue "$jsonOutput" '.[$key] = $newValue' "$filePath" >"${filePath}.tmp"; then
    mv "${filePath}.tmp" "$filePath"
    debug "Successfully stored JSON under '${jsonKey}' in '${filePath}'"
  else
    debug "Error: Failed to update JSON file."
    rm -f "${filePath}.tmp"
  fi
}

# Function to retrieve deployment outputs
retrieve_deployment_outputs() {
  local resourceGroup=$1
  local deploymentName=$2
  local mountedArtifactsDir=$3
  local deploymentScope=$4
  local outputsFile="${mountedArtifactsDir}/sg.outputs.json"

  # Initialize JSON array
  resources='[]'

  # Get deployment outputs and store them in sg.outputs.json
  debug "Retrieving deployment outputs"
  if [[ "${deploymentScope}" == "sub" ]]; then
    outputs=$(az deployment sub show --name "$deploymentName" --query 'properties.outputs' -o json)
    if [[ $? -ne 0 ]]; then
      err "Error: Failed to retrieve group deployment outputs. Ensure the deployment name ('$deploymentName') is correctly specified in the Workflow Step input and that the resource group ('$resourceGroup') is set correctly in the ARM_RESOURCE_GROUP environmental variable."
    fi
    resourceIds=$(az deployment sub show \
      --name "$deploymentName" \
      --query 'properties.outputResources[].id' \
      -o tsv)

    if [[ $? -ne 0 ]]; then
      err "Failed to get sub deployment resources. Check for a valid deployment name in the Workflow Step inputs: '$deploymentName'"
    fi

    # Ensure resourceIds is not empty
    if [[ -z "$resourceIds" ]]; then
      debug "No resources found in deployment $deploymentName."
    else
      # Process each resource ID
      while IFS= read -r resourceId; do
        # Get resource details and create JSON object
        resource_data=$(az resource show --ids "$resourceId" \
          --query "{id: id, properties: properties}" -o json)

        # Add to array using jq
        resources=$(jq --argjson data "$resource_data" '. += [$data]' <<<"$resources")
      done <<<"$resourceIds"
    fi
  elif [[ "${deploymentScope}" == "group" ]]; then
    outputs=$(az deployment group show --resource-group "$resourceGroup" --name "$deploymentName" --query 'properties.outputs' -o json)
    if [[ $? -ne 0 ]]; then
      err "Error: Failed to retrieve group deployment outputs. Ensure the deployment name ('$deploymentName') is correctly specified in the Workflow Step input and that the resource group ('$resourceGroup') is set correctly in the ARM_RESOURCE_GROUP environmental variable."
    fi
    resourceIds=$(az deployment group show \
      --resource-group "$resourceGroup" \
      --name "$deploymentName" \
      --query 'properties.outputResources[].id' \
      -o tsv)

    if [[ $? -ne 0 ]]; then
      err "Failed to get sub deployment resources. Check for a valid deployment name in the Workflow Step inputs: '$deploymentName'"
    fi

    # Ensure resourceIds is not empty
    if [[ -z "$resourceIds" ]]; then
      debug "No resources found in deployment $deploymentName."
    else
      # Process each resource ID
      while IFS= read -r resourceId; do
        # Get resource details and create JSON object
        resource_data=$(az resource show --ids "$resourceId" \
          --query "{id: id, properties: properties}" -o json)

        # Add to array using jq
        resources=$(jq --argjson data "$resource_data" '. += [$data]' <<<"$resources")
      done <<<"$resourceIds"
    fi
  else
    err "Invalid Deployment Scope in the Workflow Step inputs: '$deploymentScope'. Scope must be either 'sub' or 'group'."
  fi

  # Store the modified output in the outputs file
  echo $outputs
  echo "$outputs" >"$outputsFile"

  if [[ $? -ne 0 ]]; then
    debug "Failed to store outputs to '$outputsFile'."
  else
    debug "Successfully stored deployment outputs in '${outputsFile}'."
  fi

  # Get deployment resources and store them in sg.workflow_run_facts.json under BicepResources
  if [[ -n "$resources" && "$resources" != "[]" && $(
    jq empty <<<"$resources" 2>/dev/null
    echo $?
  ) -eq 0 ]]; then
    process_json_part "$resources" "BicepResources"
  else
    debug "No valid resources to process for BicepResources."
  fi

  # # Get deployment properties and store them in sg.workflow_run_facts.json under BicepProperties
  # TODO: Review
  # properties=$(az deployment group show --resource-group "$resourceGroup" --name "$deploymentName" --query 'properties' -o json)
  # process_json_part "$properties" "BicepProperties"
}

# Main function to deploy the resources
main() {
  # Parse input variables
  parse_variables

  # Extract parameters from input JSON
  deploymentScope=$(echo "${workflowStepInputParams}" | jq -r '.deploymentScope')
  resourceGroup=${ARM_RESOURCE_GROUP}
  subscriptionId=${ARM_SUBSCRIPTION_ID}
  location=$(echo "${workflowStepInputParams}" | jq -r '.location')
  deploymentName=$(echo "${workflowStepInputParams}" | jq -r '.deploymentName')
  deploymentMode=$(echo "${workflowStepInputParams}" | jq -r '.deploymentMode')
  additionalParameters=$(echo "${workflowStepInputParams}" | jq -r '.additionalParameters')

  # Validate required parameters
  if [[ -d "${templateFile}" ]]; then
    err "The specified template path '${templateFile}' is a directory. Please specify the Bicep file within the Working Directory configuration of the template or Git Repository as the support for the Template File parameter is removed. This might have worked with an older version of the Bicep workflow step template."
  elif [[ ! -f "${templateFile}" ]]; then
    err "Bicep file '${templateFile}' does not exist or is not a valid file."
  fi
  [[ -z "${resourceGroup}" ]] && [[ "${deploymentScope}" == "group" ]] && err "ARM_RESOURCE_GROUP is not passed as an environment variable in the Workflow Settings."
  [[ -z "${subscriptionId}" ]] && err "Subscription ID from the Cloud Connector cannot be read. Please make sure that the Cloud Connector is correctly passed."

  # Set default values for optional parameters
  deploymentMode=${deploymentMode:-"Incremental"}
  additionalParameters="${additionalParameters:-""}"

  # Get the current timestamp
  timestamp=$(date +%s)
  # Set deploymentName with a default value if it's not already defined
  deploymentName=${deploymentName:-"sg-deployment-$timestamp"}

  # Log in to Azure
  azure_login

  # # Create resource group if it doesn't exist
  # create_resource_group "${resourceGroup}" "${location}"

  # Preview the deployment if the mode is 'what-if'
  if [[ "${deploymentMode}" == "What-if" ]]; then
    info "Previewing deployment with what-if"
    if [[ "${deploymentScope}" == "sub" ]]; then
      whatIfCmdBase="az deployment sub what-if --location ${location} --template-file ${templateFile}"
    else
      whatIfCmdBase="az deployment group what-if --resource-group ${resourceGroup} --template-file ${templateFile}"
    fi
    whatIfcmd=$(build_az_command "${whatIfCmdBase}")
    print_cmd "${whatIfcmd}"
    ${whatIfcmd}
    return
  fi

  # Execute the deployment
  info "Starting deployment"
  if [[ "${deploymentScope}" == "sub" ]]; then
    deployCmdBase="az deployment sub create --name ${deploymentName} --location ${location} --template-file ${templateFile}"
  else
    deployCmdBase="az deployment group create --name ${deploymentName} --resource-group ${resourceGroup} --template-file ${templateFile} --mode ${deploymentMode}"
  fi
  cmd=$(build_az_command "${deployCmdBase}")
  # Print and execute the command
  print_cmd "${cmd}"
  ${cmd}
  #TODO: Check if the deployment was successful or if there was an error, get the error message and exit with an error code
  # Example: ERROR: {"status":"Failed","error":{"code":"DeploymentFailed","target":"/subscriptions/43434343-343434-344343-3434-34343344/resourceGroups/rg-stack-1/providers/Microsoft.Resources/deployments/SG-KeyVault","message":"At least one resource deployment operation failed. Please list deployment operations for details. Please see https://aka.ms/arm-deployment-operations for usage details.","details":[{"code":"ResourceDeploymentFailure","target":"/subscriptions/xxxx-xxx-xxx-xxx-xxxx/resourceGroups/rg-stack-dev-01/providers/Microsoft.Resources/deployments/Deploy-KeyVault-stack-dev-we-001","message":"The resource write operation failed to complete successfully, because it reached terminal provisioning state 'Failed'.","details":[{"code":"DeploymentFailed","target":"/subscriptions/xxxx-xxxx-xxxx-xxxx-xxxxxx/resourceGroups/rg-stack-infra-dev-01/providers/Microsoft.Resources/deployments/Deploy-KeyVault","message":"At least one resource deployment operation failed. Please list deployment operations for details. Please see https://aka.ms/arm-deployment-operations for usage details.","details":[{"code":"ConflictError","message":"A vault with the same name already exists in deleted state. You need to either recover or purge existing key vault. Follow this link https://go.microsoft.com/fwlink/?linkid=2149745 for more information on soft delete."}]}]}]}}
  # Call the function to retrieve and save deployment outputs
  retrieve_deployment_outputs "${resourceGroup}" "${deploymentName}" "${mountedArtifactsDir}" "${deploymentScope}"
}

main "$@"
