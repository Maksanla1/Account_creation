<#
.SYNOPSIS
    Genereerib 5 juhuslikku kasutajakontot valikuga määrata ühine staatiline parool.
    
.DESCRIPTION
    See skript loeb nimed ja kirjeldused tekstifailidest, genereerib juhuslikud kasutajad,
    puhastab kasutajanimed (eemaldab täpitähed/tühikud) ja ekspordib andmed CSV faili.
    Võimaldab valida, kas määrata kõigile üks kindel parool või genereerida igale unikaalne.
#>

# --- SEADISTUS ---
$Failid = @{
    Eesnimed     = "Eesnimed.txt"
    Perenimed    = "Perenimed.txt"
    Kirjeldused  = "Kirjeldused.txt"
    Väljund      = "new_users_accounts.csv"
}

# --- ANDMETE KONTROLL ---
# Kontrollime, kas vajalikud sisendfailid on olemas
if (!(Test-Path $Failid.Eesnimed) -or !(Test-Path $Failid.Perenimed)) {
    Write-Warning "Viga: Vajalikud sisendfailid on puudu!"
    exit
}

# Laeme failide sisu mällu (UTF8 kodeering tagab täpitähtede õige lugemise)
$ListFirst = Get-Content $Failid.Eesnimed -Encoding UTF8
$ListLast  = Get-Content $Failid.Perenimed -Encoding UTF8
$ListDesc  = Get-Content $Failid.Kirjeldused -Encoding UTF8

# --- FUNKTSIOONID ---

# Funktsioon täpitähtede eemaldamiseks (nt 'õ' -> 'o', 'š' -> 's')
function Remove-Diacritics {
    param ([String]$src = [String]::Empty)
    # Normaliseerime stringi FormD kujule, et eraldada tähed rõhumärkidest
    $normalized = $src.Normalize( [Text.NormalizationForm]::FormD )
    $sb = New-Object Text.StringBuilder
    
    $normalized.ToCharArray() | ForEach-Object { 
        # Lisame ainult need märgid, mis EI OLE rõhumärgid (non-spacing marks)
        if( [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($_)
        }
    }
    return $sb.ToString()
}

# Funktsioon puhta kasutajanime loomiseks (väiketähed, erimärgid välja)
function Get-CleanUsername {
    param ([string]$Name)
    # Esmalt eemalda täpitähed
    $CleanName = Remove-Diacritics -src $Name
    # Regex: Asenda kõik, mis EI OLE a-z või 0-9, tühjusega
    return ($CleanName.ToLower() -replace '[^a-z0-9]', '')
}

# Funktsioon turvalise juhusliku parooli loomiseks
function Get-RandomPassword {
    $Length = Get-Random -Minimum 5 -Maximum 9
    $CharSet = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    # Vali juhuslikud märgid etteantud hulgast
    return -join ((1..$Length) | ForEach-Object { $CharSet[(Get-Random -Maximum $CharSet.Length)] })
}

# --- KASUTAJA VALIK: PAROOLI SEADISTAMINE ---

Clear-Host
Write-Host "--- PAROOLI SEADISTUS ---" -ForegroundColor Cyan

# Küsi kasutajalt, kas ta soovib ühist parooli kõigile
$GlobalPass = Read-Host "Sisesta staatiline parool KÕIGILE (või vajuta ENTER juhuslike paroolide jaoks)"

if (-not [string]::IsNullOrWhiteSpace($GlobalPass)) {
    Write-Host "Valitud režiim: Staatiline parool '$GlobalPass'" -ForegroundColor Yellow
} else {
    Write-Host "Valitud režiim: Juhuslikud paroolid" -ForegroundColor Green
}
Start-Sleep -Seconds 1

# --- KASUTAJATE GENEREERIMINE ---

Write-Host "`nGenereerin 5 juhuslikku kasutajat..." -ForegroundColor Cyan
$UserList = New-Object System.Collections.Generic.List[PSObject]

# Tsükkel käib täpselt 5 korda
1..5 | ForEach-Object {
    # 1. Vali nimekirjadest suvalised andmed
    $RandFirst = $ListFirst | Get-Random
    $RandLast  = $ListLast | Get-Random
    $RandDesc  = $ListDesc | Get-Random

    # 2. Töötle ja puhasta kasutajanimi
    $CleanFirst = Get-CleanUsername -Name $RandFirst
    $CleanLast  = Get-CleanUsername -Name $RandLast
    
    # 3. Määra parool (Staatiline vs Juhuslik)
    if (-not [string]::IsNullOrWhiteSpace($GlobalPass)) {
        $FinalPassword = $GlobalPass
    } else {
        $FinalPassword = Get-RandomPassword
    }

    # 4. Loo kasutaja objekt
    $NewUser = [PSCustomObject]@{
        Eesnimi      = $RandFirst
        Perenimi     = $RandLast
        Kasutajanimi = "$CleanFirst.$CleanLast"
        Parool       = $FinalPassword
        Kirjeldus    = $RandDesc
    }
    $UserList.Add($NewUser)
}

# --- EKSPORT JA VÄLJUND ---

# Ekspordi CSV faili kasutades semikoolonit eraldajana
$UserList | Export-Csv -Path $Failid.Väljund -Delimiter ";" -NoTypeInformation -Encoding UTF8 -Force

Write-Host "`n--------------------------------------------------------" -ForegroundColor Cyan
Write-Host "EDUKAS! Fail salvestatud: $($Failid.Väljund)" -ForegroundColor Cyan
Write-Host "--------------------------------------------------------" -ForegroundColor Gray

# Kuva kokkuvõte konsoolis
foreach ($User in $UserList) {
    # Lühenda kirjeldust parema loetavuse huvides 10 märgini
    $DescShort = if ($User.Kirjeldus.Length -gt 10) { $User.Kirjeldus.Substring(0, 10) + "..." } else { $User.Kirjeldus }
    Write-Host "Kasutaja: $($User.Kasutajanimi) | Parool: $($User.Parool) | Info: $DescShort"
}
Write-Host "--------------------------------------------------------" -ForegroundColor Gray
