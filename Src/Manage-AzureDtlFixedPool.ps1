[cmdletbinding()]
param 
(
    [Parameter(Mandatory=$true, HelpMessage="Name of Lab")]
    [string] $LabName,

    [Parameter(Mandatory=$true, HelpMessage="Name of base image in lab")]
    [string] $ImageName,

    [Parameter(Mandatory=$false, HelpMessage="How many VMs to create in each batch")]
    [int] $BatchSize = 50,

    [Parameter(Mandatory=$false, HelpMessage="Path to the Deployment Template File")]
    [string] $TemplatePath = ".\dtl_multivm_customimage.json",

    [Parameter(Mandatory=$false, HelpMessage="Size of VM image")]
    [string] $Size = "Standard_DS2",    

    [Parameter(Mandatory=$false, HelpMessage="Prefix for new VMs")]
    [string] $VMNameBase = "vm",

    [Parameter(Mandatory=$false, HelpMessage="Virtual Network Name")]
    [string] $VNetName = "dtl$LabName",

    [Parameter(Mandatory=$false, HelpMessage="SubNetName")]
    [string] $SubnetName = "dtl" + $LabName + "SubNet",

    [Parameter(Mandatory=$false, HelpMessage="Location for the Machines")]
    [string] $location = "westeurope",

    [Parameter(Mandatory=$false, HelpMessage="TimeZone for machines")]
    [string] $TimeZoneId = "Central European Standard Time",

    [Parameter(Mandatory=$false, HelpMessage="Path to file with Azure Profile")]
    [string] $profilePath = "$env:APPDATA\AzProfile.txt"
)

trap
{
    # NOTE: This trap will handle all errors. There should be no need to use a catch below in this
    #       script, unless you want to ignore a specific error.
    Handle-LastError
}

. .\Common.ps1

$errors = @()

try {

    $credentialsKind = InferCredentials

    if($credentialsKind -eq "Runbook") {
        $path = Get-AutomationVariable -Name 'TemplatePath'
        $file = Invoke-WebRequest -Uri $path -UseBasicParsing
        $templateContent = $file.Content
    }
    else {
        $path = Resolve-Path $TemplatePath
        $templateContent = [IO.File]::ReadAllText($path)
    }

    if($BatchSize -gt 100) {
        throw "BatchSize must be less or equal to 100"
    }
    
    LogOutput "Start management ..."

    LoadAzureCredentials -credentialsKind $credentialsKind -profilePath $profilePath

    # Create deployment names
    $depTime = (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss")
    LogOutput "StartTime: $depTime"
    $deploymentName = "Deployment_$LabName_$depTime"
    $shutDeployment = $deploymentName + "Shutdown"
    LogOutput "Deployment Name: $deploymentName"

    $SubscriptionID = (Get-AzureRmContext).Subscription.Id
    LogOutput "Subscription id: $SubscriptionID"
    $ResourceGroupName = GetResourceGroupName -labname $LabName
    LogOutput "Resource Group: $ResourceGroupName"


    $Lab = GetLab -LabName $LabName
    $poolSize = $Lab.Tags.PoolSize
    if(! $poolSize) {
        throw "The lab $LabName doesn't contain a PoolSize tag"
    }

    [array] $vms = GetAllLabVMsExpanded -LabName $LabName
    [array] $failedVms = $vms | ? { $_.Properties.provisioningState -eq 'Failed' }
    [array] $claimedVms = $vms | ? { !$_.Properties.AllowClaim -and $_.Properties.OwnerObjectId }

    $availableVms = $vms.count - $claimedVms.count - $failedVms.count
    $vmToCreate = $poolSize - $availableVms

    LogOutput "Lab $LabName, Total VMS:$($vms.count), Failed:$($failedVms.count), Claimed:$($claimedVms.count), PoolSize: $poolSize, ToCreate: $vmToCreate"

    # Never expire (TODO: change template not to have expiry date)
    $ExpirationDate = Get-date "3000-01-01"

    # Create VMs to refill the pool
    if($vmToCreate -gt 0) {
        LogOutput "Start creating VMs ..."
        $labId = "/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroupName/providers/Microsoft.DevTestLab/labs/$LabName"
        LogOutput "LabId: $labId"
    
        # Create unique name base for this deployment by taking the current time in seconds from a startDate, for the sake of using less characters
        # as the max number of characters in an Azure vm name is 16. This algo should produce vmXXXXXXXX (10 chars) leaving 6 chars free for the VM number
        $baseDate = get-date -date "01-01-2016"
        $ticksFromBase = (get-date).ticks - $baseDate.Ticks
        $secondsFromBase = [math]::Floor($ticksFromBase / 10000000)
        $VMNameBase = $VMNameBase + $secondsFromBase.ToString()
        LogOutput "Base Name $VMNameBase"

        $tokens = @{
            Count = $BatchSize
            ExpirationDate = $ExpirationDate
            ImageName = "/subscriptions/$SubscriptionID/ResourceGroups/$ResourceGroupName/providers/Microsoft.DevTestLab/labs/$LabName/customImages/$ImageName"
            LabName = $LabName
            Location = $location
            Name = $VMNameBase
            ResourceGroupName = $ResourceGroupName
            ShutDownTime = $ShutDownTime
            Size = $Size
            SubnetName = $SubnetName
            SubscriptionId = $SubscriptionId
            TimeZoneId = $TimeZoneId
            VirtualNetworkName = $VNetName
        }

        $loops = [math]::Floor($vmToCreate / $BatchSize)
        $rem = $vmToCreate - $loops * $BatchSize
        LogOutput "VMCount: $vmToCreate, Loops: $loops, Rem: $rem"

        # Iterating loops time
        for($i = 0; $i -lt $loops; $i++) {
            $tokens["Name"] = $VMNameBase + $i.ToString()
            LogOutput "Processing batch: $i"
            Create-VirtualMachines -LabId $labId -Tokens $tokens -content $templateContent
            LogOutput "Finished processing batch: $i"
        }

        # Process reminder
        if($rem -ne 0) {
            LogOutput "Processing reminder"
            $tokens["Name"] = $VMNameBase + "Rm"
            $tokens["Count"] = $rem
            Create-VirtualMachines -LabId $labId -Tokens $tokens -content $templateContent
            LogOutput "Finished processing reminder"
        }
    }

    # Check if there are Failed VMs in the lab and deletes them, using the same batchsize as creation.
    # It is done even if the failed VMs haven't been created by this script, just for the sake of cleaning up the lab.
    LogOutput "Check for failed VMs and stopped VMs"
    [array] $vms = GetAllLabVMsExpanded -LabName $LabName
    [array] $failedVms = $vms | ? { $_.Properties.provisioningState -eq 'Failed' }
    [array] $stoppedVms = $claimedVms | ? { (GetDtlVmStatus -vm $_) -eq 'PowerState/deallocated'}
    $toDelete = $failedVms + $stoppedVms

    LogOutput "Failed:$($failedVms.Count), Stopped: $($stoppedVms.Count), ToDelete: $($toDelete.Count)"

    RemoveBatchVms -vms $toDelete -batchSize $batchSize -profilePath $profilePath -credentialsKind $credentialsKind
    LogOutput "Deleted $($toDelete.Count) VMs"

    LogOutput "All done!"

} finally {
    if($credentialsKind -eq "File") {
        1..3 | % { [console]::beep(2500,300) } # Make a sound to indicate we're done if running from command line.
    }
    popd
}