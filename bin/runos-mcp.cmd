@echo off
rem Launch the RunOS CLI's MCP server for an installed plugin. Windows sibling
rem of bin/runos-mcp, and it MUST keep the same resolution order:
rem
rem   1. %RUNOS_BIN%    an explicit override, authoritative: use it or fail
rem   2. runos on PATH
rem   3. %USERPROFILE%\.local\bin\runos.exe
rem   4. %ProgramFiles%\RunOS\runos.exe
rem
rem The same three rules as the POSIX script apply:
rem   1. Nothing is written to stdout. Stdout is the MCP stdio channel, so every
rem      diagnostic goes to stderr with 1>&2.
rem   2. The environment is NOT scrubbed. RUNOS_API_KEY is the headless and
rem      background-agent authentication route, and the client supplies
rem      PLUGIN_ROOT and PLUGIN_DATA. A child process inherits the environment
rem      by default, so the rule is: never build a new one.
rem   3. Exactly ONE binary is launched, so the filesystem-aware RunOS tools
rem      answer from one version's view of the project.
rem
rem Batch has no exec, so cmd.exe stays as a thin parent. It passes stdin and
rem stdout straight through and propagates the child's exit code.

setlocal EnableExtensions

set "RUNOS="

if defined RUNOS_BIN (
  rem An explicit override is authoritative. When it does not resolve we stop,
  rem rather than quietly running a different binary.
  if exist "%RUNOS_BIN%" (
    set "RUNOS=%RUNOS_BIN%"
  ) else (
    echo runos-mcp: RUNOS_BIN is set to '%RUNOS_BIN%', which does not exist. 1>&2
    echo runos-mcp: refusing to fall back to another binary while RUNOS_BIN is set. 1>&2
    call :install_hint
    exit /b 127
  )
) else (
  for %%I in (runos.exe) do set "RUNOS=%%~$PATH:I"
  if not defined RUNOS (
    if exist "%USERPROFILE%\.local\bin\runos.exe" set "RUNOS=%USERPROFILE%\.local\bin\runos.exe"
  )
  if not defined RUNOS (
    if exist "%ProgramFiles%\RunOS\runos.exe" set "RUNOS=%ProgramFiles%\RunOS\runos.exe"
  )
)

if not defined RUNOS (
  echo runos-mcp: cannot find the 'runos' binary. 1>&2
  echo runos-mcp: looked at %%RUNOS_BIN%%, PATH, %%USERPROFILE%%\.local\bin and %%ProgramFiles%%\RunOS. 1>&2
  call :install_hint
  exit /b 127
)

"%RUNOS%" %*
exit /b %ERRORLEVEL%

:install_hint
echo. 1>&2
echo Install the RunOS CLI, then reload your editor: 1>&2
echo. 1>&2
echo     irm https://get.runos.com/cli.ps1 ^| iex 1>&2
echo. 1>&2
echo Or point this plugin at an existing binary: 1>&2
echo. 1>&2
echo     set RUNOS_BIN=C:\path\to\runos.exe 1>&2
goto :eof
