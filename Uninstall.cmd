@echo off
chcp 65001 >nul
title Steve AI Connect - Uninstall
rem Chay tu ban sao trong TEMP de xoa duoc thu muc cai dat (ke ca chinh file nay).
set "T=%TEMP%\SteveCADConnect-uninstall"
if /i not "%~dp0"=="%T%\" (
  rmdir /s /q "%T%" 2>nul
  xcopy "%~dp0app" "%T%\app\" /e /i /q /y >nul
  xcopy "%~dp0CAD" "%T%\CAD\" /e /i /q /y >nul
  xcopy "%~dp0templates" "%T%\templates\" /e /i /q /y >nul
  copy /y "%~dp0VERSION" "%T%\" >nul
  copy /y "%~f0" "%T%\Uninstall.cmd" >nul
  start "" "%T%\Uninstall.cmd"
  exit /b
)
echo Go toan bo Steve AI Connect: ngat ZWCAD/AutoCAD/ADSCivil khoi moi tro ly AI,
echo tat tu nap ADSCivil 2026, xoa server, shortcut va muc trong Settings ^> Apps.
echo.
choice /m "Tiep tuc"
if errorlevel 2 exit /b
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\SteveCADConnect.ps1" -Uninstall
echo.
pause
