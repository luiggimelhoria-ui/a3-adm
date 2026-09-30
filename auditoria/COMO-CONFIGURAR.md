# Auditoria DEC — Passo 1 · como configurar

```
                       ┌── merge na main ──▶ Supabase (aplica supabase/migrations)
GitHub (este repo) ────┤
                       └── merge na main ──▶ Vercel (publica o painel /auditoria)

Excel do Forms ──(botão "Atualizar base" no painel)──▶ Supabase ──▶ painel lê as notas
Forms ──▶ Power Automate ──▶ issue ──▶ GitHub Action ──▶ Supabase   (opcional, automático)
```

| Arquivo | Para que serve |
|---|---|
| `supabase/migrations/20260930174847_auditoria_dec.sql` | Tabelas, segurança e **regra de aprovação** (view `auditorias_resultado`) |
| `supabase/migrations/20260930175759_envio_sem_login.sql` | Libera o botão "Atualizar base" sem login (incluir/atualizar; apagar não) |
| `supabase/migrations/20260930175931_auditor_e_numeracao.sql` | Coluna do nome do auditor e numeração P6–P18 |
| `supabase/migrations/20260930190239_criticas_configuraveis.sql` | Críticas P13–P16; a regra passa a ler as críticas da tabela `perguntas` |
| `supabase/migrations/20260930210558_substituir_e_limpar_base.sql` | Substituir toda a base / apagar tudo, com cópia de segurança em `auditorias_backup` |
| `supabase/migrations/20260930211306_modelo_10_itens.sql` | Modelo de 10 perguntas / 40 pontos; regra genérica a partir da tabela `perguntas` |
| `supabase/config.toml` | Configuração mínima para a integração Supabase ↔ GitHub |
| `.github/workflows/ingerir-auditoria.yml` | Recebe a issue do Power Automate e grava no Supabase |
| `scripts/auditoria.py` | Converte a resposta do Forms e grava; também importa o Excel |
| `auditoria/index.html` + `config.js` | O painel publicado no Vercel (`/auditoria`) |

## Regra de aprovação (implementada na migração)

- 10 perguntas (P6 a P15 no Forms), nota de 1 a 4 → máximo de **40 pontos**.
- **Critério 1:** pontos ≥ 85% do máximo → **34 pontos ou mais**.
- **Critério 2:** todas as perguntas **críticas** com nota **≥ 3**. Hoje são:
  **7 – Abertura de etiquetas no MAXIMO**, **8 – Monitoramento de etiquetas
  abertas x fechadas** e **9 – Checklist de Limpeza e Inspeção** (o painel numera
  as perguntas de 1 a 10; no Forms elas são P6 a P15). Elas ficam
  marcadas na coluna `critica` da tabela `perguntas`; a regra lê dali.
- O total e o máximo de pontos também vêm da tabela `perguntas` (4 pontos por
  pergunta), então a conta se ajusta se o número de perguntas mudar.
- Aprovada só se os dois critérios forem atendidos.

Para mudar a regra, crie uma **nova** migração em `supabase/migrations/` que recrie a view
`auditorias_resultado` (migrações já aplicadas não rodam de novo).

---

## 1. Supabase (banco de dados)

O banco é criado **pelo GitHub**, via integração do Supabase:

1. Supabase → **Project Settings → Integrations → GitHub** → conecte o
   repositório `luiggimelhoria-ui/a3-adm`.
   - *Supabase directory*: `.` (a pasta `supabase/` fica na raiz do repositório)
   - *Production branch*: `main`
   - Ative **Deploy to production**
2. A cada merge na `main`, o Supabase aplica as migrações novas de
   `supabase/migrations/`. Se a integração foi ligada depois do merge, faça um
   commit qualquer na `main` (ou cole a migração no **SQL Editor**, que é
   idempotente) para ela rodar a primeira vez.
3. Confira em **Table Editor** se existem `auditorias`, `perguntas` e
   a view `auditorias_resultado`.
4. Em **Project Settings → API Keys**, anote:
   - `Project URL` e a chave **pública** (`anon` ou `publishable`) → vão no
     `auditoria/config.js`
   - chave `service_role` / `secret` → **secreta**, só nos secrets do GitHub
     (passo 2), nunca no código

## 2. GitHub (secrets da Action)

No repositório: **Settings → Secrets and variables → Actions → New repository secret**

- `SUPABASE_URL` = Project URL
- `SUPABASE_SERVICE_KEY` = chave `service_role`

## 3. Carga inicial (opcional): respostas que já existem

Exporte as respostas do Forms para Excel e rode no seu computador:

```bash
pip install openpyxl
SUPABASE_URL=... SUPABASE_SERVICE_KEY=... python scripts/auditoria.py importar "DEC - Auditoria Passo 1.xlsx"
```

Pode rodar de novo sem duplicar: o `ID` da resposta é a chave.

## 3b. Atualizar a base pelo site (botão "Atualizar base")

É o jeito mais simples: exporte as respostas do Forms (**Respostas → Abrir no
Excel**), clique em **Atualizar base** no painel e escolha o arquivo. O painel
mostra quantas respostas são novas, quantas já existem (serão atualizadas, não
duplicadas) e quais linhas têm erro, antes de enviar.

O envio **não pede login**: qualquer pessoa com o link do painel consegue
incluir e atualizar auditorias (apagar não é permitido). Foi uma escolha do dono
do painel; para voltar a exigir login, veja o histórico das migrações em
`supabase/migrations/`.

