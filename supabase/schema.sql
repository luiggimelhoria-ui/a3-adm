-- =====================================================================
-- Auditoria DEC — Passo 1 · esquema do Supabase
-- Rode este arquivo inteiro no SQL Editor do Supabase (pode rodar de novo
-- sem perder dados: tudo usa IF NOT EXISTS / OR REPLACE).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Perguntas do checklist (13 itens, notas de 1 a 4)
-- numero_forms = número da pergunta no Microsoft Forms (as 4 primeiras
-- são o cabeçalho: Planta, Área, Equipamento, Tag).
-- ---------------------------------------------------------------------
create table if not exists perguntas (
  numero        smallint primary key,          -- 1..13 (q01..q13)
  numero_forms  smallint not null unique,      -- 5..17
  titulo        text not null,
  critica       boolean not null default false -- precisa de nota >= 3
);

insert into perguntas (numero, numero_forms, titulo, critica) values
  ( 1,  5, 'Treinamento da operação',                          false),
  ( 2,  6, 'Recursos da estação',                              false),
  ( 3,  7, 'Donos do equipamento',                             false),
  ( 4,  8, 'Mapa de contaminação',                             false),
  ( 5,  9, 'Tratamento das fontes de contaminação',            false),
  ( 6, 10, 'Grande Limpeza e restauração',                     false),
  ( 7, 11, 'Evidências Antes x Depois',                        false),
  ( 8, 12, 'Abertura de etiquetas no MAXIMO',                  true),
  ( 9, 13, 'Monitoramento de etiquetas abertas x fechadas',    false),
  (10, 14, 'Checklist de Limpeza',                             false),
  (11, 15, 'Checklist de Inspeção',                            false),
  (12, 16, 'Limpeza como momento de inspeção',                 true),
  (13, 17, 'Checklist de Lubrificação',                        false)
on conflict (numero) do update
  set numero_forms = excluded.numero_forms,
      titulo       = excluded.titulo,
      critica      = excluded.critica;

-- ---------------------------------------------------------------------
-- Respostas brutas (uma linha por envio do Forms)
-- ---------------------------------------------------------------------
create table if not exists auditorias (
  id              bigint generated always as identity primary key,
  resposta_id     text not null unique,        -- "ID" do Forms (evita duplicar)
  inicio          timestamptz,
  conclusao       timestamptz,
  email           text,
  nome            text,
  planta          text not null,
  area            text not null,
  equipamento     text not null,
  tag             text,
  q01 smallint check (q01 between 1 and 4),
  q02 smallint check (q02 between 1 and 4),
  q03 smallint check (q03 between 1 and 4),
  q04 smallint check (q04 between 1 and 4),
  q05 smallint check (q05 between 1 and 4),
  q06 smallint check (q06 between 1 and 4),
  q07 smallint check (q07 between 1 and 4),
  q08 smallint check (q08 between 1 and 4),
  q09 smallint check (q09 between 1 and 4),
  q10 smallint check (q10 between 1 and 4),
  q11 smallint check (q11 between 1 and 4),
  q12 smallint check (q12 between 1 and 4),
  q13 smallint check (q13 between 1 and 4),
  respostas_texto jsonb,                       -- texto completo de cada resposta
  criado_em       timestamptz not null default now()
);

create index if not exists auditorias_conclusao_idx on auditorias (conclusao desc);

-- ---------------------------------------------------------------------
-- Resultado calculado — ÚNICO lugar onde a regra de aprovação vive.
--   Critério 1: pontos >= 85% de 52 (ou seja, 45 pontos ou mais)
--   Critério 2: itens críticos (q08 = pergunta 12 do Forms e
--               q12 = pergunta 16 do Forms) com nota >= 3
-- Resposta em branco conta 0 ponto e reprova o item crítico.
-- ---------------------------------------------------------------------
create or replace view auditorias_resultado
with (security_invoker = true) as
select
  a.*,
  coalesce(nullif(trim(a.nome), ''),
           nullif(nullif(trim(a.email), ''), 'anonymous'),
           'Não identificado')                                   as auditor,
  c.pontos,
  52                                                             as pontos_max,
  round(c.pontos * 100.0 / 52, 1)                                as percentual,
  c.pontos * 100 >= 85 * 52                                      as criterio_pontos_ok,
  coalesce(a.q08, 0) >= 3 and coalesce(a.q12, 0) >= 3            as criterio_criticos_ok,
  c.pontos * 100 >= 85 * 52
    and coalesce(a.q08, 0) >= 3 and coalesce(a.q12, 0) >= 3      as aprovado,
  case
    when c.pontos * 100 < 85 * 52
     and not (coalesce(a.q08, 0) >= 3 and coalesce(a.q12, 0) >= 3)
      then 'Pontuação abaixo de 85% e item crítico abaixo de 3'
    when c.pontos * 100 < 85 * 52
      then 'Pontuação abaixo de 85%'
    when not (coalesce(a.q08, 0) >= 3 and coalesce(a.q12, 0) >= 3)
      then 'Item crítico abaixo de 3'
  end                                                            as motivo_reprovacao
from auditorias a
cross join lateral (
  select (coalesce(a.q01,0) + coalesce(a.q02,0) + coalesce(a.q03,0) + coalesce(a.q04,0)
        + coalesce(a.q05,0) + coalesce(a.q06,0) + coalesce(a.q07,0) + coalesce(a.q08,0)
        + coalesce(a.q09,0) + coalesce(a.q10,0) + coalesce(a.q11,0) + coalesce(a.q12,0)
        + coalesce(a.q13,0))::int as pontos
) c;

-- ---------------------------------------------------------------------
-- Segurança
--   • Visitante do site (chave "anon"): só LÊ.
--   • Administrador logado (e-mail na tabela administradores): pode enviar
--     o Excel pelo botão "Atualizar base" (insere e atualiza auditorias).
--   • GitHub Action (chave service_role): grava sem passar por RLS.
-- ---------------------------------------------------------------------
create table if not exists administradores (
  email text primary key check (email = lower(email))
);
-- Cadastre quem pode atualizar a base (e crie o mesmo usuário em
-- Authentication → Users → Add user, com e-mail e senha):
--   insert into administradores values ('seu.email@empresa.com');

create or replace function eh_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from administradores
    where email = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;
revoke all on function eh_admin() from public;
grant execute on function eh_admin() to authenticated;

alter table auditorias      enable row level security;
alter table perguntas       enable row level security;
alter table administradores enable row level security;   -- sem política: ninguém lê pelo site

drop policy if exists "leitura publica" on auditorias;
create policy "leitura publica" on auditorias for select to anon, authenticated using (true);

drop policy if exists "admin insere" on auditorias;
create policy "admin insere" on auditorias for insert to authenticated with check (eh_admin());

drop policy if exists "admin atualiza" on auditorias;
create policy "admin atualiza" on auditorias for update to authenticated using (eh_admin()) with check (eh_admin());

drop policy if exists "leitura publica" on perguntas;
create policy "leitura publica" on perguntas for select to anon, authenticated using (true);

grant select on auditorias, perguntas, auditorias_resultado to anon, authenticated;
grant insert, update on auditorias to authenticated;
