[cmdletbinding()]
Param()
$scriptPath = Join-Path (Split-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) -Parent) "Class"
Write-Verbose $scriptPath
$LabName = "Stats"
$BaseImage = "UnivImage"
& "$scriptPath\StartClass.ps1" -VMCount 10 -LabName $LabName -BaseImage $BaseImage