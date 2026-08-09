# Avalia uma oferta de renda fixa contra as referências públicas.
#
#   .\renda-fixa.ps1 -Tipo CDB -Indexador CDI  -Taxa 110  -Anos 2
#   .\renda-fixa.ps1 -Tipo LCI -Indexador CDI  -Taxa 95   -Anos 1
#   .\renda-fixa.ps1 -Tipo CDB -Indexador IPCA -Taxa 7.2  -Anos 5 -Valor 300000
#   .\renda-fixa.ps1 -Tipo CDB -Indexador PRE  -Taxa 14.5 -Anos 3
#
# NÃO existe fonte pública de taxa de CDB/LCI/LCA — são ofertas bilaterais,
# negociadas por banco e por cliente. Este script não busca taxa: ele avalia a
# que VOCÊ informar, contra CDI, Selic, IPCA e Tesouro Direto, todos oficiais.

param(
  [ValidateSet('CDB','LCI','LCA','CRI','CRA','DEB','DEB-INC','RDB','LC')]
  [string]$Tipo = 'CDB',
  [ValidateSet('CDI','PRE','IPCA')][string]$Indexador = 'CDI',
  [Parameter(Mandatory=$true)][double]$Taxa,
  [Parameter(Mandatory=$true)][double]$Anos,
  [double]$Valor = 0,
  [string]$Cache
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$IC = [Globalization.CultureInfo]::InvariantCulture
if (-not $Cache) {
  $d = Split-Path -Parent $PSCommandPath
  $Cache = Join-Path (Split-Path -Parent $d) "dados"
}
if (-not (Test-Path $Cache)) { New-Item -ItemType Directory -Path $Cache -Force | Out-Null }

# O SGS rejeita requisição sem User-Agent de navegador ("Requisição inválida").
$UA = @{ "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120 Safari/537.36" }
function SGS($cod) {
  $r = Invoke-RestMethod "https://api.bcb.gov.br/dados/serie/bcdata.sgs.$cod/dados/ultimos/1?formato=json" -Headers $UA -TimeoutSec 25
  @{ Valor = [double]::Parse(($r[0].valor -replace ',','.'), $IC); Data = $r[0].data }
}

Write-Host "Consultando Banco Central..."
$cdi   = SGS 4389    # CDI anualizado
$selic = SGS 432     # meta Selic
$ipca  = SGS 13522   # IPCA acumulado 12 meses

# --- Rendimento bruto anual da oferta ---------------------------------------
switch ($Indexador) {
  'CDI'  { $bruto = $cdi.Valor * ($Taxa / 100); $desc = "$Taxa% do CDI" }
  'PRE'  { $bruto = $Taxa;                      $desc = "$Taxa% a.a. prefixado" }
  'IPCA' { $bruto = $ipca.Valor + $Taxa;        $desc = "IPCA + $Taxa% a.a." }
}

# --- Imposto de renda --------------------------------------------------------
# Tabela regressiva, art. 1º da Lei 11.033/2004. LCI, LCA, CRI, CRA e debênture
# incentivada são isentas para pessoa física.
$isentos = @('LCI','LCA','CRI','CRA','DEB-INC')
$dias = [int]($Anos * 365)
# PowerShell 5.1 não aceita `if` como expressão inline — precisa de função.
function Aliquota([int]$d) {
  if ($d -le 180) { 0.225 } elseif ($d -le 360) { 0.20 }
  elseif ($d -le 720) { 0.175 } else { 0.15 }
}
$aliqPadrao = Aliquota $dias
$aliq = if ($Tipo -in $isentos) { 0 } else { $aliqPadrao }
$liquido = $bruto * (1 - $aliq)

# --- FGC ---------------------------------------------------------------------
# R$ 250 mil por CPF e por conglomerado; teto global de R$ 1 milhão a cada
# 4 anos. Fonte: fgc.org.br, verificado em 08/08/2026.
$comFGC = @('CDB','LCI','LCA','RDB','LC')
$temFGC = $Tipo -in $comFGC

"`n=== $Tipo — $desc — $Anos ano(s) ==="
"Referências: CDI $($cdi.Valor)% ($($cdi.Data)) · Selic $($selic.Valor)% · IPCA 12m $($ipca.Valor)%"

"`n-- Rendimento --"
"  Bruto ao ano           {0,8:N2}%" -f $bruto
if ($aliq -gt 0) { "  IR ({0:P1} em {1} dias)  -{2,7:N2}%" -f $aliq, $dias, ($bruto - $liquido) }
else             { "  IR                        isento ($Tipo para pessoa física)" }
"  Líquido ao ano         {0,8:N2}%" -f $liquido
"  Equivale a             {0,8:N1}% do CDI, líquido" -f ($liquido / $cdi.Valor * 100)

# --- Equivalência isento x tributado ----------------------------------------
# Quanto um produto tributado precisa render para empatar com este.
$eqBruto = $liquido / (1 - $aliqPadrao)
"`n-- Equivalência --"
if ($aliq -eq 0) {
  "  Um CDB precisaria render {0,6:N2}% a.a. bruto ({1:N1}% do CDI) para empatar." -f $eqBruto, ($eqBruto/$cdi.Valor*100)
  "  É esse o número a comparar — não a taxa de vitrine."
} else {
  $eqIsento = $liquido
  "  Um LCI/LCA isento empataria rendendo {0,5:N2}% a.a. ({1:N1}% do CDI)." -f $eqIsento, ($eqIsento/$cdi.Valor*100)
}

# --- Tesouro Direto de prazo semelhante -------------------------------------
$csv = "$Cache\tesouro.csv"
$precisa = -not (Test-Path $csv) -or ((Get-Date) - (Get-Item $csv).LastWriteTime).TotalDays -gt 7
if ($precisa) {
  Write-Host "`nBaixando taxas do Tesouro (~14 MB)..."
  $pkg = Invoke-RestMethod "https://www.tesourotransparente.gov.br/ckan/api/3/action/package_show?id=taxas-dos-titulos-ofertados-pelo-tesouro-direto" -TimeoutSec 60
  $url = ($pkg.result.resources | Where-Object { $_.format -eq 'CSV' }).url
  $wc = New-Object System.Net.WebClient; $wc.DownloadFile($url, $csv); $wc.Dispose()
}
$td = Import-Csv $csv -Delimiter ';' -Encoding UTF8
$base = ($td | ForEach-Object { $_.'Data Base' } |
         Sort-Object { [datetime]::ParseExact($_,'dd/MM/yyyy',$null) } | Select-Object -Last 1)
$alvo = (Get-Date).AddYears([int]$Anos)
$hoje = $td | Where-Object { $_.'Data Base' -eq $base }
$tipoTD = if ($Indexador -eq 'IPCA') { '^Tesouro IPCA\+$' } elseif ($Indexador -eq 'PRE') { '^Tesouro Prefixado$' } else { '^Tesouro Selic$' }
$cand = $hoje | Where-Object { $_.'Tipo Titulo' -match $tipoTD } |
        Sort-Object { [Math]::Abs((([datetime]::ParseExact($_.'Data Vencimento','dd/MM/yyyy',$null)) - $alvo).TotalDays) }
$tt = $cand | Select-Object -First 1

"`n-- Tesouro Direto (base $base) --"
if ($tt) {
  $txTD = [double]::Parse(($tt.'Taxa Venda Manha' -replace ',','.'), $IC)
  $brutoTD = if ($Indexador -eq 'IPCA') { $ipca.Valor + $txTD } elseif ($Indexador -eq 'PRE') { $txTD } else { $selic.Valor + $txTD }
  $liqTD = $brutoTD * (1 - $aliqPadrao)   # Tesouro é sempre tributado
  "  $($tt.'Tipo Titulo') $($tt.'Data Vencimento') — taxa $($tt.'Taxa Venda Manha')%"
  "  Bruto {0,6:N2}%   líquido {1,6:N2}%   (risco soberano, sem risco de banco)" -f $brutoTD, $liqTD
  $dif = $liquido - $liqTD
  if ($dif -gt 0) { "  → Sua oferta paga {0:N2} p.p. a mais, líquido. Esse é o prêmio pelo risco de crédito privado." -f $dif }
  else            { "  → Sua oferta paga {0:N2} p.p. a MENOS que o título público, líquido." -f ([Math]::Abs($dif)) }
  if ($Indexador -eq 'CDI') { "  (Tesouro Selic rende Selic + spread; a taxa acima é só o spread)" }
} else { "  Sem título comparável para esse prazo e indexador." }

"`n-- Garantia --"
if ($temFGC) {
  "  Coberto pelo FGC até R$ 250.000 por CPF e por conglomerado."
  "  Teto global de R$ 1 milhão a cada 4 anos (fgc.org.br, verificado 08/08/2026)."
  if ($Valor -gt 250000) { "  ⚠ R$ {0:N0} excede o limite — R$ {1:N0} ficariam sem cobertura nesse emissor." -f $Valor, ($Valor-250000) }
} else {
  "  ⚠ $Tipo NÃO tem cobertura do FGC. O risco é integralmente do emissor —"
  "    avalie rating, garantias reais e o setor antes de comparar só pela taxa."
}

"`n-- Leia antes de decidir --"
"  Taxa maior é o preço de mais risco de crédito, mais prazo ou menos liquidez."
"  Verifique qual dos três está sendo pago aqui, e se a liquidez (diária,"
"  no vencimento ou com carência) combina com o uso que você dará ao dinheiro."
"  Título com marcação a mercado pode render diferente se vendido antes do fim."
