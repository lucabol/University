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
#$global:erroractionpreference = 1
$global:VerbosePreference = $VerbosePreference

$HelperModule = Join-Path (Split-Path ($Script:MyInvocation.MyCommand.Path)) "ClassHelper.psm1"
Import-Module $HelperModule

# Load the credentials
$CredentialsPath = LoadCredentials
$SubscriptionID = LoadSubscription

# Used to disable progress bar when removing resource
$notVerbose = $VerbosePreference -eq "SilentlyContinue"

$allVms = Find-AzureRmResource -ResourceType "Microsoft.DevTestLab/labs/virtualMachines" -ResourceNameContains $LabName
$jobs = @()

$deleteVmBlock = {
    Param ($ProfilePath, $vmName, $resourceId, $notVerbose, $HelperModule)
    Import-Module $HelperModule
    LogOutput "Deleting VM: $vmName"    
    if($notVerbose) {
        $ProgressPreference = "SilentlyContinue" # disable progress bar if not verbose
    }    
    Select-AzureRmProfile -Path $ProfilePath | Out-Null
    Remove-AzureRmResource -ResourceId $resourceId -ApiVersion 2016-05-15 -Force | Out-Null
    LogOutput "Completed deleting $vmName"
}

# Iterate over all the VMs and delete any that we created
foreach ($currentVm in $allVms){        
    $vmName = $currentVm.ResourceName
    LogOutput "Starting job to delete VM $vmName"
    $jobs += Start-Job -Name $vmName -ScriptBlock $deleteVmBlock -ArgumentList $CredentialsPath, $vmName, $currentVm.ResourceId, $notVerbose, $HelperModule
}

$result = @{}
$result.statusCode = "Not Started"
$result.statusMessage = "Delete VMs process pending execution"
$result.Succeeded = @()
$result.Failed = @()

if($jobs.Count -ne 0) {
    try{
        $result.statusCode = "Started"
        $result.statusMessage = "VM Delete jobs pending completion"
        LogOutput "Waiting for VM Delete jobs to complete"
        foreach ($job in $jobs){
            Receive-Job $job -Wait -Force | Write-Verbose
        }
    } catch {
        LogError "Caught an exception:" -ForegroundColor Red
        LogError "Exception Type: $($_.Exception.GetType().FullName)" -ForegroundColor Red
        LogError "Exception Message: $($_.Exception.Message)" -ForegroundColor Red                
        $result.statusCode = "Failed"
        $result.statusMessage = "$($_.Exception.Message)"
    }
    finally{
        Get-Job | ForEach-Object {
            $status = @{}
            $status.Name = $_.Name
            $status.State = $_.State
            if ($_.State -eq "Completed") {
                $status.Details = "Job Succeeded"
                $result.Succeeded += $status
            } else {
                $status.Details = (Get-Job -Name $_.Name).JobStateInfo.Reason
                $result.Failed += $status
            }
        }
        if ($result.Failed.Count -gt 0) {
            $result.statusCode = "Failed"
            $result.statusMessage = "One or more VMs were not successfully deleted. Please see details for each job to for more information"
        } else {
            $result.statusCode = "Success"
            $result.statusMessage = "VMs successfully deleted"
        }
        Remove-Job -Job $jobs        
    }
} else {
    $result.statusCode = "Skipped"
    $result.statusMessage = "No VMs to delete"
    LogOutput "No VMs to delete"
}

LogOutput "Status for VM deletion in lab $($LabName): $($result.statusCode)"
LogOutput "VMs Deleted: $($result.Succeeded.Count)"
LogOutput "VMs Failed to Delete: $($result.Failed.Count)"

LogOutput "Cleanup Process complete"

return $result