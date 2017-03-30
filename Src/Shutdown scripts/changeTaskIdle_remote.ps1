

[cmdletbinding()]
param
(
    [Parameter(Mandatory=$false, HelpMessage="The name of the destination folder for the XML file")]
    [string] $folder = "C:\Users\SuperUser\Documents\WindowsPowerShell",

    [Parameter(Mandatory=$false, HelpMessage="The name of the XML file containing the definition of the task")]
    [string] $filename = "ShutdownOnIdle",

    [Parameter(Mandatory=$false, HelpMessage="Path to file with Azure Profile")]
    [string] $profilePath = “C:\Users\SuperUser\AppData\Roaming\AzProfile.txt”
)

$ErrorActionPreference = "Stop"

Select-AzureRmProfile -Path $profilePath | Out-Null
Write-Host "Successfully logged in using saved profile file" -ForegroundColor Green

$info = Get-AzureRmStorageAccount -Name backupbocconiimagelab -ResourceGroupName backupVLAB | Get-AzureStorageContainer | Get-AzureStorageBlob -Blob $filename*
    
Get-AzureStorageBlobContent -Container upload -Blob $info.Name -Destination $folder -Context $info.Context -Force -ErrorAction Stop

$filepath = $folder +"\"+ $filename +".xml"

schtasks.exe /delete /TN $filename /f
    
schtasks.exe /create /TN $filename /XML $filepath




