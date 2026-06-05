# restrict.ps1 — cap the current process tree to N CPUs and a memory ceiling using a
# Windows Job Object, so the host baseline is measured under VM-equivalent resources.
# Best-effort: Set-ResourceCap returns $true on success, $false (with a warning) if the
# OS/permissions don't allow it. Affects all child processes (7z, fio, iperf3, ...).
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

    # JOBOBJECT_EXTENDED_LIMIT_INFORMATION layout (x64).
    # BasicLimitInformation occupies the first 112 bytes; JobMemoryLimit at offset 128;
    # ProcessMemoryLimit at 120. We set LimitFlags = AFFINITY(0x10) | JOB_MEMORY(0x200).
    $size = 144
    $ptr  = [Runtime.InteropServices.Marshal]::AllocHGlobal($size)
    try {
      for ($i=0; $i -lt $size; $i++) { [Runtime.InteropServices.Marshal]::WriteByte($ptr,$i,0) }
      $affinity = ([UInt64]1 -shl $Vcpus) - 1            # first N logical processors
      $flags    = 0x10 -bor 0x200
      [Runtime.InteropServices.Marshal]::WriteInt32($ptr, 16, $flags)        # LimitFlags
      [Runtime.InteropServices.Marshal]::WriteIntPtr($ptr, 24, [IntPtr]$affinity) # Affinity
      [Runtime.InteropServices.Marshal]::WriteIntPtr($ptr, 128, [IntPtr]([Int64]$MemoryMb * 1MB)) # JobMemoryLimit
      $ok = [VbenchJob]::SetInformationJobObject($job, 9, $ptr, $size)        # 9 = ExtendedLimitInformation
      if (-not $ok) { throw "SetInformationJobObject failed" }
    } finally {
      [Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)
    }

    if (-not [VbenchJob]::AssignProcessToJobObject($job, [VbenchJob]::GetCurrentProcess())) {
      throw "AssignProcessToJobObject failed"
    }
    Write-Host "==> resource cap applied: $Vcpus vCPUs, $MemoryMb MB"
    return $true
  } catch {
    Write-Warning "resource cap not applied ($($_.Exception.Message)); running uncapped"
    return $false
  }
}
