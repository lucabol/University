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

# Used to disable progress bar when removing resource
$notVerbose = $VerbosePreference -eq "SilentlyContinue"

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
    Param ($ProfilePath, $vmName, $resourceId, $notVerbose)

    if($notVerbose) {
        $ProgressPreference = "SilentlyContinue" # disable progress bar if not verbose
    }
    Write-Verbose "Deleting VM: $vmName"
    Select-AzureRmProfile -Path $ProfilePath | Out-Null
    Remove-AzureRmResource -ResourceId $resourceId -ApiVersion 2016-05-15 -Force | Out-Null
    Write-Verbose "Completed deleting $vmName"
}

# Iterate over all the VMs and delete any that we created
foreach ($currentVm in $allVms){        
    $vmName = $currentVm.ResourceName
    Write-Verbose "Starting job to delete VM $vmName"

    $jobs += Start-Job -ScriptBlock $deleteVmBlock -ArgumentList $credentialPath, $vmName, $currentVm.ResourceId, $notVerbose   
}

if($jobs.Count -ne 0)
{
    try{
        Write-Verbose "Waiting for VM Delete jobs to complete"
        foreach ($job in $jobs){
            Receive-Job $job -Wait -Force | Write-Verbose
        }
    } catch {
        Write-Error “Caught an exception:” -ForegroundColor Red
        Write-Error “Exception Type: $($_.Exception.GetType().FullName)” -ForegroundColor Red
        Write-Error “Exception Message: $($_.Exception.Message)” -ForegroundColor Red                
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