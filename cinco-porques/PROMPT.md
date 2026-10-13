Quero criar um painel web para acompanhar as **anomalias do Falha Zero analisadas com os 5 Porquês**, para ser usado na **reunião operacional do setor** (líder + operadores), que avalia os KPIs impactados por cada anomalia (ex.: umidade acima da tolerância). A coleta é feita no Microsoft Forms e exportada para Excel.

## Fluxo e arquitetura
- Forms → Excel exportado → botão "Atualizar base" no painel → Supabase → painel publicado no Vercel.
- Código no GitHub, com deploy automático no Vercel a cada merge na `main`.
- Página única em HTML/CSS/JS puro, sem build e sem framework. `config.js` separado com `SUPABASE_URL` e a chave **pública** (publishable/anon). Nunca colocar a service_role no código.
- Supabase:
  - tabelas com RLS, só leitura pela chave pública;
  - gravação via funções RPC `security definer`;
  - uma view que junta a anomalia com a avaliação da reunião e calcula os campos derivados (autor, data de referência, lista de causas, nº de porquês preenchidos);
  - migrações versionadas em `supabase/migrations/`.
- Sem login para enviar (decisão minha). A proteção é uma cópia de segurança: tudo que for apagado ou substituído vai antes para uma tabela `_backup`.
- Com `?demo` no endereço, ou sem `config.js` preenchido, o painel mostra dados de demonstração.

## Importação do Excel ("Atualizar base")
- Ler o .xlsx no navegador com SheetJS (cdnjs, carregado só quando abrir a janela, `cellDates:true`).
- Reconhecer as colunas do Forms:
  - ID, Hora de início, Hora de conclusão, Email, Nome e Hora da última modificação;
  - cabeçalho: Planta, Área, Equipamento + TAG, Turno, Data do evento, Executante;
  - relato: Tipo de falha observada, O que foi feito para resolver, Primeiro a Quinto Porquê, Nível de clareza da investigação (1 a 5), Causa raiz encontrada (múltipla escolha, separada por `;`), Informe a causa (caso "Outra causa"), Comentário da causa raiz encontrada, Ações Sugeridas;
  - opcional: KPI impactado.
- Comparar os títulos sem acento, em minúsculas e com espaços normalizados (inclusive espaço não separável). Aceitar título que comece com o esperado ou vice-versa, porque o Forms muda títulos.
- Antes de enviar, mostrar uma prévia:
  - quantas respostas são novas e quantas serão atualizadas (o ID evita duplicar);
  - linhas com erro;
  - "Colunas não encontradas" (pedir confirmação se faltar alguma).
- Modos:
  - **Adicionar e atualizar** (upsert por ID), o padrão;
  - **Substituir toda a base**;
  - **Apagar tudo** (exige digitar APAGAR).
  - Os dois últimos fazem backup antes.
- As avaliações da reunião ficam numa tabela separada (por ID) e não se perdem ao atualizar ou substituir.

## Regra de negócio
- Não há nota nem aprovação: é um banco de relato de anomalias.
- **Avaliação na reunião**, por anomalia:
  - KPI impactado (lista sugerida + texto livre);
  - condição do KPI: acima da tolerância, abaixo da tolerância, dentro da tolerância ou sem impacto;
  - status: A avaliar, Em análise, Ação em andamento ou Concluída;
  - responsável, prazo e observações.
- **Reincidente**: mesmo equipamento com o mesmo tipo de falha mais de uma vez.
- **Atrasada**: prazo vencido e status diferente de Concluída.
- **Pareto** das anomalias por causa raiz, tipo de falha, equipamento e KPI impactado, com a linha de % acumulado e a marca de 80%.

## Navegação e visual
- Filtros por Planta, Área, Equipamento, Autor (Executante), Turno e período. Ficam na URL, para poder compartilhar o link já filtrado. Mostrar os filtros ativos em chips removíveis; clicar no Pareto, nos KPIs ou nos indicadores também filtra.
- Layout enxuto ("lean"):
  - menu lateral fixo (200px) com o logo e o roteiro da reunião no rodapé;
  - topo fixo com título, logos e um selo da fonte dos dados (ao vivo / demonstração / erro).
- 4 KPIs: anomalias relatadas (seta contra o mês anterior), a avaliar na reunião, ações em aberto (com atrasadas) e reincidentes.
- **Pauta da reunião**:
  - aba "A avaliar": reincidentes primeiro, depois as mais antigas;
  - aba "Ações em aberto": atrasadas primeiro, depois por prazo.
- **KPIs impactados**: barra por KPI dividida em fora, dentro e sem impacto.
- **Pareto**: barras escuras para as "poucas e vitais" (até 80%) e clique para filtrar.
- Progresso por grupo, com abas Planta / Área / Equipamento / Autor:
  - cartões da maior para a menor quantidade;
  - clicar em uma planta abre as áreas dela, e assim por diante.
- Tabela de registros (não concluídas / todas). Clicar numa linha abre o detalhe:
  - cadeia dos 5 porquês, clareza, causa raiz e ações sugeridas;
  - o formulário de avaliação;
  - setas para passar para a próxima anomalia durante a reunião.
- SVG feito à mão para o Pareto e as barras, sem biblioteca de gráficos. Tooltips simples via `data-dica`.
- Estilo:
  - cores em tokens CSS no `:root`, com tema escuro automático por `prefers-color-scheme`;
  - fonte Inter / Segoe UI, 14px; cartões brancos com borda `#e7eaf0`, raio 12px, fundo `#f5f6f9`;
  - azul-marinho `#212c65` como cor de destaque, verde `#85c440`, barras `#3a63d6`;
  - estados: ok `#139f5b`, atenção `#d98a06`, ruim `#d9362b`;
  - números tabulares;
  - responsivo: no celular o menu lateral some e as abas assumem a navegação.
- Logos obrigatórios: ADM e Performance Excellence, numa placa branca para funcionar no tema escuro.
- Texto todo em português do Brasil.

## Entregáveis
- `index.html`, `config.js`, `img/`, `supabase/migrations/*.sql`, `supabase/config.toml` e um guia curto de configuração (Supabase, Vercel, como atualizar a base, como usar na reunião).
- Testar a importação com o meu Excel antes de publicar.

Anexo: Excel exportado do Forms "Falha Zero – 5 Porquês" e logos.
