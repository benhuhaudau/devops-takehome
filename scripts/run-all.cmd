@rem scripts/run-all.cmd: Windows cmd/PowerShell wrapper for run-all.sh
@echo off
docker compose exec -T toolbox /scripts/run-all.sh %1
