# run_windows.ps1 — VirtualBench Windows host runner. Caps the process tree to the
# VM-equivalent resources, then runs the same workloads as the Linux runner using
# cross-platform tools (7-Zip CPU + app, fio disk, iperf3 + ping network). Memory
# bandwidth has no comparable Windows tool, so it is recorded as skipped.
# Missing tools are recorded as "skipped" rather than aborting the run.
#
# Usage: scripts\run_windows.ps1 -Label <name> [-Reps N] [-Config path]
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Label,
  [int]$Reps,
  [string]$Config
)
$ErrorActionPreference = "Stop"

$Repo = Split-Path -Parent $PSScriptRoot
if (-not $Config) { $Config = Join-Path $Repo "config.json" }
if (-not (Test-Path $Config)) { throw "config not found: $Config" }
. (Join-Path $Repo "src/lib/restrict.ps1")

$cfg     = Get-Content $Config -Raw | ConvertFrom-Json
$vcpus   = [int]$cfg.vm_spec.vcpus
$memMb   = [int]$cfg.vm_spec.memory_mb
if (-not $Reps) { $Reps = [int]$cfg.run.repetitions }
$warmup  = [int]$cfg.run.warmup_runs
$resDir  = Join-Path $Repo $cfg.run.results_dir

# Disk/app I/O must hit a real local volume to measure the host disk. When the repo lives on
# a UNC/9p share (e.g. a WSL checkout), fall back to a local TEMP scratch dir for fio/7z work.
$Scratch = if ($Repo -match '^[A-Za-z]:\\') { $Repo } else { $env:TEMP }

# Native tools (7-Zip's `b`) error out when the process current directory is a UNC path.
# Pin the process cwd to a local drive; all paths used below are absolute, so this is safe.
[Environment]::CurrentDirectory = $Scratch
Set-Location $Scratch

function Have($name) { return [bool](Get-Command $name -ErrorAction SilentlyContinue) }

# --- result file ----------------------------------------------------------
$stamp   = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$outdir  = Join-Path $resDir $Label
New-Item -ItemType Directory -Force -Path $outdir | Out-Null
$resultFile = Join-Path $outdir "result_$stamp.json"

$os = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue)
$result = [ordered]@{
  meta = [ordered]@{
    label           = $Label
    timestamp       = $stamp
    hostname        = $env:COMPUTERNAME
    os              = if ($os) { "$($os.Caption) $($os.Version)" } else { "Windows" }
    kernel          = [string][System.Environment]::OSVersion.Version
    allocated_vcpus = $vcpus
    visible_nproc   = [int]$env:NUMBER_OF_PROCESSORS
    total_mem_mb    = if ($os) { [int]($os.TotalVisibleMemorySize/1024) } else { 0 }
    repetitions     = $Reps
    runner          = "windows"
    capped          = $true
  }
  metrics = New-Object System.Collections.ArrayList
}

function Emit($workload,$metric,$value,$unit,$params) {
  $num = 0.0
  $v = if ([double]::TryParse([string]$value,[ref]$num)) { $num } else { [string]$value }
  [void]$result.metrics.Add([ordered]@{
    workload=$workload; metric=$metric; value=$v; unit=$unit; params=$params })
}

Write-Host "==> VirtualBench windows | label=$Label vcpus=$vcpus reps=$Reps warmup=$warmup"
$result.meta.capped = (Set-ResourceCap -Vcpus $vcpus -MemoryMb $memMb)

# Native benchmark tools (7z/fio/iperf3) write to stderr; with ErrorActionPreference="Stop"
# that stderr is promoted to a terminating error. Switch to Continue so the per-workload
# "skipped"/output checks below handle failures gracefully instead of aborting the run.
$ErrorActionPreference = "Continue"

