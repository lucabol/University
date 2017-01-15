# Delete all the VMs in a lab

# Values to change
$subscriptionId = "818e194a-9bee-486f-9854-03b3be61170b"
$labResourceGroup = "mana30007rg605919"
$labName = "Mana30007"

# Login to your Azure account
Select-AzureRmProfile -Path "C:\Users\lucabol\Documents\AzCred.txt"

# Select the Azure subscription that contains the lab. This step is optional
# if you have only one subscription.
Select-AzureRmSubscription -SubscriptionId $subscriptionId

# Get the lab that contains the VMs to delete.
$lab = Get-AzureRmResource -ResourceId ('subscriptions/' + $subscriptionId + '/resourceGroups/' + $labResourceGroup + '/providers/Microsoft.DevTestLab/labs/' + $labName)

# Get the VMs from that lab.
$labVMs = Get-AzureRmResource | Where-Object { 
          $_.ResourceType -eq 'microsoft.devtestlab/labs/virtualmachines' -and
          $_.ResourceName -like "$($lab.ResourceName)/*"}

# Delete the VMs.
foreach($labVM in $labVMs)
{
    Remove-AzureRmResource -ResourceId $labVM.ResourceId -Force
}