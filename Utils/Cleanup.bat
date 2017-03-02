@echo off
cd ..\Class
start powershell .\CleanupVMs.ps1 -LabName Stats
start powershell .\CleanupVMs.ps1 -LabName Accounting
start powershell .\CleanupVMs.ps1 -LabName Physics
start powershell .\CleanupVMs.ps1 -LabName Management
  