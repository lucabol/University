#s$ErrorActionPreference = "Stop"

$info = Get-AzureRmStorageAccount -Name backupbocconiimagelab -ResourceGroupName backupVLAB | Get-AzureStorageContainer | Get-AzureStorageBlob -Blob Shutdown*

Get-AzureStorageBlobContent -Container upload -Blob $info.Name -Destination "C:\" -Context $info.Context -Force -ErrorAction Stop

schtasks.exe /delete /TN "Shutdown on idle" /f

schtasks.exe /create /TN "Shutdown on idle" /XML "C:\Shutdown on idle.xml"