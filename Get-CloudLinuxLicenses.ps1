# Parametreler
param(
    [string]$ServerListFile = "servers.txt",
    [string]$OutputFile = "cloudlinux_licenses.txt",
    [int]$SSHPort = ssh portu
)

Write-Host "CloudLinux Lisans Kontrol Scripti baslatiliyor..." -ForegroundColor Green
Write-Host "Parametreler yuklendi" -ForegroundColor Yellow

# Sunucu listesi dosyasini kontrol et
if (-not (Test-Path $ServerListFile)) {
    Write-Host "Hata: $ServerListFile dosyasi bulunamadi!" -ForegroundColor Red
    exit 1
}

Write-Host "Sunucu dosyasi bulundu" -ForegroundColor Green

# Sunucu listesini oku
$servers = Get-Content $ServerListFile | Where-Object { $_.Trim() -ne "" }
Write-Host "Toplam sunucu sayisi: $($servers.Count)" -ForegroundColor Cyan

# Posh-SSH modulunu kontrol et ve yukle
if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
    Write-Host "Posh-SSH modulu yukleniyor..." -ForegroundColor Yellow
    try {
        Install-Module -Name Posh-SSH -Force -Scope CurrentUser
        Write-Host "Posh-SSH modulu basariyla yuklendi" -ForegroundColor Green
    }
    catch {
        Write-Host "Hata: Posh-SSH modulu yuklenemedi: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

Import-Module Posh-SSH
Write-Host "Posh-SSH modulu yuklendi" -ForegroundColor Green

# SSH sifrelerini hazirla (test icin)
$passwords = @()
$passwords += ConvertTo-SecureString "sunucu şifresi 1" -AsPlainText -Force
$passwords += ConvertTo-SecureString "sunucu şifresi 2" -AsPlainText -Force

Write-Host "Sifre sayisi: $($passwords.Count)" -ForegroundColor Green

# Sonuc dosyasini olustur
$timestamp = Get-Date -Format "MM/dd/yyyy HH:mm:ss"
"CloudLinux Lisans Kontrol Sonuclari - $timestamp" | Out-File -FilePath $OutputFile -Encoding UTF8
"=" * 60 | Out-File -FilePath $OutputFile -Append -Encoding UTF8
"" | Out-File -FilePath $OutputFile -Append -Encoding UTF8

Write-Host "Sonuc dosyasi olusturuldu: $OutputFile" -ForegroundColor Green

# Sayaclar
$successCount = 0
$failCount = 0

Write-Host "Sunucu kontrolu baslatiliyor..." -ForegroundColor Cyan
Write-Host ""

# Tum sunuculari kontrol et
foreach ($server in $servers) {
    $server = $server.Trim()
    if ($server -eq "") { continue }
    
    Write-Host "Sunucu kontrol ediliyor: $server" -ForegroundColor White
    
    $connected = $false
    $session = $null
    
    # Her sifre ile deneme yap
    foreach ($password in $passwords) {
        try {
            Write-Host "  Sifre deneniyor..." -ForegroundColor Gray
            $credential = New-Object System.Management.Automation.PSCredential("root", $password)
            $session = New-SSHSession -ComputerName $server -Port $SSHPort -Credential $credential -AcceptKey
            
            if ($session) {
                Write-Host "  SSH baglantisi basarili!" -ForegroundColor Green
                $connected = $true
                break
            }
        }
        catch {
            Write-Host "  Sifre deneniyor..." -ForegroundColor Gray
            continue
        }
    }
    
    if (-not $connected) {
        Write-Host "  Baglanti kurulamadi" -ForegroundColor Red
        "$server - BAGLANTI HATASI" | Out-File -FilePath $OutputFile -Append -Encoding UTF8
        $failCount++
        continue
    }
    
    try {
        Write-Host "  CloudLinux lisans bilgileri aliniyor..." -ForegroundColor Yellow
        
        # CloudLinux lisans bilgilerini al
        $licenseInfo = ""
        
        # CloudLinux lisans durumunu kontrol et - birden fazla yontem dene
        $licenseId = "Bulunamadi"
        $licenseType = "Bulunamadi"
        $licenseStatus = "Bulunamadi"
        $productKey = "Bulunamadi"
        $foundLicense = $false
        
        # Yontem 1: rhn_check komutu (CloudLinux lisans durumu)
        $rhnResult = Invoke-SSHCommand -SessionId $session.SessionId -Command "rhn_check 2>/dev/null && echo 'RHN_SUCCESS' || echo 'RHN_FAILED'"
        if ($rhnResult.Output -match "RHN_SUCCESS") {
            $licenseType = "CloudLinux OS"
            $licenseStatus = "Active"
            $foundLicense = $true
            
            # Lisans ID'sini almaya calis
            $rhnIdResult = Invoke-SSHCommand -SessionId $session.SessionId -Command "cat /etc/sysconfig/rhn/systemid 2>/dev/null | grep -o 'ID-[0-9]*' | head -1"
            if ($rhnIdResult.ExitStatus -eq 0 -and $rhnIdResult.Output) {
                $licenseId = ($rhnIdResult.Output -join "").Trim()
            }
            
            # Product Key'i almaya calis - birden fazla yontem
            # Yontem 1: clnreg_ks --get-key
            $productKeyResult1 = Invoke-SSHCommand -SessionId $session.SessionId -Command "clnreg_ks --get-key 2>/dev/null"
            if ($productKeyResult1.ExitStatus -eq 0 -and $productKeyResult1.Output) {
                $keyOutput1 = ($productKeyResult1.Output -join "").Trim()
                if ($keyOutput1 -match "([A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4})") {
                    $productKey = $matches[1]
                } elseif ($keyOutput1 -ne "" -and $keyOutput1 -notmatch "not found|error|command|exited") {
                    $productKey = $keyOutput1
                }
            }
            
            # Yontem 2: /etc/sysconfig/cloudlinux dosyasından
            if ($productKey -eq "Bulunamadi") {
                $productKeyResult2 = Invoke-SSHCommand -SessionId $session.SessionId -Command "cat /etc/sysconfig/cloudlinux 2>/dev/null | grep -E 'LICENSE_KEY|ACTIVATION_KEY' | head -1"
                if ($productKeyResult2.ExitStatus -eq 0 -and $productKeyResult2.Output) {
                    $keyOutput2 = ($productKeyResult2.Output -join "").Trim()
                    if ($keyOutput2 -match "LICENSE_KEY=([^\s]+)") {
                        $productKey = $matches[1]
                    } elseif ($keyOutput2 -match "ACTIVATION_KEY=([^\s]+)") {
                        $productKey = $matches[1]
                    }
                }
            }
            
            # Yontem 3: rhn-profile-sync ile lisans bilgisi
            if ($productKey -eq "Bulunamadi") {
                $productKeyResult3 = Invoke-SSHCommand -SessionId $session.SessionId -Command "cat /etc/sysconfig/rhn/systemid 2>/dev/null | grep -o '<value><string>[^<]*</string></value>' | head -2 | tail -1 | sed 's/<[^>]*>//g'"
                if ($productKeyResult3.ExitStatus -eq 0 -and $productKeyResult3.Output) {
                    $keyOutput3 = ($productKeyResult3.Output -join "").Trim()
                    if ($keyOutput3 -ne "" -and $keyOutput3 -notmatch "not found|error") {
                        $productKey = $keyOutput3
                    }
                }
            }
        }
        
        # Yontem 1b: cloudlinux-config komutu
        if (-not $foundLicense) {
            $clConfigResult = Invoke-SSHCommand -SessionId $session.SessionId -Command "cloudlinux-config get --json 2>/dev/null"
            if ($clConfigResult.ExitStatus -eq 0 -and $clConfigResult.Output) {
                $configOutput = $clConfigResult.Output -join ""
                if ($configOutput -match '"license_type":\s*"([^"]+)"') {
                    $licenseType = $matches[1]
                    $foundLicense = $true
                }
                if ($configOutput -match '"license_id":\s*"([^"]+)"') {
                    $licenseId = $matches[1]
                }
                if ($configOutput -match '"license_status":\s*"([^"]+)"') {
                    $licenseStatus = $matches[1]
                }
                if ($configOutput -match '"license_key":\s*"([^"]+)"') {
                    $productKey = $matches[1]
                }
            }
        }
        
        # Yontem 2: clnreg_ks komutu
        if (-not $foundLicense) {
            $clnRegResult = Invoke-SSHCommand -SessionId $session.SessionId -Command "clnreg_ks --info 2>/dev/null"
            if ($clnRegResult.ExitStatus -eq 0 -and $clnRegResult.Output) {
                $regOutput = $clnRegResult.Output -join " "
                if ($regOutput -match "License ID:\s*(\S+)") {
                    $licenseId = $matches[1]
                    $foundLicense = $true
                }
                if ($regOutput -match "License type:\s*([^\n]+)") {
                    $licenseType = $matches[1].Trim()
                }
                if ($regOutput -match "License status:\s*([^\n]+)") {
                    $licenseStatus = $matches[1].Trim()
                }
                if ($regOutput -match "License key:\s*([^\n]+)") {
                    $productKey = $matches[1].Trim()
                }
            }
        }
        
        # Yontem 3: /etc/sysconfig/cloudlinux dosyasini kontrol et
        if (-not $foundLicense) {
            $configFileResult = Invoke-SSHCommand -SessionId $session.SessionId -Command "cat /etc/sysconfig/cloudlinux 2>/dev/null | grep -E '(LICENSE|KEY)'"
            if ($configFileResult.ExitStatus -eq 0 -and $configFileResult.Output) {
                $configContent = $configFileResult.Output -join " "
                if ($configContent -match "LICENSE_KEY=([^\s]+)") {
                    $productKey = $matches[1]
                    $licenseType = "CloudLinux OS"
                    $licenseStatus = "Configured"
                    $foundLicense = $true
                }
            }
        }
        
        if ($foundLicense) {
                
            Write-Host "  CloudLinux lisans bilgileri alindi" -ForegroundColor Green
            Write-Host "    IP: $server | Lisans ID: $licenseId | Tip: $licenseType | Durum: $licenseStatus | Product Key: $productKey" -ForegroundColor Cyan
            
            "IP: $server | Lisans ID: $licenseId | Tip: $licenseType | Durum: $licenseStatus | Product Key: $productKey" | Out-File -FilePath $OutputFile -Append -Encoding UTF8
            $successCount++
        } else {
            # CloudLinux yuklu mu kontrol et
            $clnCheck = Invoke-SSHCommand -SessionId $session.SessionId -Command "which cloudlinux-config 2>/dev/null || ls /usr/bin/cloudlinux* 2>/dev/null || ls /etc/cloudlinux* 2>/dev/null"
            
            if ($clnCheck.ExitStatus -eq 0 -and $clnCheck.Output) {
                Write-Host "  CloudLinux yuklu ama lisans bilgisi alinamadi" -ForegroundColor Yellow
                "IP: $server | Lisans ID: Bulunamadi | Tip: Bulunamadi | Durum: Bulunamadi | Product Key: Bulunamadi" | Out-File -FilePath $OutputFile -Append -Encoding UTF8
                $successCount++
            } else {
                Write-Host "  CloudLinux yuklu degil" -ForegroundColor Yellow
                "$server - CLOUDLINUX YUKLU DEGIL" | Out-File -FilePath $OutputFile -Append -Encoding UTF8
                $failCount++
            }
        }
    }
    catch {
        Write-Host "  Hata: $($_.Exception.Message)" -ForegroundColor Red
        "$server - HATA: $($_.Exception.Message)" | Out-File -FilePath $OutputFile -Append -Encoding UTF8
        $failCount++
    }
    finally {
        # SSH oturumunu kapat
        if ($session) {
            Remove-SSHSession -SessionId $session.SessionId | Out-Null
        }
    }
    
    Write-Host ""
}

# Ozet
"" | Out-File -FilePath $OutputFile -Append -Encoding UTF8
"OZET:" | Out-File -FilePath $OutputFile -Append -Encoding UTF8
"Basarili: $successCount" | Out-File -FilePath $OutputFile -Append -Encoding UTF8
"Basarisiz: $failCount" | Out-File -FilePath $OutputFile -Append -Encoding UTF8
"Test Tarihi: $(Get-Date -Format 'MM/dd/yyyy HH:mm:ss')" | Out-File -FilePath $OutputFile -Append -Encoding UTF8

Write-Host "=" * 50 -ForegroundColor Green
Write-Host "CloudLinux lisans kontrolu tamamlandi!" -ForegroundColor Green
Write-Host "Basarili: $successCount" -ForegroundColor Green
Write-Host "Basarisiz: $failCount" -ForegroundColor Red
Write-Host "Sonuclar: $OutputFile" -ForegroundColor Cyan
Write-Host "=" * 50 -ForegroundColor Green