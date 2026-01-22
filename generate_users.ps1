<#
.SYNOPSIS
    Genereerib 5 juhuslikku kasutajakontot valikuga määrata ühine staatiline parool.
#>

# --- SUNNI KONSOOL UTF-8 KODEERINGUSSE ---
# See rida parandab täpitähtede kuvamise teises arvutis!
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# --- SEADISTUS ---
# NB! Muutujanimedes väldime täpitähti, aga tekstis (string) on need nüüd OK.
$Failid = @{
    Eesnimed     = "Eesnimed.txt"
    Perenimed    = "Perenimed.txt"
    Kirjeldused  = "Kirjeldused.txt"
    OutputFail   = "new_users_accounts.csv"
}

# --- ANDMETE KONTROLL ---
if (!(Test-Path $Failid.Eesnimed) -or !(Test-Path $Failid.Perenimed)) {
    Write-Warning "Viga: Vajalikud sisendfailid on puudu!"
    exit
}

$ListFirst = Get-Content $Failid.Eesnimed -Encoding UTF8
$ListLast  = Get-Content $Failid.Perenimed -Encoding UTF8
$ListDesc  = Get-Content $Failid.Kirjeldused -Encoding UTF8

# --- FUNKTSIOONID ---

function Remove-Diacritics {
    param ([String]$src = [String]::Empty)
    $normalized = $src.Normalize( [Text.NormalizationForm]::FormD )
    $sb = New-Object Text.StringBuilder
    $normalized.ToCharArray() | ForEach-Object { 
        if( [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($_)
        }
    }
    return $sb.ToString()
}

function Get-CleanUsername {
    param ([string]$Name)
    $CleanName = Remove-Diacritics -src $Name
    return ($CleanName.ToLower() -replace '[^a-z0-9]', '')
}

function Get-RandomPassword {
    $Length = Get-Random -Minimum 5 -Maximum 9
    $CharSet = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return -join ((1..$Length) | ForEach-Object { $CharSet[(Get-Random -Maximum $CharSet.Length)] })
}

# --- KASUTAJA VALIK: PAROOL ---

Clear-Host
Write-Host "--- PAROOLI SEADISTUS ---" -ForegroundColor Cyan
$GlobalPass = Read-Host "Sisesta staatiline parool (vajuta ENTER juhuslike paroolide jaoks)"

if (-not [string]::IsNullOrWhiteSpace($GlobalPass)) {
    Write-Host "Valitud: Staatiline parool '$GlobalPass'" -ForegroundColor Yellow
} else {
    Write-Host "Valitud: Juhuslikud paroolid" -ForegroundColor Green
}
Start-Sleep -Seconds 1

# --- KASUTAJATE GENEREERIMINE ---

Write-Host "`nGenereerin 5 juhuslikku kasutajat..." -ForegroundColor Cyan
$UserList = New-Object System.Collections.Generic.List[PSObject]

1..5 | ForEach-Object {
    $RandFirst = $ListFirst | Get-Random
    $RandLast  = $ListLast | Get-Random
    $RandDesc  = $ListDesc | Get-Random

    $CleanFirst = Get-CleanUsername -Name $RandFirst
    $CleanLast  = Get-CleanUsername -Name $RandLast
    
    if (-not [string]::IsNullOrWhiteSpace($GlobalPass)) {
        $FinalPassword = $GlobalPass
    } else {
        $FinalPassword = Get-RandomPassword
    }

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

$UserList | Export-Csv -Path $Failid.OutputFail -Delimiter ";" -NoTypeInformation -Encoding UTF8 -Force

Write-Host "`n--------------------------------------------------------" -ForegroundColor Cyan
Write-Host "EDUKAS! Fail salvestatud: $($Failid.OutputFail)" -ForegroundColor Cyan
Write-Host "--------------------------------------------------------" -ForegroundColor Gray
