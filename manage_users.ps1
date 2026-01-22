<#
.SYNOPSIS
    Loeb CSV faili ja voimaldab kasutajaid arvutisse lisada voi kustutada.
.DESCRIPTION
    Taanused:
    1. Kontrollib admin oigusi.
    2. Tookab tsuklis - parast tegevust saab valida uuesti.
    3. Lisab kasutaja ja sunnib parooli vahetust (ADSI meetodil).
    4. Kustutab kasutaja ja kodukausta.
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

# --- 2. FAILIDE KONTROLL ---
$CsvFail = "new_users_accounts.csv"
if (-not (Test-Path $CsvFail)) {
    Write-Error "CSV faili '$CsvFail' ei leitud! Kaivita enne esimene skript."
    exit
}
$CsvAndmed = Import-Csv -Path $CsvFail -Delimiter ";" -Encoding UTF8


# --- PEATSÜKKEL (LOOP) ---
$Jatka = $true

while ($Jatka) {
    Clear-Host
    Write-Host "--- KASUTAJATE HALDUS ---" -ForegroundColor Cyan
    Write-Host "Vali tegevus:"
    Write-Host "[L] Lisa koik kasutajad failist (ja sunni parooli vahetust)"
    Write-Host "[K] Kustuta uks kasutaja"
    Write-Host "[X] Katkesta / Lopeta too"
    
    $Valik = Read-Host "Sinu valik"

    # --- LISAMINE ---
    if ($Valik -match "^(l|L)$") {
        Write-Host "`nAlustan kasutajate lisamist..." -ForegroundColor Yellow
        
        foreach ($Rida in $CsvAndmed) {
            $User = $Rida.Kasutajanimi
            $Pass = $Rida.Parool
            $FullName = "$($Rida.Eesnimi) $($Rida.Perenimi)"
            $Desc = $Rida.Kirjeldus

            # Kontrollid
            if ($User.Length -gt 20) { Write-Warning "VIGA: '$User' nimi liiga pikk. Jatan vahele."; continue }
            if ($Desc.Length -gt 48) { Write-Warning "HOIATUS: '$User' kirjeldus luhikeseks loigatud."; $Desc = $Desc.Substring(0, 48) }
            if (Get-LocalUser -Name $User -ErrorAction SilentlyContinue) { Write-Warning "INFO: '$User' on juba olemas. Jatan vahele."; continue }

            try {
                $SecurePass = ConvertTo-SecureString $Pass -AsPlainText -Force
                
                # 1. Loome kasutaja (ilma parooli aegumise liputa, sest see tekitas vea)
                New-LocalUser -Name $User -Password $SecurePass -FullName $FullName -Description $Desc -ErrorAction Stop | Out-Null
                
                # 2. Lisame Users gruppi
                Add-LocalGroupMember -Group "Users" -Member $User
                
                # 3. MÄÄRAME PAROOLI VAHETUSE NÕUDE (Alternatiivne meetod: ADSI)
                # Kuna New-LocalUser parameeter puudus, kasutame vana head WinNT meetodit
                $UserObj = [ADSI]"WinNT://./$User,user"
                $UserObj.PasswordExpired = 1
                $UserObj.SetInfo()

                Write-Host "OK: Loodi kasutaja '$User'. (Parooli vahetus noutud)" -ForegroundColor Green
            }
            catch {
                Write-Error "VIGA '$User' loomisel: $($_.Exception.Message)"
            }
        }
        
        Write-Host "`nTegevus lopetatud. Vajuta ENTER jatkamiseks..." -ForegroundColor Gray
        Read-Host
    }

    # --- KUSTUTAMINE ---
    elseif ($Valik -match "^(k|K)$") {
        
        # Tsükkel kustutamise jaoks, et saaks kustutada mitut voi katkestada
        $KustutaJatka = $true
        
        while ($KustutaJatka) {
            Clear-Host
            Write-Host "--- KUSTUTAMINE ---" -ForegroundColor Yellow
            $SusteemiKasutajad = Get-LocalUser | Where-Object { $_.Name -ne "Administrator" -and $_.Name -ne "Guest" -and $_.Name -notmatch "WDAG" }
            
            if ($SusteemiKasutajad.Count -eq 0) {
                Write-Warning "Ei leitud kustutatavaid kasutajaid."
                $KustutaJatka = $false
                break
            }

            # Nimekiri
            for ($i=0; $i -lt $SusteemiKasutajad.Count; $i++) {
                Write-Host "[$($i+1)] $($SusteemiKasutajad[$i].Name)"
            }
            Write-Host "[X] Katkesta kustutamine ja mine tagasi peamenuusse"

            $KustutaValik = Read-Host "`nSisesta number keda kustutada (voi X)"

            if ($KustutaValik -match "^(x|X)$") {
                $KustutaJatka = $false
            }
            elseif ($KustutaValik -match '^\d+$' -and [int]$KustutaValik -ge 1 -and [int]$KustutaValik -le $SusteemiKasutajad.Count) {
                $ValitudNimi = $SusteemiKasutajad[[int]$KustutaValik - 1].Name
                
                Write-Host "Kustutan: $ValitudNimi..."
                Remove-LocalUser -Name $ValitudNimi -ErrorAction SilentlyContinue
                
                $KoduKaust = "C:\Users\$ValitudNimi"
                if (Test-Path $KoduKaust) {
                    Remove-Item -Path $KoduKaust -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Host "Kodukaust kustutatud."
                }
                
                Write-Host "Kasutaja kustutatud!" -ForegroundColor Green
                Start-Sleep -Seconds 1
                # Kustutamise tsükkel läheb edasi - küsib uuesti nimekirja
            } else {
                Write-Warning "Vigane valik!"
                Start-Sleep -Seconds 1
            }
        }
    }

    # --- KATKESTA ---
    elseif ($Valik -match "^(x|X)$") {
        Write-Host "Head aega!" -ForegroundColor Cyan
        $Jatka = $false
    }
    
    else {
        Write-Warning "Tundmatu valik."
        Start-Sleep -Seconds 1
    }
}
