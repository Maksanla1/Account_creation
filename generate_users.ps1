<#
.SYNOPSIS
    Loeb CSV faili ja voimaldab kasutajaid arvutisse lisada voi kustutada.
.DESCRIPTION
    Universaalne skript (PowerShell 5.1 & 7.x).
    Kustutamisel kaitseb praegust sisselogitud kasutajat.
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
$CsvKasutajad = @()

if (Test-Path $CsvFail) {
    $CsvAndmed = Import-Csv -Path $CsvFail -Delimiter ";" -Encoding UTF8
    # Salvestame CSV-st saadud kasutajanimed eraldi nimekirja
    $CsvKasutajad = $CsvAndmed.Kasutajanimi
} else {
    Write-Warning "CSV faili '$CsvFail' ei leitud. Kustutamisel naidatakse koiki tavakasutajaid."
}

# --- PEATSÜKKEL (LOOP) ---
$Jatka = $true

while ($Jatka) {
    Clear-Host
    Write-Host "--- KASUTAJATE HALDUS (Universal Mode) ---" -ForegroundColor Cyan
    Write-Host "Tuvastatud versioon: $($PSVersionTable.PSVersion)" -ForegroundColor Gray
    Write-Host "Vali tegevus:"
    Write-Host "[L] Lisa koik kasutajad failist"
    Write-Host "[K] Kustuta uks kasutaja (CSV pohjal)"
    Write-Host "[X] Katkesta / Lopeta too"
    
    $Valik = Read-Host "Sinu valik"

    # --- LISAMINE ---
    if ($Valik -match "^(l|L)$") {
        if (-not $CsvAndmed) { Write-Warning "CSV fail puudub, ei saa lisada."; Start-Sleep 2; continue }

        Write-Host "`nAlustan kasutajate lisamist..." -ForegroundColor Yellow
        
        foreach ($Rida in $CsvAndmed) {
            $User = $Rida.Kasutajanimi
            $Pass = $Rida.Parool
            $FullName = "$($Rida.Eesnimi) $($Rida.Perenimi)"
            $Desc = $Rida.Kirjeldus

            if ($User.Length -gt 20) { Write-Warning "VIGA: '$User' nimi liiga pikk. Jatan vahele."; continue }
            if ($Desc.Length -gt 48) { $Desc = $Desc.Substring(0, 48) }
            
            $UserExists = $(net user $User 2>&1) -match "User name"
            if ($UserExists) { Write-Warning "INFO: '$User' on juba olemas. Jatan vahele."; continue }

            try {
                $SecurePass = ConvertTo-SecureString $Pass -AsPlainText -Force
                New-LocalUser -Name $User -Password $SecurePass -FullName $FullName -Description $Desc -ErrorAction Stop | Out-Null
                Add-LocalGroupMember -Group "Users" -Member $User
                $UserObj = [ADSI]"WinNT://./$User,user"; $UserObj.PasswordExpired = 1; $UserObj.SetInfo()
                Write-Host "OK (PS): Loodi kasutaja '$User'." -ForegroundColor Green
            }
            catch {
                # Fallback to NET USER
                try {
                    $Null = & net user $User $Pass /ADD /FULLNAME:"$FullName" /COMMENT:"$Desc" /LOGONPASSWORDCHG:YES 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        $Null = & net localgroup Users $User /ADD 2>&1
                        Write-Host "OK (CMD): Loodi kasutaja '$User'." -ForegroundColor Green
                    }
                } catch { Write-Error "Viga loomisel." }
            }
        }
        Write-Host "`nTegevus lopetatud. Vajuta ENTER jatkamiseks..." -ForegroundColor Gray
        Read-Host
    }

    # --- KUSTUTAMINE (UUENDATUD LOOGIKA) ---
    elseif ($Valik -match "^(k|K)$") {
        
        $KustutaJatka = $true
        
        while ($KustutaJatka) {
            Clear-Host
            Write-Host "--- KUSTUTAMINE ---" -ForegroundColor Yellow
            
            # 1. Leiame kõik süsteemi kasutajad
            $KõikKasutajad = @()
            try {
                $KõikKasutajad = Get-LocalUser | Where-Object { 
                    $_.Name -ne "Administrator" -and 
                    $_.Name -ne "Guest" -and 
                    $_.Name -notmatch "WDAG" -and
                    $_.Name -ne $env:USERNAME # VÄLISTAME PRAEGUSE KASUTAJA!
                }
            } catch {
                Write-Warning "Get-LocalUser ebaonnestus. Kasuta kasitsi sisestamist."
            }
            
            # 2. Filtreerime: Näitame ainult neid, kes olid ka CSV failis (kui CSV on olemas)
            #    Või kui CSV-d polnud, näitame kõiki peale enda.
            $Kustutatavad = @()
            
            if ($CsvKasutajad.Count -gt 0) {
                # Näita ainult neid, kes on päriselt arvutis olemas JA olid CSV-s
                $Kustutatavad = $KõikKasutajad | Where-Object { $CsvKasutajad -contains $_.Name }
            } else {
                # Kui CSV puudub, näita kõiki peale iseenda
                $Kustutatavad = $KõikKasutajad
            }

            if ($Kustutatavad.Count -gt 0) {
                Write-Host "Leitud genereeritud kasutajad:"
                for ($i=0; $i -lt $Kustutatavad.Count; $i++) {
                    Write-Host "[$($i+1)] $($Kustutatavad[$i].Name)"
                }
            } else {
                Write-Host "Ei leitud uhtegi CSV failist parit kasutajat (voi nimekiri on tuhi)."
            }
           
            Write-Host "[X] Katkesta ja mine tagasi"

            $KustutaValik = Read-Host "`nSisesta number voi kasutaja nimi"

            if ($KustutaValik -match "^(x|X)$") {
                $KustutaJatka = $false
            }
            else {
                $ValitudNimi = ""
                # Number valik
                if ($KustutaValik -match '^\d+$' -and $Kustutatavad.Count -gt 0) {
                    if ([int]$KustutaValik -ge 1 -and [int]$KustutaValik -le $Kustutatavad.Count) {
                        $ValitudNimi = $Kustutatavad[[int]$KustutaValik - 1].Name
                    }
                } 
                # Nime valik
                elseif ($KustutaValik.Length -gt 1) {
                    # Lisakontroll: Ära luba kustutada iseennast, isegi kui nimi kirjutatakse käsitsi
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
