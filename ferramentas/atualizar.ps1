# Atualiza toda a base e regenera o dashboard.
#
#   .\atualizar.ps1              # só o que está velho
#   .\atualizar.ps1 -Forcar      # rebaixa tudo
#
# Para rodar sozinho todo dia útil às 20h (roda como VOCÊ, sem senha salva):
#   schtasks /create /tn "InvestimentosLeigos" /tr "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\ander\Downloads\investimentos_leigos\ferramentas\atualizar.ps1" /sc weekly /d MON,TUE,WED,THU,FRI /st 20:00

param([switch]$Forcar, [string]$Cache)

$ErrorActionPreference = "Continue"
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$IC = [Globalization.CultureInfo]::InvariantCulture
$raiz = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
if (-not $Cache) { $Cache = Join-Path $raiz "dados" }
$fer = Join-Path $raiz "ferramentas"
$log = Join-Path $Cache "atualizar.log"
function L($m) { $s = "{0:yyyy-MM-dd HH:mm} $m" -f (Get-Date); Write-Host $s; Add-Content $log $s }

L "=== inicio ==="

# Cadências diferentes: preço muda todo dia, DFP muda uma vez por ano.
# Rebaixar tudo sempre desperdiça banda e tempo sem melhorar nada.
$regras = @(
  @{ N='Informe Mensal FII'; A="$Cache\inf_mensal_fii_2026.zip"; D=7;
     U="https://dados.cvm.gov.br/dados/FII/DOC/INF_MENSAL/DADOS/inf_mensal_fii_2026.zip"; X="$Cache\inf_mensal_fii_2026" }
  @{ N='ITR 2026';           A="$Cache\itr_2026.zip"; D=30;
     U="https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/ITR/DADOS/itr_cia_aberta_2026.zip"; X="$Cache\itr2026" }
  @{ N='DFP 2025';           A="$Cache\dfp_2025.zip"; D=90;
     U="https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/DFP/DADOS/dfp_cia_aberta_2025.zip"; X="$Cache\dfp2025" }
  @{ N='IPE (fatos relev.)'; A="$Cache\ipe2026.zip"; D=3;
     U="https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/IPE/DADOS/ipe_cia_aberta_2026.zip"; X="$Cache\ipe2026" }
)
foreach ($r in $regras) {
  $velho = $Forcar -or -not (Test-Path $r.A) -or ((Get-Date) - (Get-Item $r.A).LastWriteTime).TotalDays -gt $r.D
  if (-not $velho) { L "  ok   $($r.N) (dentro de $($r.D)d)"; continue }
  try {
    $wc = New-Object System.Net.WebClient; $wc.Headers.Add("User-Agent","Mozilla/5.0")
    $wc.DownloadFile($r.U, $r.A); $wc.Dispose()
    Expand-Archive $r.A -DestinationPath $r.X -Force
    L "  BAIXOU $($r.N) ({0:N1} MB)" -f ((Get-Item $r.A).Length/1MB)
  } catch { L "  FALHOU $($r.N): $($_.Exception.Message)" }
}

# Tesouro: arquivo grande, cadência semanal.
$td = "$Cache\tesouro.csv"
if ($Forcar -or -not (Test-Path $td) -or ((Get-Date) - (Get-Item $td).LastWriteTime).TotalDays -gt 7) {
  try {
    $pkg = Invoke-RestMethod "https://www.tesourotransparente.gov.br/ckan/api/3/action/package_show?id=taxas-dos-titulos-ofertados-pelo-tesouro-direto" -TimeoutSec 60
    $u = ($pkg.result.resources | Where-Object { $_.format -eq 'CSV' }).url
    $wc = New-Object System.Net.WebClient; $wc.DownloadFile($u, $td); $wc.Dispose()
    L "  BAIXOU Tesouro Direto ({0:N1} MB)" -f ((Get-Item $td).Length/1MB)
  } catch { L "  FALHOU Tesouro: $($_.Exception.Message)" }
} else { L "  ok   Tesouro Direto" }

