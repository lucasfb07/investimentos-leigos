---
name: comparar-ativos
description: Comparação estruturada entre dois ou mais ativos, critério a critério. Use quando o usuário perguntar "qual é melhor, X ou Y", "ITSA4 ou BBAS3", "CDB ou Tesouro Selic", "prefiro FII de papel ou de tijolo", ou pedir para comparar ações, FIIs, ETFs, títulos de renda fixa ou classes de ativos entre si.
---

# Comparação entre Ativos

## Nunca responda com um nome

"Qual é melhor?" não tem resposta única, porque *melhor para quê* muda tudo. Um
ativo mais volátil não é pior — é diferente, e serve a objetivo e horizonte
diferentes.

A resposta útil mostra **em que critério cada um ganha, e o que se troca por
isso.** Toda vantagem tem uma contrapartida; a comparação existe para tornar a
troca visível.

## Antes de comparar

- Confirme que a comparação faz sentido. Comparar uma ação com um CDB exige
  explicar primeiro que são coisas de natureza diferente — uma é sociedade em um
  negócio, outra é empréstimo com prazo e taxa.
- Puxe os dados por [referencias/fontes.md](../../../referencias/fontes.md),
  dos dois lados **na mesma data**. Comparar um múltiplo de hoje com outro de
  três meses atrás distorce o resultado.
- **Uma chamada por ativo.** O plano aceita 1 ticker por requisição — comparar
  dois ativos são no mínimo duas chamadas por endpoint, não uma com os dois
  símbolos (isso retorna 400).

### Simetria de cobertura — checar antes de montar a tabela

Uma linha só entra se **os dois lados** tiverem o dado. Meia linha preenchida é
pior que linha nenhuma: o leitor compara o que está preenchido e ignora que o
outro lado é desconhecido, o que inverte conclusões.

Isso morde de forma concreta hoje: **FII tem P/VP e DY; ação não tem** (veja o
limite em `fontes.md`). Então:

- **FII × FII** — tabela completa, todos os critérios.
- **Ação × ação** — sem as linhas de Valuation e Crescimento. Sobram preço,
  histórico, volatilidade, dividendos, liquidez e setor, que já sustentam uma
  comparação útil.
- **Ação × FII** — comparação estrutural, não de múltiplos. Explique que são
  veículos de natureza diferente e compare o que é comparável: previsibilidade
  de renda, tributação, liquidez, tipo de risco.

Onde o dado faltar dos dois lados, escreva `sem dado` na célula. Nunca deixe em
branco — branco parece zero ou parece esquecimento.

## Formato

```
# [Ativo A] × [Ativo B]
*Dados de [DD/MM/AAAA] · Fontes: [...]*

## O que cada um é
Uma frase por ativo, em linguagem de iniciante.

## Comparação
| Critério | [A] | [B] |
|---|---|---|
| Risco | | |
| Retorno potencial | | |
| Dividendos / renda | | |
| Valuation | | |
| Crescimento | | |
| Liquidez | | |
| Diversificação embutida | | |
| Tributação | | |
| Horizonte típico | | |

Preencha com dado, não com adjetivo. "Risco: alto" diz pouco; "Risco: elevado —
receita concentrada em um único cliente (X% do total)" diz o que importa.

## A troca central
A frase mais importante da comparação: o que se ganha e o que se abre mão ao
escolher um em vez do outro.

Ex.: "A oferece previsibilidade de renda e menor oscilação; B oferece potencial
maior de valorização, ao custo de variação de preço que pode ser desconfortável
e de resultado incerto no curto prazo."

## Em que situação cada um costuma fazer sentido
Descreva o encaixe por **objetivo e horizonte**, não por pessoa:

"Para um objetivo de reserva com necessidade de resgate a qualquer momento, o
primeiro se encaixa melhor por causa da liquidez diária. Para acúmulo de
patrimônio ao longo de muitos anos, com tolerância a oscilação, o segundo tem
características mais alinhadas."

Note a diferença: isso descreve o encaixe entre produto e objetivo. Não diz ao
usuário qual objetivo ele deve ter, nem qual ativo ele deve comprar.

## O que a comparação não captura
Fatores fora da tabela que podem inverter a leitura — situação tributária
individual, custos da corretora, o resto da carteira, mudança regulatória
pendente.

## Convicção: [nível]
```

## Limite

Termine mostrando a troca, não escolhendo o vencedor pelo usuário. Se ele
insistir em "mas qual eu compro?", explique que a resposta depende de objetivo,
prazo e tolerância a perda que só ele define — e ofereça aprofundar o critério
que mais pesa para ele. Veja "Limites" no `CLAUDE.md`.
