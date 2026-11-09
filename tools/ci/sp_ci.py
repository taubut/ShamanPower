#!/usr/bin/env python3
"""sp-ci: ShamanPower's checks without the game. Syntax, line endings, the and/or trap, the lint,
the changelog, then the real addon in the headless sim (sp-uipreview) on both clients: every
settings page and tab opened, every icon row's menus built, and the tests in tools/ci/tests.
Run from an addon tree:  sp-ci [--client both|forever|anniversary] [--skip-lint] [--only a,b] [-v]"""
import argparse, json, os, re, subprocess, sys, glob, time

ROOT = os.path.dirname(os.path.abspath(__file__))
RELEASE = False
LUAC = "luac5.1" if subprocess.run(["which", "luac5.1"], capture_output=True).returncode == 0 else "luac"   # WoW is Lua 5.1: a 5.4+ luac rejects assignments to loop variables

def run(cmd, timeout=900, env=None):
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=env)
    return p.returncode, (p.stdout or "") + (p.stderr or "")

def lua_files(tree):
    out = []
    for p in glob.glob(os.path.join(tree, "**", "*.lua"), recursive=True):
        rel = os.path.relpath(p, tree)
        if rel.startswith("tools/") or "/Libs/" in "/" + rel or rel.startswith("Libs/") or "/.git/" in p:
            continue
        out.append(rel)
    return sorted(out)

def step_syntax(tree):
    bad = []
    for rel in lua_files(tree) + ["tools/ci/harness.lua"] + [os.path.relpath(p, tree) for p in glob.glob(os.path.join(tree, "tools/ci/tests/*.lua"))]:
        rc, out = run([LUAC, "-p", os.path.join(tree, rel)])
        if rc != 0:
            bad.append(out.strip().splitlines()[-1] if out.strip() else rel)
    return (not bad), bad

def expected_crlf(rel):
    """the repo's rule: the core's Lua is LF, its TOCs, CHANGELOG and locale are CRLF; every module folder is CRLF
    except ShamanPower_Config, which is LF throughout (TOCs included)"""
    if rel.startswith("ShamanPower_Config/"):
        return False
    if rel.endswith(".toc") or rel == "CHANGELOG.md" or rel.startswith("locale/"):
        return True
    if rel.startswith("ShamanPower_") and "/" in rel:
        return True
    return False

def step_endings(tree):
    bad = []
    files = lua_files(tree) + [os.path.relpath(p, tree) for p in glob.glob(os.path.join(tree, "*.toc"))] + ["CHANGELOG.md"]
    files += [os.path.relpath(p, tree) for p in glob.glob(os.path.join(tree, "ShamanPower_*/*.toc"))]
    for rel in sorted(set(files)):
        path = os.path.join(tree, rel)
        if not os.path.isfile(path):
            continue
        data = open(path, "rb").read()
        if b"\n" not in data:
            continue
        crlf = b"\r\n" in data
        mixed = crlf and (data.count(b"\n") != data.count(b"\r\n"))
        want = expected_crlf(rel)
        if mixed:
            bad.append("%s: mixed line endings" % rel)
        elif crlf != want:
            bad.append("%s: %s, expected %s" % (rel, "CRLF" if crlf else "LF", "CRLF" if want else "LF"))
    return (not bad), bad

def step_andor(tree):
    bad = []
    rx = re.compile(r"\band\s+(false|nil)\s+or\b")
    for rel in lua_files(tree):
        for i, line in enumerate(open(os.path.join(tree, rel), encoding="utf-8", errors="replace"), 1):
            if rx.search(line) and not line.strip().startswith("--"):
                bad.append("%s:%d: %s" % (rel, i, line.strip()[:100]))
    return (not bad), bad

