[cmdletbinding()]
param 
(
    [Parameter(Mandatory = $true, HelpMessage = "Name of Lab")]
    [string] $LabName
	
)

trap {
    # NOTE: This trap will handle all errors. There should be no need to use a catch below in this
    #       script, unless you want to ignore a specific error.
    Handle-LastError
}


try {

	. .\Common.ps1

	$credentialsKind = InferCredentials

	if ($credentialsKind -eq "Runbook") {
		$TemplatePath = Get-AutomationVariable -Name 'TemplatePath'
	}
	else {
		$path = Resolve-Path $TemplatePath
		$templateContent = [IO.File]::ReadAllText($path)
	}

	if ($BatchSize -gt 100) {
		throw "BatchSize must be less or equal to 100"
	}
		
	LogOutput "Start management ..."

	LoadAzureCredentials -credentialsKind $credentialsKind -profilePath $profilePath


	$credentialsKind = InferCredentials
	$ResourceGroupName = GetResourceGroupName -labname $LabName

	$deploymentGroup = Get-AzureRmResourceGroupDeployment -ResourceGroupName $ResourceGroupName 

	$deploymentGroup.count

	Get-AzureRmResourceGroupDeployment -ResourceGroupName $ResourceGroupName | Remove-AzureRmResourceGroupDeployment -Verbose -Force

}
finally {
    if ($credentialsKind -eq "File") {
        1..3 | % { [console]::beep(2500, 300) } # Make a sound to indicate we're done if running from command line.
    }
    popd    
}