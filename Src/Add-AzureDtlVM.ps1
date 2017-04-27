[cmdletbinding()]
param 
(
    [Parameter(Mandatory=$true, HelpMessage="Name of Lab")]
    [string] $LabName,

    [Parameter(Mandatory=$true, HelpMessage="Number of instances to create")]
    [int] $VMCount,

    [Parameter(Mandatory=$true, HelpMessage="Name of base image in lab")]
    [string] $ImageName,

    [Parameter(Mandatory=$true, HelpMessage="Shutdown time for the VMs in the lab. In form of 'HH:mm' in TimeZoneID timezone")]
    [string] $ShutDownTime,

    [Parameter(Mandatory=$false, HelpMessage="How many VMs to create in each batch")]
    [int] $BatchSize = 30,

    [Parameter(Mandatory=$false, HelpMessage="Path to the Deployment Template File")]
    [string] $TemplatePath = ".\dtl_multivm_customimage.json",

    [Parameter(Mandatory=$false, HelpMessage="Path to the Shutdown file")]
    [string] $ShutdownPath = ".\dtl_shutdown.json",

    [Parameter(Mandatory=$false, HelpMessage="Size of VM image")]
    [string] $Size = "Standard_A2_v2",    

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

    [Parameter(Mandatory=$false, HelpMessage="Fail if existing VMs in the lab")]
    [switch] $FailIfExisting,

    [Parameter(Mandatory=$false, HelpMessage="Path to file with Azure Profile")]
    [string] $profilePath = "$env:APPDATA\AzProfile.txt",

    [Parameter(Mandatory=$false, HelpMessage="Expiry DateTime (as YYYY-MM-DDTHH:mm:ss or other parsable datetime) in TimeZoneID timezone (defaults to the shutdown time)")]
    [DateTime] $ExpiryDateTime = ([timezoneinfo]::ConvertTimeFromUtc([datetime]::UtcNow, [timezoneinfo]::FindSystemTimeZoneById($TimeZoneId))).Date.AddDays(1).AddHours(3)       
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
            LogOutput "Removing virtual machine '$name' ..."
            $null = Remove-AzureRmResource -Force -ResourceId "$id"
            LogOutput "Done Removing"
        }
        catch
        {
            Report-Error -error $_
        }
    }
}

#### Main script

