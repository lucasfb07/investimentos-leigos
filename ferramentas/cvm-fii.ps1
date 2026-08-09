# Monta a base de FIIs a partir do Informe Mensal da CVM e compara um fundo
# contra seus pares. Substitui a suíte fii/* da brapi, que só cobre MXRF11 e
# HGLG11 no plano atual.
#
#   .\cvm-fii.ps1 -Ticker MXRF11
#   .\cvm-fii.ps1 -Ticker KNCR11 -Ref 2026-05-01 -MinPL 1e9
#
# Fonte: https://dados.cvm.gov.br/dados/FII/DOC/INF_MENSAL/DADOS/
# Preço vem da brapi (BRAPI_TOKEN); o resto é CVM.

param(
  [string]$Ticker = "MXRF11",
  [string]$Ref,                      # competência YYYY-MM-01; vazio = última completa
  [double]$MinPL = 3e8,              # corte de patrimônio para entrar na comparação
  [double]$MinCRI = 0.5,             # >50% em CRI = fundo de papel
  [int]$Top = 14,
  [string]$Cache = "$PSScriptRoot\..\dados"
)

$ErrorActionPreference = "Stop"
$IC = [Globalization.CultureInfo]::InvariantCulture
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

# CVM usa PONTO como decimal. Parsear com a cultura local (pt-BR) transforma
# 9.229278 em 9229278 silenciosamente — sempre InvariantCulture.
function N($v) { if ([string]::IsNullOrWhiteSpace($v)) { 0 } else { [double]::Parse($v, $IC) } }

$ano = (Get-Date).Year
if ($Ref) { $ano = [int]$Ref.Substring(0,4) }
if (-not (Test-Path $Cache)) { New-Item -ItemType Directory -Path $Cache | Out-Null }
$zip = "$Cache\inf_mensal_fii_$ano.zip"
$dir = "$Cache\inf_mensal_fii_$ano"

# Baixa só se ausente ou com mais de 7 dias. O arquivo tem ~1 MB.
$baixar = -not (Test-Path $zip) -or ((Get-Date) - (Get-Item $zip).LastWriteTime).TotalDays -gt 7
if ($baixar) {
  Write-Host "Baixando Informe Mensal FII $ano da CVM..."
  $wc = New-Object System.Net.WebClient
  $wc.Headers.Add("User-Agent","Mozilla/5.0")
  $wc.DownloadFile("https://dados.cvm.gov.br/dados/FII/DOC/INF_MENSAL/DADOS/inf_mensal_fii_$ano.zip", $zip)
  $wc.Dispose()
  Expand-Archive $zip -DestinationPath $dir -Force
} elseif (-not (Test-Path $dir)) { Expand-Archive $zip -DestinationPath $dir -Force }

# Encoding Latin-1 (-Encoding Default). Lido como UTF8, acento quebra e
# qualquer filtro por nome falha em silêncio.
$geral = Import-Csv "$dir\inf_mensal_fii_geral_$ano.csv" -Delimiter ';' -Encoding Default
$comp  = Import-Csv "$dir\inf_mensal_fii_complemento_$ano.csv" -Delimiter ';' -Encoding Default
$atpa  = Import-Csv "$dir\inf_mensal_fii_ativo_passivo_$ano.csv" -Delimiter ';' -Encoding Default

# A competência mais recente costuma ter poucos fundos (ainda entregando).
# Pega a última com cobertura >= 80% do pico.
if (-not $Ref) {
  $porMes = $geral | Group-Object Data_Referencia | Sort-Object Name
  $pico = ($porMes | Measure-Object Count -Maximum).Maximum
  $Ref = ($porMes | Where-Object { $_.Count -ge $pico * 0.8 } | Select-Object -Last 1).Name
}
Write-Host "Competência: $Ref"

$g = @{}; $geral | Where-Object { $_.Data_Referencia -eq $Ref } | ForEach-Object { $g[$_.CNPJ_Fundo_Classe] = $_ }
$a = @{}; $atpa  | Where-Object { $_.Data_Referencia -eq $Ref } | ForEach-Object { $a[$_.CNPJ_Fundo_Classe] = $_ }

