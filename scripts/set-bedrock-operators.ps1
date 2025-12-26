[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string[]]$ServerPaths = @("creative_data", "survival_data"),
    [string[]]$ContainerNames = @("minecraft-creative", "minecraft-survival"),
    [int]$LogSinceHours = 720,
    [switch]$Backup
)

function Merge-Permissions {
    param(
        [Parameter(Mandatory)] [array]$Existing,
        [Parameter(Mandatory)] [string[]]$OperatorXuids
    )
    # Build a map of xuid -> permission entry
    $map = @{}
    foreach ($entry in $Existing) {
        if ($null -ne $entry -and $entry.PSObject.Properties.Match('xuid').Count -gt 0 -and
            [string]::IsNullOrWhiteSpace([string]$entry.xuid) -eq $false) {
            $map[$entry.xuid] = $entry
        }
    }

    foreach ($x in $OperatorXuids | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique) {
        if ($map.ContainsKey($x)) {
            # Ensure permission is operator
            $map[$x].permission = 'operator'
        } else {
            $map[$x] = [pscustomobject]@{ permission = 'operator'; xuid = $x }
        }
    }

    return $map.GetEnumerator() | ForEach-Object { $_.Value }
}

function Read-JsonArray {
    param(
        [Parameter(Mandatory)] [string]$Path
    )
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return @() }
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($obj -is [System.Array]) { return $obj }
        elseif ($null -eq $obj) { return @() }
        else { return @($obj) }
    } catch {
        Write-Warning "Failed to parse JSON at $($Path): $($_.Exception.Message)"
        return @()
    }
}

function Ensure-Operator-PermissionsForServer {
    param(
        [Parameter(Mandatory)] [string]$ServerPath,
        [Parameter(Mandatory)] [hashtable]$XuidMap
    )

    $absServerPath = Resolve-Path -LiteralPath $ServerPath -ErrorAction SilentlyContinue
    if (-not $absServerPath) {
        Write-Warning "Server path not found: $ServerPath"
        return
    }
    $abs = $absServerPath.Path

    $allowPath = Join-Path $abs 'allowlist.json'
    $permPath  = Join-Path $abs 'permissions.json'

    $allow = Read-JsonArray -Path $allowPath
    if ($allow.Count -eq 0) {
        Write-Host "[$ServerPath] No allowlist entries found (or file missing). Skipping." -ForegroundColor Yellow
        return
    }

    $xuids = @()
    foreach ($e in $allow) {
        if (-not $e) { continue }
        $x = $null
        if ($e.PSObject.Properties.Match('xuid').Count -gt 0) {
            $x = [string]$e.xuid
        }
        if (([string]::IsNullOrWhiteSpace($x)) -and $e.PSObject.Properties.Match('name').Count -gt 0) {
            $name = [string]$e.name
            if (-not [string]::IsNullOrWhiteSpace($name)) {
                if ($XuidMap.ContainsKey($name)) { $x = [string]$XuidMap[$name] }
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($x)) { $xuids += $x }
    }
    $xuids = $xuids | Select-Object -Unique

    if ($xuids.Count -eq 0) {
        Write-Host "[$ServerPath] No XUIDs found in allowlist (or via logs). Skipping." -ForegroundColor Yellow
        return
    }

    $existing = Read-JsonArray -Path $permPath
    $merged   = Merge-Permissions -Existing $existing -OperatorXuids $xuids

    $jsonOut = $merged | ConvertTo-Json -Depth 10

    if ($PSCmdlet.ShouldProcess($permPath, "Write operator permissions for allowlisted users")) {
        if ($Backup -and (Test-Path -LiteralPath $permPath)) {
            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $bak   = "$permPath.bak-$stamp"
            try {
                Copy-Item -LiteralPath $permPath -Destination $bak -Force
                Write-Host "[$ServerPath] Backup saved: $bak" -ForegroundColor DarkGray
            } catch {
                Write-Warning "[$ServerPath] Failed to create backup: $($_.Exception.Message)"
            }
        }
        try {
            $jsonOut | Set-Content -LiteralPath $permPath -Encoding UTF8
            Write-Host "[$ServerPath] Updated permissions.json with $($xuids.Count) operator(s)." -ForegroundColor Green
        } catch {
            Write-Error "[$ServerPath] Failed to write $($permPath): $($_.Exception.Message)"
        }
    } else {
        Write-Host "[$ServerPath] Would update permissions.json with $($xuids.Count) operator(s)." -ForegroundColor Cyan
    }
}

function Get-XuidMapFromLogs {
    param(
        [Parameter(Mandatory)] [string[]]$Containers,
        [int]$SinceHours = 720
    )
    $map = @{}
    foreach ($c in $Containers) {
        try {
            $args = @('logs', $c, '--since', "${SinceHours}h")
            $out = & docker @args 2>$null | Out-String
            if ([string]::IsNullOrWhiteSpace($out)) { continue }
            foreach ($line in $out -split "`r?`n") {
                $m = [regex]::Match($line, 'Player\s+(?:connected|Spawned):\s*([^,]+?)(?:,|\s)\s*xuid:\s*(\d+)')
                if ($m.Success) {
                    $name = $m.Groups[1].Value.Trim()
                    $xuid = $m.Groups[2].Value.Trim()
                    if (-not [string]::IsNullOrWhiteSpace($name) -and -not [string]::IsNullOrWhiteSpace($xuid)) {
                        $map[$name] = $xuid
                    }
                }
            }
        } catch {
            Write-Verbose "Failed to read logs from $($c): $($_.Exception.Message)"
        }
    }
    return $map
}

# Main
$xuidMap = Get-XuidMapFromLogs -Containers $ContainerNames -SinceHours $LogSinceHours
foreach ($path in $ServerPaths) {
    Ensure-Operator-PermissionsForServer -ServerPath $path -XuidMap $xuidMap
}

Write-Host "Done. Restart the Minecraft containers to apply changes:" -ForegroundColor DarkGray
Write-Host "  docker compose restart minecraft-creative minecraft-survival" -ForegroundColor DarkGray
