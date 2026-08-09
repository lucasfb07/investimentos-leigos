# Watchlist de ações americanas.
#   Preço      -> brapi (aceita ticker dos EUA, sem custo de cota)
#   Fundamento -> Alpha Vantage OVERVIEW (25 requisições/dia no plano gratuito)
#
#   .\watchlist-eua.ps1                       # atualiza o que venceu
#   .\watchlist-eua.ps1 -Add NVDA,AMD         # inclui tickers
#   .\watchlist-eua.ps1 -Remove AMD
#   .\watchlist-eua.ps1 -Forcar               # ignora o cache (gasta cota!)
#
# Por que watchlist e não screener: fundamento custa 1 requisição por empresa e
# o teto é 25/dia. Varrer as ~500 do S&P levaria 20 dias. Com cache de 30 dias e
# ~20 tickers, o consumo fica perto de 1 por dia — bem dentro do limite.

param(
  [string[]]$Add, [string[]]$Remove,
  [int]$CacheDias = 30,
  [int]$MaxChamadas = 18,   # margem sob o teto de 25, para sobrar para outros usos
  [switch]$Forcar,
  [string]$Cache
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$IC = [Globalization.CultureInfo]::InvariantCulture
if (-not $Cache) { $d = Split-Path -Parent $PSCommandPath; $Cache = Join-Path (Split-Path -Parent $d) "dados" }
function N($v) { if ([string]::IsNullOrWhiteSpace($v) -or $v -eq 'None' -or $v -eq '-') { $null }
                 else { try { [double]::Parse($v, $IC) } catch { $null } } }

$listaFile = "$Cache\watchlist_eua.txt"
$fundFile  = "$Cache\watchlist_eua_fundamentos.json"

# ---- Lista de tickers --------------------------------------------------------
if (-not (Test-Path $listaFile)) {
  @('AAPL','MSFT','GOOGL','AMZN','NVDA','META','BRK-B','JNJ','V','JPM','XOM','KO','PG','UNH','HD') |
    Set-Content $listaFile -Encoding UTF8
  Write-Host "Lista inicial criada em $listaFile"
}
$tickers = @(Get-Content $listaFile -Encoding UTF8 | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ })
if ($Add)    { $tickers = @($tickers + ($Add    | ForEach-Object { $_.Trim().ToUpper() }) | Sort-Object -Unique) }
if ($Remove) { $rm = $Remove | ForEach-Object { $_.Trim().ToUpper() }; $tickers = @($tickers | Where-Object { $rm -notcontains $_ }) }
$tickers | Set-Content $listaFile -Encoding UTF8
Write-Host "Watchlist: $($tickers.Count) tickers"

