Param
(
     # Lab Name
    [Parameter(Mandatory=$true, HelpMessage="Name of Lab")]
    [string] $LabName,

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
        
        Set-AzureRmContext -SubscriptionId $SubId                            
    } 
}

$VerbosePreference = "continue"


if($PSPrivateMetadata.JobId) {
        $credentialsKind = "Runbook"
        $ShutdownPath = Get-AutomationVariable -Name 'ShutdownPath'
        $VNetName = Get-AutomationVariable -Name 'VNetName'
        $SubnetName = Get-AutomationVariable -Name 'SubnetName'
        $Size = Get-AutomationVariable -Name 'Size'   
}
else {
    $credentialsKind =  "File"
}

LoadAzureCredentials -credentialsKind $credentialsKind -profilePath $profilePath

#we have to find the RG of the compute VM, which is different from the RG of the lab and the labVM

#get the RG of the lab
$ResourceGroupName = (Find-AzureRmResource -ResourceType "Microsoft.DevTestLab/labs" -ResourceNameContains $LabName).ResourceGroupName


#get the expanded properties of the VMs
$labVMs = Find-AzureRmResource -ResourceType 'Microsoft.DevTestLab/labs/virtualmachines' -ResourceNameContains "$LabName/" -ExpandProperties | ? { $_.ResourceName -like "$LabName/*" }


foreach ($vm in $labVMs){

    #get the actual RG of the compute VM
    $labVmRGName=(Get-AzureRmResource -Id $vm.Properties.computeid).ResourceGroupName

    $VMStatus = (Get-AzureRmVM -ResourceGroupName $labVmRGName -Name $VM.Name -Status).Statuses.Code[1]

    Write-Verbose ("Status VM  "+ $VM.Name + " :" + $VMStatus)
            
    if ($VMStatus -eq 'PowerState/deallocated')
    {
        Write-Output ($VM.Name + " is already deallocated")
    }

    elseIf ($VMStatus -eq 'PowerState/stopped')
    {
        #force the VM deallocation
        Stop-AzureRmVM -Name $VM.Name -ResourceGroupName $labVmRGName -Force

    }

}