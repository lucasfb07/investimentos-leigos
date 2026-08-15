# Expande o universo de FIIs a partir de uma planilha externa.
#
#   .\importar-fiis-planilha.ps1 -Arquivo "C:\...\Book 4.xlsx"
#
# Por que existe: a brapi aceita 1 ticker por requisição no plano atual, então o
# painel cobria só ~25 FIIs. Uma planilha com a bolsa inteira resolve a largura;
# as métricas calculadas da CVM (retorno total, erosão, oscilação) continuam
# valendo para quem tiver série lá, e a planilha preenche o resto.
#
# COLUNAS: o arquivo não tem cabeçalho. O mapeamento abaixo foi verificado
# estatisticamente contra os dados já validados do painel:
#   col 2  preço    -> erro médio de R$ 0,012 em 25 fundos
#   col 5  P/VP     -> bate
#   col 6  patrimônio líquido
#   col 7  liquidez diária
#   col 8  número de imóveis
#   col 12 vacância -> erro médio de 0,03 pp contra a vacância da CVM
# As colunas 3, 4, 9, 10 e 11 NÃO foram identificadas com confiança e ficam de
# fora. Coluna 11 chegou a parecer vacância e erra 14,75 pp — não use.

param(
  [Parameter(Mandatory=$true)][string]$Arquivo,
  [string]$Cache
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$IC = [Globalization.CultureInfo]::InvariantCulture
if (-not $Cache) { $dd = Split-Path -Parent $PSCommandPath; $Cache = Join-Path (Split-Path -Parent $dd) "dados" }
if (-not (Test-Path $Arquivo)) { throw "Arquivo não encontrado: $Arquivo" }
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Num($v) { if ([string]::IsNullOrWhiteSpace($v)) { $null } else { try { [double]::Parse($v, $IC) } catch { $null } } }

# ---- Lê o xlsx (ZIP + XML, sem Excel) ---------------------------------------
$zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path $Arquivo))
$linhas = @()
try {
  $ss = @()
  $ent = $zip.Entries | Where-Object { ($_.FullName -replace '\\','/') -eq 'xl/sharedStrings.xml' }
  if ($ent) {
    $rd = New-Object IO.StreamReader($ent.Open()); $xd = [xml]$rd.ReadToEnd(); $rd.Close()
    $ss = @($xd.sst.si | ForEach-Object {
      if ($_.t -is [string]) { $_.t } elseif ($_.t.'#text') { $_.t.'#text' }
      else { ($_.r.t | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.'#text' } }) -join '' } })
  }
  $sheet = $zip.Entries | Where-Object { ($_.FullName -replace '\\','/') -match '^xl/worksheets/sheet1\.xml$' }
  $rd = New-Object IO.StreamReader($sheet.Open()); $doc = [xml]$rd.ReadToEnd(); $rd.Close()
  foreach ($r in @($doc.worksheet.sheetData.row)) {
    $cel = @{}
    foreach ($c in @($r.c)) {
      $v = $c.v
      if ($c.t -eq 's' -and $null -ne $v) { $v = $ss[[int]$v] } elseif ($c.t -eq 'inlineStr') { $v = $c.is.t }
      # Célula vazia é omitida: sem a referência, as colunas deslocam.
      $letra = ($c.r -replace '\d',''); $n = 0
      foreach ($ch in $letra.ToUpper().ToCharArray()) { $n = $n*26 + ([int][char]$ch - 64) }
      $cel[$n-1] = $v
    }
    if ($cel[0]) { $linhas += ,$cel }
  }
} finally { $zip.Dispose() }
Write-Host "Linhas lidas: $($linhas.Count)"

# ---- Normaliza ---------------------------------------------------------------
$fiis = foreach ($l in $linhas) {
  $tk = "$($l[0])".Trim().ToUpper()
  if ($tk -notmatch '^[A-Z]{4}\d{1,2}$') { continue }
  $preco = Num $l[2]; $pvp = Num $l[5]
  if (-not $preco -or -not $pvp -or $preco -le 0 -or $pvp -le 0) { continue }
  $vac = Num $l[12]
  [pscustomobject]@{
    Ticker    = $tk
    Segmento  = "$($l[1])".Trim()
    Preco     = $preco
    PVP       = $pvp
    VPcota    = $preco / $pvp
    PL        = Num $l[6]
    Liquidez  = Num $l[7]
    NImoveis  = $(if ($null -ne (Num $l[8]) -and (Num $l[8]) -gt 0) { [int](Num $l[8]) } else { $null })
    # Vacância zero em fundo sem imóvel é ausência de dado, não ocupação plena.
    Vacancia  = $(if ($null -ne $vac -and (Num $l[8]) -gt 0) { $vac * 100 } else { $null })
  }
}
Write-Host "FIIs válidos: $($fiis.Count)"

$saida = "$Cache\fiis_planilha.csv"
$fiis | Export-Csv $saida -NoTypeInformation -Encoding UTF8
Write-Host "Salvo: $saida"

# ---- Resumo ------------------------------------------------------------------
function Med($v) { $s=@($v|Sort-Object); if($s.Count -eq 0){0}else{$s[[int]($s.Count/2)]} }
$comImovel = @($fiis | Where-Object { $_.NImoveis })
"`nCobertura"
"  fundos            {0,6}" -f $fiis.Count
"  com imóveis       {0,6}" -f $comImovel.Count
"  com vacância      {0,6}" -f @($fiis | Where-Object { $null -ne $_.Vacancia }).Count
"`nMedianas"
"  P/VP              {0,6:N3}" -f (Med $fiis.PVP)
"  patrimônio     R$ {0,6:N0} mi" -f ((Med $fiis.PL)/1e6)
"  liquidez/dia   R$ {0,6:N0} mil" -f ((Med $fiis.Liquidez)/1e3)
if ($comImovel.Count) { "  vacância          {0,6:N1}%" -f (Med $comImovel.Vacancia) }

"`nSegmentos:"
$fiis | Group-Object Segmento | Sort-Object Count -Descending | Select-Object -First 8 |
  ForEach-Object { "  {0,-22} {1,4}" -f $_.Name, $_.Count }

"`n-- Cuidados --"
"  A planilha não traz data. Os preços batem com a base do painel dentro de"
"  R\$ 0,01, então é recente — mas confirme a origem antes de decidir com ela."
"  Colunas 3, 4, 9, 10 e 11 não foram identificadas e ficaram de fora. A 11"
"  parecia vacância e erra quase 15 pontos: não a use como tal."
"  O segmento vem com o mesmo erro da CVM — MXRF11, que é 100% papel, aparece"
"  como Logística. O painel classifica pela carteira real, não por este campo."
