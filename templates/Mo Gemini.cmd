@echo off
chcp 65001 >nul
title Gemini CAD AI
cd /d "%~dp0"
if not defined GEMINI_API_KEY if not exist "%~dp0.env" (
  echo Chua co GEMINI_API_KEY. Lay key tai https://aistudio.google.com/apikey
  echo roi mo Steve CAD-AI Connect, dan key vao o Gemini va bam Connect.
  pause
  exit /b 1
)
gemini