# --- Vacância (Informe Trimestral) -------------------------------------------
# Precisa vir ANTES do screener de FII, que consome fii_imoveis.csv.
L "processando imoveis (vacancia)..."
& powershell -NoProfile -ExecutionPolicy Bypass -File "$fer\cvm-fii-imoveis.ps1" *>$null
if (Test-Path "$Cache\fii_imoveis.csv") { L "  ok fii_imoveis.csv" } else { L "  FALHOU vacancia" }

# --- Screeners ---------------------------------------------------------------
L "rodando screener de acoes..."
& powershell -NoProfile -ExecutionPolicy Bypass -File "$fer\screener-acoes.ps1" -MinAnosLucro 2 -Top 5 *>$null
L "rodando screener de fiis..."
& powershell -NoProfile -ExecutionPolicy Bypass -File "$fer\screener-fiis.ps1" -MinPL 1e9 -Top 5 *>$null

# --- Regenera o JSON do dashboard -------------------------------------------
function P($v) { if ([string]::IsNullOrWhiteSpace($v)) { 0 } else { try { [double]::Parse(($v -replace ',','.'), $IC) } catch { 0 } } }

# Sanidade: L/P acima de 45% ou margem acima de 80% quase sempre é lucro
# não recorrente ou erro de escala — entra no dashboard como se fosse
# oportunidade e não é. Fica fora, mas segue no CSV completo.
$ac = Import-Csv "$Cache\screener_acoes.csv" -Encoding UTF8 | Where-Object {
  (P $_.Lucro) -gt 0 -and $_.Preco -and (P $_.EarningsYield) -gt 0 -and (P $_.EarningsYield) -le 45 -and
  (P $_.MargemLiq) -le 80 -and (P $_.MargemLiq) -gt -100 -and [int]$_.AnosLucro -ge 2 }
$ja = $ac | Sort-Object { -(P $_.EarningsYield) } | Select-Object -First 60 | ForEach-Object {
  [pscustomobject]@{ t=$_.Ticker; s=($_.Setor -replace '[^\x20-\x7E]',''); p=[math]::Round((P $_.Preco),2)
    ey=[math]::Round((P $_.EarningsYield),1); tt=[math]::Round((P $_.PrecoTeto),2)
    roe=[math]::Round((P $_.ROE),1); po=[math]::Round((P $_.Payout),0); de=[math]::Round((P $_.DivLiqEbitda),2)
    ml=[math]::Round((P $_.MargemLiq),1); al=[int]$_.AnosLucro; lu=[math]::Round((P $_.Lucro)/1e9,2)
    cl=$(if($_.CrescLucro){[math]::Round((P $_.CrescLucro),1)}else{$null})
    cr=$(if($_.CrescReceita){[math]::Round((P $_.CrescReceita),1)}else{$null})
    vir=$(if($_.ViradaLucro -eq 'True'){1}else{0}) } }

$fi = Import-Csv "$Cache\screener_fiis.csv" -Encoding UTF8 | Where-Object {
  $_.Preco -and (P $_.PVP) -ge 0.2 -and (P $_.PVP) -le 3 -and [int]$_.Cotistas -ge 500 }
# Vazio vira $null, nunca 0 — no painel aparece "—". Zero leria como "sem
# vacância", que é uma afirmação que o dado não sustenta.
function PN($v) { if ([string]::IsNullOrWhiteSpace($v)) { $null } else { [math]::Round((P $v)*100,1) } }
$jf = $fi | Sort-Object { P $_.PVP } | ForEach-Object {
  [pscustomobject]@{ t=$_.Ticker; tp=$_.Tipo; p=[math]::Round((P $_.Preco),2); vp=[math]::Round((P $_.VPcota),2)
    pvp=[math]::Round((P $_.PVP),3); dy=[math]::Round((P $_.DYano),1); tx=[math]::Round((P $_.TaxaAno)*100,2)
    cc=[math]::Round((P $_.Concentracao),2); ct=[int]$_.Cotistas; pl=[math]::Round((P $_.PL)/1e9,2)
    vac=(PN $_.VacFisica); vacf=(PN $_.VacFinan); inad=(PN $_.InadImov)
    ci=(PN $_.ConcImovel); ni=$(if($_.NImoveis){[int]$_.NImoveis}else{$null}) } }

