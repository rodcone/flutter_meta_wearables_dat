import 'package:flutter/material.dart';
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';
import 'package:flutter_meta_wearables_dat_example/providers/device_provider.dart';
import 'package:flutter_meta_wearables_dat_example/shared/widgets/meta_button.dart';
import 'package:provider/provider.dart';

/// Screen to show when user is not registered. It guides users through the
/// DAT SDK registration process, matching the CameraAccess sample app.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              const Spacer(),
              Image.asset(
                'assets/images/cameraAccessIcon.png',
                width: 130,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 30),
              const _HomeTipItem(
                icon: Icons.videocam_outlined,
                title: 'Video Capture',
                text:
                    'Record videos directly from your glasses, from your point '
                    'of view.',
              ),
              const SizedBox(height: 12),
              const _HomeTipItem(
                icon: Icons.hearing_outlined,
                title: 'Open-Ear Audio',
                text:
                    'Hear notifications while keeping your ears open to the '
                    'world around you.',
              ),
              const SizedBox(height: 12),
              const _HomeTipItem(
                icon: Icons.directions_walk_outlined,
                title: 'Enjoy On-the-Go',
                text:
                    'Stay hands-free while you move through your day. Move '
                    'freely, stay connected.',
              ),
              const Spacer(),
              Column(
                children: [
                  Text(
                    "You'll be redirected to the Meta AI app to confirm your "
                    'connection.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                    softWrap: true,
                  ),
                  const SizedBox(height: 10),
                  Consumer<DeviceProvider>(
                    builder: (context, deviceProvider, _) {
                      final registrationState =
                          deviceProvider.registrationState;
                      final isRegistering =
                          registrationState == RegistrationState.registering;

                      return MetaButton.text(
                        text: isRegistering
                            ? 'Connecting...'
                            : 'Connect my glasses',
                        enabled: !isRegistering,
                        onPressed: () {
                          if (!isRegistering) {
                            deviceProvider.startRegistration();
                          }
                        },
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeTipItem extends StatelessWidget {
  const _HomeTipItem({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 4),
          child: Icon(icon, size: 32, color: Colors.black),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                text,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
