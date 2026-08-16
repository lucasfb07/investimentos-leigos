---
name: dados-financeiros
description: Regras para não ser enganado por dado financeiro que falha em silêncio — número plausível e errado. Use sempre que for calcular indicador, montar screener, ranquear ativos, comparar rentabilidade, ler planilha ou API financeira, ou juntar série temporal de preço, cota, rendimento ou balanço. Vale para CVM, B3, Banco Central, brapi, Yahoo, Bloomberg, export de corretora, planilha de terceiro e qualquer CSV com números de mercado. Use também quando o resultado "parecer bom demais", quando um ativo desconhecido liderar um ranking, ou quando alguém pedir para conferir uma conta financeira que já foi feita.
---

# Análise de dado financeiro

O modo de falha dominante aqui não é o erro que quebra. É o erro que **roda,
devolve um número plausível e está errado** — e ninguém percebe porque não há
exceção, não há aviso, e o valor cai dentro de uma faixa que parece razoável.

Um ranking com o ativo errado no topo é pior que um ranking vazio: o vazio você
investiga, o errado você usa.

Estas regras vieram de erros reais cometidos em cima de dados públicos
brasileiros. Cada uma custou um número publicado errado antes de ser descoberta.

## A regra que mais salva: vazio nunca é zero

Campo ausente tem que ser **ausente** ao longo de todo o caminho — na leitura, no
cálculo, no filtro, no ranking e na tela. No instante em que ele vira `0`, ele
para de ser "não sei" e passa a afirmar alguma coisa. E quase sempre afirma o
melhor caso.

Como isso aparece na prática:

| Contexto | Vazio vira | Afirmação falsa |
|---|---|---|
| Vacância de fundo | 0% | "imóvel totalmente ocupado" |
| Filtro numérico em branco | 0 | "só ativos com dívida ≤ 0" |
| Taxa de administração | 0 | "fundo não cobra nada" |
| Concentração | 0 | "perfeitamente diversificado" |
| Eixo de score | 0 | pode cair num percentil alto se o resto for negativo |

Esse último é o mais perigoso e o menos óbvio. Num grupo onde muitos ativos têm
retorno negativo, o **zero fica acima da mediana** — então o ativo sem dado
nenhum recebe nota alta justamente por não ter dado. Já vi um fundo sem uma
única métrica preenchida chegar a terceiro lugar assim, com nota 72 em retorno,
100 em sustentabilidade, 100 em diversificação e 100 em taxa. Todas por ausência.

O que fazer:

- Na leitura, `null` e não `0`. Em linguagem que confunde os dois (`+""` é `0` em
  JavaScript; string vazia parseia como zero em vários lugares), teste
  explicitamente antes de converter.
- No filtro, campo em branco significa **filtro desligado**, não filtro em zero.
- No ranking, quem não tem a métrica principal **não é ranqueado**. Sem o dado
  que carrega o maior peso, não há o que pontuar. Ele continua na tabela para
  consulta, fora do Top N.
- Em eixo secundário faltando, use valor **neutro** (o meio da escala), nunca o
  melhor.
- Na tela, mostre `—` e não `0`. E se houver legenda, diga que traço é ausência.

## Antes de compor uma série, cheque plausibilidade

Composição multiplica. Uma linha errada contamina o período inteiro, e
anualizar multiplica de novo.

Um fundo reportou rendimento mensal de `0,89` num mês em que todos os outros
foram `0,009` — a linha veio em outra escala. Composta e anualizada, gerou
retorno de **2.129% ao ano** e foi para o primeiro lugar do ranking.

Antes de multiplicar valores de uma série, defina a faixa plausível para aquele
indicador e **descarte a observação fora dela, não o ativo inteiro**. Rendimento
mensal de fundo imobiliário acima de 5% já é extraordinário; acima disso é quase
sempre erro de preenchimento. Se sobrar menos da metade da série, aí sim o ativo
sai por falta de base.

Conte e reporte quantas observações foram descartadas. Silêncio aqui é o mesmo
problema de novo.

## Anualize antes de comparar

Taxa só se compara com taxa do mesmo período. Misturar rendimento anualizado com
retorno de seis meses na mesma tabela produz linhas que não fecham e conclusões
invertidas.

Um fundo aparecia com rendimento de 13,5% (anualizado) e retorno total de 4,7%
(seis meses). Parecia catástrofe. Anualizado corretamente, o retorno era 9,7% —
ainda abaixo do CDI, mas outra história.

Componha e eleve a `12/n`, onde `n` é o número de observações mensais que você
realmente tem — não o que deveria ter. E deixe a conta fechar: se você mostra
distribuição, variação patrimonial e retorno total lado a lado, o leitor precisa
conseguir somar mentalmente e chegar no terceiro.

## Localidade e encoding corrompem número sem avisar

Dois erros que não geram exceção e mudam a ordem de grandeza:

**Decimal.** Arquivos da CVM usam ponto como decimal; a cultura pt-BR usa
vírgula e trata ponto como separador de milhar. Ler `9.229278` com a cultura
errada produz `9229278` — um milhão de vezes maior, sem erro. Force cultura
invariante na leitura, e cuidado com ida e volta por CSV, que grava na cultura
local e reintroduz o problema na releitura.

