# Tinyfolk launch posts (drafts, not posted)

## Plan

- No public TestFlight. The app is free to download (try first, buy Pro only if you like it), so the App Store
  version is the "open test", and a public TestFlight link needs its own Beta App Review and splits the first
  ratings. Post once 1.0 is live, with the App Store link.
- Where: r/iPhoneDuo first (the "Pocket Hologram" video that inspired this got 3.3K upvotes there). A day later,
  if it does well: r/iOSapps (Saturday self-promotion thread rules apply) and r/SideProject.
- The video matters more than the text. A screen recording cannot show the effect, because the 3D only works from
  the viewer's eye. Film the half-open Duo with a second phone held at eye height, moving slowly left and right
  (the phone's camera becomes the "eye"; turn on head tracking and keep your face out of shot, or film with the
  simulated viewer from Settings → tap Version 5 times → Simulate viewers). 15–25 seconds:
  1. Half open, Pim waves; slow arc around it so it looks solid.
  2. A second person leans in; Pim turns and waves.
  3. Open the phone flat: the floor gives way, the lantern well.
- Reply to every comment in the first two hours. Don't ask for upvotes or reviews.

## r/iPhoneDuo

**Title:** I made a pocket hologram for iPhone Duo: a tiny 3D friend that stands on the fold and follows your eyes

**Body:**

Inspired by the "Pocket Hologram" video here a few weeks ago, I built a native app that does it for real.

Stand your Duo half open like a tiny laptop. The upper half becomes a back wall, the lower half a floor, and a
little character stands right on the fold. The front camera finds where your eyes are, and each half is drawn with
its own off-axis projection from your eye using the live hinge angle, so the floor stays flat and the character
looks solid as you move your head around it.

A few things I'm happy with:

- Open the phone all the way flat and the floor gives way: your friend falls into a lantern well under the glass,
  and the lanterns knock on the glass from below (you feel each knock).
- It notices two people: it looks at whoever is looking and waves when someone new leans in. The 3D view can only
  be right for one person at a time, so it follows one viewer and hands over smoothly.
- Eight original characters, six stages, and instrumental music played live by a small synth on the phone.
- Works on regular iPhones and iPad too, as a window into a little box.

Camera frames are analysed on the device and thrown away; no account, no ads, no tracking. It's free; one optional
purchase unlocks more characters and stages.

App Store: <link>

Happy to answer questions about the off-axis rendering or the hinge API. Feedback very welcome, especially from
anyone with a Duo in a dim room (that's where face tracking struggles most).
