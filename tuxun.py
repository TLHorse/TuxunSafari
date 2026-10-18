#!/usr/bin/env python3
"""Safari 图寻脚本：仅使用 AppleScript + 页面 JavaScript。"""
import argparse
import json
import math
import pathlib
import subprocess
import sys
import time
import uuid
from urllib.parse import urlparse

BASE = pathlib.Path(__file__).resolve().parent


def apple_literal(value):
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('\r', '\\r').replace('\n', '\\n') + '"'


def osascript(source):
    result = subprocess.run(['osascript', '-'], input=source, text=True, capture_output=True, timeout=25)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or 'Safari 调用失败')
    return result.stdout.strip()


def evaluate(url, js):
    source = '''tell application "Safari"
set wantedURL to %s
repeat with aWindow in windows
repeat with aTab in tabs of aWindow
if URL of aTab is wantedURL then
return do JavaScript %s in aTab
end if
end repeat
end repeat
error "找不到启动时选定的图寻标签页；请回到原标签页后重新启动脚本。"
end tell''' % (apple_literal(url), apple_literal(js))
    return json.loads(osascript(source))


def settings(config, args):
    mode = args.delay_mode or config.get('delay_mode', 'fixed')
    if args.random_delay is not None:
        mode = 'random'
    elif args.delay is not None:
        mode = 'fixed'
    fixed = args.delay if args.delay is not None else float(config.get('delay_seconds', 10))
    low, high = args.random_delay if args.random_delay is not None else (
        float(config.get('delay_min_seconds', 8)), float(config.get('delay_max_seconds', 15)))
    offset = args.offset_meters if args.offset_meters is not None else float(config.get('offset_meters', 100))
    if mode not in ('fixed', 'random'):
        raise ValueError('delay_mode 只能是 fixed 或 random')
    if not all(math.isfinite(x) and 0 <= x <= 3600 for x in (fixed, low, high)):
        raise ValueError('等待秒数必须是 0 到 3600 之间的有限数字')
    if low > high:
        raise ValueError('随机等待的最短时间不能大于最长时间')
    if not math.isfinite(offset) or not 0 <= offset <= 100000:
        raise ValueError('偏移半径必须是 0 到 100000 米之间的有限数字')
    return {'delayMode': mode, 'delayMs': round(fixed * 1000),
            'delayMinMs': round(low * 1000), 'delayMaxMs': round(high * 1000),
            'offsetMeters': offset}


def main():
    parser = argparse.ArgumentParser(description='连接 Safari 当前图寻标签页，读取全景坐标并延迟提交。')
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--delay', type=float, help='固定等待秒数，覆盖配置中的等待模式')
    group.add_argument('--random-delay', nargs=2, type=float, metavar=('MIN', 'MAX'), help='每轮在此秒数区间随机等待')
    parser.add_argument('--delay-mode', choices=('fixed', 'random'), help='使用配置中的固定或随机等待参数')
    parser.add_argument('--offset-meters', type=float, help='随机偏移的最大半径（米），0 表示不偏移')
    parser.add_argument('--check', action='store_true', help='仅检查连接，不选点或提交')
    args = parser.parse_args()
    config = json.loads((BASE / 'config.json').read_text(encoding='utf-8'))
    options = settings(config, args)
    url = osascript('tell application "Safari" to get URL of current tab of front window')
    parsed = urlparse(url)
    if parsed.hostname != 'tuxun.fun' or not parsed.path.startswith(('/party/', '/solo/')):
        raise ValueError('请先在 Safari 当前标签页打开图寻对局（party 或 solo），再运行脚本。')
    if args.check:
        print(json.dumps(evaluate(url, 'JSON.stringify({url:location.href,title:document.title,text:document.body.innerText.slice(0,500)})'), ensure_ascii=False, indent=2))
        return
    run_id = str(uuid.uuid4())
    js = (BASE / 'runner.js').read_text(encoding='utf-8').replace('__RUN_ID__', json.dumps(run_id)).replace('__OPTIONS__', json.dumps(options, allow_nan=False))
    print('已连接：' + url, flush=True)
    if options['delayMode'] == 'random':
        print(f"每轮随机等待 {options['delayMinMs']/1000:g}–{options['delayMaxMs']/1000:g} 秒。", flush=True)
    else:
        print(f"每轮固定等待 {options['delayMs']/1000:g} 秒。", flush=True)
    print(f"位置随机偏移半径：{options['offsetMeters']:g} 米。Ctrl+C 停止。", flush=True)
    print('请保持原图寻标签页打开。页面刷新或进入新对局后可重新运行。', flush=True)
    last_event = 0
    last_round = None
    failures = 0
    log_path = BASE / 'last-run.log'
    with log_path.open('w', encoding='utf-8') as log:
        while True:
            try:
                result = evaluate(url, js)
                failures = 0
            except (RuntimeError, subprocess.TimeoutExpired, json.JSONDecodeError) as error:
                failures += 1
                print(f'连接异常（{failures}/3）：{error}', flush=True)
                if failures >= 3:
                    raise RuntimeError('连续三次连接失败，已停止。请检查 Safari 标签页和 JavaScript 权限。')
                time.sleep(2)
                continue
            if result.get('error'):
                raise RuntimeError(result['error'])
            current_round = (result.get('gameId'), result.get('round'))
            if current_round != last_round and result.get('round'):
                last_round = current_round
                print(f'\n第 {result["round"]} / {result.get("total") or "不限"} 轮', flush=True)
            for event in result.get('events', []):
                if event['id'] > last_event:
                    last_event = event['id']
                    extras = {k: v for k, v in event.items() if k not in ('id', 'time', 'message')}
                    print(event['message'] + ' ' + json.dumps(extras, ensure_ascii=False), flush=True)
                    log.write(json.dumps(event, ensure_ascii=False) + '\n')
                    log.flush()
            if result.get('done'):
                print('\n本局已结束，脚本停止。\n' + result.get('text', ''), flush=True)
                return
            time.sleep(1)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print('\n已停止。之后不会继续自动提交。')
    except Exception as error:
        print('\n错误：' + str(error), file=sys.stderr)
        print('若 Safari 拒绝执行 JavaScript：在 Safari 设置 → 高级中显示开发者功能，\n然后在“开发”菜单启用“允许来自 Apple 事件的 JavaScript”。', file=sys.stderr)
        sys.exit(1)
