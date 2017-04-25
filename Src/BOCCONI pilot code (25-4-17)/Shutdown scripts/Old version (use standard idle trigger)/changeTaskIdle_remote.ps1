param
(
    [Parameter(Mandatory=$false, HelpMessage="The name of the storage account")]
    [string] $StorageAccountName="vlabresources",

    [Parameter(Mandatory=$false, HelpMessage="The name of the container")]
    [string] $containerName="content",

    [Parameter(Mandatory=$false, HelpMessage="The name of the SAS token")]
    [string] $SASToken="?sv=2016-05-31&ss=b&srt=sco&sp=r&se=2025-04-06T21:13:00Z&st=2017-04-06T10:00:00Z&spr=https,http&sig=Snb5dfr2c%2FGHZQM6k7996AS6BzpRh2%2BRxgosuH5D3fA%3D",

    [Parameter(Mandatory=$false, HelpMessage="The name of the destination folder for the XML file")]
    [string] $folder = "C:\Users\SuperUser\Documents\WindowsPowerShell",

    [Parameter(Mandatory=$false, HelpMessage="The name of the XML file containing the definition of the task")]
    [string] $filename = "ShutdownOnIdle.xml",

    [Parameter(Mandatory=$false, HelpMessage="Path to file with Azure Profile")]
    [string] $profilePath = “C:\Users\SuperUser\AppData\Roaming\AzProfile.txt”
)

$ErrorActionPreference = "Stop"

$Ctx = New-AzureStorageContext $StorageAccountName -SasToken $SASToken
    
Get-AzureStorageBlobContent -Container $containerName -Blob $filename -Destination $folder -Context $Ctx -Force -ErrorAction Stop

$filepath = $folder +"\"+ $filename

$taskname = $filename.Split('.')[0]

schtasks.exe /delete /TN $taskname /f
    
schtasks.exe /create /TN $taskname /XML $filepath