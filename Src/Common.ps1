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
    return (Find-AzureRmResource -ResourceType "Microsoft.DevTestLab/labs" -ResourceNameContains $LabName  | where ResourceName -EQ "$LabName").ResourceGroupName    
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
    param($LabName, $ResourceGroupName)

    $SubscriptionID = (Get-AzureRmContext).Subscription.SubscriptionId
    $lab = Get-AzureRmResource -ResourceId (GetLabId -subscriptionID $SubscriptionID -resourceGroupName $ResourceGroupName -LabName $LabName)

    $labVMs = Get-AzureRmResource | Where-Object {
            $_.ResourceType -eq 'microsoft.devtestlab/labs/virtualmachines' -and
            $_.ResourceName -like "$($lab.ResourceName)/*"}

    return $LabVMs    
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

function Exec-With-Retry {
    [CmdletBinding()]
    param(    
    [Parameter(ValueFromPipeline,Mandatory)] $Command,
    $successTest = { return $true},   
    $RetryDelay = 1,
    $MaxRetries = 5
    )
    
    $currentRetry = 0
    $success = $false
    $cmd = $Command.ToString()

    do {
        try
        {
            LogOutput "Executing [$command]"
            & $Command
            $success = & $successTest
            if(!$success) { throw "Go to catch block"}
        }
        catch [System.Exception]
        {
            $currentRetry = $currentRetry + 1
            LogOutput "[$command] executed $currentRetry times"                      
            if ($currentRetry -gt $MaxRetries) {                
                throw "Could not execute [$command]. The error: " + $_.Exception.ToString()
            }
            Start-Sleep -s $RetryDelay
        }
    } while (!$success);
}

function TestCommon {
    [CmdletBinding()]
    param()
    # Test isDtlVmClaimed
    $labvmid = (GetLabId -SubscriptionID "d5e481ac-7346-47dc-9557-f405e1b3dcb0" -ResourceGroupName "PhysicsRG999685" -labname "Physics") + "/virtualmachines/labvm2017032909033800"
    write-host $labvmid
    $props = GetDTLComputeProperties $labvmid
    write-host $props
    IsDtlVmClaimed $props

    Exec-With-Retry { LogOutput "In Success block"} -Verbose
    Exec-With-Retry { LogOutput "In Success block"} -successTest {return $currentRetry -eq 2} -Verbose
    Exec-With-Retry { throw "test"} -Verbose
    
}

#TestCommon