**Encoding.** Arquivos da CVM são Latin-1. Lidos como UTF-8, `PETRÓLEO` não casa
com `PETROLEO` e o filtro devolve zero como se não houvesse registro. Um filtro
que falha vazio é pior que um que estoura, porque parece resposta.

Ao juntar valor de duas fontes, confira uma amostra contra valor conhecido antes
de confiar no conjunto.

## O rótulo da fonte pode estar errado — o dado bruto raramente

Campos categóricos e derivados são preenchidos por pessoas e vêm errados com
frequência maior do que se imagina.

- Um fundo 100% de papel, sem um imóvel, aparece classificado como "Logística"
  na base oficial. Classificar pela **carteira real** resolve; confiar no rótulo
  não.
- Vários fundos preenchem o campo de vacância com a **taxa de ocupação**:
  shoppings reportando "98% de vacância" enquanto geram receita normal.

O teste que pega isso é procurar **contradição entre dois campos que deveriam
concordar**. Um imóvel 98% vago não pode ser 17% da receita do fundo. Quando os
dois se contradizem, descarte o campo suspeito — e descarte para **ausente**,
não para zero, senão você troca um erro por outro na direção oposta. Não tente
inverter o valor: isso é adivinhar a intenção de quem preencheu.

## A competência mais recente costuma estar vazia

Base regulatória enche ao longo do tempo. O mês mais recente tem os primeiros
que entregaram, não o universo. Uma base tinha 1.326 fundos em junho e 85 em
julho — usar julho por ser "mais atual" reduziria a amostra em 94%.

Pegue a última competência com cobertura próxima do pico (80% costuma funcionar)
e diga qual foi. E lembre que data de **entrega** não é data de **referência**:
um relatório entregue em 05/08 pode se referir a 30/06.

## Um indicador isolado não sustenta conclusão

O indicador famoso costuma ser o mais enganoso, porque é o mais otimizável.

O caso clássico em fundo imobiliário: o rendimento distribuído parece ótimo
enquanto o patrimônio por cota encolhe. O dinheiro pinga na conta e a base que
gera a renda diminui — parte da distribuição é devolução do seu próprio capital.
Um fundo com 13,5% de rendimento entregava 9,7% de retorno real; outro, com 9,3%
de rendimento, entregava 17,8%. O ranking por rendimento estava exatamente
invertido.

Sempre que existir um indicador de "quanto pingou", procure o de "quanto sobrou"
e mostre os dois. Em ação, lucro crescendo muito acima da receita costuma ser
ganho não recorrente, não negócio crescendo — a receita é a coluna de controle.

## Ancore no custo de oportunidade

Número absoluto não significa nada sozinho. `Retorno de 12%` é bom ou ruim
depende do que a renda fixa paga sem risco relevante.

No Brasil a régua é o CDI (nominal) e o juro real:

```
juro real = (1 + Selic) / (1 + IPCA) − 1
```

Divisão, não subtração. Com Selic a 14% e IPCA a 4,44%, o juro real é 9,15% ao
ano — não 9,56%.

Busque esses números na hora; eles mudam. E compare sempre o retorno **total**
com a régua, não a parte distribuída.

## Quando o resultado parecer bom demais, ele provavelmente está errado

Ativo desconhecido liderando ranking é sinal de bug antes de ser sinal de
oportunidade. A ordem de investigação que funciona:

1. Abra o **dado bruto** daquele ativo, mês a mês. A anomalia quase sempre está
   visível a olho nu numa linha só.
2. Confira se ele tem **todos** os campos preenchidos. Liderança por ausência é
   o caso mais comum.
3. Verifique a **unidade** contra um ativo conhecido do mesmo grupo.
4. Se o número for real, veja se vem de **evento único** — reavaliação, venda de
   ativo, ganho não recorrente — extrapolado para o ano.

## Verificação: rode o cálculo e confira a contagem

Checar sintaxe não pega nenhum dos erros acima. Todos rodam sem exceção.

O que pega:

- **Contagem antes e depois de cada filtro.** Uma queda inesperada revela filtro
  ativo por acidente. Foi assim que apareceu um filtro em branco cortando 15 de
  45 empresas.
- **Identidades contábeis.** Ativo = passivo + patrimônio. Se não fecha, o
  mapeamento de contas está errado.
- **Amostra contra fonte conhecida.** Um punhado de ativos conferidos contra
  valor já validado detecta erro de escala, coluna trocada e unidade.
- **Sanidade dos extremos.** Olhe o topo e o fundo do ranking, não a mediana. O
  lixo se acumula nas pontas.

Quando cruzar uma fonte nova sem cabeçalho ou com colunas ambíguas, identifique
as colunas por **erro médio contra dados que você já validou**, não por
suposição. Foi assim que uma coluna que parecia vacância se revelou outra coisa:
errava 14,75 pontos percentuais, enquanto a coluna correta errava 0,03.

## Ao apresentar

- Diga a **data de referência** do dado, não a data da consulta.
- Diga o que **não** está no cálculo. Vacância que não existe na base, custo que
  o indicador não captura, período curto demais para concluir.
- Marque o que é **estimativa** e o que é medido.
- Se um dado foi descartado por implausibilidade, diga quantos e por quê.
- Rentabilidade passada não projeta futuro — e série de poucos meses não sustenta
  conclusão sobre ativo de longo prazo, por mais limpa que esteja.
