# Layer

<img src="logo.svg" alt="Layer logo" width="64">

Layer is a native macOS assistant that lives beneath the MacBook notch. Hover
over the Notch or press the configured modifier key twice, enter a prompt, and
receive a streamed response from the selected model provider. OpenAI models may
search the web when a Turn needs current information. A Turn can include
selected content from the frontmost app and the active display or a manually
selected region as visual context.

> **Input context disclosure:** When **Include selected content** is enabled,
> opening the Notch reads the focused field's selected text (via Accessibility,
> or briefly via the clipboard if Accessibility cannot see it) and may send that
> text to the selected model provider with Chat, Voice, or Insert. When **Take
> screen context** is enabled, starting Chat, Voice, or Insert captures the target
> display, excluding Layer's own windows, and sends the image to the selected
> model provider. Submitting **Select** to Chat sends only the selected region.
> **Copy img** on Select writes that region to the clipboard and does not send it
> to a provider. Both options are off by default.

## Privacy and permissions

- **Provider connections:** Layer supports OpenAI and self-hosted
  [LiteLLM](https://docs.litellm.ai/) proxies. Configure each provider's base
  URL, key, and model, then select the active provider in the Settings sidebar.
  These details are saved locally in the app's macOS user preferences.
  Remote hosts should use HTTPS; local-network HTTP is supported for development.
- **OpenAI:** Every Responses API request sets `store: true`, so OpenAI retains
  each response — including the prompt, any selected text, and any Screen
  context image — as
  application state on your account; Layer carries conversational continuity by
  referencing the previous response by id rather than resending local history.
  Each Turn also enables OpenAI's hosted web search tool, so the model may query
  the live web from the prompt; search usage is billed on your OpenAI account.
  OpenAI may additionally retain API content in abuse-monitoring logs. See
  [OpenAI's data controls](https://developers.openai.com/api/docs/guides/your-data)
  for retention and deletion.
- **LiteLLM:** Chat and Insert are sent to the selected proxy through its
  OpenAI-compatible `/v1/chat/completions` endpoint. Storage, logging, web
  access, and downstream-provider retention depend on that proxy's configuration.
- **Telemetry:** Layer includes no analytics or telemetry.
- **Microphone:** Required for voice mode, which currently requires an OpenAI
  connection. Audio is sent to OpenAI's Realtime API only while the Notch
  microphone control is on.
- **Screen Recording:** Required only to capture the active display or a
  selected region for Chat, Voice, Insert, or Select. macOS controls access in
  Privacy & Security settings.
- **Input Monitoring:** Used for the global double-modifier shortcut so Layer
  can open while another app is active. The global monitor receives only
  modifier-key changes, never typed key events, so Layer does not see what you
  type in other apps. Inside Layer's own windows it also watches for key
  presses, purely so that a key struck while the modifier is held cancels a
  pending double tap; that needs no permission, since an app always receives
  its own key events, and the keys themselves are never read. macOS grants the
  Input Monitoring permission at the coarse granularity of "input events";
  there is no narrower scope an app can request.
- **Accessibility:** Required to insert at the cursor in another app (restore
  focus and post paste). When **Include selected content** is enabled, Layer also
  reads the focused field's selected text before taking focus, or if
  Accessibility cannot see it, copies with Cmd+C, uses that string as model
  context, then restores the clipboard. Chat, Voice, and Insert can send that
  selected text to the active provider. Paste puts the result on the clipboard
  briefly, then restores the previous clipboard when nothing else changed it.
- **App Sandbox:** The app is intentionally built without App Sandbox. macOS
  privacy permissions still gate Screen Recording, Microphone, Input
  Monitoring, and Accessibility.

## Requirements

- An Apple silicon Mac (M1 or newer) running macOS 14 or newer
- Swift 6 and the macOS SDK
- An [OpenAI API key](https://platform.openai.com/api-keys), or a LiteLLM proxy
  base URL, virtual key, and model name

Xcode project files are not required. If `swift --version` is unavailable,
install Apple's Command Line Tools with `xcode-select --install`.

## Download

[Latest release](https://github.com/layer-hq/layer/releases/latest)
(signed and notarized). Open the DMG and drag `Layer.app` to Applications.
The app checks that page for updates.

The bundle identifier is `com.getlayerapp`.

## Build and run

```sh
make run
```

This builds `.build/Layer.app`, stops an older development instance, and opens
the new build. Add and select a provider connection in Layer's Settings window.

Other useful commands:

```sh
make dev   # rebuild and relaunch after source changes; requires fswatch
make stop  # close Layer
swift test
```

## License

Layer is released under the MIT License; see [LICENSE](LICENSE).

Bundled dependencies ship under their own permissive
licenses, reproduced in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md). That
file must accompany a distributed `Layer.app`.
