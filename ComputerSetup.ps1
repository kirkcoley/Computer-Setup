# Install NuGet, Download PSWindowsUpdate Module from PSGallery
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module PSWindowsUpdate
Import-Module PSWindowsUpdate

# Declare functions for Bitlocker progress
function Get-BitLockerStatus {
    $status = & manage-bde.exe -status C:
    $status = $status -join " "
    $Matches = $null
    $status -match '\:\s([\d]{2,})\.\d\%' | Out-Null
    $Matches[1]
}

function Display-BitlockerProgress{
    $Loop = $true
    while($true){
        [int]$progress = Get-BitLockerStatus
        if($progress -ne 100){
            Write-Progress -Activity "Bitlocker Progress" -Status "Working" -PercentComplete $progress
            Start-Sleep -Seconds 2
        }
        else{
            Write-Progress -Activity "Bitlocker Progress" -Completed
            $Loop = $false
        }
    }
}

# Create Credential
$cred = Get-Credential

# Install Windows Updates
Install-WindowsUpdate -AcceptAll

# Create a workflow so that the script can continue after the reboot
workflow Reboot-Reencrypt{

    # Join computer to domain (input computer name when prompted) and restart
    Add-Computer -DomainCredential $cred -DomainName domain.com -OUPath "OU=01_Computers_General_Windows,OU=01_Computers_General,OU=01_Computers,OU=Managed,DC=domain,DC=com" -Restart

    # Enforce Group Policy
    gpudate /force
    
    # Decrypt
    manage-bde.exe -off C:
    Display-BitlockerProgress

    # Use stronger encryption
    manage-bde.exe -on C: -rp -em xts_aes256 -s
    Display-BitlockerProgress
    
}

# Provide the executable and command line options
$executable = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
$arguments = '-NonInteractive -WindowStyle Hidden -NoLogo -NoProfile -NoExit -Command "& {Import-Module PSWorkflow ; Get-Job | Resume-Job}"'

# Create task, provide required options, and create trigger 
$taskAction = New-ScheduledTaskAction -Execute $executable -Argument $arguments
$taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -WakeToRun
$trigger = New-JobTrigger -AtStartup -RandomDelay (New-TimeSpan -Minutes 5)

# Register task with system, then call the workflow
Register-ScheduledTask -TaskName ContinueWorkflow -Action $taskAction -Trigger $trigger -Settings $taskSettings -RunLevel Highest

Reboot-Reencrypt -ASJob