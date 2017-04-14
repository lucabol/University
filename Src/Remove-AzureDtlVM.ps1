[cmdletbinding()]
param
(
    [Parameter(Mandatory=$true, HelpMessage="The name of the Dev Test Lab to clean up")]
    [string] $LabName,

    [Parameter(Mandatory=$false, HelpMessage="Path to file with Azure Profile")]
    [string] $profilePath = "$env:APPDATA\AzProfile.txt",

    [Parameter(Mandatory=$false, HelpMessage="How many VMs to delete in parallel")]
    [string] $parallelDeletion = 10
    
)

try {

    if($PSPrivateMetadata.JobId) {
        $credentialsKind = "Runbook"
        $HelperPath = ""
    }
    else {
        $credentialsKind =  "File"
    }
    Write-Verbose "Credentials: $credentialsKind"

    if ($credentialsKind -eq "File"){
        . "./Common.ps1"
        $HelperPath = Join-Path (Split-Path ($Script:MyInvocation.MyCommand.Path)) "Common.ps1"
        LogOutput $HelperPath
    }

    LogOutput "Start Removal"

    LoadAzureCredentials -credentialsKind $credentialsKind -profilePath $profilePath

    # Used to disable progress bar when removing resource
    $notVerbose = $VerbosePreference -eq "SilentlyContinue"

    $ResourceGroupName = GetResourceGroupName -labname $LabName
    LogOutput "Resource Group: $ResourceGroupName"

    [array] $allVms = GetAllLabVMs -labname $LabName

    # Then delete all the vms in parallel
    $deleteVmBlock = {
        Param ($credentialsKind, $ProfilePath, $vmName, $resourceId, $notVerbose, $HelperPath)

        if ($credentialsKind -eq "File"){
            . $HelperPath
        }

        if($notVerbose) {
            $ProgressPreference = "SilentlyContinue" # disable progress bar if not verbose
        }

        LoadAzureCredentials -credentialsKind $credentialsKind -profilePath $profilePath
        Write-Host "Attempted Deleting VM $resourceId"
        $null = Remove-AzureRmResource -ResourceId $resourceId -Force
        Write-Host "Succeeded Deleting VM $resourceId"
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
            LogOutput "Starting job to delete VM $vmName, with params  $credentialsKind,$profilePath, $vmName, $($currentVm.ResourceId), $notVerbose, $HelperPath"

            $jobs += Start-Job -Name $vmName -ScriptBlock $deleteVmBlock -ArgumentList $credentialsKind,$profilePath, $vmName, $currentVm.ResourceId, $notVerbose, $HelperPath
            $vmiter = $vmiter + 1
        }

        if($jobs.count -ne 0) {
            Wait-job -Job $jobs -Force | Write-Verbose
            LogOutput "Batch: $i completed"
            foreach($job in $jobs) {
                Receive-Job $job -ErrorAction SilentlyContinue | LogOutput
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