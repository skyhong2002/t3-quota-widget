#!/bin/zsh
set -e
TASK_WIDGET_ROOT="$(cd -- "$(dirname -- "$0")" && pwd)"
/usr/bin/python3 "$TASK_WIDGET_ROOT/scripts/build.py" --install
printf '\nWidget 已更新。請稍等 macOS 更新桌面小工具。\n'
printf '按 Enter 關閉此視窗。'
read -r TASK_WIDGET_DONE
