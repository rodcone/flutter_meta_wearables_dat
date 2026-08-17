#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_meta_wearables_dat_mock_device.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_meta_wearables_dat_mock_device'
  s.version          = '0.8.1'
  s.summary          = 'Optional MockDeviceKit add-on for flutter_meta_wearables_dat.'
  s.description      = <<-DESC
Optional MockDeviceKit add-on for flutter_meta_wearables_dat. Pull this in only
when you need to simulate a Ray-Ban Meta device with the phone's camera —
production builds should omit it to keep AVFoundation/Camera symbols out of
the binary and skip the matching Info.plist usage strings.
                       DESC
  s.homepage         = 'https://github.com/rodcone/flutter_meta_wearables_dat'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Gautier de Lataillade' => 'gautier@levinriegner.com' }
  s.source           = { :path => '.' }
  s.source_files = 'flutter_meta_wearables_dat_mock_device/Sources/flutter_meta_wearables_dat_mock_device/**/*'
  s.dependency 'Flutter'
  # Transitive access to MWDATCore.xcframework (vendored by the core plugin)
  # — needed for MWDATCore.Permission / MWDATCore.PermissionStatus types.
  s.dependency 'flutter_meta_wearables_dat'
  s.platform = :ios, '17.2'
  s.static_framework = true
  s.vendored_frameworks = [
    'flutter_meta_wearables_dat_mock_device/Frameworks/MWDATMockDevice.xcframework'
  ]
  s.preserve_paths = 'flutter_meta_wearables_dat_mock_device/Frameworks/*.xcframework'
  s.frameworks = 'AVFoundation', 'CoreMedia'
  s.xcconfig = { 'OTHER_LDFLAGS' => '-framework MWDATMockDevice' }

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386', 'OTHER_LDFLAGS' => '-lc++' }
  s.swift_version = '5.0'
end
