# University repository
This repository has been created to collect the required material to set up DevTest Labs in Univerisities. This is useful both for IT admin and students because the former won't have to maintain physical machines, the latter will always have fresh machines available both for classes and self-service usage.

## Documentation folder
This folder contains three useful files:
- [A video for a complete demo about setting up an entire environment on Azure DevTest Lab](Documentation/DemoVirtualLab_Ita.mp4)
- [A complete manual which describes the solution implemented and how to deploy the Azure DevTest Lab for both class and self-service scenario](University/Documentation/Virtual Lab Manual.docx)
- [An excel which helps in calculate an estimate of the price to run the solution](University/Documentation/DevTestLab - VM Price estimator.xlsx)

## Src folder
This folder contains:
- [Powershell scripts file which needs to be run either via Console or via Automation account on Azure to set up the environments for the imagined scenarios.](University/Src)
    - [Add-AzureDtlVM](University/Src/Add-AzureDtlVM.ps1): This script adds the specified number of Azure virtual machines to a DevTest Lab.
    - [Add-AzureDtlVMAutoVar](University/Src/Add-AzureDtlVMAutoVar.ps1): This script adds the number of Azure virtual machines in the DevTest Lab by reading some parameters from AutomationVariable.
    - [Add-GroupPermissionsDevTestLab](University/Src/Add-GroupPermissionsDevTestLab.ps1): This script adds the specified role to the AD Group in the DevTest Lab.
    - [Common](University/Src/Common.ps1): This script contains many useful functions for the other scripts.
    - [DeallocateStoppedVM](University/Src/DeallocateStoppedVM.ps1): This script deallocates every stopped Azure virtual machines.
    - [Manage-AzureDtlFixedPool](University/Src/Manage-AzureDtlFixedPool.ps1): This script guarantees that the Virtual Machine pool of the Lab equals to the PoolSize specified as Azure Tag of Lab.
    - [Remove-AzureDtlLabVMs](Remove-AzureDtlLabVMs.ps1): This script guarantees that the Virtual Machine pool of the Lab equals to the PoolSize specified as Azure Tag of Lab.
    - [Remove-AzureDtlVM](University/Src/Remove-AzureDtlVM.ps1): This script deletes every Azure virtual machines in the DevTest Lab.
    - [Remove-GroupPermissionsDevTestLab](University/Src/Remove-GroupPermissionsDevTestLab.ps1): This script removes the specified role from the AD Group in the DevTest Lab.
    - [Test-AzureDtlVMs](University/Src/Test-AzureDtlVMs.ps1): Given LabName and LabSize, this script verifies how many Azure virtual machines are inside the DevTest Lab and throws an error inside the logs when the number is greater or lower than size +/- VMDelta. 
- [Roles folder which contains the json file which specifies the actions that a University user can take on a VM](Src/Roles)
- [Shutdown scripts folder which contains the scripts to automatically shutdown a VM if it's not used for a certain period of time](Src/Shutdown scripts)
    - [LoadIdleScript](Src/Shutdown scripts/LoadIdleScript.ps1): This script creates a task inside Windows Task Scheduler getting a file script from a blob storage.
    - [ShutdownOnIdleV2](Src/Shutdown scripts/ShutdownOnIdleV2.ps1): This script shutdowns the machine if the user hasn't been active.
- [Simplifies JS portal contains the files needed to set a simplified portal for the students to claim a VM in an easier way](Src/SimplifiedJSPortal)
