# Taxas do mercado secundário de debêntures, da ANBIMA.
#
#   .\anbima-debentures.ps1                        # resumo do mercado
#   .\anbima-debentures.ps1 -Busca KLABIN          # por emissor
#   .\anbima-debentures.ps1 -Busca RADL14          # por código
#   .\anbima-debentures.ps1 -Data 30/07/2026
#
# Fonte: anbima.com.br/informacoes/merc-sec-debentures
#
# ⚠️ Só há histórico de 5 DIAS ÚTEIS. Não serve para série temporal — é foto do
# mercado agora. Para histórico longo, não existe fonte pública.

param(
  [string]$Busca,
  [string]$Data,
  [int]$Top = 20,
  [string]$Cache
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
if (-not $Cache) {
  $d = Split-Path -Parent $PSCommandPath
  $Cache = Join-Path (Split-Path -Parent $d) "dados"
}
if (-not (Test-Path $Cache)) { New-Item -ItemType Directory -Path $Cache -Force | Out-Null }

$UA = @{ "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120 Safari/537.36" }
$meses = @('','jan','fev','mar','abr','mai','jun','jul','ago','set','out','nov','dez')

# A ANBIMA monta o nome do arquivo como DD+mes+AAAA (ex.: 31jul2026). Se nenhuma
# data for dada, tenta os últimos 7 dias corridos até achar publicação — fim de
# semana e feriado não têm arquivo.
function UrlDe([datetime]$dt, [string]$cat) {
  $s = "{0:00}{1}{2:0000}" -f $dt.Day, $meses[$dt.Month], $dt.Year
  "https://www.anbima.com.br/informacoes/merc-sec-debentures/resultados/mdeb_${s}_$cat.asp"
}

$datas = if ($Data) { ,([datetime]::ParseExact($Data,'dd/MM/yyyy',$null)) }
         else { 0..7 | ForEach-Object { (Get-Date).AddDays(-$_) } }

# O HTML da ANBIMA NÃO fecha as tags </TR>, então split em <TR é mais confiável
# que regex de par aberto/fechado.
function Parse([string]$html, [string]$cat) {
  foreach ($b in ($html -split '(?i)<TR')) {
    $tds = [regex]::Matches($b,'(?is)<TD[^>]*>(.*?)</TD>') |
           ForEach-Object { ($_.Groups[1].Value -replace '(?is)<[^>]+>','' -replace '&nbsp;',' ').Trim() }
    if ($tds.Count -ge 10 -and $tds[0] -match '^[A-Z0-9]{4,6}$') {
      [pscustomobject]@{
        Codigo = $tds[0]; Nome = $tds[1]; Vencimento = $tds[2]; Indice = $tds[3]
        TaxaCompra = $tds[4]; TaxaVenda = $tds[5]; TaxaIndicativa = $tds[6]
        Desvio = $tds[7]; PU = $tds[10]; Categoria = $cat
      }
    }
  }
}

$cats = @{ 'di_percentual' = '% do DI'; 'di_spread' = 'DI + spread'; 'ipca_spread' = 'IPCA + spread' }
$todos = @(); $refUsada = $null
foreach ($dt in $datas) {
  $achou = $false
  foreach ($c in $cats.Keys) {
    try {
      $r = Invoke-WebRequest (UrlDe $dt $c) -Headers $UA -TimeoutSec 60 -UseBasicParsing
      $linhas = Parse $r.Content $cats[$c]
      if ($linhas) { $todos += $linhas; $achou = $true }
    } catch {}
  }
  if ($achou) { $refUsada = $dt; break }
}

if (-not $todos) {
  Write-Warning "Nenhuma publicação encontrada. A ANBIMA mantém só 5 dias úteis de histórico."
  return
}

"`nMercado Secundário de Debêntures — ANBIMA"
"Referência: {0:dd/MM/yyyy} · {1} papéis" -f $refUsada, $todos.Count
$todos | Group-Object Categoria | ForEach-Object { "  {0,-16} {1}" -f $_.Name, $_.Count }

$sel = if ($Busca) { $todos | Where-Object { $_.Codigo -match $Busca -or $_.Nome -match $Busca } } else { $todos }
if ($Busca -and -not $sel) { Write-Warning "Nada encontrado para '$Busca'."; return }

"`n{0,-9}{1,-30}{2,-12}{3,-16}{4,10}{5,14}" -f "Código","Emissor","Vencimento","Índice","Indicativa","PU"
$sel | Select-Object -First $Top | ForEach-Object {
  $n = $_.Nome -replace '\(\*+\)','' -replace '\s+',' '
  "{0,-9}{1,-30}{2,-12}{3,-16}{4,10}{5,14}" -f $_.Codigo, $n.Substring(0,[Math]::Min(29,$n.Length)),
    $_.Vencimento, $_.Indice.Substring(0,[Math]::Min(15,$_.Indice.Length)), $_.TaxaIndicativa, $_.PU
}
if ($sel.Count -gt $Top) { "... e mais $($sel.Count - $Top). Use -Top N." }

$csv = Join-Path $Cache "anbima_debentures.csv"
$todos | Export-Csv $csv -NoTypeInformation -Encoding UTF8
"`nSalvo em $csv"

"`n-- Como ler --"
"  'Taxa Indicativa' é a taxa de referência da ANBIMA, não uma oferta a você."
"  Debênture NÃO tem FGC: o risco é integralmente do emissor. Compare o spread"
"  sobre o DI com o rating e as garantias antes de olhar só a taxa."
"  Debênture incentivada (Lei 12.431) é isenta de IR para pessoa física — use"
"  renda-fixa.ps1 -Tipo DEB-INC para a comparação líquida."
