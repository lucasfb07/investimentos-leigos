---
name: analise-ativo
description: Análise estruturada de um ativo individual — ação, FII, ETF, BDR, REIT, renda fixa, commodity ou criptoativo. Use quando o usuário perguntar sobre um ticker ou produto específico ("o que você acha de BBAS3", "analise MXRF11", "vale a pena o Tesouro IPCA+ 2035", "como funciona esse CDB"), pedir para entender fundamentos, valuation, dividendos ou riscos de um ativo, ou quiser saber por que um ativo subiu ou caiu.
---

# Análise de Ativo

Estruture a análise de um ativo individual de forma que um iniciante entenda o
raciocínio, não só a conclusão.

## Antes de escrever

1. **Identifique a classe** — ela decide o checklist *e* quanto dado existe.
2. **Consulte [referencias/fontes.md](../../../referencias/fontes.md)** e puxe os
   dados de lá. Nunca de memória. Não chame endpoint marcado como bloqueado.
3. **Busque o que mudou recentemente** — último resultado trimestral, fatos
   relevantes, mudança regulatória ou setorial. Uma análise sem os últimos 90
   dias está incompleta. Isso vem de documento, não de API:
   **FII → FNET** (busca por CNPJ, que vem do `fii/indicators`);
   **ação → CVM IPE** (`Categoria = "Fato Relevante"`). Veja `fontes.md` —
   ambos têm armadilhas de encoding e defasagem.
4. **Se faltar dado material, diga qual falta** e siga com o resto. Não preencha
   lacuna com estimativa apresentada como número.

### Cobertura por classe — leia antes de prometer análise

**FII: cobertura completa apenas para `MXRF11` e `HGLG11`.** Todo o resto da
suíte (`indicators`, `portfolio`, `dividends`, `properties`, `reports`,
`financials`) dá **403 para qualquer outro fundo** — medido contra 30 FIIs
líquidos, 28 falharam. Para os demais: só `stocks/quote` e o FNET, que aceita
qualquer CNPJ.

**Para comparar com pares, use `ferramentas/cvm-fii.ps1 -Ticker XXXX11`** — ele
monta a base de ~1.000 FIIs a partir do Informe Mensal da CVM e devolve P/VP, DY,
taxa de administração e a mediana do segmento. É o que a brapi não entrega.

O eixo **Valuation exige as duas réguas**: a própria história (via
`indicators/history`, quando disponível) e a mediana dos pares (via o script).
Um P/VP sem nenhuma das duas não sustenta adjetivo.

**Três endpoints que mudam a qualidade da análise — use sempre:**

`fii/indicators/history` — série mensal de preço, VP/cota, P/VP, DY e nº de
cotistas. **O indicador de hoje sozinho não diz quase nada.** P/VP 1,02 parece
neutro; ver que veio de 0,90 em 11 meses mostra reprecificação. Sempre compare o
ativo com a própria história antes de chamar um múltiplo de caro ou barato.
Payload sob a chave `history`.

`fii/reports` — Informe Mensal da CVM. Traz **taxa de administração**
(`adminFeeRate`), **amortização** (`amortizationRate`), patrimônio, nº de cotas,
composição por classe e passivo. Payload sob `reports`, **paginado**.

`fii/financials` — demonstração financeira anual auditada: **parecer do auditor**
e `fields.Link_Download` com o documento original no FNET.

**Como distinguir por que o VP/cota caiu.** Queda de valor patrimonial por cota
tem três causas que exigem tratamento diferente, e a combinação dos endpoints
separa as três:

| Causa | Como identificar |
|---|---|
| **Emissão de novas cotas** (diluição) | `sharesOutstanding` sobe em `fii/reports`. Se o PL cresce menos que o nº de cotas, o VP/cota cai sem nada ter piorado |
| **Amortização** (devolução de capital) | `amortizationRate` > 0, ou registro com label `AMORTIZACAO` em `fii/dividends` |
| **Marcação a mercado ou distribuição acima do resultado** | `sharesOutstanding` **constante** e PL caindo. Para separar as duas, o Relatório Gerencial no FNET traz a DRE com resultado **realizado** (caixa) e **não realizado** (marcação) em linhas distintas |

Nunca atribua queda de VP/cota a uma causa sem fazer essa checagem. As três têm
significados opostos para o investidor.

**Inadimplência de FII de papel não existe em dado estruturado** — nenhum
endpoint tem esse campo. Está no Relatório Gerencial (FNET), junto com CRIs em
atraso, renegociações e execução de garantias. Para um fundo de crédito, omitir
isso deixa a análise incompleta: diga que foi ao documento, ou diga que não foi.

**Ação: use `ferramentas/cvm-acoes.ps1 -Ticker XXXX3`.** Ele lê a DFP da CVM e
devolve receita, margens, lucro, patrimônio, dívida, **P/L, P/VP, ROE e ROA**.
Os endpoints de fundamento da brapi estão bloqueados; a CVM cobre o mesmo com
fonte melhor.

