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

trap
{
    # NOTE: This trap will handle all errors. There should be no need to use a catch below in this
    #       script, unless you want to ignore a specific error.
    Handle-LastError
}

. .\Common.ps1

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
