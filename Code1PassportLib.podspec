#
# Be sure to run `pod lib lint Code1PassportLib.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'Code1PassportLib'
  s.version          = '0.1.12'
  s.summary          = 'Code1System Passport Module.'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
TODO: Add long description of the pod here.
                       DESC

  s.homepage         = 'https://github.com/code1hong/Code1PassportLib'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'code1hong' => 'code1hong@gmail.com' }
  s.source           = { :git => 'https://github.com/code1hong/Code1PassportLib.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '10.0'

  s.source_files = 'Code1PassportLib/Classes/**/*'
  
  s.swift_version = '5.0'
  
  s.static_framework = true
  s.dependency 'TensorFlowLiteSwift', '~> 2.3.0'
  s.dependency 'CryptoSwift', '~> 1.3.8'

  # s.resources = "Code1Passport/*.{png,jpeg,jpg,storyboard,xib,xcassets,lic,tflite,txt}"
  
#  s.resources = ["Code1PassportLib/res/passport_s-fp16.tflite", "Code1PassportLib/res/*.{storyboard, tflite, txt}", "classes.txt"]
  s.resources = ["Code1PassportLib/res/passport_s-fp16.tflite", "Code1PassportLib/res/classes.txt", "Code1PassportLib/res/Live.storyboard", "Code1PassportLib/res/nationality.txt", "Code1PassportLib/res/Code1License.lic", "Code1PassportLib/res/camera_icon_pressed.png", "Code1PassportLib/res/pp_guide.png"]

#  s.resources = "Resources/**/*.{tflite, txt,storyboard}"
  
  s.pod_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64'}
  s.user_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64'}
  
  # s.resource_bundles = {
  #   'Code1PassportLib' => ['Code1PassportLib/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  # s.dependency 'AFNetworking', '~> 2.3'
end
