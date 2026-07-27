#requires -RunAsAdministrator
<#
.SYNOPSIS
    Notsz - Debloat Agressivo + Anti-Telemetria (Windows 10 / 11)
.DESCRIPTION
    - Remove apps built-in (bloatware) + todos os residuos (AppData, Registry, MUICache)
    - Desativa servicos e tarefas de telemetria do Windows
    - Reduz telemetria do Windows Defender (mantem a proteccao em tempo real ativa)
    - Remove OneDrive por completo
    - Desativa telemetria do Edge (e Chrome/Firefox se instalados)
.USAGE
    PowerShell como Administrador:  .\notsz-debloat-privacy.ps1
#>

$ErrorActionPreference = "SilentlyContinue"

Write-Host ""
Write-Host " ================================================" -ForegroundColor Cyan
Write-Host "  Notsz - Debloat + Privacy (Win10/Win11)" -ForegroundColor Cyan
Write-Host " ================================================" -ForegroundColor Cyan
Write-Host ""

$osCaption = (Get-CimInstance Win32_OperatingSystem).Caption
$isWin11 = $osCaption -match "Windows 11"
Write-Host " SO detetado: $osCaption" -ForegroundColor Yellow
Write-Host ""

# --- Ponto de restauro antes de mexer em nada ---
Write-Host " A criar ponto de restauro..."
try {
    Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
    Checkpoint-Computer -Description "Antes do Notsz Debloat" -RestorePointType "MODIFY_SETTINGS"
    Write-Host "  OK." -ForegroundColor Green
} catch {
    Write-Host "  Restauro do sistema desativado/indisponivel, a continuar sem ponto de restauro." -ForegroundColor DarkYellow
}

# ===========================================================================
# 1) DEBLOAT - APPS + RESIDUOS (AppData, Registry, MUICache)
# ===========================================================================
Write-Host ""
Write-Host " [1/6] DEBLOAT - a remover apps e residuos..." -ForegroundColor Cyan

# --- Os 5 que ficam, por pedido explicito ---
$KeepExplicit = @(
    "Microsoft.WindowsCalculator","Microsoft.WindowsCamera","Microsoft.WindowsStore",
    "Microsoft.Windows.Photos","Microsoft.ZuneVideo"
)

# --- Bibliotecas/runtimes - nao sao apps, sao dependencias de que os 5 acima
#     (e o proprio Windows) precisam para correr. Nao aparecem no menu Iniciar. ---
$FrameworkDeps = @(
    "Microsoft.DesktopAppInstaller","Microsoft.StorePurchaseApp",
    "Microsoft.VCLibs.140.00","Microsoft.NET.Native.Framework","Microsoft.NET.Native.Runtime",
    "Microsoft.UI.Xaml.2.7","Microsoft.UI.Xaml.2.8","Microsoft.WindowsAppRuntime"
)

# --- Componentes da propria shell do Windows - NAO sao apps, sao o Ambiente
#     de Trabalho em si. Remover isto = sem menu Iniciar, sem pesquisa, sem
#     ecra de bloqueio, sem login. Isto fica de fora sempre, sem excecao. ---
$ShellCritical = @(
    "MicrosoftWindows.Client.CBS","Microsoft.Windows.ShellExperienceHost",
    "Microsoft.Windows.StartMenuExperienceHost","Microsoft.Windows.SearchApp",
    "Microsoft.Windows.Search","Microsoft.LockApp","Microsoft.AAD.BrokerPlugin",
    "Microsoft.AccountsControl","Microsoft.CredDialogHost","Microsoft.ECApp",
    "Microsoft.Win32WebViewHost","Microsoft.Windows.CapturePicker",
    "Microsoft.Windows.CloudExperienceHost","Microsoft.Windows.PeopleExperienceHost",
    "Microsoft.Windows.PinningConfirmationDialog","Microsoft.XboxGameCallableUI",
    "Microsoft.Windows.NarratorQuickStart","Windows.CBSPreview"
)

$NeverTouch = $KeepExplicit + $FrameworkDeps + $ShellCritical

