# LiteSpeedLisans Kontrol Araçları

Bu araçlar, birden fazla sunucudaki LiteSpeed Web Server lisans bilgilerini SSH üzerinden kontrol etmek için geliştirilmiştir.

## Özellikler

- Birden fazla sunucuya SSH bağlantısı
- Farklı şifrelerle otomatik deneme
- LiteSpeed lisans bilgilerini otomatik alma
- Sonuçları dosyaya kaydetme
- Detaylı hata raporlama

## Gereksinimler

- PowerShell 5.0 veya üzeri
- Posh-SSH modülü (script otomatik olarak yükler)
- SSH erişimi olan sunucular

## Dosya Yapısı

```
litespeed-license-check/
├── Get-LiteSpeedLicenses.ps1   # LiteSpeed lisans kontrol scripti
├── servers.txt                 # Sunucu IP listesi
├── README.md                   # Bu dosya
├── litespeed_licenses.txt      # LiteSpeed sonuç dosyası

```

## Kullanım

### 1. Sunucu Listesi Hazırlama

`servers.txt` dosyasına kontrol edilecek sunucu IP adreslerini her satıra bir tane olacak şekilde ekleyin:

```
ip1
ip2
ip3
```

### 2. Script'leri Çalıştırma

PowerShell'i yönetici olarak açın ve aşağıdaki komutları çalıştırın:

**LiteSpeed Lisans Kontrolü:**
```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Get-LiteSpeedLicenses.ps1
```
