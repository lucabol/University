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
<<<<<<< HEAD
    [string] $newVMName = "studentlabvm"    ,

    # Start time for each "Session" to start
    [Parameter(Mandatory=$true, HelpMessage="Scheduled start time for class. In form of 'HH:mm'")]
    [string] $ClassStart,

    # Duration for each VM to "live" before shutting off
    [Parameter(Mandatory=$true, HelpMessage="Time to live for VMs (in minutes)")]
    [int] $TTL
=======
    [string] $newVMName = "studentlabvm",

    # Credential path
    [Parameter(Mandatory=$false, HelpMessage="Path to file with Azure credentials")]
    [string] $credentialPath = "$env:APPDATA\AzProfile.txt"
       
>>>>>>> master
)

$global:VerbosePreference = $VerbosePreference

$rootFolder = Split-Path ($Script:MyInvocation.MyCommand.Path)
Import-Module (Join-Path $rootFolder "ClassHelper.psm1")

# Stops at the first error instead of continuing and potentially messing up things
#$global:erroractionpreference = 1
LogOutput -msg "Begin Process" 
$startTime = (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss")
$deploymentName = "Deployment_$LabName_$startTime"

# Load the credentials
<<<<<<< HEAD
$Credential_Path = LoadCredentials

# Set the Subscription ID
$SubscriptionID = LoadSubscription

# Do we need to check if the Subscription is correctly selected?
=======
Write-Verbose "Credentials File: $credentialPath"
if (! (Test-Path $credentialPath)) {
    Write-Error "Credential files missing. Exiting script..."
    exit 1
}

Select-AzureRmProfile -Path $credentialPath | Out-Null
>>>>>>> master

# Check to see if any VMs already exist in the lab. 
# Assume if ANY VMs exist then 
#   a) each VM is a VM for the class
#   b) has not been cleaned up 
#   thus the script should exit
# 
LogOutput "Checking for existing VMs in $LabName"
$existingVMs = (Find-AzureRmResource -ResourceType "Microsoft.DevTestLab/labs/virtualMachines" -ResourceNameContains $newVMName).Count

if ($existingVMs -ne 0) {
    # Fatal error encountered. Log Error/Notify and Exit Script
    LogError "Lab $LabName contains $existingVMs existing VMs. Please clean up lab before creating new VMs"
    Exit 1
}

# Result object to return
$result = @{}
$result.statusCode = "Not Started"
$result.statusMessage = "Start class process pending execution"
$result.Failed = @()
$result.Succeeded = @()

# Set the expiration Date
$UniversalDate = (Get-Date).ToUniversalTime()
$ExpirationDate = $UniversalDate.AddDays(1).ToString("yyyy-MM-dd")
LogOutput "Expiration Date: $ExpirationDate"

# Set the shutdown time
$startTime = Get-Date $ClassStart
$endTime = $startTime.AddMinutes($TTL).toString("yyyyMMddHHmmss")
LogOutput "Class Start Time: $($startTime)    Class End Time: $($endTime)"

$parameters = @{}
$parameters.Add("count",$VMCount)
$parameters.Add("labName",$LabName)
$parameters.Add("newVMName", $newVMName)
$parameters.Add("size", $ImageSize)
$parameters.Add("expirationDate", $ExpirationDate)
$parameters.Add("imageName", $BaseImage)
$parameters.Add("shutDownTime", $endTime)

$ResourceGroupName = (Find-AzureRmResource -ResourceType "Microsoft.DevTestLab/labs" -ResourceNameContains $LabName).ResourceGroupName

# deploy resources via template
try {
    LogOutput "Starting Deployment $deploymentName for lab $LabName"
    $result.statusCode = "Started"
    $result.statusMessage = "Beginning template deployment"
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

    # process each deployment operation. separate into succeeded and failed buckets    
    ($ops | Where-Object {$_.properties.provisioningOperation -ne "EvaluateDeploymentOutput"}).Properties | ForEach-Object {        
        $task = @{}
        $task.name = $_.targetResource.ResourceName
        $task.type = $_.targetResource.ResourceType
        $task.statusCode = $_.targetResource.statusCode
        $task.statusMessage= $_.targetResource.statusMessage
        if ($_.provisioningState -eq "Succeeded") {                
            $result.Succeeded += $task
        } else {
            $result.Failed += $task
        }
    }    
    
    LogOutput "Status for VM creation in lab $($LabName): $($result.statusCode)"
    LogOutput "Target VMs: $VMCount"
    LogOutput "VMs Succesfully created: $($result.Succeeded.Count)"
    LogOutput "VMs Failed: $($result.Failed.Count)"
    
}

LogOutput "Process complete"
return $result