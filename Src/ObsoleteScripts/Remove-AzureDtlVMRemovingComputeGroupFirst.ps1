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
    [string] $parallelDeletion = 10
    
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

    $HelperPath = Join-Path (Split-Path ($Script:MyInvocation.MyCommand.Path)) "Common.ps1"
    LogOutput $HelperPath

    # First find all compute groups for the VMs
    $set = New-Object System.Collections.Generic.HashSet[string]

    foreach ($currentVm in $allVms){
        LogOutput "CurrentVM: $currentVm"
        $vmName = $currentVm.ResourceName

        $SubscriptionID = (Get-AzureRmContext).Subscription.SubscriptionId
        $vmId = $currentVM.ResourceId
        LogOutput "VmId: $vmId"
        
        $props = GetDTLComputeProperties -labvmid $vmId
        LogOutput "Props: $props"
        $gr = GetComputeGroup -props $props
        LogOutput "Compute Group Id: $gr"
        if($gr -ne "") {
            $set.Add($gr) | Out-Null
        }
    }

    # Then delete all compute groups found (could be done in parallel)
    foreach ($grName in $set){
        LogOutput "Started deletion of resource group: $grName"
        Remove-AzureRmResourceGroup -Name $grName -Force -ErrorAction SilentlyContinue | Out-Null
    }

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

    $allVms = @($allVms) # PS magick to convert object to array, otherwise it automatically convert 1 sized array to the object contained.
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