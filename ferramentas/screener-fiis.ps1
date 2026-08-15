# Screener de FIIs sobre o Informe Mensal da CVM.
#
#   .\screener-fiis.ps1
#   .\screener-fiis.ps1 -Segmento tijolo -MinPL 5e8 -MaxPVP 1.0
#   .\screener-fiis.ps1 -Ticker MXRF11
#
# ⚠️ VACÂNCIA NÃO ENTRA. O Informe Mensal da CVM não tem esse campo — só
# `Contas_Receber_Aluguel`, que é outra coisa. Vacância existe por fundo, no
# relatório gerencial (FNET), não em base comparável. Qualquer screener que
# afirme filtrar FII por vacância está estimando.

param(
  [ValidateSet('todos','papel','tijolo')][string]$Segmento = 'todos',
  [double]$MinPL = 3e8,
  [double]$MaxPVP = 99,
  [double]$MinDY = 0,
  [double]$MaxTaxa = 99,
  [string]$Ticker,
  [int]$Top = 25,
  [string]$Cache
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$IC = [Globalization.CultureInfo]::InvariantCulture
if (-not $Cache) { $d = Split-Path -Parent $PSCommandPath; $Cache = Join-Path (Split-Path -Parent $d) "dados" }
function N($v) { if ([string]::IsNullOrWhiteSpace($v)) { 0 } else { [double]::Parse($v, $IC) } }
# Export-Csv grava com a cultura LOCAL (vírgula decimal em pt-BR), mas os CSVs
# da CVM usam ponto. Ler um com o parser do outro corrompe a escala em silêncio —
# 0,2927 vira 29 quatrilhões. Este parser aceita as duas formas.
function NC($v) {
  if ([string]::IsNullOrWhiteSpace($v)) { return $null }
  $s = "$v".Trim()
  if ($s -match ',') { $s = ($s -replace '\.','') -replace ',','.' }
  try { [double]::Parse($s, $IC) } catch { $null }
}

$dir = "$Cache\inf_mensal_fii_2026"
if (-not (Test-Path $dir)) { throw "Base ausente. Rode cvm-fii.ps1 uma vez para baixar." }

$geral = Import-Csv "$dir\inf_mensal_fii_geral_2026.csv" -Delimiter ';' -Encoding Default
# A competência mais recente costuma estar quase vazia — pega a última com
# cobertura >= 80% do pico.
$porMes = $geral | Group-Object Data_Referencia | Sort-Object Name
$pico = ($porMes | Measure-Object Count -Maximum).Maximum
$REF = ($porMes | Where-Object { $_.Count -ge $pico * 0.8 } | Select-Object -Last 1).Name
Write-Host "Competência: $REF"

$g = @{}; $geral | Where-Object { $_.Data_Referencia -eq $REF } | ForEach-Object { $g[$_.CNPJ_Fundo_Classe] = $_ }
$a = @{}; Import-Csv "$dir\inf_mensal_fii_ativo_passivo_2026.csv" -Delimiter ';' -Encoding Default |
     Where-Object { $_.Data_Referencia -eq $REF } | ForEach-Object { $a[$_.CNPJ_Fundo_Classe] = $_ }

# Vacância vem do Informe TRIMESTRAL (o mensal não tem o campo). Gerado por
# cvm-fii-imoveis.ps1; se ausente, o screener roda sem vacância e avisa.
$VAC = @{}
$fv = "$Cache\fii_imoveis.csv"
if (Test-Path $fv) {
  Import-Csv $fv -Encoding UTF8 | ForEach-Object {
    $k = ($_.CNPJ -replace '[^\d]','')
    $VAC[$k] = $_
  }
  Write-Host "Vacância carregada para $($VAC.Count) fundos (Informe Trimestral)"
} else {
  Write-Warning "Sem dados de vacância. Rode ferramentas\cvm-fii-imoveis.ps1 primeiro."
}

# ---- Série mensal: o DY de um mês x 12 não descreve o fundo -------------------
# Um mês com receita não recorrente infla o número inteiro. Com a série do
# Informe Mensal dá para medir o que importa de verdade:
#   1. quanto ele DISTRIBUIU de fato no período (composto, não extrapolado)
#   2. quanto o PATRIMÔNIO por cota variou no mesmo período
#   3. a soma dos dois, que é o retorno econômico real
#   4. se parte da distribuição saiu do capital em vez do resultado
#   5. o quanto a distribuição mensal oscila
$SERIE = @{}
$todasLinhas = Import-Csv "$dir\inf_mensal_fii_complemento_2026.csv" -Delimiter ';' -Encoding Default |
               Where-Object { $_.Data_Referencia -le $REF }
# $grpSerie, não $g: $g já é a hashtable do cadastro geral e o laço a
# sobrescrevia, zerando a base inteira sem erro visível.
foreach ($grpSerie in ($todasLinhas | Group-Object CNPJ_Fundo_Classe)) {
  $rs = @($grpSerie.Group | Sort-Object Data_Referencia)
  if ($rs.Count -lt 3) { continue }   # menos de 3 meses não sustenta média
  $fdy = 1.0; $fpat = 1.0; $dys = @(); $n = 0
  foreach ($r in $rs) {
    $dy  = N $r.Percentual_Dividend_Yield_Mes
    $pat = N $r.Percentual_Rentabilidade_Patrimonial_Mes
    if ($null -ne $dy)  { $fdy  *= (1 + $dy);  $dys += $dy; $n++ }
    if ($null -ne $pat) { $fpat *= (1 + $pat) }
  }
  if ($n -lt 3) { continue }
  $dyAcum  = ($fdy  - 1) * 100
  $patAcum = ($fpat - 1) * 100
  # Anualiza pelo número de meses efetivamente observados.
  $dyAno = ([Math]::Pow($fdy, 12.0/$n) - 1) * 100
  # Retorno econômico: o que pingou na conta MAIS o que aconteceu com o
  # patrimônio. Distribuição alta com patrimônio caindo não é retorno cheio.
  # ANUALIZADO pelo mesmo critério do DY — misturar taxa anual com retorno de
  # 6 meses na mesma tabela compara coisas de tamanhos diferentes.
  $retTotal = ([Math]::Pow($fdy * $fpat, 12.0/$n) - 1) * 100
  $patAno   = ([Math]::Pow($fpat, 12.0/$n) - 1) * 100
  # Quando o patrimônio encolhe, essa fatia da distribuição veio do capital.
  $erosao = if ($patAcum -lt 0 -and $dyAcum -gt 0) { [Math]::Min(100, (-$patAcum / $dyAcum) * 100) } else { 0 }
  # Oscilação da distribuição mensal: quanto menor, mais previsível a renda.
  $cv = $null
  if ($dys.Count -ge 3) {
    $m = ($dys | Measure-Object -Average).Average
    if ($m -gt 0) {
      $sd = [Math]::Sqrt((($dys | ForEach-Object { [Math]::Pow($_-$m,2) } | Measure-Object -Sum).Sum)/($dys.Count-1))
      $cv = $sd/$m*100
    }
  }
  # patAcum fica no período (é variação de estoque, não taxa); patAno anualiza
  # para poder somar com o DY na mesma unidade.
  $SERIE[$grpSerie.Name] = @{ meses=$n; dyAcum=$dyAcum; dyAno=$dyAno
                              patAcum=$patAcum; patAno=$patAno
                              retTotal=$retTotal; erosao=$erosao; cv=$cv }
}
Write-Host "Série mensal montada para $($SERIE.Count) fundos"

$base = foreach ($c in (Import-Csv "$dir\inf_mensal_fii_complemento_2026.csv" -Delimiter ';' -Encoding Default | Where-Object { $_.Data_Referencia -eq $REF })) {
  $k = $c.CNPJ_Fundo_Classe; $gg = $g[$k]; $aa = $a[$k]
  if (-not $gg -or -not $aa) { continue }
  if ($gg.Codigo_ISIN -notmatch '^BR(.{4})CTF') { continue }
  $tk = $Matches[1] + "11"
  $inv = N $aa.Total_Investido; if ($inv -le 0) { continue }

  $cri    = (N $aa.CRI) + (N $aa.CRI_CRA)
  $imovel = (N $aa.Imoveis_Renda_Acabados) + (N $aa.Imoveis_Renda_Construcao) +
            (N $aa.Imoveis_Venda_Acabados) + (N $aa.Imoveis_Venda_Construcao) + (N $aa.Terrenos)
  $fii    = N $aa.FII
  $outros = $inv - $cri - $imovel - $fii

  # Concentração por CLASSE de ativo (não por imóvel individual — esse dado não
  # existe na base). Índice de Herfindahl: 1 = tudo numa classe só.
  $pesos = @($cri, $imovel, $fii, [Math]::Max($outros,0)) | ForEach-Object { $_ / $inv }
  $hhi = ($pesos | ForEach-Object { $_ * $_ } | Measure-Object -Sum).Sum

  $kv = ($k -replace '[^\d]',''); $v = $VAC[$kv]
  [pscustomobject]@{
    Ticker = $tk; Nome = $gg.Nome_Fundo_Classe; Gestao = $gg.Tipo_Gestao; Mandato = $gg.Mandato
    PL = N $c.Patrimonio_Liquido; VPcota = N $c.Valor_Patrimonial_Cotas
    TaxaAno = (N $c.Percentual_Despesas_Taxa_Administracao) * 12
    DYmes = N $c.Percentual_Dividend_Yield_Mes
    RentMes = N $c.Percentual_Rentabilidade_Efetiva_Mes
    Cotistas = [int]$c.Total_Numero_Cotistas
    PctCRI = $cri/$inv; PctImovel = $imovel/$inv; PctFII = $fii/$inv
    Concentracao = $hhi
    Tipo = if ($cri/$inv -gt 0.5) { 'papel' } elseif ($imovel/$inv -gt 0.5) { 'tijolo' } else { 'híbrido' }
    # Do Informe Trimestral. Vazio em FII de papel (não tem imóvel) e em fundo
    # que não preencheu — vazio NÃO é zero.
    NImoveis  = if ($v) { [int]$v.NImoveis } else { $null }
    VacFisica = if ($v) { NC $v.VacFisica } else { $null }
    VacFinan  = if ($v) { NC $v.VacFinanceira } else { $null }
    InadImov  = if ($v) { NC $v.Inadimplencia } else { $null }
    ConcImovel= if ($v) { NC $v.ConcReceita } else { $null }
    CobVac    = if ($v) { NC $v.Cobertura } else { $null }
    # Da série mensal — substituem o DY extrapolado de um mês só.
    Meses     = if ($SERIE.ContainsKey($k)) { $SERIE[$k].meses }    else { $null }
    DYreal    = if ($SERIE.ContainsKey($k)) { $SERIE[$k].dyAno }    else { $null }
    # Anualizado, para a linha fechar: DY + patrimônio ≈ retorno total.
    PatAcum   = if ($SERIE.ContainsKey($k)) { $SERIE[$k].patAno }   else { $null }
    PatPeriodo= if ($SERIE.ContainsKey($k)) { $SERIE[$k].patAcum }  else { $null }
    RetTotal  = if ($SERIE.ContainsKey($k)) { $SERIE[$k].retTotal } else { $null }
    Erosao    = if ($SERIE.ContainsKey($k)) { $SERIE[$k].erosao }   else { $null }
    DYcv      = if ($SERIE.ContainsKey($k)) { $SERIE[$k].cv }       else { $null }
  }
}
Write-Host "Fundos na base: $($base.Count)"

$sel = $base | Where-Object { $_.PL -ge $MinPL }
if ($Segmento -ne 'todos') { $sel = $sel | Where-Object { $_.Tipo -eq $Segmento } }
if ($Ticker) { $sel = $base | Where-Object { $_.Ticker -eq $Ticker.ToUpper() } }

# Preço só existe na brapi — uma chamada por ticker (limite do plano).
$tok = $env:BRAPI_TOKEN; if (-not $tok) { $tok = [Environment]::GetEnvironmentVariable("BRAPI_TOKEN","User") }
$hdr = @{ Authorization = "Bearer $tok" }
$alvo = $sel | Sort-Object PL -Descending | Select-Object -First ([Math]::Min(40, $sel.Count))
Write-Host "Buscando preço de $($alvo.Count) fundos..."
$res = foreach ($f in $alvo) {
  try {
    $q = (Invoke-RestMethod "https://brapi.dev/api/v2/stocks/quote?symbols=$($f.Ticker)" -Headers $hdr -TimeoutSec 15).results[0].data
    if ($q.regularMarketPrice -and $f.VPcota -gt 0) {
      $f | Add-Member Preco $q.regularMarketPrice -Force
      $f | Add-Member PVP ($q.regularMarketPrice / $f.VPcota) -Force
      $f | Add-Member DYano ($f.DYmes * 12 * 100) -Force
      $f
    }
  } catch {}
  Start-Sleep -Milliseconds 150
}

# Guarda contra registro de outra CLASSE do mesmo fundo. Depois da regulação de
# classes, um ISIN pode apontar para uma classe institucional com VP/cota na casa
# dos milhares e um punhado de cotistas — XPML11 aparecia com VP R$ 22.492 e 11
# cotistas, gerando P/VP 0,005. Descarta em vez de exibir número sem sentido.
$suspeitos = $res | Where-Object { $_.PVP -lt 0.2 -or $_.PVP -gt 3 -or $_.Cotistas -lt 500 }
if ($suspeitos) {
  Write-Warning "Descartados $($suspeitos.Count) por P/VP fora de [0,2 – 3] ou < 500 cotistas (provável classe institucional):"
  $suspeitos | ForEach-Object { Write-Warning ("  {0} P/VP {1:N3} · {2:N0} cotistas" -f $_.Ticker, $_.PVP, $_.Cotistas) }
}
$res = $res | Where-Object { $_.PVP -ge 0.2 -and $_.PVP -le 3 -and $_.Cotistas -ge 500 }

$ok = $res | Where-Object { $_.PVP -le $MaxPVP -and $_.DYano -ge $MinDY -and $_.TaxaAno -le ($MaxTaxa/100) }

"`n=== Screener de FIIs — Informe Mensal CVM $REF ==="
"Filtros: segmento $Segmento · PL ≥ R$ {0:N0} · P/VP ≤ {1} · DY ano ≥ {2}%" -f $MinPL, $MaxPVP, $MinDY
"Com preço: {0} · passaram: {1}" -f $res.Count, $ok.Count

"`n{0,-9}{1,-8}{2,8}{3,8}{4,9}{5,10}{6,10}{7,9}{8,8}" -f "Ticker","Tipo","P/VP","DY real","Patrim.","Ret total","Do capital","Oscil.","Vac fís"
$ok | Sort-Object { -$_.RetTotal } | Select-Object -First $Top | ForEach-Object {
  $vf = if ($null -ne $_.VacFisica) { "{0:P1}" -f $_.VacFisica } else { "—" }
  $f = { param($v,$suf) if ($null -ne $v) { "{0:N1}$suf" -f $v } else { "—" } }
  "{0,-9}{1,-8}{2,8:N3}{3,9}{4,10}{5,11}{6,10}{7,9}{8,8}" -f `
    $_.Ticker,$_.Tipo,$_.PVP,(& $f $_.DYreal '%'),(& $f $_.PatAcum '%'),(& $f $_.RetTotal '%'),
    (& $f $_.Erosao '%'),(& $f $_.DYcv '%'),$vf
}
function Med($v) { $s=@($v|Sort-Object); if($s.Count -eq 0){0}else{$s[[int]($s.Count/2)]} }
"`nMedianas -> P/VP {0:N3} · DY ano {1:N1}% · taxa {2:P2} · concentração {3:N2}" -f (Med $ok.PVP),(Med $ok.DYano),(Med $ok.TaxaAno),(Med $ok.Concentracao)

$out = "$Cache\screener_fiis.csv"
$res | Export-Csv $out -NoTypeInformation -Encoding UTF8
"Base salva: $out"

"`n-- Como ler as colunas novas --"
"  Todas as taxas estão ANUALIZADAS, para serem comparáveis entre si e com o CDI."
"  DY REAL é o distribuído no período, composto e anualizado — não um mês x 12."
"  PATRIM. é a variação do valor patrimonial por cota, também anualizada."
"  RET TOTAL compõe os dois. É o retorno econômico: o que pingou na conta MAIS o"
"  que aconteceu com o patrimônio que sustenta a renda."
"  Compare RET TOTAL com o CDI. Um fundo que distribui acima do CDI mas rende"
"  abaixo dele no total está devolvendo capital, não gerando retorno."
"  DO CAPITAL é a fatia da distribuição que saiu do patrimônio em vez do"
"  resultado. Acima de zero significa que parte do rendimento é devolução do seu"
"  próprio dinheiro — o DY parece bom e o patrimônio encolhe."
"  OSCIL. mede a variação da distribuição mensal. Baixo = renda previsível."
"`n-- Sobre a vacância --"
"  Vem do Informe TRIMESTRAL da CVM (o mensal não tem), ponderada por área."
"  '—' significa SEM DADO, não zero: FII de papel não tem imóvel, e parte dos"
"  fundos não preenche o campo. Não trate traço como ausência de vacância."
"  O trimestral é mais defasado que o mensal — o 1T fecha em março."
"`n-- O que este screener NÃO vê --"
"  QUALIDADE DO IMÓVEL, localização e prazo de contrato. Um galpão AAA em"
"  Cajamar e um barracão em cidade pequena entram iguais nesta tabela."
"  CONCENTRAÇÃO aqui é por classe de ativo (0,25 = bem distribuído, 1 = tudo"
"  numa classe), não por imóvel individual."
"  DY do mês anualizado × 12 supõe repetição — mês com receita não recorrente"
"  distorce. Confira a série antes de tratar como recorrente."
