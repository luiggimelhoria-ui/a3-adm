-- =====================================================================
-- Painel 5 Porquês (Falha Zero) · relato de anomalias
-- Não tem nota nem aprovação: cada resposta do Forms é uma anomalia com a
-- investigação dos 5 porquês. Na reunião operacional, líder e operadores
-- avaliam o KPI impactado e o andamento da ação (tabela anomalias_avaliacao).
-- Leitura pela chave pública; gravação só pelas funções RPC abaixo.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Respostas do Forms (uma linha por anomalia relatada)
-- Horas em "timestamp" sem fuso: guardam a hora de parede do Excel.
-- ---------------------------------------------------------------------
create table if not exists public.anomalias (
  id                bigint generated always as identity primary key,
  resposta_id       text not null unique,       -- "ID" do Forms (evita duplicar)
  inicio            timestamp,
  conclusao         timestamp,
  email             text,
  nome              text,
  modificado_em     timestamp,
  planta            text not null,
  area              text not null,
  equipamento       text not null,              -- "Equipamento + TAG"
  turno             text,
  data_evento       date,
  executante        text,
  tipo_falha        text,
  acao_imediata     text,                       -- "O que foi feito para resolver"
  porque1           text,
  porque2           text,
  porque3           text,
  porque4           text,
  porque5           text,
  clareza           smallint check (clareza between 1 and 5),
  causa_raiz        text,                       -- categorias do Forms, separadas por ";"
  causa_outra       text,                       -- "Informe a causa, caso marque Outra causa"
  comentario_causa  text,
  acoes_sugeridas   text,
  kpi_forms         text,                       -- coluna opcional "KPI impactado", se for criada no Forms
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now()
);
create index if not exists anomalias_data_idx on public.anomalias (data_evento desc);

-- ---------------------------------------------------------------------
-- Avaliação feita na reunião operacional (fica separada para não ser
-- sobrescrita quando a base do Forms é atualizada)
-- ---------------------------------------------------------------------
create table if not exists public.anomalias_avaliacao (
  resposta_id  text primary key,
  kpi          text,
  condicao     text check (condicao in ('Acima da tolerância','Abaixo da tolerância','Dentro da tolerância','Sem impacto em KPI')),
  status       text not null default 'Nova' check (status in ('Nova','Em análise','Ação em andamento','Concluída')),
  responsavel  text,
  prazo        date,
  observacao   text,
  avaliado_em  timestamptz not null default now()
);

-- Cópia de segurança de tudo que sair pelo painel ("Substituir" ou "Apagar tudo")
create table if not exists public.anomalias_backup (
  id         bigint generated always as identity primary key,
  backup_em  timestamptz not null default now(),
  motivo     text not null,
  dados      jsonb not null
);

-- ---------------------------------------------------------------------
-- View lida pelo painel: anomalia + avaliação + campos derivados
-- ---------------------------------------------------------------------
create or replace view public.anomalias_painel
with (security_invoker = true) as
select
  a.*,
  coalesce(nullif(trim(a.executante), ''),
           nullif(trim(a.nome), ''),
           nullif(nullif(trim(a.email), ''), 'anonymous'),
           'Não identificado')                                         as autor,
  coalesce(a.data_evento, a.conclusao::date)                           as data_ref,
  array(select trim(c) from unnest(string_to_array(coalesce(a.causa_raiz, ''), ';')) c
        where trim(c) <> '')                                           as causas,
  (select count(*) from unnest(array[a.porque1, a.porque2, a.porque3, a.porque4, a.porque5]) p
    where nullif(trim(p), '') is not null)::int                        as porques,
  coalesce(nullif(trim(v.kpi), ''), nullif(trim(a.kpi_forms), ''))     as kpi,
  v.condicao,
  coalesce(v.status, 'Nova')                                           as status,
  v.responsavel,
  v.prazo,
  v.observacao,
  v.avaliado_em
from public.anomalias a
left join public.anomalias_avaliacao v on v.resposta_id = a.resposta_id;

-- ---------------------------------------------------------------------
-- Segurança: o site só lê; grava pelas funções security definer
-- ---------------------------------------------------------------------
alter table public.anomalias           enable row level security;
alter table public.anomalias_avaliacao enable row level security;
alter table public.anomalias_backup    enable row level security;   -- sem política: não é lida pelo site

drop policy if exists "leitura publica" on public.anomalias;
create policy "leitura publica" on public.anomalias for select to anon, authenticated using (true);
drop policy if exists "leitura publica" on public.anomalias_avaliacao;
create policy "leitura publica" on public.anomalias_avaliacao for select to anon, authenticated using (true);

revoke all on public.anomalias, public.anomalias_avaliacao, public.anomalias_backup from anon, authenticated;
grant select on public.anomalias, public.anomalias_avaliacao, public.anomalias_painel to anon, authenticated;

