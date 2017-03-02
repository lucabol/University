@echo off
cd ..\Class
powershell .\StartClass.ps1 -LabName %1 -VMCount 5 -BaseImage UnivImage -ClassStart 01:00 -Duration 120