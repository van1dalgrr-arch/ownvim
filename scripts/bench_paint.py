# время от запуска ownvim до момента, когда код файла нарисован (pty, отвечаем на запросы, как настоящий терминал)
# python3 scripts/bench_paint.py <папка> <файл> <строка из файла> [прогонов]; XDG_CONFIG_HOME=<папка с ownvim/> — сравнить с другой копией
import os, pty, sys, time, select, statistics, fcntl, termios, struct, signal
d, f, marker = sys.argv[1], sys.argv[2], sys.argv[3].encode(); n = int(sys.argv[4]) if len(sys.argv) > 4 else 10
env = dict(os.environ, NVIM_APPNAME="ownvim", TERM="xterm-256color", COLORTERM="truecolor")
REPLY = [(b"\x1b]11;?", b"\x1b]11;rgb:1010/1010/1010\x1b\\"), (b"\x1b[5n", b"\x1b[0n"), (b"\x1b[c", b"\x1b[?62;22c")]
times = []
for i in range(n + 1):
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(d); os.execvpe("nvim", ["nvim", "-n", f], env)  # -n: без swap — прогоны убиваются
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 45, 160, 0, 0))
    t0 = time.perf_counter(); buf = b""; got = None; answered = {}
    while time.perf_counter() - t0 < 5:
        r, _, _ = select.select([fd], [], [], 0.01)
        if not r: continue
        try: buf += os.read(fd, 65536)
        except OSError: break
        for q, a in REPLY:
            c = buf.count(q)
            while answered.get(q, 0) < c: answered[q] = answered.get(q, 0) + 1; os.write(fd, a)
        if marker in buf: got = (time.perf_counter() - t0) * 1000; break
    os.kill(pid, signal.SIGKILL); os.waitpid(pid, 0); os.close(fd)
    if i > 0 and got: times.append(got)
print(f"медиана {statistics.median(times):.1f} мс  (мин {min(times):.1f}, макс {max(times):.1f}, n={len(times)})")
