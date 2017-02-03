[cmdletbinding()]
Param()
$scriptPath = Join-Path (Split-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) -Parent) "Class"
Write-Verbose $scriptPath
$LabName = "Stats"
Write-Verbose "Cleaning up VMs in lab $LabName" 
& "$scriptPath\CleanupVMs.ps1" -LabName $LabName

#Write-Verbose "Creating VMs in lab $LabName"
#& "$scriptPath\StartClass.ps1" -VMCount 10 -LabName $LabName -BaseImage $BaseImage