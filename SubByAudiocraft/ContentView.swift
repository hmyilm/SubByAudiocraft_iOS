import SwiftUI
import PhotosUI

struct ContentView: View {
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var statusMessage: String = "Video Seçin"
    @State private var isProcessing: Bool = false
    @State private var segments: [String] = [] // Will hold Whisper results
    
    // Config
    @State private var fontName: String = "Georgia"
    @State private var fontSize: String = "70"
    @State private var marginV: String = "1250"
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    Text("Sub by Audiocraft")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .padding(.top)
                    
                    // 1. Video Seçimi
                    VStack(alignment: .leading, spacing: 12) {
                        Text("1. Video ve Ayarlar")
                            .font(.headline)
                        
                        PhotosPicker(selection: $selectedItem, matching: .videos, photoLibrary: .shared()) {
                            HStack {
                                Image(systemName: "video.fill")
                                Text(selectedItem == nil ? "Galeriden Video Seç" : "Video Seçildi ✓")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .onChange(of: selectedItem) { newValue in
                            if newValue != nil {
                                statusMessage = "Video yüklendi. Ayarları yapıp analiz edebilirsiniz."
                            }
                        }
                        
                        // Ayarlar
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Yazı Tipi")
                                    .font(.caption)
                                TextField("Georgia", text: $fontName)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }
                            VStack(alignment: .leading) {
                                Text("Boyut")
                                    .font(.caption)
                                TextField("70", text: $fontSize)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }
                            VStack(alignment: .leading) {
                                Text("MarginV")
                                    .font(.caption)
                                TextField("1250", text: $marginV)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }
                        }
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(16)
                    
                    // 2. Analiz Butonu
                    Button(action: startAnalysis) {
                        if isProcessing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.purple)
                                .cornerRadius(12)
                        } else {
                            Text("Videoyu Analiz Et (Whisper)")
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                    .disabled(selectedItem == nil || isProcessing)
                    
                    // Durum
                    Text(statusMessage)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                    
                }
                .padding()
            }
            .navigationBarHidden(true)
        }
    }
    
    func startAnalysis() {
        guard let _ = selectedItem else { return }
        isProcessing = true
        statusMessage = "Yapay zeka analiz ediyor... (Bu işlem cihazda yapılıyor, internet gerektirmez)"
        
        // Burada WhisperManager ve VideoProcessor devreye girecek.
        // Şimdilik simüle ediyoruz:
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.isProcessing = false
            self.statusMessage = "Analiz bitti! Sözleri düzenleyebilirsiniz."
            self.segments = ["Test kelimesi 1", "Test kelimesi 2"]
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .preferredColorScheme(.dark)
    }
}
