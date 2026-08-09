# Mapa de fontes

Onde buscar cada número. **Consulte antes de qualquer análise** — chamar
endpoint bloqueado desperdiça requisição e, pior, o erro pode ser confundido com
"dado inexistente".

Cobertura medida em **08/08/2026** contra o token real. Se algo aqui divergir da
realidade, corrija o arquivo — ele não é aspiracional, é o estado verificado.

## Roteamento

| Preciso de | Fonte | Endpoint |
|---|---|---|
| Cotação de ação/FII/ETF/BDR | brapi | `/v2/stocks/quote?symbols=PETR4,VALE3` |
| Ibovespa | brapi | `/v2/stocks/quote?symbols=^BVSP` |
| S&P 500 · Nasdaq | brapi | `^GSPC` e `^IXIC`, **um por chamada** |
| Histórico de preço | brapi | `/v2/stocks/historical?symbols=PETR4&range=1y&interval=1d` |
| Dividendos e JCP de ação | brapi | `/v2/stocks/dividends?symbols=ITUB4` |
| Setor, CNPJ, descrição | brapi | `/v2/stocks/profile?symbols=PETR4` |
| Validar/buscar ticker | brapi | `/v2/tickers?search=WEGE` |
| P/VP, DY e patrimônio de FII | brapi | `/v2/fii/indicators?symbols=MXRF11` |
| **Série mensal desses indicadores** | brapi | `/v2/fii/indicators/history?symbols=MXRF11` |
| **Informe Mensal CVM** (PL, cotas, taxa adm, amortização, composição) | brapi | `/v2/fii/reports?symbols=MXRF11&limit=5&page=1` |
| **Demonstração financeira anual** (+ link FNET, parecer do auditor) | brapi | `/v2/fii/financials?symbols=MXRF11` |
| Vacância e imóveis de FII | brapi | `/v2/fii/properties?symbols=HGLG11` |
| Carteira de FII (CRI, cotas) | brapi | `/v2/fii/portfolio?symbols=MXRF11` |
| Rendimentos de FII | brapi | `/v2/fii/dividends?symbols=MXRF11` |
| Listar/filtrar FIIs | brapi | `/v2/fii/list?segmentType=tijolo` |
| **Selic, CDI, IPCA, IGP-M, dólar** | **BCB SGS** | veja abaixo |
| **Expectativa de Selic, IPCA, PIB, câmbio** | **BCB Focus** | veja abaixo |
| **Taxas do Tesouro Direto** | **Tesouro Transparente** | veja abaixo |
| **Relatório gerencial e inadimplência de FII** | **FNET** | veja abaixo |
| **Fato relevante de empresa listada** | **CVM IPE** | veja abaixo |

## ⚠️ A suíte de FII só funciona para MXRF11 e HGLG11

Medido em 08/08/2026 contra 30 FIIs líquidos: **28 retornaram 403**. Os dois que
passaram são exatamente os tickers de sandbox gratuitos.

`fii/indicators`, `fii/portfolio`, `fii/dividends`, `fii/properties`,
`fii/reports`, `fii/financials` e `fii/indicators/history` **não são
entitlement geral** — valem para `MXRF11` e `HGLG11` e mais nada. Falharam:
MIDW11, GGRC11, GARE11, CPTS11, VGHF11, VGIR11, KNSC11, TRXF11, BTCI11, ALZR11,
KNCR11, BTLG11, HGBS11, XPML11, KNHY11, entre outros.

**Consequências diretas:**

- **Comparação com pares é impossível** neste plano. Não dá para dizer se um
  P/VP está caro ou barato contra o segmento — só contra a própria história do
  ativo. Declare essa limitação em vez de omitir.
- Análise de FII completa só existe para esses dois tickers. Para qualquer outro,
  há apenas `stocks/quote` (preço) e o que estiver no FNET.
- `tickers?subType=fii` enumera os 338 FIIs e **isso funciona** — serve para
  validar ticker e achar o CNPJ, não para obter indicadores.

**O FNET não tem essa limitação:** aceita qualquer CNPJ e é a via para relatório
gerencial, informe mensal e demonstração de qualquer fundo. Quando os
indicadores derem 403, o documento ainda está acessível.