# --- workloads ------------------------------------------------------------
function Invoke-Cpu($sink) {
  $p = @{ threads = $vcpus }
  if (-not (Have "7z")) { & $sink "cpu" "7z_total_mips" "skipped" "MIPS" $p; return }
  # NB: the arg MUST be quoted. PowerShell passes a bareword like -mmt$vcpus to a native
  # exe literally (no variable expansion for dash-prefixed tokens), so 7z would receive
  # "-mmt$vcpus" and fail with "parameter is incorrect". Quoting forces expansion.
  $out  = & 7z b "-mmt$vcpus" 2>$null
  $tot  = $out | Select-String '^Tot:' | Select-Object -First 1
  if ($tot) { & $sink "cpu" "7z_total_mips" (($tot -split '\s+')[-1]) "MIPS" $p }
  else      { & $sink "cpu" "7z_total_mips" "skipped" "MIPS" $p }
}

function Invoke-Mem($sink) {
  # No cross-platform memory bandwidth tool on Windows — documented limitation.
  & $sink "mem" "sysbench_read_MiBps"  "skipped" "MiB/s" @{ note = "no Windows equivalent" }
  & $sink "mem" "sysbench_write_MiBps" "skipped" "MiB/s" @{ note = "no Windows equivalent" }
}

function Invoke-Disk($sink) {
  $d = $cfg.workloads.disk
  $testdir = Join-Path $Scratch "fio_testdir"
  # fio parses ':' in --directory as a path separator, so a Windows drive letter must be
  # escaped (C:\x -> C\:\x). UNC paths have no drive-letter colon and pass through unchanged.
  $fioDir  = $testdir -replace '^([A-Za-z]):', '$1\:'
  $haveFio = Have "fio"
  if ($haveFio) { New-Item -ItemType Directory -Force -Path $testdir | Out-Null }
  foreach ($bs in $d.sizes) { foreach ($pat in $d.patterns) {
    $p = @{ bs=$bs; pattern=$pat; iodepth=[int]$d.iodepth }
    if (-not $haveFio) {
      & $sink "disk" "iops" "skipped" "IOPS" $p
      & $sink "disk" "bandwidth" "skipped" "KiB/s" $p
      & $sink "disk" "latency_avg" "skipped" "us" $p
      continue
    }
    $json = & fio --name=vbench --directory="$fioDir" --rw=$pat --bs=$bs `
                  --iodepth=$($d.iodepth) --size=$($d.file_size) --runtime=$($d.runtime_s) --time_based `
                  --ioengine=windowsaio --direct=1 --thread --group_reporting --output-format=json 2>$null | Out-String
    # fio may print warnings to stdout before the JSON (e.g. the shared-mutex notice), so
    # parse from the first '{' rather than feeding the whole string to ConvertFrom-Json.
    $start = if ($json) { $json.IndexOf('{') } else { -1 }
    if ($start -ge 0) {
      $j  = $json.Substring($start) | ConvertFrom-Json
      $job = $j.jobs[0]
      $rec = if ($job.read.iops -gt 0) { $job.read } else { $job.write }
      & $sink "disk" "iops" $rec.iops "IOPS" $p
      & $sink "disk" "bandwidth" $rec.bw "KiB/s" $p
      & $sink "disk" "latency_avg" ([math]::Round($rec.lat_ns.mean/1000,2)) "us" $p
    } else {
      & $sink "disk" "iops" "skipped" "IOPS" $p
      & $sink "disk" "bandwidth" "skipped" "KiB/s" $p
      & $sink "disk" "latency_avg" "skipped" "us" $p
    }
  }}
  if ($haveFio) { Remove-Item -Recurse -Force $testdir -ErrorAction SilentlyContinue }
}

