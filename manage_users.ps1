<#
.SYNOPSIS
    Loeb CSV faili ja voimaldab kasutajaid arvutisse lisada voi kustutada.
.DESCRIPTION
    Universaalne skript (PowerShell 5.1 & 7.x).
    Parandatud kasutaja olemasolu kontroll.
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# --- 1. ADMIN KONTROLL ---
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]"Administrator"
)
if (-not $IsAdmin) {
    Write-Warning "VIGA: Seda skripti peab kaivitama ADMINISTRAATORI oigustes!"
    exit
}

# --- 2. FAILIDE LUGEMINE ---
$CsvFail = "new_users_accounts.csv"
if (Test-Path $CsvFail) {
    $CsvAndmed = Import-Csv -Path $CsvFail -Delimiter ";" -Encoding UTF8
} else {
    Write-Warning "CSV faili '$CsvFail' ei leitud. Lisamine ei toota."
    $CsvAndmed = @()
}

# --- PEATSÜKKEL (LOOP) ---
$Jatka = $true

while ($Jatka) {
    Clear-Host
    Write-Host "--- KASUTAJATE HALDUS (Universal Mode) ---" -ForegroundColor Cyan
    Write-Host "Tuvastatud versioon: $($PSVersionTable.PSVersion)" -ForegroundColor Gray
    Write-Host "Vali tegevus:"
    Write-Host "[L] Lisa koik kasutajad failist"
    Write-Host "[K] Kustuta uks kasutaja"
    Write-Host "[X] Katkesta / Lopeta too"
    
    $Valik = Read-Host "Sinu valik"

    # --- LISAMINE ---
    if ($Valik -match "^(l|L)$") {
        if ($CsvAndmed.Count -eq 0) { Write-Warning "CSV fail puudub voi on tuhi."; Start-Sleep 2; continue }

        Write-Host "`nAlustan kasutajate lisamist..." -ForegroundColor Yellow
        
        foreach ($Rida in $CsvAndmed) {
            $User = $Rida.Kasutajanimi
            
            # Lisa kontroll: Kui CSV rida on tühi või nimi puudub
            if ([string]::IsNullOrWhiteSpace($User)) { continue }

            $Pass = $Rida.Parool
            $FullName = "$($Rida.Eesnimi) $($Rida.Perenimi)"
            $Desc = $Rida.Kirjeldus

            if ($User.Length -gt 20) { Write-Warning "VIGA: '$User' nimi liiga pikk. Jatan vahele."; continue }
            if ($Desc.Length -gt 48) { $Desc = $Desc.Substring(0, 48) }
            
            # --- UUS KONTROLL: KAS KASUTAJA ON OLEMAS? ---
            $UserExists = $false
            try {
                # Proovime leida täpset vastet
                $Check = Get-LocalUser -Name $User -ErrorAction Stop
                if ($Check) { $UserExists = $true }
            } catch {
                # Kui Get-LocalUser viskab vea (nt "User not found" või Telemetry viga), siis eeldame et pole.
                # Igaks juhuks kontrollime vana 'net user' käsuga, aga PARANDATUD moel.
                
                # 'net user kasutajanimi' tagastab vea koodi 0 kui on olemas, 2 kui pole.
                $Null = net user $User 2>&1
                if ($LASTEXITCODE -eq 0) { $UserExists = $true }
            }

            if ($UserExists) { 
                Write-Warning "INFO: '$User' on juba olemas. Jatan vahele."
                continue 
            }

            # --- LOOMINE ---
            try {
                $SecurePass = ConvertTo-SecureString $Pass -AsPlainText -Force
                New-LocalUser -Name $User -Password $SecurePass -FullName $FullName -Description $Desc -ErrorAction Stop | Out-Null
                Add-LocalGroupMember -Group "Users" -Member $User
                $UserObj = [ADSI]"WinNT://./$User,user"; $UserObj.PasswordExpired = 1; $UserObj.SetInfo()
                Write-Host "OK (PS): Loodi kasutaja '$User'." -ForegroundColor Green
            }
            catch {
                # Kui PS käsk ebaõnnestus (nt Telemetry viga), proovime CMD käsku
                try {
                    $Null = & net user $User $Pass /ADD /FULLNAME:"$FullName" /COMMENT:"$Desc" /LOGONPASSWORDCHG:YES 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        $Null = & net localgroup Users $User /ADD 2>&1
                        Write-Host "OK (CMD): Loodi kasutaja '$User'." -ForegroundColor Green
                    } else {
                        Write-Error "Viga '$User' loomisel (CMD)."
                    }
                } catch { Write-Error "Kriitiline viga loomisel." }
            }
        }
        Write-Host "`nKasutajad said edukalt lisatud. Vajuta ENTER jatkamiseks..." -ForegroundColor Gray
        Read-Host
    }

    # --- KUSTUTAMINE (UUENDATUD: 'ALL DELETE' tugi) ---
    elseif ($Valik -match "^(k|K)$") {
        
        $KustutaJatka = $true
        
        while ($KustutaJatka) {
            Clear-Host
            Write-Host "--- KUSTUTAMINE ---" -ForegroundColor Yellow
            
            # 1. Leiame kasutajad (v.a. admin ja ise)
            $KõikKasutajad = @()
            try {
                $KõikKasutajad = Get-LocalUser | Where-Object { 
                    $_.Name -ne "Administrator" -and 
                    $_.Name -ne "Guest" -and 
                    $_.Name -notmatch "WDAG" -and
                    $_.Name -ne $env:USERNAME 
                }
            } catch {
                Write-Warning "Get-LocalUser ei tootnud. Proovi nime sisestada kasitsi."
            }
            
            # 2. Näitame nimekirja
            if ($KõikKasutajad.Count -gt 0) {
                for ($i=0; $i -lt $KõikKasutajad.Count; $i++) {
                    Write-Host "[$($i+1)] $($KõikKasutajad[$i].Name)"
                }
            } else {
                Write-Host "Ei leitud kustutatavat kasutajat."
            }
           
            Write-Host "[X] Katkesta ja mine tagasi"
            Write-Host "Kirjuta 'ALL' et kustutada nimekirjas olevad kasutajad korraga!" -ForegroundColor Red

            $KustutaValik = Read-Host "`nSisesta number, nimi voi 'ALL'"

            # --- VALIK 1: KATKESTA ---
            if ($KustutaValik -match "^(x|X)$") {
                $KustutaJatka = $false
            }
            # --- VALIK 2: KUSTUTA KÕIK (ALL DELETE) ---
            elseif ($KustutaValik -eq "ALL") {
                if ($KõikKasutajad.Count -gt 0) {
                    Write-Host "`nHOIATUS: Kustutan $($KõikKasutajad.Count) kasutajat..." -ForegroundColor Red
                    Start-Sleep 2
                    
                    foreach ($Kasutaja in $KõikKasutajad) {
                        $Nimi = $Kasutaja.Name
                        Write-Host "Kustutan: $Nimi..."
                        
                        # Kustuta konto
                        try {
                            Remove-LocalUser -Name $Nimi -ErrorAction Stop
                            Write-Host "  - Konto kustutatud" -ForegroundColor Green
                        } catch {
                            $Null = & net user $Nimi /DELETE 2>&1
                            if ($LASTEXITCODE -eq 0) { Write-Host "  - Konto kustutatud (CMD)" -ForegroundColor Green }
                            else { Write-Error "  - Viga konto kustutamisel" }
                        }

                        # Kustuta kaust
                        $KoduKaust = "C:\Users\$Nimi"
                        if (Test-Path $KoduKaust) {
                            Remove-Item -Path $KoduKaust -Recurse -Force -ErrorAction SilentlyContinue
                            Write-Host "  - Kodukaust kustutatud" -ForegroundColor Gray
                        }
                    }
                    Write-Host "`nValitud kasutajad on kustutatud!" -ForegroundColor Yellow
                    Start-Sleep 3
                } else {
                    Write-Warning "Pole kedagi kustutada."
                    Start-Sleep 2
                }
            }
            # --- VALIK 3: ÜKSIK KUSTUTAMINE (Number või Nimi) ---
            else {
                $ValitudNimi = ""
                # Number valik
                if ($KustutaValik -match '^\d+$' -and $KõikKasutajad.Count -gt 0) {
                    if ([int]$KustutaValik -ge 1 -and [int]$KustutaValik -le $KõikKasutajad.Count) {
                        $ValitudNimi = $KõikKasutajad[[int]$KustutaValik - 1].Name
                    }
                } 
                # Nime valik
                elseif ($KustutaValik.Length -gt 1) {
                    if ($KustutaValik -eq $env:USERNAME) {
                        Write-Warning "Sa ei saa kustutada iseennast!"
                        Start-Sleep 2
                        continue
                    }
                    $ValitudNimi = $KustutaValik
                }

                if ($ValitudNimi -ne "") {
                    Write-Host "Kustutan: $ValitudNimi..."
                    
                    try {
                        Remove-LocalUser -Name $ValitudNimi -ErrorAction Stop
                        Write-Host "Kasutaja konto kustutatud (PS)." -ForegroundColor Green
                    } catch {
                        $Null = & net user $ValitudNimi /DELETE 2>&1
                        if ($LASTEXITCODE -eq 0) { Write-Host "Kasutaja konto kustutatud (CMD)." -ForegroundColor Green }
                        else { Write-Error "Ei saanud kasutajat kustutada." }
                    }

                    $KoduKaust = "C:\Users\$ValitudNimi"
                    if (Test-Path $KoduKaust) {
                        Remove-Item -Path $KoduKaust -Recurse -Force -ErrorAction SilentlyContinue
                        Write-Host "Kodukaust kustutatud."
                    }
                    Start-Sleep -Seconds 1
                }
            }
        }
    }


    # --- KATKESTA ---
    elseif ($Valik -match "^(x|X)$") {
        $Jatka = $false
    }
}
