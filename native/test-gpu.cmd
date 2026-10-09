@echo off
cd /d "%~dp0"
call .\build.cmd
if errorlevel 1 exit /b 1
if not exist test-runtime\previews mkdir test-runtime\previews
if not exist test-runtime\ui-fonts xcopy /E /I /Y "..\package\payload\ue4ss\Mods\AC7MouseAim\Scripts\ui-fonts" "test-runtime\ui-fonts" >nul
cl /nologo /std:c++20 /EHsc /MD /O2 gpu_reticle_test.cpp /Fobuild\gpu_reticle_test.obj /Febuild\gpu_reticle_test.exe
if errorlevel 1 exit /b 1
build\gpu_reticle_test.exe
exit /b %errorlevel%
