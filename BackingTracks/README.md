# Bundled backing tracks

The public repo bundles no backing tracks: the recording used during development isn't ours to
share. Add your own here (audio you made or have the rights to), and the packaged app will ship it.

Everything here ships inside the packaged app and is added to each user's backing-track
library on launch. Same layout as the library, plus the audio:

```
BackingTracks/
  tracks/<uuid>.backing.json
  links.json
  <audio file named in each track's audioPath>.m4a
```

To ship tracks you've set up in PianoPad, from the repo root:

```sh
cp -R ~/Library/Application\ Support/PianoPad/Backing\ Tracks/. BackingTracks/
cp "/path/to/your track.m4a" BackingTracks/
```

Links to book passages carry over as is. Links to MIDI files move onto the bundled file of the
same name in Examples/, so link backing tracks to the example MIDI files, not copies elsewhere.
A track the user already has (same id) is never overwritten.
