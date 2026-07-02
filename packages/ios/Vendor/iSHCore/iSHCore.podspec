Pod::Spec.new do |s|
  s.name = 'iSHCore'
  s.version = '0.3.0'
  s.summary = 'Vendored iSHCore runtime for local Napaxi iOS development.'
  s.homepage = 'https://github.com/ish-app/ish'
  s.license = { :type => 'GPL-3.0', :file => 'THIRD-PARTY.md' }
  s.author = { 'iSH' => 'https://github.com/ish-app/ish' }
  s.source = { :path => '.' }
  s.platform = :ios, '15.0'
  s.static_framework = true
  s.header_mappings_dir = 'include'
  s.public_header_files = 'include/**/*.h'
  s.vendored_libraries = 'lib/*.a'
  s.libraries = ['archive', 'bz2', 'iconv', 'z']
  s.preserve_paths = ['include/**/*', 'lib/**/*', 'THIRD-PARTY.md']
end
