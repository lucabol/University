[cmdletbinding()]
param 
(
    [Parameter(Mandatory=$false, HelpMessage="The path to the Deployment Template File ")]
    [string] $TemplatePath = ".\MultiVMCustomImageTemplate.json",

    [Parameter(Mandatory=$true, HelpMessage="Number of instances to create")]
    [int] $VMCount,

    [Parameter(Mandatory=$true, HelpMessage="Name of Lab")]
    [string] $LabName,

    [Parameter(Mandatory=$true, HelpMessage="Name of base image in lab")]
    [string] $BaseImage,

    [Parameter(Mandatory=$false, HelpMessage="Size of VM image")]
    [string] $ImageSize = "Standard_DS2",    

    [Parameter(Mandatory=$false, HelpMessage="Prefix for new VMs")]
    [string] $newVMName = "studentlabvm",

    [Parameter(Mandatory=$true, HelpMessage="Scheduled start time for class. In form of 'HH:mm'")]
    [string] $ClassStart,

    [Parameter(Mandatory=$true, HelpMessage="Time to live for VMs (in minutes)")]
    [int] $Duration,

    [Parameter(Mandatory=$false, HelpMessage="Path to file with Azure Profile")]
    [string] $profilePath = "$env:APPDATA\AzProfile.txt",

    [Parameter(Mandatory=$false, HelpMessage="How many VMs to create at a time")]
    [int] $batchSize = 10,

    [Parameter(Mandatory=$false, HelpMessage="How many times to retry when an error occurs")]
    [int] $retries = 3,

    [Parameter(Mandatory=$false, HelpMessage="Seconds between each batch deployment")]
    [int] $batchDelay = 0   
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
LoadProfile $profilePath

# Set the Subscription ID
$SubscriptionID = (Get-AzureRmContext).Subscription.SubscriptionId

$ResourceGroupName = (Find-AzureRmResource -ResourceType "Microsoft.DevTestLab/labs" -ResourceNameContains $LabName  | where ResourceName -CEQ "$LabName").ResourceGroupName

# Check to see if any VMs already exist in the lab. 
# Assume if ANY VMs exist then 
#   a) each VM is a VM for the class
#   b) has not been cleaned up 
#   thus the script should exit
# 
LogOutput "Checking for existing VMs in $LabName"
$existingVMs = (Find-AzureRmResource -ResourceType "Microsoft.DevTestLab/labs/virtualMachines" -ResourceGroupNameContains $ResourceGroupName | where ResourceName -CLike "$LabName/*").Count

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
$endTime = $startTime.AddMinutes($Duration).toString("HHmm")
LogOutput "Class Start Time: $($startTime)    Class End Time: $($endTime)"

# Calculate number of batches and reminder VMs
$numberOfBatches = [math]::floor($VMCount / $batchSize)
LogOutput "Number of batches: $numberOfBatches"
$remindervms = $VMCount % $batchSize
LogOutput "Reminder VMs: $remindervms"

$parameters = @{}
$parameters.Add("count",$batchSize)
$parameters.Add("labName",$LabName)
$parameters.Add("size", $ImageSize)
$parameters.Add("expirationDate", $ExpirationDate)
$parameters.Add("imageName", $BaseImage)
$parameters.Add("shutDownTime", $endTime)

# Create an alphabet array to create unique names for VMs in batches
$alph = @()
65..90 | foreach-object { $alph+=[char]$_ }
65..90 | foreach-object{
    $ch = [char]$_
    $alph += "$ch"
    $alph += "$ch$ch"
    $alph += "$ch$ch$ch"
    $alph += "$ch$ch$ch$ch"   
}
LogOutput $alph

# This simple nameing scheme works just for 103 batches top (consider you need one more for reminder VMs)
if($numberOfBatches -gt ((26 * 4) - 1)) {
    LogError "Lab $LabName contains $existingVMs existing VMs. Please clean up lab before creating new VMs"
    Exit 1    
}

# Iterate for the specified number of batches plus one for the reminder vms
for($i = 0; $i -lt $numberOfBatches + 1; $i++) {

    # If it's the last time through the loop just create reminderVMs
    if($i -eq $numberOfBatches) {
        $parameters["count"] = $remindervms
    }

    # deploy resources via template
    try {
        LogOutput "$i Starting Deployment $deploymentName for lab $LabName"
        $parameters["newVMName"] = $newVMName + $alph[$i]
        $strParams = $parameters | Out-String
        LogOutput "Params: $strParams"
        $deploymentName = "$deploymentName$i"
        LogOutput "Deployment Name: $deploymentName"
        LogOutput "Resource Group: $ResourceGroupName"

        $result.statusCode = "$i Started"
        $result.statusMessage = "$i Beginning template deployment"
        $vmDeployResult = New-AzureRmResourceGroupDeployment -Name $deploymentName -ResourceGroup $ResourceGroupName -TemplateFile $TemplatePath -TemplateParameterObject $parameters 
        Start-sleep -s $batchDelay
    } 
    catch {
        $result.errorCode = $_.Exception.GetType().FullName
        $result.errorMessage = $_.Exception.Message
        LogError "Exception: $($result.errorCode) Message: $($result.errorMessage)"
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

        $vmsCreated = ($result.Succeeded | Where-Object {$_.type -eq "Microsoft.DevTestLabs/labs/virtualmachines"}).Count
        $subResourcesCreated = ($result.Succeeded | Where-Object {$_.type -ne "Microsoft.DevTestLabs/labs/virtualmachines"}).Count
        
        LogOutput "$i Status for VM creation in lab $($LabName): $($result.statusCode)"
        LogOutput "$i Target VMs: $VMCount"
        LogOutput "$i VMs Succesfully created: $vmsCreated"
        LogOutput "$i VM Sub-Resources Succesfully created: $subResourcesCreated"
        LogOutput "$i VMs Failed: $($result.Failed.Count)"
        
    }
}

LogOutput "Process complete"
return $result