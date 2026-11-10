#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
exec "${THESIS_PRO_PYTHON:-python3}" "$task_root/scripts/thesis_pro_mcp.py"