Três limites do script, todos por design:

- **Recusa banco e seguradora.** Plano de contas diferente — o parser genérico
  daria número errado em silêncio. Quando recusar, diga que o dado não está
  disponível para o setor financeiro; não improvise.
- **Recusa ticker fora do mapa CNPJ.** Cobertura de 672 de 771 tickers. Sem
  mapeamento confiável, prefere não responder a arriscar a empresa errada.
- **O padrão é o exercício anual**, com ~3 meses de defasagem.

**Prefira `-Modo ltm`** — combina DFP e ITR para medir os últimos 12 meses, que é
a base correta para P/L. O modo anual serve para comparar exercícios fechados.
Nunca calcule múltiplo sobre resultado acumulado de um trimestre: o ITR é
acumulado no ano, e P/L sobre um semestre dá o dobro do real.

**Sempre informe o período que o script devolveu.** Empresas entregam o ITR em
ritmos diferentes — em agosto de 2026, WEGE3 já tinha 2T e PETR4 só 1T. "Dados
atuais" é impreciso; "últimos 12 meses até 30/06/2026" é correto.

Se o script recusar, aí sim vale a regra antiga: escreva `indisponível` e siga.
Nunca infira margem por setor nem estime múltiplo a partir de preço.

**DY de ação é a exceção calculável:** some os proventos de 12 meses em
`dividends` e divida pelo preço de `quote`. Marque como cálculo próprio e diga
a janela usada.

## Quadro de evidências

Em vez de um veredito único de compra/venda, avalie três eixos separados. Eles
frequentemente apontam em direções diferentes — e é exatamente aí que está a
informação útil.

| Eixo | Escala | O que mede |
|---|---|---|
| **Fundamentos** | Frágeis · Mistos · Sólidos | Qualidade e consistência do negócio ou da estrutura |
| **Valuation** | Esticado · Neutro · Descontado | Preço atual vs. história do próprio ativo e vs. pares |
| **Risco** | Baixo · Moderado · Elevado · Alto | Quanto pode dar errado, e com que probabilidade |

Nunca declare um eixo sem justificar com dado. "Valuation descontado" exige
mostrar o múltiplo atual, a referência histórica e a dos pares.

Um ativo com fundamentos sólidos e valuation esticado não é "bom" nem "ruim" —
é caro. Explique a diferença.

## Estrutura da resposta

```
## [TICKER] — [Nome]
Classe · Setor · Dados de [DD/MM/AAAA]

### O que é, em uma frase
[Modelo de negócio em linguagem de quem nunca investiu]

### Quadro de evidências
Fundamentos: [nível] · Valuation: [nível] · Risco: [nível]

### O que os dados mostram
[FATO — números com fonte]

### O que isso pode significar
[INTERPRETAÇÃO — explicitamente rotulada como leitura, não fato]

### Pontos fortes
### Pontos fracos
### Principais riscos
[Por risco: o mecanismo, não só o rótulo. "Risco de vacância" não basta —
explique o que acontece com a distribuição se um inquilino grande sair.]

### Cenários
🟢 Positivo — o que precisa acontecer
🟡 Base — se o cenário atual seguir
🔴 Negativo — o que quebra a tese

### Horizonte típico dessa tese
[Curto: dias a meses · Médio: meses a poucos anos · Longo: vários anos]
Uma leitura de curto prazo nunca justifica automaticamente uma decisão de longo
prazo, nem o contrário.

### Convicção: [muito baixa / baixa / moderada / alta / muito alta]
[Justifique pela qualidade das evidências — não pelo desempenho recente]

### O que eu não sei
[Lacunas de dado, incertezas, o que mudaria a leitura]
```

## Checklists por classe

### Ações
Modelo de negócio · vantagem competitiva · receita · lucro · margens · ROE ·
ROIC · endividamento (dívida líquida/EBITDA) · geração de caixa · histórico de
resultados · política de dividendos · governança · controlador.

Valuation: P/L, P/VP, EV/EBITDA, DY — sempre em três comparações: **contra a
própria história, contra os pares do setor, e contra o crescimento esperado.**

Um múltiplo isolado não diz nada. P/L baixo pode significar preço atrativo — ou
que o mercado já espera queda de lucro. Diga qual das duas leituras os dados
sustentam, ou que não dá para distinguir.

> ⚠️ **Hoje, quase nada deste bloco vem de API.** Margens, ROE, dívida, receita
> e múltiplos estão bloqueados no plano atual. Só `quote`, `historical`,
> `dividends` e `profile` respondem — ou seja, dá para descrever preço,
> volatilidade, proventos, setor e modelo de negócio, mas não para avaliar
> qualidade financeira nem preço relativo.
>
> Se o usuário quiser esses números, o caminho é o **release trimestral ou o RI
> da empresa** — fonte primária, mais lenta e manual, mas legítima. Ofereça esse
> caminho em vez de entregar um múltiplo sem procedência.

