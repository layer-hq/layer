# Layer

<img src="logo.svg" alt="Layer logo" width="64">

Layer is a native macOS assistant that lives beneath the MacBook notch. Hover
over the Notch or press the configured modifier key twice, enter a prompt, and
receive a streamed response from OpenAI. The model may search the web when a
Turn needs current information. A Turn can include the active display or a
manually selected region as visual context.

> **Screen context disclosure:** When **Take screen context** is enabled,
> submitting a prompt captures the entire active display (the display under the
> pointer) and sends the image to OpenAI with the prompt and Chat conversation
> history. **Select** sends only the selected region. Screen context is off by
> default.

## Privacy and permissions

- **OpenAI:** Layer uses your own API key, saved locally in the app's macOS user
  preferences. Every Responses API request sets `store: true`, so OpenAI retains
  each response — including the prompt and any Screen context image — as
  application state on your account; Layer carries conversational continuity by
  referencing the previous response by id rather than resending local history.
  Each Turn also enables OpenAI's hosted web search tool, so the model may query
  the live web from the prompt; search usage is billed on your OpenAI account.
  OpenAI may additionally retain API content in abuse-monitoring logs. See
  [OpenAI's data controls](https://developers.openai.com/api/docs/guides/your-data)
  for retention and deletion.
- **Telemetry:** Layer includes no analytics or telemetry.
- **Screen Recording:** Required only to capture the active display or a
  selected region. macOS controls access in Privacy & Security settings.
- **Input Monitoring:** Used for the global double-modifier shortcut so Layer
  can open while another app is active. The global monitor receives only
  modifier-key changes, never typed key events, so Layer does not see what you
  type in other apps. Inside Layer's own windows it also watches for key
  presses, purely so that a key struck while the modifier is held cancels a
  pending double tap; that needs no permission, since an app always receives
  its own key events, and the keys themselves are never read. macOS grants the
  Input Monitoring permission at the coarse granularity of "input events";
  there is no narrower scope an app can request.
- **App Sandbox:** The app is intentionally built without App Sandbox. macOS
  privacy permissions still gate Screen Recording and Input Monitoring.

## Requirements

- An Apple silicon Mac (M1 or newer) running macOS 14 or newer
- Swift 6 and the macOS SDK
- An [OpenAI API key](https://platform.openai.com/api-keys)

Xcode project files are not required. If `swift --version` is unavailable,
install Apple's Command Line Tools with `xcode-select --install`.

## Build and run

```sh
make run
```

This builds `.build/Layer.app`, stops an older development instance, and opens
the new build. Add the OpenAI API key in Layer's Settings window.

Other useful commands:

```sh
make dev   # rebuild and relaunch after source changes; requires fswatch
make stop  # close Layer
swift test
```

The bundle identifier is `use.layer.app`.

## License

Layer is released under the MIT License; see [LICENSE](LICENSE).

Bundled dependencies and Phosphor Icons ship under their own permissive
licenses, reproduced in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md). That
file must accompany a distributed `Layer.app`.
