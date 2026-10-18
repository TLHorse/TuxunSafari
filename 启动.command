#!/bin/zsh
cd -- "${0:A:h}" || exit 1
if ! command -v python3 >/dev/null 2>&1; then
  print '没有找到 Python 3，请安装 Python 3 后再运行。'
  read 'reply?按回车关闭…'
  exit 1
fi
print '先在 Safari 当前标签页打开图寻对局。'
print '等待：输入固定秒数，输入 r 使用随机模式，回车使用 config.json。'
read 'delay?本次等待设置：'
args=()
if [[ "$delay" == [rR] ]]; then
  read 'low?随机等待最短秒数（回车使用配置区间）：'
  if [[ -z "$low" ]]; then
    args+=(--delay-mode random)
  else
    read 'high?随机等待最长秒数：'
    args+=(--random-delay "$low" "$high")
  fi
elif [[ -n "$delay" ]]; then
  args+=(--delay "$delay")
fi
read 'offset?最大偏移半径（米；0 不偏移；回车使用配置）：'
if [[ -n "$offset" ]]; then
  args+=(--offset-meters "$offset")
fi
python3 tuxun.py "${args[@]}"
read 'reply?按回车关闭…'
