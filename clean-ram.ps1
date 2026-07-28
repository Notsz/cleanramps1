<#
.SYNOPSIS
    Limpa a RAM:
    1) Working sets de todos os processos
    2) Modified List (paginas sujas a espera de ir para o disco)
    3) Standby List (o "Cached" que aparece no Task Manager)
    4) Low-Priority Standby List (subset da Standby, limpa primeiro)
    5) File System Cache (RAM usada para cache de ficheiros do disco)
.NOTES
    Precisa de Administrador para os passos 2-5.
#>
 
Add-Type -Namespace Notsz -Name Mem -MemberDefinition @"
[DllImport("ntdll.dll")]
public static extern int NtSetSystemInformation(int InfoClass, IntPtr Info, int Length);
 
[DllImport("kernel32.dll", SetLastError=true)]
public static extern bool SetSystemFileCacheSize(IntPtr MinimumFileCacheSize, IntPtr MaximumFileCacheSize, uint Flags);
 
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
    $tp.Attributes = 0x2
    [Notsz.Mem]::AdjustTokenPrivileges($hTok, $false, [ref]$tp, 0, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
}
 
# Ativar privilegios necessarios
Enable-Priv "SeProfileSingleProcessPrivilege"
Enable-Priv "SeIncreaseQuotaPrivilege"
 
# --- 1) Trim working set de cada processo ---
Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
    try { $_.MinWorkingSet = $_.MinWorkingSet } catch {}
}
 
# --- 2-5) Limpar listas de memoria do sistema ---
# SystemMemoryListInformation = 80
# 2 = MemoryEmptyWorkingSets      (working sets do sistema)
# 3 = MemoryFlushModifiedList     (paginas sujas -> disco)
# 4 = MemoryPurgeStandbyList      (standby list completa = "Cached" no Task Manager)
# 5 = MemoryPurgeLowPriorityStandbyList (subset de baixa prioridade da standby)
foreach ($cmd in 2, 3, 4, 5) {
    $ptr = [Runtime.InteropServices.Marshal]::AllocHGlobal(4)
    [Runtime.InteropServices.Marshal]::WriteInt32($ptr, $cmd)
    [Notsz.Mem]::NtSetSystemInformation(80, $ptr, 4) | Out-Null
    [Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)
}
 
# --- 6) File System Cache ---
# RAM que o Windows usa para guardar ficheiros lidos do disco (diferente da Standby List).
# Passar -1 em ambos os tamanhos forca o Windows a redefinir e libertar a cache.
# Requer SeIncreaseQuotaPrivilege (ja ativado acima).
[Notsz.Mem]::SetSystemFileCacheSize([IntPtr](-1), [IntPtr](-1), 0) | Out-Null
 
# --- Notificacao ---
Add-Type -AssemblyName PresentationFramework
[System.Windows.MessageBox]::Show(
    "RAM limpa com sucesso!`n`n- Working Sets`n- Modified List`n- Standby List`n- Low-Priority Standby`n- File System Cache",
    "Notsz Tweaks",
    "OK",
    "Information"
) | Out-Null
 
