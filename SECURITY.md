# Security policy

Layer runs on your Mac with your OpenAI API key, and — when **Take screen
context** is enabled — it can capture the active display. That makes two classes
of bug security-relevant, not just cosmetic:

- anything that discloses the API key, or
- anything that captures, retains, or transmits screen content the person did
  not intend to send.

Please report those privately rather than in a public issue.

## Supported versions

Layer has no tagged releases yet. Only the current `main` branch receives fixes;
there is no supported older line. See [CHANGELOG.md](CHANGELOG.md).

## Reporting a vulnerability

Use GitHub's private vulnerability reporting: open the repository's **Security**
tab and choose **Report a vulnerability**. The report stays private to you and
the maintainers, and the discussion happens in that advisory.

If that form is unavailable to you, open a public issue containing **only** a
request for a private contact route — no details, no reproduction steps — and a
maintainer will open an advisory and invite you to it.

A useful report includes:

- what an attacker gains (read the key, exfiltrate a screenshot, run code);
- the affected file or code path, if you have it;
- steps to reproduce, and the macOS version and build you saw it on;
- whether the app had Screen Recording or Input Monitoring permission granted.

Proof-of-concept code is welcome. Please do not test against anyone else's
machine or account.

### What to expect

This is a small, unfunded project — there is no bounty and no paid on-call
rotation. Expect a first response within 7 days and, for a confirmed issue, an
assessment and a plan within 30 days. A fix ships on `main` with a GitHub
Security Advisory crediting you, unless you ask to stay anonymous. If a report
turns out not to be a vulnerability, the advisory is closed with an explanation
and you are free to discuss it publicly.

Please give us a chance to ship a fix before publishing details. If you have not
heard back in 30 days, disclose — silence is not a request for indefinite
embargo.

## Known design decisions that are not vulnerabilities

These are deliberate and documented; reporting them is not necessary, though
arguments for changing them are welcome as ordinary issues.

- **The API key is stored in `UserDefaults`, in cleartext.** It lands in
  `~/Library/Preferences/`, readable by any process running as you, and is
  swept into backups. Moving it to the Keychain is a known open task.
- **The app is not sandboxed.** macOS still gates Screen Recording, Microphone,
  Input Monitoring, and Accessibility through TCC. See "Privacy and permissions"
  in the
  [README](README.md).
- **Screen context is sent to OpenAI when enabled, and OpenAI stores it.**
  Requests set `store: true`, so the prompt and any Screen context image are
  retained on your OpenAI account as a stored response that Layer references by
  id on the next Turn. OpenAI may additionally retain API content in
  abuse-monitoring logs. The README says so up front.
- **Turns use OpenAI hosted web search.** The model may fetch live web results
  from the prompt. Layer does not call other search APIs; search usage is billed
  on the same OpenAI key.
- **Screen context captures the whole active display** with no preview or
  redaction step, so it can include whatever else is on screen. Adding a
  confirm step is a known open task. Screen context is off by default.

## Scope

In scope: this repository's source, build scripts, and CI workflows.

Out of scope: vulnerabilities in OpenAI's API, in macOS itself, or in the
third-party dependencies listed in
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) — report those to their
maintainers. If a dependency's flaw is reachable through Layer in a way that
makes it materially worse, that is in scope and worth telling us about.
