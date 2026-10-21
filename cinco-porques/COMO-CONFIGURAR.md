# Falha Zero — 5 Porquês · como configurar e usar

Painel de anomalias para a **reunião operacional** (líder + operadores do setor).
É um **banco de informações**, não uma ferramenta de gestão de ações: cada
resposta do Forms é uma anomalia com os 5 porquês. Na reunião, o grupo discute
cada anomalia, **prioriza a ação sugerida** e marca se ela já foi **lançada no
controle de ações da área**, onde ela é acompanhada (responsável, prazo, andamento).

```
Forms ──▶ Excel exportado ──(botão "Atualizar base")──▶ Supabase ──▶ painel (/cinco-porques no Vercel)
                                    reunião ──(Marcar como discutida)──▶ Supabase
```

| Arquivo | Para que serve |
|---|---|
| `supabase/migrations/20261013180000_cinco_porques.sql` | Tabelas `anomalias`, `anomalias_avaliacao`, `anomalias_backup`, view `anomalias_painel` e as funções de gravação |
| `supabase/migrations/20261021120000_cinco_porques_banco.sql` | Troca o acompanhamento de ações e o KPI impactado pela prioridade da ação sugerida e o lançamento no controle de ações |
| `cinco-porques/index.html` + `config.js` | O painel publicado no Vercel (`/cinco-porques`) |
| `cinco-porques/img/` | Logos ADM e Performance Excellence |
| `cinco-porques/PROMPT.md` | O prompt-modelo preenchido para este painel |

## 1. Supabase

Usa o **mesmo projeto** da Auditoria DEC. A migração entra sozinha no merge na
`main` (integração Supabase ↔ GitHub já configurada). Confira em **Table Editor**
se apareceram `anomalias`, `anomalias_avaliacao` e a view `anomalias_painel`.
Se a integração não rodar, cole o arquivo da migração no **SQL Editor**: ele pode
ser rodado mais de uma vez.

Segurança:
- a chave pública (`config.js`) só **lê** as tabelas;
- gravar é só pelas funções `gravar_anomalias`, `substituir_anomalias` e
  `registrar_reuniao` (sem login, como na auditoria);
- tudo que sai em "Substituir" ou "Apagar tudo" vai antes para
  `anomalias_backup`, que o site não lê.

## 2. Vercel

Nada a fazer: o projeto `a3-adm` já publica a pasta. O painel fica em
**`/cinco-porques`**. Com `?demo` no endereço, ou com o `config.js` vazio, ele
mostra dados de demonstração.

## 3. Atualizar a base

1. No Forms: **Respostas → Abrir no Excel** e baixe o arquivo.
2. No painel: **Atualizar base** → escolha o arquivo.
3. A prévia mostra quantas respostas são novas, quantas serão atualizadas (o ID
   evita duplicar), as linhas com erro e as colunas não encontradas.
4. Modos:
   - **Adicionar e atualizar** (padrão);
   - **Substituir toda a base**;
   - **Apagar tudo** (é preciso digitar `APAGAR`).

O **que foi registrado na reunião não se perde** ao atualizar ou substituir a base:
elas ficam numa tabela separada, ligadas pelo ID da resposta. Só "Apagar tudo"
as remove (com backup).

Colunas reconhecidas: `ID`, horas, `Email`, `Nome`, `Planta`, `Área`,
`Equipamento + TAG`, `Turno`, `Data do evento`, `Executante`, `Tipo de falha
observada`, `O que foi feito para resolver`, `Primeiro` a `Quinto Porquê`,
`Nível de clareza da investigação (1 a 5)`, `Causa raiz encontrada` (aceita mais
de uma, separadas por `;`), `Informe a causa…`, `Comentário da causa raiz
encontrada` e `Ações Sugeridas`. O título pode mudar um pouco no Forms: a
importação compara sem acento e aceita o início do título.

## 4. Como usar na reunião

1. **Filtre o setor**: planta, área, equipamento, autor, turno e período. Os
   filtros ficam no endereço, então o link já filtrado pode ir no convite da
   reunião.
2. **Pauta → A discutir**: anomalias que ainda não passaram pela reunião, com as
   reincidentes primeiro. Clique para abrir, leia a cadeia dos 5 porquês e a causa
   raiz e, em **Reunião operacional**:
   - dê a **prioridade da ação sugerida** (alta, média ou baixa);
   - marque **Lançada no controle de ações** quando ela já estiver lá (o número
     no controle é opcional);
   - anote observações, se houver;
   - clique em **Marcar como discutida**.

   As setas **‹ ›**, ou as setas do teclado, passam para a próxima anomalia.
3. **Pauta → Ações a lançar no controle**: ações sugeridas já priorizadas que
   ainda não foram para o controle de ações, da prioridade alta para a baixa.
   Depois de lançar, abra a anomalia e marque a caixa.
4. **Pareto**: por causa raiz, tipo de falha ou equipamento. As barras escuras
   são as "poucas e vitais", que somam 80%: é onde atacar primeiro. Clique numa
   barra para filtrar o painel por ela.

Indicadores no topo:
- **anomalias relatadas**, com a seta contra o mês anterior;
- **a discutir na reunião**;
- **ações a lançar no controle**, com quantas são de prioridade alta;
- **reincidentes**: mesmo equipamento com o mesmo tipo de falha mais de uma vez.

Clicar em um indicador filtra a lista.

O painel não acompanha as ações (responsável, prazo, andamento): isso fica no
controle de ações da área. Registros antigos dessas informações continuam
guardados no banco, só não aparecem mais.
