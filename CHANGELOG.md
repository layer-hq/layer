# Changelog

All notable changes to Layer are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
Layer follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-09-10

### Added

- LiteLLM proxy connections alongside OpenAI, so Chat and Insert can use a
  self-hosted OpenAI-compatible endpoint.
- Copy img on Select writes the chosen region to the clipboard as PNG and TIFF
  without opening Chat, then restores the previous app.

### Changed

- Chat conversation window matches the Notch UI.
- Notch controls are rebuilt without Phosphor icons.

### Fixed

- Escape aborts Insert without dismissing the Notch.
- Voice no longer treats speaker echo as a user turn.
- Copy img clears the pasteboard before writing the new image.

## [0.1.0] - 2026-09-05

### Added

- Hosted OpenAI web search on every Turn, so the model can use current
  information with the existing API key.
- Direct distribution as a signed, notarized DMG from GitHub Releases, with
  Sparkle in-app updates.
