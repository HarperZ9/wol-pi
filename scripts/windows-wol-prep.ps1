<#
.SYNOPSIS
  One-shot Windows prep for Wake-on-LAN. Run once, as Administrator.
.DESCRIPTION
  - Disables Fast Startup (the #1 reason WoL silently fails)
  - Enables Wake-on-Magic-Packet on the Ethernet NIC (driver advanced property + power management)
  - Tells the adapter that waking the PC is allowed
  - Sets the active power plan to allow wake timers
  - Prints a summary you can paste back to verify
.NOTES
  Safe to re-run. Leaves Wi-Fi alone because cable + WoL is the reliable path.
#>

[CmdletBinding()]
param(
    [string]$AdapterName = "Ethernet 3"
)

function Require-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Error "This script must run elevated (Run as Administrator)."
        exit 1
    }
}

Require-Admin

Write-Host "==> Step 1/4: disable Fast Startup"
powercfg /hibernate off 2>&1 | Out-Null
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -Value 0 -Type DWord
Write-Host "   Fast Startup disabled."

Write-Host "==> Step 2/4: enable Wake-on-Magic-Packet on '$AdapterName' driver properties"
$wakeProps = @(
    @{Name="Wake on Magic Packet";             Value="Enabled"},
    @{Name="Wake On Magic Packet From S5";     Value="Enabled"},
    @{Name="Wake on Pattern Match";            Value="Enabled"},
    @{Name="Energy-Efficient Ethernet";        Value="Disabled"},
    @{Name="Ultra Low Power Mode";             Value="Disabled"}
)
foreach ($p in $wakeProps) {
    try {
        Set-NetAdapterAdvancedProperty -Name $AdapterName -DisplayName $p.Name -DisplayValue $p.Value -ErrorAction Stop
        Write-Host "   $($p.Name) = $($p.Value)"
    } catch {
        Write-Host "   (skip) $($p.Name): $_"
    }
}

Write-Host "==> Step 3/4: enable 'allow this device to wake the computer'"
try {
    Enable-NetAdapterPowerManagement -Name $AdapterName -ErrorAction Stop
    Write-Host "   Power management cmdlet succeeded."
} catch {
    Write-Host "   Power-management cmdlet failed ($($_.Exception.Message)). Falling back to devcon/wmi path."
    # Fallback: set WakeOnMagicPacket via CIM
    try {
        $nic = Get-NetAdapter -Name $AdapterName
        $pnp = Get-WmiObject -Class MSPower_DeviceWakeEnable -Namespace root\wmi |
               Where-Object { $_.InstanceName -match [regex]::Escape($nic.PnPDeviceID) }
        if ($pnp) {
            $pnp.Enable = $true
            $pnp.Put() | Out-Null
            Write-Host "   WMI Enable=true written."
        }
    } catch {
        Write-Host "   WMI fallback also failed: $_"
    }
}

Write-Host "==> Step 4/4: power plan — allow wake timers"
$active = (powercfg /getactivescheme).Split()[3]
powercfg /setacvalueindex $active SUB_SLEEP RTCWAKE 1 2>&1 | Out-Null
powercfg /setdcvalueindex $active SUB_SLEEP RTCWAKE 1 2>&1 | Out-Null
powercfg /setactive $active 2>&1 | Out-Null
Write-Host "   Wake timers enabled on active plan."

Write-Host ""
Write-Host "=================================================="
Write-Host "Current wake state on '$AdapterName':"
Write-Host "=================================================="
Get-NetAdapterAdvancedProperty -Name $AdapterName | Where-Object { $_.DisplayName -match 'Wake|Magic' } |
    Select-Object DisplayName, DisplayValue | Format-Table -AutoSize

Write-Host "Devices that may wake the computer:"
powercfg /devicequery wake_armed

Write-Host ""
Write-Host "MAC to configure on the Pi:"
(Get-NetAdapter -Name $AdapterName).MacAddress

Write-Host ""
Write-Host "==> done. Remember:"
Write-Host "    - plug in the Ethernet cable and ensure link is up occasionally"
Write-Host "    - BIOS/UEFI must have 'Wake on LAN' or 'PCIe Wake-Up' enabled (one-time)"
Write-Host "    - full shutdown (shutdown /s /t 0) must complete, not just 'sleep'"