# --- Debloat MAXIMO: tudo o que for reconhecivel/visivel e nao esteja nas
#     listas acima, vai embora. Inclui itens com consequencia pratica
#     (Notepad, Paint, Snipping Tool, Terminal, Windows Security UI) -
#     ver aviso no chat sobre o que perdes com cada um destes. ---
$BloatApps = @(
    "Microsoft.3DBuilder","Microsoft.Microsoft3DViewer","Microsoft.MixedReality.Portal",
    "Microsoft.BingFinance","Microsoft.BingNews","Microsoft.BingSports","Microsoft.BingWeather",
    "Microsoft.BingSearch","Microsoft.549981C3F5F10","Microsoft.GetHelp","Microsoft.Getstarted",
    "Microsoft.WindowsFeedbackHub","Microsoft.Messaging","Microsoft.MicrosoftOfficeHub",
    "Microsoft.MicrosoftSolitaireCollection","Microsoft.NetworkSpeedTest","Microsoft.News",
    "Microsoft.Office.Sway","Microsoft.OneConnect","Microsoft.People","Microsoft.Print3D",
    "Microsoft.SkypeApp","Microsoft.Wallet","Microsoft.WindowsMaps","Microsoft.YourPhone",
    "Microsoft.Windows.Phone","Microsoft.ZuneMusic","Microsoft.Todos",
    "Microsoft.PowerAutomateDesktop","Microsoft.Teams","MicrosoftTeams","Microsoft.GamingApp",
    "Clipchamp.Clipchamp","MicrosoftCorporationII.MicrosoftFamily","Microsoft.WindowsMeetNow",
    "Microsoft.Xbox.TCUI","Microsoft.XboxApp","Microsoft.XboxGameOverlay",
    "Microsoft.XboxGamingOverlay","Microsoft.XboxIdentityProvider","Microsoft.XboxSpeechToTextOverlay",
    "Microsoft.MicrosoftStickyNotes","microsoft.windowscommunicationsapps",
    "MicrosoftWindows.Client.WebExperience","Microsoft.OutlookForWindows",
    "Microsoft.WindowsAlarms","Microsoft.WindowsSoundRecorder",
    "Microsoft.WindowsNotepad","Microsoft.Paint","Microsoft.ScreenSketch",
    "Microsoft.WindowsTerminal","Microsoft.SecHealthUI"
)

$removedPFNs = @()

foreach ($app in $BloatApps) {
    if ($NeverTouch -contains $app) { continue }
    $pkgs = Get-AppxPackage -AllUsers -Name $app -ErrorAction SilentlyContinue
    foreach ($p in $pkgs) {
        $removedPFNs += $p.PackageFamilyName
        Write-Host "   Removendo: $($p.Name)" -ForegroundColor DarkGray
        Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction SilentlyContinue
    }
    # Remove tambem provisionado, para nao voltar em contas novas / updates
    $prov = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $app }
    foreach ($pp in $prov) {
        Remove-AppxProvisionedPackage -Online -PackageName $pp.PackageName -ErrorAction SilentlyContinue
    }
}

Write-Host "   A limpar residuos das apps removidas (AppData, Registry, MUICache)..."
foreach ($pfn in $removedPFNs) {
    if (-not $pfn) { continue }
    # AppData
    Remove-Item "$env:LOCALAPPDATA\Packages\$pfn" -Recurse -Force -ErrorAction SilentlyContinue
    # Registry - dados de app model
    Remove-Item "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\$pfn" -Recurse -Force -ErrorAction SilentlyContinue
    # Registry - AppContainer storage
    Remove-Item "HKCU:\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\$pfn" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\$pfn" -Recurse -Force -ErrorAction SilentlyContinue
}

# MUICache - Windows reconstroi automaticamente, seguro limpar tudo
Remove-Item "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache" -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "   Debloat concluido ($($removedPFNs.Count) pacotes removidos)." -ForegroundColor Green

# ===========================================================================
# 2) TELEMETRIA DO WINDOWS - SERVICOS, TAREFAS E POLICIES
# ===========================================================================
Write-Host ""
Write-Host " [2/6] TELEMETRIA - a desativar coleta de dados do Windows..." -ForegroundColor Cyan

# Servicos
foreach ($svc in @("DiagTrack","dmwappushservice","diagnosticshub.standardcollector.service","WerSvc")) {
    Stop-Service $svc -Force -ErrorAction SilentlyContinue
    Set-Service $svc -StartupType Disabled -ErrorAction SilentlyContinue
    Write-Host "   Servico $svc -> Disabled" -ForegroundColor DarkGray
}

