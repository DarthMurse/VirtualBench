<#
.SYNOPSIS
  VirtualBench — Windows host (bare-metal) runner.

  Run this MANUALLY on the physical host. It CAPS itself to the VM's vCPU + RAM
  (via restrict.ps1 / Job Object) so the baseline is fair, runs the same logical
  workloads as the Linux guests using cross-platform tools, writes results to
  results/<label>/, and prints the git commands to commit + push.

  Usage:
    .\run.ps1 -Label host-baseline
    .\run.ps1 -Label host-baseline -Reps 5

  Prereqs on the host (put on PATH):
    7-Zip (7z.exe), fio (Windows build), iperf3 (Windows build).
  Use the SAME tool versions as the guests where possible (see docs/DESIGN.md).
#>
param(
  [Parameter(Mandatory=$true)][string]$Label,
  [int]$Reps,
  [string]$Config = "$PSScriptRoot/../config.json"
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. "$PSScriptRoot/restrict.ps1"

$repoRoot = (Resolve-Path "$PSScriptRoot/..").Path
$cfg = Get-Content $Config -Raw | ConvertFrom-Json
$vcpus  = $cfg.vm_spec.vcpus
$memMb  = $cfg.vm_spec.memory_mb
if (-not $Reps) { $Reps = $cfg.run.repetitions }
$warmup = $cfg.run.warmup_runs

# --- the whole point of the host run: cap to VM-equivalent resources ---
Set-ResourceCap -Vcpus $vcpus -MemoryMb $memMb

$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$resultsDir = Join-Path $repoRoot (Join-Path $cfg.run.results_dir $Label)
New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
$resultFile = Join-Path $resultsDir "result_$stamp.json"

$result = [ordered]@{
  meta = [ordered]@{
    label = $Label; timestamp = $stamp; hostname = $env:COMPUTERNAME
    os = (Get-CimInstance Win32_OperatingSystem).Caption
    allocated_vcpus = $vcpus; capped_memory_mb = $memMb
    physical_cpus = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
    repetitions = $Reps; runner = "windows"; capped = $true
  }
  metrics = @()
}

function Add-Metric($workload, $metric, $value, $unit, $params) {
  $script:result.metrics += [ordered]@{
    workload=$workload; metric=$metric; value=$value; unit=$unit; params=$params
  }
}

function Resolve-Tool($name) {
  $c = Get-Command $name -ErrorAction SilentlyContinue
  if (-not $c) { throw "MISSING TOOL: $name — install it and add to PATH" }
  return $c.Source
}

# --- workloads (cross-platform tools, matching bench/*.sh) ---

function Invoke-Cpu {
  $sevenz = Resolve-Tool "7z"
  $out = & $sevenz b "-mmt$vcpus" 2>$null
  $tot = ($out | Select-String '^Tot:').ToString()
  if ($tot -match '(\d+)\s*$') {
    Add-Metric "cpu" "7z_total_mips" ([double]$Matches[1]) "MIPS" @{threads=$vcpus}
    Write-Host "cpu: $($Matches[1]) MIPS"
  }
}

function Invoke-Disk {
  $fio = Resolve-Tool "fio"
  $d = $cfg.workloads.disk
  $testdir = Join-Path $env:TEMP "vbench_fio"
  New-Item -ItemType Directory -Force -Path $testdir | Out-Null
  foreach ($bs in $d.sizes) {
    foreach ($pat in $d.patterns) {
      # windowsaio is the native fio ioengine on Windows.
      $json = & $fio --name=vbench --directory="$testdir" --rw=$pat --bs=$bs `
        --iodepth=$($d.iodepth) --size=$($d.file_size) --runtime=$($d.runtime_s) `
        --time_based --ioengine=windowsaio --direct=1 --group_reporting --output-format=json 2>$null | ConvertFrom-Json
      $side = if ($pat -like "*write*") { "write" } else { "read" }
      $p = @{bs=$bs; pattern=$pat; iodepth=$d.iodepth}
      Add-Metric "disk" "iops"      $json.jobs[0].$side.iops "IOPS"  $p
      Add-Metric "disk" "bandwidth" $json.jobs[0].$side.bw   "KiB/s" $p
      Write-Host "disk $pat $bs: $($json.jobs[0].$side.iops) IOPS"
    }
  }
  Remove-Item -Recurse -Force $testdir
}

function Invoke-Net {
  $iperf = Resolve-Tool "iperf3"
  $server = $cfg.workloads.net.server
  try {
    $j = & $iperf -c $server -t $cfg.workloads.net.duration_s -J 2>$null | ConvertFrom-Json
    $mbps = $j.end.sum_received.bits_per_second / 1000000
    Add-Metric "net" "throughput" $mbps "Mbit/s" @{server=$server; proto="tcp"}
    Write-Host "net: $mbps Mbit/s"
  } catch {
    Write-Warning "net: iperf3 server $server unreachable — start 'iperf3 -s' there. Skipping."
    Add-Metric "net" "status" 0 "skipped" @{server=$server; reason="unreachable"}
  }
}

function Invoke-App {
  $sevenz = Resolve-Tool "7z"
  $work = Join-Path $env:TEMP "vbench_app"
  New-Item -ItemType Directory -Force -Path $work | Out-Null
  $blob = Join-Path $work "blob.bin"
  $fs = [IO.File]::OpenWrite($blob); $buf = New-Object byte[] (1MB)
  (New-Object Random).NextBytes($buf)
  for ($i=0; $i -lt 512; $i++) { $fs.Write($buf,0,$buf.Length) }; $fs.Close()
  $sw = [Diagnostics.Stopwatch]::StartNew()
  & $sevenz a "-mmt$vcpus" -mx5 (Join-Path $work "out.7z") $blob | Out-Null
  $sw.Stop()
  Add-Metric "app" "7z_compress_time" $sw.Elapsed.TotalSeconds "s" @{threads=$vcpus; level=5}
  Write-Host "app: 7z compress $($sw.Elapsed.TotalSeconds)s"
  Remove-Item -Recurse -Force $work
}

Write-Host "=== VirtualBench :: $Label :: $stamp (CAPPED $vcpus cpu / $memMb MB) ==="

# Warm-up (discarded).
for ($w=1; $w -le $warmup; $w++) { Write-Host "--- warmup $w/$warmup ---"; if ($cfg.workloads.cpu.enabled) { Invoke-Cpu | Out-Null } }
$result.metrics = @()  # clear anything added during warmup

for ($r=1; $r -le $Reps; $r++) {
  Write-Host "--- rep $r/$Reps ---"
  if ($cfg.workloads.cpu.enabled)  { Invoke-Cpu }
  if ($cfg.workloads.disk.enabled) { Invoke-Disk }
  if ($cfg.workloads.net.enabled)  { Invoke-Net }
  if ($cfg.workloads.app.enabled)  { Invoke-App }
  # NOTE: 'mem' uses sysbench (Linux). On Windows it's approximated by 7z CPU
  # throughput; see docs/DESIGN.md. Add a Windows memory bench here if desired.
}

$result | ConvertTo-Json -Depth 8 | Set-Content -Path $resultFile -Encoding utf8
Write-Host ""
Write-Host "=== DONE. Results: $resultFile ==="
Write-Host ""
Write-Host "To save these results, run:"
Write-Host "  cd `"$repoRoot`""
Write-Host "  git add `"results/$Label/`""
Write-Host "  git commit -m `"results($Label): run $stamp`""
Write-Host "  git push $($cfg.git.remote) $($cfg.git.branch)"
