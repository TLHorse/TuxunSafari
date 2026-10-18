#!/usr/bin/env python3
"""Safari 图寻脚本：仅使用 AppleScript + 页面 JavaScript。"""
import argparse
import json
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


def main():
    parser = argparse.ArgumentParser(description='连接 Safari 当前图寻标签页，读取全景坐标并延迟提交。')
    parser.add_argument('--delay', type=float, help='读到坐标后等待的秒数，覆盖 config.json')
    parser.add_argument('--check', action='store_true', help='仅检查连接，不选点或提交')
    args = parser.parse_args()
    config = json.loads((BASE / 'config.json').read_text(encoding='utf-8'))
    delay = args.delay if args.delay is not None else float(config.get('delay_seconds', 10))
    if not 0 <= delay <= 3600:
        raise ValueError('等待秒数应在 0 到 3600 之间')
    url = osascript('tell application "Safari" to get URL of current tab of front window')
    parsed = urlparse(url)
    if parsed.hostname != 'tuxun.fun' or not parsed.path.startswith(('/party/', '/solo/')):
        raise ValueError('请先在 Safari 当前标签页打开图寻对局（party 或 solo），再运行脚本。')
    if args.check:
        print(json.dumps(evaluate(url, 'JSON.stringify({url:location.href,title:document.title,text:document.body.innerText.slice(0,500)})'), ensure_ascii=False, indent=2))
        return
    run_id = str(uuid.uuid4())
    js = (BASE / 'runner.js').read_text(encoding='utf-8').replace('__RUN_ID__', json.dumps(run_id)).replace('__DELAY_MS__', str(round(delay * 1000)))
    print('已连接：' + url, flush=True)
    print(f'每轮读到坐标后等待 {delay:g} 秒再提交。Ctrl+C 停止。', flush=True)
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
