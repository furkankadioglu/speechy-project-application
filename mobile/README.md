# Speechy iOS

whisper.cpp tabanlı iOS konuşma-yazı çevirici. Tamamen cihaz üzerinde çalışır, internet bağlantısı sadece model indirmek için gereklidir.

## Mimari

```
ContentView (TabView)
  ├── Kayıt Tab
  │     ├── ModelDownloadManager   (model indirme + CoreML kopyalama)
  │     └── WhisperTranscriber     (ViewModel)
  │           ├── AudioRecorderEngine  (AVAudioEngine, 16kHz mono)
  │           └── SwiftWhisper         (whisper.cpp Swift wrapper)
  └── Geçmiş Tab
        └── HistoryManager         (JSON persistence)
```

### Dosyalar

| Dosya | Açıklama |
|-------|----------|
| `SpeechyApp.swift` | Uygulama giriş noktası |
| `ContentView.swift` | Ana UI: TabView (kayıt + geçmiş), model indirme ekranı |
| `WhisperTranscriber.swift` | Ana ViewModel: model yükleme, kayıt, transkripsiyon, zamanlama |
| `ModelDownloadManager.swift` | HuggingFace'den model indirme, CoreML model kopyalama, dosya yönetimi |
| `AudioRecorderEngine.swift` | AVAudioEngine ile mikrofon kaydı, 16kHz mono float dönüşümü |
| `TranscriptionRecord.swift` | Transkripsiyon kayıt modeli (Codable) — kelime sayısı dahil |
| `HistoryManager.swift` | Geçmiş kayıtlarının JSON dosyasında saklanması |
| `HistoryView.swift` | Geçmiş kayıtları listesi UI |
| `ggml-small-encoder.mlmodelc/` | CoreML encoder modeli (Apple Neural Engine hızlandırma) |
| `Info.plist` | Mikrofon izin açıklaması |

## Gereksinimler

- Xcode 15.0+
- iOS 16.0+
- Fiziksel iPhone (simulator'da whisper çok yavaş)
- ~350 MB boş alan (181 MB model dosyası + 168 MB CoreML)

## Kurulum

```bash
cd mobile

# SPM bağımlılığını çöz
xcodebuild -resolvePackageDependencies -project Speechy.xcodeproj

# Derle (fiziksel cihaz için)
xcodebuild build -project Speechy.xcodeproj -scheme Speechy \
  -destination 'generic/platform=iOS'
```

## Testleri Çalıştırma

```bash
# Simulator'da unit testleri çalıştır
xcodebuild test -project Speechy.xcodeproj -scheme Speechy \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:SpeechyTests
```

### Test Kapsamı (38 test)

- **ModelDownloadManagerTests** (20 test): State yönetimi, dosya işlemleri, indirme callback'leri, CoreML
- **WhisperTranscriberTests** (10 test): State geçişleri, computed property'ler, clearTranscript
- **AudioRecorderEngineTests** (8 test): Başlangıç durumu, hata tipleri, stop davranışı

## Kullanım Akışı

1. Uygulama açılır, model kontrolü yapılır
2. Model yoksa indirme ekranı gösterilir (~181 MB, `ggml-small-q5_1.bin`)
3. Model indirildikten sonra CoreML encoder modeli bundle'dan Documents'a kopyalanır
4. Model arka planda yüklenir (CoreML Neural Engine otomatik algılanır)
5. Mikrofon butonuna basınca kayıt başlar
6. Tekrar basınca kayıt durur ve transkripsiyon başlar
7. Sonuç ekranda gösterilir, kopyalanabilir
8. Kayıt süresi, çeviri süresi ve kelime sayısı gösterilir
9. Tüm transkripsiyon geçmişi "Geçmiş" sekmesinde saklanır

## Model

- **Whisper Small (Q5_1)**: `ggml-small-q5_1.bin` (~181 MB, 244M parametre)
- **CoreML Encoder**: `ggml-small-encoder.mlmodelc` (~168 MB, app bundle'da)
- **Kaynak**: `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small-q5_1.bin`
- **Yerel dosya adı**: `ggml-small.bin` (CoreML isimlendirme uyumu için)
- **Dil**: Türkçe (varsayılan)
- **Depolama**: Uygulamanın Documents dizini

## Performans Optimizasyonları

| Optimizasyon | Etki | Durum |
|-------------|------|-------|
| CoreML Neural Engine | ~3-10x encoder hızlanma | Aktif |
| `greedy.best_of = 1` | ~5x decoder hızlanma | Aktif |
| Sessizlik kırpma | Değişken | Aktif |
| Token bastırma | Küçük hızlanma | Aktif |
| 6 thread | Küçük hızlanma | Aktif |
| ~~Dinamik `audio_ctx`~~ | — | Kaldırıldı (kalite kaybı) |
| ~~`temperature_inc = -1`~~ | — | Kaldırıldı (kalite kaybı) |
| ~~`single_segment`~~ | — | Kaldırıldı (kalite kaybı) |
| ~~`no_context`~~ | — | Kaldırıldı (kalite kaybı) |

> **Not:** Kaldırılan optimizasyonlar tek başına zararsız görünse de, birlikte uygulandığında decoder'a hata telafi şansı bırakmıyordu ve transkripsiyon kalitesini ciddi şekilde düşürüyordu. Hız optimizasyonu için compute-level çözümler (CoreML, thread) tercih edilmeli, decode kalitesini etkileyen parametreler değiştirilmemeli.

## CoreML Model Üretimi

CoreML encoder modeli tekrar üretmek gerekirse:

```bash
# Sanal ortam oluştur
python3 -m venv /tmp/whisper-coreml-env
source /tmp/whisper-coreml-env/bin/activate

# Bağımlılıkları kur
pip install openai-whisper coremltools ane_transformers

# SwiftWhisper checkout'undan modeli dönüştür
cd <DerivedData>/SourcePackages/checkouts/SwiftWhisper/whisper.cpp/models/
python3 convert-whisper-to-coreml.py --model small

# Derle
xcrun coremlc compile models/coreml-encoder-small.mlpackage models/

# Sonuç: models/ggml-small-encoder.mlmodelc (~168MB)
# Bu dizini Speechy/ altına kopyala
```

## Bağımlılıklar

- [SwiftWhisper](https://github.com/exPHAT/SwiftWhisper) v1.2.0 - whisper.cpp v1.4.2 Swift wrapper (SPM)
