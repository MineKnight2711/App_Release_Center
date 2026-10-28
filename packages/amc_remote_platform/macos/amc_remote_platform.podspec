Pod::Spec.new do |s|
  s.name = 'amc_remote_platform'
  s.version = '0.0.1'
  s.summary = 'AMC remote desktop native adapter.'
  s.description = 'Permissions and session-scoped input for AMC.'
  s.homepage = 'https://example.invalid/amc-local-plugin'
  s.license = { :type => 'Proprietary' }
  s.author = 'AMC'
  s.source = { :path => '.' }
  s.source_files = 'amc_remote_platform/Sources/amc_remote_platform/**/*.swift'
  s.dependency 'FlutterMacOS'
  s.osx.deployment_target = '12.0'
  s.swift_version = '5.0'
end
