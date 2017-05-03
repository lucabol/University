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

        $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName         

        Add-AzureRmAccount `
            -ServicePrincipal `
            -TenantId $servicePrincipalConnection.TenantId `
            -ApplicationId $servicePrincipalConnection.ApplicationId `
            -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint
        
        #Set-AzureRmContext -SubscriptionId $servicePrincipalConnection.SubscriptionID 
        Select-AzureRmSubscription -SubscriptionId $servicePrincipalConnection.SubscriptionID  | Write-Verbose

        # Save profile so it can be used later and set credentialsKind to "File"
        $global:profilePath = (Join-Path $env:TEMP  (New-guid).Guid)
        Save-AzureRmProfile -Path $global:profilePath | Write-Verbose
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

#### Removing VMs

# Function to return the Automation account information that this job is running in.
Function WhoAmI
{
    $AutomationResource = Find-AzureRmResource -ResourceType Microsoft.Automation/AutomationAccounts

    foreach ($Automation in $AutomationResource)
    {
        $Job = Get-AzureRmAutomationJob -ResourceGroupName $Automation.ResourceGroupName -AutomationAccountName $Automation.Name -Id $PSPrivateMetadata.JobId.Guid -ErrorAction SilentlyContinue
        if (!([string]::IsNullOrEmpty($Job)))
        {
            $AutomationInformation = @{}
            $AutomationInformation.Add("SubscriptionId",$Automation.SubscriptionId)
            $AutomationInformation.Add("Location",$Automation.Location)
            $AutomationInformation.Add("ResourceGroupName",$Job.ResourceGroupName)
            $AutomationInformation.Add("AutomationAccountName",$Job.AutomationAccountName)
            $AutomationInformation.Add("RunbookName",$Job.RunbookName)
            $AutomationInformation.Add("JobId",$Job.JobId.Guid)
            $AutomationInformation
            break;
        }
    }
}

# workflow Remove-AzureDtlLabVMs
# {
#     [CmdletBinding()]
#     param($Ids,$profilePath)

#     foreach -parallel ($id in $Ids)
#     {
#         try
#         {
#             $null = Select-AzureRmProfile -Path $profilePath
#             $name = $id.Split('/')[-1]
#             Write-Verbose "Removing virtual machine $name ..."
#             $null = Remove-AzureRmResource -Force -ResourceId "$id"
#             Write-Verbose "Done Removing $name ."
#         }
#         catch
#         {
#             Report-Error $_
#         }
#     }
# }

function RemoveBatchVMs {
    [CmdletBinding()]
    param($vms,$BatchSize, $credentialsKind, $profilePath)

    LogOutput "Removing VMs: $vm"
    $batch = @(); $i = 0;

    $vms | % {
        $batch += $_.ResourceId
        $i++
        if ($batch.Count -eq $BatchSize -or $vms.Count -eq $i)
        {
            if($credentialsKind -eq "File") {
                LogOutput "We are in the File path"
                . .\Remove-AzureDtlLabVMs -Ids $batch
            } else {
                LogOutput "We are in the Runbook path"
                # Get Account information on where this job is running from
                $AccountInfo = WhoAmI
                $RunbookName = "Remove-AzureDtlLabVMs"

                $RunbookNameParams = @{}
                $RunbookNameParams.Add("Ids",$batch)
                Start-AzureRmAutomationRunbook -ResourceGroupName $AccountInfo.ResourceGroupName -AutomationAccountName $AccountInfo.AutomationAccountName -Name $RunbookName -Parameters $RunbookNameParams | Out-Null
            }
            if($vms.Count -gt $i) {
                LogOutput "Waiting between batches to avoid executing too many things in parallel"
                Start-sleep -Seconds 240
            }
            $batch = @()
        }
    }    
}

### Creating VMs

function ConvertTo-Hashtable
{
    param(
        [Parameter(ValueFromPipeline)]
        [string] $Content
    )

    [void][System.Reflection.Assembly]::LoadWithPartialName("System.Web.Extensions")  
    $parser = New-Object Web.Script.Serialization.JavaScriptSerializer   
    Write-Output -NoEnumerate $parser.DeserializeObject($Content)
}

function Create-ParamsJson
{
    [CmdletBinding()]
    Param(
        [string] $Content,
        [hashtable] $Tokens,
        [switch] $Compress
    )

    $replacedContent = (Replace-Tokens -Content $Content -Tokens $Tokens)
    
    if ($Compress)
    {
        return (($replacedContent.Split("`r`n").Trim()) -join '').Replace(': ', ':')
    }
    else
    {
        return $replacedContent
    }
}

function Create-VirtualMachines
{
    [CmdletBinding()]
    Param(
        [string] $content,
        [string] $LabId,
        [hashtable] $Tokens
    )

    try {
        $json = Create-ParamsJson -Content $content -Tokens $tokens
        LogOutput $json

        $parameters = $json | ConvertTo-Hashtable

        Invoke-AzureRmResourceAction -ResourceId "$LabId" -Action CreateEnvironment -Parameters $parameters -Force  | Out-Null
    } catch {
            Report-Error $_        
    }

}

function Extract-Tokens
{
    [CmdletBinding()]
    Param(
        [string] $Content
    )
    
    ([Regex]'__(?<Token>.*?)__').Matches($Content).Value.Trim('__')
}

function Replace-Tokens
{
    [CmdletBinding()]
    Param(
        [string] $Content,
        [hashtable] $Tokens
    )
    
    $Tokens.GetEnumerator() | % { $Content = $Content.Replace("__$($_.Key)__", "$($_.Value)") }
    
    return $Content
}