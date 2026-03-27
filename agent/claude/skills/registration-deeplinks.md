# Registration and deep links

## Overview

Registration is a one-time flow where the user approves your app in the Meta AI companion app. The flow uses deep links for the round-trip.

## Registration flow

```dart
// 1. Subscribe to registration state BEFORE starting
final sub = MetaWearablesDat.registrationStateStream().listen((state) {
  switch (state) {
    case RegistrationState.registering:
      // Show loading indicator
      break;
    case RegistrationState.registered:
      // Registration complete — proceed to camera permission
      break;
    case RegistrationState.available:
      // Ready to register
      break;
    case RegistrationState.unavailable:
      // Cannot register (system constraints)
      break;
  }
});

// 2. Start registration — opens Meta AI app
await MetaWearablesDat.startRegistration();

// 3. User confirms in Meta AI app, which redirects back via deep link

// 4. Handle the callback (in your app_links listener)
appLinks.uriLinkStream.listen((uri) async {
  await MetaWearablesDat.handleUrl(uri.toString());
  // After returning from Meta AI, restart device monitoring (critical on Android)
  await MetaWearablesDat.restartActiveDeviceMonitoring();
});
```

## RegistrationState values

| Value | Int | Meaning |
|-------|-----|---------|
| `unavailable` | 0 | Cannot register (system constraints) |
| `available` | 1 | Ready to register |
| `registering` | 2 | Registration in progress |
| `registered` | 3 | Successfully registered |

## Disconnect (unregistration)

```dart
// Also opens Meta AI app — handle the deep link callback the same way
await MetaWearablesDat.disconnect();
```

## Error handling

```dart
try {
  await MetaWearablesDat.startRegistration();
} on PlatformException catch (e) {
  if (e.code == 'REGISTRATION_ERROR') {
    // e.message contains a description
    // e.details may contain error code:
    //   0 = alreadyRegistered
    //   1 = configurationInvalid
    //   2 = metaAINotInstalled
    //   3 = networkUnavailable
    //   4 = unknown
  }
}
```

## Key patterns

- Always subscribe to `registrationStateStream()` before calling `startRegistration()`.
- Always call `handleUrl()` on every incoming deep link URI — it handles both registration and unregistration.
- After returning from Meta AI (handleUrl), call `restartActiveDeviceMonitoring()` — the app was in background and the device flow may be stale.
- Check registration state on app startup with `getRegistrationState()`.

## Reference implementation

See `example/lib/providers/device_provider.dart` for the canonical pattern.
