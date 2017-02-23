[cmdletbinding()]
param
(
    [Parameter(Mandatory=$true, HelpMessage="The name of the Dev Test Lab to clean up")]
    [string] $LabName,

    # Credential path
    [Parameter(Mandatory=$false, HelpMessage="Path to file with Azure credentials")]
    [string] $credentialPath = "$env:APPDATA\AzProfile.txt"
)

# Stops at the first error instead of continuing and potentially messing up things
$global:erroractionpreference = 1

# Disable progress bar if Verbose was not passed in. need to test
if($VerbosePreference -eq "SilentlyContinue") {
    $ProgressPreference = "SilentlyContinue"
}

# Load the credentials
Write-Verbose "Credentials File: $credentialPath"
if (! (Test-Path $credentialPath)) {
    Write-Error "##[ERROR]Credential files missing. Exiting script..."
    exit
}
Select-AzureRmProfile -Path $credentialPath | Out-Null

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

    $jobs += Start-Job -ScriptBlock $deleteVmBlock -ArgumentList $credentialPath, $vmName, $currentVm.ResourceId    
}

if($jobs.Count -ne 0)
{
    try{
        Write-Verbose "Waiting for VM Delete jobs to complete"
        foreach ($job in $jobs){
            Receive-Job $job -Wait -Force | Write-Verbose
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