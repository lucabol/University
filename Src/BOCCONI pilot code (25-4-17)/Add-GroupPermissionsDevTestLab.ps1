[cmdletbinding()]
param 
(
    [Parameter(Mandatory=$true, HelpMessage="The name of the lab")]
    [string] $labName,
    
    [Parameter(Mandatory=$true, HelpMessage="The name of the AD group")]
    [string] $ADGroupName,

    [Parameter(Mandatory=$false, HelpMessage="The role definition name")]
    [string] $role = "Bocconi DevTest Labs User",

    [Parameter(Mandatory=$false, HelpMessage="Path to file with Azure Profile")]
    [string] $profilePath = "$env:APPDATA\AzProfile.txt"
)

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

function LogOutput {         
    [CmdletBinding()]
    param($msg)
    $timestamp = (Get-Date).ToUniversalTime()
    $output = "$timestamp [INFO]:: $msg"    
    Write-Verbose $output
}

if($PSPrivateMetadata.JobId) {
        $credentialsKind = "Runbook"
}
else {
    $credentialsKind =  "File"
}

LogOutput "Credentials kind: $credentialsKind"


$ErrorActionPreference = "Stop"

LoadAzureCredentials -credentialsKind $credentialsKind -profilePath $profilePath

$SubscriptionID = (Get-AzureRmContext).Subscription.SubscriptionId

$ResourceGroupName = (Find-AzureRmResource -ResourceType "Microsoft.DevTestLab/labs" -ResourceNameContains $LabName).ResourceGroupName

# get the ObjectId from the AD group name
$objectId = Get-AzureRmADGroup -SearchString $ADGroupName

# assign the role to the group for the specified lab
New-AzureRmRoleAssignment -ObjectId $objectId.Id -Scope /subscriptions/$SubscriptionID/resourcegroups/$ResourceGroupName/providers/microsoft.devtestlab/labs/$labName -RoleDefinitionName $role
