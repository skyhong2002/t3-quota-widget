#!/bin/zsh
TASK_WIDGET_ROOT="$(cd -- "$(dirname -- "$0")" && pwd)"
TASK_DIAGNOSTIC="$TASK_WIDGET_ROOT/widget-diagnostic.txt"
{
  /bin/date
  /usr/bin/pluginkit -m -v -i tw.skyhong.t3usage.widget
  /usr/bin/codesign --verify --deep --strict '/Applications/T3 帳號額度 Widget.app'
  /usr/bin/log show --last 15m --style compact --predicate '(process == "chronod" OR process == "T3Widget" OR process == "sandboxd") AND (eventMessage CONTAINS "t3usage" OR eventMessage CONTAINS "T3Widget" OR process == "T3Widget")'
} > "$TASK_DIAGNOSTIC" 2>&1
printf '診斷已存到：%s\n' "$TASK_DIAGNOSTIC"
printf '請回到 Codex 告訴我已完成；這個檔案不會上傳 GitHub。\n'
printf '按 Enter 關閉。'
read -r TASK_DIAGNOSTIC_DONE