## Bloqueado no plano atual — NÃO chamar

Estes retornam **403** (restrição de plano, não erro de token):

`/v2/stocks/statistics` · `/v2/stocks/financial-data` ·
`/v2/stocks/balance-sheet` · `/v2/stocks/income-statement` · `/v2/macro` ·
`/v2/currency`

Consequência direta: **P/L, P/VP de ação, margens, ROE, dívida e receita não
estão disponíveis.** Quando a análise precisar deles, escreva que o dado não
está acessível — nunca estime, nunca preencha de memória. É a regra central do
`CLAUDE.md`, e aqui ela tem consequência concreta.

Macro e câmbio estão bloqueados na brapi mas **resolvidos pelo BCB**, que é
fonte melhor. Só os fundamentos de ação ficam realmente descobertos.

### O que ainda dá para fazer sem eles

**Dividend Yield de ação é calculável:** some os proventos dos últimos 12 meses
em `/v2/stocks/dividends` e divida pelo preço atual de `/v2/stocks/quote`.
Explicite que é cálculo próprio e diga a janela usada.

**FIIs não são afetados.** `fii/indicators` traz P/VP e DY prontos, e
`fii/properties` traz vacância. A análise de FII roda inteira.

## Por que HTTP direto, e não o MCP da brapi

O servidor MCP oficial (`https://brapi.dev/api/mcp/mcp`) foi configurado, testado
e **removido em 08/08/2026**. Medido com o mesmo token, na mesma hora:

| Recurso | REST direto | MCP |
|---|---|---|
| `stocks/quote` | OK, múltiplos tickers | OK, **1 ticker por chamada** |
| `fii/indicators` | **OK** | "plano não tem acesso" |
| `fii/dividends` | **OK** | "plano não tem acesso" |
| `fii/portfolio` | **OK** | "plano não tem acesso" |
| `macro` | 403 | bloqueado |

O MCP tem acesso **estritamente pior** que o REST com a mesma credencial, e ainda
custa ~69 ferramentas no contexto de toda sessão. Uma análise de FII completa é
inviável por ele — os três endpoints que a sustentam estão bloqueados.

A única vantagem observada: o MCP devolve um campo `stale: true` que o REST
omite. Não compensa; a defasagem se detecta checando o calendário, como descrito
adiante.

**Para reativar**, se um upgrade de plano mudar esse quadro, recrie `.mcp.json`
na raiz:

```json
{
  "mcpServers": {
    "brapi": {
      "type": "http",
      "url": "https://brapi.dev/api/mcp/mcp",
      "headers": { "Authorization": "Bearer ${BRAPI_TOKEN}" }
    }
  }
}
```

E **meça de novo antes de confiar** — não presuma que o upgrade destravou a via
MCP só porque destravou a REST.

## brapi — autenticação e regras

Token na variável de ambiente `BRAPI_TOKEN`. Nunca em arquivo versionado, nunca
em URL (`?token=`), nunca no corpo de uma análise. Toda chamada usa header:

```bash
curl -H "Authorization: Bearer $BRAPI_TOKEN" "https://brapi.dev/api/v2/stocks/quote?symbols=PETR4"
```

Payload por ativo em `results[].data`. Use `regularMarketTime` para carimbar a
data — não `requestedAt`, que é só quando você perguntou.

### ⚠️ A chave do payload muda por endpoint

Não presuma `results` nem `fiis`. Medido em 08/08/2026:

| Endpoint | Chave | Observação |
|---|---|---|
| `stocks/quote` | `results[].data` | |
| `fii/indicators` | `fiis[]` | |
| `fii/portfolio` | `fiis[]` | |
| `fii/indicators/history` | **`history[]`** | não `fiis` |
| `fii/reports` | **`reports[]`** | **paginado** — `limit` e `page`, veja `pagination` |
| `fii/financials` | **`financials[]`** | traz `fields.Link_Download` do FNET |

Assumir a chave errada devolve nulo, fácil de confundir com "sem dado".
Inspecione as chaves de topo antes de indexar.

### ⚠️ Não converta `referenceDate` para datetime local

