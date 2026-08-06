Pod::Spec.new do |s|
  s.name             = 'napaxi_flutter'
  s.version          = '1.0.0'
  s.summary          = 'napaxi AI Agent Engine SDK'
  s.description      = 'Flutter plugin providing napaxi AI Agent engine capabilities.'
  s.homepage         = 'https://github.com/napaxi/napaxi'
  # The plugin source is licensed under GPL-3.0-or-later. The shipped artifact
  # bundles third-party runtime components. See ../../../THIRD-PARTY-LICENSES.md
  # before redistributing.
  s.license          = { :type => 'GPL-3.0-or-later' }
  s.author           = { 'napaxi' => 'wenyu.mwt@antgroup.com' }
  s.source           = { :path => '.' }
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.static_framework = true

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386 arm64 x86_64',
    'HEADER_SEARCH_PATHS' => '$(inherited) $(PODS_TARGET_SRCROOT)/Vendor/IosQemu/Sources/QEMU $(PODS_TARGET_SRCROOT)/Vendor/IosQemu/Vendor/QEMU/include $(PODS_TARGET_SRCROOT)/Vendor/IosQemu/Vendor/QEMU/include/glib-2.0 $(PODS_TARGET_SRCROOT)/Vendor/IosQemu/Vendor/QEMU/lib/glib-2.0/include',
    'LIBRARY_SEARCH_PATHS[sdk=iphoneos*]' => '$(inherited) $(PODS_TARGET_SRCROOT)/Vendor/IosQemu/Vendor/QEMU/lib/iphoneos',
    'OTHER_SWIFT_FLAGS' => '$(inherited) -DNAPAXI_IOS_QEMU',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) NAPAXI_IOS_QEMU=1',
    'OTHER_LDFLAGS[sdk=iphoneos*]' => '$(inherited) -Wl,-force_load,$(PODS_TARGET_SRCROOT)/Vendor/IosQemu/Vendor/QEMU/lib/iphoneos/libqemu-aarch64-linux-user.a -Wl,-force_load,$(PODS_TARGET_SRCROOT)/Vendor/IosQemu/Vendor/QEMU/lib/iphoneos/libhwcore.a -lqemuutil -lqom -levent-loop-base -lglib-2.0 -lpcre2-8 -lintl -lffi -lz -lm -liconv',
  }
  s.user_target_xcconfig = {
    'LIBRARY_SEARCH_PATHS[sdk=iphoneos*]' => '$(inherited) $(PODS_ROOT)/../.symlinks/plugins/napaxi_flutter/ios/Vendor/IosQemu/Vendor/QEMU/lib/iphoneos',
    # Dart FFI resolves FRB symbols from DynamicLibrary.process() on iOS.
    # Force-load the Rust static library so those symbols are present in the
    # final app binary even though no native code calls them directly.
    'OTHER_LDFLAGS[sdk=iphoneos*]' => '$(inherited) -Wl,-force_load,$(PODS_ROOT)/../.symlinks/plugins/napaxi_flutter/ios/Frameworks/napaxi_api_bridge.xcframework/ios-arm64/libnapaxi_api_bridge.a -Wl,-force_load,$(PODS_ROOT)/../.symlinks/plugins/napaxi_flutter/ios/Vendor/IosQemu/Vendor/QEMU/lib/iphoneos/libqemu-aarch64-linux-user.a -Wl,-force_load,$(PODS_ROOT)/../.symlinks/plugins/napaxi_flutter/ios/Vendor/IosQemu/Vendor/QEMU/lib/iphoneos/libhwcore.a -lqemuutil -lqom -levent-loop-base -lglib-2.0 -lpcre2-8 -lintl -lffi -lz -lm -liconv',
    'STRIP_STYLE[sdk=iphoneos*]' => 'debugging',
  }
  s.swift_version = '5.0'

  # Source file that references a Rust symbol to force the linker to include
  # the entire static library (dart:ffi uses dlsym at runtime).
  s.source_files = 'Classes/**/*', 'Vendor/IosQemu/Sources/QEMU/*.{h,c}'
  s.public_header_files = 'Vendor/IosQemu/Sources/QEMU/qemu_bridge.h'
  s.preserve_paths = 'Vendor/IosQemu/Vendor/QEMU/**/*'

  # Rust compiled xcframework
  s.vendored_frameworks = 'Frameworks/napaxi_api_bridge.xcframework'

  # iOS QEMU sandbox bootstrap archive. This is the lightweight iOS rootfs
  # profile, not Android's full APK-build rootfs.
  s.resources = 'Resources/alpine-rootfs.bin'
end