### FIIs
Segmento · tipo (tijolo, papel, fundo de fundos, híbrido) · número e qualidade
dos imóveis · localização · vacância física e financeira · concentração de
inquilinos · prazo e tipo dos contratos (típico vs. atípico) · receita ·
histórico de distribuição · P/VP · alavancagem · gestão e taxas · liquidez
diária.

**Nunca avalie um FII pelo dividend yield sozinho.** DY alto frequentemente
sinaliza risco precificado, receita não recorrente (venda de ativo, ganho de
capital) ou queda esperada de distribuição. Sempre verifique se a distribuição
é recorrente antes de tratar o yield como sustentável.

### ETFs
Índice replicado · metodologia · composição e top 10 · concentração ·
diversificação setorial e geográfica · taxa de administração · liquidez e
spread · tracking (aderência ao índice) · tributação · política de dividendos
(distribui ou reinveste).

Explique sempre o conceito básico: comprar uma cota dá exposição a uma cesta
inteira, em vez de escolher ativo por ativo.

### Renda fixa

**Fontes:** Tesouro Direto via Tesouro Transparente; CDI e Selic via BCB SGS;
expectativa de juros via BCB Focus.

**CDB, LCI e LCA não têm fonte pública** — são ofertas bilaterais, negociadas por
banco e por cliente. Nunca invente uma taxa. Quando o usuário trouxer uma oferta:

```
.\ferramentas\renda-fixa.ps1 -Tipo LCI -Indexador CDI -Taxa 95 -Anos 1
```

Calcula o líquido após IR, converte para % do CDI, compara com o Tesouro de
prazo equivalente e checa o FGC. Aceita `CDB LCI LCA CRI CRA DEB DEB-INC RDB LC`
e indexador `CDI PRE IPCA`.

**Duas leituras que ele torna óbvias, e que a taxa de vitrine esconde:**
uma LCI a 95% do CDI equivale a um CDB de 115,2% (isenção de IR); e um CDB
IPCA+7,2% em 5 anos pode render *menos* que o Tesouro IPCA+ de prazo parecido —
risco de banco pagando abaixo do soberano. Sempre rode a comparação antes de
comentar se uma taxa é boa.

**Debêntures:** `ferramentas/anbima-debentures.ps1 -Busca KLABIN` traz a taxa
indicativa da ANBIMA (1.253 papéis). Lembre que é **referência de mercado, não
oferta ao investidor**, e que debênture **não tem FGC** — o spread sobre o DI
tem que ser lido junto com rating e garantias, nunca sozinho.

⚠️ **A taxa do Tesouro Selic é spread, não rendimento.** Aparece como 0,01%–0,08%
— o retorno é Selic + spread. Nunca escreva "rende 0,01%".

Emissor e risco de crédito · rating · indexador (prefixado, CDI, IPCA+) ·
taxa · prazo e vencimento · liquidez (diária, no vencimento, carência) ·
garantia (FGC e seu limite) · tributação (tabela regressiva, isenção de
LCI/LCA/CRI/CRA/debênture incentivada) · marcação a mercado.

**Use o Focus para contextualizar prefixado vs pós-fixado.** Se o mercado projeta
a Selic caindo, travar um prefixado alto tem lógica diferente de ficar no CDI —
explique o mecanismo dos dois lados, apresentando o Focus como expectativa que
pode errar, nunca como certeza, e sem dizer qual o usuário deve escolher.

Compare sempre **rentabilidade líquida × risco × liquidez × prazo**. "Maior
taxa = melhor" é falso: taxa mais alta normalmente é o preço de mais risco de
crédito, mais prazo ou menos liquidez. Diga qual dos três está sendo pago.

Para títulos com marcação a mercado, explique que vender antes do vencimento
pode gerar resultado diferente da taxa contratada — para cima ou para baixo.

### BDRs e REITs
Tudo de ações, mais: risco cambial (o retorno em reais depende do dólar),
tributação específica, liquidez no mercado local, e o fato de o BDR ser um
recibo lastreado no papel lá fora, não a ação em si.

### Cripto e ativos de alto risco
Explicação reforçada de funcionamento e risco antes de qualquer análise:
volatilidade, ausência de fluxo de caixa que sustente valuation tradicional,
risco de custódia, risco regulatório, liquidez em estresse. Não aplique
métricas de valuation de empresa a ativo sem fluxo de caixa.

## Limite

Descreva o ativo e para que tipo de objetivo e horizonte aquela classe costuma
ser usada — não diga ao usuário que ele deve comprá-lo, nem em que percentual.
Veja "Limites" no `CLAUDE.md`.
