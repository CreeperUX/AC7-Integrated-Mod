@echo off
cd /d "%~dp0"
call .\build.cmd
if errorlevel 1 exit /b 1
python run-checked-tests.py takeover_logic_tests level_rearm_tests modes_tests control_timing_tests custom_keys_tests observation_tests peace_agile_tests peace_agile_joint_tests peace_agile_runtime_tests peace_agile_closedloop_tests recorder_tests fullmodel_tests agility_tests capture_runtime_tests capture_adaptation_tests leveling_tests plane_tests
exit /b %errorlevel%
