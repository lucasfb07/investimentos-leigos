# Fundamentos de ação a partir da DFP/ITR da CVM — substitui os endpoints
# statistics / financial-data / balance-sheet / income-statement da brapi,
# todos bloqueados no plano atual.
#
#   .\cvm-acoes.ps1 -Ticker WEGE3
#   .\cvm-acoes.ps1 -Ticker PETR4 -Ano 2024
#
# Fonte: https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/DFP/DADOS/
# Preço e valor de mercado vêm da brapi; fundamentos vêm da CVM.

param(
  [Parameter(Mandatory=$true)][string]$Ticker,
  [int]$Ano = 2025,
  [ValidateSet('anual','ltm')][string]$Modo = 'anual',
  [string]$Cache
)

$ErrorActionPreference = "Stop"
# $PSScriptRoot em default de param é frágil conforme o modo de invocação —
# resolver aqui, já no corpo.
if (-not $Cache) {
  $raizProj = Split-Path -Parent $PSCommandPath
  $Cache = Join-Path (Split-Path -Parent $raizProj) "dados"
}
if (-not (Test-Path $Cache)) { New-Item -ItemType Directory -Path $Cache -Force | Out-Null }
$IC = [Globalization.CultureInfo]::InvariantCulture
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
function N($v) { if ([string]::IsNullOrWhiteSpace($v)) { $null } else { [double]::Parse($v, $IC) } }

$Ticker = $Ticker.ToUpper()
$raizAlvo = $Ticker.Substring(0, [Math]::Min(4, $Ticker.Length))

# ---- 1. Mapa CNPJ -> ticker -------------------------------------------------
# Construído por ferramentas/mapa-cnpj.ps1. A brapi só devolve CNPJ para parte
# dos tickers (sobretudo ON), então o mapa é indexado pela RAIZ de 4 letras —
# PETR3 e PETR4 são a mesma empresa e compartilham CNPJ.
$mapFile = "$Cache\cnpj_ticker.csv"
if (-not (Test-Path $mapFile)) { throw "Mapa ausente. Rode ferramentas/mapa-cnpj.ps1 primeiro." }
$raiz = @{}
Import-Csv $mapFile -Encoding UTF8 | ForEach-Object {
  $r = $_.Ticker.Substring(0,4); if (-not $raiz.ContainsKey($r)) { $raiz[$r] = $_ }
}
if (-not $raiz.ContainsKey($raizAlvo)) {
  Write-Warning "CNPJ de $Ticker não está no mapa. Fundamentos indisponíveis — não estime."
  return
}
$emp = $raiz[$raizAlvo]
$cnpj = $emp.CNPJ

# A detecção de plano de contas é feita adiante, a partir das DESCRIÇÕES das
# contas — não do setor declarado nem de CD_CONTA fixo. Medido na DFP 2025:
#   - Banco (BBDC4): 2.03 = "Provisões" e o patrimônio está em 2.07.
#     Fixar 2.03 como PL erraria o P/VP em ~2,5x, sem erro visível.
#   - Seguradora (BBSE3, CXSE3): estrutura padrão, 2.03 = patrimônio.
# Por isso a regra por setor foi abandonada: ela recusava seguradora à toa e
# não protegia contra a variação real, que é de layout.

# ---- 3. Baixa e abre a DFP --------------------------------------------------
$zip = "$Cache\dfp_$Ano.zip"; $dir = "$Cache\dfp$Ano"
if (-not (Test-Path $zip)) {
  Write-Host "Baixando DFP $Ano da CVM (~12 MB)..."
  $wc = New-Object System.Net.WebClient; $wc.Headers.Add("User-Agent","Mozilla/5.0")
  $wc.DownloadFile("https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/DFP/DADOS/dfp_cia_aberta_$Ano.zip", $zip)
  $wc.Dispose()
}
if (-not (Test-Path $dir)) { Expand-Archive $zip -DestinationPath $dir -Force }

