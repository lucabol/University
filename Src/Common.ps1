#### General PS settings.

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

#### Azure helper functions.

function InferCredentials {
    [CmdletBinding()]
    param()

    if($PSPrivateMetadata.JobId) {
        return "Runbook"
    }
    else {
        return "File"
    }
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

#### DTL Helper functions

function GetLab {
    [CmdletBinding()]
    param($LabName)
    $lab = Find-AzureRmResource -ResourceType "Microsoft.DevTestLab/labs" -ResourceNameContains $LabName  | where ResourceName -EQ "$LabName"
    LogOutput "Lab: $lab"
    return $lab
}

function GetResourceGroupName {
    [CmdletBinding()]
    param($LabName)
    return (GetLab -labname $LabName).ResourceGroupName    
}

function GetLabId {
    [CmdletBinding()]
    param($SubscriptionID, $LabName, $ResourceGroupName)

    $labId = 'subscriptions/' + $SubscriptionID + '/resourceGroups/' + $ResourceGroupName + '/providers/Microsoft.DevTestLab/labs/' + $LabName
    LogOutput("LabId: $labId")
    return $labId
}

function GetAllLabVMs {
    [CmdletBinding()]
    param($LabName)
    
    return Find-AzureRmResource -ResourceType 'Microsoft.DevTestLab/labs/virtualmachines' -ResourceNameContains "$LabName/" | ? { $_.ResourceName -like "$LabName/*" }
} 

# Hideously slow. Is there a way to retrieve it bulk? btw: just adding OData query to Find-AzureRmResource doesn't work
function GetAllLabVMsWithCompute {
    [CmdletBinding()]
    param($LabName)
    $vms = GetAllLabVms -LabName $LabName
    return $vms | % { Get-AzureRmResource -ResourceId $_.ResourceId -ODataQuery '$expand=Properties($expand=ComputeVm)' | ? { $_.ResourceName -like "$LabName/*" } }
} 

function GetDTLComputeProperties {
    [CmdletBinding()]
    param($LabVmId)

    $propRes = Get-AzureRmResource -ResourceId $LabVMId -ODataQuery '$expand=Properties($expand=ComputeVm,ApplicableSchedule)'
    LogOutput("Compute Properties: $propRes")
    return $propRes.Properties
}

function IsDtlVmClaimed {
    [CmdletBinding()]
    param($props)

    return !$props.AllowClaim -and $props.OwnerObjectId
}

function IsProvisioningFailed {
    [CmdletBinding()]
    param($props)

    return $props.provisioningState -eq 'Failed'   
}

function GetComputeGroup {
    [CmdletBinding()]
    param($props)

    return ($props.ComputeId -split "/")[4]    
}