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

# Load the credentials
$Credential_Path =  Join-Path (Split-Path ($Script:MyInvocation.MyCommand.Path)) "creds.txt"
Write-Output "Credentials File: $Credential_Path"
if (! (Test-Path $Credential_Path)) {
    Write-Error "Credential files missing. Exiting script..."
    exit
}

Select-AzureRmProfile -Path $Credential_Path

# Set the Subscription ID
$SubscriptionIDPath = Join-Path (Split-Path ($Script:MyInvocation.MyCommand.Path)) "subID.txt"
Write-Output "Subscription ID File: $SubscriptionIDPath"
if (! (Test-Path $SubscriptionIDPath)) {
    Write-Error "Subscription ID file missing. Exiting script..."
    exit
}
$SubscriptionID = Get-Content -Path $SubscriptionIDPath
Write-Output "SubscriptionID: $SubscriptionID"
Select-AzureRmSubscription -SubscriptionId $SubscriptionID

# Check to see if any VMs already exist in the lab. 
# Assume if ANY VMs exist then 
#   a) each VM is a VM for the class
#   b) has not been cleaned up 
#   thus the script should exit
# 
#Write-Output "Checking for existing VMs in $LabName"
#$existingVMs = Find-AzureRmResource -ResourceType "Microsoft.DevTestLab/labs/virtualMachines" -ResourceNameContains $newVMName

# Set the expiration Date
$ExpirationDate = $UniversalDate.ToUniversalTime().AddDays(1).ToString("yyyy-MM-dd")
Write-Output "Expiration Date: $ExpirationDate"


Write-Output "Starting Deployment for lab $LabName"
$parameters = @{}
$parameters.Add("count",$VMCount)
$parameters.Add("labName",$LabName)
$parameters.Add("newVMName", $newVMName)
$parameters.Add("size", $ImageSize)
$parameters.Add("expirationDate", $ExpirationDate)
$parameters.Add("imageName", $BaseImage)

$ResourceGroupName = (Find-AzureRmResource -ResourceType "Microsoft.DevTestLab/labs" -ResourceNameContains $LabName).ResourceGroupName

# deploy resources via template
$vmDeployResult = New-AzureRmResourceGroupDeployment -Name "Deployment_$LabName" -ResourceGroup $ResourceGroupName -TemplateFile $TemplatePath -TemplateParameterObject $parameters

if ($vmDeployResult.ProvisioningState -eq "Succeeded") {
    Write-Output "Deployment completed successfully"   
}
else {
    Write-Error "##[error]Deploying VMs to lab $LabName failed"
}