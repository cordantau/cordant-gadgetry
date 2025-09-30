<# 
.SYNOPSIS
  Reset (clean) FSLogix profile for a user:
   - Clears local Cloud Cache/Proxy on this host
   - (Optional) Deletes remote VHD/VHDX from all CCDLocations (Profiles + ODFC)

.PARAMETER User
  SAM/UPN/DOMAIN\User. Use this OR -Sid.

.PARAMETER Sid
  User SID. Use this OR -User.

.PARAMETER AlsoRemoveRemote
  If set, removes VHD/VHDX from all configured CCDLocations (Profiles + ODFC).

.PARAMETER WhatIf
  Dry run for destructive actions.

.NOTES
  Run as Administrator. Test in a maintenance window.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [Parameter(ParameterSetName = 'ByUser', Mandatory = $true)]
  [string]$User,

  [Parameter(ParameterSetName = 'BySid', Mandatory = $true)]
  [string]$Sid,

  [switch]$AlsoRemoveRemote
)

function Assert-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "This script must be run as Administrator."
  }
}

function Resolve-Sid {
  param([string]$User, [string]$Sid)
  if ($Sid) { return $Sid }
  try {
    return ((New-Object System.Security.Principal.NTAccount($User)).Translate([System.Security.Principal.SecurityIdentifier])).Value
  }
  catch {
    throw "Could not resolve SID for user '$User'. $_"
  }
}

function Resolve-UserNameFromSid {
  param([string]$Sid)
  try {
    return ((New-Object System.Security.Principal.SecurityIdentifier($Sid)).Translate([System.Security.Principal.NTAccount])).Value
  }
  catch {
    return $null
  }
}

function Stop-FrxSvc {
  Write-Verbose "Stopping FSLogix service (frxsvc)..."
  $svc = Get-Service -Name 'frxsvc' -ErrorAction SilentlyContinue
  if ($svc -and $svc.Status -eq 'Running') {
    Stop-Service -Name 'frxsvc' -Force -ErrorAction Stop
    $svc.WaitForStatus('Stopped', '00:00:15')
  }
}

function Start-FrxSvc {
  Write-Verbose "Starting FSLogix service (frxsvc)..."
  Start-Service -Name 'frxsvc' -ErrorAction Stop
}

function Get-CCDLocations {
  param([string]$RootKey)
  $paths = @()
  try {
    $val = Get-ItemProperty -Path $RootKey -Name 'CCDLocations' -ErrorAction Stop | Select-Object -ExpandProperty CCDLocations
    if ($val -is [string]) { $paths += $val }
    elseif ($val -is [array]) { $paths += $val }
  }
  catch { } # key or value may not exist
  # Normalise trailing backslashes
  $paths = $paths | Where-Object { $_ -and $_.Trim() -ne '' } | ForEach-Object {
    ($_ -replace '[\\/]+$', '')  # strip trailing slash
  }
  return $paths | Select-Object -Unique
}

