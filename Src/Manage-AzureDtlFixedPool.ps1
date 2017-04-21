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
        [string] $path,
        [string] $LabId,
        [hashtable] $Tokens
    )

    if ($credentialsKind -eq "File"){
        $path = Resolve-Path $path

        $content = [IO.File]::ReadAllText($path)

        }
    elseif ($credentialsKind -eq "Runbook"){

        $path = Get-AutomationVariable -Name 'TemplatePath'

        $file = Invoke-WebRequest -Uri $path -UseBasicParsing
        $content = $file.Content
    }

    $json = Create-ParamsJson -Content $content -Tokens $tokens
    LogOutput $json

    $parameters = $json | ConvertTo-Hashtable

    Invoke-AzureRmResourceAction -ResourceId "$LabId" -Action CreateEnvironment -Parameters $parameters -Force  | Out-Null
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
            Write-Output "Removing virtual machine '$name' ..."
            $null = Remove-AzureRmResource -Force -ResourceId "$id"
            Write-Output "Done Removing"
        }
        catch
        {
            $posMessage = $_.ToString() + "`n" + $_.InvocationInfo.PositionMessage
            $errors += ,$posMessage
            Write-Output "`nWORKFLOW ERROR: $posMessage"
        }
    }
}

#### Main script

$errors = @()

try {

    if($PSPrivateMetadata.JobId) {
        $credentialsKind = "Runbook"
        $VNetName = Get-AutomationVariable -Name 'VNetName'
        $SubnetName = Get-AutomationVariable -Name 'SubnetName'
        $Size = Get-AutomationVariable -Name 'Size'   
    }
    else {
        $credentialsKind =  "File"
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

    $SubscriptionID = (Get-AzureRmContext).Subscription.SubscriptionId
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
            try {
                $tokens["Name"] = $VMNameBase + $i.ToString()
                LogOutput "Processing batch: $i"
                Create-VirtualMachines -LabId $labId -Tokens $tokens -path $TemplatePath
                LogOutput "Finished processing batch: $i"
            } catch {
                $posMessage = $_.ToString() + "`n" + $_.InvocationInfo.PositionMessage
                $errors += ,$posMessage
                Write-Host -Object "`nERROR: $posMessage" -ForegroundColor Red
                Write-Host "Moving on to next batch after error"            
            }
        }

        # Process reminder
        if($rem -ne 0) {
            try {
                LogOutput "Processing reminder"
                $tokens["Name"] = $VMNameBase + "Rm"
                $tokens["Count"] = $rem
                Create-VirtualMachines -LabId $labId -Tokens $tokens -path $TemplatePath
                LogOutput "Finished processing reminder"
            } catch {
                $posMessage = $_.ToString() + "`n" + $_.InvocationInfo.PositionMessage
                $errors += ,$posMessage
                Write-Host -Object "`nERROR: $posMessage" -ForegroundColor Red
                Write-Host "Moving on to next batch after error"            
            }           
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

    $batch = @(); $i = 0;

    $toDelete | % {
        $batch += $_.ResourceId
        $i++
        if ($batch.Count -eq $BatchSize -or $toDelete.Count -eq $i)
        {
            Remove-AzureDtlLabVMs -Ids $batch -ProfilePath $profilePath -credentialsKind $credentialsKind
            $batch = @()
        }
    }
    LogOutput "Deleted $($toDelete.Count) VMs"

    if($errors) {
        throw $errors
    }
    LogOutput "All done!"

} finally {
    if($credentialsKind -eq "File") {
        1..3 | % { [console]::beep(2500,300) } # Make a sound to indicate we're done if running from command line.
    }
    popd
}