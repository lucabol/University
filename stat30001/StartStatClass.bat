@echo off
echo Starting Class Creation. Might take a few minutes ...
set startTime=%time%
az group deployment create -g stat30001rg801276 -n testmulti1 --parameters @MultiVM.params.json --template-file MultiVMTemplate.json
set endTime = %time%
echo Class Created.
echo Start Time: %startTime%
echo Finish Time: %endTime%
echo Time Spent: %endTime% - %startTime%
