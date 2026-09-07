# Layer

Layer is a macOS assistant that starts conversations from a persistent Notch and can include selected content and visual information from the user’s active display.

## Language

**Notch**:
The persistent control surface beneath the MacBook notch where a person starts a Chat conversation.
_Avoid_: Handle, tray

**Chat conversation**:
A sequence of user turns and assistant responses that share conversational continuity.
_Avoid_: Session, thread

**Turn**:
One user prompt and the assistant response it produces within a Chat conversation.
_Avoid_: Request, message exchange

**Selected content**:
Optional text from the focused field in the frontmost app. Layer reads it before taking focus, and only when **Include selected content** is enabled for that opening.
_Avoid_: Clipboard dump, highlighted text

**Screen context**:
An optional image of the active display attached when Chat, Voice, or Insert starts. Layer excludes its own windows from the image. Failure to acquire Screen context does not prevent the action from continuing.
_Avoid_: Screenshot, screen attachment

**Pending context**:
Remembered application, target display, and optional Selected content for the current Notch opening. It is cleared after an action takes a snapshot or when the Notch is dismissed.
_Avoid_: Buffer, stash

**Invocation inputs**:
The immutable snapshot passed to Chat, Voice, or Insert. Model context (Selected content and Screen context) may be sent to OpenAI. The interaction target (application, display, and accessibility restore metadata) stays on the device.
_Avoid_: Tool request, context bag
