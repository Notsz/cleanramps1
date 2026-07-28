#requires -RunAsAdministrator
<#
.SYNOPSIS
    Notsz - Limpeza completa de RAM
    Working Sets + Modified List + Standby List + File System Cache
#>

Add-Type -AssemblyName PresentationFramework

# Evitar erro "tipo ja existe" se correr multiplas vezes na mesma sessao
try {
Add-Type -Namespace NotszMem -Name RAM -MemberDefinition @"
[DllImport("ntdll.dll")]
public static extern uint NtSetSystemInformation(int cls, IntPtr buf, int len);

[DllImport("advapi32.dll", SetLastError=true)]
public static extern bool OpenProcessToken(IntPtr proc, uint access, out IntPtr token);

[DllImport("advapi32.dll", SetLastError=true)]
public static extern bool LookupPrivilegeValue(string sys, string name, out long luid);

[DllImport("advapi32.dll", SetLastError=true)]
public static extern bool AdjustTokenPrivileges(IntPtr token, bool disable, ref TP tp, uint len, IntPtr prev, IntPtr ret);

[DllImport("kernel32.dll")]
public static extern IntPtr GetCurrentProcess();

[StructLayout(LayoutKind.Sequential, Pack=4)]
public struct TP { public uint Count; public long Luid; public uint Attribs; }

[StructLayout(LayoutKind.Sequential)]
public struct FILECACHE {
    public IntPtr CurrentSize;
    public IntPtr PeakSize;
    public uint PageFaultCount;
    public IntPtr MinimumWorkingSet;
    public IntPtr MaximumWorkingSet;
    public IntPtr CurrentSizeIncludingTransitionInPages;
    public IntPtr PeakSizeIncludingTransitionInPages;
    public uint TransitionRePurposeCount;
    public uint Flags;
}
"@
} catch {}

function Enable-Priv([string]$name) {
    $tok = [IntPtr]::Zero
    [NotszMem.RAM]::OpenProcessToken([NotszMem.RAM]::GetCurrentProcess(), 0x28, [ref]$tok) | Out-Null
    $luid = 0L
    [NotszMem.RAM]::LookupPrivilegeValue($null, $name, [ref]$luid) | Out-Null
    $tp = New-Object NotszMem.RAM+TP
    $tp.Count = 1; $tp.Luid = $luid; $tp.Attribs = 2
    [NotszMem.RAM]::AdjustTokenPrivileges($tok, $false, [ref]$tp, 0, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
}

# RAM livre antes
$antes = [Math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1024)

# Ativar privilegios necessarios
Enable-Priv "SeProfileSingleProcessPrivilege"
Enable-Priv "SeIncreaseQuotaPrivilege"

# 1) Trim working sets de todos os processos
Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
    try { $_.MinWorkingSet = $_.MinWorkingSet } catch {}
}

# 2-5) SystemMemoryListInformation (class 80)
#   2 = MemoryEmptyWorkingSets          (working sets do sistema)
#   3 = MemoryFlushModifiedList         (paginas sujas -> escreve no disco)
#   4 = MemoryPurgeStandbyList          (Standby = "Cached" no Task Manager)
#   5 = MemoryPurgeLowPriorityStandbyList
foreach ($cmd in 2, 3, 4, 5) {
    $ptr = [Runtime.InteropServices.Marshal]::AllocHGlobal(4)
    [Runtime.InteropServices.Marshal]::WriteInt32($ptr, $cmd)
    [NotszMem.RAM]::NtSetSystemInformation(80, $ptr, 4) | Out-Null
    [Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)
}

# 6) File System Cache - SystemFileCacheInformation (class 81)
#    Passar -1 em MinimumWorkingSet e MaximumWorkingSet forca o Windows
#    a libertar a cache de ficheiros lidos do disco (System Working Set)
$fc = New-Object NotszMem.RAM+FILECACHE
$fc.MinimumWorkingSet = [IntPtr]::new(-1)
$fc.MaximumWorkingSet = [IntPtr]::new(-1)
$fcSize = [Runtime.InteropServices.Marshal]::SizeOf($fc)
$fcPtr  = [Runtime.InteropServices.Marshal]::AllocHGlobal($fcSize)
[Runtime.InteropServices.Marshal]::StructureToPtr($fc, $fcPtr, $false)
[NotszMem.RAM]::NtSetSystemInformation(81, $fcPtr, $fcSize) | Out-Null
[Runtime.InteropServices.Marshal]::FreeHGlobal($fcPtr)

# Dar tempo ao OS para atualizar os contadores
Start-Sleep -Milliseconds 500

# RAM livre depois
$depois    = [Math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1024)
$libertada = $depois - $antes

[System.Windows.MessageBox]::Show(
    "RAM limpa!`n`n  Antes:       $antes MB livres`n  Depois:      $depois MB livres`n  Libertada: +$libertada MB",
    "Notsz Tweaks", "OK", "Information"
) | Out-Null
