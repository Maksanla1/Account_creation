<#
.SYNOPSIS
    Loeb CSV faili ja voimaldab kasutajaid arvutisse lisada voi kustutada.
.DESCRIPTION
    Skript taisab jargmised ulesanded:
    1. Kontrollib administraatori oigusi.
    2. Pakub valikut: Lisa kasutajad voi Kustuta uks kasutaja.
    3. Lisamisel kontrollib nime pikkust, duplikaate ja kirjelduse pikkust.
    4. Loob kasutaja ja lisab gruppi "Users".
    5. Kustutamisel eemaldab nii kasutajakonto kui ka kodukausta.
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

# --- 2. CSV ANDMETE LUGEMINE ---
$CsvFail = "new_users_accounts.csv"

if (-not (Test-Path $CsvFail)) {
    Write-Error "CSV faili '$CsvFail' ei leitud! Kaivita enne esimene skript."
    exit
}

$CsvAndmed = Import-Csv -Path $CsvFail -Delimiter ";" -Encoding UTF8

# --- 3. MENUU ---
Clear-Host
Write-Host "--- KASUTAJATE HALDUS ---" -ForegroundColor Cyan
Write-Host "Vali tegevus:"
Write-Host "[L] Lisa koik kasutajad failist susteemi"
Write-Host "[K] Kustuta uks kasutaja susteemist"
$Valik = Read-Host "Sinu valik"

# --- LISAMINE ---
if ($Valik -match "^(l|L)$") {
    Write-Host "`nAlustan kasutajate lisamist..." -ForegroundColor Yellow
    
    foreach ($Rida in $CsvAndmed) {
        $User = $Rida.Kasutajanimi
        $Pass = $Rida.Parool
        $FullName = "$($Rida.Eesnimi) $($Rida.Perenimi)"
        $Desc = $Rida.Kirjeldus
        
        # 1) Kasutajanime pikkus
        if ($User.Length -gt 20) {
            Write-Warning "EI SAA LISADA '$User': Kasutajanimi on liiga pikk (>20 marki)."
            continue
        }

        # 2) Kirjelduse pikkus
        if ($Desc.Length -gt 48) {
            Write-Warning "HOIATUS '$User': Kirjeldus liiga pikk. Karbitud 48 margini."
            $Desc = $Desc.Substring(0, 48)
        }

        # 3) Duplikaat kasutaja
        if (Get-LocalUser -Name $User -ErrorAction SilentlyContinue) {
            Write-Warning "EI SAA LISADA '$User': Kasutaja on juba susteemis olemas (Duplikaat)."
            continue
        }

        try {
            # Parool SecureString kujule
            $SecurePass = ConvertTo-SecureString $Pass -AsPlainText -Force
            
            # LOOME KASUTAJA
            # Sinu versioonis ei toeta New-LocalUser parameetrit -PasswordChangeRequiredOnLogin,
            # seega seda ei kasuta, et vigu ei tekiks.
            New-LocalUser -Name $User `
                          -Password $SecurePass `
                          -FullName $FullName `
                          -Description $Desc `
                          -ErrorAction Stop | Out-Null
            
            # Lisame gruppi "Users"
            Add-LocalGroupMember -Group "Users" -Member $User

            Write-Host "OK: Loodi kasutaja '$User'." -ForegroundColor Green
            # Parooli vahetuse noue tuleks sinu versioonis vajadusel lahendada eraldi (nt manualne test).
        }
        catch {
            Write-Error "VIGA '$User' loomisel: $($_.Exception.Message)"
        }
    }

    # LOPPRAPORT – naitame ainult tavakasutajaid (mitte sisseehitatud kontosid)
    Write-Host "`n--- HETKEL ARVUTIS OLEVAD TAVAKASUTAJAD ---" -ForegroundColor Cyan
    Get-LocalUser | Where-Object { 
        $_.Enabled -eq $true -and 
        $_.Name -ne "Administrator" -and 
        $_.Name -ne "Guest" -and 
        $_.Name -notmatch "WDAGUtilityAccount" -and 
        $_.Name -notmatch "DefaultAccount"
    } | Select-Object Name, FullName, Description | Format-Table -AutoSize
}

# --- KUSTUTAMINE ---
elseif ($Valik -match "^(k|K)$") {
    
    $SusteemiKasutajad = Get-LocalUser | Where-Object { 
        $_.Name -ne "Administrator" -and 
        $_.Name -ne "Guest" -and 
        $_.Name -notmatch "WDAG"
    }
    
    if ($SusteemiKasutajad.Count -eq 0) {
        Write-Warning "Arvutis ei leitud uhtegi kustutatavat tavakasutajat."
        exit
    }

    Write-Host "`n--- VALI KASUTAJA KUSTUTAMISEKS ---" -ForegroundColor Cyan
    for ($i=0; $i -lt $SusteemiKasutajad.Count; $i++) {
        Write-Host "[$($i+1)] $($SusteemiKasutajad[$i].Name)"
    }

    $KustutaValik = Read-Host "`nSisesta number, keda kustutada"

    if ($KustutaValik -match '^\d+$' -and [int]$KustutaValik -ge 1 -and [int]$KustutaValik -le $SusteemiKasutajad.Count) {
        $ValitudKasutaja = $SusteemiKasutajad[[int]$KustutaValik - 1]
        $Nimi = $ValitudKasutaja.Name
        
        Write-Host "Kustutan kasutajat '$Nimi'..." -ForegroundColor Yellow
        
        try {
            Remove-LocalUser -Name $Nimi -ErrorAction Stop
            Write-Host "Kasutaja konto kustutatud." -ForegroundColor Green
        }
        catch {
            Write-Error "Viga kasutaja kustutamisel: $($_.Exception.Message)"
            exit
        }

        # Kustutame ka kodukausta, kui see on juba tekkinud
        $KoduKaust = "C:\Users\$Nimi"
        if (Test-Path $KoduKaust) {
            Write-Host "Leiti kodukaust: $KoduKaust. Kustutan..."
            try {
                Remove-Item -Path $KoduKaust -Recurse -Force -ErrorAction Stop
                Write-Host "Kodukaust kustutatud." -ForegroundColor Green
            }
            catch {
                Write-Warning "Ei saanud kodukausta kustutada (voib olla lukus voi oiguste probleem)."
            }
        } else {
            Write-Host "Kodukausta ei leitud (kasutaja pole sisse loginud)." -ForegroundColor Gray
        }

    } else {
        Write-Warning "Vigane valik. Skript lopetas too."
    }

} else {
    Write-Warning "Tundmatu valik. Vali 'L' voi 'K'."
}

Write-Host "`nSkript lopetas too." -ForegroundColor Gray
