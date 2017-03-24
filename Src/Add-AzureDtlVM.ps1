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
    [string] $VMNameBase = "studentlabvm",

    [Parameter(Mandatory=$true, HelpMessage="Scheduled start time for class. In form of 'HH:mm'")]
    [string] $ClassStart,

    [Parameter(Mandatory=$true, HelpMessage="Time to live for VMs (in minutes)")]
    [int] $Duration,

    [Parameter(Mandatory=$false, HelpMessage="Virtual Network Name")]
    [string] $VNetName = "dtl$LabName",

    [Parameter(Mandatory=$false, HelpMessage="SubNetName")]
    [string] $SubnetName = "dtl" + $LabName + "SubNet",

    [Parameter(Mandatory=$false, HelpMessage="Path to file with Azure Profile")]
    [string] $profilePath = "$env:APPDATA\AzProfile.txt",

    [Parameter(Mandatory=$true, HelpMessage="Which credential type to use (either File or Runbook)")]
    [string] $credentialsKind,

    [Parameter(Mandatory=$false, HelpMessage="Location for the Machines")]
    [string] $location = "westeurope",

    [Parameter(Mandatory=$false, HelpMessage="TimeZone for machines")]
    [string] $TimeZoneId = "Central European Standard Time"
    
      
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

    $path = Resolve-Path $path

    $content = [IO.File]::ReadAllText($path)
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
    # Import common functions
    . "./Common.ps1"
    
    LogOutput "Start provisioning ..."

    LoadAzureCredentials $credentialsKind $profilePath

    $startTime = (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss")
    LogOutput "StartTime: $startTime"
    $deploymentName = "Deployment_$LabName_$startTime"
    $shutDeployment = $deploymentName + "Shutdown"
    LogOutput "Deployment Name: $deploymentName"
    LogOutput "Shutdown Deployment Name: $shutDeployment"

    $SubscriptionID = (Get-AzureRmContext).Subscription.SubscriptionId
    LogOutput "Subscription id: $SubscriptionID"
    $ResourceGroupName = GetResourceGroupName $LabName
    LogOutput "Resource Group: $ResourceGroupName"

    # Check to see if any VMs already exist in the lab. 
<#    LogOutput "Checking for existing VMs in $LabName"
    $existingVMs = (GetAllLabVMs $LabName $ResourceGroupName).Count
    if ($existingVMs -ne 0) {
        throw "Lab $LabName contains $existingVMs existing VMs. Please clean up lab before creating new VMs"
    }
    LogOutput "No existing VMs in $LabName"
#>
    # Set the expiration Date
    $UniversalDate = (Get-Date).ToUniversalTime()
    $ExpirationDate = $UniversalDate.AddDays(1).ToString("yyyy-MM-dd")
    LogOutput "Expiration Date: $ExpirationDate"

    # Set the shutdown time
    $startTime = Get-Date $ClassStart
    $ShutDownTime = $startTime.AddMinutes($Duration).toString("HHmm")
    LogOutput "Class Start Time: $($startTime)    Class End Time: $($ShutDownTime)"

    LogOutput "Start deployment of Shutdown time ..."
    # Change Shutdown time in lab
    $shutParams = @{
            newLabName = $LabName
            shutDownTime = $ShutDownTime
            timeZoneId = $TimeZoneId
        }
    
    New-AzureRmResourceGroupDeployment -Name $shutDeployment -ResourceGroupName $ResourceGroupName -TemplateFile $ShutdownPath -TemplateParameterObject $shutParams
    LogOutput "Shutdown time deployed."

    LogOutput "Start creating VMs ..."
    $labId = "/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroupName/providers/Microsoft.DevTestLab/labs/$LabName"
    LogOutput "LabId: $labId"
   
    $tokens = @{
        Count = $VMCount
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

    Create-VirtualMachines -LabId $labId -Tokens $tokens -path $TemplatePath
    LogOutput "All done!"

} finally {
    if($credentialsKind -eq "File") {
        1..3 | % { [console]::beep(2500,300) } # Make a sound to indicate we're done.
    }
    popd
}
