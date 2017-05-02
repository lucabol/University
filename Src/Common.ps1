#### PS utility functions
$ErrorActionPreference = "Stop"
pushd $PSScriptRoot

$global:VerbosePreference = $VerbosePreference
$ProgressPreference = $VerbosePreference # Disable Progress Bar

function Report-Error {
    [CmdletBinding()]
    param($error)

    LogOutput "In ReportError"
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
        
        Set-AzureRmContext -SubscriptionId $servicePrincipalConnection.SubscriptionID 

        # Save profile so it can be used later and set credentialsKind to "File"
        $global:profilePath = (Join-Path $env:TEMP  (New-guid).Guid)
        Save-AzureRmProfile -Path $global:profilePath | Write-Verbose
        $global:credentialsKind =  "File"                          
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

function GetAllLabVMsExpanded {
    [CmdletBinding()]
    param($LabName)

    return Find-AzureRmResource -ResourceType 'Microsoft.DevTestLab/labs/virtualmachines' -ResourceNameContains "$LabName/" -ExpandProperties | ? { $_.ResourceName -like "$LabName/*" }    
}

function GetResourceGroupName {
    [CmdletBinding()]
    param($LabName)
    return (GetLab -labname $LabName).ResourceGroupName    
}

function GetDtlVmStatus {
    [CmdletBinding()]
    param($vm)

    $computeGroup = ($vm.Properties.ComputeId -split "/")[4]
    $name = ($vm.Properties.ComputeId -split "/")[8]
    $compVM = Get-azurermvm -ResourceGroupName $computeGroup -name $name -Status

    return $compVM.Statuses.Code[1]
}
