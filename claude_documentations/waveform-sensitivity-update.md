# Waveform Sensitivity Update

**Tarih:** 2026-03-01

## Sorun
Overlay ekranındaki ses dalgası (waveform) görselleştirmesi, normal konuşma seviyesinde çok küçük çubuklar gösteriyordu. Kullanıcının bağırması gerekiyordu ki dalgalanma görünür olsun.

## Çözüm
İki aşamalı iyileştirme yapıldı:

### 1. Güçlendirilmiş Ses Seviyesi İşleme (AudioRecorder)
Ham RMS değerine power curve uygulandı:

**Öncesi:**
```swift
onLevel?(rms) // Ham RMS direkt gönderiliyordu
```

**Sonrası:**
```swift
let boosted = powf(rms * mult, exp) // Power curve ile güçlendirme
onLevel?(boosted)
```

### 2. Ayarlanabilir Waveform Parametreleri (SettingsManager + UI)
3 parametre Advanced sekmesine slider olarak eklendi:

| Parametre | Varsayılan | Aralık | Açıklama |
|---|---|---|---|
| **Multiplier** | 100 | 100-2000 | RMS çarpanı (yüksek = daha hassas) |
| **Exponent** | 0.45 | 0.05-0.50 | Üs değeri (düşük = düşük sesleri daha çok büyütür) |
| **Divisor** | 1.00 | 0.10-1.00 | WaveformView normalizasyon böleni |

### Formül
```
AudioRecorder: boosted = pow(rms × multiplier, exponent)
WaveformView:  normalized = min(boosted × weight[i] / divisor, 1.0)
```

## Değişen Dosyalar
- `desktop/SpeechToText/main.swift`:
  - `SettingsManager`: 3 yeni @Published property (waveMultiplier, waveExponent, waveDivisor)
  - `AudioRecorder.startRecording()`: Power curve boost eklendi
  - `WaveformView.updateLevel()`: Dinamik bölen kullanımı
  - `AdvancedTab`: "Waveform Sensitivity" UI bölümü eklendi