# Shared library tables (the owner, 2026-10-17: "how do we make sure we dont have that happen EVER?").
# Some library tables are the same table for every addon: AceDBOptions' Profiles rows and
# SharedMedia's MediaTable. Writing into them shows ShamanPower's changes in other addons (and theirs in
# ours). Allowed only where it is guarded: the profiles rows go through OwnProfileArgs, a MediaTable write
# only under a free name (an "== nil" test on the line before). Libs/ is the libraries' own code.
SHARED_RULES = [
    (re.compile(r'LibStub\(\s*["\']AceDBOptions-3\.0["\']\s*\)\s*:\s*GetOptionsTable'),
     lambda lines, i: "OwnProfileArgs" in lines[i + 1] if i + 1 < len(lines) else False,
     "AceDBOptions rows are every addon's: copy them with SP:OwnProfileArgs on the next line"),
    (re.compile(r'MediaTable\s*\.\s*\w+\s*\[[^\]]+\]\s*=[^=]'),
     lambda lines, i: i > 0 and "== nil" in lines[i - 1],
     "SharedMedia's MediaTable is every addon's: write only under a free name (test == nil first)"),
    (re.compile(r'\.args\s*=\s*optionsTable\b'),
     lambda lines, i: False,
     "never hand a library's shared options table to an options page"),
]
def step_shared_tables(tree):
    bad = []
    for rel in lua_files(tree):
        if rel.startswith("Libs/") or "/Libs/" in rel:
            continue
        lines = open(os.path.join(tree, rel), encoding="utf-8", errors="replace").read().split("\n")
        for i, line in enumerate(lines):
            if line.strip().startswith("--"):
                continue
            for rx, ok, why in SHARED_RULES:
                if rx.search(line) and not ok(lines, i):
                    bad.append("%s:%d: %s (%s)" % (rel, i + 1, line.strip()[:90], why))
    return (not bad), bad

def step_share_mirror(tree):
    """the setup code's feature list (SP.SHARE_FEATURES, append-only) and its mirror tools/share-code-features.json,
    which the Discord bot decodes with: same keys, same order"""
    lua_path, json_path = os.path.join(tree, "ShamanPowerShareCode.lua"), os.path.join(tree, "tools", "share-code-features.json")
    if not (os.path.exists(lua_path) and os.path.exists(json_path)):
        return True, []
    src = open(lua_path, encoding="utf-8").read()
    block = src[src.index("SP.SHARE_FEATURES = {"):]
    lua_keys = re.findall(r'^\t\{ key = "([^"]+)"', block, re.M)
    json_keys = [f["key"] for f in json.load(open(json_path, encoding="utf-8"))["features"]]
    if lua_keys == json_keys:
        return True, []
    bad = ["ShamanPowerShareCode.lua has %d features, tools/share-code-features.json %d" % (len(lua_keys), len(json_keys))]
    for i, (a, b) in enumerate(zip(lua_keys, json_keys)):
        if a != b:
            bad.append("feature %d: %s in the Lua, %s in the json" % (i + 1, a, b))
            break
    return False, bad

LINT_LINE = re.compile(r"^(\S+?\.lua):(\d+)")
def changed_lines(tree, base):
    """{relpath: set(line numbers)} changed against `base` (committed and uncommitted), untracked files whole"""
    out = {}
    rc, diff = run(["git", "-C", tree, "diff", "-U0", base, "--", "*.lua"])
    if rc != 0:
        return None
    cur = None
    for line in diff.splitlines():
        if line.startswith("+++ b/"):
            cur = line[6:]; out.setdefault(cur, set())
        elif line.startswith("@@") and cur:
            m = re.search(r"\+(\d+)(?:,(\d+))?", line)
            if m:
                start, n = int(m.group(1)), int(m.group(2) or "1")
                out[cur].update(range(start, start + n))
    rc, untracked = run(["git", "-C", tree, "ls-files", "--others", "--exclude-standard"])
    for rel in untracked.split():
        if rel.endswith(".lua"):
            out[rel] = None   # every line is new
    return out

