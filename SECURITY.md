# Security and privacy

Local Wispr is designed to keep dictation local by default.

## Privacy defaults

- No cloud transcription path in the default app.
- No account requirement.
- No analytics or remote history.
- Audio temp files are deleted after processing.
- Optional HTTP services are loopback-only by default.
- Automatic paste requires macOS Accessibility permission; without it, text is copied to the clipboard.

## Sensitive data

Do not commit or attach:

- personal audio recordings;
- raw `.wav`, `.caf`, `.aiff`, `.m4a`, `.mp3`, or `.flac` files;
- downloaded model weights;
- API keys, notary credentials, certificates, or `.p12` files;
- timing logs that contain sensitive dictated text or app context.

## Reporting a vulnerability

This project does not yet have a dedicated security inbox. For now, open a minimal GitHub issue that describes the affected area without posting secrets, credentials, private audio, or exploit details. The maintainer can coordinate a private follow-up channel if needed.

## Security-sensitive areas

Please be especially careful with changes to:

- microphone capture and temporary file cleanup;
- paste helper and Accessibility behavior;
- loopback URL validation;
- release signing/notarization scripts;
- any new network or model-download behavior.
