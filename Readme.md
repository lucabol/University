# University related cmdlets
## Creating the appropriate Azure credential file to run the script in Class
In 'powershell' do the following:

    Login-AzureRmAccount
    Set-AzureRmContext -SubscriptionId "XXXXX-XXXX-XXXX"
    Save-AzureRMProfile -Path "$env:APPDATA\AzProfile.txt"

This saves the credential file where the scripts look for.