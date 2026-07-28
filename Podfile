platform :ios, '16.0'
use_frameworks!

target 'SubByAudiocraft' do
  pod 'ffmpeg-kit-ios-full', :podspec => 'https://raw.githubusercontent.com/luthviar/ffmpeg-kit-ios-full/main/ffmpeg-kit-ios-full.podspec'

  # Test paketi @testable import ile uygulama modülünü yükler. Xcode 26'nın explicit
  # module denetimi sırasında uygulamanın ffmpegkit bağımlılığını da çözebilmesi için
  # ana hedefin framework/header arama yollarını test hedefine aktar.
  target 'SubByAudiocraftTests' do
    inherit! :search_paths
  end
end
