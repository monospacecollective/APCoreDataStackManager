Pod::Spec.new do |s|
  s.name         = 'APCoreDataStackManager'
  s.version      = '0.0.1'
  s.license      = 'BSD'
  s.summary      = 'APCoreDataStackManager is a class that lets you set up a Core Data stack, using a local or ubiquitous persistent store.'
  s.homepage     = 'https://github.com/monospacecollective/APCoreDataStackManager'
  s.author       = { 'Axel Péju' => 'pejuaxel@me.com' }
  s.source       = { :git => 'https://github.com/monospacecollective/APCoreDataStackManager.git', :tag => '0.0.1' }
  s.source_files = 'APCoreDataStackManager.{h,m}'
	s.requires_arc = true
  s.platform     = :ios, '5.0'
end
