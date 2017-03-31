[cmdletbinding()]
param
(
    [Parameter(Mandatory=$true, HelpMessage="The name of the Dev Test Lab to clean up")]
    [string] $LabName,

    [Parameter(Mandatory=$true, HelpMessage="Which credential type to use (either File or Runbook)")]
    [string] $credentialsKind,

    [Parameter(Mandatory=$false, HelpMessage="Path to file with Azure Profile")]
    [string] $profilePath = "$env:APPDATA\AzProfile.txt",

    [Parameter(Mandatory=$false, HelpMessage="How many VMs to delete in parallel")]
    [string] $parallelDeletion = 20
    
)

try {
    if ($credentialsKind -eq "File"){
        . "./Common.ps1"
    }

    LogOutput "Start Removal"

    LoadAzureCredentials -credentialsKind $credentialsKind -profilePath $profilePath

    # Used to disable progress bar when removing resource
    $notVerbose = $VerbosePreference -eq "SilentlyContinue"

    $ResourceGroupName = GetResourceGroupName -labname $LabName
    LogOutput "Resource Group: $ResourceGroupName"

    [array] $allVms = GetAllLabVMs -labname $LabName -resourcegroupname $ResourceGroupName

    $HelperPath = Join-Path (Split-Path ($Script:MyInvocation.MyCommand.Path)) "Common.ps1"
    LogOutput $HelperPath

    # Then delete all the vms in parallel
    $deleteVmBlock = {
        Param ($credentialsKind, $ProfilePath, $vmName, $resourceId, $notVerbose, $HelperPath)

        . $HelperPath

        if($notVerbose) {
            $ProgressPreference = "SilentlyContinue" # disable progress bar if not verbose
        }

        LoadAzureCredentials -credentialsKind $credentialsKind -profilePath $profilePath
        Write-Host "Deleting VM $resourceId"
        Remove-AzureRmResource -ResourceId $resourceId -ApiVersion 2016-05-15 -Force | Out-Null
    }

    $vmcount = $allVms.Length
    $loops = [math]::Floor($vmcount / $parallelDeletion)
    $rem = $vmcount - $loops * $parallelDeletion
    LogOutput "VMCount: $vmcount, Loops: $loops, Rem: $rem"
    LogOutput "Vms: $allVms"

    $vmiter = 0
    for($i = 0; $i -lt $loops + 1; $i++) {

        $jobs = @()
        for($j = 0; $j -lt $parallelDeletion; $j++) {
            if($vmiter -ge $vmCount) {
                break
            }
            $currentVm = $allVms[$vmiter]
            $vmName = $currentVm.ResourceName
            LogOutput "Starting job to delete VM $vmName"

            $jobs += Start-Job -Name $vmName -ScriptBlock $deleteVmBlock -ArgumentList $credentialsKind,$profilePath, $vmName, $currentVm.ResourceId, $notVerbose, $HelperPath
            $vmiter = $vmiter + 1
        }

        if($jobs.count -ne 0) {
            Wait-job -Job $jobs -Force | Write-Verbose
            LogOutput "Batch: $i completed"
            foreach($job in $grjobs) {
                Receive-Job $job | LogOutput
            }
        } else {
            LogOutput "No VMs to delete."
        }
    }

} finally {
    if($credentialsKind -eq "File") {
        1..3 | % { [console]::beep(2500,300) } # Make a sound to indicate we're done.
    }
    popd
}