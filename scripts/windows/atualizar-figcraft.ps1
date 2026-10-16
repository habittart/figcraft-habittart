# Instala ou atualiza o FigCraft Habittart neste PC (Windows x64), sem precisar de administrador.
# Baixa a versao mais recente de https://github.com/habittart/figcraft-habittart/releases, instala em
# %LOCALAPPDATA%\FigCraft-Habittart, cria os atalhos, associa .figcraft e links figcraft://,
# liga o MCP do FigCraft no app do Claude e agenda a verificacao automatica (toda segunda-feira).
# Toda vez tambem aplica as configuracoes gerais compartilhadas (settings/figcraft-settings.json do
# repositorio) e o link do projeto online, para o FigCraft abrir direto nele.
#
#   Primeira vez (PowerShell):
#   irm https://raw.githubusercontent.com/habittart/figcraft-habittart/main/scripts/windows/atualizar-figcraft.ps1 | iex
param([switch]$Quiet)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Repo = 'habittart/figcraft-habittart'
$Port = 7979
$Dir = Join-Path $env:LOCALAPPDATA 'FigCraft-Habittart'
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
try { Start-Transcript -Append -Path (Join-Path $Dir 'update.log') | Out-Null } catch {}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
function Say($m) { if (-not $Quiet) { Write-Host $m } else { Write-Output $m } }

# Restos de uma atualizacao anterior (executaveis renomeados enquanto estavam abertos)
Get-ChildItem $Dir -Filter '*.old-*' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

$rel = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ 'User-Agent' = 'figcraft-habittart' }
$tag = $rel.tag_name
$stateFile = Join-Path $Dir 'installed.txt'
$cur = if (Test-Path $stateFile) { (Get-Content $stateFile -Raw).Trim() } else { '' }
$exe = Join-Path $Dir 'figcraft.exe'
$updated = $false

if ($tag -ne $cur -or -not (Test-Path $exe)) {
    Say "== instalando FigCraft $tag"
    $asset = $rel.assets | Where-Object { $_.name -like '*windows-x64.zip' } | Select-Object -First 1
    if (-not $asset) { throw "a versao $tag nao tem o pacote para Windows" }
    $zip = Join-Path $env:TEMP "figcraft-habittart-$PID.zip"
    Invoke-WebRequest $asset.browser_download_url -OutFile $zip -UseBasicParsing
    # Um .exe aberto (o FigCraft, ou o MCP rodando no Claude) nao pode ser sobrescrito, mas pode
    # ser renomeado: a versao nova entra no lugar e vale na proxima vez que abrir.
    $stamp = Get-Date -Format 'yyyyMMddHHmmss'
    foreach ($n in 'figcraft.exe', 'figcraft-cli.exe', 'figcraft-mcp.exe') {
        $p = Join-Path $Dir $n
        if (Test-Path $p) { Rename-Item $p "$n.old-$stamp" -ErrorAction SilentlyContinue }
    }
    try {
        Expand-Archive -Path $zip -DestinationPath $Dir -Force
        if (-not (Test-Path $exe)) { throw 'o pacote nao trouxe o figcraft.exe' }
    } catch {
        # Volta para a versao anterior em vez de deixar o FigCraft quebrado
        foreach ($n in 'figcraft.exe', 'figcraft-cli.exe', 'figcraft-mcp.exe') {
            $o = Join-Path $Dir "$n.old-$stamp"
            if (Test-Path $o) { Move-Item $o (Join-Path $Dir $n) -Force -ErrorAction SilentlyContinue }
        }
        throw
    }
    Get-ChildItem $Dir -File | Unblock-File -ErrorAction SilentlyContinue
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    Set-Content -Path $stateFile -Value $tag
    $updated = $true
} else {
    Say "== FigCraft ja esta na versao mais recente ($tag)"
}

# Atalhos (Menu Iniciar e Area de Trabalho), sempre com o canal de controle do Claude ligado
$ws = New-Object -ComObject WScript.Shell
$links = @(
    (Join-Path ([Environment]::GetFolderPath('Programs')) 'FigCraft.lnk'),
    (Join-Path ([Environment]::GetFolderPath('Desktop')) 'FigCraft.lnk')
)
foreach ($lnk in $links) {
    $s = $ws.CreateShortcut($lnk)
    $s.TargetPath = $exe; $s.Arguments = "--control $Port"; $s.WorkingDirectory = $Dir
    $s.IconLocation = "$exe,0"; $s.Description = 'FigCraft (Habittart)'; $s.Save()
}

