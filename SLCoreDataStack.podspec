Pod::Spec.new do |spec|
  spec.name          = 'SLCoreDataStack'
  spec.version       = '1.0.9'
  spec.platforms      = { :ios => '8.0', :osx => '10.10', :tvos => '9.0', :watchos => '2.0' }
  spec.license       = 'MIT'
  spec.source        = { :git => 'https://github.com/OliverLetterer/SLCoreDataStack.git', :tag => spec.version.to_s }
  spec.source_files  = 'SLCoreDataStack'
  spec.frameworks    = 'Foundation', 'CoreData'
  spec.requires_arc  = true
  spec.homepage      = 'https://github.com/OliverLetterer/SLCoreDataStack'
  spec.summary       = 'CoreData stack boilerplate'
  spec.author        = { 'Oliver Letterer' => 'oliver.letterer@gmail.com' }
end
