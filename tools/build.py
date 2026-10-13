#!/usr/bin/env python3
# KediRay release dosyaları üreticisi (yalnızca Python standart kütüphanesi)
#
# Copyright (C) 2026 Şaban Vurgun
# SPDX-License-Identifier: GPL-3.0-or-later
"""Kaynak ağacından release dosyalarını üretir. Tek kaynak: depodaki klasörler ve VERSION.

Çıktı (varsayılan: dist/):
  kediray-install.sh      tek dosya kurulum (tools/installer/install.sh.in + ağaçtaki dosyalar, sürüm VERSION'dan)
  kediray-all.tar.gz      mimariden bağımsız paket: modeme kopyalanacak dosya ağacı (files/), ilk açılış betiği, paket listesi
  kediray-src.tar.gz      kaynak ağacı (git'in izlediği dosyalar)
  sha256sums              yukarıdakilerin SHA256 toplamları (sha256sum -c sha256sums)

Kullanım:
  python3 tools/build.py [--out dist] [--root <depo>]     (ya da: ./build.sh)

Aynı girdiden her çalıştırmada birebir aynı dosyalar çıkar (sıralı, sabit zaman damgası, root sahipli, sabit gzip başlığı).
Üretimden sonra kendini doğrular; bir şey tutmazsa hata koduyla çıkar.
"""
import argparse
import gzip
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

MARK = re.compile(r'^@@KR_FILE (.+)@@$')
HEREDOC = re.compile(r"^cat > '([^']+)' <<'(KEDIRAY_EOF_\d+)'$")
ASSETS = ('kediray-install.sh', 'kediray-all.tar.gz', 'kediray-src.tar.gz')

# Ağaçtaki klasör → modemdeki yol. (Kurulum betiği bunların hepsini yazar; EXTRA yalnızca pakette olur.)
TREES = ('package/kediray/files', 'package/aw1k-panel/files', 'luci-app-kediray/htdocs', 'luci-app-kediray/root')
EXTRA = {'package/kediray/files/etc/uci-defaults/99-kediray'}   # ilk açılış betiği: yalnızca firmware paketinde
EXEC = {
    '/usr/bin/kediray', '/usr/bin/aw1k-usage', '/usr/libexec/rpcd/aw1k', '/etc/init.d/kediray',
    '/etc/hotplug.d/iface/80-kediray', '/etc/hotplug.d/firewall/99-kediray', '/etc/uci-defaults/99-kediray',
}
PRIVATE = {'/etc/config/kediray'}
FALLBACK_EPOCH = 1704067200  # 2024-01-01; git ve SOURCE_DATE_EPOCH yoksa


def die(msg):
    print('HATA: ' + msg, file=sys.stderr)
    sys.exit(1)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def rd(path):
    return Path(path).read_bytes().decode('utf-8')


def tree_path(rel):
    """Ağaçtaki dosyanın modemdeki yolu."""
    p = rel.split('/')
    if p[0] == 'package' and p[2] == 'files':
        return '/' + '/'.join(p[3:])
    if p[0] == 'luci-app-kediray' and p[1] == 'htdocs':
        return '/www/' + '/'.join(p[2:])
    if p[0] == 'luci-app-kediray' and p[1] == 'root':
        return '/' + '/'.join(p[2:])
    die('bilinmeyen ağaç yolu: ' + rel)


def tree_files(root):
    out = {}
    for t in TREES:
        base = root / t
        if not base.is_dir():
            die('klasör yok: ' + t)
        for f in sorted(base.rglob('*')):
            if f.is_file():
                out[f.relative_to(root).as_posix()] = tree_path(f.relative_to(root).as_posix())
    return out


def read_map(root):
    rows = []
    for n, line in enumerate(rd(root / 'tools' / 'installer' / 'files.map').split('\n'), 1):
        if not line.strip() or line.startswith('#'):
            continue
        parts = line.split('\t')
        if len(parts) != 3 or not re.fullmatch(r'KEDIRAY_EOF_\d+', parts[2]):
            die('tools/installer/files.map:%d biçimi bozuk' % n)
        rows.append(tuple(parts))
    if len({r[0] for r in rows}) != len(rows) or len({r[2] for r in rows}) != len(rows):
        die('tools/installer/files.map: aynı kaynak ya da işaret iki kez geçiyor')
    return rows


