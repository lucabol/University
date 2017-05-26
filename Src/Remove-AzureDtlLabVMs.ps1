[cmdletbinding()]
param
(
    [Parameter(Mandatory=$true, HelpMessage="Resource ids for the VMs to delete")]
    [string[]] $ids   
)

trap
{
    # NOTE: This trap will handle all errors. There should be no need to use a catch below in this
    #       script, unless you want to ignore a specific error.
    Handle-LastError
}

. .\Common.ps1

$deleteVmBlock = {
    param($id, $profilePath)

    try {
        $azVer = GetAzureModuleVersion
        
        if($azVer -ge "3.8.0") {
            Save-AzureRmContext -Path $global:profilePath | Write-Verbose
        } else {
            Save-AzureRmProfile -Path $global:profilePath | Write-Verbose
        }

        $name = $id.Split('/')[-1]
        Write-Verbose "Removing virtual machine $name ..."
        Remove-AzureRmResource -Force -ResourceId "$id" | Out-Null
        Write-Verbose "Done Removing $name ."
    } catch {
        $posMessage = $_.ToString() + "`n" + $_.InvocationInfo.PositionMessage
        Write-Error "`nERROR: $posMessage" -ErrorAction "Continue"
    }
}

try {

    LogOutput "Start Removal"

    $credentialsKind = InferCredentials
    LogOutput "Credentials: $credentialsKind"

    LoadAzureCredentials -credentialsKind $credentialsKind -profilePath $profilePath

    $jobs = @()

    foreach ($id in $ids){        
        LogOutput "Starting job to delete $id ..."
        $jobs += Start-Job -Name $id -ScriptBlock $deleteVmBlock -ArgumentList $id, $profilePath
        LogOutput "$id deleted."
    }
    Wait-Job -Job $jobs | Write-Verbose
    LogOutput "VM Deletion jobs have completed"

} finally {
    if($credentialsKind -eq "File") {
        1..3 | % { [console]::beep(2500,300) } # Make a sound to indicate we're done.
    }
    popd    
}