$base = foreach ($c in ($comp | Where-Object { $_.Data_Referencia -eq $Ref })) {
  $k = $c.CNPJ_Fundo_Classe; $gg = $g[$k]; $aa = $a[$k]
  if (-not $gg -or -not $aa) { continue }
  $inv = N $aa.Total_Investido; if ($inv -le 0) { continue }
  # Ticker sai do ISIN: BRMXRFCTF008 -> MXRF11
  if ($gg.Codigo_ISIN -notmatch '^BR(.{4})CTF') { continue }
  [pscustomobject]@{
    Ticker   = $Matches[1] + "11"
    Nome     = $gg.Nome_Fundo_Classe
    PL       = N $c.Patrimonio_Liquido
    VP       = N $c.Valor_Patrimonial_Cotas
    TxAdmAno = (N $c.Percentual_Despesas_Taxa_Administracao) * 12   # campo é mensal e fração
    DYmes    = N $c.Percentual_Dividend_Yield_Mes
    RentMes  = N $c.Percentual_Rentabilidade_Efetiva_Mes
    Cotistas = [int]$c.Total_Numero_Cotistas
    PctCRI   = ((N $aa.CRI) + (N $aa.CRI_CRA)) / $inv
    PctImovel= ((N $aa.Imoveis_Renda_Acabados) + (N $aa.Imoveis_Renda_Construcao) +
                (N $aa.Imoveis_Venda_Acabados) + (N $aa.Imoveis_Venda_Construcao) + (N $aa.Terrenos)) / $inv
    Gestao   = $gg.Tipo_Gestao
  }
}
Write-Host "Fundos na base: $($base.Count)"

$alvo = $base | Where-Object { $_.Ticker -eq $Ticker } | Select-Object -First 1
if (-not $alvo) { Write-Warning "$Ticker não encontrado em $Ref."; return }

# Classifica pelo que o fundo CARREGA, não pelo Segmento_Atuacao — esse campo
# vem errado na origem (MXRF11, que é 100% papel, aparece como "Logística").
$ehPapel = $alvo.PctCRI -gt $MinCRI
$pares = $base | Where-Object {
  $_.PL -ge $MinPL -and (($ehPapel -and $_.PctCRI -gt $MinCRI) -or (-not $ehPapel -and $_.PctImovel -gt $MinCRI))
} | Sort-Object PL -Descending | Select-Object -First $Top
Write-Host "Pares ($(if($ehPapel){'papel'}else{'tijolo'})): $($pares.Count)"

# Preço não existe na CVM — vem da brapi, 1 ticker por requisição.
$tok = $env:BRAPI_TOKEN
if (-not $tok) { $tok = [Environment]::GetEnvironmentVariable("BRAPI_TOKEN","User") }
$hdr = @{ Authorization = "Bearer $tok" }
$res = foreach ($p in $pares) {
  try {
    $q = (Invoke-RestMethod "https://brapi.dev/api/v2/stocks/quote?symbols=$($p.Ticker)" -Headers $hdr -TimeoutSec 20).results[0].data
    if ($q.regularMarketPrice -and $p.VP -gt 0) {
      $p | Add-Member Preco $q.regularMarketPrice -Force
      $p | Add-Member PVP ($q.regularMarketPrice / $p.VP) -Force
      $p
    }
  } catch {}
  Start-Sleep -Milliseconds 200
}

"`n{0,-9}{1,10}{2,9}{3,8}{4,9}{5,8}{6,8}{7,11}" -f "Ticker","Preco","VP/cota","P/VP","DY mes","TxAdm","PL bi","Cotistas"
$res | Sort-Object PVP | ForEach-Object {
  $m = if ($_.Ticker -eq $Ticker) { "*" } else { " " }
  "{0}{1,-8}{2,10:N2}{3,9:N2}{4,8:N3}{5,9:P2}{6,8:P2}{7,8:N2}{8,11:N0}" -f $m,$_.Ticker,$_.Preco,$_.VP,$_.PVP,$_.DYmes,$_.TxAdmAno,($_.PL/1e9),$_.Cotistas
}
function Mediana($v) { $s = @($v | Sort-Object); if ($s.Count -eq 0) { 0 } else { $s[[int]($s.Count/2)] } }
"`nMediana dos pares -> P/VP {0:N3} | DY mês {1:P2} | Taxa adm {2:P2}" -f (Mediana $res.PVP), (Mediana $res.DYmes), (Mediana $res.TxAdmAno)
"$Ticker            -> P/VP {0:N3} | DY mês {1:P2} | Taxa adm {2:P2}" -f $alvo.PVP, $alvo.DYmes, $alvo.TxAdmAno
