Param
(
[Parameter(Mandatory=$True, HelpMessage="Resource group of the VMs")]
[string] $ResourceGroupName
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


#Get all the VMs inside the lab
#NOTE: the RG must be the one where the VMs are created (type: Microsoft.Compute/virtualMachines/), which is different from the RG of the lab
$VirtualMachines = Get-AzureRmVM -ResourceGroupName $ResourceGroupName


foreach ($VM in $VirtualMachines)
{
    #get the VM status
	#PowerState/deallocated = Stopped(deallocated)
	#PowerState/stopped = Stopped (shutdown from the OS)
    $VMStatus = (Get-AzureRmVM -ResourceGroupName $ResourceGroupName -Name $VM.Name -Status).Statuses.Code[1]
    
            Write-Verbose ("Status VM  "+ $VM.Name + " :" + $VMStatus)
            
            if ($VMStatus -eq 'PowerState/deallocated')
            {
            Write-Output ($VM.Name + " is already deallocated")
            }

            elseIf ($VMStatus -eq 'PowerState/stopped')
            {
                #force the VM deallocation
                $stopping = Stop-AzureRmVM -Name $VM.Name -ResourceGroupName $ResourceGroupName -Force

                #check again the VM status
                $VMStatus = (Get-AzureRmVM -ResourceGroupName $ResourceGroupName -Name $VM.Name -Status).Statuses.Code[1]

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