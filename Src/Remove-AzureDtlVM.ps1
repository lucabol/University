[cmdletbinding()]
param
(
    [Parameter(Mandatory=$true, HelpMessage="The name of the Dev Test Lab to clean up")]
    [string] $LabName,

    [Parameter(Mandatory=$true, HelpMessage="Which credential type to use (either File or Runbook)")]
    [string] $credentialsKind,

    [Parameter(Mandatory=$false, HelpMessage="Path to file with Azure Profile")]
    [string] $profilePath = "$env:APPDATA\AzProfile.txt"
)

try {
    . ./Common.ps1

    LogOutput "Start Removal"
    # Load the credentials
    LoadAzureCredentials $credentialsKind $profilePath

    # Used to disable progress bar when removing resource
    $notVerbose = $VerbosePreference -eq "SilentlyContinue"

    $ResourceGroupName = GetResourceGroupName $LabName
    LogOutput "Resource Group: $ResourceGroupName"

    $allVms = GetAllLabVMs $LabName $ResourceGroupName

    $jobs = @()

    $deleteVmBlock = {
        Param ($credentialsKind, $ProfilePath, $vmName, $resourceId, $notVerbose)
        $utils = Join-Path (Split-Path ($Script:MyInvocation.MyCommand.Path)) "ClassHelper.ps1"
        Write-Verbose $utils

        . $utils
        LogOutput "Deleting VM: $vmName"    
        if($notVerbose) {
            $ProgressPreference = "SilentlyContinue" # disable progress bar if not verbose
        }

        LoadAzureCredentials $credentialsKind $profilePath
        Remove-AzureRmResource -ResourceId $resourceId -ApiVersion 2016-05-15 -Force | Out-Null
        LogOutput "Completed deleting $vmName"    
    }

    # Iterate over all the VMs and delete any that we created
    foreach ($currentVm in $allVms){        
        $vmName = $currentVm.ResourceName

        LogOutput "Starting job to delete VM $vmName"
        $jobs += Start-Job -Name $vmName -ScriptBlock $deleteVmBlock -ArgumentList $credentialsKind,$profilePath, $vmName, $currentVm.ResourceId, $notVerbose
    }

    $result = @{}
    $result.statusCode = "Not Started"
    $result.statusMessage = "Delete VMs process pending execution"
    $result.Succeeded = @()
    $result.Failed = @()

    if($jobs.Count -ne 0) {
        $result.statusCode = "Started"
        $result.statusMessage = "VM Delete jobs pending completion"
        LogOutput "Waiting for VM Delete jobs to complete"
        Wait-Job -Job $jobs | Write-Verbose
        LogOutput "VM Deletion jobs have completed"

        foreach ($job in $jobs){
            try {
                $status = @{}
                $status.Name = $job.Name
                $status.State = $job.State
                if ($job.State -eq "Failed") {
                    $status.Details = (Get-Job -Id $job.Id).JobStateInfo.Reason
                    $result.Failed += $status
                } else {
                    Receive-Job $job | Write-Verbose
                    $status.Details = "Job Succeeded"
                    $result.Succeeded += $status
                }
            } catch {
                # Catch any exceptions, log them and add them as part of the "failed" jobs
                Write-Error "Caught an exception:"
                Write-Error "Exception Type: $($_.Exception.GetType().FullName)"
                Write-Error "Exception Message: $($_.Exception.Message)"
                $status.errorCode = $_.Exception.GetType().FullName
                $status.errorMessage = $_.Exception.Message
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
        Remove-Job -Job $jobs -Force
} else {
    $result.statusCode = "Skipped"
    $result.statusMessage = "No VMs to delete"
    LogOutput "No VMs to delete"
}

LogOutput "Status for VM deletion in lab $($LabName): $($result.statusCode)"
LogOutput "VMs Deleted: $($result.Succeeded.Count)"
LogOutput "VMs Failed to Delete: $($result.Failed.Count)"

LogOutput "Cleanup Process complete"


} finally {
    if($credentialsKind -eq "File") {
        1..3 | % { [console]::beep(2500,300) } # Make a sound to indicate we're done.
    }
    popd
}