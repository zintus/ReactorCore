platform :ios, '9.0'

inhibit_all_warnings!

target 'Workflows' do
  use_frameworks!

  pod 'ReactiveSwift'
  pod 'ReactiveCocoa'
  
  pod 'ReactorCore', :path => './ReactorCore'

  pod 'SwiftFormat/CLI'

  target 'WorkflowsTests' do
      inherit! :search_paths
  end
end
