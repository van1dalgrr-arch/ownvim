# Пример расширения: сортирует выделенные строки (пробел x s в обычном/выделении).
import sys

lines = sys.stdin.read().split("\n")
print("\n".join(sorted(lines, key=str.lower)), end="")
