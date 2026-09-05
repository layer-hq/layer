# Changelog

All notable changes to Layer are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
Layer follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- OpenRouter as a hosted model provider for Chat and Insert, with model loading
  and a fixed official API endpoint.
- Copy img on Select writes the chosen region to the clipboard as PNG and TIFF
  without opening Chat, then restores the previous app.

## [0.1.0] - 2026-09-05

### Added

- Hosted OpenAI web search on every Turn, so the model can use current
  information with the existing API key.
- Direct distribution as a signed, notarized DMG from GitHub Releases, with
  Sparkle in-app updates.
