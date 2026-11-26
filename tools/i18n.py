#!/usr/bin/env python3
"""Traductions des messages de passionphoto (core.get_translator("passionphoto") -> S("…")).

  python3 -I tools/i18n.py           extrait les S("…") de init.lua et src/**/*.lua, met à jour locale/template.txt
                                     et ajoute les entrées manquantes (vides) à chaque locale/passionphoto.<lang>.tr
  python3 -I tools/i18n.py --check   n'écrit rien ; code 1 si le modèle n'est pas à jour, s'il manque une
                                     traduction, ou si une traduction a des paramètres @1…@9 différents

Le texte source est le FRANÇAIS ; locale/passionphoto.en.tr donne l'anglais (comme chester).
Les concaténations de littéraux (S("a" .. "b")) sont prises en compte. Repris de chester.
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCALE = os.path.join(ROOT, "locale")
DOMAIN = "passionphoto"
CALL = re.compile(r'\bS\(\s*((?:"(?:[^"\\]|\\.)*"\s*(?:\.\.\s*)?)+)')
LIT = re.compile(r'"((?:[^"\\]|\\.)*)"')


def unescape(s):
    return re.sub(r'\\(.)', lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), s)


def tr_escape(s):
    return s.replace("=", "@=").replace("\n", "@n")


def sources():
    files = [os.path.join(ROOT, "init.lua")]
    files += sorted(glob.glob(os.path.join(ROOT, "src", "**", "*.lua"), recursive=True))
    return [f for f in files if os.path.isfile(f)]


def extract():
    found = []
    for path in sources():
        src = open(path, encoding="utf-8").read()
        for m in CALL.finditer(src):
            s = "".join(unescape(x) for x in LIT.findall(m.group(1)))
            if s not in found:
                found.append(s)
    return found


def read_tr(path):
    entries = {}
    if not os.path.exists(path):
        return entries
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        m = re.match(r"^((?:[^=@]|@.)*)=(.*)$", line)
        if m:
            entries[m.group(1)] = m.group(2)
    return entries


def params(s):
    return sorted(set(re.findall(r"@(\d)", s)))


def main():
    check = "--check" in sys.argv
    strings = extract()
    keys = [tr_escape(s) for s in strings]
    header = f"# textdomain: {DOMAIN}\n"
    template = header + "".join(k + "=\n" for k in keys)
    problems = []
    tpath = os.path.join(LOCALE, "template.txt")
    old = open(tpath, encoding="utf-8").read() if os.path.exists(tpath) else ""
    if old != template:
        problems.append("locale/template.txt n'est pas à jour (lancer make i18n)")
        if not check:
            os.makedirs(LOCALE, exist_ok=True)
            open(tpath, "w", encoding="utf-8").write(template)
    for path in sorted(glob.glob(os.path.join(LOCALE, f"{DOMAIN}.*.tr"))):
        name = os.path.basename(path)
        entries = read_tr(path)
        for k in keys:
            if not entries.get(k):
                problems.append(f"{name} : traduction manquante : {k}")
            elif params(k) != params(entries[k]):
                problems.append(f"{name} : paramètres différents : {k}")
        stale = [k for k in entries if k not in keys]
        for k in stale:
            problems.append(f"{name} : entrée obsolète : {k}")
        if not check:
            out = [f"# textdomain: {DOMAIN}"]
            out += [f"{k}={entries.get(k, '')}" for k in keys]
            out += [f"# obsolète : {k}={entries[k]}" for k in stale]
            open(path, "w", encoding="utf-8").write("\n".join(out) + "\n")
    print(f"i18n : {len(keys)} message(s)" + (f", {len(problems)} problème(s)" if problems else " — OK"))
    for p in problems:
        print("  " + p)
    if check and problems:
        sys.exit(1)


if __name__ == "__main__":
    main()
