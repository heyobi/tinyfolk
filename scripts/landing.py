"""GitHub Pages landing page (docs/index.html) for Tinyfolk, from heyobi/querly scripts/landing-pages.py. Usage: python -X utf8 scripts/landing.py"""
import html, json

BADGE = 'app-store-badge.svg'

CSS = """
:root{--bg:#f4f7fb;--fg:#0c1426;--muted:#56637a;--card:#e8eef7;--line:#d5deeb;--accent:#0b7fae}
@media (prefers-color-scheme:dark){:root{--bg:#05070e;--fg:#eef4ff;--muted:#9aa8c0;--card:#0e1424;--line:#1c2840;--accent:#6fd3ff}}
h1,h2{font-weight:700}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:17px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
main{max-width:1040px;margin:0 auto;padding:40px 16px 64px}
header{text-align:center}header img.icon{width:112px;height:112px;border-radius:24px;box-shadow:0 10px 30px rgba(0,0,0,.18)}
h1{font-size:clamp(30px,5vw,46px);line-height:1.15;margin:18px 0 10px;letter-spacing:-.02em}
.lead{font-size:clamp(17px,2.2vw,20px);color:var(--muted);max-width:720px;margin:0 auto 22px}
.badge img{height:54px}
.shots{display:flex;gap:14px;overflow-x:auto;padding:28px 0 8px;scroll-snap-type:x mandatory}
.shots img{height:min(560px,70vh);border-radius:18px;scroll-snap-align:center;flex:none;box-shadow:0 8px 24px rgba(0,0,0,.15)}
h2{font-size:28px;margin:48px 0 12px;letter-spacing:-.01em}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:14px}
.card{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:18px}
.card b{display:block;margin-bottom:4px}
details{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:14px 18px;margin:10px 0}
summary{font-weight:600;cursor:pointer}
a{color:var(--accent)}code{font:15px ui-monospace,Menlo,monospace;background:var(--card);padding:1px 6px;border-radius:6px}
.wide img{width:100%;border-radius:18px;box-shadow:0 8px 24px rgba(0,0,0,.15)}
footer{color:var(--muted);font-size:14px;margin-top:56px;text-align:center}
"""