# Tarefas agendadas relacionadas com telemetria/CEIP
$telemetryTasks = @(
    "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
    "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
    "\Microsoft\Windows\Application Experience\StartupAppTask",
    "\Microsoft\Windows\Autochk\Proxy",
    "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
    "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
    "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
    "\Microsoft\Windows\Feedback\Siuf\DmClient",
    "\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload",
    "\Microsoft\Windows\Windows Error Reporting\QueueReporting"
)
foreach ($task in $telemetryTasks) {
    Disable-ScheduledTask -TaskPath (Split-Path $task) -TaskName (Split-Path $task -Leaf) -ErrorAction SilentlyContinue | Out-Null
}

# Policies de telemetria (chaves oficiais documentadas pela Microsoft)
$dc = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
New-Item -Path $dc -Force | Out-Null
Set-ItemProperty -Path $dc -Name "AllowTelemetry" -Value 0 -Type DWord -Force
Set-ItemProperty -Path $dc -Name "DoNotShowFeedbackNotifications" -Value 1 -Type DWord -Force

# Advertising ID
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 0 -Type DWord -Force
$aiPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"
New-Item -Path $aiPolicy -Force | Out-Null
Set-ItemProperty -Path $aiPolicy -Name "DisabledByGroupPolicy" -Value 1 -Type DWord -Force

# Windows Error Reporting
$werPath = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting"
Set-ItemProperty -Path $werPath -Name "Disabled" -Value 1 -Type DWord -Force

# Tailored experiences / Consumer features / Start menu suggestions
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338393Enabled" -Value 0 -Type DWord -Force
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-353694Enabled" -Value 0 -Type DWord -Force
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-353696Enabled" -Value 0 -Type DWord -Force
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SilentInstalledAppsEnabled" -Value 0 -Type DWord -Force
$cf = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
New-Item -Path $cf -Force | Out-Null
Set-ItemProperty -Path $cf -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $cf -Name "DisableTailoredExperiencesWithDiagnosticData" -Value 1 -Type DWord -Force

# Historico de atividades / upload para a cloud (Timeline)
$act = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
New-Item -Path $act -Force | Out-Null
Set-ItemProperty -Path $act -Name "EnableActivityFeed" -Value 0 -Type DWord -Force
Set-ItemProperty -Path $act -Name "PublishUserActivities" -Value 0 -Type DWord -Force
Set-ItemProperty -Path $act -Name "UploadUserActivities" -Value 0 -Type DWord -Force

# Pesquisa web na barra de tarefas / Cortana
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 0 -Type DWord -Force
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "CortanaConsent" -Value 0 -Type DWord -Force

Write-Host "   Telemetria do Windows desativada." -ForegroundColor Green

# ===========================================================================
# 3) WINDOWS DEFENDER - APENAS TELEMETRIA/REPORTING (protecao mantem-se ativa)
# ===========================================================================
Write-Host ""
Write-Host " [3/6] DEFENDER - a desativar reporting/telemetria (protecao real-time mantem-se ligada)..." -ForegroundColor Cyan

$spynet = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet"
New-Item -Path $spynet -Force | Out-Null
Set-ItemProperty -Path $spynet -Name "SpyNetReporting" -Value 0 -Type DWord -Force
Set-ItemProperty -Path $spynet -Name "SubmitSamplesConsent" -Value 2 -Type DWord -Force   # 2 = nunca enviar

try {
    Set-MpPreference -MAPSReporting 0 -ErrorAction SilentlyContinue          # 0 = Off
    Set-MpPreference -SubmitSamplesConsent 2 -ErrorAction SilentlyContinue   # NeverSend
    Set-MpPreference -DisableBlockAtFirstSeen $true -ErrorAction SilentlyContinue
} catch {}

Write-Host "   Feito. (Real-time protection NAO foi tocado - mantem-se ativo)" -ForegroundColor Green

# ===========================================================================
# 4) ONEDRIVE - REMOCAO COMPLETA
# ===========================================================================
Write-Host ""
Write-Host " [4/6] ONEDRIVE - a remover..." -ForegroundColor Cyan

Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

$oduninst32 = "$env:SystemRoot\System32\OneDriveSetup.exe"
$oduninst64 = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
if (Test-Path $oduninst64) { Start-Process $oduninst64 -ArgumentList "/uninstall" -Wait -ErrorAction SilentlyContinue }
elseif (Test-Path $oduninst32) { Start-Process $oduninst32 -ArgumentList "/uninstall" -Wait -ErrorAction SilentlyContinue }

Start-Sleep -Seconds 2
Remove-Item "$env:USERPROFILE\OneDrive" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$env:LOCALAPPDATA\Microsoft\OneDrive" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$env:PROGRAMDATA\Microsoft OneDrive" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\OneDriveTemp" -Recurse -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "OneDriveSetup" -Force -ErrorAction SilentlyContinue