Vem como `2026-06-01 00:00:00+00`. Convertido para o fuso de Brasília (UTC−3)
vira 31/05, e um mês inteiro de dados aparece rotulado como o mês anterior —
erro que passa despercebido porque a tabela continua parecendo coerente.

**Fatie a string:** `referenceDate.Substring(0,7)` para obter `YYYY-MM`.

### ⚠️ `regularMarketTime` mente com o mercado fechado

Medido em 08/08/2026, um **sábado**, com a B3 fechada:

- `BBAS3` → `2026-08-07T21:31` — honesto, fechamento de sexta
- `^BVSP` → `2026-08-08T18:36` — **recarimbado com o horário da requisição**

O índice não negociou no sábado. O valor era o fechamento de sexta com timestamp
reescrito. Índices recarimbam; ações não.

**Portanto: valide o calendário antes de confiar no timestamp.** Se hoje for
fim de semana ou feriado, o dado é do último pregão, independentemente do que o
campo disser. Nunca escreva "hoje" com base só no `regularMarketTime` — cheque o
dia da semana primeiro e descreva o dado como "fechamento de [dia do último
pregão]".

### ⚠️ Um ticker por requisição

**O plano atual aceita apenas 1 ativo por chamada.** Dois ou mais retornam
**400**. A documentação pública fala em lotes de até 20 — não vale aqui.

Única exceção: os 4 tickers de sandbox gratuitos (`PETR4`, `MGLU3`, `VALE3`,
`ITUB4`) agrupam entre si, por serem de acesso público. Misturar um deles com
qualquer outro ticker volta a dar 400.

Medido em 08/08/2026:

| Requisição | Resultado |
|---|---|
| `PETR4,MGLU3,VALE3,ITUB4` | OK (4) — todos sandbox |
| `BBAS3` | OK (1) |
| `BBAS3,WEGE3` | **400** |
| `PETR4,BBAS3` | **400** — sandbox + não-sandbox |
| `MXRF11,HGLG11` | **400** |
| `^BVSP,^GSPC` | **400** |

Consequência prática: **uma chamada por ativo, sempre.** Comparar dois FIIs são
duas chamadas; um panorama com Ibovespa, S&P 500 e Nasdaq são três. Não é
desperdício, é o limite do plano — planeje o número de requisições por isso.

Índices (`^BVSP`, `^GSPC`, `^IXIC`) seguem a mesma regra: um por chamada. Não
têm restrição especial própria.

**Anual × trimestral:** `period=annual` para tendência estrutural,
`period=quarterly` para o que mudou agora. Não misture na mesma série sem avisar.

## BCB SGS — macro e câmbio

Gratuito, sem token, fonte primária. Formato:

```
https://api.bcb.gov.br/dados/serie/bcdata.sgs.{codigo}/dados/ultimos/{n}?formato=json
```

Séries verificadas em 08/08/2026:

| Série | Código | Último valor lido |
|---|---|---|
| Selic meta (% a.a.) | `432` | 14,00 |
| Selic diária (% a.d.) | `11` | 0,051660 |
| CDI diário (% a.d.) | `12` | 0,051660 |
| IPCA mensal (%) | `433` | 0,16 (jun/26) |
| IPCA acumulado 12m (%) | `13522` | 4,64 (jun/26) |
| IGP-M mensal (%) | `189` | -1,16 (jul/26) |
| IGP-DI mensal (%) | `190` | -0,86 (jul/26) |
| Desemprego PNAD (%) | `24369` | 5,4 (jun/26) |
| Dólar PTAX venda (R$) | `1` | 5,0908 (07/08) |
| Euro PTAX venda (R$) | `21619` | 5,8845 (07/08) |

Para série histórica em vez do último ponto, troque `/ultimos/1` por
`?formato=json&dataInicial=DD/MM/AAAA&dataFinal=DD/MM/AAAA` — note que o SGS usa
**DD/MM/AAAA**, não ISO.

**Cuidado com a defasagem.** Índices de inflação saem com semanas de atraso: em
08/08 o IPCA mais recente era de junho. Sempre informe o mês de referência, não
a data da consulta. Selic meta vem datada com a vigência (que pode ser futura),
e não com a data da reunião do Copom.