def page(app):
    faq_ld = {"@context": "https://schema.org", "@type": "FAQPage", "mainEntity": [
        {"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in app['faq']]}
    app_ld = {"@context": "https://schema.org", "@type": "SoftwareApplication", "name": app['name'],
              "operatingSystem": "iOS, iPadOS", "applicationCategory": app['category'],
              "description": app['description'], "url": app['store'], "downloadUrl": app['store'],
              "image": app['site'] + 'icon.png', "screenshot": [app['site'] + s for s, _ in app['shots']],
              "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
              "author": {"@type": "Person", "name": "heyobi", "url": "https://github.com/heyobi"}}
    e = html.escape
    shots = '\n'.join(f'    <img src="{s}" alt="{e(alt)}" loading="lazy">' for s, alt in app['shots'])
    feats = '\n'.join(f'    <div class="card"><b>{e(t)}</b>{e(d)}</div>' for t, d in app['features'])
    faq = '\n'.join(f'  <details><summary>{e(q)}</summary><p>{e(a)}</p></details>' for q, a in app['faq'])
    extra = app.get('extra', '')
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{e(app['title'])}</title>
<meta name="description" content="{e(app['description'])}">
<meta name="keywords" content="{e(app['keywords'])}">
<link rel="canonical" href="{app['site']}">
<link rel="icon" href="icon.png">
<meta name="apple-itunes-app" content="app-id={app['id']}">
<meta property="og:type" content="website">
<meta property="og:title" content="{e(app['title'])}">
<meta property="og:description" content="{e(app['description'])}">
<meta property="og:url" content="{app['site']}">
<meta property="og:image" content="{app['site']}{app['shots'][0][0]}">
<meta name="twitter:card" content="summary_large_image">
<script type="application/ld+json">{json.dumps(app_ld, ensure_ascii=False)}</script>
<script type="application/ld+json">{json.dumps(faq_ld, ensure_ascii=False)}</script>
<style>{CSS}</style>
</head>
<body>
<main>
<header>
  <img class="icon" src="icon.png" alt="{e(app['name'])} app icon" width="112" height="112">
  <h1>{e(app['h1'])}</h1>
  <p class="lead">{e(app['lead'])}</p>
  <a class="badge" href="{app['store']}"><img src="{BADGE}" alt="Download {e(app['name'])} on the App Store"></a>
</header>
<div class="shots">
{shots}
</div>
<h2>{e(app['features_title'])}</h2>
<div class="grid">
{feats}
</div>
{extra}
<h2>Questions</h2>
{faq}
<footer>
  <p><a href="{app['store']}">{e(app['name'])} on the App Store</a> · <a href="{app['repo']}">Source code on GitHub</a> · {app['sibling']}</p>
  <p>{e(app['legal'])}</p>
</footer>
</main>
</body>
</html>
"""


import os
APP_ID = os.environ.get('APP_ID', '0000000000')

tinyfolk_app = dict(
    id=APP_ID, name='Tinyfolk', category='EntertainmentApplication',
    store=f'https://apps.apple.com/app/id{APP_ID}',
    site='https://heyobi.github.io/tinyfolk/', repo='https://github.com/heyobi/tinyfolk',
    title='Tinyfolk: a head-tracked 3D pocket hologram for iPhone Duo, iPhone and iPad',
    h1='A pocket hologram for iPhone Duo',
    lead='Stand iPhone Duo half open like a tiny laptop and a little 3D friend appears on the fold. Tinyfolk follows your eyes with the front camera and draws the scene from exactly your point of view, so the character seems to stand right there in front of you. Open it flat for a surprise. On every iPhone and iPad, the screen becomes a window into a little box.',
    description='A head-tracked 3D hologram app made for iPhone Duo: a tiny original character stands on the fold, follows your eyes and waves at newcomers. Off-axis 3D from the live hinge angle, a lantern well when opened flat, live instrumental music. Free, private, no ads.',
    keywords='hologram app iPhone, iPhone Duo hologram, 3D hologram app, head tracking 3D, pocket hologram, off-axis projection iPhone, parallax 3D app, iPhone Duo apps, desk toy app, 3D character app',
    shots=[('screens/duo-1-stage.jpg', 'iPhone Duo half open: a small robot stands on the fold in 3D'),
           ('screens/duo-2-two.jpg', 'The character turns to wave at a second person'),
           ('screens/duo-3-dance.jpg', 'Odette dances on the Night Rooftop'),
           ('screens/duo-5-well.jpg', 'Opened flat: a lantern well beneath the glass'),
           ('screens/iphone-1-box.jpg', 'Tinyfolk on iPhone: a window into a little box'),
           ('screens/ipad-1-box.jpg', 'Tinyfolk on iPad')],
    features_title='The phone becomes a tiny stage',
    features=[('Real 3D, no glasses', 'Each half of iPhone Duo is drawn with its own off-axis projection from your eye, using the live hinge angle. The floor looks flat, the character looks solid.'),
              ('Follows your eyes', 'The front camera finds where you are. Frames are analysed on the device and dropped at once.'),
              ('Notices both of you', 'It looks at whoever is looking, turns between two people and waves when someone new arrives.'),
              ('Open it flat', 'The floor gives way into a lantern well. Lanterns rise and knock on the glass from below, and you feel each knock.'),
              ('Eight original friends', 'A ceramic robot, a fox, a leaf sprite, a wooden dancer and more, each with a dance of their own.'),
              ('Live music', 'Instrumental pieces played by a small synthesizer on the device. The cast dances on the beat.'),
              ('Every iPhone and iPad', 'Without a fold, the screen is a window into a little diorama box.'),
              ('Fair', 'Free with no ads or account. One optional purchase for more friends, stages, music and recording.')],
    faq=[('Is there a hologram app for iPhone Duo?', 'Tinyfolk stands a tiny 3D character on the fold of a half-open iPhone Duo and draws both halves from your point of view with head tracking, so it looks like a small hologram on your desk.'),
         ('How does the 3D effect work without glasses?', 'The front camera estimates where your eyes are. Each half of the display is rendered with an asymmetric (off-axis) frustum from that point, so the virtual scene stays fixed in space as you move your head.'),
         ('Can two people watch at once?', 'A flat screen can only be exactly right for one eye point, so the view follows one person at a time and hands over smoothly. The character notices both and turns between them.'),
         ('Does Tinyfolk work on other iPhones and iPad?', 'Yes. The screen becomes a window into a little box; lay it flat to look down into a well. Tilting the phone gives depth even without the camera.'),
         ('Does Tinyfolk record or upload my face?', 'No. Camera frames are analysed on the device and discarded immediately. Nothing is stored or sent. Head tracking is optional.'),
         ('What does Tinyfolk Pro add?', 'Four more friends, three more stages, four more pieces of music and screen recording, for one payment shared with your family. No subscription.')],
    sibling='<a href="https://heyobi.github.io/pleats/">Pleats: an accordion for iPhone Duo</a>',
    legal='iPhone and iPhone Duo are trademarks of Apple Inc. Characters and original music by heyobi; traditional tunes are public domain.',
)

import os
out = os.path.join(os.path.dirname(__file__), '..', 'docs', 'index.html')
open(out, 'w', encoding='utf-8').write(page(tinyfolk_app))
print('ok')