def check_tree(root, tf, rows):
    """Ağaçtaki her dosya haritada (ya da EXTRA'da) olmalı ve tersi; modemdeki yollar tutmalı."""
    mapped = {r[0] for r in rows}
    tree = set(tf)
    miss = sorted(tree - mapped - EXTRA)
    gone = sorted(mapped - tree)
    if miss:
        die('ağaçta olup tools/installer/files.map\'te olmayan dosya (kurulum betiğine girmez): ' + ', '.join(miss))
    if gone:
        die('tools/installer/files.map\'te olup ağaçta olmayan dosya: ' + ', '.join(gone))
    for s, p, _ in rows:
        norm = '/etc/config/kediray' if p == '/tmp/kediray.default' else p
        if tf[s] != norm:
            die('%s: haritadaki yol (%s) ağaçtaki yolla (%s) uyuşmuyor' % (s, p, tf[s]))


def generate_installer(root, ver, rows):
    skel = rd(root / 'tools' / 'installer' / 'install.sh.in').replace('@VERSION@', ver)
    by_src = {s: (p, d) for s, p, d in rows}
    used, out = set(), []
    for line in skel.split('\n'):
        m = MARK.match(line)
        if not m:
            out.append(line)
            continue
        s = m.group(1)
        if s not in by_src:
            die('iskelette olup tools/installer/files.map\'te olmayan işaret: ' + s)
        p, d = by_src[s]
        used.add(s)
        out.append("cat > '%s' <<'%s'\n%s%s" % (p, d, rd(root / s), d))
    left = sorted(set(by_src) - used)
    if left:
        die('tools/installer/files.map\'te olup iskelette işareti olmayan dosya: ' + ', '.join(left))
    text = '\n'.join(out)
    if '@@KR_FILE' in text:
        die('üretilen kurulum betiğinde çözülmemiş işaret kaldı')
    return text


def heredocs(text):
    lines = text.split('\n')
    out, i = [], 0
    while i < len(lines):
        m = HEREDOC.match(lines[i])
        if not m:
            i += 1
            continue
        path, delim = m.groups()
        j = i + 1
        while j < len(lines) and lines[j] != delim:
            j += 1
        if j >= len(lines):
            die('%s: bitiş işareti %s yok' % (path, delim))
        body = lines[i + 1:j]
        out.append((path, delim, ('\n'.join(body) + '\n') if body else ''))
        i = j + 1
    return out


def kit_body(kpath, body):
    # Kurulum betiği menüyü sonda sed ile admin/vpn altına taşır; paket bunu baştan hazır taşır
    if '/menu.d/' in kpath and kpath.endswith('luci-app-kediray.json'):
        body = body.replace('admin/services/kediray', 'admin/vpn/kediray')
    return body


def mode_of(kpath):
    if kpath in EXEC:
        return 0o755
    if kpath in PRIVATE:
        return 0o600
    return 0o644


def source_epoch(root):
    env = os.environ.get('SOURCE_DATE_EPOCH')
    if env and env.isdigit():
        return int(env)
    try:
        r = subprocess.run(['git', '-C', str(root), 'log', '-1', '--format=%ct'], capture_output=True, text=True, timeout=20)
        if r.returncode == 0 and r.stdout.strip().isdigit():
            return int(r.stdout.strip())
    except (OSError, subprocess.SubprocessError):
        pass
    return FALLBACK_EPOCH


def tracked_files(root):
    try:
        r = subprocess.run(['git', '-C', str(root), 'ls-files', '-z'], capture_output=True, timeout=30)
        if r.returncode == 0 and r.stdout:
            return sorted(x for x in r.stdout.decode('utf-8').split('\0') if x and (root / x).is_file())
    except (OSError, subprocess.SubprocessError):
        pass
    return sorted(p.relative_to(root).as_posix() for p in root.rglob('*')
                  if p.is_file() and '.git' not in p.parts and 'dist' not in p.relative_to(root).parts)


def write_tar(path, entries, mtime):
    names = {}
    for arc, (data, mode) in entries.items():
        names[arc] = (data, mode, False)
        parts = arc.split('/')[:-1]
        for k in range(1, len(parts) + 1):
            names.setdefault('/'.join(parts[:k]), (b'', 0o755, True))
    with open(path, 'wb') as raw:
        with gzip.GzipFile(filename='', mode='wb', fileobj=raw, compresslevel=9, mtime=0) as gz:
            with tarfile.open(fileobj=gz, mode='w', format=tarfile.GNU_FORMAT) as tf:
                for arc in sorted(names):
                    data, mode, is_dir = names[arc]
                    ti = tarfile.TarInfo(arc)
                    ti.mode, ti.mtime, ti.uid, ti.gid = mode, mtime, 0, 0
                    ti.uname = ti.gname = 'root'
                    if is_dir:
                        ti.type = tarfile.DIRTYPE
                        tf.addfile(ti)
                    else:
                        ti.size = len(data)
                        tf.addfile(ti, io.BytesIO(data))


