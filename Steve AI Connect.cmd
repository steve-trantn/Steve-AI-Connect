@echo off
rem Mo giao dien Steve AI Connect
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "%~dp0app\SteveCADConnect.ps1"
