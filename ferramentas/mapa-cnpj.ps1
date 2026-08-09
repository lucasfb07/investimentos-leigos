# Constrói o mapa CNPJ -> ticker usado por cvm-acoes.ps1.
# Roda uma vez; CNPJ não muda. Reexecute só quando surgirem novas listagens.
#
#   .\mapa-cnpj.ps1
#
# A brapi devolve CNPJ em stocks/profile para ~35% dos tickers (sobretudo ON).
# O mapa é indexado pela RAIZ de 4 letras: PETR3 e PETR4 são a mesma empresa,
# então mapear uma classe cobre as demais. Cobertura medida: 672 de 771 tickers.

param([string]$Cache)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
if (-not $Cache) {
  $d = Split-Path -Parent $PSCommandPath
  $Cache = Join-Path (Split-Path -Parent $d) "dados"
}
if (-not (Test-Path $Cache)) { New-Item -ItemType Directory -Path $Cache -Force | Out-Null }

$tok = $env:BRAPI_TOKEN
if (-not $tok) { $tok = [Environment]::GetEnvironmentVariable("BRAPI_TOKEN","User") }
if (-not $tok) { throw "BRAPI_TOKEN não configurado." }
$h = @{ Authorization = "Bearer $tok" }

Write-Host "Enumerando tickers de ação..."
$all = @(); $p = 1
do {
  $r = Invoke-RestMethod "https://brapi.dev/api/v2/tickers?subType=stock&limit=200&page=$p" -Headers $h -TimeoutSec 40
  $all += $r.results; $p++
} while ($r.pagination.hasNextPage -and $p -le 10)
Write-Host "  $($all.Count) tickers"

# Uma raiz basta por empresa — pula classes já resolvidas para economizar chamadas.
$vistas = @{}; $map = @(); $i = 0
foreach ($s in $all) {
  $i++
  if ($s.symbol.Length -lt 4) { continue }
  $raiz = $s.symbol.Substring(0,4)
  if ($vistas.ContainsKey($raiz)) { continue }
  if ($i % 50 -eq 0) { Write-Host "  $i/$($all.Count)... ($($map.Count) mapeados)" }
  try {
    $d = (Invoke-RestMethod "https://brapi.dev/api/v2/stocks/profile?symbols=$($s.symbol)" -Headers $h -TimeoutSec 15).results[0].data
    if ($d.cnpj) {
      $vistas[$raiz] = 1
      $map += [pscustomobject]@{
        Ticker = $s.symbol; CNPJ = ($d.cnpj -replace '[^\d]',''); Nome = $s.name
        Setor = $s.sector; Subsetor = $s.subsector
      }
    }
  } catch {}
  Start-Sleep -Milliseconds 120
}

$out = Join-Path $Cache "cnpj_ticker.csv"
$map | Export-Csv $out -NoTypeInformation -Encoding UTF8
Write-Host "`nRaízes mapeadas: $($map.Count) -> $out"
Write-Host "Tickers sem CNPJ na brapi ficam de fora — cvm-acoes.ps1 recusa esses"
Write-Host "explicitamente em vez de adivinhar por nome, que gera falso positivo."
