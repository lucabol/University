# Source folder
The Src directory contains scripts to create a DTL class in a lab and to remove all VMs in a lab.
The scripts need the lab to be created manually and for the correct image to be in the lab.
Also, they require the creation of an Azure profile file, as detailed below.

## Add-AzureDtlVM

It allows the creation of the VMs inside a specific lab. This script can be run either from command line or Azure Automation for the creation of the VMs of each lab. 

##Add-AzureDtlVMAutoVar

This script adds the number of Azure virtual machines in the DevTest Lab by reading some parameters from AutomationVariable.

##Add-GroupPermissionsDevTestLab

This script allows IT admins to give programmatically the permissions to access lab resources to a specific group using the lab role.

##Common

This script contains several functions useful for the other scripts.

##DeallocateStoppedVM

This script deallocates every stopped Azure virtual machines.

##Manage-AzureDtlFixedPool

This script guarantees that the Virtual Machine pool of the Lab equals to the PoolSize specified as Azure Tag of Lab.

##Remove-AzureDtlLabVMs

This script deletes the Azure virtual machines with the passed Ids in the DevTest Lab.

##Remove-AzureDtlVM

This script deletes every Azure virtual machines in the DevTest Lab.

##Remove-GroupPermissionsDevTestLab

This script removes the specified role from the AD Group in the DevTest Lab.

##Test-AzureDtlVMs

Given LabName and LabSize, this script verifies how many Azure virtual machines are inside the DevTest Lab and throws an error inside the logs when the number is greater or lower than size +/- VMDelta. 

