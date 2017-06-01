[cmdletbinding()]
param 
(
    [Parameter(Mandatory=$true, HelpMessage="Name of Lab")]
    [string] $LabName,

    [Parameter(Mandatory=$true, HelpMessage="Number of VMs to create with this execution")]
    [int] $VMCount,

    [Parameter(Mandatory=$true, HelpMessage="Name of base image in lab")]
    [string] $ImageName,

    [Parameter(Mandatory=$true, HelpMessage="Shutdown time for the VMs in the lab. In form of 'HH:mm' in TimeZoneID timezone")]
    [string] $ShutDownTime,

    [Parameter(Mandatory=$true, HelpMessage="Desired total number of VMs in the lab")]
    [int] $TotalLabSize,

    [Parameter(Mandatory=$false, HelpMessage="How many days before expiring the VMs (-1 never, 0 today, 1 tomorrow, 2 .... Defaults to tomorrow.")]
    [int] $DaysToExpiry = 1,

    [Parameter(Mandatory=$false, HelpMessage="What time to expire the VMs at. Defaults to 3am. In form of 'HH:mm' in TimeZoneID timezone")]
    [string] $ExpirationTime = "03:00"
)

trap
{
    # NOTE: This trap will handle all errors. There should be no need to use a catch below in this
    #       script, unless you want to ignore a specific error.
    Handle-LastError
}

. .\Common.ps1

try {
    $credentialsKind = InferCredentials

    if($credentialsKind -eq "Runbook") {
        $ShutdownPath = Get-AutomationVariable -Name 'ShutdownPath'
        $VNetName = Get-AutomationVariable -Name 'VNetName'
        $SubnetName = Get-AutomationVariable -Name 'SubnetName'
        $Size = Get-AutomationVariable -Name 'Size'
        $TemplatePath = Get-AutomationVariable -Name 'TemplatePath'
    }
    else {
        throw "This script just works under Azure Automation, and expects the variables in the code just above"
    }

    . .\Add-AzureDtlVM.ps1 -LabName $LabName -VMCount $VMCount -ImageName $ImageName -ShutDownTime $ShutDownTime -TotalLabSize $TotalLabSize `
                            -ShutdownPath $ShutdownPath -TemplatePath $TemplatePath -VNetName $VNetName -SubnetName $SubnetName -Size $Size -ExpirationTime $ExpirationTime -DaysToExpiry $DaysToExpiry
} finally {
    if($credentialsKind -eq "File") {
        1..3 | % { [console]::beep(2500,300) } # Make a sound to indicate we're done if running from command line.
    }
    popd    
}