start "Manager" /min az group deployment create -g mana30007rg605919 -n testmulti1 --parameters @MultiVMCustomImage.params.json --template-file MultiVMCustomImageTemplate.json

