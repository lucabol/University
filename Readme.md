# Cmdlets to create and cleanup labs
The Src directory contains scripts to create a DTL class in a lab and to remove all VMs in a lab.
The scripts need the lab to be created manually and for the correct image to be in the lab.
Also, they require the creation of an Azure profile file, as detailed below.

## Sample usage
Create 10 VMs in the Stats DTL lab using the UnivImage image.

    .\Add-AzureDtlVM.ps1 -LabName Stats -VMCount 10 -BaseImage UnivImage -ClassStart 12:00 -Duration 120 -CredentialsKind File

Remove all VMs from the Stats DTL lab

    .\Remove-AzureDtlVM -LabName Stats -CredentialsKind File

The CredentialsKind parameter can have the value of 'File' to load credentails from a file or 'Runbook' if you are running the sript in a runbook. 
For other parameters, look at the code.

## Creating the appropriate Azure credential file to run the script in Class
In 'powershell' do the following:

    Login-AzureRmAccount
    Set-AzureRmContext -SubscriptionId "XXXXX-XXXX-XXXX"
    Save-AzureRMProfile -Path "$env:APPDATA\AzProfile.txt"

This saves the credentials file where the scripts look for.