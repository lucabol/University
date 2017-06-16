# University repository
This repository has been created to collect the required material to set up DevTest Labs in Univerisities. This is useful both for IT admin and students because the former won't have to maintain physical machines, the latter will always have fresh machines available both for classes and self-service usage.

## Documentation folder
This folder contains three useful files:
- A video for a complete demo about setting up an entire environment on Azure DevTest Lab
- A complete manual which describes the solution implemented and how to deploy the Azure DevTest Lab for both class and self-service scenario
- An excel which helps in calculate an estimate of the price to run the solution

## Src folder
This folder contains:
- Powershell scripts file which needs to be run either via Console or via Automation account on Azure to set up the environments for the imagined scenarios.
- Roles folder which contains the json file which specifies the actions that a University user can take on a VM
- Shutdown scripts folder which contains the scripts to automatically shutdown a VM if it's not used for a certain period of time
- Simplifies JS portal contains the files needed to set a simplified portal for the students to claim a VM in an easier way
