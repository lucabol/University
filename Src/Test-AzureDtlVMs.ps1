[cmdletbinding()]
param
(
    [Parameter(Mandatory=$true, HelpMessage="The name of the Dev Test Lab to clean up")]
    [string] $LabName,

    [Parameter(Mandatory=$false, HelpMessage="Path to file with Azure Profile")]
    [string] $profilePath = "$env:APPDATA\AzProfile.txt",

    [Parameter(Mandatory=$true, HelpMessage="Number of VMs that should be in the lab")]
    [string] $LabSize,

    [Parameter(Mandatory=$false, HelpMessage="Percentage of error in number of VMs (i.e. 0.1 means the lab can contain 10% more or less VMs)")]
    [double] $VMDelta = 0.1    
)

#### PS utility functions
$ErrorActionPreference = "Stop"
pushd $PSScriptRoot

$global:VerbosePreference = $VerbosePreference
$ProgressPreference = $VerbosePreference # Disable Progress Bar

trap
{
    # NOTE: This trap will handle all errors. There should be no need to use a catch below in this
    #       script, unless you want to ignore a specific error.
    Handle-LastError
}

function Report-Error {
    [CmdletBinding()]
    param($error)

    $posMessage = $error.ToString() + "`n" + $error.InvocationInfo.PositionMessage
    Write-Error "`nERROR: $posMessage" -ErrorAction "Continue"
}

function Handle-LastError
{
    [CmdletBinding()]
    param()

    Report-Error -error $_
    LogOutput "All done!"
    # IMPORTANT NOTE: Throwing a terminating error (using $ErrorActionPreference = "Stop") still
    # returns exit code zero from the PowerShell script when using -File. The workaround is to
    # NOT use -File when calling this script and leverage the try-catch-finally block and return
    # a non-zero exit code from the catch block.
    exit -1
}

function LogOutput {         
    [CmdletBinding()]
    param($msg)
    $timestamp = (Get-Date).ToUniversalTime()
    $output = "$timestamp [INFO]:: $msg"    
    Write-Verbose $output
}

### Azure utility functions

function LoadAzureCredentials {
    [CmdletBinding()]
    param($credentialsKind, $profilePath)

    Write-Verbose "Credentials Kind: $credentialsKind"
    Write-Verbose "Credentials File: $profilePath"

    if(($credentialsKind -ne "File") -and ($credentialsKind -ne "RunBook")) {
        throw "CredentialsKind must be either 'File' or 'RunBook'. It was $credentialsKind instead"
    }

    if($credentialsKind -eq "File") {
        if (! (Test-Path $profilePath)) {
            throw "Profile file(s) not found at $profilePath. Exiting script..."    
        }
        Select-AzureRmProfile -Path $profilePath | Out-Null
    } else {
        $connectionName = "AzureRunAsConnection"
        $SubId = Get-AutomationVariable -Name 'SubscriptionId'

        $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName         

        Add-AzureRmAccount `
            -ServicePrincipal `
            -TenantId $servicePrincipalConnection.TenantId `
            -ApplicationId $servicePrincipalConnection.ApplicationId `
            -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint
        
        Set-AzureRmContext -SubscriptionId $servicePrincipalConnection.SubscriptionID | Write-Verbose

        # Save profile so it can be used later and set credentialsKind to "File"
        $global:profilePath = (Join-Path $env:TEMP  (New-guid).Guid)
        Save-AzureRmProfile -Path $global:profilePath | Write-Verbose
        $global:credentialsKind =  "File"                         
    } 
}

### DTL utility functions

function GetAllLabVMsExpanded {
    [CmdletBinding()]
    param($LabName)

    return Find-AzureRmResource -ResourceType 'Microsoft.DevTestLab/labs/virtualmachines' -ResourceNameContains "$LabName/" -ExpandProperties | ? { $_.ResourceName -like "$LabName/*" }    
}

#### Main script

try {
    LogOutput "Start Testing Lab"

    if($PSPrivateMetadata.JobId) {
        $credentialsKind = "Runbook"
    }
    else {
        $credentialsKind =  "File"
    }

    LogOutput "Credentials: $credentialsKind"
    LoadAzureCredentials -credentialsKind $credentialsKind -profilePath $profilePath

    [array] $vms = GetAllLabVMsExpanded -LabName $LabName
    [array] $failedVms = $vms | ? { $_.Properties.provisioningState -eq 'Failed' }

    $vmCount = $vms.Count
    $failedCount = $failedVms.Count
    $availableVMs = $vmCount - $failedCount
    Write-Output "Total Number of VMs: $vmCount, Failed VMs: $failedCount, Available VMs: $availableVMs"

    $wrongCount = ($availableVMs -lt $LabSize * (1 - $VMDelta)) -or ($availableVMs -gt $LabSize * (1 + $VMDelta))
    $someFailed = $failedCount -ne 0

    if($someFailed -or $wrongCount) {
        Write-Error "VMs count: $availableVMs / $LabSize, Failed VMs: $FailedCount"
    } else {
        Write-Output "The lab is as expected"
    }

} finally {
    if($credentialsKind -eq "File") {
        1..3 | % { [console]::beep(2500,300) } # Make a sound to indicate we're done.
    }
    popd
}