def build_all(root, ver, tf):
    top = 'kediray-all-' + ver
    e = {}

    def add(arc, data, mode):
        if arc in e:
            die('pakette iki kez: ' + arc)
        e[arc] = (data, mode)

    for rel, kp in tf.items():
        body = kit_body(kp, rd(root / rel))
        add('%s/files%s' % (top, kp), body.encode('utf-8'), mode_of(kp))
    add(top + '/files/usr/share/kediray/version', (ver + '\n').encode('utf-8'), 0o644)
    tpl = root / 'tools' / 'pkg-all'
    for name in ('README.md', 'NOTICE', 'packages.txt'):
        add('%s/%s' % (top, name), rd(tpl / name).replace('@VERSION@', ver).encode('utf-8'), 0o644)
    add(top + '/LICENSE', (root / 'LICENSE').read_bytes(), 0o644)
    add(top + '/README-KediRay.md', (root / 'README.md').read_bytes(), 0o644)
    docs = root / 'docs'
    if docs.is_dir():
        for f in sorted(docs.rglob('*')):
            if f.is_file():
                add('%s/docs/%s' % (top, f.relative_to(docs).as_posix()), f.read_bytes(), 0o644)
    return top, e


def build_src(root, ver):
    top = 'kediray-src-' + ver
    e = {}
    for rel in tracked_files(root):
        p = root / rel
        e['%s/%s' % (top, rel)] = (p.read_bytes(), 0o755 if os.stat(p).st_mode & 0o111 else 0o644)
    return top, e


def verify(root, out, ver, installer, rows, tf):
    ok = True

    def check(cond, label):
        nonlocal ok
        print('  %s %s' % ('✔' if cond else '✘', label))
        if not cond:
            ok = False

    # 1) sha256sums
    sums = {}
    for line in (out / 'sha256sums').read_text(encoding='utf-8').splitlines():
        h, _, name = line.partition('  ')
        sums[name] = h
    check(set(sums) == set(ASSETS), 'sha256sums üç dosyayı da kapsıyor')
    for name, h in sums.items():
        check(sha256((out / name).read_bytes()) == h, 'SHA256 tutuyor: ' + name)

    # 2) kurulum betiği
    gen = (out / 'kediray-install.sh').read_bytes().decode('utf-8')
    check(gen == installer, 'dist/kediray-install.sh üretilenle aynı')
    check('@VERSION@' not in gen and '@@KR_FILE' not in gen, 'çözülmemiş işaret yok')
    check(re.search(r'^KR_VERSION="%s"$' % re.escape(ver), gen, re.M) is not None
          and re.search(r'^#\s+KediRay %s\s' % re.escape(ver), '\n'.join(gen.split('\n')[:8]), re.M) is not None,
          'başlık yorumu ve KR_VERSION = ' + ver)
    sh, node = shutil.which('sh'), shutil.which('node')
    if sh:
        with tempfile.TemporaryDirectory() as td:
            f = Path(td) / 'i.sh'
            f.write_bytes(gen.encode('utf-8'))
            r = subprocess.run([sh, '-n', str(f)], capture_output=True, text=True)
            check(r.returncode == 0, 'sh -n: kediray-install.sh' + ('' if r.returncode == 0 else ' ' + r.stderr.strip()[:200]))
    # betiğin yazdığı dosyalar ağaçtakilerle aynı mı
    hd = {(p, d): body for p, d, body in heredocs(gen)}
    bad = [s for s, p, d in rows if hd.get((p, d)) != rd(root / s)]
    check(len(hd) == len(rows) and not bad, '%d gömülü dosya ağaçtakiyle birebir aynı%s' % (len(rows), (': ' + ', '.join(bad)) if bad else ''))

    # 3) kediray-all
    top = 'kediray-all-' + ver
    with tarfile.open(out / 'kediray-all.tar.gz', 'r:gz') as t:
        members = {m.name: m for m in t.getmembers()}
        check(not [n for n in members if n.startswith('/') or '..' in n.split('/')], 'kediray-all: mutlak yol / ".." yok')
        check(all(m.uid == 0 and m.gid == 0 for m in members.values()), 'kediray-all: tüm dosyalar root sahipli')
        diff = []
        for rel, kp in tf.items():
            m = members.get('%s/files%s' % (top, kp))
            if m is None:
                diff.append(kp + ' (yok)')
                continue
            if t.extractfile(m).read() != kit_body(kp, rd(root / rel)).encode('utf-8'):
                diff.append(kp + ' (içerik)')
            if (m.mode & 0o777) != mode_of(kp):
                diff.append(kp + ' (izin)')
        check(not diff, 'kediray-all: %d dosya ağaçtakiyle aynı (içerik + izin)%s' % (len(tf), (': ' + ', '.join(diff)) if diff else ''))
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            for name, m in members.items():
                if not m.isfile() or '/files/' not in name:
                    continue
                body = t.extractfile(m).read()
                f = td / name.replace('/', '__')
                f.write_bytes(body)
                short = name.split('/files', 1)[1]
                if body.startswith(b'#!/bin/sh') and sh:
                    r = subprocess.run([sh, '-n', str(f)], capture_output=True, text=True)
                    check(r.returncode == 0, 'sh -n: ' + short)
                elif name.endswith('.js') and node:
                    c = f.with_suffix('.cjs')
                    f.rename(c)
                    r = subprocess.run([node, '--check', str(c)], capture_output=True, text=True)
                    check(r.returncode == 0, 'node --check: ' + short + ('' if r.returncode == 0 else ' ' + r.stderr.strip()[:200]))
                elif name.endswith('.json'):
                    try:
                        json.loads(body.decode('utf-8'))
                        check(True, 'JSON geçerli: ' + short)
                    except ValueError as ex:
                        check(False, 'JSON bozuk: %s (%s)' % (short, ex))
    if not sh:
        print('  ! sh yok: kabuk söz dizimi denetlenmedi')
    if not node:
        print('  ! node yok: JavaScript söz dizimi denetlenmedi')

    # 4) kediray-src
    stop = 'kediray-src-' + ver
    with tarfile.open(out / 'kediray-src.tar.gz', 'r:gz') as t:
        names = {n[len(stop) + 1:] for n in t.getnames() if n.startswith(stop + '/') and n != stop}
    want = set(tracked_files(root))
    check(want <= names and 'tools/installer/install.sh.in' in names, 'kediray-src: izlenen %d dosyanın hepsi var' % len(want))

    # 5) eski güncelleme düğmesi için kökteki kopya (geçiş dönemi): varsa güncel olmalı
    legacy = root / 'kediray-install.sh'
    if legacy.is_file():
        check(legacy.read_bytes().decode('utf-8') == gen, 'kökteki kediray-install.sh (eski düğme için) üretilenle aynı')
        s = root / 'kediray-install.sh.sha256'
        check(s.is_file() and s.read_text(encoding='utf-8').split()[:1] == [sha256(gen.encode('utf-8'))], 'kökteki kediray-install.sh.sha256 güncel')
        check((root / 'VERSION').read_text(encoding='utf-8').strip() == ver, 'VERSION = ' + ver)
    return ok


