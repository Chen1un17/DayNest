# Contributing

Bug reports and pull requests are welcome. Include your macOS version, chip architecture and steps to reproduce. Use synthetic examples rather than uploading your personal data.json or screenshots with private tasks.

Build and check changes on macOS:

```sh
./scripts/test.sh
./scripts/build-app.sh
```

For conference parser changes, also verify the live feed using the optional fixture command in README.md. Keep old JSON backups readable, preserve user data, and test changes to folder isolation and time zones. The app uses SwiftUI/AppKit and has no third-party Swift dependencies.

By contributing, you agree that your contributions are licensed under the MIT license.
