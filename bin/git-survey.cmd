@echo off
setlocal
set "GIT_BASH=%ProgramFiles%\Git\bin\bash.exe"
if not exist "%GIT_BASH%" set "GIT_BASH=bash"
"%GIT_BASH%" "%~dp0git-survey" %*
