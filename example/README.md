# flutter_meta_wearables_dat_example

Demonstrates how to use the flutter_meta_wearables_dat plugin.

## Secrets setup (required to run)

Meta App ID and Client Token must be configured before the app can connect to
Meta AI Glasses. These values are stored in gitignored files.

### iOS

1. Copy the template: `cp ios/Flutter/Secrets.template.xcconfig ios/Flutter/Secrets.xcconfig`
2. Edit `Secrets.xcconfig` and replace `YOUR_APP_ID` and `YOUR_CLIENT_TOKEN`
   with your values from the [Meta Wearables Developer Center](https://wearables.developer.meta.com/devcenter)

### Android

1. Copy the template: `cp android/secrets.properties.template android/secrets.properties`
2. Edit `secrets.properties` and replace `YOUR_APP_ID` and `YOUR_CLIENT_TOKEN`
   with your values from the [Meta Wearables Developer Center](https://wearables.developer.meta.com/devcenter)
3. Use `0` for `META_APPLICATION_ID` if using Developer Mode

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
