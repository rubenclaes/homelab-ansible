# Schijfgezondheid voor Alloy op de pc van je ouders, in het textfile-formaat
# van Prometheus. Draait als geplande taak (SYSTEM, bij de opstart en elk uur)
# en schrijft C:\ProgramData\homelab\textfile\disk.prom. Alloy leest die map
# (textfile-collector in windows-family.alloy).
#
# Waarom een script: Alloy heeft geen diskdrive-collector. Get-PhysicalDisk en
# Get-StorageReliabilityCounter geven bovendien meer dan die collector: de
# slijtage van een SSD, de temperatuur en de leesfouten.

$dir = 'C:\ProgramData\homelab\textfile'
New-Item -ItemType Directory -Force -Path $dir | Out-Null

$lines = @(
    '# HELP windows_disk_healthy 1 als Windows de schijf Healthy noemt.'
    '# TYPE windows_disk_healthy gauge'
)
$extra = @()

foreach ($d in Get-PhysicalDisk) {
    $name = ($d.FriendlyName -replace '[\\"]', '').Trim()
    $l = "disk=`"$name`",media=`"$($d.MediaType)`",serial=`"$(($d.SerialNumber -replace '[\\"\s]', ''))`""
    $lines += "windows_disk_healthy{$l} $([int]($d.HealthStatus -eq 'Healthy'))"

    $r = $d | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
    if ($r) {
        if ($null -ne $r.Wear)                  { $extra += "windows_disk_wear_percent{$l} $($r.Wear)" }
        if ($r.Temperature)                     { $extra += "windows_disk_temperature_celsius{$l} $($r.Temperature)" }
        if ($null -ne $r.ReadErrorsUncorrected) { $extra += "windows_disk_read_errors_uncorrected{$l} $($r.ReadErrorsUncorrected)" }
        if ($null -ne $r.PowerOnHours)          { $extra += "windows_disk_power_on_hours{$l} $($r.PowerOnHours)" }
    }
}

$lines += $extra
$lines += "windows_disk_health_last_run_timestamp_seconds $([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"

# Eerst naar een tijdelijk bestand en dan verplaatsen: Alloy mag nooit een half
# bestand lezen. ASCII zonder BOM, en eindigen op een lege regel.
$tmp = Join-Path $dir 'disk.prom.tmp'
[IO.File]::WriteAllText($tmp, (($lines -join "`n") + "`n"), [Text.Encoding]::ASCII)
Move-Item -Force $tmp (Join-Path $dir 'disk.prom')
