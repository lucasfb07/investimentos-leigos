# Importa o relatório de posição da Área do Investidor da B3.
#
#   .\importar-b3.ps1 -Arquivo "$env:USERPROFILE\Downloads\relatorio-posicao.xlsx"
#   .\importar-b3.ps1 -Arquivo posicao.xlsx -Saida dados\carteira.json
#
# Onde baixar: investidor.b3.com.br -> Extratos e relatórios -> Posição ->
# exportar Excel. O arquivo fica no SEU computador; nada é enviado para lugar
# nenhum. Este script só lê e converte.
#
# Não usa Excel nem biblioteca externa: .xlsx é um ZIP com XML dentro.

param(
  [Parameter(Mandatory=$true)][string]$Arquivo,
  [string]$Saida,
  [switch]$Detalhe
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$IC = [Globalization.CultureInfo]::InvariantCulture
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (-not (Test-Path $Arquivo)) { throw "Arquivo não encontrado: $Arquivo" }
if (-not $Saida) { $d = Split-Path -Parent $PSCommandPath; $Saida = Join-Path (Split-Path -Parent $d) "dados\carteira_b3.json" }

# Cabeçalho sem acento e minúsculo, para casar independentemente de como a B3
# escreveu ("Código de Negociação" / "Codigo de negociacao").
function Norm([string]$s){
  if(-not $s){ return '' }
  ($s.ToUpper() -replace '[ÁÀÂÃÄ]','A' -replace '[ÉÈÊË]','E' -replace '[ÍÌÎÏ]','I' `
     -replace '[ÓÒÔÕÖ]','O' -replace '[ÚÙÛÜ]','U' -replace 'Ç','C' -replace '[^A-Z0-9 ]',' ' `
     -replace '\s+',' ').Trim()
}
# "1.234,56" (pt-BR) e "1234.56" (invariante) convivem no mesmo arquivo.
function Num($v){
  if([string]::IsNullOrWhiteSpace($v)){ return $null }
  $s="$v" -replace '[R$\s]',''
  if($s -match ',\d{1,2}$'){ $s = ($s -replace '\.','') -replace ',','.' } else { $s = $s -replace ',','' }
  try { [double]::Parse($s,$IC) } catch { $null }
}
# Coluna a partir da referência da célula: "AB12" -> 28
function ColIdx([string]$ref){
  $l=($ref -replace '\d','').ToUpper(); $n=0
  foreach($c in $l.ToCharArray()){ $n = $n*26 + ([int][char]$c - 64) }
  $n - 1
}

# ---- Lê todas as abas ---------------------------------------------------------
$zip=[IO.Compression.ZipFile]::OpenRead((Resolve-Path $Arquivo))
$abas=@()
try{
  # O padrão OOXML usa barra normal, mas alguns geradores no Windows gravam
  # com barra invertida. Normaliza para casar nos dois casos.
  function Cam($e){ $e.FullName -replace '\\','/' }
  $ss=@()
  $e=$zip.Entries | Where-Object { (Cam $_) -eq 'xl/sharedStrings.xml' }
  if($e){ $sr=New-Object IO.StreamReader($e.Open()); $xml=[xml]$sr.ReadToEnd(); $sr.Close()
    $ss=@($xml.sst.si | ForEach-Object { if($_.t -is [string]){$_.t} elseif($_.t.'#text'){$_.t.'#text'} else{ ($_.r.t | ForEach-Object { if($_ -is [string]){$_}else{$_.'#text'} }) -join '' } }) }

  # Nome de cada aba, para saber o que é ação, fundo, renda fixa...
  $nomes=@()
  $wb=$zip.Entries | Where-Object { (Cam $_) -eq 'xl/workbook.xml' }
  if($wb){ $sr=New-Object IO.StreamReader($wb.Open()); $x=[xml]$sr.ReadToEnd(); $sr.Close()
    $nomes=@($x.workbook.sheets.sheet | ForEach-Object { $_.name }) }

  $sheets=$zip.Entries | Where-Object { (Cam $_) -match '^xl/worksheets/sheet\d+\.xml$' } |
          Sort-Object { [int](((Cam $_) -replace '\D','')) }
  $i=0
  foreach($sh in $sheets){
    $sr=New-Object IO.StreamReader($sh.Open()); $doc=[xml]$sr.ReadToEnd(); $sr.Close()
    $linhas=@()
    foreach($r in @($doc.worksheet.sheetData.row)){
      $cel=@{}
      foreach($c in @($r.c)){
        $v=$c.v
        if($c.t -eq 's' -and $v -ne $null){ $v=$ss[[int]$v] }
        elseif($c.t -eq 'inlineStr'){ $v=$c.is.t }
        # Célula vazia é OMITIDA no xlsx: sem a referência, tudo desloca.
        if($c.r){ $cel[(ColIdx $c.r)] = $v }
      }
      if($cel.Count){ $linhas += ,$cel }
    }
    $abas += [pscustomobject]@{ Nome=$(if($i -lt $nomes.Count){$nomes[$i]}else{"aba$($i+1)"}); Linhas=$linhas }
    $i++
  }
} finally { $zip.Dispose() }

Write-Host "Abas lidas: $($abas.Count)"
foreach($a in $abas){ Write-Host ("  {0,-34} {1,5} linhas" -f $a.Nome, $a.Linhas.Count) }

# ---- Localiza o cabeçalho e mapeia colunas -----------------------------------
# A B3 costuma pôr título e filtros antes da tabela, então o cabeçalho não é
# necessariamente a linha 1. Procura a primeira linha que tenha os campos-chave.
$ALVOS=@{
  ticker  = @('CODIGO DE NEGOCIACAO','CODIGO NEGOCIACAO','TICKER','CODIGO')
  produto = @('PRODUTO','ATIVO','NOME DO FUNDO','ESPECIFICACAO','DESCRICAO')
  qtd     = @('QUANTIDADE','QTDE','QUANTIDADE DISPONIVEL')
  valor   = @('VALOR ATUALIZADO','VALOR BRUTO','VALOR LIQUIDO','VALOR APLICADO','VALOR')
  preco   = @('PRECO DE FECHAMENTO','PRECO FECHAMENTO','ULTIMO PRECO','PRECO')
  inst    = @('INSTITUICAO','CORRETORA','PARTICIPANTE')
  venc    = @('VENCIMENTO','DATA DE VENCIMENTO')
  indexa  = @('INDEXADOR','INDICE')
}
function MapaColunas($linha){
  $m=@{}
  foreach($k in $linha.Keys){
    $h=Norm $linha[$k]
    if(-not $h){ continue }
    foreach($campo in $ALVOS.Keys){
      if($m.ContainsKey($campo)){ continue }
      foreach($cand in $ALVOS[$campo]){ if($h -eq $cand -or $h -like "*$cand*"){ $m[$campo]=$k; break } }
    }
  }
  $m
}

$itens=@(); $avisos=@()
foreach($a in $abas){
  $hdr=$null; $mapa=$null; $iniLinha=0
  for($j=0; $j -lt [Math]::Min(15,$a.Linhas.Count); $j++){
    $m=MapaColunas $a.Linhas[$j]
    # Cabeçalho válido: identifica o ativo E tem quantidade ou valor.
    if(($m.ContainsKey('ticker') -or $m.ContainsKey('produto')) -and ($m.ContainsKey('qtd') -or $m.ContainsKey('valor'))){
      $hdr=$a.Linhas[$j]; $mapa=$m; $iniLinha=$j+1; break
    }
  }
  if(-not $mapa){ $avisos += "aba '$($a.Nome)': cabeçalho não reconhecido — ignorada"; continue }
  if($Detalhe){ Write-Host "  [$($a.Nome)] colunas: $(($mapa.Keys | Sort-Object) -join ', ')" }

  for($j=$iniLinha; $j -lt $a.Linhas.Count; $j++){
    $L=$a.Linhas[$j]
    $get={ param($c) if($mapa.ContainsKey($c) -and $L.ContainsKey($mapa[$c])){ $L[$mapa[$c]] } else { $null } }
    $tk=(& $get 'ticker'); $pr=(& $get 'produto')
    if(-not $tk -and -not $pr){ continue }
    $q=Num (& $get 'qtd'); $v=Num (& $get 'valor'); $p=Num (& $get 'preco')
    if(-not $q -and -not $v){ continue }
    # Linha de total costuma vir sem ativo identificado.
    if(("$tk$pr" -match '(?i)^\s*(total|subtotal)')){ continue }

    $tick=$null
    if($tk -and "$tk".Trim() -match '^[A-Z]{4}\d{1,2}F?$'){ $tick=("$tk".Trim().ToUpper() -replace 'F$','') }
    elseif($pr -and "$pr" -match '^([A-Z]{4}\d{1,2})\b'){ $tick=$Matches[1] }

    $classe = if($tick -match '11$'){ 'fii' } elseif($tick){ 'acao' } else { 'outro' }
    # Nome da aba decide melhor que o ticker quando não há código.
    $na=Norm $a.Nome
    if($na -match 'TESOURO'){ $classe='outro' }
    elseif($na -match 'RENDA FIXA'){ $classe='outro' }
    elseif($na -match 'FUNDO'){ $classe='outro' }
    elseif($na -match 'BDR'){ $classe='outro' }
    elseif($na -match 'ETF'){ $classe='outro' }

    $itens += [pscustomobject]@{
      Aba=$a.Nome; Ticker=$tick
      Nome=$(if($pr){"$pr".Trim()}elseif($tick){$tick}else{'(sem nome)'})
      Quantidade=$q; Preco=$p
      Valor=$(if($v){$v}elseif($q -and $p){$q*$p}else{$null})
      Classe=$classe
      Vencimento=(& $get 'venc'); Indexador=(& $get 'indexa'); Instituicao=(& $get 'inst')
    }
  }
}

if($avisos){ Write-Host ""; $avisos | ForEach-Object { Write-Warning $_ } }
if(-not $itens){ throw "Nenhuma posição reconhecida. Rode com -Detalhe para ver as colunas encontradas." }

# Mesmo ativo em corretoras diferentes vira uma linha só.
$agr = $itens | Group-Object { if($_.Ticker){"T:$($_.Ticker)"} else {"N:$($_.Nome)"} } | ForEach-Object {
  $g=$_.Group
  [pscustomobject]@{
    tipo=$(if($g[0].Classe -eq 'acao'){'acao'}elseif($g[0].Classe -eq 'fii'){'fii'}else{'outro'})
    id=$(if($g[0].Ticker){$g[0].Ticker}else{$g[0].Nome})
    qtd=$(if($g[0].Ticker){ ($g | Measure-Object Quantidade -Sum).Sum } else { $null })
    valor=$(if($g[0].Ticker){ $null } else { ($g | Measure-Object Valor -Sum).Sum })
    origem=$g[0].Aba
  }
}

$total=($itens | Measure-Object Valor -Sum).Sum
"`n=== Posições importadas ==="
"{0,-30}{1,-8}{2,12}{3,14}" -f "Ativo","Tipo","Quantidade","Valor R$"
# PowerShell 5.1 não tem ?? nem ?: — calcula o valor de cada grupo antes.
$comValor = foreach($x in $agr){
  $orig=$itens | Where-Object { ($_.Ticker -eq $x.id) -or ($_.Nome -eq $x.id) }
  $x | Add-Member -NotePropertyName ValorTotal -NotePropertyValue (($orig | Measure-Object Valor -Sum).Sum) -Force -PassThru
}
foreach($x in ($comValor | Sort-Object ValorTotal -Descending)){
  $val=$x.ValorTotal
  "{0,-30}{1,-8}{2,12}{3,14:N2}" -f `
    $x.id.Substring(0,[Math]::Min(29,$x.id.Length)), $x.tipo,
    $(if($x.qtd){"{0:N0}" -f $x.qtd}else{"—"}), $val
}
"`nTotal: R$ {0:N2} em {1} posições" -f $total, $agr.Count

$agr | Select-Object tipo,id,qtd,valor,origem | ConvertTo-Json -Compress | Set-Content $Saida -Encoding UTF8
"Salvo em: $Saida"
"`nNo painel: aba Minha carteira -> Importar da B3 -> selecione este arquivo."
"`n-- Cuidados --"
"  Quantidade e preço vêm do relatório da B3; o painel recalcula o valor com a"
"  cotação atual da base, então o total pode divergir do extrato."
"  Renda fixa, Tesouro e fundos entram como valor fixo — o painel não tem"
"  indicador desses ativos e vai tratá-los como 'Outro'."
"  Confira a lista acima contra o seu extrato antes de confiar no diagnóstico."
