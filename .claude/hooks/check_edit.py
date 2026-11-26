#!/usr/bin/env python3
"""Hook PostToolUse (Edit|Write) : contrôle rapide et non destructif du fichier modifié (repris de chester).

- .lua  : compilation LuaJIT (`luajit -bl`, syntaxe seulement) ; luacheck en plus s'il est installé (erreurs seulement).
- .py   : compilation Python (py_compile).
- .json : JSON valide.
- .sh   : `sh -n`, ou `bash -n` si le script commence par un shebang bash.
- .px   : source pixel art valide (palette « x = #rrggbb[aa] », rangées de même largeur, symboles définis).
- .tr   : première ligne « # textdomain: passionphoto ».
- .claude/agents/*.md, .claude/skills/*/SKILL.md : frontmatter avec name et description.
- Écriture dans .deps/, .run/ ou .headless/ signalée (dépendances et dossiers générés : jamais modifiés à la main).
Code de sortie 2 = message renvoyé à Claude (le fichier est déjà écrit : il doit le corriger). Ne modifie rien.
"""
import json
import os
import re
import shutil
import subprocess
import sys


def fail(msg):
    print(msg, file=sys.stderr)
    sys.exit(2)


try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
path = (data.get("tool_input") or {}).get("file_path") or ""
if not path or not os.path.isfile(path):
    sys.exit(0)
root = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
rel = os.path.relpath(os.path.realpath(path), os.path.realpath(root))

for protected in (".deps", ".run", ".headless"):
    if rel == protected or rel.startswith(protected + os.sep):
        fail(f"{rel} : {protected}/ n'est jamais modifié à la main (CLAUDE.md, règles de sécurité). Annule cette "
             f"modification ; .deps/ se prépare avec tools/fetch_deps.sh, .run/ avec tools/server.sh, "
             f".headless/ avec tools/headless/run.sh.")


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


if path.endswith(".lua"):
    luajit = shutil.which("luajit")
    if luajit:
        r = subprocess.run([luajit, "-bl", path, os.devnull], capture_output=True, text=True)
        if r.returncode != 0:
            fail(f"Erreur de syntaxe Lua dans {rel} :\n{(r.stderr or r.stdout).strip()}")
    luacheck = shutil.which("luacheck")
    if luacheck:
        r = subprocess.run([luacheck, "--no-color", "-q", path], capture_output=True, text=True, cwd=root)
        if r.returncode not in (0, 1):  # 1 = avertissements seulement
            fail(f"luacheck signale des erreurs dans {rel} :\n{r.stdout.strip()}")
elif path.endswith(".py"):
    r = subprocess.run([sys.executable, "-m", "py_compile", path], capture_output=True, text=True)
    if r.returncode != 0:
        fail(f"Erreur de syntaxe Python dans {rel} :\n{r.stderr.strip()}")
elif path.endswith(".json"):
    try:
        json.loads(read(path))
    except Exception as e:
        fail(f"JSON invalide dans {rel} : {e}")
elif path.endswith(".sh"):
    first = read(path).split("\n", 1)[0]
    shell = "bash" if "bash" in first else "sh"
    r = subprocess.run([shell, "-n", path], capture_output=True, text=True)
    if r.returncode != 0:
        fail(f"Erreur de syntaxe {shell} dans {rel} :\n{r.stderr.strip()}")
elif path.endswith(".px"):
    palette, rows = {}, []
    for n, line in enumerate(read(path).splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        m = re.match(r"^(\S)\s*=\s*(\S+)\s*$", line)
        if m and not rows:
            sym, col = m.groups()
            if col != "transparent" and not re.match(r"^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$", col):
                fail(f"{rel}:{n} : couleur invalide « {col} » (attendu #rrggbb, #rrggbbaa ou transparent).")
            palette[sym] = col
            continue
        rows.append((n, line.rstrip("\n")))
    if not rows:
        fail(f"{rel} : aucune rangée de pixels.")
    width = len(rows[0][1])
    for n, row in rows:
        if len(row) != width:
            fail(f"{rel}:{n} : rangée de {len(row)} pixels, {width} attendus (toutes les rangées ont la même largeur).")
        unknown = sorted(set(row) - set(palette))
        if unknown:
            fail(f"{rel}:{n} : symbole(s) sans couleur dans la palette : {' '.join(unknown)}")
elif path.endswith(".tr"):
    if not read(path).startswith("# textdomain: passionphoto"):
        fail(f"{rel} : la première ligne doit être « # textdomain: passionphoto ».")
elif re.search(r"\.claude/(agents/[^/]+\.md|skills/[^/]+/SKILL\.md)$", path):
    m = re.match(r"^---\n(.*?)\n---\n", read(path), re.S)
    if not m:
        fail(f"{rel} : le frontmatter YAML doit commencer à la première ligne (---).")
    for field in ("name", "description"):
        if not re.search(rf"^{field}:\s*\S", m.group(1), re.M):
            fail(f"{rel} : champ « {field} » manquant dans le frontmatter.")
sys.exit(0)
