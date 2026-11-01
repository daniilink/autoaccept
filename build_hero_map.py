"""Builds heroes_map.txt for DotaAutoPick.ahk from Dota's own game files (read-only).

It reads, from game\\dota\\pak01_dir.vpk:
  scripts/npc/npc_heroes.txt            - the hero list
  scripts/npc/heroes/<hero>.txt         - primary attribute and the English name
  resource/localization/abilities_<lang>.txt - hero names per language (key "<hero>:n")
and writes ..\\heroes_map.txt:
  N|<key>|<attr S/A/I/U>|<en>|<ru>|<uk>              names of every hero
  O|<lang>|<attr>|<key>,<key>,...                    on-screen order of each attribute block,
                                                     per client language (alphabetical by the
                                                     localized name, as the game's grid is)

Run it again after a Dota update that adds heroes:  python build_hero_map.py
"""
import os, re, struct, sys, datetime

BASE = r'C:\Program Files (x86)\Steam\steamapps\common\dota 2 beta\game\dota'
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'heroes_map.txt')
LANGS = ['en', 'ru', 'uk']
LANGFILE = {'en': 'english', 'ru': 'russian', 'uk': 'ukrainian'}
ATTR = {'DOTA_ATTRIBUTE_STRENGTH': 'S', 'DOTA_ATTRIBUTE_AGILITY': 'A',
        'DOTA_ATTRIBUTE_INTELLECT': 'I', 'DOTA_ATTRIBUTE_ALL': 'U'}
ALPHA = {
    'ru': 'абвгдеёжзийклмнопрстуфхцчшщъыьэюя',
    'uk': 'абвгґдеєжзиіїйклмнопрстуфхцчшщьюя',
}


def read_vpk(wanted_exact, wanted_prefix):
    """Returns {path: bytes} for the exact paths and for every path under the prefixes."""
    f = open(os.path.join(BASE, 'pak01_dir.vpk'), 'rb')
    sig, ver = struct.unpack('<II', f.read(8))
    assert sig == 0x55AA1234 and ver == 2, 'unexpected VPK header'
    tree_size = struct.unpack('<IIIII', f.read(20))[0]
    tree = f.read(tree_size)
    data_off = 28 + tree_size

    def cstr(pos):
        e = tree.index(b'\0', pos)
        return tree[pos:e].decode('utf-8', 'replace'), e + 1

    found = {}
    pos = 0
    while True:
        ext, pos = cstr(pos)
        if ext == '':
            break
        while True:
            path, pos = cstr(pos)
            if path == '':
                break
            while True:
                name, pos = cstr(pos)
                if name == '':
                    break
                crc, pre, arch, off, length, term = struct.unpack_from('<IHHIIH', tree, pos)
                pos += 18
                preload = tree[pos:pos + pre]
                pos += pre
                full = (path + '/' if path != ' ' else '') + name + '.' + ext
                if full in wanted_exact or any(full.startswith(p) for p in wanted_prefix):
                    found[full] = (arch, off, length, preload)
    out = {}
    for full, (arch, off, length, preload) in found.items():
        if arch == 0x7FFF:
            f.seek(data_off + off)
            body = f.read(length)
        else:
            with open(os.path.join(BASE, 'pak01_%03d.vpk' % arch), 'rb') as a:
                a.seek(off)
                body = a.read(length)
        out[full] = preload + body
    return out


def collate_key(name, lang):
    s = name.lower()
    if lang in ALPHA:
        order = ALPHA[lang]
        key = []
        for ch in s:
            if ch in order:
                key.append((1, order.index(ch)))
            elif ch.isalpha():
                key.append((2, ord(ch)))
            else:
                key.append((0, ord(ch)))      # space, hyphen, apostrophe sort first
        return key
    return [(0 if not ch.isalnum() else 1, ord(ch)) for ch in s]


def main():
    files = read_vpk(
        {'scripts/npc/npc_heroes.txt'} | {'resource/localization/abilities_%s.txt' % LANGFILE[l] for l in LANGS},
        ['scripts/npc/heroes/'])
    order = re.findall(r'#base "heroes/(npc_dota_hero_[a-z_0-9]+)\.txt"',
                       files['scripts/npc/npc_heroes.txt'].decode('utf-8', 'replace'))
    order = [o for o in order if o != 'npc_dota_hero_base']
    loc = {l: files['resource/localization/abilities_%s.txt' % LANGFILE[l]].decode('utf-8', 'replace') for l in LANGS}

    def lname(key, lang):
        m = re.search(r'"%s:n"\s+"([^"]+)"' % re.escape(key), loc[lang])
        if not m:
            return None
        return re.sub(r'^#\|[a-z]+\|#', '', m.group(1))   # drop the gender marker "#|m|#"

    heroes = []
    for k in order:
        t = files.get('scripts/npc/heroes/%s.txt' % k, b'').decode('utf-8', 'replace')
        a = re.search(r'"AttributePrimary"\s+"([A-Z_]+)"', t)
        wn = re.search(r'"workshop_guide_name"\s+"([^"]+)"', t)
        if not a or not wn or k == 'npc_dota_hero_target_dummy':
            continue
        names = {}
        for l in LANGS:
            names[l] = lname(k, l) or (wn.group(1) if l == 'en' else None)
        names['en'] = names['en'] or wn.group(1)
        for l in LANGS:
            if not names[l]:
                print('warning: no %s name for %s, using English' % (l, k))
                names[l] = names['en']
        heroes.append({'key': k, 'attr': ATTR[a.group(1)], 'names': names})

    lines = ['# generated by tools/build_hero_map.py on %s from Dota game files; %d heroes'
             % (datetime.date.today().isoformat(), len(heroes))]
    for h in heroes:
        lines.append('N|%s|%s|%s|%s|%s' % (h['key'], h['attr'], h['names']['en'], h['names']['ru'], h['names']['uk']))
    for l in LANGS:
        for attr in 'SAIU':
            blk = [h for h in heroes if h['attr'] == attr]
            blk.sort(key=lambda h: collate_key(h['names'][l], l))
            lines.append('O|%s|%s|%s' % (l, attr, ','.join(h['key'] for h in blk)))
    open(OUT, 'wb').write(('\n'.join(lines) + '\n').encode('utf-8'))
    print('written', os.path.abspath(OUT), len(heroes), 'heroes')
    for l in LANGS:
        for attr in 'SAIU':
            n = sum(1 for h in heroes if h['attr'] == attr)
            print(' ', l, attr, n)


if __name__ == '__main__':
    main()
