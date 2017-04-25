Param
(
 # Lab Name
[Parameter(Mandatory=$true, HelpMessage="Name of Lab")]
[string] $LabName
)

$VerbosePreference = "continue"

$connectionName = "AzureRunAsConnection"
try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch 
{
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

#we have to find the RG of the compute VM (different from the RG of the lab and the labVM)

#get the RG of the lab
$ResourceGroupName = (Find-AzureRmResource -ResourceType "Microsoft.DevTestLab/labs" -ResourceNameContains $LabName).ResourceGroupName

#get the lab VMs
$labVM=Find-AzureRmResource -ResourceType "Microsoft.DevTestLab/labs/virtualMachines" -ResourceGroupName $ResourceGroupName


#get the resourceID of each labVM
$labVmId = @()
foreach ($machine in $labVM){
    $labVmId += $machine.ResourceId
}


$VirtualMachines = @()
foreach ($id in $labVmId){
    #get the specific compute id from the labVmId
    $computeId = (Get-AzureRmResource -Id $id).Properties.computeId

    #get the actual RG of the compute VM
    $labVmRGName=(Get-AzureRmResource -Id $computeId).resourcegroupname

    #Get all the compute VMs of the specific compute RG. Avoid recalling for the same RG
    if ($VirtualMachines.ResourceGroupName -notcontains $labVmRGName){
        $VirtualMachines += Get-AzureRmVM -ResourceGroupName $labVmRGName
    }
}



foreach ($VM in $VirtualMachines)
{
    #get the VM status
	#PowerState/deallocated = Stopped(deallocated)
	#PowerState/stopped = Stopped (shutdown from the OS)
    $VMStatus = (Get-AzureRmVM -ResourceGroupName $labVmRGName -Name $VM.Name -Status).Statuses.Code[1]
    
            Write-Verbose ("Status VM  "+ $VM.Name + " :" + $VMStatus)
            
            if ($VMStatus -eq 'PowerState/deallocated')
            {
            Write-Output ($VM.Name + " is already deallocated")
            }

            elseIf ($VMStatus -eq 'PowerState/stopped')
            {
                #force the VM deallocation
                $stopping = Stop-AzureRmVM -Name $VM.Name -ResourceGroupName $labVmRGName -Force

                #check again the VM status
                $VMStatus = (Get-AzureRmVM -ResourceGroupName $labVmRGName -Name $VM.Name -Status).Statuses.Code[1]

                    if ($VMstatus -eq 'PowerState/deallocated')
                        
                    {
                        Write-Output ($VM.Name + " deallocated")
                        }

                    else
                    {
                        Write-Output ($VM.Name + " fail to deallocate")
                    }
            }
}