# ---- Cache de fundamentos ----------------------------------------------------
$fund = @{}
if (Test-Path $fundFile) {
  try { (Get-Content $fundFile -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties |
          ForEach-Object { $fund[$_.Name] = $_.Value } } catch {}
}
$avKey = $env:ALPHAVANTAGE_TOKEN
if (-not $avKey) { $avKey = [Environment]::GetEnvironmentVariable("ALPHAVANTAGE_TOKEN","User") }

$venc = @($tickers | Where-Object {
  $Forcar -or -not $fund.ContainsKey($_) -or
  -not $fund[$_].buscadoEm -or
  ((Get-Date) - [datetime]$fund[$_].buscadoEm).TotalDays -gt $CacheDias
})
if ($venc.Count) {
  if (-not $avKey) {
    Write-Warning "ALPHAVANTAGE_TOKEN ausente — sem fundamentos. Só preço será atualizado."
  } else {
    $fazer = @($venc | Select-Object -First $MaxChamadas)
    Write-Host "Fundamentos vencidos: $($venc.Count). Buscando $($fazer.Count) (teto $MaxChamadas/dia)."
    foreach ($t in $fazer) {
      try {
        $r = Invoke-RestMethod "https://www.alphavantage.co/query?function=OVERVIEW&symbol=$t&apikey=$avKey" -TimeoutSec 40
        if ($r.Note -or $r.Information) { Write-Warning "  $t : cota diária esgotada — parando."; break }
        if (-not $r.Symbol) { Write-Warning "  $t : sem dados"; continue }
        $fund[$t] = @{
          nome=$r.Name; setor=$r.Sector; industria=$r.Industry
          pl=(N $r.PERatio); pvp=(N $r.PriceToBookRatio); roe=(N $r.ReturnOnEquityTTM)
          margem=(N $r.ProfitMargin); dy=(N $r.DividendYield); evEbitda=(N $r.EVToEBITDA)
          mcap=(N $r.MarketCapitalization); payout=(N $r.PayoutRatio)
          divEq=(N $r.DebtToEquity); beta=(N $r.Beta)
          max52=(N $r.'52WeekHigh'); min52=(N $r.'52WeekLow')
          buscadoEm=(Get-Date).ToString('s')
        }
        Write-Host ("  {0,-7} {1}" -f $t, $r.Name)
      } catch { Write-Warning "  $t : $($_.Exception.Message)" }
      Start-Sleep -Milliseconds 1300   # o plano gratuito também limita 1 req/s
    }
  }
} else { Write-Host "Fundamentos em cache, nada vencido." }
$fund | ConvertTo-Json -Depth 5 | Set-Content $fundFile -Encoding UTF8

# ---- Preço (brapi, sem consumir cota do Alpha Vantage) ----------------------
$tok = $env:BRAPI_TOKEN; if (-not $tok) { $tok = [Environment]::GetEnvironmentVariable("BRAPI_TOKEN","User") }
$hdr = @{ Authorization = "Bearer $tok" }
$res = foreach ($t in $tickers) {
  $p = $null; $var = $null
  try {
    $q = (Invoke-RestMethod "https://brapi.dev/api/v2/stocks/quote?symbols=$t" -Headers $hdr -TimeoutSec 20).results[0].data
    $p = $q.regularMarketPrice; $var = $q.regularMarketChangePercent
  } catch {}
  Start-Sleep -Milliseconds 120
  $f = $fund[$t]
  # Lucro/preço = inverso do P/L. Mesma régua da aba de ações brasileiras,
  # para os dois lados ficarem comparáveis.
  $ey = if ($f -and $f.pl -and $f.pl -gt 0) { 100/$f.pl } else { $null }
  [pscustomobject]@{
    Ticker=$t; Nome=$(if($f){$f.nome}else{$t}); Setor=$(if($f){$f.setor}else{''})
    Preco=$p; VarDia=$var
    PL=$(if($f){$f.pl}else{$null}); PVP=$(if($f){$f.pvp}else{$null})
    EarningsYield=$ey
    ROE=$(if($f -and $f.roe){$f.roe*100}else{$null})
    Margem=$(if($f -and $f.margem){$f.margem*100}else{$null})
    DY=$(if($f -and $f.dy){$f.dy*100}else{$null})
    Payout=$(if($f -and $f.payout){$f.payout*100}else{$null})
    EvEbitda=$(if($f){$f.evEbitda}else{$null})
    DivEq=$(if($f){$f.divEq}else{$null}); Beta=$(if($f){$f.beta}else{$null})
    MCap=$(if($f){$f.mcap}else{$null})
    Atualizado=$(if($f){$f.buscadoEm}else{''})
  }
}
$res | Export-Csv "$Cache\watchlist_eua.csv" -NoTypeInformation -Encoding UTF8

"`n{0,-7}{1,10}{2,8}{3,9}{4,8}{5,9}{6,8}{7,8}" -f "Ticker","Preço USD","L/P %","P/L","P/VP","ROE %","DY %","Beta"
$res | Sort-Object { if ($_.EarningsYield) { -$_.EarningsYield } else { 999 } } | ForEach-Object {
  "{0,-7}{1,10}{2,8}{3,9}{4,8}{5,9}{6,8}{7,8}" -f $_.Ticker,
    $(if($_.Preco){"{0:N2}" -f $_.Preco}else{"—"}),
    $(if($_.EarningsYield){"{0:N1}" -f $_.EarningsYield}else{"—"}),
    $(if($_.PL){"{0:N1}" -f $_.PL}else{"—"}),
    $(if($_.PVP){"{0:N1}" -f $_.PVP}else{"—"}),
    $(if($_.ROE){"{0:N1}" -f $_.ROE}else{"—"}),
    $(if($_.DY){"{0:N2}" -f $_.DY}else{"—"}),
    $(if($_.Beta){"{0:N2}" -f $_.Beta}else{"—"})
}
"`nSalvo em $Cache\watchlist_eua.csv"
"`n-- Cuidados --"
"  RISCO CAMBIAL: tudo aqui está em dólar. Se o dólar cair, o retorno em reais"
"  encolhe mesmo com a ação subindo. O contrário também vale."
"  P/VP alto é NORMAL em empresa de tecnologia — o valor está em marca, software e"
"  gente, que quase não aparecem no balanço. Comparar com banco ou indústria engana."
"  Fundamento vem do Alpha Vantage, com até $CacheDias dias de cache. A coluna"
"  Atualizado no CSV mostra a data de cada um."