# Consolidado (_con) é o padrão correto; individual (_ind) é fallback com aviso.
function Carrega($doc) {
  foreach ($tipo in @('con','ind')) {
    $f = "$dir\dfp_cia_aberta_${doc}_${tipo}_$Ano.csv"
    if (-not (Test-Path $f)) { continue }
    $r = Import-Csv $f -Delimiter ';' -Encoding Default |
         Where-Object { ($_.CNPJ_CIA -replace '[^\d]','') -eq $cnpj -and $_.ORDEM_EXERC -eq 'ÚLTIMO' }
    if ($r) { return @{ Linhas = $r; Tipo = $tipo } }
  }
  $null
}
function Conta($bloco, $cd) {
  if (-not $bloco) { return $null }
  $l = $bloco.Linhas | Where-Object { $_.CD_CONTA -eq $cd } | Select-Object -First 1
  if (-not $l) { return $null }
  $v = N $l.VL_CONTA
  # ESCALA_MOEDA diz se os valores estão em unidades ou milhares.
  if ($l.ESCALA_MOEDA -match 'MIL') { $v * 1000 } else { $v }
}

$dre = Carrega 'DRE'; $bpp = Carrega 'BPP'; $bpa = Carrega 'BPA'
if (-not $dre -or -not $bpp) { Write-Warning "DFP $Ano sem dados para $Ticker."; return }
if ($dre.Tipo -eq 'ind') { Write-Warning "Usando demonstração INDIVIDUAL (consolidada ausente)." }

# Localiza a conta pela DESCRIÇÃO, não pelo código — é o que sobrevive à
# diferença de layout entre banco, seguradora e empresa operacional.
function ContaPorDesc($bloco, $padrao, $nivel) {
  if (-not $bloco) { return $null }
  $l = $bloco.Linhas | Where-Object { $_.DS_CONTA -match $padrao -and $_.CD_CONTA -match $nivel } |
       Select-Object -First 1
  if (-not $l) { return $null }
  $v = [double]::Parse($l.VL_CONTA, $IC)
  if ($l.ESCALA_MOEDA -match 'MIL') { $v * 1000 } else { $v }
}

# Banco se identifica pelo próprio texto da DRE.
$ehBanco = [bool]($dre.Linhas | Where-Object { $_.CD_CONTA -eq '3.03' -and $_.DS_CONTA -match 'Intermedia' })

$lucroLiq = Conta $dre '3.11'
$ativo    = Conta $bpa '1'
# Patrimônio: 2.03 na maioria, 2.07 em banco. A busca por descrição resolve os
# dois sem hardcode.
$patrLiq  = ContaPorDesc $bpp 'Patrim.nio L.quido' '^2\.\d\d$'
if (-not $patrLiq) { $patrLiq = Conta $bpp '2.03' }
$passTotal = Conta $bpp '2'
if ($passTotal -and $patrLiq) { $passTotal = $passTotal - $patrLiq }  # passivo exigível
$periodo  = "exercício $Ano (anual)"

if ($ehBanco) {
  # Num banco, 3.01 é receita BRUTA de juros — margem sobre ela não significa
  # nada. A base econômica é a margem financeira (3.03).
  $margemFin = Conta $dre '3.03'
  $pdd       = ContaPorDesc $dre 'Perda Esperada|Provis.o para Perda' '^3\.\d\d\.\d\d$'
  $servicos  = ContaPorDesc $dre 'Presta..o de Servi' '^3\.\d\d\.\d\d$'
  $pessoal   = ContaPorDesc $dre 'Despesas com Pessoal' '^3\.\d\d\.\d\d$'
  $receita   = $margemFin
} else {
  $receita  = Conta $dre '3.01'
  $lucroBru = Conta $dre '3.03'
  $ebit     = Conta $dre '3.05'
}

