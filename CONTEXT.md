# Layer

Layer is a macOS assistant that starts conversations from a persistent Notch and can include visual information from the user’s active display.

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

**Screen context**:
An optional image of the active display attached to a Turn. Failure to acquire Screen context does not prevent the Turn from continuing.
_Avoid_: Screenshot, screen attachment
