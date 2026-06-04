import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';
import 'package:flutter_meta_wearables_dat_example/providers/device_provider.dart';
import 'package:flutter_meta_wearables_dat_example/providers/mock_device_provider.dart';
import 'package:flutter_meta_wearables_dat_example/providers/stream_provider.dart';
import 'package:flutter_meta_wearables_dat_example/screens/home/home_screen.dart';
import 'package:flutter_meta_wearables_dat_example/screens/mock_device/mock_device_sheet.dart';
import 'package:flutter_meta_wearables_dat_example/screens/settings/settings_sheet.dart';
import 'package:flutter_meta_wearables_dat_example/screens/stream/stream_screen.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final appLinks = AppLinks();
  StreamSubscription<Uri>? _deepLinkSubscription;
  String? _lastHandledDeepLink;
  final navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initDeepLinkListener());
  }

  // app_links delivers deep links via uriLinkStream; without this override
  // MaterialApp's default observer also tries to Navigator.pushNamed the full
  // URL as a route and logs "Could not find a generator for route". Returning
  // true short-circuits that fallback.
  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) {
    return Future.value(true);
  }

  Future<void> _initDeepLinkListener() async {
    try {
      final initialUri = await appLinks.getInitialLink();
      if (initialUri != null) {
        await _handleDeepLinkUri(initialUri);
      }
    } catch (e) {
      debugPrint('[MetaWearablesDAT] Error reading initial deep link: $e');
    }

    _deepLinkSubscription = appLinks.uriLinkStream.listen(
      _handleDeepLinkUri,
      onError: (dynamic err) {
        debugPrint('[MetaWearablesDAT] Error handling deep link: $err');
      },
    );
  }

  Future<void> _handleDeepLinkUri(Uri uri) async {
    final uriString = uri.toString();
    if (_lastHandledDeepLink == uriString) {
      return;
    }
    _lastHandledDeepLink = uriString;

    final context = navigatorKey.currentContext;
    if (context != null && context.mounted) {
      final deviceProvider = Provider.of<DeviceProvider>(
        context,
        listen: false,
      );
      await deviceProvider.handleUrl(uriString);
      return;
    }

    await MetaWearablesDat.handleUrl(uriString);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deepLinkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DeviceProvider()),
        ChangeNotifierProvider(create: (_) => MockDeviceProvider()),
        ChangeNotifierProxyProvider2<
          DeviceProvider,
          MockDeviceProvider,
          StreamSessionProvider
        >(
          create: (context) => StreamSessionProvider(
            context.read<DeviceProvider>(),
            context.read<MockDeviceProvider>(),
          ),
          update: (_, deviceProvider, mockDeviceProvider, previous) =>
              previous ??
              StreamSessionProvider(deviceProvider, mockDeviceProvider),
        ),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        home: Builder(
          builder: (context) =>
              Consumer2<DeviceProvider, StreamSessionProvider>(
            builder: (context, deviceProvider, streamProvider, _) => Scaffold(
              floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
              floatingActionButton: streamProvider.isStreaming
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(top: 8, right: 5),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (deviceProvider.isRegistered)
                            Padding(
                              padding: const EdgeInsets.only(right: 5),
                              child: FloatingActionButton.small(
                                heroTag: 'settings',
                                backgroundColor: Colors.blueAccent,
                                tooltip: 'Settings',
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  showModalBottomSheet<void>(
                                    isScrollControlled: true,
                                    context: context,
                                    builder: (ctx) => const SettingsSheet(),
                                  );
                                },
                                child: const Icon(
                                  Icons.settings,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          if (!deviceProvider.isRegistered)
                            FloatingActionButton.small(
                              heroTag: 'mock_device',
                              backgroundColor: Colors.blueAccent,
                              tooltip: 'Mock device',
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                showModalBottomSheet<void>(
                                  isScrollControlled: true,
                                  context: context,
                                  builder: (ctx) => const MockDeviceSheet(),
                                );
                              },
                              child: const Icon(
                                Icons.bug_report,
                                color: Colors.white,
                              ),
                            ),
                        ],
                      ),
                    ),
              body:
                  Consumer3<
                    DeviceProvider,
                    MockDeviceProvider,
                    StreamSessionProvider
                  >(
                    builder:
                        (
                          context,
                          deviceProvider,
                          mockDeviceProvider,
                          streamProvider,
                          _,
                        ) {
                          // If we have a device and media selected, show stream screen
                          if (mockDeviceProvider.deviceUUID != null &&
                              (streamProvider.selectedVideo != null ||
                                  streamProvider.selectedImage != null)) {
                            return const StreamScreen();
                          }
                          // If registered but no device/media, show stream screen for camera permission
                          if (deviceProvider.isRegistered) {
                            return const StreamScreen();
                          }
                          // Otherwise show home screen for registration
                          return const HomeScreen();
                        },
                  ),
            ),
          ),
        ),
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF0081FB),
            primary: const Color(0xFF0081FB),
          ),
          useMaterial3: true,
        ),
        themeMode: ThemeMode.light,
      ),
    );
  }
}
