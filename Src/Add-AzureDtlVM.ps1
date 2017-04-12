[cmdletbinding()]
param 
(
    [Parameter(Mandatory=$false, HelpMessage="Path to the Deployment Template File")]
    [string] $TemplatePath = ".\dtl_multivm_customimage.json",

    [Parameter(Mandatory=$false, HelpMessage="Path to the Shutdown file")]
    [string] $ShutdownPath = ".\dtl_shutdown.json",

    [Parameter(Mandatory=$true, HelpMessage="Number of instances to create")]
    [int] $VMCount,

    [Parameter(Mandatory=$true, HelpMessage="Name of Lab")]
    [string] $LabName,

    [Parameter(Mandatory=$true, HelpMessage="Name of base image in lab")]
    [string] $ImageName,

    [Parameter(Mandatory=$false, HelpMessage="Size of VM image")]
    [string] $Size = "Standard_DS2",    

    [Parameter(Mandatory=$false, HelpMessage="Prefix for new VMs")]
    [string] $VMNameBase = "vm",

    [Parameter(Mandatory=$true, HelpMessage="Shutdown time for the VMs in the lab. In form of 'HH:mm' in TimeZoneID timezone")]
    [string] $ShutDownTime,

    [Parameter(Mandatory=$false, HelpMessage="Expiry DateTime in TimeZoneID timezone (defaults to the shutdown time)")]
    [DateTime] $ExpiryDateTime = (Get-Date $ShutDownTime),

    [Parameter(Mandatory=$false, HelpMessage="Virtual Network Name")]
    [string] $VNetName = "dtl$LabName",

    [Parameter(Mandatory=$false, HelpMessage="SubNetName")]
    [string] $SubnetName = "dtl" + $LabName + "SubNet",

    [Parameter(Mandatory=$false, HelpMessage="Path to file with Azure Profile")]
    [string] $profilePath = "$env:APPDATA\AzProfile.txt",

    [Parameter(Mandatory=$false, HelpMessage="Location for the Machines")]
    [string] $location = "westeurope",

    [Parameter(Mandatory=$false, HelpMessage="TimeZone for machines")]
    [string] $TimeZoneId = "Central European Standard Time",

    [Parameter(Mandatory=$false, HelpMessage="How many VMs to create in each batch")]
    [int] $BatchSize = 50,

    [Parameter(Mandatory=$false, HelpMessage="Fail if existing VMs in the lab")]
    [switch] $FailIfExiting
        
)

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

try {

    if($PSPrivateMetadata.JobId) {
        $credentialsKind = "Runbook"
    }
    else {
        $credentialsKind =  "File"
    }

    if($BatchSize -gt 100) {
        throw "BatchSize must be less or equal to 100"
    }

    if ($credentialsKind -eq "File"){
        . "./Common.ps1"
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

    LogOutput "Start deployment of Shutdown time ..."
    # Change Shutdown time in lab
    $shutParams = @{
            newLabName = $LabName
            shutDownTime = $ShutDownTime
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
        ShutDownTime = $ShutDownTime
        Size = $Size
        SubnetName = $SubnetName
        SubscriptionId = $SubscriptionId
        TimeZoneId = $TimeZoneId
        VirtualNetworkName = $VNetName
    }

    $loops = [math]::Floor($VMCount / $BatchSize)
    $rem = $VMCount - $loops * $BatchSize
    LogOutput "VMCount: $vmcount, Loops: $loops, Rem: $rem"

    # Iterating loops time
    for($i = 0; $i -lt $loops; $i++) {
        try {
            $tokens["Name"] = $VMNameBase + $i.ToString()
            LogOutput "Processing batch: $i"
            Create-VirtualMachines -LabId $labId -Tokens $tokens -path $TemplatePath
            LogOutput "Finished processing batch: $i"
        } catch {
            $posMessage = $_.ToString() + "`n" + $_.InvocationInfo.PositionMessage
            Write-Host -Object "`nERROR: $posMessage" -ForegroundColor Red
            Write-Host "Moving on to next batch after error"            
        }
    }

    # Process reminder
    if($rem -ne 0) {
        LogOutput "Processing reminder"
        $tokens["Name"] = $VMNameBase + "Rm"
        $tokens["Count"] = $rem
        Create-VirtualMachines -LabId $labId -Tokens $tokens -path $TemplatePath
        LogOutput "Finished processing reminder"
    }
    LogOutput "All done!"

} finally {
    if($credentialsKind -eq "File") {
        1..3 | % { [console]::beep(2500,300) } # Make a sound to indicate we're done.
    }
    popd
}
