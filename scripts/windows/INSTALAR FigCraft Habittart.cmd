@echo off
title FigCraft Habittart - instalar
echo == Baixando o atualizador do FigCraft Habittart...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p = Join-Path $env:TEMP 'atualizar-figcraft.ps1'; Invoke-RestMethod 'https://raw.githubusercontent.com/habittart/figcraft-habittart/main/scripts/windows/atualizar-figcraft.ps1' -OutFile $p; & $p"
if errorlevel 1 (
  echo.
  echo == ERRO na instalacao. Veja a mensagem acima.
  pause
  exit /b 1
)
echo.
echo == Abrindo o FigCraft (entra sozinho no projeto online)...
start "" "%LOCALAPPDATA%\FigCraft-Habittart\figcraft.exe"
echo.
echo == PRONTO. Feche e reabra o app do Claude para o MCP do FigCraft aparecer.
pause