## BCB Focus — expectativas de mercado

Gratuito, sem token, oficial. Traz o que o mercado **espera**, não o que já
aconteceu — a única fonte prospectiva do projeto.

```
https://olinda.bcb.gov.br/olinda/servico/Expectativas/versao/v1/odata/ExpectativasMercadoAnuais?$top=20&$filter=Indicador eq 'Selic'&$orderby=Data desc&$format=json
```

Indicadores: `Selic` · `IPCA` · `PIB Total` · `Câmbio` · `IGP-M` · `IPCA
Administrados`. Payload em `value[]`. Campos úteis: `Data` (data da coleta),
`DataReferencia` (ano projetado), `Mediana`, `Minimo`, `Maximo`,
`numeroRespondentes`.

Coleta de 31/07/2026, para calibração:

| | Fim 2026 | Fim 2027 | Fim 2028 |
|---|---|---|---|
| Selic | 13,75% | 12,00% | 10,50% |
| IPCA | 5,03% | 4,22% | 3,80% |

**Como usar sem virar previsão.** Focus é **expectativa mediana de analistas**,
não fato nem garantia — e erra com frequência. Apresente sempre como "o mercado
projeta", nunca como "vai acontecer", e cite a data da coleta. Serve para
ancorar o cenário base em número em vez de achismo, e para mostrar ao leitor que
o consenso também é uma opinião.

Também há `ExpectativasMercadoTop5Anuais` (só as casas mais assertivas) e séries
mensais. Não testados.

## Tesouro Direto — Tesouro Transparente

Gratuito, sem token, fonte primária. Cobre Selic, Prefixado, IPCA+, Renda+ e
Educa+, com taxa de compra e venda e preço unitário.

**A URL do CSV muda.** Pegue sempre pelo catálogo, não fixe o link:

```
https://www.tesourotransparente.gov.br/ckan/api/3/action/package_show?id=taxas-dos-titulos-ofertados-pelo-tesouro-direto
```

O recurso com `format = CSV` traz a `url` do arquivo.

**É um arquivo grande:** ~13,7 MB, ~174 mil linhas, cobrindo desde 2014 e ~30s
de download. Não baixe a cada pergunta — baixe uma vez e filtre.

Formato: separador `;`, decimal com **vírgula**, datas `DD/MM/AAAA`, encoding
UTF-8. Colunas: `Tipo Titulo` · `Data Vencimento` · `Data Base` ·
`Taxa Compra Manha` · `Taxa Venda Manha` · `PU Compra Manha` ·
`PU Venda Manha` · `PU Base Manha`.

**Para as taxas de hoje:** filtre pela maior `Data Base`. Em 07/08/2026 havia 60
títulos.

### Duas armadilhas que confundem iniciante

**A taxa do Tesouro Selic não é o rendimento.** Ele aparece como `0,01%` a
`0,08%` — isso é o **spread sobre a Selic**, não o retorno total. O rendimento é
Selic + spread, hoje ~14%. Dizer "Tesouro Selic rende 0,01%" está errado e é
exatamente o tipo de erro que este projeto existe para não cometer.

**Título perto do vencimento distorce.** O IPCA+ 15/08/2026 aparecia com 14,69%
em 07/08 — vence em uma semana. Taxa anualizada sobre prazo curtíssimo não é
comparável com a de um título de 2035. Ignore ou sinalize.

## CDB, LCI, LCA — sem fonte, com comparador

Essas taxas **não são dado público** e nenhuma API as tem: não há mercado
centralizado, cada banco negocia bilateralmente e o valor varia por cliente,
volume e relacionamento. Os agregadores raspam plataformas de corretora e não
expõem API. Isso é estrutural, não falta de ferramenta.

O que existe é `ferramentas/renda-fixa.ps1`, que **avalia a oferta que o usuário
trouxer** contra referências oficiais — não busca taxa nenhuma:

```
.\ferramentas\renda-fixa.ps1 -Tipo CDB -Indexador CDI  -Taxa 110 -Anos 2
.\ferramentas\renda-fixa.ps1 -Tipo LCI -Indexador CDI  -Taxa 95  -Anos 1
.\ferramentas\renda-fixa.ps1 -Tipo CDB -Indexador IPCA -Taxa 7.2 -Anos 5 -Valor 300000
```

Calcula bruto, IR pela tabela regressiva, líquido, equivalência em % do CDI,
comparação com o Tesouro de prazo próximo e cobertura do FGC (R$ 250 mil por CPF
e conglomerado; teto global de R$ 1 milhão a cada 4 anos, fgc.org.br verificado
em 08/08/2026).

**Duas armadilhas técnicas:** o SGS do BCB rejeita requisição sem `User-Agent` de
navegador, e o PowerShell 5.1 não aceita `if` como expressão inline — ambas
resolvidas no script.

## ANBIMA — debêntures (`ferramentas/anbima-debentures.ps1`)

```
.\ferramentas\anbima-debentures.ps1 -Busca KLABIN
```

Mercado secundário de debêntures: código, emissor, vencimento, indexador, taxas
de compra/venda/indicativa, desvio padrão, PU e duration. Gratuito, sem cadastro.
Medido em 08/08/2026: **1.253 papéis** na referência de 07/08.

URL: `merc-sec-debentures/resultados/mdeb_{DDmesAAAA}_{cat}.asp`, com data no
formato `31jul2026`. Três categorias, e só essas três existem:

| Categoria | Papéis |
|---|---|
| `di_percentual` | 5 |
| `di_spread` | 590 |
| `ipca_spread` | 658 |

**Três armadilhas:**

1. **Só 5 dias úteis de histórico.** É foto do mercado, não série temporal. Para
   histórico longo não há fonte pública.
2. **O HTML não fecha as tags `</TR>`.** Regex de par aberto/fechado devolve
   zero linhas; o parser divide em `<TR` e conta os `<TD>`.
3. **Fim de semana e feriado não têm arquivo.** O script tenta os últimos 7 dias
   corridos até achar publicação e informa a referência que usou.

**CRI e CRA não estão nessas páginas** — a ANBIMA publica os dois em seções
separadas, não mapeadas.

⚠️ Debênture **não tem FGC**. E "taxa indicativa" é referência de mercado, não
oferta ao investidor — a taxa que ele consegue na corretora costuma ser pior.

## Alpha Vantage — notícias (fonte terciária)

Token em `ALPHAVANTAGE_TOKEN`. A API só aceita chave em query string — é
limitação deles, não escolha nossa.

```
https://www.alphavantage.co/query?function=NEWS_SENTIMENT&topics=financial_markets&limit=50&apikey=$ALPHAVANTAGE_TOKEN
```

Parâmetros: `topics` (`financial_markets`, `economy_macro`, `energy_transportation`,
`finance`…), `tickers`, `time_from`/`time_to` (`YYYYMMDDTHHMM`), `limit` (máx 1000).
Payload em `feed[]`: `title`, `url`, `time_published`, `source`, `summary`,
`ticker_sentiment[]`.

### Limites medidos (08/08/2026)

**25 requisições por dia**, 1 por segundo. É pouco — uma análise diária que
consulte três tópicos já queima 12% da cota. Planeje: consulte uma vez, reaproveite.

**Não aceita ticker da B3.** `PETR4.SA` retorna erro de formato. Só ADR:

| Empresa | ADR |
|---|---|
| Petrobras | `PBR`, `PBR.A` |
| Vale | `VALE` |
| Itaú | `ITUB` |
| Bradesco | `BBD`, `BBDO` |
| Ambev | `ABEV` |
| Embraer | `ERJ` |

Confirme o ADR antes de usar — a lista acima não foi verificada endpoint a
endpoint. Empresa brasileira **sem ADR não tem cobertura nenhuma** aqui, o que
exclui a maioria da B3 e todos os FIIs.

### Regras de uso — leia antes de citar qualquer coisa daqui

**É fonte terciária.** Serve para saber que *algo aconteceu* e para contexto
internacional. Nunca como base de um número, nunca como fonte única. Para empresa
brasileira, o fato relevante no FNET/CVM é a fonte primária e vence sempre.

