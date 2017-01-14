start "Audit" /min az group deployment create -g audi30161rg009998 -n testmulti1 --parameters @MultiVMCustomImage.params.json --template-file MultiVMCustomImageTemplate.json

