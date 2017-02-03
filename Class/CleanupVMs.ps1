param
(
    [Parameter(Mandatory=$true, HelpMessage="The name of the Dev Test Lab resource group")]
    [string] $ResourceGroupName,

    [Parameter(Mandatory=$true, HelpMessage="The name of the Dev Test Lab to clean up")]
    [string] $LabName
)

# Load the credentials
$Credential_Path =  Join-Path (Split-Path ($Script:MyInvocation.MyCommand.Path)) "creds.txt"
Write-Output "Credentials File: " $Credential_Path
if (! (Test-Path $Credential_Path)) {
    Write-Error "##[ERROR]Credential files missing. Exiting script..."
    exit
}

Select-AzureRmProfile -Path $Credential_Path

# Set the Subscription ID
$SubscriptionIDPath = Join-Path (Split-Path ($Script:MyInvocation.MyCommand.Path)) "subId.txt"
Write-Output "Subscription ID File: " $SubscriptionIDPath
if (! (Test-Path $SubscriptionIDPath)) {
    Write-Error "##[ERROR]Subscription ID file missing. Exiting script..."
    exit
}
$SubscriptionID = Get-Content -Path $SubscriptionIDPath
Write-Output "SubscriptionID: " $SubscriptionID
Select-AzureRmSubscription -SubscriptionId $SubscriptionID

$allVms = Find-AzureRmResource -ResourceType "Microsoft.DevTestLab/labs/virtualMachines" -ResourceNameContains $LabName
$jobs = @()

$deleteVmBlock = {
    Param ($ProfilePath, $vmName, $resourceId)
    Write-Output "Deleting VM: $vmName"
    Select-AzureRmProfile -Path $ProfilePath | Out-Null
    Remove-AzureRmResource -ResourceId $resourceId -ApiVersion 2016-05-15 -Force
    Write-Output "Completed deleting $vmName"
}

# Iterate over all the VMs and delete any that we created
foreach ($currentVm in $allVms){        
    $vmName = $currentVm.ResourceName
    $provisioningState = (Get-AzureRmResource -ResourceId $currentVm.ResourceId).Properties.ProvisioningState

    Write-Output "Starting job to delete VM $vmName"
    $jobs += Start-Job -ScriptBlock $deleteVmBlock -ArgumentList $Credential_Path, $vmName, $currentVm.ResourceId    
}

if($jobs.Count -ne 0)
{
    try{
        Write-Output "Waiting for VM Delete jobs to complete"
        foreach ($job in $jobs){
            Receive-Job $job -Wait | Write-Output
        }
    }
    finally{
        Remove-Job -Job $jobs
    }
}
else 
{
    Write-Output "No VMs to delete"
}

Write-Output "Cleanup complete"