# Пример: что за файл и сколько в нём строк — в уведомлении (пробел x i).
import os, sys

text = sys.stdin.read()
print(f"{os.path.basename(os.environ[\"OWN_FILE\"])}: {len(text.splitlines())} строк, тип {os.environ[\"OWN_FILETYPE\"]}")
