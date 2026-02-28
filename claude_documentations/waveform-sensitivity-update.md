# Waveform Sensitivity Update

**Tarih:** 2026-02-28

## Sorun
Overlay ekranındaki ses dalgası (waveform) görselleştirmesi, normal konuşma seviyesinde çok küçük çubuklar gösteriyordu. Kullanıcının bağırması gerekiyordu ki dalgalanma görünür olsun.

## Kök Neden
`WaveformView.updateLevel()` fonksiyonunda ses seviyesi (RMS) `0.15` değerine bölünerek normalize ediliyordu. Normal konuşma RMS değeri genellikle `0.01-0.05` arasında olduğundan, çubuklar maksimum yüksekliğin yalnızca %7-33'üne ulaşabiliyordu.

## Çözüm
Normalizasyon böleni `0.15`'ten `0.04`'e düşürüldü (~3.75x hassasiyet artışı).

**Dosya:** `desktop/SpeechToText/main.swift` - `WaveformView` sınıfı, `updateLevel()` metodu

**Öncesi:**
```swift
let normalized = min(level * weights[i] / 0.15, 1.0)
```

**Sonrası:**
```swift
let normalized = min(level * weights[i] / 0.04, 1.0)
```

## Etki
| Senaryo | Tahmini RMS | Önceki Çubuk Yüksekliği | Yeni Çubuk Yüksekliği |
|---|---|---|---|
| Fısıltı | ~0.005 | %3 | %12 |
| Normal konuşma | ~0.02 | %13 | %50 |
| Yüksek sesle konuşma | ~0.05 | %33 | %100 |
| Bağırma | ~0.10+ | %67 | %100 (clamp) |

`min(..., 1.0)` ile üst sınır korunduğundan, yüksek seslerde taşma olmaz.