# --- Renda fixa: macro do BCB, Focus e Tesouro Direto ------------------------
$UA = @{ "User-Agent" = "Mozilla/5.0" }
function SGS($cod) {
  try { $r = (Invoke-RestMethod "https://api.bcb.gov.br/dados/serie/bcdata.sgs.$cod/dados/ultimos/1?formato=json" -Headers $UA -TimeoutSec 30)[0]
        @{ v = [double](($r.valor) -replace ',','.'); d = $r.data } } catch { $null }
}
$macro = @{}
foreach ($x in @(@('cdi',4389), @('selic',432), @('ipca12',13522), @('igpm',189), @('dolar',1))) {
  $s = SGS $x[1]; if ($s) { $macro[$x[0]] = $s }
}
$focus = @{}
foreach ($ind in @('Selic','IPCA')) {
  try {
    $u = "https://olinda.bcb.gov.br/olinda/servico/Expectativas/versao/v1/odata/ExpectativasMercadoAnuais?`$top=8&`$filter=Indicador%20eq%20'$ind'&`$orderby=Data%20desc&`$format=json"
    $r = Invoke-RestMethod $u -TimeoutSec 30
    $focus[$ind] = @($r.value | Sort-Object DataReferencia -Unique | Select-Object -First 3 |
                     ForEach-Object { @{ ano = $_.DataReferencia; v = [double]$_.Mediana } })
  } catch {}
}
$tes = @(); $baseTD = ''
if (Test-Path "$Cache\tesouro.csv") {
  $td = Import-Csv "$Cache\tesouro.csv" -Delimiter ';' -Encoding UTF8
  $baseTD = ($td | ForEach-Object { $_.'Data Base' } |
             Sort-Object { [datetime]::ParseExact($_,'dd/MM/yyyy',$null) } | Select-Object -Last 1)
  $tes = @($td | Where-Object { $_.'Data Base' -eq $baseTD -and $_.'Tipo Titulo' -match '^Tesouro (Selic|Prefixado|IPCA\+)$' } |
    ForEach-Object { [pscustomobject]@{ n=$_.'Tipo Titulo'; v=$_.'Data Vencimento'
      tx=[double]((($_.'Taxa Venda Manha')) -replace ',','.')
      pu=[double]((($_.'PU Venda Manha')) -replace '\.','' -replace ',','.') } } | Sort-Object n,v)
}
$rf = @{ macro=$macro; focus=$focus; tesouro=$tes; baseTD=$baseTD }

# --- Fundos de investimento --------------------------------------------------
# 25 mil fundos não cabem no painel. Recorta os maiores e mais acessíveis de
# cada classe: quem tem escala, base de cotistas e não é exclusivo.
$fundos = @(); $cdi12 = $null
# CDI acumulado em 12 meses — a régua contra a qual o retorno dos fundos é lido.
try {
  $ini = (Get-Date).AddMonths(-12).ToString('dd/MM/yyyy'); $fim = (Get-Date).ToString('dd/MM/yyyy')
  $s = Invoke-RestMethod "https://api.bcb.gov.br/dados/serie/bcdata.sgs.12/dados?formato=json&dataInicial=$ini&dataFinal=$fim" -Headers @{"User-Agent"="Mozilla/5.0"} -TimeoutSec 60
  $acc = 1.0; foreach ($x in $s) { $acc *= (1 + [double](($x.valor) -replace ',','.')/100) }
  $cdi12 = [math]::Round(($acc-1)*100, 2)
} catch {}
if (Test-Path "$Cache\screener_fundos.csv") {
  $todos = Import-Csv "$Cache\screener_fundos.csv" -Encoding UTF8
  foreach ($cl in @('Renda Fixa','Multimercado','Ações','Cambial')) {
    $fundos += @($todos | Where-Object {
        $_.Classificacao -eq $cl -and (P $_.PL) -ge 3e8 -and [int]$_.Cotistas -ge 500 -and
        $_.Exclusivo -notmatch 'Sim' -and $_.Publico -notmatch 'Exclusivo'
      } | Sort-Object { -(P $_.Retorno) } | Select-Object -First 40 | ForEach-Object {
        [pscustomobject]@{ n=(($_.Nome -replace '"','') -replace '\s+',' ').Trim(); c=$cl
          r=[math]::Round((P $_.Retorno),2)
          cdi=$(if($_.PctCDI){[math]::Round((P $_.PctCDI),0)}else{$null})
          v=$(if($_.Vol){[math]::Round((P $_.Vol),1)}else{$null})
          pl=[math]::Round((P $_.PL)/1e6,0); ct=[int]$_.Cotistas
          b=($_.Benchmark -replace '"','') } })
  }
  L "  fundos no painel: $($fundos.Count) de $($todos.Count)"
}

