#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""正统马哲深度学习系统 —— 一键安装 / 启动 / 停止 跨平台启动器。

纯标准库实现（运行本脚本无需第三方依赖）；仅在真正启动/安装时才用到 venv 与依赖。
用法:
    python scripts/oneclick.py install     # 安装（创建 venv、装依赖、生成 .env、构建前端）
    python scripts/oneclick.py start       # 启动（后端 8190 + 前端 8080），并打开浏览器
    python scripts/oneclick.py stop        # 停止
    python scripts/oneclick.py all         # 安装 + 启动
"""
from __future__ import annotations

import os
import sys
import shutil
import subprocess
import time
import urllib.request

# ---- 控制台统一 UTF-8（Windows GBK 控制台打印中文不乱码）----
try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BACKEND = os.path.join(ROOT, "backend")
FRONTEND = os.path.join(ROOT, "frontend")
VENV_DIR = os.path.join(BACKEND, ".venv")
VENV_PY = os.path.join(VENV_DIR, "Scripts", "python.exe") if os.name == "nt" \
    else os.path.join(VENV_DIR, "bin", "python")
REQUIREMENTS = os.path.join(BACKEND, "requirements.txt")
ENV_FILE = os.path.join(BACKEND, ".env")
ENV_EXAMPLE = os.path.join(BACKEND, ".env.example")
BACK_PORT = 8190
FRONT_PORT = 8080
BACKEND_LOG = os.path.join(ROOT, ".xxmz-backend.log")
FRONTEND_LOG = os.path.join(ROOT, ".xxmz-frontend.log")
BACKEND_PID = os.path.join(ROOT, ".xxmz-backend.pid")
FRONTEND_PID = os.path.join(ROOT, ".xxmz-frontend.pid")


def log(*a):
    print(*a, flush=True)


def banner(text):
    log("=" * 52)
    log(f"   {text}")
    log("=" * 52)


def http_ok(url, timeout=2.0):
    try:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            return 200 <= r.status < 400
    except Exception:
        return False


def system_python():
    return sys.executable or shutil.which("python") or shutil.which("python3")


# ------------------------------------------------------------------ 端口 / 进程

def netstat_pids(port: int):
    """返回正在 LISTEN 指定端口的 PID 集合（跨平台，尽力而为）。"""
    pids = set()
    try:
        if os.name == "nt":
            out = subprocess.run(["netstat", "-ano"], capture_output=True, text=True).stdout
            for line in out.splitlines():
                u = line.upper()
                if f":{port} " in line and "LISTENING" in u:
                    parts = line.split()
                    if parts and parts[-1].isdigit():
                        pids.add(int(parts[-1]))
        else:
            out = subprocess.run(["lsof", "-nP", f"-iTCP:{port}", "-sTCP:LISTEN"],
                                 capture_output=True, text=True).stdout
            for line in out.splitlines()[1:]:
                parts = line.split()
                if len(parts) >= 2 and parts[1].isdigit():
                    pids.add(int(parts[1]))
    except Exception:
        pass
    return pids


def port_busy(port: int) -> bool:
    return bool(netstat_pids(port))


def kill_pid(pid: int):
    try:
        if os.name == "nt":
            subprocess.run(["taskkill", "/PID", str(pid), "/F"],
                           capture_output=True, text=True)
        else:
            os.kill(pid, 9)
    except Exception:
        pass


def _spawn_detached(cmd, cwd, env, log_path):
    """后台脱离式启动子进程，日志写入 log_path，返回 Popen。"""
    f = open(log_path, "w", encoding="utf-8", errors="replace")
    kwargs = dict(cwd=cwd, env=env, stdout=f, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
    if os.name == "nt":
        DETACHED_PROCESS = 0x00000008
        CREATE_NEW_PROCESS_GROUP = 0x00000200
        p = subprocess.Popen(cmd, creationflags=DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP, **kwargs)
    else:
        p = subprocess.Popen(cmd, start_new_session=True, **kwargs)
    try:
        with open(log_path + ".pid", "w") as pf:
            pf.write(str(p.pid))
    except Exception:
        pass
    return p


# ------------------------------------------------------------------ 安装

def ensure_venv():
    if os.path.exists(VENV_PY):
        return
    log("[2/4] 创建后端虚拟环境 backend/.venv ...")
    import venv as _venv
    _venv.create(VENV_DIR, system_site_packages=True, with_pip=True)
    if not os.path.exists(VENV_PY):  # 极端情况下 venv 路径异常
        raise RuntimeError("虚拟环境创建失败，未找到 " + VENV_PY)


def pip_install():
    log("      安装后端依赖（首次可能几分钟，请耐心等待）...")
    subprocess.run([VENV_PY, "-m", "pip", "install", "--upgrade", "pip"],
                   capture_output=True, text=True)
    rc = subprocess.run([VENV_PY, "-m", "pip", "install", "-r", REQUIREMENTS, "aiosqlite"]).returncode
    if rc != 0:
        log("")
        log("[错误] 后端依赖安装失败。若网络受限，可换国内镜像后重试：")
        log(f'       "{VENV_PY}" -m pip install -r backend\\requirements.txt aiosqlite -i https://pypi.tuna.tsinghua.edu.cn/simple')
        raise SystemExit(1)


def ensure_env():
    log("[3/4] 生成配置文件 backend/.env ...")
    if not os.path.exists(ENV_FILE) and os.path.exists(ENV_EXAMPLE):
        shutil.copyfile(ENV_EXAMPLE, ENV_FILE)
        log("      已由 .env.example 生成 backend/.env")
    elif os.path.exists(ENV_FILE):
        log("      backend/.env 已存在，保留原配置")


def _run_fixed(argv, cwd):
    """Run a *fixed* argv list without a shell (no command-injection surface).

    Keeping shell=False is deliberate: the commands here are compile-time
    constants (never user input), so a shell only widens the attack surface.
    Windows quirk: `flutter` resolves to `flutter.BAT`, and CreateProcess cannot
    launch a .bat/.cmd directly -- those must go through `cmd /c`. We therefore
    only wrap in cmd.exe when the resolved launcher is a batch/cmd file on nt.
    """
    exe = shutil.which(argv[0]) or argv[0]
    args = [exe, *argv[1:]]
    if os.name == "nt" and exe.lower().endswith((".bat", ".cmd")):
        args = ["cmd", "/c", *args]
    subprocess.run(args, cwd=cwd, check=False)


def prune_web_build():
    """Prune the Flutter Web build dir of assets the browser never fetches.

    Flutter emits every CanvasKit renderer variant plus *.js.symbols maps into
    build/web/canvaskit/.  A default (JS) build on Chrome only actually loads
    `canvaskit/chromium/canvaskit.{js,wasm}`; other engines load
    `canvaskit/canvaskit.{js,wasm}`.  The `skwasm*`, `wimp*` and
    `experimental_webparagraph/*` trees are only used by non-default renderers,
    and `*.js.symbols` is source-map-only (never served to browsers).  Pruning
    them removes ~30 MB from disk with **zero** change to the runtime first-load
    payload.  Missing optional variants just fall back to the default CanvasKit.
    """
    root = os.path.join(FRONTEND, "build", "web")
    ck = os.path.join(root, "canvaskit")
    if not os.path.isdir(ck):
        return
    removed = 0
    # 1) drop *.js.symbols everywhere (stack-trace maps, never fetched)
    for dirpath, _dirs, files in os.walk(root):
        for f in files:
            if f.endswith(".js.symbols"):
                try:
                    os.remove(os.path.join(dirpath, f))
                    removed += 1
                except OSError:
                    pass
    # 2) drop non-default CanvasKit renderer variants (keep root + chromium)
    for name in ("skwasm.js", "skwasm.wasm", "skwasm_heavy.wasm"):
        pth = os.path.join(ck, name)
        if os.path.exists(pth):
            try:
                os.remove(pth)
                removed += 1
            except OSError:
                pass
    for sub in ("experimental_webparagraph",):
        shutil.rmtree(os.path.join(ck, sub), ignore_errors=True)
        removed += 1
    for f in os.listdir(ck):
        if f.startswith("wimp") or f.startswith("skwasm"):
            try:
                os.remove(os.path.join(ck, f))
                removed += 1
            except OSError:
                pass
    log(f"      已裁剪未使用的前端渲染变体/符号表（约 {removed} 项），首屏载荷不变")


def build_frontend():
    log("[4/4] 检查 Flutter 并构建前端（可选）...")
    if os.path.exists(os.path.join(FRONTEND, "build", "web", "index.html")):
        log("      前端已构建，跳过（如需重建请删除 frontend/build/web 后重跑）")
        return
    if not shutil.which("flutter"):
        log("      未检测到 Flutter，跳过前端构建。仅后端 API 可用（http://localhost:8190/docs）")
        return
    log("      正在 pub get + build web ...（首次较慢）")
    try:
        _run_fixed(["flutter", "pub", "get"], FRONTEND)
        # --no-web-resources-cdn: 把 CanvasKit 打包到本地，避免国内无法访问
        #   www.gstatic.com（否则页面一片空白）。
        # --pwa-strategy=none: 禁用 Service Worker，避免旧缓存导致白屏。
        # --no-tree-shake-icons: Flutter 的图标 tree-shaking 不收录框架自动注入的图标
        #   （AppBar 返回箭头 arrow_back、下拉箭头 arrow_drop_down、close、check 等），
        #   这些码点缺失后 CanvasKit 会渲染成【方框内带 X】的 .notdef 豆腐块。
        #   必须关闭 tree-shaking，打包官方全量图标字体（1.57MB）。
        _run_fixed(["flutter", "build", "web", "--pwa-strategy=none",
                    "--no-web-resources-cdn", "--no-tree-shake-icons"], FRONTEND)
    except Exception as e:
        log(f"      [提示] 前端构建异常：{e}")
        return
    if os.path.exists(os.path.join(FRONTEND, "build", "web", "index.html")):
        log("      前端构建完成")
        prune_web_build()
    else:
        log("      [提示] 前端构建未成功，后端不受影响；可稍后重试或直接 flutter run。")


def do_install():
    banner("正统马哲深度学习系统 — 一键安装")
    log("[1/4] 检查 Python ...")
    py = system_python()
    if not py:
        log("[错误] 未找到 Python，请安装 Python 3.10+ 并加入 PATH。")
        raise SystemExit(1)
    log(f"      Python {sys.version.split()[0]}  ({py})")
    ensure_venv()
    pip_install()
    ensure_env()
    build_frontend()
    log("")
    log("安装完成 ✅  请运行「一键启动」（或 ./一键安装启动.sh start）。")


# ------------------------------------------------------------------ 启动

def do_start():
    banner("正统马哲深度学习系统 — 一键启动")
    if not os.path.exists(VENV_PY):
        log("[错误] 尚未安装，请先运行「一键安装」（或 ./一键安装启动.sh install）。")
        raise SystemExit(1)
    if port_busy(BACK_PORT):
        log(f"[错误] 端口 {BACK_PORT} 已被占用，后端可能已在运行。先「停止」再试。")
        raise SystemExit(1)

    env = os.environ.copy()
    env["LEARNING_DB_MODE"] = "memory"
    env["AUTO_CREATE_TABLES"] = "0"

    log(f"[1/2] 启动后端 API（轻量模式，无需 Docker/PG）: :{BACK_PORT}")
    _spawn_detached([VENV_PY, "-m", "uvicorn", "app:app",
                     "--host", "0.0.0.0", "--port", str(BACK_PORT)],
                    cwd=BACKEND, env=env, log_path=BACKEND_LOG)

    log("      等待后端就绪 ...")
    ready = False
    for _ in range(40):
        if http_ok(f"http://localhost:{BACK_PORT}/api/routes"):
            ready = True
            break
        time.sleep(1)
    if ready:
        log(f"      后端已就绪: http://localhost:{BACK_PORT}")
    else:
        log(f"      [警告] 后端 40s 内未就绪，请查看日志: {BACKEND_LOG}")

    web = None
    if os.path.exists(os.path.join(FRONTEND, "build", "web", "index.html")) and not port_busy(FRONT_PORT):
        log(f"[2/2] 启动前端静态服务（无缓存）: :{FRONT_PORT}")
        # 用自带的无缓存静态服务器，确保浏览器每次都拿到最新构建，
        # 避免旧 main.dart.js / 字体被启发式缓存导致“改好了仍显示旧bug”。
        _spawn_detached([VENV_PY, os.path.join(ROOT, "scripts", "serve_frontend.py"), str(FRONT_PORT)],
                        cwd=os.path.join(FRONTEND, "build", "web"), env=env, log_path=FRONTEND_LOG)
        for _ in range(8):
            if http_ok(f"http://localhost:{FRONT_PORT}/index.html"):
                break
            time.sleep(0.5)
        web = f"http://localhost:{FRONT_PORT}"
    else:
        log("[2/2] 跳过前端静态服务（未构建或端口占用）")
        log("      前端可用: cd frontend && flutter run -d chrome")

    log("")
    log("=" * 52)
    log("  启动完成！")
    log(f"  网页界面 : {web or '(前端未启动)'}")
    log(f"  接口文档 : http://localhost:{BACK_PORT}/docs")
    log("  登录账号密码：本系统当前无登录，打开即用（演示用户 demo_user）")
    log("  停止     : 运行「停止」（或 ./一键安装启动.sh stop）")
    log("=" * 52)

    if web and ready:
        try:
            import webbrowser
            webbrowser.open(web)
        except Exception:
            pass


# ------------------------------------------------------------------ 停止

def do_stop():
    banner("正在停止 正统马哲深度学习系统 ...")
    killed = set()
    for pf in (BACKEND_PID, FRONTEND_PID):
        try:
            if os.path.exists(pf):
                pid = int(open(pf).read().strip())
                kill_pid(pid)
                killed.add(pid)
                os.remove(pf)
        except Exception:
            pass
    for port in (BACK_PORT, FRONT_PORT):
        for pid in netstat_pids(port):
            kill_pid(pid)
            killed.add(pid)
    log(f"已停止（{BACK_PORT} / {FRONT_PORT} 端口已释放）")


def main(argv):
    action = argv[1] if len(argv) > 1 else "all"
    if action == "install":
        do_install()
    elif action == "start":
        do_start()
    elif action == "stop":
        do_stop()
    elif action == "all":
        do_install()
        do_start()
    else:
        log(f"未知命令: {action}（可用: install | start | stop | all）")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
