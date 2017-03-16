Param
(
[Parameter(Mandatory=$True)]
[string] $ResourceGroupName
)

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
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

#metto in una variabile tutte le VM
$VirtualMachines = Get-AzureRmVM -ResourceGroupName $ResourceGroupName

foreach ($VM in $VirtualMachines)
{
    #catturo lo stato (accensione o spegnimento) della macchina
    $VMStatus = (Get-AzureRmVM -ResourceGroupName $ResourceGroupName -Name $VM.Name -Status).Statuses.Code[1]
    
            if ($VMStatus -eq 'PowerState/deallocated')
             {
                Write-Output ($VM.Name + " is already deallocated")
             }

            elseIf ($VMStatus -eq 'PowerState/stopped')
                {
                    #lancia il comando per spegnere la macchina
                    $stopping = Stop-AzureRmVM -Name $VM.Name -ResourceGroupName $ResourceGroupName -Force

                    #catturo nuovamente lo stato (accensione o spegnimento) della macchina)
                    $VMStatus = (Get-AzureRmVM -ResourceGroupName $ResourceGroupName -Name $VM.Name -Status).Statuses.Code[1]

                        if ($VMstatus -eq 'PowerState/deallocated')
                        
                        {
                            Write-Output ($VM.Name + " deallocated")
                         }

                        else
                            {
                             Write-Output ($VM.Name + " fail")
                            }
                }
}