def main():
    ap = argparse.ArgumentParser(description='KediRay release dosyalarını üretir ve doğrular')
    ap.add_argument('--root', default=str(Path(__file__).resolve().parent.parent), help='depo dizini (varsayılan: betiğin üst dizini)')
    ap.add_argument('--out', default=None, help='çıktı dizini (varsayılan: <depo>/dist)')
    args = ap.parse_args()
    root = Path(args.root).resolve()
    out = Path(args.out).resolve() if args.out else root / 'dist'

    ver = rd(root / 'VERSION').strip()
    if not re.fullmatch(r'\d+\.\d+\.\d+', ver):
        die('VERSION biçimi bozuk: %r' % ver)
    rows = read_map(root)
    tf = tree_files(root)
    check_tree(root, tf, rows)
    installer = generate_installer(root, ver, rows)
    if len(rows) < 10:
        die('tools/installer/files.map çok kısa')

    out.mkdir(parents=True, exist_ok=True)
    for n in ASSETS + ('sha256sums',):
        if (out / n).exists():
            (out / n).unlink()
    (out / 'kediray-install.sh').write_bytes(installer.encode('utf-8'))
    mt = source_epoch(root)
    _, all_e = build_all(root, ver, tf)
    write_tar(out / 'kediray-all.tar.gz', all_e, mt)
    _, src_e = build_src(root, ver)
    write_tar(out / 'kediray-src.tar.gz', src_e, mt)
    (out / 'sha256sums').write_text(''.join('%s  %s\n' % (sha256((out / n).read_bytes()), n) for n in sorted(ASSETS)), encoding='utf-8')

    print('KediRay %s → %s' % (ver, out))
    for n in ASSETS + ('sha256sums',):
        print('  %-22s %9.1f KB' % (n, (out / n).stat().st_size / 1024))
    print('Doğrulama:')
    if not verify(root, out, ver, installer, rows, tf):
        die('doğrulama başarısız')
    print('Tamam.')


if __name__ == '__main__':
    main()