**Ignore o campo de sentimento.** `overall_sentiment_label` traz rótulos como
"Bullish" e "Somewhat-Bullish". Isso é classificação automática de terceiro, não
análise — e reproduzi-la seria emitir sinal direcional, exatamente o que os
"Limites" do `CLAUDE.md` proíbem. Use o texto da notícia, descarte o rótulo.

**Filtre o ruído.** Parte do feed é gerada por robô: títulos no padrão
`TICKER|Nome|Price:X|Chg%:Y` são cotação formatada como manchete, sem conteúdo.
Fontes como `TradingKey` publicam muito disso. Descarte.

**Verifique a data.** `time_published` pode ter dias de atraso. Uma "notícia"
de quatro dias atrás não explica o movimento de hoje.

## FNET — documentos de fundos (FII, FIAGRO, FIDC)

Repositório oficial da B3. Gratuito, sem token. **É aqui que está a
inadimplência da carteira de um FII de papel**, e todo o resto que não cabe em
dado estruturado.

**Busca por CNPJ do fundo** (sem pontuação):

```
https://fnet.bmfbovespa.com.br/fnet/publico/pesquisarGerenciadorDocumentosDados?d=0&s=0&l=15&o[0][dataEntrega]=desc&cnpjFundo=97521225000125
```

**Download do documento:**

```
https://fnet.bmfbovespa.com.br/fnet/publico/downloadDocumento?id={id}
```

Devolve JSON com `recordsTotal` e `data[]`. Campos úteis: `tipoDocumento`,
`dataEntrega`, `dataReferencia`, `id`, `situacaoDocumento`, `versao`.

**Exige `User-Agent` de navegador** e **é lento** — use timeout de 60–90s. Sem
o header ou com timeout curto, parece fora do ar quando não está.

Tipos que importam:

| `tipoDocumento` | Para quê |
|---|---|
| **Relatório Gerencial** | **Inadimplência**, DRE realizado × não realizado, comentário do gestor |
| Informe Mensal Estruturado | Mesmo dado do `fii/reports` da brapi, na origem |
| Rendimentos e Amortizações | Confirmação do provento anunciado |
| Fato Relevante | Eventos do fundo |

O MXRF11 tinha 890 documentos, com Relatório Gerencial de 05/08/2026.

**O CNPJ vem do `fii/indicators`** (campo `cnpj`) — encadeie as duas fontes.

## CVM IPE — fatos relevantes de companhias

Fatos relevantes, comunicados ao mercado e avisos de empresas listadas.
Gratuito, oficial, **cobre toda a B3** — inclusive quem não tem ADR e por isso
não aparece no Alpha Vantage.

```
https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/IPE/DADOS/ipe_cia_aberta_{ANO}.zip
```

2026: 1,3 MB zipado → 11,6 MB de CSV, ~29 mil registros, 1.567 fatos relevantes.

Colunas: `CNPJ_Companhia` · `Nome_Companhia` · `Codigo_CVM` · `Data_Referencia` ·
`Categoria` · `Tipo` · `Especie` · `Assunto` · `Data_Entrega` ·
`Protocolo_Entrega` · `Versao` · **`Link_Download`**

Filtre `Categoria = "Fato Relevante"`. `Assunto` já resume o evento — muitas
vezes basta, sem abrir o PDF.

### Três armadilhas, todas medidas

**Encoding é Latin-1, não UTF-8.** Lendo como UTF-8, "Mobiliários" vira
"Mobili�rios" e qualquer filtro com acento falha silenciosamente. No PowerShell:
`Import-Csv -Delimiter ';' -Encoding Default`.

**Nome de empresa tem acento.** É `PETRÓLEO BRASILEIRO S.A. - PETROBRAS`, não
`PETROLEO`. Buscar sem acento devolve zero e parece "não houve fato relevante" —
erro perigoso. Prefira filtrar por `CNPJ_Companhia` ou por um trecho sem acento
(`PETROBRAS`).