def step_libs(tree):
    """every bundled library the newest out there (lib_versions.py): against the installed addons' copies
    on this machine (warnings), and with --release against each library's official source (fails)"""
    sys.path.insert(0, ROOT)
    sys.dont_write_bytecode = True   # no __pycache__ in the tree
    import lib_versions
    return lib_versions.check(tree, use_online=RELEASE, use_local=True)

def step_lint(tree, base):
    """shamanpower-lint over the whole tree; the rule is that only NEW lines (changed against `base`) must be clean,
    the old findings are a count"""
    rc, out = run(["shamanpower-lint", tree], timeout=1200)
    findings = []
    for line in out.splitlines():
        m = LINT_LINE.match(line.strip())
        if m:
            findings.append((m.group(1), int(m.group(2)), line.strip()))
    if "Traceback" in out:
        return False, ["lint crashed: " + out.strip().splitlines()[-1]]
    changed = changed_lines(tree, base)
    if changed is None:
        return True, ["warn: not a git tree or no '%s': %d findings in all, none checked against new lines" % (base, len(findings))]
    fresh = []
    for rel, ln, text in findings:
        if rel.startswith("tools/"):
            continue   # the sim tests use sim globals; not shipped
        lines = changed.get(rel)
        if rel in changed and (lines is None or ln in lines):
            fresh.append(text)
    detail = ["%d findings in all, %d on lines new since %s" % (len(findings), len(fresh), base)]
    return (not fresh), detail + fresh[:60]

def step_changelog(tree):
    bad = []
    toc = open(os.path.join(tree, "ShamanPower.toc"), encoding="utf-8", errors="replace").read()
    m = re.search(r"## Version:\s*([\d.]+)", toc)
    ver = m.group(1) if m else "?"
    cl = open(os.path.join(tree, "CHANGELOG.md"), encoding="utf-8", errors="replace").read()
    pn = open(os.path.join(tree, "ShamanPower_Config/PatchNotes.lua"), encoding="utf-8", errors="replace").read()
    top = re.search(r"^## v([\d.]+)", cl, re.M)
    first = re.search(r'v\s*=\s*"([\d.]+)"', pn)
    if not top: bad.append("CHANGELOG.md has no '## v' section")
    if not first: bad.append("PatchNotes.lua has no v = entry")
    if top and first and top.group(1) != first.group(1):
        bad.append("CHANGELOG top section v%s but PatchNotes first entry v%s" % (top.group(1), first.group(1)))
    warn = []
    if top and ver != "?" and top.group(1) != ver:
        warn.append("TOC says %s, CHANGELOG top section is v%s (fine before a bump; wrong at release)" % (ver, top.group(1)))
    tocs = glob.glob(os.path.join(tree, "*.toc")) + glob.glob(os.path.join(tree, "ShamanPower_*/*.toc"))
    vers = set()
    for t in tocs:
        m2 = re.search(r"## Version:\s*([\d.]+)", open(t, encoding="utf-8", errors="replace").read())
        vers.add(m2.group(1) if m2 else "?")
    if len(vers) > 1:
        bad.append("TOC versions differ: %s" % ", ".join(sorted(vers)))
    if RELEASE:
        bad += warn
    return (not bad), bad + ["warn: " + w for w in warn]

SIM_ERR = re.compile(r"^\s*\[\d+x\]\s*(.*)$")
def sim(client, tree, lua, timeout=900, env=None):
    """run Lua in the sim; return (spci summary or None, real errors, raw)"""
    cmd = ["sp-uipreview", "run", "--client", client, "--tree", tree, "--lua", lua, "--out", "/tmp/sp-ci-%s.png" % client]
    rc, out = run(cmd, timeout=timeout, env=env)
    summary, errors, inblock = None, [], False
    for line in out.splitlines():
        if line.startswith("sim errors"):
            inblock = True
            continue
        if inblock:
            m = SIM_ERR.match(line)
            if not m:
                inblock = False
                continue
            text = m.group(1)
            text = re.sub(r"^--lua #\d+: --lua #\d+:\d+: ", "", text)
            if "SPCI|" in text:
                summary = text[text.index("SPCI|"):]
            else:
                errors.append(text)
    if "Traceback" in out or rc not in (0, 1):
        errors.append("sim run failed (rc %s): %s" % (rc, out.strip().splitlines()[-1] if out.strip() else ""))
    return summary, dedupe(errors), out

