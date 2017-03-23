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

    #$posMessage = $_.InvocationInfo.PositionMessage
    $posMessage = $_.ToString() + "`n" + $_.InvocationInfo.PositionMessage
    Write-Host -Object "`nERROR: $posMessage" -ForegroundColor Red
    
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

function GetResourceGroupName {
    [CmdletBinding()]
    param($LabName)
    return (Find-AzureRmResource -ResourceType "Microsoft.DevTestLab/labs" -ResourceNameContains $LabName  | where ResourceName -CEQ "$LabName").ResourceGroupName    
}

function GetAllLabVMs {
    [CmdletBinding()]
    param($LabName, $ResourceGroupName)
    return Find-AzureRmResource -ResourceType "Microsoft.DevTestLab/labs/virtualMachines" -ResourceGroupNameContains $ResourceGroupName | where ResourceName -CLike "$LabName/*"    
}

function LoadAzureCredentials {
    [CmdletBinding()]
    param($credentialsKind, $profilePath)

    LogOutput "Credentials Kind: $credentialsKind"
    LogOutput "Credentials File: $profilePath"

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