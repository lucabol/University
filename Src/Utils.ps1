. ./Common.ps1

function Exec-With-Retry {
    [CmdletBinding()]
    param(    
    [Parameter(ValueFromPipeline,Mandatory)] $Command,
    $successTest = { return $true},   
    $RetryDelay = 1,
    $MaxRetries = 5
    )
    
    $currentRetry = 0
    $success = $false
    $cmd = $Command.ToString()

    do {
        try
        {
            LogOutput "Executing [$command]"
            & $Command
            $success = & $successTest
            if(!$success) { throw "Go to catch block"}
        }
        catch [System.Exception]
        {
            $currentRetry = $currentRetry + 1
            LogOutput "[$command] executed $currentRetry times"                      
            if ($currentRetry -gt $MaxRetries) {                
                throw "Could not execute [$command]. The error: " + $_.Exception.ToString()
            }
            Start-Sleep -s $RetryDelay
        }
    } while (!$success);
}

function TestVMComputeId {

    $labName = "TestCreationFix"
    $lab = GetLab -labName $labName
    write-host "lab: $lab"
    $resourcegroupname = GetResourceGroupName -LabName $labName
    write-host "RGN: $resourcegroupname"
    $vms = GetAllLabVMs -LabName $labName 
    write-host $vms[0]
}
function TestCommon {
    [CmdletBinding()]
    param()
    # Test isDtlVmClaimed
    #$labvmid = "subscriptions/d5e481ac-7346-47dc-9557-f405e1b3dcb0/resourceGroups/PhysicsRG999685/providers/Microsoft.DevTestLab/labs/Physics/virtualmachines/vm164442610600"
    #$labvmid = "subscriptions/d5e481ac-7346-47dc-9557-f405e1b3dcb0/resourceGroups/PhysicsRG999685/providers/Microsoft.DevTestLab/labs/Physics/virtualmachines/labvm2017032909033800"
    $labvmid = "subscriptions/d5e481ac-7346-47dc-9557-f405e1b3dcb0/resourceGroups/TestCreationFixRG893172/providers/Microsoft.DevTestLab/labs/TestCreationFix/virtualmachines/vm1247640841008"

    write-host $labvmid
    $props = GetDTLComputeProperties $labvmid
    write-host $props

    $gr = GetComputeGroup -props $props
    $what = $gr -eq ""
    write-host "What: $what"

    IsDtlVmClaimed $props
    $compid = $props.ComputeId
    write-host "Compute id: $compid"
    $compGroup = ($compid -split "/")[4]
    write-host "Comp Group: $compGroup"

    # Exec-With-Retry { LogOutput "In Success block"} -Verbose
    # Exec-With-Retry { LogOutput "In Success block"} -successTest {return $currentRetry -eq 2} -Verbose
    # Exec-With-Retry { throw "test"} -Verbose
    
}
function TestMany {
    $labName = "VMDiskNat"
    $resourceGroupName = "VMDiskNatRG494167"
    $vms = GetAllLabVMs -labName $labName
    Write-host $vms.count
    $labName = "AfterMDisk"
    $resourceGroupName = "AfterMDiskRG237826"
    $vms = GetAllLabVMs -labName $labName 
    Write-host $vms.count
    $labName = "TestCreationFix"
    $resourceGroupName = "TestCreationFixRG893172"
    $vms = GetAllLabVMs -labName $labName 
    Write-host $vms.count
}
TestMany
#TestCommon
TestVMComputeId