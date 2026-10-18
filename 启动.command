#!/bin/zsh
cd -- "${0:A:h}" || exit 1
if ! command -v python3 >/dev/null 2>&1; then
  print '没有找到 Python 3，请安装 Python 3 后再运行。'
  read 'reply?按回车关闭…'
  exit 1
fi
print '先在 Safari 当前标签页打开图寻对局。'
print '直接回车使用 config.json 中的等待秒数（默认 10 秒）。'
read 'delay?本次等待秒数：'
if [[ -z "$delay" ]]; then
  python3 tuxun.py
else
  python3 tuxun.py --delay "$delay"
fi
read 'reply?按回车关闭…'
