# restrict.ps1 — cap the current process tree to N CPUs-worth of compute and a memory
# ceiling using a Windows Job Object, so the host baseline is measured under VM-equivalent
# resources. Best-effort: Set-ResourceCap returns $true on success, $false (with a warning)
# if the OS/permissions don't allow it. Affects all child processes (7z, fio, iperf3, ...).
#
# CPU is capped with a Job Object *CPU rate* hard cap (= vcpus / total_logical_cores), NOT
# an affinity mask. An affinity mask restricts which cores the tree may use, but benchmark
# tools (7-Zip's `b`, fio's clock calibration) call SetThreadAffinityMask for cores of their
# own choosing; when those land outside the allowed set the call fails and the tool aborts.
# A rate cap throttles total cycles instead — the same "fewer vCPUs" effect, tool-compatible.
#
# Dot-source this file, then call: Set-ResourceCap -Vcpus 4 -MemoryMb 8192

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class VbenchJob {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)]
  public static extern IntPtr CreateJobObject(IntPtr a, string lpName);
  [DllImport("kernel32.dll")]
  public static extern bool SetInformationJobObject(IntPtr hJob, int infoClass, IntPtr lpInfo, uint cb);
  [DllImport("kernel32.dll")]
  public static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProcess);
  [DllImport("kernel32.dll")]
  public static extern IntPtr GetCurrentProcess();
}
"@ -ErrorAction SilentlyContinue

function Set-ResourceCap {
  param([Parameter(Mandatory=$true)][int]$Vcpus,
        [Parameter(Mandatory=$true)][int]$MemoryMb)
  try {
    $job = [VbenchJob]::CreateJobObject([IntPtr]::Zero, $null)
    if ($job -eq [IntPtr]::Zero) { throw "CreateJobObject failed" }

    # 1) Memory ceiling via JOBOBJECT_EXTENDED_LIMIT_INFORMATION (class 9, x64 layout):
    #    LimitFlags @16 = JOB_MEMORY(0x200); IO_COUNTERS span 64..112; JobMemoryLimit @120.
    $size = 144
    $ptr  = [Runtime.InteropServices.Marshal]::AllocHGlobal($size)
    try {
      for ($i=0; $i -lt $size; $i++) { [Runtime.InteropServices.Marshal]::WriteByte($ptr,$i,0) }
      [Runtime.InteropServices.Marshal]::WriteInt32($ptr, 16, 0x200)         # LimitFlags = JOB_MEMORY
      [Runtime.InteropServices.Marshal]::WriteIntPtr($ptr, 120, [IntPtr]([Int64]$MemoryMb * 1MB)) # JobMemoryLimit
      if (-not [VbenchJob]::SetInformationJobObject($job, 9, $ptr, $size)) { throw "set memory limit failed" }
    } finally {
      [Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)
    }

    # 2) CPU hard cap via JOBOBJECT_CPU_RATE_CONTROL_INFORMATION (class 15, 8 bytes):
    #    ControlFlags @0 = ENABLE(0x1)|HARD_CAP(0x4); CpuRate @4 in 1/100ths of a percent
    #    (1..10000). Cap = vcpus / total_logical_cores. Skip if asking for >= all cores.
    $total = [int]$env:NUMBER_OF_PROCESSORS
    if ($total -lt 1) { $total = [Environment]::ProcessorCount }
    $cpuApplied = $false
    if ($Vcpus -lt $total) {
      $rate = [int][math]::Round(($Vcpus / $total) * 10000)
      if ($rate -lt 1) { $rate = 1 } elseif ($rate -gt 10000) { $rate = 10000 }
      $cptr = [Runtime.InteropServices.Marshal]::AllocHGlobal(8)
      try {
        [Runtime.InteropServices.Marshal]::WriteInt32($cptr, 0, (0x1 -bor 0x4)) # ENABLE | HARD_CAP
        [Runtime.InteropServices.Marshal]::WriteInt32($cptr, 4, $rate)          # CpuRate
        if (-not [VbenchJob]::SetInformationJobObject($job, 15, $cptr, 8)) { throw "set cpu rate failed" }
        $cpuApplied = $true
      } finally {
        [Runtime.InteropServices.Marshal]::FreeHGlobal($cptr)
      }
    }

    if (-not [VbenchJob]::AssignProcessToJobObject($job, [VbenchJob]::GetCurrentProcess())) {
      throw "AssignProcessToJobObject failed"
    }
    $cpuDesc = if ($cpuApplied) { "$Vcpus/$total cores (hard cap)" } else { "$Vcpus vCPUs (uncapped: >= host cores)" }
    Write-Host "==> resource cap applied: CPU $cpuDesc, mem $MemoryMb MB"
    return $true
  } catch {
    Write-Warning "resource cap not applied ($($_.Exception.Message)); running uncapped"
    return $false
  }
}
