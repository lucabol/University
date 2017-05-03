[cmdletbinding()]
param
(
    [Parameter(Mandatory=$true, HelpMessage="The name of the Dev Test Lab to clean up")]
    [string] $LabName,

    [Parameter(Mandatory=$false, HelpMessage="Path to file with Azure Profile")]
    [string] $profilePath = "$env:APPDATA\AzProfile.txt",

    [Parameter(Mandatory=$false, HelpMessage="How many VMs to delete in parallel")]
    [string] $batchSize = 10
    
)

trap
{
    # NOTE: This trap will handle all errors. There should be no need to use a catch below in this
    #       script, unless you want to ignore a specific error.
    Handle-LastError
}

. .\Common.ps1

#### Main script

try {
    LogOutput "Start Removal"

    $credentialsKind = InferCredentials
    LogOutput "Credentials: $credentialsKind"

    LoadAzureCredentials -credentialsKind $credentialsKind -profilePath $profilePath

    $ResourceGroupName = GetResourceGroupName -labname $LabName
    LogOutput "Resource Group: $ResourceGroupName"

    [array] $allVms = GetAllLabVMs -labname $LabName

    RemoveBatchVms -vms $allVms -batchSize $batchSize -profilePath $profilePath -credentialsKind $credentialsKind

    LogOutput "Deleted $($allVms.Count) VMs"
    LogOutput "All Done"

} finally {
    if($credentialsKind -eq "File") {
        1..3 | % { [console]::beep(2500,300) } # Make a sound to indicate we're done.
    }
    popd
}