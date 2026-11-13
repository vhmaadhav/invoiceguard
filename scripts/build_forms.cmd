@echo off
REM Build the InvoiceGuard Oracle Forms application on Windows.
REM Mirrors scripts/build_forms.sh. Requires IG_DB_CONNECT and IG_DB_PASSWORD in the environment.
REM Optional: FORMS_BIN = folder holding frmxml2f.bat and frmcmp_batch.exe.
REM Logs go to forms\build\. Exit code 1 on any failure. Nothing is committed or pushed.
setlocal EnableDelayedExpansion

if "%IG_DB_CONNECT%"=="" ( echo set IG_DB_CONNECT, e.g. //localhost:1521/FREEPDB1 & exit /b 1 )
if "%IG_DB_PASSWORD%"=="" ( echo set IG_DB_PASSWORD for schema IG & exit /b 1 )

set "ROOT=%~dp0.."
set "FORMS=%ROOT%\forms"
set "BUILD=%FORMS%\build"
set "XML2F=frmxml2f.bat"
set "CMP=frmcmp_batch.exe"
if not "%FORMS_BIN%"=="" (
  set "XML2F=%FORMS_BIN%\frmxml2f.bat"
  set "CMP=%FORMS_BIN%\frmcmp_batch.exe"
)
if not exist "%BUILD%" mkdir "%BUILD%"
set "FORMS_PATH=%BUILD%;%FORMS%"
cd /d "%BUILD%"

echo.
echo == 1. regenerate XML and run static checks
python "%FORMS%\tools\gen_forms_xml.py" > "%BUILD%\gen.log" 2>&1 || ( type "%BUILD%\gen.log" & echo BUILD FAILED: gen_forms_xml.py & exit /b 1 )
python "%FORMS%\tools\check_refs.py" > "%BUILD%\check_refs.log" 2>&1 || ( type "%BUILD%\check_refs.log" & echo BUILD FAILED: check_refs.py & exit /b 1 )

echo.
echo == 2. frmxml2f: XML to binary FMB/MMB
for %%M in (IG_MAIN IG_INVOICE IG_EXCEPTIONS IG_PO_GRN IG_SETUP) do (
  call "%XML2F%" OVERWRITE=YES "%FORMS%\%%M_fmb.xml" > "%BUILD%\%%M.xml2f.log" 2>&1
  if errorlevel 1 ( type "%BUILD%\%%M.xml2f.log" & echo BUILD FAILED: frmxml2f %%M & exit /b 1 )
  if not exist "%BUILD%\%%M.fmb" ( echo BUILD FAILED: %%M.fmb not produced, see %BUILD%\%%M.xml2f.log & exit /b 1 )
)

echo.
echo == 3. compile IG_LIB.pld to IG_LIB.pll
"%CMP%" module="%FORMS%\IG_LIB.pld" output_file="%BUILD%\IG_LIB.pll" module_type=library parse=yes > "%BUILD%\IG_LIB.compile.log" 2>&1
if errorlevel 1 ( type "%BUILD%\IG_LIB.compile.log" & echo BUILD FAILED: IG_LIB & exit /b 1 )
if not exist "%BUILD%\IG_LIB.pll" ( echo BUILD FAILED: IG_LIB.pll not produced & exit /b 1 )

echo.
echo == 4. compile forms and menu to FMX/MMX
set "USERID=ig/%IG_DB_PASSWORD%@%IG_DB_CONNECT%"
for %%M in (IG_MAIN IG_INVOICE IG_EXCEPTIONS IG_PO_GRN IG_SETUP) do (
  "%CMP%" userid="%USERID%" module="%BUILD%\%%M.fmb" output_file="%BUILD%\%%M.fmx" module_type=form batch=yes compile_all=yes > "%BUILD%\%%M.compile.log" 2>&1
  if errorlevel 1 ( type "%BUILD%\%%M.compile.log" & echo BUILD FAILED: compile %%M & exit /b 1 )
  if not exist "%BUILD%\%%M.fmx" ( echo BUILD FAILED: %%M.fmx not produced & exit /b 1 )
  echo compiled %%M.fmx
)
"%CMP%" userid="%USERID%" module="%BUILD%\IG_MENU.mmb" output_file="%BUILD%\IG_MENU.mmx" module_type=menu batch=yes > "%BUILD%\IG_MENU.compile.log" 2>&1
if errorlevel 1 ( type "%BUILD%\IG_MENU.compile.log" & echo BUILD FAILED: compile menu & exit /b 1 )

echo.
echo done: artefacts in %BUILD%
endlocal
exit /b 0
