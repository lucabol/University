[cmdletbinding()]
param
(
    [Parameter(Mandatory=$true, HelpMessage="The name of the Dev Test Lab to clean up")]
    [string] $LabName
)

# Stops at the first error instead of continuing and potentially messing up things
$global:erroractionpreference = 1

# Load the credentials
$Credential_Path =  Join-Path (Split-Path ($Script:MyInvocation.MyCommand.Path)) "creds.txt"
Write-Verbose "Credentials File: $Credential_Path"
if (! (Test-Path $Credential_Path)) {
    Write-Error "##[ERROR]Credential files missing. Exiting script..."
    exit
}
Select-AzureRmProfile -Path $Credential_Path | Out-Null

# Set the Subscription ID
$SubscriptionIDPath = Join-Path (Split-Path ($Script:MyInvocation.MyCommand.Path)) "subId.txt"
Write-Verbose "Subscription ID File: $SubscriptionIDPath"
if (! (Test-Path $SubscriptionIDPath)) {
    Write-Error "###[ERROR]Subscription ID file missing. Exiting script..."
    exit
}
$SubscriptionID = Get-Content -Path $SubscriptionIDPath
Select-AzureRmSubscription -SubscriptionId $SubscriptionID  | Out-Null

$allVms = Find-AzureRmResource -ResourceType "Microsoft.DevTestLab/labs/virtualMachines" -ResourceNameContains $LabName
$jobs = @()

$deleteVmBlock = {
    Param ($ProfilePath, $vmName, $resourceId)
    Write-Verbose "Deleting VM: $vmName"
    Select-AzureRmProfile -Path $ProfilePath | Out-Null
    Remove-AzureRmResource -ResourceId $resourceId -ApiVersion 2016-05-15 -Force | Out-Null
    Write-Verbose "Completed deleting $vmName"
}

# Iterate over all the VMs and delete any that we created
foreach ($currentVm in $allVms){        
    $vmName = $currentVm.ResourceName
    Write-Verbose "Starting job to delete VM $vmName"

    $jobs += Start-Job -ScriptBlock $deleteVmBlock -ArgumentList $Credential_Path, $vmName, $currentVm.ResourceId    
}

if($jobs.Count -ne 0)
{
    try{
        Write-Verbose "Waiting for VM Delete jobs to complete"
        foreach ($job in $jobs){
            Receive-Job $job -Wait | Write-Verbose
        }
    } catch {
        write-host “Caught an exception:” -ForegroundColor Red
        write-host “Exception Type: $($_.Exception.GetType().FullName)” -ForegroundColor Red
        write-host “Exception Message: $($_.Exception.Message)” -ForegroundColor Red                
    }
    finally{
        Remove-Job -Job $jobs
    }
}
else 
{
    Write-Verbose "No VMs to delete"
}

Write-Verbose "Cleanup complete"