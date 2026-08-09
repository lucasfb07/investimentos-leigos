# Investimentos para leigos

Painel de triagem de investimentos brasileiros e americanos, montado sobre
**dados públicos oficiais** — CVM, Banco Central, Tesouro Nacional e B3.

Não é robô de recomendação. Ele aplica critérios que **você** define e mostra o
que passa, com a origem de cada número e — o que costuma faltar em ferramenta
do tipo — **onde o dado não existe**.

![abas](https://img.shields.io/badge/abas-6-0d6e6e) ![dados](https://img.shields.io/badge/fonte-CVM%20%C2%B7%20BCB%20%C2%B7%20B3-c2761b) ![custo](https://img.shields.io/badge/custo-R%24%200-1f7a4d)

## O que tem dentro

| Aba | Cobertura | Fonte |
|---|---|---|
| **Ações BR** | 437 empresas, fundamentos completos | DFP/ITR da CVM |
| **FIIs** | 1.045 fundos, com vacância por imóvel | Informe Mensal + Trimestral CVM |
| **Renda fixa** | 16 títulos do Tesouro + simulador de CDB/LCI/LCA | Tesouro Transparente, BCB |
| **EUA** | Watchlist com fundamentos | brapi + Alpha Vantage |
| **Fundos** | 25.348 fundos com retorno e volatilidade | Informe Diário CVM |
| **Carteira** | Diagnóstico estrutural das suas posições | local, nada sai do navegador |

## Como rodar

```powershell
# 1. Token gratuito da brapi (cotações) — crie em brapi.dev/dashboard
[Environment]::SetEnvironmentVariable("BRAPI_TOKEN", "SEU_TOKEN", "User")

# 2. Opcional: fundamentos de ações americanas — alphavantage.co
[Environment]::SetEnvironmentVariable("ALPHAVANTAGE_TOKEN", "SUA_CHAVE", "User")

# 3. Abra um terminal NOVO e rode
powershell -ExecutionPolicy Bypass -File ferramentas\atualizar.ps1
```

Abra `dashboard.html`. A primeira execução baixa ~2 GB de bases da CVM e leva
alguns minutos; depois só busca o que envelheceu.

Para rodar sozinho em dias úteis:

```powershell
schtasks /create /tn "InvestimentosLeigos" /sc weekly /d MON,TUE,WED,THU,FRI /st 20:00 `
  /tr "powershell -NoProfile -ExecutionPolicy Bypass -File CAMINHO\ferramentas\atualizar.ps1"
```

## Ferramentas

Cada uma roda sozinha, sem depender do painel:

```powershell
ferramentas\cvm-acoes.ps1     -Ticker WEGE3          # fundamentos e múltiplos
ferramentas\cvm-acoes.ps1     -Ticker PETR4 -Modo ltm # últimos 12 meses
ferramentas\screener-acoes.ps1 -MaxDivida 3 -MaxPayout 100
ferramentas\cvm-fii.ps1       -Ticker MXRF11         # FII contra seus pares
ferramentas\cvm-fii-imoveis.ps1                      # vacância imóvel a imóvel
ferramentas\screener-fiis.ps1 -MinPL 1e9
ferramentas\cvm-fundos.ps1    -Classe "Ações" -Meses 12
ferramentas\watchlist-eua.ps1 -Add NVDA,AMD
```

Mapa completo das fontes, endpoints e limites: [`referencias/fontes.md`](referencias/fontes.md).
Glossário: [`referencias/glossario.md`](referencias/glossario.md).

## Armadilhas de dado que este projeto trata

Foram todas encontradas na prática, medindo — e cada uma produzia número errado
**sem gerar erro visível**, que é o pior tipo de falha:

- **Vacância virando ocupação.** Parte dos FIIs preenche o campo com a taxa de
  ocupação: shoppings reportam "98% de vacância" enquanto geram receita normal.
  20 fundos são descartados por essa inconsistência, e viram `sem dado` — nunca `0`.
- **Banco tem plano de contas próprio.** No Bradesco, a conta `2.03` é
  "Provisões", não patrimônio. Fixar o código erraria o P/VP em ~2,5×. As contas
  são localizadas pela **descrição**, não pelo código.
- **Ponto é decimal nos arquivos da CVM.** Ler com cultura pt-BR transforma
  `9.229278` em `9229278` silenciosamente.
- **Encoding Latin-1.** Lido como UTF-8, `PETRÓLEO` não casa com `PETROLEO` e o
  filtro devolve zero como se não houvesse fato relevante.
- **A competência mais recente vem quase vazia.** Em agosto havia 1.326 FIIs
  entregues em junho e 85 em julho. Os scripts pegam a última com cobertura real.
- **A taxa do Tesouro Selic é spread, não rendimento.** Aparece como 0,01%–0,08%;
  o retorno é Selic + spread.
- **Um ticker por requisição** no plano gratuito da brapi, apesar de a
  documentação falar em lotes de 20.

## O que este projeto não faz

Não diz o que comprar, vender ou reduzir, e não sugere percentual de alocação.

No Brasil recomendar valores mobiliários profissionalmente exige registro na CVM
(Resoluções 19 e 20), e nenhum aviso de rodapé transforma recomendação
personalizada em análise. Os "Top 5" ordenam por critérios que você define, com
os pesos visíveis e editáveis — mudou o peso, mudou a ordem. É régua, não veredito.

O que ele faz é o oposto e mais útil: mostrar a estrutura, a origem de cada
número e o tamanho da incerteza.

## Limites conhecidos

- **CDB, LCI e LCA não têm fonte pública** — são negociados por banco e cliente.
  O simulador avalia a oferta que você informar contra CDI e Tesouro.
- **EUA é watchlist, não screener**: fundamentos custam 1 requisição por empresa
  e o teto gratuito é 25/dia. Cache de 30 dias mantém o consumo perto de zero.
- **Qualidade de imóvel, localização e contrato** não estão em base nenhuma.
- **DFP é anual, com ~3 meses de atraso**; o Informe Trimestral atrasa mais.

## Aviso

Ferramenta informativa e educacional. Investimentos envolvem riscos e nenhuma
rentabilidade é garantida. Rentabilidade passada não se repete. A decisão final
deve considerar seu perfil, objetivos e situação financeira, idealmente com
apoio de um profissional registrado na CVM.
