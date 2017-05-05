﻿Param
(
     # Lab Name
    [Parameter(Mandatory=$true, HelpMessage="Name of Lab")]
    [string] $LabName,

    [Parameter(Mandatory=$false, HelpMessage="Path to file with Azure Profile")]
    [string] $profilePath = "$env:APPDATA\AzProfile.txt"
)

. .\Common.ps1

$VerbosePreference = "continue"


$credentialsKind = InferCredentials
LogOutput "Credentials: $credentialsKind"

LoadAzureCredentials -credentialsKind $credentialsKind -profilePath $profilePath

#we have to find the RG of the compute VM, which is different from the RG of the lab and the labVM

#get the RG of the lab
$ResourceGroupName = GetResourceGroupName -LabName $LabName

#get the expanded properties of the VMs
$labVMs = GetAllLabVMsExpanded -LabName $LabName


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