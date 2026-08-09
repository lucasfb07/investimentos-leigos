---
name: analise-diaria
description: Panorama do mercado do dia — Ibovespa, dólar, juros, inflação, commodities, mercado internacional, notícias relevantes e riscos do momento, explicados para iniciantes. Use quando o usuário pedir "análise do mercado hoje", "como fechou o mercado", "o que aconteceu hoje", "resumo do dia", "por que o Ibovespa caiu", ou um panorama geral do cenário atual.
---

# Análise Diária do Mercado

## Regra de ouro deste relatório

Este é o formato com maior risco de número inventado, porque ele pede muitos
dados de uma vez. **Todo número aqui vem de busca feita agora**, com fonte e
horário/data de referência. Nenhum vem de memória.

Se a busca não retornar um dado, escreva "não confirmado" naquele campo e siga.
Um relatório com três campos vazios e honestos vale mais que um completo e
inventado.

Deixe claro se os dados são de **fechamento** (mercado encerrado) ou
**intradiário** (mercado aberto, número ainda vai mudar). Faz diferença.

## Antes de escrever

1. **Verifique o dia da semana ANTES de qualquer chamada.** Fim de semana ou
   feriado significa que o dado será do último pregão — e a API não avisa. Pior:
   cotação de índice vem **recarimbada com o horário da requisição** mesmo com o
   mercado fechado (verificado em 08/08/2026, sábado). Confiar no timestamp da
   API sem checar o calendário publica número de sexta como se fosse de hoje.
   Detalhes em `fontes.md`.
2. Puxe os dados conforme [referencias/fontes.md](../../../referencias/fontes.md):

   **Índices — brapi, três chamadas separadas.** O plano aceita **1 ticker por
   requisição**; agrupar retorna 400 (ver `fontes.md`):
   `/v2/stocks/quote?symbols=^BVSP` · `?symbols=^GSPC` · `?symbols=^IXIC`
   (Ibovespa, S&P 500, Nasdaq)

   **Macro e câmbio — BCB SGS**, formato
   `https://api.bcb.gov.br/dados/serie/bcdata.sgs.{cod}/dados/ultimos/1?formato=json`

   | Dado | Código |
   |---|---|
   | Selic meta | `432` |
   | CDI diário | `12` |
   | IPCA mensal | `433` |
   | IPCA acum. 12m | `13522` |
   | IGP-M | `189` |
   | Dólar PTAX venda | `1` |

   **Expectativas — BCB Focus** (`fontes.md`). O que o mercado projeta para
   Selic e IPCA nos próximos anos. É o que transforma "os juros podem cair" em
   número. Apresente sempre como expectativa mediana de analistas, com a data da
   coleta — consenso também erra, e não é previsão.

   **Tesouro Direto** — quando o panorama tocar em renda fixa, as taxas vêm do
   Tesouro Transparente. Arquivo grande: baixe uma vez, filtre pela maior
   `Data Base`.

3. Busque as notícias econômicas do dia, priorizando fonte primária (Copom,
   BCB, IBGE, fatos relevantes) sobre manchete de portal.

   **Fatos relevantes de empresas: CVM IPE** (`fontes.md`). É a fonte primária e
   cobre toda a B3. Duas ressalvas que mudam o uso: o arquivo é **Latin-1** (ler
   como UTF-8 quebra qualquer filtro com acento) e **atrasa ~7 dias** — não serve
   para evento de ontem. Informe a data de corte em vez de deixar implícito.

   O feed do Alpha Vantage (`fontes.md`) ajuda no contexto internacional, mas
   tem **25 requisições/dia** — uma consulta por relatório, não uma por assunto.
   Três regras inegociáveis: **descarte o campo de sentimento** (rótulo
   direcional automático), **filtre títulos-robô** no padrão `TICKER|Price:X`, e
   **cheque a data** antes de usar uma notícia para explicar o movimento de hoje.
   Empresa brasileira sem ADR não aparece — para essas, a fonte é o fato
   relevante no FNET/CVM.
4. Identifique setores de maior alta e maior queda, se disponível.

### Duas armadilhas específicas deste relatório

**Defasagem dos índices de inflação.** IPCA e IGP-M saem com semanas de atraso —
o dado "mais recente" pode ser de dois meses atrás. Sempre escreva o **mês de
referência**, nunca a data da consulta. "IPCA de junho, divulgado em julho" é
correto; "IPCA hoje" é errado e engana o leitor.

**Sem cobertura:** commodities (Brent, minério) e IFIX não têm fonte
configurada. Se entrarem no relatório, vêm de busca na web **com fonte e data
citadas** e marcados como secundários. Se não achar, escreva "não confirmado" —
esses dois campos são os de maior risco de o número sair da memória.

## Formato

```
# 📊 Análise do Mercado — [DD/MM/AAAA]
*Dados de [fechamento / intradiário às HHhMM]. Fontes: [...]*

## 🌎 Panorama
Brasil · Exterior · Juros · Inflação · Dólar · Commodities

## 📈 Mercado
Ibovespa: [pontos, variação %]
Dólar: [cotação, variação %]
Juros: [Selic, movimento da curva DI]

[Explique o mecanismo dos principais movimentos — não só "caiu 1,2%", mas por
quê, e como uma coisa puxa a outra.]

## 📰 Notícias importantes
Por notícia: o que aconteceu · fonte e data · por que importa · quem é afetado ·
**impacto temporário ou estrutural?**

Nem toda notícia é oportunidade. A maioria é ruído. Diga quando for ruído.

## 🔍 Movimentos que chamaram atenção
| Ativo/Setor | O que aconteceu | Leitura possível |

Descritivo. Explica o movimento e as hipóteses para ele — não emite sinal de
compra ou venda.

## ⚠️ Riscos do momento
Os principais riscos abertos no cenário, com o mecanismo de cada um.

## 📚 Como isso afeta cada tipo de investimento
Renda fixa · ações · FIIs · câmbio e internacional

Explique o encadeamento causal. Ex.: juro alto tende a favorecer a remuneração
da renda fixa e a pressionar empresas endividadas e ações de crescimento,
porque o custo do dinheiro sobe e o lucro futuro vale menos hoje.

## 🎯 Resumo em linguagem simples
Todo o cenário explicado como para alguém que nunca investiu. Sem jargão.

## 🚩 Armadilhas do dia
Decisões que o cenário atual torna especialmente arriscadas, e por quê —
perseguir alta forte, concentrar em ativo ilíquido, reagir por pânico a uma
notícia de impacto temporário.
```

## Encerramento

Uma linha de aviso, conforme `CLAUDE.md`. Sem repetir ao longo do texto.
