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
    LoadAzureCredentials -credentialsKind $credentialsKind -profilePath $profilePath

    # Used to disable progress bar when removing resource
    $notVerbose = $VerbosePreference -eq "SilentlyContinue"

    $ResourceGroupName = GetResourceGroupName -labname $LabName
    LogOutput "Resource Group: $ResourceGroupName"

    $allVms = GetAllLabVMs -labname $LabName -resourcegroupname $ResourceGroupName

    $jobs = @()

    $deleteVmBlock = {
        Param ($credentialsKind, $ProfilePath, $vmName, $resourceId, $notVerbose, $HelperPath)

        . $HelperPath

        if($notVerbose) {
            $ProgressPreference = "SilentlyContinue" # disable progress bar if not verbose
        }

        LoadAzureCredentials -credentialsKind $credentialsKind -profilePath $profilePath
        Remove-AzureRmResource -ResourceId $resourceId -ApiVersion 2016-05-15 -Force | Out-Null
    }

    $HelperPath = Join-Path (Split-Path ($Script:MyInvocation.MyCommand.Path)) "Common.ps1"
    LogOutput $HelperPath

    # Iterate over all the VMs and delete any that we created
    foreach ($currentVm in $allVms){        
        $vmName = $currentVm.ResourceName

        LogOutput "Starting job to delete VM $vmName"
        $jobs += Start-Job -Name $vmName -ScriptBlock $deleteVmBlock -ArgumentList $credentialsKind,$profilePath, $vmName, $currentVm.ResourceId, $notVerbose, $HelperPath
    }
    if($jobs.count -ne 0) {
        Wait-job -Job $jobs -Force | Write-Verbose
        LogOutput "VM Deletion jobs have completed"
    } else {
        LogOutput "No VMs to delete."
    }

} finally {
    if($credentialsKind -eq "File") {
        1..3 | % { [console]::beep(2500,300) } # Make a sound to indicate we're done.
    }
    popd
}