try {

    if($PSPrivateMetadata.JobId) {
        $credentialsKind = "Runbook"
        $ShutdownPath = Get-AutomationVariable -Name 'ShutdownPath'
        $VNetName = Get-AutomationVariable -Name 'VNetName'
        $SubnetName = Get-AutomationVariable -Name 'SubnetName'
        $Size = Get-AutomationVariable -Name 'Size'
        $path = Get-AutomationVariable -Name 'TemplatePath'
        $file = Invoke-WebRequest -Uri $path -UseBasicParsing
        $templateContent = $file.Content
    }
    else {
        $credentialsKind =  "File"
        $path = Resolve-Path $TemplatePath
        $templateContent = [IO.File]::ReadAllText($path)
    }

    if($BatchSize -gt 100) {
        throw "BatchSize must be less or equal to 100"
    }
    
    LogOutput "Start provisioning ..."

    LoadAzureCredentials -credentialsKind $credentialsKind -profilePath $profilePath

    # Create deployment names
    $depTime = (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss")
    LogOutput "StartTime: $depTime"
    $deploymentName = "Deployment_$LabName_$depTime"
    $shutDeployment = $deploymentName + "Shutdown"
    LogOutput "Deployment Name: $deploymentName"
    LogOutput "Shutdown Deployment Name: $shutDeployment"
    LogOutput "Shutdown time: $ShutDownTime"

    $SubscriptionID = (Get-AzureRmContext).Subscription.SubscriptionId
    LogOutput "Subscription id: $SubscriptionID"
    $ResourceGroupName = GetResourceGroupName -labname $LabName
    LogOutput "Resource Group: $ResourceGroupName"

    if($FailIfExiting) {
        # Check to see if any VMs already exist in the lab. 
        LogOutput "Checking for existing VMs in $LabName"
        $existingVMs = (GetAllLabVMs -labName $LabName).Count
        if ($existingVMs -ne 0) {
            throw "Lab $LabName contains $existingVMs existing VMs. Please clean up lab before creating new VMs"
        }
        LogOutput "No existing VMs in $LabName"
    }

    # Set the expiration date. This needs to be passed to DevTestLab in UTC time, so it is converted to UTC from TimeZoneId time
    $tz = [system.timezoneinfo]::FindSystemTimeZoneById($TimeZoneId)
    $ExpirationUtc = [system.timezoneinfo]::ConvertTimeToUtc($ExpiryDateTime, $tz)
    if($ExpirationUtc -le [DateTime]::UtcNow) {
        throw "Expiration date $ShutDownDate (or in UTC $ExpirationUtc) must be in the future."
    }
    $ExpirationDate = $ExpirationUtc.ToString("yyyy-MM-ddTHH:mm:ss")
    LogOutput "Expiration Date: $ExpirationDate"

    $ShutDownTimeHours = ([DateTime]$ShutDownTime).ToString("HHmm")
    LogOutput "Shutdown Time hours: $ShutdownTimeHours"

    LogOutput "Start deployment of Shutdown time ..."
    $shutParams = @{
            newLabName = $LabName
            shutDownTime = $ShutDownTimeHours
            timeZoneId = $TimeZoneId
        }
    
    New-AzureRmResourceGroupDeployment -Name $shutDeployment -ResourceGroupName $ResourceGroupName -TemplateFile $ShutdownPath -TemplateParameterObject $shutParams | Write-Verbose
    LogOutput "Shutdown time deployed."

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
        ShutDownTime = $ShutDownTimeHours
        Size = $Size
        SubnetName = $SubnetName
        SubscriptionId = $SubscriptionId
        TimeZoneId = $TimeZoneId
        VirtualNetworkName = $VNetName
    }

    $loops = [math]::Floor($VMCount / $BatchSize)
    $rem = $VMCount - $loops * $BatchSize
    LogOutput "VMCount: $vmcount, Loops: $loops, Rem: $rem"

    $creationError = $false

    # Iterating loops time
    for($i = 0; $i -lt $loops; $i++) {
        try {
            $tokens["Name"] = $VMNameBase + $i.ToString()
            LogOutput "Processing batch: $i"
            Create-VirtualMachines -LabId $labId -Tokens $tokens -content $templateContent
            LogOutput "Finished processing batch: $i"
        } catch {
            $creationError = $true
            Report-Error -error $_
            LogOutput "Moving on to next batch after error"            
        }
    }

    # Process reminder
    if($rem -ne 0) {
        try {
            LogOutput "Processing reminder"
            $tokens["Name"] = $VMNameBase + "Rm"
            $tokens["Count"] = $rem
            Create-VirtualMachines -LabId $labId -Tokens $tokens -content $templateContent
            LogOutput "Finished processing reminder"
         } catch {
            $creationError = $true
            Report-Error -error $_
            LogOutput "Moving on to next batch after error"            
        }           
    }

    # Check if there are Failed VMs in the lab and deletes them, using the same batchsize as creation.
    # It is done even if the failed VMs haven't been created by this script, just for the sake of cleaning up the lab.
    LogOutput "Check for failed VMs"
    [array] $vms = GetAllLabVMsExpanded -LabName $LabName
    [array] $failed = $vms | ? { $_.Properties.provisioningState -eq 'Failed' }
    LogOutput "Detected $($failed.Count) failed VMs"

    $batch = @(); $i = 0;

    $failed | % {
        $batch += $_.ResourceId
        $i++
        if ($batch.Count -eq $BatchSize -or $failed.Count -eq $i)
        {
            Remove-AzureDtlLabVMs -Ids $batch -ProfilePath $profilePath -credentialsKind $credentialsKind
            $batch = @()
        }
    }
    LogOutput "Deleted $($failed.Count) failed VMs"

    # An error is thrown if any batch creation in this script failed *NOT* if we found existing failed VMs in the lab.
    if($creationError) {
        throw "Deleted $($failed.Count) failed VMs"         
    }

    LogOutput "All done!"

} finally {
    if($credentialsKind -eq "File") {
        1..3 | % { [console]::beep(2500,300) } # Make a sound to indicate we're done if running from command line.
    }
    popd
}