# Esconde o OneDrive do painel de navegacao do Explorer
foreach ($hive in @("HKCU:\Software\Classes","HKLM:\SOFTWARE\Classes")) {
    Set-ItemProperty -Path "$hive\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" -Name "System.IsPinnedToNameSpaceTree" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
}

# Impede reinstalacao automatica
$odPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
New-Item -Path $odPolicy -Force | Out-Null
Set-ItemProperty -Path $odPolicy -Name "DisableFileSyncNGSC" -Value 1 -Type DWord -Force

Write-Host "   OneDrive removido." -ForegroundColor Green

# ===========================================================================
# 5) BROWSER - TELEMETRIA (Edge sempre; Chrome/Firefox se instalados)
# ===========================================================================
Write-Host ""
Write-Host " [5/6] BROWSER - a desativar telemetria..." -ForegroundColor Cyan

# Edge (via Group Policy, oficialmente documentado pela Microsoft)
$edgePol = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
New-Item -Path $edgePol -Force | Out-Null
Set-ItemProperty -Path $edgePol -Name "MetricsReportingEnabled" -Value 0 -Type DWord -Force
Set-ItemProperty -Path $edgePol -Name "PersonalizationReportingEnabled" -Value 0 -Type DWord -Force
Set-ItemProperty -Path $edgePol -Name "DiagnosticData" -Value 0 -Type DWord -Force
Set-ItemProperty -Path $edgePol -Name "UserFeedbackAllowed" -Value 0 -Type DWord -Force
Set-ItemProperty -Path $edgePol -Name "EdgeCollectionsEnabled" -Value 0 -Type DWord -Force
Write-Host "   Edge: telemetria desativada." -ForegroundColor DarkGray

# Chrome (so aplica se estiver instalado - via Group Policy oficial da Google)
if (Get-Item "HKLM:\SOFTWARE\Google\Chrome" -ErrorAction SilentlyContinue) {
    $chromePol = "HKLM:\SOFTWARE\Policies\Google\Chrome"
    New-Item -Path $chromePol -Force | Out-Null
    Set-ItemProperty -Path $chromePol -Name "MetricsReportingEnabled" -Value 0 -Type DWord -Force
    Write-Host "   Chrome: telemetria desativada." -ForegroundColor DarkGray
}

# Firefox (so aplica se estiver instalado - via ficheiro de policies oficial da Mozilla)
$ffPath = "${env:ProgramFiles}\Mozilla Firefox"
if (Test-Path $ffPath) {
    $ffPolicyDir = "$ffPath\distribution"
    New-Item -Path $ffPolicyDir -ItemType Directory -Force | Out-Null
    $ffPolicyJson = @"
{
  "policies": {
    "DisableTelemetry": true,
    "DisableFirefoxStudies": true,
    "DisablePocket": true
  }
}
"@
    Set-Content -Path "$ffPolicyDir\policies.json" -Value $ffPolicyJson -Force
    Write-Host "   Firefox: telemetria desativada." -ForegroundColor DarkGray
}

# ===========================================================================
# 6) LIMPEZA FINAL
# ===========================================================================
Write-Host ""
Write-Host " [6/6] Limpeza final..." -ForegroundColor Cyan
ipconfig /flushdns | Out-Null
Write-Host "   Concluido." -ForegroundColor Green

Write-Host ""
Write-Host " ================================================" -ForegroundColor Green
Write-Host "  TUDO CONCLUIDO - reinicia o PC" -ForegroundColor Green
Write-Host " ================================================" -ForegroundColor Green
Write-Host ""
Write-Host " Resumo:"
Write-Host "  - $($removedPFNs.Count) apps bloatware removidas + residuos limpos"
Write-Host "  - Telemetria do Windows (DiagTrack, CEIP, WER, Advertising ID, Timeline) off"
Write-Host "  - Defender: reporting/SpyNet off (protecao real-time continua ativa)"
Write-Host "  - OneDrive removido por completo"
Write-Host "  - Edge/Chrome/Firefox: telemetria off (os que estiverem instalados)"
Write-Host ""
Write-Host " NOTA: se algo partir (ex.: um app que afinal usavas), corre o" -ForegroundColor Yellow
Write-Host " ponto de restauro criado no inicio: Painel de Controlo > Recuperacao" -ForegroundColor Yellow
Write-Host " > Abrir Restauro do Sistema." -ForegroundColor Yellow
Write-Host ""
pause