# ---- 3b. Modo LTM: DFP anual + ITR para os últimos 12 meses -----------------
# Resultado de ITR é ACUMULADO no ano, então o múltiplo calculado direto sobre
# ele fica errado. A conta certa:
#   LTM = ano cheio anterior − acumulado do ano anterior até o mesmo trimestre
#         + acumulado do ano corrente
# ORDEM_EXERC='PENÚLTIMO' no ITR já traz o mesmo período do ano anterior.
if ($Modo -eq 'ltm') {
  $anoI = $Ano + 1
  $zipI = "$Cache\itr_$anoI.zip"; $dirI = "$Cache\itr$anoI"
  if (-not (Test-Path $zipI)) {
    Write-Host "Baixando ITR $anoI da CVM (~10 MB)..."
    $wc = New-Object System.Net.WebClient; $wc.Headers.Add("User-Agent","Mozilla/5.0")
    try { $wc.DownloadFile("https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/ITR/DADOS/itr_cia_aberta_$anoI.zip", $zipI) }
    catch { Write-Warning "ITR $anoI indisponível. Seguindo com o anual."; $Modo = 'anual' }
    finally { $wc.Dispose() }
  }
  if ($Modo -eq 'ltm') {
    if (-not (Test-Path $dirI)) { Expand-Archive $zipI -DestinationPath $dirI -Force }
    $fI = "$dirI\itr_cia_aberta_DRE_$($dre.Tipo)_$anoI.csv"
    if (Test-Path $fI) {
      # Só o ACUMULADO: DT_INI_EXERC em 1º de janeiro. O arquivo também traz o
      # trimestre isolado (ex.: 01/04→30/06) para as mesmas contas.
      $itr = Import-Csv $fI -Delimiter ';' -Encoding Default |
             Where-Object { ($_.CNPJ_CIA -replace '[^\d]','') -eq $cnpj -and $_.DT_INI_EXERC -match '-01-01$' }
      $ultFim = ($itr | Where-Object { $_.ORDEM_EXERC -eq 'ÚLTIMO' } | ForEach-Object { $_.DT_FIM_EXERC } | Sort-Object | Select-Object -Last 1)
      if ($ultFim) {
        $atual = @{ Linhas = ($itr | Where-Object { $_.ORDEM_EXERC -eq 'ÚLTIMO'   -and $_.DT_FIM_EXERC -eq $ultFim }) }
        $ant   = @{ Linhas = ($itr | Where-Object { $_.ORDEM_EXERC -eq 'PENÚLTIMO' }) }
        function LTM($cd) {
          $a = Conta $atual $cd; $p = Conta $ant $cd; $f = Conta $dre $cd
          if ($null -eq $a -or $null -eq $p -or $null -eq $f) { $null } else { $f - $p + $a }
        }
        $r2=(LTM '3.01'); $b2=(LTM '3.03'); $e2=(LTM '3.05'); $l2=(LTM '3.11')
        if ($null -ne $l2) {
          $receita=$r2; $lucroBru=$b2; $ebit=$e2; $lucroLiq=$l2
          $periodo = "últimos 12 meses até $ultFim (DFP $Ano + ITR $anoI)"
          # Balanço passa a ser a foto mais recente do ITR, não a do fim do ano.
          $fB = "$dirI\itr_cia_aberta_BPP_$($dre.Tipo)_$anoI.csv"
          $fA = "$dirI\itr_cia_aberta_BPA_$($dre.Tipo)_$anoI.csv"
          if (Test-Path $fB) {
            $bb = @{ Linhas = (Import-Csv $fB -Delimiter ';' -Encoding Default | Where-Object { ($_.CNPJ_CIA -replace '[^\d]','') -eq $cnpj -and $_.ORDEM_EXERC -eq 'ÚLTIMO' -and $_.DT_FIM_EXERC -eq $ultFim }) }
            if ($bb.Linhas) { $patrLiq=(Conta $bb '2.03'); $passCirc=(Conta $bb '2.01'); $passNCirc=(Conta $bb '2.02') }
          }
          if (Test-Path $fA) {
            $aa = @{ Linhas = (Import-Csv $fA -Delimiter ';' -Encoding Default | Where-Object { ($_.CNPJ_CIA -replace '[^\d]','') -eq $cnpj -and $_.ORDEM_EXERC -eq 'ÚLTIMO' -and $_.DT_FIM_EXERC -eq $ultFim }) }
            if ($aa.Linhas) { $ativo = Conta $aa '1' }
          }
        } else { Write-Warning "ITR incompleto para $Ticker — mantendo o anual." }
      } else { Write-Warning "Sem ITR acumulado para $Ticker — mantendo o anual." }
    }
  }
}

# ---- 4. Preço e valor de mercado (brapi) ------------------------------------
$tok = $env:BRAPI_TOKEN; if (-not $tok) { $tok = [Environment]::GetEnvironmentVariable("BRAPI_TOKEN","User") }
$preco = $null; $mcap = $null
try {
  $q = (Invoke-RestMethod "https://brapi.dev/api/v2/stocks/quote?symbols=$Ticker" -Headers @{Authorization="Bearer $tok"} -TimeoutSec 20).results[0].data
  $preco = $q.regularMarketPrice; $mcap = $q.marketCap
} catch {}