Na mesma janela:

- **Substituir toda a base por este arquivo**: apaga o que está na base e deixa
  só o que vier no Excel. Use quando mudar o Forms (ex.: tirar uma pergunta).
- **Apagar tudo…**: esvazia a base (pede para digitar `APAGAR`).

Nos dois casos o que sai vai antes para a tabela `auditorias_backup` (não
aparece no site). Se o arquivo tiver erro, nada é apagado. Para recuperar um
backup, peça pelo SQL Editor / Claude.

Com o botão, o Power Automate (passo 5) passa a ser opcional: use-o só se quiser
que cada resposta entre sozinha, sem exportar o Excel.

## 4. Microsoft Forms

O formulário tem um campo com o **nome do auditor**. Qualquer coluna com
"auditor" no título (ex.: *Nome do auditor*) é gravada em `auditor_nome` e é o
nome que aparece no painel. Se ela vier vazia, o painel usa o nome/e-mail
registrado pelo Forms e, sem nada disso, mostra **Não identificado**.

## 5. Power Automate (a cada resposta nova)

Crie um **Fluxo da nuvem automatizado**:

1. **Gatilho:** *Microsoft Forms → Quando uma nova resposta é enviada* → escolha o formulário.
2. **Ação:** *Microsoft Forms → Obter detalhes da resposta* → mesmo formulário,
   *Id da resposta* = conteúdo dinâmico **Id da resposta**.
3. **Ação:** *Operação de Dados → Compor*. Cole o JSON abaixo e troque cada
   `<...>` pelo **conteúdo dinâmico** correspondente (sempre entre aspas):

   ```json
   {
     "id": "<Id da resposta>",
     "conclusao": "<Hora do envio>",
     "email": "<Email do respondente>",
     "auditor_nome": "<Auditor>",
     "planta": "<Planta>",
     "area": "<Área>",
     "equipamento": "<Equipamento2>",
     "tag": "<Informe a Tag do equipamento>",
     "q01": "<Treinamento da operação>",
     "q02": "<Recursos da estação>",
     "q03": "<Donos do equipamento>",
     "q04": "<Mapa de contaminação>",
     "q05": "<Tratamento das fontes de contaminação>",
     "q06": "<Grande Limpeza e restauração com registros antes e depois>",
     "q07": "<Abertura de etiquetas no MAXIMO>",
     "q08": "<Monitoramento de etiquetas abertas x fechadas>",
     "q09": "<Checklist de Limpeza e Inspeção>",
     "q10": "<Checklist de Lubrificação>"
   }
   ```

   As respostas podem vir como texto completo (`3 — Implementado. ...`): o script
   usa o primeiro número.
4. **Ação:** *GitHub → Criar um problema (issue)* — é conector **padrão**, não Premium.
   Conecte com a conta **dona do repositório** (`luiggimelhoria-ui`).
   - Proprietário: `luiggimelhoria-ui` · Repositório: `a3-adm`
   - Título: `[auditoria] ` + **Id da resposta** (tem que começar com `[auditoria]`)
   - Corpo: **Saídas** da ação *Compor*

Teste enviando uma resposta: em ~1 minuto a issue recebe um comentário com o
resultado (✅/❌) e é fechada. Se der erro, a issue recebe um comentário com o link do log.

> A Action só aceita issues abertas pela conta dona do repositório, para que
> ninguém de fora consiga inserir auditorias falsas.

## 6. Vercel (site)

1. Em <https://vercel.com> → **Add New → Project** → importe `a3-adm`.
2. Framework Preset: **Other**. Sem build command. **Deploy**.
3. Preencha `auditoria/config.js` com `SUPABASE_URL` e a chave **anon** e faça
   push: o Vercel republica sozinho.

O A3 continua em `/` e o painel fica em **`/auditoria`**. Enquanto o `config.js`
estiver vazio, o painel mostra dados de demonstração.

## Navegação do painel

- **Filtros** por Planta, Área, Equipamento, Auditor e período. Ficam na URL,
  então dá para mandar o link de uma visão filtrada.
- **Indicadores**: auditorias, taxa de aprovação, nota média contra a meta de
  85% e reprovadas por item crítico, com seta de tendência contra o mês anterior.
- **Por planta / área / equipamento / auditor** (menu lateral ou abas): do pior
  para o melhor. Clicar numa planta abre as áreas; numa área, os equipamentos.
- **Temas prioritários**: radar com a nota média de cada pergunta (0 no centro,
  4 na borda, então a distância é proporcional à nota; pontos vermelhos = média abaixo de 3) e, com filtro ativo, a média geral
  para comparar. Ao lado, "Onde agir primeiro": só as **críticas** com média abaixo de 3
  (nota 3 já passa). As demais (não críticas e críticas com 3 ou mais) ficam em
  "Demais perguntas", da menor para a maior média; a marca nas barras é a nota 3.
- **Auditorias**: reprovadas ou todas; clicar numa linha abre as 13 respostas.
- Logos ADM e Performance Excellence em `auditoria/img/`.

## Privacidade

O repositório é **público**. Isso significa que as issues, com as respostas
completas, e o site ficam visíveis para qualquer pessoa. Se os dados forem
internos, torne o repositório **privado** (Settings → General → Danger Zone).
Tudo continua funcionando, e o Vercel publica repositórios privados normalmente.
