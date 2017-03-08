# Cmdlets to create and cleanup labs
The Class directory contains scripts to create a DTL class in a lab and to remove all VMs in a lab.
The scripts need the lab to be created manually and for the correct image to be in the lab.
Also, they require the creation of an Azure profile file, as detailed below.

## Sample usage
Create 10 VMs in the Stats DTL lab using the UnivImage image.

    StartClass -LabName Stats -VMCount 10 -BaseImage UnivImate -ClassStart 12:00 -Duration 120

Remove all VMs from the Stats DTL lab

    CleanupVMs -LabName Stats

For other parameters, look at the code.

## Creating the appropriate Azure credential file to run the script in Class
In 'powershell' do the following:

    Login-AzureRmAccount
    Set-AzureRmContext -SubscriptionId "XXXXX-XXXX-XXXX"
    Save-AzureRMProfile -Path "$env:APPDATA\AzProfile.txt"

This saves the credentials file where the scripts look for.