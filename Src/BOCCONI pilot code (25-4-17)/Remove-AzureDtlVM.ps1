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

function Handle-LastError
{
    [CmdletBinding()]
    param(
    )

    $posMessage = $_.ToString() + "`n" + $_.InvocationInfo.PositionMessage
    Write-Host -Object "`nERROR: $posMessage" -ForegroundColor Red
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
        
        Set-AzureRmContext -SubscriptionId $SubId                      
    } 
}

### DTL utility functions

function GetLab {
    [CmdletBinding()]
    param($LabName)
    $lab = Find-AzureRmResource -ResourceType "Microsoft.DevTestLab/labs" -ResourceNameContains $LabName  | where ResourceName -EQ "$LabName"
    LogOutput "Lab: $lab"
    return $lab
}

function GetAllLabVMs {
    [CmdletBinding()]
    param($LabName)
    
    return Find-AzureRmResource -ResourceType 'Microsoft.DevTestLab/labs/virtualmachines' -ResourceNameContains "$LabName/" | ? { $_.ResourceName -like "$LabName/*" }
} 

function GetResourceGroupName {
    [CmdletBinding()]
    param($LabName)
    return (GetLab -labname $LabName).ResourceGroupName    
}

workflow Remove-AzureDtlLabVMs
{
    [CmdletBinding()]
    param(
        $Ids,
        $credentialsKind,
        $profilePath
    )

    foreach -parallel ($id in $Ids)
    {
        try
        {
            LoadAzureCredentials -credentialsKind $credentialsKind -profilePath $profilePath
            $name = $id.Split('/')[-1]
            Write-Verbose "Removing virtual machine '$name' ..."
            $null = Remove-AzureRmResource -Force -ResourceId "$id"
            Write-Verbose "Done Removing"
        }
        catch
        {
            $posMessage = $_.ToString() + "`n" + $_.InvocationInfo.PositionMessage
            Write-Output "`nWORKFLOW ERROR: $posMessage"
        }
    }
}

#### Main script

try {

    if($PSPrivateMetadata.JobId) {
        $credentialsKind = "Runbook"
    }
    else {
        $credentialsKind =  "File"
    }
    Write-Verbose "Credentials: $credentialsKind"

    LogOutput "Start Removal"

    LoadAzureCredentials -credentialsKind $credentialsKind -profilePath $profilePath

    $ResourceGroupName = GetResourceGroupName -labname $LabName
    LogOutput "Resource Group: $ResourceGroupName"

    [array] $allVms = GetAllLabVMs -labname $LabName

    $batch = @(); $i = 0;

    $allVms | % {
        $batch += $_.ResourceId
        $i++
        if ($batch.Count -eq $BatchSize -or $allVms.Count -eq $i)
        {
            Remove-AzureDtlLabVMs -Ids $batch -ProfilePath $profilePath -credentialsKind $credentialsKind
            $batch = @()
        }
    }
    LogOutput "Deleted $($allVms.Count) VMs"
    LogOutput "All Done"

} finally {
    if($credentialsKind -eq "File") {
        1..3 | % { [console]::beep(2500,300) } # Make a sound to indicate we're done.
    }
    popd
}