def dedupe(items):
    seen, out = {}, []
    for x in items:
        if x in seen:
            seen[x] += 1
        else:
            seen[x] = 1; out.append(x)
    return [x if seen[x] == 1 else "%s  (x%d)" % (x, seen[x]) for x in out]

def paths_from_window(tree):
    src = open(os.path.join(tree, "ShamanPower_Config/Window.lua"), encoding="utf-8", errors="replace").read()
    seen, out = set(), []
    for a, b in re.findall(r'P\("([a-z_]+)",\s*"([a-z_]+)"\)', src):
        if (a, b) not in seen:
            seen.add((a, b)); out.append((a, b))
    return out

SWEEP = r'''
local paths = %s
local opened, menus, rows, bad = 0, 0, 0, {}
local function visit(items, depth)
	if type(items) ~= "table" then return end
	for _, it in ipairs(items) do
		if type(it) == "table" then
			rows = rows + 1
			if type(it.value) == "function" then local ok, err = pcall(it.value); if not ok then bad[#bad + 1] = "value: " .. tostring(err) end end
			if type(it.sub) == "function" and depth > 0 then
				local ok, sub = pcall(it.sub)
				if ok then visit(sub, depth - 1) else bad[#bad + 1] = "sub: " .. tostring(sub) end
			end
		end
	end
end
local done = {}
for _, p in ipairs(paths) do
	local ok, err = pcall(function() ShamanPowerConfig:Open({ p[1], p[2] }) end)
	if ok then opened = opened + 1 else bad[#bad + 1] = p[2] .. ": " .. tostring(err) end
	__sim.advance(0.3)
	local function walk(f)
		if f.item and f.row and f.row.def and f:IsShown() then
			local id = tostring(f.row) .. "|" .. tostring(f.item.key)
			if not done[id] and type(f.row.def.menu) == "function" then
				done[id] = true
				local okm, items = pcall(f.row.def.menu, f.item)
				if okm then menus = menus + 1; visit(items, 2) else bad[#bad + 1] = p[2] .. " menu " .. tostring(f.item.key) .. ": " .. tostring(items) end
			end
		end
		for _, c in ipairs({ f:GetChildren() }) do walk(c) end
	end
	if ShamanPowerConfigUIFrame then walk(ShamanPowerConfigUIFrame) end
end
error("SPCI|" .. opened .. " pages, " .. menus .. " menus, " .. rows .. " rows|" .. table.concat(bad, " ;; "), 0)
'''

def step_sweep(tree, client):
    paths = paths_from_window(tree)
    lua = SWEEP % ("{ " + ", ".join('{ "%s", "%s" }' % p for p in paths) + " }")
    summary, errors, raw = sim(client, tree, lua, timeout=1200)
    detail = []
    if summary:
        parts = summary.split("|", 2)
        detail.append(parts[1])
        if len(parts) > 2 and parts[2].strip():
            errors = errors + dedupe([x.strip() for x in parts[2].split(";;") if x.strip()])
    else:
        errors.append("sweep gave no summary")
    return (not errors), detail + errors

