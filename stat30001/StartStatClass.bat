start "Stats" /min az group deployment create -g stat30001rg393666 -n testmulti1 --parameters @MultiVMCustomImage.params.json --template-file MultiVMCustomImageTemplate.json

