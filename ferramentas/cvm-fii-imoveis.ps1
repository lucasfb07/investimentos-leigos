# Vacância, inadimplência e concentração por imóvel — Informe TRIMESTRAL de FII.
#
#   .\cvm-fii-imoveis.ps1                    # gera a base e mostra o resumo
#   .\cvm-fii-imoveis.ps1 -Cnpj 24.796.967/0001-90
#
# Fonte: dados.cvm.gov.br/dados/FII/DOC/INF_TRIMESTRAL/
#
# O Informe MENSAL não tem vacância — só o trimestral. Ele traz imóvel a imóvel:
# área, endereço, % de vacância, % de inadimplência e a fatia que o imóvel
# representa na receita do fundo.

param([string]$Cnpj, [string]$Ref, [string]$Cache, [switch]$Forcar)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$IC = [Globalization.CultureInfo]::InvariantCulture
if (-not $Cache) { $d = Split-Path -Parent $PSCommandPath; $Cache = Join-Path (Split-Path -Parent $d) "dados" }
function P($v) { if ([string]::IsNullOrWhiteSpace($v)) { $null } else { try { [double]::Parse($v, $IC) } catch { $null } } }

$ano = (Get-Date).Year
$zip = "$Cache\fii_tri$ano.zip"; $dir = "$Cache\fii_tri$ano"
if ($Forcar -or -not (Test-Path $zip) -or ((Get-Date) - (Get-Item $zip).LastWriteTime).TotalDays -gt 15) {
  Write-Host "Baixando Informe Trimestral FII $ano..."
  $wc = New-Object System.Net.WebClient; $wc.Headers.Add("User-Agent","Mozilla/5.0")
  $wc.DownloadFile("https://dados.cvm.gov.br/dados/FII/DOC/INF_TRIMESTRAL/DADOS/inf_trimestral_fii_$ano.zip", $zip)
  $wc.Dispose(); Expand-Archive $zip -DestinationPath $dir -Force
} elseif (-not (Test-Path $dir)) { Expand-Archive $zip -DestinationPath $dir -Force }

$im = Import-Csv "$dir\inf_trimestral_fii_imovel_$ano.csv" -Delimiter ';' -Encoding Default

# O trimestre mais recente costuma estar incompleto (fundos ainda entregando).
# Pega o último com pelo menos 60% do pico de imóveis.
if (-not $Ref) {
  $porTri = $im | Group-Object Data_Referencia | Sort-Object Name
  $pico = ($porTri | Measure-Object Count -Maximum).Maximum
  $Ref = ($porTri | Where-Object { $_.Count -ge $pico * 0.6 } | Select-Object -Last 1).Name
}
$sel = $im | Where-Object { $_.Data_Referencia -eq $Ref }
Write-Host "Trimestre: $Ref · $($sel.Count) imóveis · $(($sel.CNPJ_Fundo_Classe | Sort-Object -Unique).Count) fundos"

# Só imóveis de RENDA. "Imóveis para venda" são estoque a vender — vacância ali
# não significa inquilino ausente, e misturar distorce o indicador.
$renda = $sel | Where-Object { $_.Classe -match 'renda' }
Write-Host "Imóveis de renda: $($renda.Count)"

