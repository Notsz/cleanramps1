@echo off
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%~dp0clean-ram.ps1\"' -Verb RunAs"
