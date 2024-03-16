<# 
    .SYNOPSIS 
    Register a event watcher and disable automatic checkpoints for a new created Hyper-V vm

    Torsten Schlopsnies

    THIS CODE IS MADE AVAILABLE AS IS, WITHOUT WARRANTY OF ANY KIND. THE ENTIRE  
    RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS CODE REMAINS WITH THE USER. 

    Version 1.0, 2024-03-16

    Please submit ideas, comments, and suggestions using GitHub. 

    .DESCRIPTION 

    This script register a event watcher and extract the vm id when a new vm is created. With the id
    the script disable automatic checkpoints for the vm
    
    .NOTES 

    Requirements 
    - Windows 11 Pro/Enterprise
    - Administrative rights
    
    Revision History 
    -------- ----------------------------------------------------------------------- 
    1.0      Initial community release 

    .PARAMETER Register  
    Register the event watcher and write the watcher information into a json text file. The fill is stored aside the script.

    .PARAMETER ReceiveOutput
    When used with -Register it will allow to reive the Write-Host cmdlets from the $action block in Register-Watcher

    .PARAMETER Unregister
    Unregister the event watcher. To get the watcher details it will try to load the json text file which was created with -Register

    .PARAMETER InstallTask
    Install a scheduled task which will run on boot with SYSTEM rights. As long as the task is running the watcher is listening.

    .PARAMETER RemoveTask
    Removes the scheduled task.

    .PARAMETER Help
    Display a short usage text

    .EXAMPLE 

    Register a event watcher

    .\Disable-AutomaticCheckpoints.ps1 -Register

    .EXAMPLE 

    Register a event watcher and receive output from the action which was taken

    .\Disable-AutomaticCheckpoints.ps1 -Register -ReceiveOutput

    .EXAMPLE 

    Unregister the event watcher

    .\Disable-AutomaticCheckpoints.ps1 -Unregister

    .EXAMPLE 

    Install the task

    .\Disable-AutomaticCheckpoints.ps1 -InstallTask

    EXAMPLE 

    Remove the task

    .\Disable-AutomaticCheckpoints.ps1 -RemoveTask
#> 
param(
    [Parameter(ParameterSetName = "Register", Mandatory = $true)][switch]$Register,
    [Parameter(ParameterSetName = "Register")][switch]$ReceiveOutput,
    [Parameter(ParameterSetName = "Unregister", Mandatory = $true)][switch]$Unregister,
    [Parameter(ParameterSetName = "InstallTask", Mandatory = $true)][switch]$InstallTask,
    [Parameter(ParameterSetName = "RemoveTask", Mandatory = $true)][switch]$RemoveTask,
    [Parameter(ParameterSetName = "Help")][switch]$Help
)

# Variables
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
$jobPath = "$($scriptPath)\job.json"



function Get-AdministrativeRightsInfo {
    <#
        .SYNPOSIS
            Check if script is running with administrative rights
    #>
    if (-not ($PsCmdlet.ParameterSetName -eq "Help")) {
        if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
            if ([int](Get-CimInstance -Class Win32_OperatingSystem | Select-Object -ExpandProperty BuildNumber) -ge 6000) {
                Write-Error "Administrative rights are mandatory to register the event watcher or install/uninstall the task"
                Exit
            }
        }
    }
}

function Get-Job {
    <#
        .SYNPOSIS
            Will load the json object from -Path and check if this event is already registered.

        .PARAMETER Path
            Job file (json)

        .OUTPUTS
            Return $true if job is registered, $false if not
    #>
    param (
        [Parameter(Mandatory = $true)]$Path
    )

    if (-not(Test-Path -Path $Path)) {
        return $false
    }

    $loadedJob = (Get-Content -Path $jobPath | ConvertFrom-Json -ErrorAction SilentlyContinue).Name
    if ($null -eq $loadedJob) {
        return $false
    }

    if ($null -eq (Get-EventSubscriber -SourceIdentifier $loadedJob -ErrorAction SilentlyContinue)) { 
        return $false
    }
    
    return $true
}