# ---- 5. Saída ---------------------------------------------------------------
"`n$Ticker — $($emp.Nome)"
"$($emp.Setor) / $($emp.Subsetor) · CNPJ $cnpj"
"Período: $periodo · demonstração $($dre.Tipo.ToUpper()) · fonte CVM"
if ($preco) { "Preço R$ $preco · valor de mercado R$ {0:N0}" -f $mcap }

if ($ehBanco) {
  "`n-- Resultado (banco) --"
  "  Margem financeira      R$ {0,18:N0}" -f $margemFin
  if ($servicos) { "  Receita de serviços    R$ {0,18:N0}" -f $servicos }
  if ($pdd)      { "  Provisão p/ perdas     R$ {0,18:N0}   {1:P1} da margem" -f $pdd, ([Math]::Abs($pdd)/$margemFin) }
  if ($pessoal)  { "  Despesas com pessoal   R$ {0,18:N0}" -f $pessoal }
  if ($lucroLiq) { "  Lucro líquido          R$ {0,18:N0}" -f $lucroLiq }
  "  (margem sobre receita não se aplica: 3.01 é juros brutos, não faturamento)"
} else {
  # Margem só faz sentido com receita positiva. Holding e seguradora às vezes
  # não preenchem 3.01 no consolidado — nesses casos mostra o valor sem margem
  # em vez de dividir por zero e imprimir "∞".
  $temRec = ($null -ne $receita -and $receita -gt 0)
  "`n-- Resultado --"
  if ($temRec)   { "  Receita líquida        R$ {0,18:N0}" -f $receita }
  else           { "  Receita líquida        não informada no consolidado" }
  if ($lucroBru) { if ($temRec) { "  Lucro bruto            R$ {0,18:N0}   margem {1:P1}" -f $lucroBru,($lucroBru/$receita) } else { "  Lucro bruto            R$ {0,18:N0}" -f $lucroBru } }
  if ($ebit)     { if ($temRec) { "  Resultado operacional  R$ {0,18:N0}   margem {1:P1}" -f $ebit,($ebit/$receita) }         else { "  Resultado operacional  R$ {0,18:N0}" -f $ebit } }
  if ($lucroLiq) { if ($temRec) { "  Lucro líquido          R$ {0,18:N0}   margem {1:P1}" -f $lucroLiq,($lucroLiq/$receita) } else { "  Lucro líquido          R$ {0,18:N0}" -f $lucroLiq } }
}

"`n-- Balanço --"
if ($ativo)     { "  Ativo total            R$ {0,18:N0}" -f $ativo }
if ($patrLiq)   { "  Patrimônio líquido     R$ {0,18:N0}" -f $patrLiq }
if ($passTotal) { "  Passivo exigível       R$ {0,18:N0}" -f $passTotal }
if ($ativo -and $patrLiq) { "  Alavancagem            {0,10:N1}x  (ativo / patrimônio)" -f ($ativo/$patrLiq) }

"`n-- Múltiplos e retorno --"
if ($mcap -and $lucroLiq -gt 0) { "  P/L                    {0,10:N2}" -f ($mcap/$lucroLiq) }
elseif ($lucroLiq -le 0)        { "  P/L                    n/a (prejuízo no exercício)" }
if ($mcap -and $patrLiq -gt 0)  { "  P/VP                   {0,10:N2}" -f ($mcap/$patrLiq) }
if ($lucroLiq -and $patrLiq -gt 0) { "  ROE                    {0,10:P1}" -f ($lucroLiq/$patrLiq) }
if ($lucroLiq -and $ativo -gt 0)   { "  ROA                    {0,10:P1}" -f ($lucroLiq/$ativo) }

if ($Modo -eq 'anual') { "`nDFP é anual e sai ~3 meses após o fechamento. Para dado mais recente: -Modo ltm" }
else { "`nLTM combina o ano cheio da DFP com o acumulado do ITR — mede os últimos 12 meses, não o ano-calendário." }
