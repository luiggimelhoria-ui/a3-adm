# Auditoria DEC — Passo 1 · como configurar

```
Microsoft Forms ──▶ Power Automate ──(abre uma issue)──▶ GitHub Action ──▶ Supabase
                                                                              │
                        GitHub (código) ──(deploy automático)──▶ Vercel ◀─────┘ (lê as notas)
```

| Arquivo | Para que serve |
|---|---|
| `supabase/schema.sql` | Tabelas + **regra de aprovação** (view `auditorias_resultado`) |
| `.github/workflows/ingerir-auditoria.yml` | Recebe a issue do Power Automate e grava no Supabase |
| `scripts/auditoria.py` | Converte a resposta do Forms e grava; também importa o Excel |
| `auditoria/index.html` + `config.js` | O painel publicado no Vercel (`/auditoria`) |

## Regra de aprovação (implementada em `supabase/schema.sql`)

- 13 perguntas, nota de 1 a 4 → máximo de 52 pontos.
- **Critério 1:** pontos ≥ 85% de 52 → **45 pontos ou mais** (44 = 84,6% reprova).
- **Critério 2:** perguntas críticas **P12 – Abertura de etiquetas no MAXIMO** e
  **P16 – Limpeza como momento de inspeção** com nota **≥ 3**.
- Aprovada só se os dois critérios forem atendidos.

Para mudar a regra, altere só a view `auditorias_resultado` e rode o SQL de novo.

---

## 1. Supabase (banco de dados)

1. Crie um projeto em <https://supabase.com> (plano gratuito atende).
2. **SQL Editor → New query** → cole todo o `supabase/schema.sql` → **Run**.
3. Em **Project Settings → API**, anote:
   - `Project URL`
   - chave `anon` `public` → vai no site
   - chave `service_role` → **secreta**, vai só no GitHub

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

## 4. Microsoft Forms

Em **Configurações** do formulário, marque *Somente pessoas da minha organização
podem responder* + *Registrar nome*. Sem isso o auditor fica como
"anonymous" e o painel mostra **Não identificado**.

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
     "planta": "<Planta>",
     "area": "<Área>",
     "equipamento": "<Equipamento2>",
     "tag": "<Informe a Tag do equipamento>",
     "q01": "<Treinamento da operação>",
     "q02": "<Recursos da estação>",
     "q03": "<Donos do equipamento>",
     "q04": "<Mapa de contaminação>",
     "q05": "<Tratamento das fontes de contaminação>",
     "q06": "<Grande Limpeza e restauração>",
     "q07": "<Evidências Antes x Depois>",
     "q08": "<Abertura de etiquetas no MAXIMO>",
     "q09": "<Monitoramento de etiquetas abertas x fechadas>",
     "q10": "<Checklist de Limpeza>",
     "q11": "<Checklist de Inspeção>",
     "q12": "<Limpeza como momento de inspeção>",
     "q13": "<Checklist de Lubrificação>"
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
- **Temas prioritários**: radar com a nota média de cada pergunta (1 no centro,
  4 na borda), meta de 3,4 (= 85%) tracejada e, com filtro ativo, a média geral
  para comparar. Ao lado, as perguntas com menor nota, em ordem de prioridade.
- **Auditorias**: reprovadas ou todas; clicar numa linha abre as 13 respostas.
- Logos ADM e Performance Excellence em `auditoria/img/`.

## Privacidade

O repositório é **público**. Isso significa que as issues, com as respostas
completas, e o site ficam visíveis para qualquer pessoa. Se os dados forem
internos, torne o repositório **privado** (Settings → General → Danger Zone).
Tudo continua funcionando, e o Vercel publica repositórios privados normalmente.
