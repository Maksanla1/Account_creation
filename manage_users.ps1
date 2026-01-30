<#
.SYNOPSIS
    Loeb CSV faili ja voimaldab kasutajaid arvutisse lisada voi kustutada.
.DESCRIPTION
    Universaalne skript (PowerShell 5.1 & 7.x).
    Kustutamisel naitab KOIKI kasutajaid, valja arvatud praegust sisselogitud kasutajat.
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
    Write-Warning "CSV faili '$CsvFail' ei leitud. Lisamine ei toota, kuid kustutamine tootab."
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
    Write-Host "[K] Kustuta uks kasutaja (Nae koiki)"
    Write-Host "[X] Katkesta / Lopeta too"
    
    $Valik = Read-Host "Sinu valik"

    # --- LISAMINE ---
    if ($Valik -match "^(l|L)$") {
        if ($CsvAndmed.Count -eq 0) { Write-Warning "CSV fail puudub voi on tuhi."; Start-Sleep 2; continue }

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

    # --- KUSTUTAMINE (UUENDATUD: Näitab kõiki peale iseenda) ---
    elseif ($Valik -match "^(k|K)$") {
        
        $KustutaJatka = $true
        
        while ($KustutaJatka) {
            Clear-Host
            Write-Host "--- KUSTUTAMINE (Kõik kasutajad) ---" -ForegroundColor Yellow
            
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
                # Fallback CMD
                Write-Warning "Get-LocalUser ei tootnud. Proovi nime sisestada kasitsi."
            }
            
            # 2. Näitame nimekirja
            if ($KõikKasutajad.Count -gt 0) {
                for ($i=0; $i -lt $KõikKasutajad.Count; $i++) {
                    Write-Host "[$($i+1)] $($KõikKasutajad[$i].Name)"
                }
            } else {
                Write-Host "Ei leitud uhtegi kustutatavat kasutajat."
            }
           
            Write-Host "[X] Katkesta ja mine tagasi"

            $KustutaValik = Read-Host "`nSisesta number voi kasutaja nimi"

            if ($KustutaValik -match "^(x|X)$") {
                $KustutaJatka = $false
            }
            else {
                $ValitudNimi = ""
                # Number valik
                if ($KustutaValik -match '^\d+$' -and $KõikKasutajad.Count -gt 0) {
                    if ([int]$KustutaValik -ge 1 -and [int]$KustutaValik -le $KõikKasutajad.Count) {
                        $ValitudNimi = $KõikKasutajad[[int]$KustutaValik - 1].Name
                    }
                } 
                # Nime valik (käsitsi kirjutatud)
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
                        else { Write-Error "Ei saanud kasutajat '$ValitudNimi' kustutada." }
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
