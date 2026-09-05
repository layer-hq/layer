# Contributing to Layer

Thanks for taking a look. Layer is a small native macOS app, and the codebase is
meant to stay readable — a contribution that fits the existing shape is worth
more here than a large one that rearranges it.

By contributing you agree that your work is licensed under the
[MIT License](LICENSE), the same terms as the rest of the project.

## Before you start

- **Bug fixes:** open a pull request directly. No issue required.
- **New features or anything that changes behavior:** open an issue first and
  say what you have in mind. Layer is opinionated about scope — a feature can be
  well built and still not belong in it, and finding that out after the work is
  done is nobody's idea of fun.
- **Anything security-relevant:** do not open a public issue. Follow
  [SECURITY.md](SECURITY.md).

## Development setup

Requirements:

- macOS 14 or newer
- Swift 6 and the macOS SDK — `xcode-select --install` if `swift --version`
  comes up empty
- An [OpenAI API key](https://platform.openai.com/api-keys) for running the app
  (not needed to build or to run the tests)

There is no Xcode project; SwiftPM plus a build script produces the bundle.

```sh
make run     # build .build/Layer.app, stop any old instance, launch it
make dev     # rebuild and relaunch on save; requires fswatch
make stop    # quit Layer
swift build  # compile only
swift test   # run the test suite
```

Add your API key in Layer's Settings window after the first launch.

The bundle identifier is `com.getlayerapp`. Changing it resets saved settings
and macOS privacy grants for local builds.

Layer needs **Screen Recording** permission to capture screen context and
**Input Monitoring** for the global double-modifier shortcut. macOS ties those
grants to the app bundle, so a rebuilt bundle occasionally has to be re-approved
in System Settings → Privacy & Security.

## Making a change

- **Match the surrounding code.** Swift 6, SwiftUI and AppKit as already used,
  the same naming and comment density as the file you are editing.
- **Use the project's vocabulary.** [CONTEXT.md](CONTEXT.md) defines the terms —
  Notch, Chat conversation, Turn, Screen context — and names the words to avoid.
  It applies to identifiers, comments, and UI strings alike.
- **Add tests for logic.** The suite in `Tests/LayerTests/` covers the pieces
  that can be tested without a window server; keep that boundary. `swift test`
  must pass.
- **Keep privacy changes visible.** Anything that widens what Layer captures,
  monitors, or sends — a broader event mask, a new network call, more of the
  screen — belongs in the pull request description and, if it changes what the
  README promises, in the README too.
- **Do not commit secrets or build output.** `.build/`, `.env` and
  signing material are gitignored; keep it that way.

## Commit messages and pull requests

Write a subject line that says what changed and why it needed to change.
"Narrow the global event monitor to flagsChanged" beats "fix: keyboard". Bodies
are welcome for anything non-obvious.

A pull request should:

- do one thing, and say in the description what problem it solves;
- state how you verified it — `swift test`, plus what you clicked through if the
  change is visual;
- include a screenshot or short recording for UI changes;
- leave CI green. The [Build workflow](.github/workflows/build.yml) builds the
  app bundle and runs the tests on macOS.

## Releasing

Releases are cut from a maintainer Mac. Apple and Sparkle private keys stay in
the login Keychain; they are never stored in GitHub.

One-time setup:

```sh
gh auth login
xcrun notarytool store-credentials "layer-notary"
```

Sparkle also needs an EdDSA key in the login Keychain (`generate_keys` from
`.build/artifacts/sparkle/Sparkle/bin` after resolving packages). Export a
backup with `generate_keys -x`; do not commit it.

Each release:

1. Increment `CFBundleVersion`, set `CFBundleShortVersionString` in
   `Resources/Info.plist`, and move [CHANGELOG.md](CHANGELOG.md) Unreleased
   entries under that version.
2. Commit and push `main`.
3. Run `./scripts/release.sh`.

The script tests, signs, notarizes a DMG, generates the Sparkle appcast, tags
`v<version>`, and publishes the GitHub Release. If `gh release create` fails
after the tag is pushed, rerun that command; do not retag.

## Dependencies

Adding a dependency is a real decision: it has to be permissively licensed,
maintained, and worth its weight. If you add one, record it in
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) with its full license text in
the same style as the existing entries.

## Code of conduct

Participation is governed by the [Code of Conduct](CODE_OF_CONDUCT.md).
