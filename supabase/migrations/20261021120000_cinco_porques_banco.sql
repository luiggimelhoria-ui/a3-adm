-- Painel 5 Porquês vira banco de informações: sai o acompanhamento de ações
-- (status, responsável, prazo) e a avaliação do KPI impactado. Na reunião, o
-- grupo só prioriza a ação sugerida e marca se ela já foi lançada no controle
-- de ações da área, onde ela é acompanhada.
-- As colunas antigas (kpi, condicao, status, responsavel, prazo) e a função
-- avaliar_anomalia ficam no banco para não perder o que já foi registrado,
-- mas o painel não as usa mais.

alter table public.anomalias_avaliacao
  add column if not exists prioridade       text check (prioridade in ('Alta','Média','Baixa')),
  add column if not exists enviada_controle boolean not null default false,
  add column if not exists ref_controle     text;

-- Mesma view, com as colunas novas no fim (create or replace só permite acrescentar)
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
  v.avaliado_em,
  v.prioridade,
  coalesce(v.enviada_controle, false)                                  as enviada_controle,
  v.ref_controle
from public.anomalias a
left join public.anomalias_avaliacao v on v.resposta_id = a.resposta_id;

grant select on public.anomalias_painel to anon, authenticated;

-- Registro da reunião: prioridade da ação sugerida, se já foi lançada no
-- controle de ações (e o número lá) e observações. Marca a anomalia como discutida.
create or replace function public.registrar_reuniao(
  p_resposta_id text, p_prioridade text, p_enviada_controle boolean,
  p_ref_controle text, p_observacao text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from anomalias where resposta_id = p_resposta_id) then
    raise exception 'anomalia % não encontrada', p_resposta_id;
  end if;

  insert into anomalias_avaliacao (resposta_id, prioridade, enviada_controle, ref_controle, observacao, avaliado_em)
  values (p_resposta_id,
          nullif(p_prioridade, ''),
          coalesce(p_enviada_controle, false),
          left(nullif(trim(p_ref_controle), ''), 120),
          left(nullif(trim(p_observacao), ''), 2000),
          now())
  on conflict (resposta_id) do update set
    prioridade = excluded.prioridade, enviada_controle = excluded.enviada_controle,
    ref_controle = excluded.ref_controle, observacao = excluded.observacao, avaliado_em = now();
end;
$$;

grant execute on function public.registrar_reuniao(text, text, boolean, text, text) to anon, authenticated;
notify pgrst, 'reload schema';
