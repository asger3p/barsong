# Barsong

Spotify in your Mac's menu bar: the cover and the song up top, a one-click like, a player a click away, synced lyrics under the notch, and studio-style analysis of what you're hearing.

Barsong is an independent project, not affiliated with or endorsed by Spotify.

![The menu bar item with the cover, song and like button, and synced lyrics floating underneath](docs/screenshots/menu-bar-and-lyrics.png)

## Features

**Menu bar**
- The album cover and "Artist – Title" (or "Title – Artist", title only, or just the cover). A pause badge shows while paused.
- One click on **+** adds the song to Liked Songs; the check mark removes it.
- A lyrics button turns the floating lyrics on.
- Optional pill background, plain or tinted with the cover's colours.

**Player**
- Play/pause, previous, next, shuffle, repeat, a scrubber, and Spotify's own volume.
- Click the title or cover to open the song in Spotify, and the artist or album to open those.
- A copy button puts the song's open.spotify.com link on your clipboard.
- Full and compact (one-row) layouts, and a pin to keep the player open.
- Pick any accent colour, or keep Spotify green.

**Lyrics**
- Synced lyrics in a floating pill below the menu bar, showing 1, 2, 3 or 5 lines.
- Click a line to jump to it in the song.
- Expand to a full-height view of the whole song.
- Dark, light, glass or album-coloured styles.
- Drag them anywhere, and reset to a default position.
- The timing can be nudged earlier or later.
- Lyrics come from LRCLIB, with NetEase as a fallback.

**Visualizer**
- Studio-style analysis of Spotify's audio beside the player: spectrum, spectrogram, scopes, level and loudness meters, and key. See [Visualizers](#visualizers) below.

**General**
- Open at login.

## Visualizers

![Full screen: the player beside all nine visuals, from the spectrum analyzer to the chromagram](docs/screenshots/full-screen-visualizers.jpg)

The visualizer column sits to the right of the full player. Switch visuals with the **‹ ›** arrows above it, by clicking the visual itself, or under Settings → Player.

