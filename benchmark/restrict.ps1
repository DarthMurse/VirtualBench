<#
.SYNOPSIS
  Resource capping for the bare-metal HOST run, so the host baseline uses the
  SAME amount of CPU + RAM as the VMs (fair comparison).

  Implemented with a Windows Job Object:
    - CPU: affinity mask limited to the first <Vcpus> logical processors.
    - RAM: JOB_OBJECT_LIMIT_JOB_MEMORY caps total committed memory for every
           process in the job to <MemoryMb>.
  The current PowerShell process is assigned to the job; all bench tools it
  spawns (7z, fio, iperf3) inherit the cap automatically.

  Call Set-ResourceCap once near the top of run.ps1 before any workload.
  Requires Windows 8 / Server 2012+ (nested job objects).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not ([System.Management.Automation.PSTypeName]'VBench.JobCap').Type) {
  Add-Type @"
using System;
using System.Runtime.InteropServices;
namespace VBench {
  public static class JobCap {
    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
      public long PerProcessUserTimeLimit;
      public long PerJobUserTimeLimit;
      public uint LimitFlags;
      public UIntPtr MinimumWorkingSetSize;
      public UIntPtr MaximumWorkingSetSize;
      public uint ActiveProcessLimit;
      public UIntPtr Affinity;
      public uint PriorityClass;
      public uint SchedulingClass;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct IO_COUNTERS {
      public ulong ReadOperationCount, WriteOperationCount, OtherOperationCount;
      public ulong ReadTransferCount, WriteTransferCount, OtherTransferCount;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
      public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
      public IO_COUNTERS IoInfo;
      public UIntPtr ProcessMemoryLimit;
      public UIntPtr JobMemoryLimit;
      public UIntPtr PeakProcessMemoryUsed;
      public UIntPtr PeakJobMemoryUsed;
    }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)]
    public static extern IntPtr CreateJobObject(IntPtr a, string name);
    [DllImport("kernel32.dll")]
    public static extern bool SetInformationJobObject(IntPtr job, int cls, IntPtr info, uint len);
    [DllImport("kernel32.dll")]
    public static extern bool AssignProcessToJobObject(IntPtr job, IntPtr proc);
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetCurrentProcess();

    const int ExtendedLimitClass = 9;
    const uint LIMIT_AFFINITY    = 0x00000010;
    const uint LIMIT_JOB_MEMORY  = 0x00000200;

    public static void Apply(int vcpus, long memoryBytes) {
      IntPtr job = CreateJobObject(IntPtr.Zero, null);
      if (job == IntPtr.Zero) throw new Exception("CreateJobObject failed");

      var ext = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
      ext.BasicLimitInformation.LimitFlags = LIMIT_AFFINITY | LIMIT_JOB_MEMORY;
      // affinity mask = first <vcpus> logical processors
      ulong mask = (vcpus >= 64) ? ulong.MaxValue : ((1UL << vcpus) - 1UL);
      ext.BasicLimitInformation.Affinity = (UIntPtr)mask;
      ext.JobMemoryLimit = (UIntPtr)(ulong)memoryBytes;

      int len = Marshal.SizeOf(ext);
      IntPtr p = Marshal.AllocHGlobal(len);
      try {
        Marshal.StructureToPtr(ext, p, false);
        if (!SetInformationJobObject(job, ExtendedLimitClass, p, (uint)len))
          throw new Exception("SetInformationJobObject failed: " + Marshal.GetLastWin32Error());
        if (!AssignProcessToJobObject(job, GetCurrentProcess()))
          throw new Exception("AssignProcessToJobObject failed: " + Marshal.GetLastWin32Error());
      } finally { Marshal.FreeHGlobal(p); }
    }
  }
}
"@
}

function Set-ResourceCap {
  param([int]$Vcpus, [int]$MemoryMb)
  [VBench.JobCap]::Apply($Vcpus, [int64]$MemoryMb * 1MB)
  Write-Host "[cap] Host run limited to $Vcpus logical CPUs and ${MemoryMb} MB (Job Object)."
}
