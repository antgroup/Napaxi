Pod::Spec.new do |s|
  s.name             = 'napaxi_flutter'
  s.version          = '0.1.1'
  s.summary          = 'napaxi AI Agent Engine SDK'
  s.description      = 'Flutter plugin providing napaxi AI Agent engine capabilities.'
  s.homepage         = 'https://github.com/napaxi/napaxi'
  # The plugin's own source is MIT. The shipped artifact statically links the
  # GPL-licensed `iSHCore` pod (below) and bundles other third-party runtime
  # components; the effective obligations on a distributed app are broader than
  # MIT. See ../../../THIRD-PARTY-LICENSES.md before redistributing.
  s.license          = { :type => 'MIT' }
  s.author           = { 'napaxi' => 'wenyu.mwt@antgroup.com' }
  s.source           = { :path => '.' }
  s.dependency 'Flutter'
  s.dependency 'iSHCore', '0.3.0'
  s.platform = :ios, '13.0'
  s.static_framework = true

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'HEADER_SEARCH_PATHS' => '$(inherited) $(PODS_ROOT)/iSHCore/include',
  }
  s.user_target_xcconfig = {
    # Dart FFI resolves FRB symbols from DynamicLibrary.process() on iOS.
    # Force-load the Rust static library so those symbols are present in the
    # final app binary even though no native code calls them directly.
    'OTHER_LDFLAGS[sdk=iphoneos*]' => '$(inherited) -Wl,-force_load,$(PODS_ROOT)/../.symlinks/plugins/napaxi_flutter/ios/Frameworks/napaxi_api_bridge.xcframework/ios-arm64/libnapaxi_api_bridge.a',
    'STRIP_STYLE[sdk=iphoneos*]' => 'debugging',
  }
  s.swift_version = '5.0'

  # Source file that references a Rust symbol to force the linker to include
  # the entire static library (dart:ffi uses dlsym at runtime).
  s.source_files = 'Classes/**/*'

  # Rust compiled xcframework
  s.vendored_frameworks = 'Frameworks/napaxi_api_bridge.xcframework'

  # iOS sandbox bootstrap archive. Keep a single source of truth under
  # packages/ios and copy it into the host app bundle for the Flutter adapter.
  s.resources = 'Resources/alpine-rootfs.tar.gz'
end
