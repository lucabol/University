@echo off
cd ..\Class
powershell .\CleanupVMs.ps1 -LabName Stats
powershell .\CleanupVMs.ps1 -LabName Accounting
powershell .\CleanupVMs.ps1 -LabName Physics
powershell .\CleanupVMs.ps1 -LabName Management
  