- **Full screen:** hover the visual and click the expand button in its corner. It opens a full-screen view with the player on the left and every visual at once. Click a visual to show it large; **All visuals** goes back to the grid; Esc leaves full screen.
- **Pausing:** freezes the picture exactly as it was, so you can study it, and listening stops until you press play.
- **Requirements:** macOS 14.2 or later and the System Audio Recording permission (see [First run](#first-run)).

### How the data is collected

Every visual is drawn from the same audio and the same analysis pass — one pipeline, not nine.

- **Capture:** a Core Audio process tap (macOS 14.2+) on Spotify's own processes, mixed to stereo, inside a private aggregate device on your current output device. Spotify plays on untouched, nothing else is tapped, and nothing is recorded or saved. Barsong listens only while a visual is on screen and the music plays; pausing removes the tap, and a new track restarts the loudness, key and tempo measurements.
- **Every chunk of audio** (a few milliseconds, straight from the audio device): peak and RMS levels, the stereo scope's points, correlation and balance, and the loudness meter — K-weighted per sample to ITU-R BS.1770, in 100 ms hops (momentary 400 ms, short-term 3 s, gated integrated, one history point every 0.2 s).
- **From a Hann-windowed 4096-sample window** (~11.7 Hz per bin at 48 kHz): the spectrum curve (192 log-spaced bands over 20 Hz–20 kHz, tilted +3 dB per octave, rising fast and falling back gently), the waveform, triggered on a rising zero crossing of a low-passed copy, and the spectral flux the tempo is read from. Waveform snapshots are stacked 30 a second, spectra 20 a second.
- **Sixty times a second**, three windows at once — 16384, 8192 and 4096 samples: one spectrogram column of 512 log-spaced rows from 30 Hz to 16 kHz, each row read at the resolution meant for its frequency. The longest window also gives the note strengths, summing bins from 55 Hz to 2 kHz onto the 12 pitch classes, which feed the chromagram and, averaged over ~15 s, the key.
- **Tempo:** onset strength resampled onto a 100 Hz grid, autocorrelated over the last 8 seconds between 60 and 200 BPM, re-estimated twice a second.
- **It is Spotify's output** that gets measured, after Spotify's volume and **Normalize volume** settings — which is why the loudness meter asks for 100%.

### Spectrum analyzer
A smooth, filled frequency curve from 20 Hz to 20 kHz over a log grid (50, 100, 200, 500, 1k, 2k, 5k, 10k), like the analyzer in a studio EQ. A thin white line holds recent peaks and sinks slowly.
- **Reading it:** peaks are strong frequencies. A kick shows around 50–100 Hz, vocals around 200 Hz–4 kHz, air and cymbals above 8 kHz.
- **Tilt:** the curve is tilted up 3 dB per octave so treble shows as clearly as bass, as most analyzers do. Height is relative, not absolute dB.

### Spectrogram
Frequency over time as a heat map: about 9 seconds scrolling right to left, low notes at the bottom, louder in brighter colours (black → purple → orange → pale yellow).
- **Resolution:** bass is analysed with a long window for fine pitch, treble with a short one for sharp timing. Partials and harmonics show as separate bright lines.
- **Reading it:** horizontal lines are sustained notes and their overtones; vertical streaks are drum hits; the brightness shows how loud.

### Spectral waterfall
The spectrum analyzer's curve every 1/20 s, stacked into a shaded 3D landscape: newest at the front (bottom), the last ~2.4 seconds rising behind it. Shows how the frequency balance moves, like an acoustics waterfall plot.

### Oscilloscope
The waveform itself over a few milliseconds. It's triggered on rising zero crossings, like a hardware scope, so steady tones hold still instead of jittering. Pure tones look like smooth waves; distortion and rich synths look jagged.

### Wavetable
Steadied waveform snapshots, 30 a second, stacked edge to edge into a shaded, hilly landscape, like a synth's wavetable display. The newest is along the bottom, the last ~2 seconds rise behind it. Changes in timbre ripple back through the stack.

### Vectorscope
The stereo image: every recent sample plotted left against right and turned 45°, as on a goniometer.
- **Reading the shape:**
  - A vertical line (towards **M**) is mono.
  - A wide cloud is a wide stereo mix.
  - Leaning towards **L** or **R** means that side is louder.
  - A horizontal spread means out-of-phase content, which partly cancels when played in mono.
- **Correlation:** runs from −1 to +1, by convention. **+1** (right end) is mono, **0** (middle) means the sides are unrelated (very wide), and **below 0** (red) means out of phase. Healthy mixes sit mostly between +0.3 and +1.
- **Balance:** sits dead centre when left and right are equally loud, and shows how far it leans otherwise.

### Level meters
Peak and RMS for left and right on a dBFS scale from −60 to 0.
- **The solid bar** is the RMS (average) level over ~300 ms, roughly how loud it feels.
- **The lighter band above it** is the peak, rising instantly and falling at 24 dB per second.
- **The white line** holds the highest recent peak for 1.5 seconds, with its value on top. It shows red above −1 dBFS.
- **Colours** turn warm above −6 dB.
- The peak is the sample peak; true-peak meters can read up to about 0.5 dB higher.

### Loudness (LUFS)
A loudness meter to the ITU-R BS.1770 / EBU R 128 standard, the way streaming services measure loudness.
- **Integrated:** the gated average loudness of the track so far. It starts over with each track.
- **Short-term** (3 s) and **momentary** (400 ms): how loud it is right now.
- **Peak:** the highest sample since the track started, in dBFS.
- **History:** the last minute of short-term loudness against a dashed line at **−14 LUFS**, the level Spotify normalises to. Most modern masters sit well above it, which is why Spotify turns them down.
- **For true numbers:** set Spotify's volume to 100% and turn off its **Normalize volume** setting, because Barsong hears Spotify's output after both. The meter reminds you when the volume isn't at 100%.

### Chromagram
Which notes are sounding, as 12 rows (C at the bottom to B at the top, any octave) over the last ~8 seconds, brighter where a note is stronger.
- **Key:** named on top, estimated from roughly the last 15 seconds with the Krumhansl–Kessler key profiles, and marked as clear, likely or unsure. The notes of its scale are highlighted.
- **Tempo:** in BPM. Barsong measures how sharply the sound changes (spectral flux), then finds the strongest repeating interval between 60 and 200 BPM. Like most beat trackers, it leans towards the tempos people tap along to. When a beat is equally strong halfway between, it reads the faster tempo (up to 180 BPM, so drum & bass reads 174, not 87).
- **Both start over with every track.** They take a few seconds to settle.
- **Expect:**
  - occasional mix-ups between a major key and its relative minor (C major and A minor share their notes);
  - half or double tempo on some songs;
  - unreliable results for drum-heavy or atonal music.

## Requirements

- macOS 13 or later. The visualizer needs macOS 14.2 or later.
- The Spotify desktop app.
- For Liked Songs and the artist and album links: a Spotify account that can create a developer app. Spotify currently requires Premium for that.

## Install

Barsong is built from source.

1. Install Xcode 16 or later, or just its command line tools:
   ```sh
   xcode-select --install
   ```
2. Clone and build:
   ```sh
   git clone https://github.com/asger3p/barsong.git
   cd barsong
   ./build.sh
   ```

`build.sh` builds the app, installs it to `~/Applications/Barsong.app` and opens it. Run it again to update.

## First run

macOS asks for two permissions:

- **"Barsong wants to control Spotify"**: needed to read the current song and cover, and to play, pause, skip, seek and change the volume. Barsong never launches Spotify by itself.
- **System Audio Recording**: only asked when the visualizer first opens. Barsong listens to Spotify's audio alone, only while the visualizer is on screen, and records or saves nothing.

Both can be changed later in macOS System Settings → Privacy & Security.

## Connect your Spotify account

Liked Songs and the artist and album links use the Spotify Web API. Each user signs in through a small Spotify app of their own, so there's no shared key and no user limit. Barsong walks you through it under Settings (gear icon) → **Spotify Account**:

1. **Create a Spotify app.** "Open Spotify dashboard" takes you to the form. Copy in the app name and the redirect URI (`http://127.0.0.1:43117/callback`) with the copy buttons, tick **Web API** and save. The account creating the app needs Spotify Premium.
2. **Paste its Client ID**, found under the app's Settings. Barsong connects as soon as a complete Client ID is pasted.
3. **Approve in the browser.** After that, Barsong keeps you signed in.

## Privacy

- **Lyrics:** the artist, title, album and length of the current song are sent to [LRCLIB](https://lrclib.net), and to NetEase when LRCLIB has no synced lyrics.
- **Spotify:** Liked Songs and the artist and album links talk to Spotify's Web API with your own developer app.
- **Covers:** downloaded from Spotify's image servers.
- **Everything else stays on your Mac:**
  - Settings and your Client ID are kept in the app's preferences.
  - The sign-in is kept in your Keychain.
  - Audio is analysed live in memory and never stored or sent anywhere.

## Troubleshooting

- **No cover, or the buttons do nothing:** allow Barsong under System Settings → Privacy & Security → Automation → Spotify.
- **The visualizer says "No sound coming through":** allow Barsong under System Settings → Privacy & Security → System Audio Recording, then reopen the player.
- **Connecting fails with "Couldn't listen on port 43117":** another program is using that port. Quit it and try again.
- **"Spotify API error 403":** check that **Web API** is ticked for your developer app.
- **No lyrics for a song:** neither LRCLIB nor NetEase has synced lyrics for it. The lyrics button shows a crossed-out mic when that's the case.

## Uninstall

Turn off **Open Barsong at login** first (or remove Barsong later under System Settings → General → Login Items), then:

```sh
rm -rf ~/Applications/Barsong.app
defaults delete dev.asger.Barsong
security delete-generic-password -s dev.asger.Barsong
```

## Acknowledgements

- [LRCLIB](https://lrclib.net) for synced lyrics.
- NetEase Cloud Music as a fallback lyrics source, an idea borrowed from [LyricFever](https://github.com/aviwad/LyricFever).

## License

MIT. See [LICENSE](LICENSE).
