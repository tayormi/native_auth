Pod::Spec.new do |s|
  s.name = 'native_auth'
  s.version = '0.1.0'
  s.summary = 'Native biometric authentication for DartNative.'
  s.description = s.summary
  s.homepage = 'https://github.com/tayormi/native_auth'
  s.license = { :type => 'MIT', :file => '../LICENSE' }
  s.author = 'Native Auth contributors'
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*.swift'
  s.platform = :ios, '15.0'
  s.swift_version = '5.9'
  s.static_framework = true
  s.frameworks = 'Foundation', 'UIKit', 'LocalAuthentication'
  s.user_target_xcconfig = { 'OTHER_LDFLAGS' => '$(inherited) -Wl,-u,_DnauthRequest -Wl,-u,_DnauthFree' }
end
