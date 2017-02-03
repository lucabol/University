$scriptPath = Join-Path (Split-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) -Parent) "Class"
Write-Output $startPath
$LabName = "<lab_name>"
$BaseImage = "<base_image_name>"
& "$scriptPath\StartClass.ps1" -VMCount 10 -LabName $LabName -BaseImage $BaseImage