# --- Watchlist EUA -----------------------------------------------------------
L "atualizando watchlist EUA..."
& powershell -NoProfile -ExecutionPolicy Bypass -File "$fer\watchlist-eua.ps1" *>$null
$eua = @()
if (Test-Path "$Cache\watchlist_eua.csv") {
  $eua = @(Import-Csv "$Cache\watchlist_eua.csv" -Encoding UTF8 | Where-Object { $_.Preco } | ForEach-Object {
    [pscustomobject]@{ t=$_.Ticker; n=($_.Nome -replace '"',''); s=($_.Setor -replace '[^\x20-\x7E]','')
      p=[math]::Round((P $_.Preco),2); ey=$(if($_.EarningsYield){[math]::Round((P $_.EarningsYield),1)}else{$null})
      pl=$(if($_.PL){[math]::Round((P $_.PL),1)}else{$null}); pvp=$(if($_.PVP){[math]::Round((P $_.PVP),1)}else{$null})
      roe=$(if($_.ROE){[math]::Round((P $_.ROE),1)}else{$null}); mg=$(if($_.Margem){[math]::Round((P $_.Margem),1)}else{$null})
      dy=$(if($_.DY){[math]::Round((P $_.DY),2)}else{$null}); be=$(if($_.Beta){[math]::Round((P $_.Beta),2)}else{$null})
      ee=$(if($_.EvEbitda){[math]::Round((P $_.EvEbitda),1)}else{$null}) } })
  L "  watchlist EUA: $($eua.Count) papeis"
}
L "renda fixa: CDI $($macro.cdi.v)% · $($tes.Count) titulos do Tesouro (base $baseTD)"

$modelo = Join-Path $raiz "dashboard.template.html"
$saida  = Join-Path $raiz "dashboard.html"
if (-not (Test-Path $modelo)) { L "SEM TEMPLATE em $modelo — dashboard nao regenerado."; L "=== fim ==="; return }
$html = [IO.File]::ReadAllText($modelo, [Text.Encoding]::UTF8)
$html = $html.Replace('__ACOES__', ($ja | ConvertTo-Json -Compress))
$html = $html.Replace('__FIIS__',  ($jf | ConvertTo-Json -Compress))
$html = $html.Replace('__RF__',    ($rf | ConvertTo-Json -Depth 6 -Compress))
$html = $html.Replace('__EUA__',   $(if($eua.Count){ $eua | ConvertTo-Json -Compress } else { '[]' }))
$html = $html.Replace('__FUNDOS__',$(if($fundos.Count){ $fundos | ConvertTo-Json -Compress } else { '[]' }))
$html = $html.Replace('__CDI12__', $(if($cdi12){ "$cdi12" } else { 'null' }))
$html = $html.Replace('__ATUALIZADO__', (Get-Date -Format 'dd/MM/yyyy HH:mm'))
[IO.File]::WriteAllText($saida, $html, (New-Object Text.UTF8Encoding($false)))
L "dashboard regenerado: $($ja.Count) acoes, $($jf.Count) fiis"
L "=== fim ==="
