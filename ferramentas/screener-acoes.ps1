# Screener de ações sobre a DFP da CVM, com critérios explícitos do usuário.
#
#   .\screener-acoes.ps1
#   .\screener-acoes.ps1 -RetornoExigido 15 -MaxDivida 2 -MaxPayout 80
#   .\screener-acoes.ps1 -Ticker WEGE3          # detalha um papel só
#
# NÃO é lista de compra. É um filtro mecânico: aplica os critérios que VOCÊ
# define e mostra o que passa, com o dado bruto de cada linha para conferência.
# Passar no filtro não diz nada sobre a empresa além dos números filtrados.

param(
  [double]$RetornoExigido = 12,   # lucro/preço alvo, em % — define o preço-teto
  [double]$MaxDivida = 3,         # dívida líquida / EBITDA
  [double]$MaxPayout = 100,       # dividendos / lucro, em %
  [double]$MinCrescLucro = -999,  # CAGR do lucro, em % ao ano
  [double]$MinLucro = 0,          # lucro líquido mínimo, R$
  [int]$MinAnosLucro = 0,         # exercícios com lucro positivo (máx 3)
  [string]$Ticker,
  [int]$Top = 30,
  [string]$Cache
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$IC = [Globalization.CultureInfo]::InvariantCulture
if (-not $Cache) { $d = Split-Path -Parent $PSCommandPath; $Cache = Join-Path (Split-Path -Parent $d) "dados" }
function N($v) { if ([string]::IsNullOrWhiteSpace($v)) { $null } else { [double]::Parse($v, $IC) } }

$anos = @(2025, 2024, 2023)
$mapa = Import-Csv "$Cache\cnpj_ticker.csv" -Encoding UTF8
$raiz = @{}; $mapa | ForEach-Object { $r = $_.Ticker.Substring(0,4); if (-not $raiz.ContainsKey($r)) { $raiz[$r] = $_ } }

Write-Host "Carregando DFP $($anos -join ', ')..."
# Indexa por CNPJ+ano. Escala em MIL é o padrão da CVM; normalizar aqui evita
# comparar empresa em milhares com empresa em unidades.
function Carrega($ano, $doc) {
  $f = "$Cache\dfp$ano\dfp_cia_aberta_${doc}_con_$ano.csv"
  if (-not (Test-Path $f)) { return @{} }
  $h = @{}
  Import-Csv $f -Delimiter ';' -Encoding Default | Where-Object { $_.ORDEM_EXERC -eq 'ÚLTIMO' } | ForEach-Object {
    $k = ($_.CNPJ_CIA -replace '[^\d]','')
    if (-not $h.ContainsKey($k)) { $h[$k] = @{} }
    $mult = if ($_.ESCALA_MOEDA -match 'MIL') { 1000 } else { 1 }
    $h[$k][$_.CD_CONTA] = @{ V = (N $_.VL_CONTA) * $mult; D = $_.DS_CONTA }
  }
  $h
}
$DRE = @{}; $BPP = @{}; $BPA = @{}; $DFC = @{}
foreach ($a in $anos) { $DRE[$a] = Carrega $a 'DRE'; $BPP[$a] = Carrega $a 'BPP'; $BPA[$a] = Carrega $a 'BPA'; $DFC[$a] = Carrega $a 'DFC_MI' }

# Remuneração ao acionista vem da DMPL, não da brapi — stocks/dividends dá 403
# fora dos 4 tickers de sandbox. Dividendos e JCP são LINHAS SEPARADAS (5.04.*)
# e precisam ser somados; usar só "Dividendos" subestima quem remunera via JCP.
Write-Host "Carregando remuneracao ao acionista (DMPL)..."
# Hashtable PLANA, só do exercício corrente. Aninhar por ano dentro de script
# .ps1 estava corrompendo o nó (virava Int32 no acesso).
$REM2025 = @{}
foreach ($a in @(2025)) {
  $f = "$Cache\dfp$a\dfp_cia_aberta_DMPL_con_$a.csv"
  if (-not (Test-Path $f)) { continue }
  # A DMPL repete cada conta em várias COLUNA_DF ("Patrimônio Líquido" e
  # "Patrimônio Líquido Consolidado"), então somar direto DOBRA o valor.
  # Deduplica por CNPJ+conta antes de somar.
  # Monta em hashtable LOCAL: `+=` direto em hashtable aninhada dentro de
  # pipeline corrompe a estrutura (o nó vira o próprio número).
  $acc = @{}; $visto = @{}
  $linhas = Import-Csv $f -Delimiter ';' -Encoding Default | Where-Object {
    $_.ORDEM_EXERC -eq 'ÚLTIMO' -and $_.CD_CONTA -match '^5\.04' -and
    $_.COLUNA_DF -match 'Patrim.nio L.quido' -and
    # "Dividendos com reservas" fica FORA: é distribuição de lucro acumulado de
    # exercícios anteriores, não do resultado do ano. Incluir infla o payout.
    $_.DS_CONTA -match '^(Dividendos|Juros sobre Capital Pr.prio)$'
  }
  foreach ($l in $linhas) {
    $k = ($l.CNPJ_CIA -replace '[^\d]','')
    $chave = "$k|$($l.CD_CONTA)"
    if ($visto.ContainsKey($chave)) { continue }
    $visto[$chave] = 1
    $mult = if ($l.ESCALA_MOEDA -match 'MIL') { 1000 } else { 1 }
    $v = [Math]::Abs((N $l.VL_CONTA) * $mult)
    if ($acc.ContainsKey($k)) { $acc[$k] = $acc[$k] + $v } else { $acc[$k] = $v }
  }
  $REM2025 = $acc
}
Write-Host "  remuneracao carregada para $($REM2025.Count) empresas"

function V($tab, $ano, $cnpj, $cd) {
  if ($tab[$ano].ContainsKey($cnpj) -and $tab[$ano][$cnpj].ContainsKey($cd)) { $tab[$ano][$cnpj][$cd].V } else { $null }
}
# Soma contas cuja DESCRIÇÃO casa — o código varia entre setores.
function SomaDesc($tab, $ano, $cnpj, $padrao, $nivel) {
  if (-not $tab[$ano].ContainsKey($cnpj)) { return 0 }
  $s = 0
  foreach ($kv in $tab[$ano][$cnpj].GetEnumerator()) {
    if ($kv.Key -match $nivel -and $kv.Value.D -match $padrao) { $s += $kv.Value.V }
  }
  $s
}

# ---- Crescimento TRIMESTRAL (ITR) -------------------------------------------
# O CAGR anual usa exercícios fechados, então fica até 8 meses velho. O ITR traz
# o acumulado do ano contra o MESMO período do ano anterior (ORDEM_EXERC
# PENÚLTIMO), que é a comparação trimestral padrão e a mais recente disponível.
# Só o acumulado (DT_INI em 1º de janeiro): o arquivo também traz o trimestre
# isolado, e misturar os dois compara períodos de tamanhos diferentes.
Write-Host "Carregando crescimento trimestral (ITR)..."
# NÃO chamar de $TRI: colide com o $tri usado logo abaixo, porque PowerShell
# ignora maiúsculas — a hashtable virava string e o índice quebrava.
$MapaTri = @{}
$anoI = $anos[0] + 1
$fItr = "$Cache\itr$anoI\itr_cia_aberta_DRE_con_$anoI.csv"
if (Test-Path $fItr) {
  $linhas = Import-Csv $fItr -Delimiter ';' -Encoding Default |
            Where-Object { $_.DT_INI_EXERC -match '-01-01$' -and $_.CD_CONTA -in @('3.01','3.11') }
  $porEmp = @{}
  foreach ($l in $linhas) {
    $k = ($l.CNPJ_CIA -replace '[^\d]','')
    if (-not $porEmp.ContainsKey($k)) { $porEmp[$k] = @() }
    $porEmp[$k] += $l
  }
  foreach ($k in $porEmp.Keys) {
    $rs = $porEmp[$k]
    # Trimestre mais recente que a empresa entregou.
    $tri = ($rs | Where-Object { $_.ORDEM_EXERC -eq 'ÚLTIMO' } | ForEach-Object { $_.DT_FIM_EXERC } | Sort-Object | Select-Object -Last 1)
    if (-not $tri) { continue }
    function Val($ordem, $cd, $fim) {
      $x = $rs | Where-Object { $_.ORDEM_EXERC -eq $ordem -and $_.CD_CONTA -eq $cd -and ($null -eq $fim -or $_.DT_FIM_EXERC -eq $fim) } | Select-Object -First 1
      if (-not $x) { return $null }
      $v = N $x.VL_CONTA
      if ($x.ESCALA_MOEDA -match 'MIL') { $v * 1000 } else { $v }
    }
    $lucA = Val 'ÚLTIMO' '3.11' $tri;    $lucP = Val 'PENÚLTIMO' '3.11' $null
    $recA = Val 'ÚLTIMO' '3.01' $tri;    $recP = Val 'PENÚLTIMO' '3.01' $null
    # Base negativa não vira percentual — mesma regra do CAGR anual.
    $cl = if ($null -ne $lucA -and $null -ne $lucP -and $lucP -gt 0) { ($lucA/$lucP - 1)*100 } else { $null }
    $cr = if ($null -ne $recA -and $null -ne $recP -and $recP -gt 0) { ($recA/$recP - 1)*100 } else { $null }
    $MapaTri[$k] = @{ tri=$tri; cl=$cl; cr=$cr; virada=($null -ne $lucP -and $lucP -le 0 -and $null -ne $lucA -and $lucA -gt 0) }
  }
  Write-Host "  crescimento trimestral para $($MapaTri.Count) empresas"
} else { Write-Warning "ITR $anoI ausente — crescimento trimestral indisponível" }

$tok = $env:BRAPI_TOKEN; if (-not $tok) { $tok = [Environment]::GetEnvironmentVariable("BRAPI_TOKEN","User") }
$hdr = @{ Authorization = "Bearer $tok" }

$alvos = if ($Ticker) { @($raiz[$Ticker.Substring(0,4)]) } else { $raiz.Values }
$alvos = $alvos | Where-Object { $_ }
Write-Host "Avaliando $($alvos.Count) empresas..."

$res = @(); $i = 0
foreach ($e in $alvos) {
  $i++
  if (-not $Ticker -and $i % 40 -eq 0) { Write-Host "  $i/$($alvos.Count)..." }
  $cnpj = $e.CNPJ
  # Banco tem plano de contas próprio: dívida líquida/EBITDA não se aplica a
  # quem capta como negócio. Fica fora do screener, não é omissão.
  $ehBanco = $false
  $c303 = if ($DRE[2025].ContainsKey($cnpj) -and $DRE[2025][$cnpj].ContainsKey('3.03')) { $DRE[2025][$cnpj]['3.03'].D } else { '' }
  if ($c303 -match 'Intermedia') { $ehBanco = $true }
  if ($ehBanco) { continue }

  $lucro = V $DRE 2025 $cnpj '3.11'
  if ($null -eq $lucro) { continue }
  $receita = V $DRE 2025 $cnpj '3.01'
  $ebit    = V $DRE 2025 $cnpj '3.05'
  $patr    = SomaDesc $BPP 2025 $cnpj 'Patrim.nio L.quido' '^2\.\d\d$'
  $ativo   = V $BPA 2025 $cnpj '1'
  $dep     = SomaDesc $DFC 2025 $cnpj 'Deprecia|Amortiza' '^6\.'
  $ebitda  = if ($null -ne $ebit) { $ebit + [Math]::Abs($dep) } else { $null }

  $divCP = SomaDesc $BPP 2025 $cnpj '^Empr.stimos e Financiamentos$' '^2\.01\.\d\d$'
  $divLP = SomaDesc $BPP 2025 $cnpj '^Empr.stimos e Financiamentos$' '^2\.02\.\d\d$'
  $caixa = (SomaDesc $BPA 2025 $cnpj 'Caixa e Equivalentes' '^1\.01\.\d\d$') + (SomaDesc $BPA 2025 $cnpj '^Aplica..es Financeiras$' '^1\.01\.\d\d$')
  $divLiq = $divCP + $divLP - $caixa
  $divEbitda = if ($ebitda -and $ebitda -gt 0) { $divLiq / $ebitda } else { $null }

  # Previsibilidade: exercícios com lucro positivo entre os anos carregados.
  $anosLucro = 0; $lucros = @()
  foreach ($a in $anos) { $l = V $DRE $a $cnpj '3.11'; if ($null -ne $l) { $lucros += $l; if ($l -gt 0) { $anosLucro++ } } }

  # Crescimento do lucro e da receita entre o exercício mais antigo carregado e
  # o mais recente, anualizado (CAGR). Mede a empresa ficando maior — que é o
  # que sustenta valorização no longo prazo, diferente da alta do preço.
  # Base negativa ou zero invalida o cálculo: sair de prejuízo para lucro não é
  # "crescimento de X%", é mudança de sinal, e tratar como percentual engana.
  function Cagr($ini, $fim, $per) {
    if ($null -eq $ini -or $null -eq $fim) { return $null }
    if ($ini -le 0 -or $fim -le 0 -or $per -lt 1) { return $null }
    ([Math]::Pow($fim/$ini, 1/$per) - 1) * 100
  }
  $anoIni = $anos[-1]; $anoFim = $anos[0]; $per = $anos.Count - 1
  $lucroIni = V $DRE $anoIni $cnpj '3.11'; $recIni = V $DRE $anoIni $cnpj '3.01'
  $cresLucro  = Cagr $lucroIni $lucro   $per
  $cresReceita= Cagr $recIni   $receita $per
  # Sinaliza virada de prejuízo para lucro, que o CAGR não consegue expressar.
  $viradaLucro = ($null -ne $lucroIni -and $lucroIni -le 0 -and $lucro -gt 0)

  $rem = 0
  if ($REM2025.ContainsKey($cnpj)) { $rem = $REM2025[$cnpj] }

  $preco = $null; $mcap = $null
  try {
    $q = (Invoke-RestMethod "https://brapi.dev/api/v2/stocks/quote?symbols=$($e.Ticker)" -Headers $hdr -TimeoutSec 15).results[0].data
    $preco = $q.regularMarketPrice; $mcap = $q.marketCap
  } catch {}
  if (-not $mcap -or -not $preco) { continue }
  Start-Sleep -Milliseconds 90

  $acoes  = $mcap / $preco
  $lpa    = $lucro / $acoes
  $div12  = if ($acoes -gt 0) { $rem / $acoes } else { 0 }   # remuneração por ação
  $payout = if ($lucro -gt 0) { $rem / $lucro * 100 } else { $null }
  $ey     = $lucro / $mcap * 100                       # lucro/preço, em %
  # Preço que faria o lucro/preço igualar o retorno exigido.
  $teto   = if ($lucro -gt 0) { $lpa / ($RetornoExigido/100) } else { $null }

  $res += [pscustomobject]@{
    Ticker=$e.Ticker; Nome=$e.Nome; Setor=$e.Setor; Preco=$preco; MCap=$mcap
    Lucro=$lucro; Receita=$receita; MargemLiq=$(if($receita -gt 0){$lucro/$receita*100}else{$null})
    ROE=$(if($patr -gt 0){$lucro/$patr*100}else{$null}); DivLiqEbitda=$divEbitda
    Payout=$payout; DY=$(if($preco -gt 0){$div12/$preco*100}else{0}); EarningsYield=$ey
    PrecoTeto=$teto; Desconto=$(if($teto){($teto/$preco-1)*100}else{$null})
    AnosLucro=$anosLucro; DivLiq=$divLiq; Ebitda=$ebitda
    CrescLucro=$cresLucro; CrescReceita=$cresReceita; ViradaLucro=$viradaLucro
    AnosCresc=$per
    # Trimestral: mais recente, e é o que o filtro usa.
    CrescLucroTri=$(if($MapaTri.ContainsKey($cnpj)){$MapaTri[$cnpj].cl}else{$null})
    CrescReceitaTri=$(if($MapaTri.ContainsKey($cnpj)){$MapaTri[$cnpj].cr}else{$null})
    ViradaTri=$(if($MapaTri.ContainsKey($cnpj)){$MapaTri[$cnpj].virada}else{$false})
    TrimestreRef=$(if($MapaTri.ContainsKey($cnpj)){$MapaTri[$cnpj].tri}else{$null})
  }
}

# --- Filtros -----------------------------------------------------------------
$ok = $res | Where-Object {
  $_.Lucro -gt $MinLucro -and
  $_.AnosLucro -ge $MinAnosLucro -and
  ($null -eq $_.DivLiqEbitda -or $_.DivLiqEbitda -le $MaxDivida) -and
  ($null -eq $_.Payout -or ($_.Payout -le $MaxPayout -and $_.Payout -ge 0)) -and
  # Filtra pelo TRIMESTRAL, que é o dado mais recente. Cai para o CAGR anual
  # só quando a empresa não entregou ITR comparável.
  ($MinCrescLucro -le -999 -or (
     ($null -ne $_.CrescLucroTri -and $_.CrescLucroTri -ge $MinCrescLucro) -or
     ($null -eq $_.CrescLucroTri -and $null -ne $_.CrescLucro -and $_.CrescLucro -ge $MinCrescLucro)))
}

"`n=== Screener de ações — DFP 2025 ==="
"Critérios: retorno exigido {0}% · dívida líq/EBITDA ≤ {1} · payout ≤ {2}% · anos com lucro ≥ {3}" -f $RetornoExigido,$MaxDivida,$MaxPayout,$MinAnosLucro
"Avaliadas {0} · passaram {1}  (bancos fora: plano de contas incompatível)" -f $res.Count, $ok.Count

"`n{0,-8}{1,9}{2,8}{3,8}{4,11}{5,11}{6,9}{7,9}{8,10}" -f "Ticker","Preço","L/P %","ROE %","Luc tri YoY","Rec tri YoY","Trim","Payout","Dív/EBITDA"
$ok | Sort-Object EarningsYield -Descending | Select-Object -First $Top | ForEach-Object {
  $cl = if ($_.ViradaTri) { "virada" } elseif ($null -ne $_.CrescLucroTri) { "{0:N1}%" -f $_.CrescLucroTri }
        elseif ($null -ne $_.CrescLucro) { "{0:N1}%*" -f $_.CrescLucro } else { "—" }
  $cr = if ($null -ne $_.CrescReceitaTri) { "{0:N1}%" -f $_.CrescReceitaTri }
        elseif ($null -ne $_.CrescReceita) { "{0:N1}%*" -f $_.CrescReceita } else { "—" }
  $tr = if ($_.TrimestreRef) { ([datetime]$_.TrimestreRef).ToString('MM/yy') } else { "anual" }
  "{0,-8}{1,9:N2}{2,8:N1}{3,8:N1}{4,11}{5,11}{6,9}{7,9:N0}{8,10:N2}" -f `
    $_.Ticker,$_.Preco,$_.EarningsYield,$_.ROE,$cl,$cr,$tr,$_.Payout,$_.DivLiqEbitda
}
"`n  * = CAGR anual (2023–2025): a empresa não entregou ITR comparável."

$out = "$Cache\screener_acoes.csv"
$res | Export-Csv $out -NoTypeInformation -Encoding UTF8
"`nBase completa (inclusive reprovados): $out"

"`n-- Como ler --"
"  L/P % é o lucro do exercício dividido pelo valor de mercado — o 'dividend"
"  yield' que a empresa teria se distribuísse todo o lucro. Não é o que ela paga."
"  Teto R\$ é o preço em que L/P igualaria $RetornoExigido%. É aritmética sobre o"
"  lucro de UM exercício passado, não previsão: lucro cai, o teto cai junto."
"  Desc % positivo = preço atual abaixo desse teto."
"  Passar no filtro não é recomendação. Setor, governança, ciclo e concorrência"
"  não entram em nenhuma dessas contas."