**O dataset atrasa ~7 dias.** Em 08/08/2026 a entrega mais recente era 01/08.
Para evento de ontem, ele não serve — vá ao portal da CVM ou ao RI. Sempre
informe a data de corte do arquivo em vez de deixar implícito que está em dia.

## CVM dados abertos — substitui de graça o que a brapi bloqueia

Mesmo portal e mesma mecânica do IPE (ZIP anual, `;`, **Latin-1**). Verificado
em 08/08/2026, todos com arquivo de 2026:

| Dataset | Caminho | Substitui |
|---|---|---|
| Informe Mensal FII | `FII/DOC/INF_MENSAL/DADOS/inf_mensal_fii_{ANO}.zip` | `fii/reports` e `fii/indicators`, **para os 338 FIIs** |
| Demonstrações anuais | `CIA_ABERTA/DOC/DFP/DADOS/dfp_cia_aberta_{ANO}.zip` | `balance-sheet`, `income-statement`, `financial-data` |
| Trimestrais | `CIA_ABERTA/DOC/ITR/DADOS/` | idem, com frequência trimestral |
| Fatos relevantes | `CIA_ABERTA/DOC/IPE/DADOS/` | já em uso |

Base: `https://dados.cvm.gov.br/dados/`

### FII: implementado em `ferramentas/cvm-fii.ps1`

```
.\ferramentas\cvm-fii.ps1 -Ticker MXRF11
```

Monta a base de ~1.000 FIIs e compara o alvo contra os pares. Cache em `dados/`,
revalidado a cada 7 dias. Preço vem da brapi; o resto é CVM.

Quatro decisões que o script embute, todas apanhadas na marra:

1. **Decimal é PONTO** (formato US). Parsear com cultura pt-BR converte
   `9.229278` em `9229278` **em silêncio**. Use `InvariantCulture` sempre — e
   nunca faça round-trip por `Export-Csv`/`Import-Csv`, que reintroduz o bug.
2. **Encoding Latin-1** (`-Encoding Default`).
3. **A competência mais recente costuma estar vazia** — em 08/08 havia 1.326
   fundos em junho e só 85 em julho. O script pega a última com ≥80% do pico.
4. **`Segmento_Atuacao` vem errado na origem** — MXRF11, 72% em CRI, aparece
   como "Logística". O script classifica pela carteira real (CRI > 50% = papel),
   não pelo rótulo.

Campos úteis: `Valor_Patrimonial_Cotas`, `Patrimonio_Liquido`,
`Percentual_Despesas_Taxa_Administracao` (mensal, fração),
`Percentual_Dividend_Yield_Mes`, `Total_Numero_Cotistas`, e a carteira inteira
em `ativo_passivo`. Ticker sai do ISIN: `BRMXRFCTF008` → `MXRF11`.

### Ações: implementado em `ferramentas/cvm-acoes.ps1`

```
.\ferramentas\cvm-acoes.ps1 -Ticker WEGE3
```

Lê a DFP e devolve receita, margens, lucro, ativo, patrimônio, passivo, **P/L,
P/VP, ROE, ROA**. Validado: WEGE3 (P/L 29,97 · P/VP 10,95 · ROE 36,5%) e PETR4
(P/L 5,21 · P/VP 1,38 · ROE 26,5%), ambos com balanço fechando.

Estrutura da DFP: `BPA` ativo · `BPP` passivo e PL · `DRE` resultado · `DFC_MI`
caixa. Sufixo `_con` consolidado (padrão) e `_ind` individual (fallback com
aviso). `CD_CONTA` é padronizado — 3.01 receita, 3.03 lucro bruto, 3.05
operacional, 3.11 líquido, 2.03 patrimônio. `ORDEM_EXERC` traz dois exercícios
por arquivo; `ESCALA_MOEDA` diz se está em milhares.

**Não há ticker no arquivo.** O mapa CNPJ→ticker vem de `stocks/profile` da
brapi (`ferramentas/mapa-cnpj.ps1`, roda uma vez) e é indexado pela raiz de 4
letras — PETR3 e PETR4 compartilham CNPJ. Cobertura: 672 de 771 tickers.

**Casar por nome foi testado e descartado:** produziu falsos positivos como
`LUXM` → "TREVISA INVESTIMENTOS". Ticker fora do mapa é recusado, não adivinhado.

