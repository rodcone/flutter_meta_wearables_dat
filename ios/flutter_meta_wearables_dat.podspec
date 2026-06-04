#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_meta_wearables_dat.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_meta_wearables_dat'
  s.version          = '0.5.1'
  s.summary          = "Flutter bridge to Meta's Wearables DAT for iOS and Android."
  s.description      = <<-DESC
Flutter plugin providing a bridge to Meta's Wearables Device Access Toolkit (DAT)
for integration with Meta AI Glasses (Ray-Ban Meta). Supports device registration,
camera permissions, video streaming with raw (BGRA) and hvc1 (HEVC) codecs, photo
capture, and background streaming on iOS 17.0+.
                       DESC
  s.homepage         = 'https://github.com/rodcone/flutter_meta_wearables_dat'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Gautier de Lataillade' => 'gautier@levinriegner.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '17.0'
  s.static_framework = true
  s.vendored_frameworks = [
    'Frameworks/MWDATCore.xcframework',
    'Frameworks/MWDATCamera.xcframework'
  ]
  s.preserve_paths = 'Frameworks/*.xcframework'
  s.frameworks = 'CoreBluetooth', 'Network', 'AVFoundation', 'VideoToolbox'
  s.xcconfig = { 'OTHER_LDFLAGS' => '-framework MWDATCamera -framework MWDATCore' }

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386', 'OTHER_LDFLAGS' => '-lc++' }
  s.swift_version = '5.0'

  # Privacy manifest declares no required-reason API usage and no tracking; ship
  # it so consumers' aggregated privacy report stays accurate.
  s.resource_bundles = {'flutter_meta_wearables_dat_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