-- Adicionar e atualizar (upsert pelo ID do Forms). Não mexe nas avaliações.
create or replace function public.gravar_anomalias(linhas jsonb)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  n integer;
begin
  if linhas is null or jsonb_typeof(linhas) <> 'array' then
    raise exception 'linhas deve ser uma lista';
  end if;

  insert into anomalias (resposta_id, inicio, conclusao, email, nome, modificado_em, planta, area, equipamento,
                         turno, data_evento, executante, tipo_falha, acao_imediata,
                         porque1, porque2, porque3, porque4, porque5, clareza,
                         causa_raiz, causa_outra, comentario_causa, acoes_sugeridas, kpi_forms)
  select resposta_id, inicio, conclusao, email, nome, modificado_em, planta, area, equipamento,
         turno, data_evento, executante, tipo_falha, acao_imediata,
         porque1, porque2, porque3, porque4, porque5, clareza,
         causa_raiz, causa_outra, comentario_causa, acoes_sugeridas, kpi_forms
  from jsonb_populate_recordset(null::anomalias, linhas)
  on conflict (resposta_id) do update set
    inicio = excluded.inicio, conclusao = excluded.conclusao, email = excluded.email, nome = excluded.nome,
    modificado_em = excluded.modificado_em, planta = excluded.planta, area = excluded.area,
    equipamento = excluded.equipamento, turno = excluded.turno, data_evento = excluded.data_evento,
    executante = excluded.executante, tipo_falha = excluded.tipo_falha, acao_imediata = excluded.acao_imediata,
    porque1 = excluded.porque1, porque2 = excluded.porque2, porque3 = excluded.porque3,
    porque4 = excluded.porque4, porque5 = excluded.porque5, clareza = excluded.clareza,
    causa_raiz = excluded.causa_raiz, causa_outra = excluded.causa_outra,
    comentario_causa = excluded.comentario_causa, acoes_sugeridas = excluded.acoes_sugeridas,
    kpi_forms = excluded.kpi_forms, atualizado_em = now();
  get diagnostics n = row_count;
  return n;
end;
$$;

-- Troca toda a base pelas linhas enviadas, numa transação só (se alguma
-- linha for inválida, nada é apagado). Lista vazia = apagar tudo, inclusive
-- as avaliações. Ao substituir, as avaliações ficam: o ID do Forms não muda.
create or replace function public.substituir_anomalias(linhas jsonb)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  apagar boolean;
begin
  if linhas is null or jsonb_typeof(linhas) <> 'array' then
    raise exception 'linhas deve ser uma lista';
  end if;
  apagar := jsonb_array_length(linhas) = 0;

  insert into anomalias_backup (motivo, dados)
  select case when apagar then 'apagar tudo' else 'substituir base' end, to_jsonb(a) from anomalias a;
  delete from anomalias where true;

  if apagar then
    insert into anomalias_backup (motivo, dados)
    select 'apagar tudo (avaliação)', to_jsonb(v) from anomalias_avaliacao v;
    delete from anomalias_avaliacao where true;
    return 0;
  end if;

  return gravar_anomalias(linhas);
end;
$$;

-- Avaliação da reunião: KPI impactado, condição, status, responsável, prazo
create or replace function public.avaliar_anomalia(
  p_resposta_id text, p_kpi text, p_condicao text, p_status text,
  p_responsavel text, p_prazo date, p_observacao text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from anomalias where resposta_id = p_resposta_id) then
    raise exception 'anomalia % não encontrada', p_resposta_id;
  end if;

  insert into anomalias_avaliacao (resposta_id, kpi, condicao, status, responsavel, prazo, observacao, avaliado_em)
  values (p_resposta_id,
          left(nullif(trim(p_kpi), ''), 120),
          nullif(p_condicao, ''),
          coalesce(nullif(p_status, ''), 'Nova'),
          left(nullif(trim(p_responsavel), ''), 120),
          p_prazo,
          left(nullif(trim(p_observacao), ''), 2000),
          now())
  on conflict (resposta_id) do update set
    kpi = excluded.kpi, condicao = excluded.condicao, status = excluded.status,
    responsavel = excluded.responsavel, prazo = excluded.prazo,
    observacao = excluded.observacao, avaliado_em = now();
end;
$$;

revoke all on function public.gravar_anomalias(jsonb) from public;
revoke all on function public.substituir_anomalias(jsonb) from public;
revoke all on function public.avaliar_anomalia(text, text, text, text, text, date, text) from public;
grant execute on function public.gravar_anomalias(jsonb) to anon, authenticated;
grant execute on function public.substituir_anomalias(jsonb) to anon, authenticated;
grant execute on function public.avaliar_anomalia(text, text, text, text, text, date, text) to anon, authenticated;
