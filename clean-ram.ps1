<#
.SYNOPSIS
    Limpa a RAM: reduz o working set de todos os processos e esvazia a
    Standby List / Modified Page List do sistema (mesma técnica usada por
    ferramentas como RAMMap, Memreduct, Wise Memory Optimizer, etc).
.NOTES
    Precisa rodar como Administrador para a parte de Standby List.
    Sem admin, ainda funciona a parte de trim de working sets (efeito menor).
#>

Add-Type -Namespace Notsz -Name Mem -MemberDefinition @"
[DllImport("ntdll.dll")]
public static extern int NtSetSystemInformation(int InfoClass, IntPtr Info, int Length);

[DllImport("advapi32.dll", SetLastError=true)]
public static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

[DllImport("advapi32.dll", SetLastError=true)]
public static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out long lpLuid);

[DllImport("advapi32.dll", SetLastError=true)]
public static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges, ref TOKEN_PRIVILEGES NewState, uint BufferLength, IntPtr PreviousState, IntPtr ReturnLength);

[DllImport("kernel32.dll")]
public static extern IntPtr GetCurrentProcess();

[StructLayout(LayoutKind.Sequential)]
public struct TOKEN_PRIVILEGES {
    public uint PrivilegeCount;
    public long Luid;
    public uint Attributes;
}
"@

function Enable-Priv([string]$name) {
    $hTok = [IntPtr]::Zero
    if (-not [Notsz.Mem]::OpenProcessToken([Notsz.Mem]::GetCurrentProcess(), 0x28, [ref]$hTok)) { return }
    $luid = 0
    if (-not [Notsz.Mem]::LookupPrivilegeValue($null, $name, [ref]$luid)) { return }
    $tp = New-Object Notsz.Mem+TOKEN_PRIVILEGES
    $tp.PrivilegeCount = 1
    $tp.Luid = $luid
    $tp.Attributes = 0x2   # SE_PRIVILEGE_ENABLED
    [Notsz.Mem]::AdjustTokenPrivileges($hTok, $false, [ref]$tp, 0, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
}

# --- 1) Trim do working set de cada processo (libera páginas físicas) ---
Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
    try { $_.MinWorkingSet = $_.MinWorkingSet } catch {}
}

# --- 2) Esvaziar Standby List / Modified List / Working Sets do sistema ---
# SystemMemoryListInformation = 80
# Comandos: 2=MemoryEmptyWorkingSets 3=MemoryFlushModifiedList 4=MemoryPurgeStandbyList
Enable-Priv "SeProfileSingleProcessPrivilege"
Enable-Priv "SeIncreaseQuotaPrivilege"

foreach ($cmd in 2, 3, 4) {
    $ptr = [Runtime.InteropServices.Marshal]::AllocHGlobal(4)
    [Runtime.InteropServices.Marshal]::WriteInt32($ptr, $cmd)
    [Notsz.Mem]::NtSetSystemInformation(80, $ptr, 4) | Out-Null
    [Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)
}

# --- Notificação simples (opcional) ---
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.MessageBox]::Show("RAM limpa (working sets + standby list).", "Notsz Tweaks") | Out-Null
