# Screener de fundos de investimento a partir do Informe Diário da CVM.
#
#   .\cvm-fundos.ps1                                  # renda fixa, 12 meses
#   .\cvm-fundos.ps1 -Classe Ações -Meses 12
#   .\cvm-fundos.ps1 -Classe Multimercado -MinPL 5e8 -Top 20
#
# Fonte: dados.cvm.gov.br/dados/FI/  (INF_DIARIO + CAD/registro_fundo_classe)
# Cobre ~25 mil fundos. Cadastro cruza com o informe em 99% dos casos.
#
# ATENÇÃO: cada mês de informe diário tem ~12 MB zipado e ~56 MB aberto.
# 12 meses são ~140 MB de download na primeira execução. Depois fica em cache.

param(
  [string]$Classe = 'Renda Fixa',
  [int]$Meses = 12,
  [double]$MinPL = 1e8,
  [int]$MinCotistas = 100,
  [int]$Top = 25,
  [string]$Cnpj,
  [string]$Cache
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$IC = [Globalization.CultureInfo]::InvariantCulture
if (-not $Cache) { $d = Split-Path -Parent $PSCommandPath; $Cache = Join-Path (Split-Path -Parent $d) "dados" }
function N($v) { if ([string]::IsNullOrWhiteSpace($v)) { $null } else { try { [double]::Parse($v, $IC) } catch { $null } } }
function Baixa($url, $dest) {
  $wc = New-Object System.Net.WebClient; $wc.Headers.Add("User-Agent","Mozilla/5.0")
  try { $wc.DownloadFile($url, $dest); $true } catch { $false } finally { $wc.Dispose() }
}

# ---- Cadastro de classes (nome, classificação, benchmark) -------------------
$regZip = "$Cache\reg_fc.zip"; $regDir = "$Cache\reg_fc"
if (-not (Test-Path $regZip) -or ((Get-Date) - (Get-Item $regZip).LastWriteTime).TotalDays -gt 15) {
  Write-Host "Baixando cadastro de classes..."
  if (Baixa "https://dados.cvm.gov.br/dados/FI/CAD/DADOS/registro_fundo_classe.zip" $regZip) {
    Expand-Archive $regZip -DestinationPath $regDir -Force }
}
$CAD = @{}
Import-Csv "$regDir\registro_classe.csv" -Delimiter ';' -Encoding Default |
  Where-Object { $_.Situacao -match 'Funcionamento' } | ForEach-Object {
    $k = ($_.CNPJ_Classe -replace '[^\d]','')
    if ($k -and -not $CAD.ContainsKey($k)) { $CAD[$k] = $_ }
  }
Write-Host "Cadastro: $($CAD.Count) classes em funcionamento"

# ---- Informe diário: baixa os meses e guarda só o necessário ----------------
# Guardar as 583 mil linhas de cada mês estoura a memória. Para retorno basta a
# PRIMEIRA e a ÚLTIMA cota de cada fundo em cada mês.
$hoje = Get-Date
# NÃO chamar de $meses: PowerShell é case-insensitive e colidiria com o
# parâmetro [int]$Meses, quebrando com "não é possível converter Object[]".
$competencias = 0..($Meses-1) | ForEach-Object { $hoje.AddMonths(-$_).ToString('yyyyMM') } | Sort-Object
$serie = @{}   # cnpj -> lista de @{d;q;pl;ct}
foreach ($ym in $competencias) {
  $zip = "$Cache\fi_$ym.zip"; $dir = "$Cache\fi_$ym"
  $csv = "$dir\inf_diario_fi_$ym.csv"
  if (-not (Test-Path $csv)) {
    if (-not (Test-Path $zip)) {
      Write-Host "  baixando $ym..."
      if (-not (Baixa "https://dados.cvm.gov.br/dados/FI/DOC/INF_DIARIO/DADOS/inf_diario_fi_$ym.zip" $zip)) {
        Write-Warning "  $ym indisponível"; continue }
    }
    try { Expand-Archive $zip -DestinationPath $dir -Force } catch { continue }
  }
  if (-not (Test-Path $csv)) { continue }
  $prim = @{}; $ult = @{}
  Import-Csv $csv -Delimiter ';' -Encoding Default | ForEach-Object {
    $k = $_.CNPJ_FUNDO_CLASSE -replace '[^\d]',''
    if (-not $prim.ContainsKey($k)) { $prim[$k] = $_ }
    $ult[$k] = $_
  }
  foreach ($k in $ult.Keys) {
    if (-not $serie.ContainsKey($k)) { $serie[$k] = @() }
    $a = $prim[$k]; $b = $ult[$k]
    $serie[$k] += @{ d=$a.DT_COMPTC; q=(N $a.VL_QUOTA); pl=(N $a.VL_PATRIM_LIQ); ct=[int]$a.NR_COTST }
    $serie[$k] += @{ d=$b.DT_COMPTC; q=(N $b.VL_QUOTA); pl=(N $b.VL_PATRIM_LIQ); ct=[int]$b.NR_COTST }
  }
  Write-Host "  $ym -> $($ult.Count) fundos"
}
Write-Host "Série montada para $($serie.Count) fundos"

# ---- CDI acumulado no mesmo período, para servir de régua -------------------
$cdiAcum = $null
try {
  $ini = $hoje.AddMonths(-$Meses).ToString('dd/MM/yyyy'); $fim = $hoje.ToString('dd/MM/yyyy')
  $s = Invoke-RestMethod "https://api.bcb.gov.br/dados/serie/bcdata.sgs.12/dados?formato=json&dataInicial=$ini&dataFinal=$fim" -Headers @{"User-Agent"="Mozilla/5.0"} -TimeoutSec 60
  $f = 1.0; foreach ($x in $s) { $f *= (1 + (N $x.valor)/100) }
  $cdiAcum = ($f - 1) * 100
  Write-Host ("CDI acumulado no período: {0:N2}%" -f $cdiAcum)
} catch { Write-Warning "CDI não obtido — comparação relativa fica indisponível" }

# ---- Consolida ---------------------------------------------------------------
$out = foreach ($k in $serie.Keys) {
  $c = $CAD[$k]; if (-not $c) { continue }
  $pts = @($serie[$k] | Where-Object { $_.q -and $_.q -gt 0 } | Sort-Object d)
  if ($pts.Count -lt 4) { continue }
  $q0 = $pts[0].q; $q1 = $pts[-1].q
  if (-not $q0 -or $q0 -le 0) { continue }
  $ret = ($q1/$q0 - 1) * 100

  # Volatilidade: desvio-padrão das variações mês a mês, anualizado.
  $vars = @()
  for ($i=1; $i -lt $pts.Count; $i++) { if ($pts[$i-1].q -gt 0) { $vars += ($pts[$i].q/$pts[$i-1].q - 1) } }
  $vol = $null
  if ($vars.Count -gt 2) {
    $m = ($vars | Measure-Object -Average).Average
    $sd = [Math]::Sqrt((($vars | ForEach-Object { [Math]::Pow($_-$m,2) } | Measure-Object -Sum).Sum)/($vars.Count-1))
    $vol = $sd * [Math]::Sqrt(12) * 100
  }
  [pscustomobject]@{
    CNPJ=$k; Nome=$c.Denominacao_Social; Classificacao=$c.Classificacao
    Anbima=$c.Classificacao_Anbima; Benchmark=$c.Indicador_Desempenho
    Publico=$c.Publico_Alvo; Exclusivo=$c.Exclusivo
    PL=$pts[-1].pl; Cotistas=$pts[-1].ct
    Retorno=$ret; Vol=$vol
    PctCDI=$(if ($cdiAcum -and $cdiAcum -ne 0) { $ret/$cdiAcum*100 } else { $null })
    Meses=$Meses
  }
}
$out | Export-Csv "$Cache\screener_fundos.csv" -NoTypeInformation -Encoding UTF8
Write-Host "Fundos consolidados: $($out.Count) -> $Cache\screener_fundos.csv"

if ($Cnpj) {
  $k = $Cnpj -replace '[^\d]',''
  $f = $out | Where-Object { $_.CNPJ -eq $k }
  if (-not $f) { Write-Warning "CNPJ não encontrado."; return }
  "`n$($f.Nome)"
  "  $($f.Classificacao) · $($f.Anbima) · benchmark: $($f.Benchmark)"
  "  PL R$ {0:N0} · {1:N0} cotistas" -f $f.PL, $f.Cotistas
  "  Retorno {0} meses: {1:N2}%{2}" -f $f.Meses, $f.Retorno, $(if($f.PctCDI){" ({0:N0}% do CDI)" -f $f.PctCDI}else{""})
  if ($f.Vol) { "  Volatilidade anualizada: {0:N2}%" -f $f.Vol }
  return
}

# ---- Saída -------------------------------------------------------------------
# Fundo exclusivo/reservado não é acessível ao investidor comum — fica fora,
# senão o topo da lista enche de fundo de family office.
$sel = $out | Where-Object {
  $_.Classificacao -eq $Classe -and $_.PL -ge $MinPL -and $_.Cotistas -ge $MinCotistas -and
  $_.Exclusivo -notmatch 'Sim' -and $_.Publico -notmatch 'Exclusivo'
}
"`n=== Fundos: $Classe · $Meses meses ==="
"PL ≥ R$ {0:N0} · ≥ {1} cotistas · sem exclusivos — {2} fundos" -f $MinPL, $MinCotistas, $sel.Count
"`n{0,-52}{1,10}{2,9}{3,9}{4,11}{5,9}" -f "Fundo","Retorno","% CDI","Vol","PL R$ mi","Cotistas"
$sel | Sort-Object Retorno -Descending | Select-Object -First $Top | ForEach-Object {
  "{0,-52}{1,10:N2}{2,9}{3,9}{4,11:N0}{5,9:N0}" -f `
    $_.Nome.Substring(0,[Math]::Min(51,$_.Nome.Length)), $_.Retorno,
    $(if($_.PctCDI){"{0:N0}%" -f $_.PctCDI}else{"—"}),
    $(if($_.Vol){"{0:N1}%" -f $_.Vol}else{"—"}),
    ($_.PL/1e6), $_.Cotistas
}

"`n-- Como ler --"
"  Retorno é a variação da COTA no período — já líquido de taxa de administração,"
"  que é descontada da cota todo dia. Não é líquido de imposto de renda."
"  % do CDI compara com o CDI acumulado no MESMO período. Acima de 100% significa"
"  que rendeu mais que a renda fixa básica; em fundo de ações isso diz pouco,"
"  porque o risco assumido é completamente diferente."
"  Volatilidade é o tamanho das oscilações mensais, anualizado. Retorno alto com"
"  volatilidade alta não é o mesmo produto que retorno alto com volatilidade baixa."
"  RENTABILIDADE PASSADA NÃO SE REPETE. Um ano bom pode ser competência, sorte ou"
"  um risco que ainda não apareceu — os dados aqui não distinguem os três."