def step_tests(tree, client, only=None):
    harness = open(os.path.join(ROOT, "harness.lua"), encoding="utf-8").read()
    results, allok = [], True
    for path in sorted(glob.glob(os.path.join(ROOT, "tests", "*.lua"))):
        name = os.path.basename(path)[:-4]
        if only and name not in only:
            continue
        src = open(path, encoding="utf-8").read()
        m = re.search(r"--\s*client:\s*(\w+)", src)
        want = m.group(1) if m else "both"
        if want not in ("both", client):
            continue
        # "-- regime: secrets": the sim's client says it has WoW: Forever's secret regime from load on
        env = dict(os.environ, SP_SIM_SECRETS="1") if re.search(r"--\s*regime:\s*secrets", src) else None
        # "-- regime: aurasounds": WoW: Forever's C_UnitAuras.AddAuraSound in the sim (the game's own aura sounds)
        if re.search(r"--\s*regime:\s*aurasounds", src):
            env = dict(env or os.environ, SP_SIM_AURASOUND="1")
        summary, errors, raw = sim(client, tree, harness + "\n" + src, env=env)
        if summary and summary.startswith("SPCI|skip|"):
            results.append("  skip  %-18s %s" % (name, summary.split("|", 2)[2]))
            continue
        if summary:
            parts = summary.split("|", 2)
            passes, fails = parts[1], [x.strip() for x in (parts[2] if len(parts) > 2 else "").split(";;") if x.strip()]
        else:
            passes, fails = "0", ["no finish(): " + (errors[0] if errors else "no output")]
            errors = errors[1:] if errors else errors
        ok = not fails and not errors
        allok = allok and ok
        results.append("  %s  %-18s %s passed%s" % ("ok  " if ok else "FAIL", name, passes, "" if ok else "; " + "; ".join(fails + errors)))
    return allok, results

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--tree", default=None)
    ap.add_argument("--client", default="both", choices=["both", "forever", "anniversary"])
    ap.add_argument("--skip-lint", action="store_true")
    ap.add_argument("--lint-base", default="main", help="git ref the lint's 'new lines' are measured against (default main)")
    ap.add_argument("--only", default=None, help="comma list of steps (syntax,endings,andor,lint,changelog,libs,sweep,tests) or test names")
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.add_argument("--release", action="store_true", help="strict: the CHANGELOG top section must match the TOC version; every library checked against its official newest")
    a = ap.parse_args()
    global RELEASE
    RELEASE = a.release
    tree = os.path.abspath(a.tree or (os.getcwd() if os.path.exists("ShamanPower.toc") else os.path.expanduser("~/git-work/ShamanPower")))
    only = set(a.only.split(",")) if a.only else None
    steps_named = {"syntax", "endings", "andor", "lint", "changelog", "libs", "sweep", "tests"}
    test_only = only and not (only & steps_named)
    clients = ["forever", "anniversary"] if a.client == "both" else [a.client]
    print("sp-ci  tree %s  clients %s" % (tree, ", ".join(clients)))
    failed, t0 = [], time.time()
    def report(name, ok, detail):
        print("%s  %s" % ("ok  " if ok else "FAIL", name))
        if detail and (not ok or a.verbose or name == "lint" or any(str(d).startswith("warn:") for d in detail)):
            for d in detail[:70]:
                if ok and not a.verbose and name != "lint" and not str(d).startswith("warn:"): continue
                print("      " + str(d))
        if not ok: failed.append(name)
    if not test_only:
        for name, fn in (("syntax", step_syntax), ("endings", step_endings), ("andor", step_andor), ("shared tables", step_shared_tables), ("share code mirror", step_share_mirror), ("changelog", step_changelog), ("libs", step_libs)):
            if only and name not in only: continue
            ok, d = fn(tree); report(name, ok, d)
        if (not only or "lint" in only) and not a.skip_lint:
            ok, d = step_lint(tree, a.lint_base); report("lint", ok, d)
    for c in clients:
        if not test_only and (not only or "sweep" in only):
            ok, d = step_sweep(tree, c); report("sweep (%s)" % c, ok, d)
        if not only or "tests" in only or test_only:
            ok, d = step_tests(tree, c, only if test_only else None)
            print("%s  tests (%s)" % ("ok  " if ok else "FAIL", c))
            for line in d: print(line)
            if not ok: failed.append("tests (%s)" % c)
    print("\n%s in %ds%s" % ("ALL GREEN" if not failed else "FAILED: " + ", ".join(failed), time.time() - t0, ""))
    sys.exit(1 if failed else 0)

if __name__ == "__main__":
    main()
