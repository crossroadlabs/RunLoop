Pod::Spec.new do |s|
  s.name         = "RunLoop"
  s.version      = "0.1.1"
  s.license      = { :type => "Apache 2", :file => "LICENSE" }
  s.summary      = "Swift run loops with different underlying implementations"
  s.homepage     = "https://github.com/reactive-swift/RunLoop"
  s.social_media_url = "https://github.com/reactive-swift/RunLoop"
  s.authors = { "Daniel Leping" => "daniel@crossroadlabs.xyz" }
  
  s.source = { :git => "https://github.com/reactive-swift/RunLoop.git", :tag => "#{s.version}" }
  
  s.platform = :ios, :watchos, :tvos

  s.ios.deployment_target = "8.0"
  # s.osx.deployment_target = "10.10"
  s.watchos.deployment_target = "2.0"
  s.tvos.deployment_target = "9.0"

  s.source_files = "RunLoop/*.swift", 
  s.ios.exclude_files = "RunLoop/UVRunLoop.swift"
  s.watchos.exclude_files = "RunLoop/UVRunLoop.swift"
  s.tvos.exclude_files = "RunLoop/UVRunLoop.swift"

  s.ios.pod_target_xcconfig = { 'OTHER_SWIFT_FLAGS' => '-Dnouv' }
  s.watchos.pod_target_xcconfig = { 'OTHER_SWIFT_FLAGS' => '-Dnouv' }
  s.tvos.pod_target_xcconfig = { 'OTHER_SWIFT_FLAGS' => '-Dnouv' }

  s.dependency 'Boilerplate', '~> 0.1.0'
  s.dependency 'Foundation3', '~> 0.1.1'
  
  s.requires_arc = true

end