function Register-Watcher {
    <#
        .SYNPOSIS
            Register the watcher for the object event. Stores the job as json object into a text file.

        .DESCRIPTION
            Register the watcher. $action will be executed if the event occurs and the watcher will be called.

    #>
    # check first if we already have a event registered
    if (Get-Job -Path $jobPath) {
        $jobId = (Get-Content -Path $jobPath | ConvertFrom-Json).Name
        Write-Warning "There is already a object event registered. The job id is $($jobId). Please unregister before try again."
        Exit
    }

    # event id from creating a new VM
    $eventId = 13002
    $LogName = 'Microsoft-Windows-Hyper-V-VMMS-Admin'
    $select = "*[System[(EventID=$eventId)]]"
    $query = [System.Diagnostics.Eventing.Reader.EventLogQuery]::new($logName, [System.Diagnostics.Eventing.Reader.PathType]::LogName, $select)
    
    $watcher = [System.Diagnostics.Eventing.Reader.EventLogWatcher]::new($query)
    $watcher.Enabled = $true
    
    # in the action scope you can add anything you would like to do with the VM
    $action = {
        $vmId = $Eventargs.EventRecord.properties[1].Value
        if ($null -eq $vmId) {
            Write-Host "Warning: incomplete message in event"
            Exit
        }
        $vm = Get-VM -id $vmId
        if ($null -eq $vm) {
            Write-Host "Error: VM with id ""$($vmId)"" could not be loaded. Error message: $($Error)"
        }

        $null = $vm | Set-VM -AutomaticCheckpointsEnabled $false
    }
    
    $job = Register-ObjectEvent -InputObject $watcher -EventName 'EventRecordWritten' -Action $action
    Receive-Job $job
    Write-Host "Job with id ""$($job.Name)"" registered"
    try {
        if (Test-Path -Path $jobPath) {
            $null = Remove-Item -Path $jobPath -Force
        }
        ConvertTo-Json -InputObject $job | Out-File -FilePath $jobPath
    }
    catch {
        Write-Warning "Could not remove or save the job file ""$($jobPath)"". Please unregister (Unregister-Event) manual with the job id ""$($job.Name)"""
    }
    
    if ($ReceiveOutput) {
        # note that this will only work if rou run the script directly and let the powershell window stay open. Will not work when started via the task scheduler.
        Receive-Job $job
    }
    
}

function Unregister-Watcher {
    <#
        .SYNPOSIS
            Unregister the watcher for the object event.

        .DESCRIPTION
            Unregister the watcher which was created in Register-Watcher
    #>
    if (-not (Get-Job -Path $jobPath)) {
        Write-Host "No registered job found."
        Exit
    }

    try {
        $jobId = (Get-Content -Path $jobPath | ConvertFrom-Json).Name
    }
    catch {
        Write-Error "Error on reading the json file."
        Exit
    }
    

    try {
        Unregister-Event -SourceIdentifier $jobId
        $null = Remove-Item -Path $jobPath -Force
        Write-Host "Job with id ""$($jobId)"" successfully unregistered"

    }
    catch {
        Write-Error "Error on unregister follwing job id: $($jobId)"
        Write-Error "Error message: $($Error)"
    }
}

function Install-Task {
    <#
        .SYNPOSIS
            Install a scheduled task

        .DESCRIPTION
            Install a task which will run on boot under SYSTEM rights. The task start a powershell session 
    #>
    $task = Get-ScheduledTask -TaskName "Disable-AutomaticCheckpoints" -ErrorAction SilentlyContinue
    if ($null -ne $task) {
        Write-Warning "The task already exists."
        Exit
    }

    $taskTrigger = New-ScheduledTaskTrigger -AtStartup
    $taskAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoLogo -NoProfile -WindowStyle Hidden -Noninteractive -NoExit -file $($MyInvocation.ScriptName) -Register" -WorkingDirectory "$($scriptPath)"
    $settingSet = New-ScheduledTaskSettingsSet -DontStopIfGoingOnBatteries -DontStopOnIdleEnd -AllowStartIfOnBatteries -ExecutionTimeLimit '00:00:00'
    $Principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount
    Register-ScheduledTask "Disable-AutomaticCheckpoints" -Action $taskAction -Trigger $taskTrigger -Principal $Principal -Settings $settingSet
    Start-ScheduledTask "Disable-AutomaticCheckpoints"
}

function Remove-Task {
    <#
        .SYNPOSIS
            Remove a scheduled task

        .DESCRIPTION
            Remove the task which was created with Install-Task
    #>    
    $task = Get-ScheduledTask -TaskName "Disable-AutomaticCheckpoints" -ErrorAction SilentlyContinue
    if ($null -eq $task) {
        Write-Warning "No task found"
        Exit
    }
    
    Unregister-ScheduledTask -TaskName "Disable-AutomaticCheckpoints" -Confirm:$false
    Write-Host "Task removed"
}

# check for administrative rights
Get-AdministrativeRightsInfo

switch ($PsCmdlet.ParameterSetName) {
    "Register" {
        Register-Watcher 
    }
    "Unregister" {
        Unregister-Watcher
    }
    "InstallTask" {
        Install-Task
    }
    "RemoveTask" {
        Remove-Task
    }
    "Help" {
        Write-Host  "Usage:"
        Write-Host  "Disable-AutomaticCheckpoints [-Register] [-Unregister] [-Help] [-InstallTask] [-RemoveTask] `n"
        
        Write-Host  "-Register:"
        Write-Host  "Register the event watcher. This also includes the action which will be taken when the event occurs `n"

        Write-Host  "-Unregister:"
        Write-Host  "Unregister the event watcher. `n"

        Write-Host  "-Help:"
        Write-Host  "Display this usage text. `n"

        Write-Host  "-InstallTask:"
        Write-Host  "Install the task which will register the event watcher on boot  `n"

        Write-Host  "-RemoveTask:"
        Write-Host  "Remove the task which will register the event watcher on boot  `n"
    }
}