function Invoke-Net($sink) {
  $n = $cfg.workloads.net
  $p = @{ server=$n.server; duration_s=[int]$n.duration_s; proto="tcp" }
  if (Have "iperf3") {
    $json = & iperf3 -c $n.server -t $n.duration_s -J 2>$null | Out-String
    if ($json -and ($json | ConvertFrom-Json).end.sum_received) {
      $j = $json | ConvertFrom-Json
      & $sink "net" "throughput" ([math]::Round($j.end.sum_received.bits_per_second/1e6,2)) "Mbit/s" $p
      & $sink "net" "retransmits" ([int]$j.end.sum_sent.retransmits) "count" $p
    } else {
      & $sink "net" "throughput" "skipped" "Mbit/s" $p
      & $sink "net" "retransmits" "skipped" "count" $p
    }
  } else {
    & $sink "net" "throughput" "skipped" "Mbit/s" $p
    & $sink "net" "retransmits" "skipped" "count" $p
  }
  $pp = @{ server=$n.server; count=[int]$n.ping_count }
  $ping = Test-Connection -ComputerName $n.server -Count $n.ping_count -ErrorAction SilentlyContinue
  if ($ping) {
    $avg = ($ping | Measure-Object -Property ResponseTime -Average).Average
    & $sink "net" "rtt_avg" ([math]::Round($avg,2)) "ms" $pp
  } else {
    & $sink "net" "rtt_avg" "skipped" "ms" $pp
  }
}

function Invoke-App($sink) {
  $a = $cfg.workloads.app
  $p = @{ threads=$vcpus; level=[int]$a.level; corpus_mb=[int]$a.corpus_mb }
  if (-not (Have "7z")) { & $sink "app" "7z_compress_time" "skipped" "s" $p; return }
  $work = Join-Path $Scratch "app_testdir"
  New-Item -ItemType Directory -Force -Path $work | Out-Null
  try {
    $halfMb = [int]($a.corpus_mb/2)
    $blob = Join-Path $work "blob.bin"; $text = Join-Path $work "text.txt"
    $buf = New-Object byte[] (1MB); (New-Object Random).NextBytes($buf)
    $fs = [IO.File]::OpenWrite($blob); for ($i=0;$i -lt $halfMb;$i++){ $fs.Write($buf,0,$buf.Length) }; $fs.Close()
    $line = ("the quick brown fox jumps over the lazy dog`n") * 20000
    $sw = [IO.StreamWriter]::new($text); for ($i=0;$i -lt $halfMb;$i++){ $sw.Write($line) }; $sw.Close()
    # Quote the switches so PowerShell expands $vcpus/$a.level (see note in Invoke-Cpu).
    $archive = Join-Path $work "out.7z"
    $t = Measure-Command { & 7z a "-mmt$vcpus" "-mx$($a.level)" $archive $blob $text 2>$null | Out-Null }
    # Only record a time if the archive was actually produced; otherwise the compression failed.
    if (Test-Path $archive) { & $sink "app" "7z_compress_time" ([math]::Round($t.TotalSeconds,3)) "s" $p }
    else                    { & $sink "app" "7z_compress_time" "skipped" "s" $p }
  } finally { Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue }
}

function Run-All($sink) {
  if ($cfg.workloads.cpu.enabled)  { Invoke-Cpu  $sink }
  if ($cfg.workloads.mem.enabled)  { Invoke-Mem  $sink }
  if ($cfg.workloads.disk.enabled) { Invoke-Disk $sink }
  if ($cfg.workloads.net.enabled)  { Invoke-Net  $sink }
  if ($cfg.workloads.app.enabled)  { Invoke-App  $sink }
}

# warmup discards into a no-op sink; measured passes use Emit.
$discard = { param($w,$m,$v,$u,$p) }
for ($i=1; $i -le $warmup; $i++) { Write-Host "--- warmup $i/$warmup ---"; Run-All $discard }
for ($i=1; $i -le $Reps;   $i++) { Write-Host "--- rep $i/$Reps ---";     Run-All ${function:Emit} }

# Write UTF-8 WITHOUT a BOM. PowerShell 5.1's `Set-Content -Encoding UTF8` prepends a BOM,
# which trips the stdlib JSON reader in analyze.py (json.load can't skip a BOM).
$json = $result | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText($resultFile, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "==> done. results in $resultFile"
Write-Host "==> analyze with: python3 analyze/analyze.py results"
