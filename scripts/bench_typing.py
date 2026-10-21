# задержка набора: от нажатия до появления буквы на экране, во вставке (настоящий pty, языковой сервер работает)
# python3 scripts/bench_typing.py <папка проекта> <файл>
import os, pty, time, select, fcntl, termios, struct, signal, statistics, sys
env = dict(os.environ, NVIM_APPNAME="ownvim", TERM="xterm-256color")
REPLY = [(b"\x1b]11;?", b"\x1b]11;rgb:1010/1010/1010\x1b\\"), (b"\x1b[5n", b"\x1b[0n"), (b"\x1b[c", b"\x1b[?62;22c")]
pid, fd = pty.fork()
if pid == 0:
    os.chdir(sys.argv[1]); os.execvpe("nvim", ["nvim", "-n", sys.argv[2]], env)  # -n: без swap — прогон убивается
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 45, 160, 0, 0))
buf = b""; ans = {}
def pump(t):
    global buf
    end = time.perf_counter() + t; got = b""
    while time.perf_counter() < end:
        r, _, _ = select.select([fd], [], [], 0.002)
        if r:
            c = os.read(fd, 65536); buf += c; got += c
            for q, a in REPLY:
                n = buf.count(q)
                while ans.get(q, 0) < n: ans[q] = ans.get(q, 0) + 1; os.write(fd, a)
    return got
pump(4)                                   # старт, gopls подключился
os.write(fd, b"\x1bGo"); pump(1)          # новая строка внизу, вставка
def measure(ch, n):
    res = []
    for _ in range(n):
        t0 = time.perf_counter(); os.write(fd, ch); seen = b""
        while time.perf_counter() - t0 < 1.5:
            r, _, _ = select.select([fd], [], [], 0.001)
            if r:
                c = os.read(fd, 65536); seen += c
                if ch in seen: res.append((time.perf_counter() - t0) * 1000); break
        pump(0.12)                        # пауза между нажатиями, как у человека
    return res
for ch in (b"a", b"j"):
    r = measure(ch, 25)
    print(f"'{ch.decode()}': медиана {statistics.median(r):.1f} мс, 90% {sorted(r)[int(len(r)*0.9)-1]:.1f} мс (n={len(r)})")
os.kill(pid, signal.SIGKILL); os.waitpid(pid, 0)
