function LogOutput {         
    [CmdletBinding()]
    param($msg)
    $timestamp = (Get-Date).ToUniversalTime()
    $output = "$timestamp [INFO]:: $msg"    
    if ($VerbosePreference -eq "Continue") {
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

function LoadCredentials {
    [CmdletBinding()]
    $Credential_Path = Join-Path (Split-Path ($Script:MyInvocation.MyCommand.Path)) "creds.txt"
    LogOutput "Credentials File: $Credential_Path"
    if (! (Test-Path $Credential_Path)) {
        LogError "Credential files not found at $Credential_Path. Exiting script..."    
        Exit 1
    }
    Select-AzureRmProfile -Path $Credential_Path | Out-Null    
    return $Credential_Path
}

function LoadSubscription {
    [CmdletBinding()]
    $SubscriptionIDPath = Join-Path (Split-Path ($Script:MyInvocation.MyCommand.Path)) "subId.txt"
    LogOutput "Subscription ID File: $SubscriptionIDPath"
    if (! (Test-Path $SubscriptionIDPath)) {
        LogError "Subscription ID file missing at $SubscriptionIDPath. Exiting script..." 
        Exit 1
    }
    $SubscriptionID = Get-Content -Path $SubscriptionIDPath
    LogOutput -msg "Subscription ID: $SubscriptionID"
    Select-AzureRmSubscription -SubscriptionId $SubscriptionID  | Out-Null
    Return $SubscriptionID
}