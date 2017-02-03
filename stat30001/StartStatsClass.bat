start "Accounting" /min az group deployment create -g acc30005rg114208 -n testmulti1 --parameters @MultiVMCustomImage.params.json --template-file MultiVMCustomImageTemplate.json

