function LogOutput {         
    [CmdletBinding()]
    param($msg)
    $timestamp = (Get-Date).ToUniversalTime()
    $output = "$timestamp [INFO]:: $msg"    
    if ($VerbosePreference -ne "SilentlyContinue") {
        Write-Verbose $output
    }        
}

function LogError {
    [CmdletBinding()]
    param($msg)    
    $timestamp = (Get-Date).ToUniversalTime()
    $output = "$timestamp [ERROR]:: $msg"
    Write-Error $output
    exit 1
    
}

function LoadProfile {
    [CmdletBinding()]
    param($profilePath)    
    LogOutput "Credentials File: $profilePath"
    if (! (Test-Path $profilePath)) {
        LogError "Profile file(s) not found at $profilePath. Exiting script..."    
        Exit 1
    }
    Select-AzureRmProfile -Path $profilePath | Out-Null    
}

#function LoadSubscription {
#    [CmdletBinding()]
#    param($subscriptionIDPath)
#    LogOutput "Subscription ID File: $SubscriptionIDPath"
#    if (! (Test-Path $SubscriptionIDPath)) {
#        LogError "Subscription ID file missing at $SubscriptionIDPath. Exiting script..." 
#        Exit 1
#    }
#    $SubscriptionID = Get-Content -Path $SubscriptionIDPath
#    LogOutput -msg "Subscription ID: $SubscriptionID"
#    Select-AzureRmSubscription -SubscriptionId $SubscriptionID  | Out-Null
#    Return $SubscriptionID
#}