### Planos de contas — resolvido por descrição, não por código

Medido na DFP 2025:

| | Patrimônio líquido | 3.01 significa |
|---|---|---|
| Empresa operacional | `2.03` | Receita de venda |
| **Banco** | **`2.07`** | Receita de intermediação (juros brutos) |
| Seguradora | `2.03` | Receita da atividade seguradora |

Fixar `2.03` como patrimônio erraria o P/VP de banco em ~2,5× — no Bradesco,
`2.03` é "Provisões" (R$ 443 bi) e o patrimônio real é R$ 179 bi. **Sem erro
visível**, só um número plausível e falso.

O script localiza a conta pela **descrição** (`Patrimônio Líquido` em qualquer
`^2\.\d\d$`), o que sobrevive às três variações. A regra antiga por setor foi
removida: recusava seguradora à toa e não protegia contra a variação real, que
é de layout, não de setor.

**Para banco, margem sobre receita não é calculada** — `3.01` é juros brutos, não
faturamento. Reporta margem financeira (`3.03`), PDD, receita de serviços e
alavancagem. Validado: BBDC4 (P/VP 1,03 · ROE 13,4% · alavancagem 13,0×),
BBSE3 (P/L 8,80 · ROE 86,8%), WEGE3 inalterado.

### ITR — últimos 12 meses (`-Modo ltm`)

```
.\ferramentas\cvm-acoes.ps1 -Ticker WEGE3 -Modo ltm
```

O ITR (`CIA_ABERTA/DOC/ITR/DADOS/`) tem estrutura idêntica à DFP, com **duas
diferenças que quebram o parser ingênuo**:

**1. O resultado do ITR é ACUMULADO no ano — e o arquivo traz as duas versões da
mesma conta.** Para o 2T, existe a linha `01/01→30/06` (acumulado) e a linha
`01/04→30/06` (trimestre isolado). Neoenergia no 2T26: R$ 25,88 bi acumulado
contra R$ 12,57 bi isolado. Pegar a errada dobra ou corta o número pela metade,
sem nenhum erro visível. **Filtre `DT_INI_EXERC` terminando em `-01-01`.**

**2. Múltiplo sobre acumulado sai errado.** P/L calculado sobre o lucro de um
semestre é o dobro do real. A conta certa é o LTM:

```
LTM = ano cheio (DFP) − acumulado do ano anterior até o mesmo trimestre + acumulado atual
```

`ORDEM_EXERC='PENÚLTIMO'` no ITR já traz o mesmo período do ano anterior, então
os três termos saem de dois arquivos. No modo `ltm` o balanço também passa a ser
a foto mais recente do ITR, não a do fim do ano.

**Cada empresa entrega no seu ritmo:** em 08/08/2026, WEGE3 tinha 2T26 e PETR4
só 1T26. O script usa o trimestre mais recente disponível e informa qual é —
sempre cite o período, nunca "dados atuais".

Validado: WEGE3 LTM até 30/06/2026 (P/L 24,28 · ROE 41,4%) e PETR4 LTM até
31/03/2026 (P/L 5,33 · P/VP 1,29), ambos com balanço fechando.

## Sem cobertura

**Commodities** (Brent, minério de ferro) e **IFIX** (404 na brapi) não têm
fonte configurada. Se forem necessários, busque na web, cite a fonte e a data
explicitamente, e trate como fonte secundária — nunca de memória.

**Fundamentos de ação** — as alternativas seriam upgrade do plano brapi ou
dados abertos da CVM (DFP/ITR em CSV). Nenhuma implementada.

## Quando a fonte falhar

Erro de rede, 403, 404 ou ticker inexistente viram, no texto da análise:

> "Não consegui confirmar esse dado com uma fonte confiável."

Nunca viram estimativa, nunca viram silêncio. Um campo vazio e honesto vale mais
que um relatório completo e inventado.

**E a API não substitui o documento.** Ela entrega o número; fato relevante,
release trimestral, ata do Copom e relatório gerencial explicam **por quê**. Para
entender um movimento, o número é o começo da investigação, não o fim.
