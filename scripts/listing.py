# Merges store/listing/<locale>.json into store/listing.json and checks App Store limits.
# Usage: python -X utf8 scripts/listing.py
import json, glob, os
LIM = dict(name=30, subtitle=30, keywords=100, promo=170, description=4000)
out = {}
ok = True
for f in sorted(glob.glob(os.path.join(os.path.dirname(__file__), '..', 'store', 'listing', '*.json'))):
    loc = os.path.basename(f)[:-5]
    d = json.load(open(f, encoding='utf-8'))
    for k, n in LIM.items():
        if len(d[k]) > n:
            ok = False
            print(f'{loc} {k}: {len(d[k])} > {n}')
    print(loc, {k: len(d[k]) for k in LIM})
    out[loc] = d
json.dump(out, open(os.path.join(os.path.dirname(__file__), '..', 'store', 'listing.json'), 'w', encoding='utf-8', newline='\n'), ensure_ascii=False, indent=2)
print('OK' if ok else 'LIMITS EXCEEDED')