$out = foreach ($g in ($renda | Group-Object CNPJ_Fundo_Classe)) {
  $rows = $g.Group
  $areaT = 0.0; $recT = 0.0; $vacA = 0.0; $vacR = 0.0; $inaR = 0.0; $comVac = 0; $maxRec = 0.0; $maxArea = 0.0
  $suspeitos = 0

  # ⚠️ Parte dos fundos preenche Percentual_Vacancia com a TAXA DE OCUPAÇÃO.
  # Detectado no HSI Malls: shoppings com "vacância" de 91–98% gerando 14–17%
  # da receita do fundo cada. Um imóvel 98% vago não sustenta 17% da receita —
  # os dois campos se contradizem, e o campo de vacância é o errado.
  # Regra: imóvel com vacância > 50% E receita > 0 é inconsistente. Se a maioria
  # do fundo cai nisso, o campo inteiro é descartado em vez de invertido —
  # inverter seria adivinhar a intenção de quem preencheu.
  $comDado = 0
  foreach ($r in $rows) {
    $v = P $r.Percentual_Vacancia; $rc = P $r.Percentual_Receitas_FII
    if ($null -eq $v) { continue }
    $comDado++
    if ($v -gt 0.5 -and $null -ne $rc -and $rc -gt 0.01) { $suspeitos++ }
  }
  $invertido = ($comDado -gt 0) -and (($suspeitos / $comDado) -gt 0.5)

  foreach ($r in $rows) {
    $a = P $r.Area; if ($null -eq $a) { $a = 0 }
    $rc = P $r.Percentual_Receitas_FII; if ($null -eq $rc) { $rc = 0 }
    $v = P $r.Percentual_Vacancia; $n = P $r.Percentual_Inadimplencia
    $areaT += $a; $recT += $rc
    if ($rc -gt $maxRec) { $maxRec = $rc }
    if ($a -gt $maxArea) { $maxArea = $a }
    if ($null -ne $v -and -not $invertido) { $comVac++; $vacA += $v * $a; $vacR += $v * $rc }
    if ($null -ne $n) { $inaR += $n * $rc }
  }
  [pscustomobject]@{
    CNPJ = $g.Name; NImoveis = $rows.Count
    Cobertura = if ($rows.Count) { $comVac / $rows.Count } else { 0 }
    # Física pondera por área; financeira pondera por receita. Um galpão vago de
    # 50 mil m² que não gerava receita pesa muito na física e nada na financeira.
    # Campo suspeito vira SEM DADO, não zero. Zero leria como "sem vacância",
    # que é tão errado quanto o 90% original — só erra para o outro lado.
    VacFisica    = if ($invertido) { $null } elseif ($areaT -gt 0) { $vacA / $areaT } else { $null }
    VacFinanceira= if ($invertido) { $null } elseif ($recT  -gt 0) { $vacR / $recT  } else { $null }
    Inadimplencia= if ($recT  -gt 0) { $inaR / $recT  } else { $null }
    # Concentração real: fatia do maior imóvel na receita do fundo.
    ConcReceita  = if ($recT -gt 0) { $maxRec / $recT } else { $null }
    ConcArea     = if ($areaT -gt 0) { $maxArea / $areaT } else { $null }
    AreaTotal = $areaT; RecCoberta = $recT
    CampoSuspeito = $invertido
  }
}
$sus = @($out | Where-Object { $_.CampoSuspeito })
if ($sus.Count) {
  Write-Warning "$($sus.Count) fundos descartados: campo de vacância inconsistente com a receita"
  Write-Warning "  (provável preenchimento com taxa de OCUPAÇÃO em vez de vacância)"
}

$csv = "$Cache\fii_imoveis.csv"
$out | Export-Csv $csv -NoTypeInformation -Encoding UTF8
Write-Host "Fundos com imóvel de renda: $($out.Count) -> $csv"

if ($Cnpj) {
  $f = $out | Where-Object { ($_.CNPJ -replace '[^\d]','') -eq ($Cnpj -replace '[^\d]','') }
  if (-not $f) { Write-Warning "CNPJ sem imóvel de renda em $Ref."; return }
  "`nCNPJ $($f.CNPJ) · $($f.NImoveis) imóveis · área {0:N0} m²" -f $f.AreaTotal
  "  Vacância física      {0}" -f $(if($null -ne $f.VacFisica){"{0:P2}" -f $f.VacFisica}else{"n/d"})
  "  Vacância financeira  {0}" -f $(if($null -ne $f.VacFinanceira){"{0:P2}" -f $f.VacFinanceira}else{"n/d"})
  "  Inadimplência        {0}" -f $(if($null -ne $f.Inadimplencia){"{0:P2}" -f $f.Inadimplencia}else{"n/d"})
  "  Maior imóvel (receita) {0}" -f $(if($null -ne $f.ConcReceita){"{0:P0}" -f $f.ConcReceita}else{"n/d"})
  "  Cobertura do campo   {0:P0} dos imóveis" -f $f.Cobertura
  return
}

$val = $out | Where-Object { $null -ne $_.VacFisica -and $_.Cobertura -ge 0.5 }
"`nCom vacância em ≥50% dos imóveis: $($val.Count) fundos"
function Med($v) { $s=@($v|Sort-Object); if($s.Count -eq 0){0}else{$s[[int]($s.Count/2)]} }
"Mediana da vacância física: {0:P2}" -f (Med ($val.VacFisica))
"`nMaiores vacâncias (≥3 imóveis, cobertura ≥50%):"
"{0,-22}{1,6}{2,11}{3,11}{4,10}" -f "CNPJ","Imóv","Vac fís","Vac fin","Maior%"
$val | Where-Object { $_.NImoveis -ge 3 } | Sort-Object VacFisica -Descending | Select-Object -First 10 | ForEach-Object {
  "{0,-22}{1,6}{2,11:P1}{3,11}{4,10}" -f $_.CNPJ,$_.NImoveis,$_.VacFisica,
    $(if($null -ne $_.VacFinanceira){"{0:P1}" -f $_.VacFinanceira}else{"n/d"}),
    $(if($null -ne $_.ConcReceita){"{0:P0}" -f $_.ConcReceita}else{"n/d"})
}

"`n-- Como ler --"
"  Vacância FÍSICA pondera por área; FINANCEIRA pondera por receita. Divergência"
"  grande entre as duas é informação: área vaga que já não gerava receita."
"  'n/d' na financeira = o fundo não informou receita por imóvel, não que seja 0."
"  Cobertura < 100% significa que parte dos imóveis não teve o campo preenchido —"
"  o número vale para a parte informada, não para o fundo inteiro."
"  O trimestral é MAIS DEFASADO que o mensal: o 1T fecha em março e sai depois."
