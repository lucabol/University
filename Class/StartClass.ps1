[cmdletbinding()]
param 
(
    [Parameter(Mandatory=$false, HelpMessage="The path to the Deployment Template File ")]
    [string] $TemplatePath = ".\MultiVMCustomImageTemplate.json",

    # Instance Count
    [Parameter(Mandatory=$true, HelpMessage="Number of instances to create")]
    [int] $VMCount,

    # Lab Name
    [Parameter(Mandatory=$true, HelpMessage="Name of Lab")]
    [string] $LabName,

    # Base Image
    [Parameter(Mandatory=$true, HelpMessage="Name of base image in lab")]
    [string] $BaseImage,

    # Image Size
    [Parameter(Mandatory=$false, HelpMessage="Size of VM image")]
    [string] $ImageSize = "Standard_DS2",    

    # New VM name
    [Parameter(Mandatory=$false, HelpMessage="Prefix for new VMs")]
    [string] $newVMName = "studentlabvm"    
)

# Stops at the first error instead of continuing and potentially messing up things
#$global:erroractionpreference = 1
Write-Verbose "Begin Process"
$startTime = (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss")
$deploymentName = "Deployment_$LabName_$startTime"

# Load the credentials
$Credential_Path =  Join-Path (Split-Path ($Script:MyInvocation.MyCommand.Path)) "creds.txt"
Write-Verbose "Credentials File: $Credential_Path"
if (! (Test-Path $Credential_Path)) {
    # Fatal error encountered. Exit Script    
    Write-Error "Credential files missing. Exiting script..."
    exit 1
}

Select-AzureRmProfile -Path $Credential_Path | Out-Null

# Set the Subscription ID
$SubscriptionIDPath = Join-Path (Split-Path ($Script:MyInvocation.MyCommand.Path)) "subID.txt"
Write-Verbose "Subscription ID File: $SubscriptionIDPath"
if (! (Test-Path $SubscriptionIDPath)) {
    # Fatal error encountered. Log Error/Notify and Exit Script
    Write-Error "Subscription ID file missing. Exiting script..."
    exit 1    
}
$SubscriptionID = Get-Content -Path $SubscriptionIDPath
Select-AzureRmSubscription -SubscriptionId $SubscriptionID | Out-Null

# Do we need to check if the Subscription is correct selected?

# Check to see if any VMs already exist in the lab. 
# Assume if ANY VMs exist then 
#   a) each VM is a VM for the class
#   b) has not been cleaned up 
#   thus the script should exit
# 
Write-Verbose "Checking for existing VMs in $LabName"
$existingVMs = (Find-AzureRmResource -ResourceType "Microsoft.DevTestLab/labs/virtualMachines" -ResourceNameContains $newVMName).Count

if ($existingVMs -ne 0) {
    # Fatal error encountered. Log Error/Notify and Exit Script
    Write-Error "Lab $LabName contains $existingVMs existing VMs. Please clean up lab before creating new VMs"
    Exit 1
}

# Result object to return
$result = @{}

# Set the expiration Date
$UniversalDate = (Get-Date).ToUniversalTime()
$ExpirationDate = $UniversalDate.AddDays(1).ToString("yyyy-MM-dd")
Write-Verbose "Expiration Date: $ExpirationDate"

$parameters = @{}
$parameters.Add("count",$VMCount)
$parameters.Add("labName",$LabName)
$parameters.Add("newVMName", $newVMName)
$parameters.Add("size", $ImageSize)
$parameters.Add("expirationDate", $ExpirationDate)
$parameters.Add("imageName", $BaseImage)

$ResourceGroupName = (Find-AzureRmResource -ResourceType "Microsoft.DevTestLab/labs" -ResourceNameContains $LabName).ResourceGroupName

# deploy resources via template
try {
    Write-Verbose "Starting Deployment $deploymentName for lab $LabName"
    $vmDeployResult = New-AzureRmResourceGroupDeployment -Name $deploymentName -ResourceGroup $ResourceGroupName -TemplateFile $TemplatePath -TemplateParameterObject $parameters 
} 
catch {
    $result.errorCode = $_.Exception.GetType().FullName
    $result.errorMessage = $_.Exception.Message
}
finally {
    #Even if we got an error from the deployment call, get the deployment operation statuses for more invformation
    $ops = Get-AzureRmResourceGroupDeploymentOperation -DeploymentName $deploymentName -SubscriptionId $SubscriptionID -ResourceGroupName $ResourceGroupName
    
    $deploymentEval = ($ops | Where-Object {$_.properties.provisioningOperation -eq "EvaluateDeploymentOutput"}).Properties
    
    $result.statusCode = $deploymentEval.statusCode
    $result.statusMessage = $deploymentEval.statusMessage

    $failedtasks = @()
    $succeededtasks = @()

    # process each deployment operation. separate into succeeded and failed buckets    
    ($ops | Where-Object {$_.properties.provisioningOperation -ne "EvaluateDeploymentOutput"}).Properties | ForEach-Object {        
        $task = @{}
        $task.name = $_.targetResource.ResourceName
        $task.type = $_.targetResource.ResourceType
        $task.statusCode = $_.targetResource.statusCode
        $task.statusMessage= $_.targetResource.statusMessage
        if ($_.provisioningState -eq "Succeeded") {                
            $succeededtasks += $task
        } else {
            $failedtasks += $task
        }
    }

    $result.Succeeded = $succeededtasks
    $result.Failed = $failedtasks
    
    Write-Verbose "Status for VM creation in lab $($LabName): $($result.statusCode)"
    Write-Verbose "Target VMs: $VMCount"
    Write-Verbose "VMs Succesfully created: $($result.Succeeded.Count)"
    Write-Verbose "VMs Failed: $($result.Failed.Count)"
    
}

Write-Verbose "Process complete"
return $result