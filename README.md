<h1 align="center">VexoraSpotify</h1>

<p align="center">by Ximmy. A fork of <a href="https://spoti.pw">spoti.pw</a> (<a href="https://chroma.pw">chroma.pw</a>) by darkk. Liquid glass Spotify for iPhone, injected into your own decrypted IPA.</p>

<p align="center">
  <img src="https://img.shields.io/badge/iOS-000000?style=for-the-badge&logo=ios&logoColor=white" alt="iOS">
  <img src="https://img.shields.io/badge/Spotify-9.1.90-1ED760?style=for-the-badge&logo=spotify&logoColor=white" alt="Spotify 9.1.90">
  <img src="https://img.shields.io/badge/Objective--C-3A95E3?style=for-the-badge&logo=apple&logoColor=white" alt="Objective-C">
  <img src="https://img.shields.io/badge/GitHub_Actions-2671E5?style=for-the-badge&logo=githubactions&logoColor=white" alt="GitHub Actions">
</p>

<p align="center">
  <a href="#install-it">Install it</a> ·
  <a href="#build-it">Build it</a> ·
  <a href="docs/tweaks.md">Hack on it</a>
</p>

A Theos tweak that rebuilds Spotify for iOS in Liquid Glass. You bring a decrypted **Spotify 9.1.90** IPA. The hooks target that version's classes, so another Spotify release may build and then break.

| | |
|---|---|
| Redesigned look | **iOS 26+**, and it is the look the app opens in |
| Legacy look | iOS 16.1+, Spotify's own screens with the rest of the mod on top |
| Live Activity | iOS 17+ |

On iOS 26 there is no theme picker. Hold Home on the tab bar to open Mod Settings. The version beside Mod is the number in `version.txt`.

## What it does

Lyrics are their own page. The app stays upright.

The lyrics background fills that page:

- **Solid color**, default black, with its own picker
- **Cover glow**, colour taken from the album art
- **Original**, Spotify's own lyrics background, left as Spotify drew it

Title, artist, credits, and the playback controls stay on that page. Their outline is white when the background is dark and black when it is light. The control icons are white, so their ring is black.

Sung lyrics can follow the cover, made more vivid after the colour is chosen, or use a colour you pick. Looks are Apple Music, Large, Compact, Calm, Vivid, and Vexora. Vexora is the one that glows the line being sung. Mojangles is in the font list for every look, and a `.ttf` or `.otf` from Files can be used for the lyrics only.

Discord status is **Listening to Vexora**, with the current lyric on the artwork. Set the token under Lyrics → Discord. It is the same token the desktop Vexora app uses.

Mod Settings also has appearance and fonts, the navbar, the player, lock screen artwork, audio effects, vibrations, Live Activity, AirPods gestures, listening stats, albums, artists, karaoke, lossless files from Files → Spotify → Lossless, and Premium, ads & privacy. Spoof Premium starts on. The page warns that a Premium account gains nothing from it, and that it can end in a forced logout.

## Install it

Releases do not carry an IPA. In Actions, run **Build IPA from your own Spotify IPA** with a direct link to a decrypted Spotify 9.1.90 `.ipa`. The result is a workflow artifact named `VexoraSpotify-<version>.ipa`. Sign it and install it with SideStore, Feather, or any certificate signer.

The link is masked in the log. On a private repo the Mac runner is shared with one job at a time, so a build can sit queued, and starting another one cancels the one already waiting.

## Build it

On a Mac you get the same unsigned `out/VexoraSpotify-<version>.ipa`.

Theos in `~/theos`, and Xcode with an iPhoneOS 26+ SDK (`xcode-select` it). An SDK in `~/theos/sdks` alone builds too, but without the Live Activity. Then:

    brew install make ldid dpkg zsign ideviceinstaller libimobiledevice
    uv tool install "cyan @ git+https://github.com/asdfzxcvbn/pyzule-rw"

Put the decrypted `.ipa` in `ipa/`, then:

    make release    # out/VexoraSpotify-<version>.ipa, ready to sign
    make install    # the same, signed with your certificate and pushed over USB

`make install` reads `SIGN_P12`, `SIGN_PROFILE` and `SIGN_P12_PASSWORD` from `.signing.env`. Copy `.signing.env.example` and fill it in.

The first build spends a minute reading Spotify's flags out of your IPA. `make flags` regenerates that.

### Signing

Sign with a bundle id matching your certificate's App ID. If it does not match, the app still works, but tapping the player on the lock screen will not open it, and the first launch tells you which id to use. In Feather, copy the App ID into **Identifier** and leave **PPQ protection** off. AltStore, SideStore, and Sideloadly get this right on their own.

The app keeps Spotify's bundle id, so it installs over the real Spotify.

## Contributing

Pull requests are welcome. The pull request description has a box for the [Contributor License Agreement](CLA.md), which gives the project's owner the rights to the contribution. Tick it once, before the first pull request is merged.

## Credits

VexoraSpotify is by Ximmy. It is a fork of [spoti.pw](https://spoti.pw) / [chroma.pw](https://chroma.pw) by darkk. Settings credit @Pulse-Ice (EeveeImmersive).

[cyan](https://github.com/asdfzxcvbn/pyzule-rw) injects, [Theos](https://theos.dev) builds, and [FLEX](https://github.com/FLEXTool/FLEX), as hopeless's AutoFLEX build in `vendor/`, is the inspector the view trees are read through.

Licensed under the [PolyForm Strict License 1.0.0](LICENSE). Not affiliated with Spotify.

## Safari link opener

IPA builds include the Open in Spotify Safari extension. See [setup, coverage, and verification](docs/safari-extension.md). `make test-safari` runs the checks. `SAFARI=0` builds without the extension.