function Remove-LocalCacheForSid {
  param([string]$Sid)
  $base = 'C:\ProgramData\FSLogix'
  $targets = @(
    Join-Path $base "Cache\$Sid",
    Join-Path $base "Proxy\$Sid"
  )
  foreach ($t in $targets) {
    if (Test-Path $t) {
      if ($PSCmdlet.ShouldProcess($t, "Remove local cache folder")) {
        try {
          # Try to make deletions more reliable if filter/handles are lingering
          cmd /c "attrib -r -s -h `"$t`" /s /d" | Out-Null
          Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction Stop
          Write-Host "[OK] Removed $t"
        }
        catch {
          Write-Warning "Failed to remove $t : $_"
        }
      }
    }
    else {
      Write-Verbose "Local cache path not found: $t"
    }
  }
}

function Build-RemoteDeleteCandidates {
  param(
    [string[]]$Locations,
    [string]$Sid,
    [string]$UserName
  )
  $namesToTry = @()
  # Try common naming patterns used by FSLogix
  if ($UserName) {
    $sam = ($UserName -split '\\')[-1]
    $namesToTry += @(
      "$sam.vhdx", "$sam.VHDX", "$sam.vhd", "$sam.VHD",
      "$Sid.vhdx", "$Sid.VHDX", "$Sid.vhd", "$Sid.VHD"
    )
  }
  else {
    $namesToTry += @("$Sid.vhdx", "$Sid.VHDX", "$Sid.vhd", "$Sid.VHD")
  }

  $candidates = @()
  foreach ($loc in $Locations) {
    foreach ($n in $namesToTry) {
      $p = Join-Path $loc $n
      $candidates += $p
    }
    # Also include subfolder conventions: \%username%\*.vhdx or \SID\*.vhdx
    if ($UserName) {
      $sam = ($UserName -split '\\')[-1]
      $candidates += Join-Path (Join-Path $loc $sam) '*.vhd*'
    }
    $candidates += Join-Path (Join-Path $loc $Sid) '*.vhd*'
  }
  $candidates | Select-Object -Unique
}

function Remove-RemoteProfiles {
  param(
    [string[]]$Locations,
    [string]$Sid,
    [string]$UserName
  )
  if (-not $Locations -or $Locations.Count -eq 0) {
    Write-Verbose "No CCDLocations configured for this container type."
    return
  }

  $candidates = Build-RemoteDeleteCandidates -Locations $Locations -Sid $Sid -UserName $UserName
  $matched = @()

  foreach ($pattern in $candidates) {
    try {
      # Support wildcards (e.g., ...\username\*.vhdx)
      $files = Get-Item $pattern -ErrorAction SilentlyContinue
      if ($files) { $matched += $files }
    }
    catch { }
  }

  $matched = $matched | Sort-Object -Property FullName -Unique
  if (-not $matched -or $matched.Count -eq 0) {
    Write-Host "[INFO] No remote VHD/VHDX files matched for $Sid ($UserName) under configured CCDLocations."
    return
  }

  Write-Host "[INFO] Found remote files:"
  $matched | ForEach-Object { Write-Host "  - $($_.FullName)" }

  foreach ($f in $matched) {
    if ($PSCmdlet.ShouldProcess($f.FullName, "Delete remote profile container")) {
      try {
        # Clear read-only & hidden attrs in case
        cmd /c "attrib -r -s -h `"$($f.FullName)`"" | Out-Null
        Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
        Write-Host "[OK] Deleted $($f.FullName)"
      }
      catch {
        Write-Warning "Failed to delete $($f.FullName): $_"
      }
    }
  }
}

# -------------------- MAIN --------------------
try {
  Assert-Admin

  $resolvedSid = Resolve-Sid -User $User -Sid $Sid
  $resolvedUser = Resolve-UserNameFromSid -Sid $resolvedSid
  Write-Host "Target SID : $resolvedSid"
  if ($resolvedUser) { Write-Host "User      : $resolvedUser" }

  # Stop FSLogix to release local handles
  Stop-FrxSvc

  # Remove local cache (Cache + Proxy)
  Remove-LocalCacheForSid -Sid $resolvedSid

  if ($AlsoRemoveRemote) {
    Write-Host "[INFO] Removing remote containers from all configured Cloud Cache locations..."

    # Profiles (user profile container)
    $profileLocs = Get-CCDLocations -RootKey 'HKLM:\SOFTWARE\FSLogix\Profiles'
    if ($profileLocs) {
      Write-Host "[INFO] Profiles CCDLocations:"
      $profileLocs | ForEach-Object { Write-Host "  - $_" }
      Remove-RemoteProfiles -Locations $profileLocs -Sid $resolvedSid -UserName $resolvedUser
    }
    else {
      Write-Verbose "No Profiles CCDLocations found."
    }

    # ODFC (Office container, if you use it)
    $odfcLocs = Get-CCDLocations -RootKey 'HKLM:\SOFTWARE\FSLogix\ODFC'
    if ($odfcLocs) {
      Write-Host "[INFO] ODFC CCDLocations:"
      $odfcLocs | ForEach-Object { Write-Host "  - $_" }
      Remove-RemoteProfiles -Locations $odfcLocs -Sid $resolvedSid -UserName $resolvedUser
    }
    else {
      Write-Verbose "No ODFC CCDLocations found."
    }
  }
  else {
    Write-Host "[INFO] Skipping remote container deletion (no -AlsoRemoveRemote)."
  }

}
finally {
  # Always try to restart frxsvc
  try { Start-FrxSvc } catch { Write-Warning "Could not start frxsvc: $_" }
  Write-Host "[DONE] You can have the user log on to rebuild a fresh profile."
}
 