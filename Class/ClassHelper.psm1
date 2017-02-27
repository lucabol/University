function LogOutput {         
    [CmdletBinding()]
    param($msg)
    $timestamp = (Get-Date).ToUniversalTime()
    $output = "$timestamp [INFO]:: $msg"    
    Write-Verbose $output
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