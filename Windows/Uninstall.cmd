@echo off
echo Close TaskLock from its tray menu before continuing.
pause
"%~dp0TaskLock.exe" --remove-startup
if exist "%LOCALAPPDATA%\Programs\TaskLock\TaskLock.exe" del "%LOCALAPPDATA%\Programs\TaskLock\TaskLock.exe"
if exist "%LOCALAPPDATA%\Programs\TaskLock\TaskLock.exe" (
  echo TaskLock is still running or cannot be removed. Close it and try again.
  pause
  exit /b 1
)
if exist "%LOCALAPPDATA%\Programs\TaskLock\DOTNET-LICENSE.txt" del "%LOCALAPPDATA%\Programs\TaskLock\DOTNET-LICENSE.txt"
if exist "%LOCALAPPDATA%\Programs\TaskLock\DOTNET-THIRD-PARTY-NOTICES.txt" del "%LOCALAPPDATA%\Programs\TaskLock\DOTNET-THIRD-PARTY-NOTICES.txt"
if exist "%APPDATA%\Microsoft\Windows\Start Menu\Programs\TaskLock.lnk" del "%APPDATA%\Microsoft\Windows\Start Menu\Programs\TaskLock.lnk"
if exist "%LOCALAPPDATA%\Programs\TaskLock" rmdir "%LOCALAPPDATA%\Programs\TaskLock" 2>nul
echo TaskLock removed. Your task data was preserved.
pause
