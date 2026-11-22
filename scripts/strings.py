# Builds Tinyfolk/Localizable.xcstrings from scripts/i18n: keysN.json (English source) and <lang>N.json (same order).
# Song titles are proper names and are not localized.
# Usage: python -X utf8 scripts/strings.py
import json, os
D = os.path.join(os.path.dirname(__file__), 'i18n')
LANGS = ['tr', 'es', 'pt-BR', 'de']
strings = {}
import glob
parts = sorted(int(os.path.basename(p)[4:-5]) for p in glob.glob(os.path.join(D, "keys*.json")))
for part in parts:
    keys = json.load(open(os.path.join(D, f'keys{part}.json'), encoding='utf-8'))
    for lang in LANGS:
        vals = json.load(open(os.path.join(D, f'{lang}{part}.json'), encoding='utf-8'))
        assert len(vals) == len(keys), f'{lang}{part}: {len(vals)} values for {len(keys)} keys'
        for k, v in zip(keys, vals):
            assert k.count('%') == v.count('%'), f'{lang}: placeholder mismatch in {k!r}'
            strings.setdefault(k, {"localizations": {}})["localizations"][lang] = {
                "stringUnit": {"state": "translated", "value": v}}
cat = {"sourceLanguage": "en", "strings": dict(sorted(strings.items())), "version": "1.0"}
out = os.path.join(os.path.dirname(__file__), '..', 'Tinyfolk', 'Localizable.xcstrings')
json.dump(cat, open(out, 'w', encoding='utf-8', newline='\n'), ensure_ascii=False, indent=2)
print(f'{len(strings)} strings x {len(LANGS)} languages')