# .figcraft abre no FigCraft, e links figcraft:// (convites de edicao) tambem
# The command line is exactly the one FigCraft registers for itself (it re-registers at every start
# when the line differs), so the app and this script don't overwrite each other. The control channel
# for the Claude MCP comes from FIGCRAFT_CONTROL_PORT instead, so every start has it (links,
# double-clicked files, the Start menu).
$open = "`"$exe`" `"%1`""
if ([Environment]::GetEnvironmentVariable('FIGCRAFT_CONTROL_PORT', 'User') -ne "$Port") {
    [Environment]::SetEnvironmentVariable('FIGCRAFT_CONTROL_PORT', "$Port", 'User')
    Say "== canal de controle do Claude ligado em toda abertura do FigCraft (FIGCRAFT_CONTROL_PORT=$Port)"
}
$env:FIGCRAFT_CONTROL_PORT = "$Port"
$classes = 'HKCU:\Software\Classes'
function Set-Key($path, $value, $name = '(default)') {
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    Set-ItemProperty -Path $path -Name $name -Value $value
}
Set-Key "$classes\.figcraft" 'FigCraft.Habittart'
Set-Key "$classes\FigCraft.Habittart" 'FigCraft Document'
Set-Key "$classes\FigCraft.Habittart\DefaultIcon" "$exe,0"
Set-Key "$classes\FigCraft.Habittart\shell\open\command" $open
Set-Key "$classes\figcraft" 'URL:FigCraft'
Set-Key "$classes\figcraft" '' 'URL Protocol'
Set-Key "$classes\figcraft\DefaultIcon" "$exe,0"
Set-Key "$classes\figcraft\shell\open\command" $open

# Configuracoes gerais iguais nos dois computadores, e o projeto online ao abrir o app
$cfgDir = Join-Path $env:APPDATA 'FigCraft'
New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
try {
    $tmpSettings = Join-Path $cfgDir '.habittart-settings.new'
    Invoke-WebRequest "https://raw.githubusercontent.com/$Repo/main/settings/figcraft-settings.json" -OutFile $tmpSettings -UseBasicParsing
    Move-Item $tmpSettings (Join-Path $cfgDir 'habittart-settings.json') -Force
} catch { Say "== configuracoes compartilhadas: sem rede agora ($($_.Exception.Message))" }
foreach ($f in @((Join-Path $Dir 'link-edicao-PRIVADO.txt'), (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'figcraft-oracle\link-edicao-PRIVADO.txt'))) {
    if (Test-Path $f) {
        $m = Select-String -Path $f -Pattern 'figcraft://join\?\S+' | Select-Object -First 1
        if ($m) {
            [IO.File]::WriteAllText((Join-Path $cfgDir 'habittart-autojoin.txt'), $m.Matches[0].Value + "`n")
            break
        }
    }
}

# MCP do FigCraft no app do Claude (instalacao normal e versao da Microsoft Store)
$mcp = Join-Path $Dir 'figcraft-mcp.exe'
$cfgDirs = @(Join-Path $env:APPDATA 'Claude')
$cfgDirs += Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Packages') -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName 'LocalCache\Roaming\Claude' } | Where-Object { Test-Path $_ }
foreach ($d in $cfgDirs) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    $cfgPath = Join-Path $d 'claude_desktop_config.json'
    $cfg = [pscustomobject]@{}
    if (Test-Path $cfgPath) {
        $raw = Get-Content $cfgPath -Raw
        if ($raw.Trim()) { $cfg = $raw | ConvertFrom-Json }
    }
    if (-not $cfg.PSObject.Properties['mcpServers']) { $cfg | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([pscustomobject]@{}) }
    $entry = [pscustomobject]@{ command = $mcp; args = @('mcp', '--attach', "$Port") }
    $old = $cfg.mcpServers.PSObject.Properties['figcraft']
    $same = $old -and $old.Value.command -eq $mcp
    if (-not $same) {
        if (Test-Path $cfgPath) { Copy-Item $cfgPath "$cfgPath.backup-$(Get-Date -Format yyyyMMddHHmmss)" }
        if ($old) { $cfg.mcpServers.PSObject.Properties.Remove('figcraft') }
        $cfg.mcpServers | Add-Member -NotePropertyName figcraft -NotePropertyValue $entry
        [IO.File]::WriteAllText($cfgPath, ($cfg | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding $false))
        Say "== MCP do FigCraft configurado em $cfgPath (reinicie o app do Claude)"
    }
}

# Verificacao automatica: toda segunda-feira as 10h (ou assim que o PC ligar, se estava desligado), escondida
$self = Join-Path $Dir 'atualizar-figcraft.ps1'
if (Test-Path $self) {
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$self`" -Quiet"
    $t1 = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At '10:00'
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
    Register-ScheduledTask -TaskName 'FigCraft Habittart - atualizar' -Action $action -Trigger $t1 -Settings $settings -Description 'Mantem o FigCraft com as correcoes Habittart atualizado' -Force | Out-Null
}

if ($updated) { Say "== PRONTO: FigCraft $tag instalado em $Dir" }
try { Stop-Transcript | Out-Null } catch {}
