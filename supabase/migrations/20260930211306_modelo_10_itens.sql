-- Novo modelo do Forms: 10 perguntas (P6..P15), 4 pontos cada = 40 pontos.
-- Críticas: Abertura de etiquetas no MAXIMO, Monitoramento de etiquetas
-- abertas x fechadas e Checklist de Limpeza e Inspeção (nota >= 3).
-- Aprovação: pontos >= 85% do máximo (34 de 40) e todas as críticas >= 3.

-- 1) As respostas no formato antigo (13 perguntas) não são compatíveis:
--    vão para a cópia de segurança e saem da base.
insert into public.auditorias_backup (motivo, dados)
select 'modelo antigo (13 perguntas)', to_jsonb(a) from public.auditorias a;
delete from public.auditorias where true;

-- 2) Perguntas do novo modelo
delete from public.perguntas where numero > 10;
update public.perguntas p set titulo = v.titulo, critica = v.critica, numero_forms = v.numero + 5
from (values
  ( 1, 'Treinamento da operação',                                    false),
  ( 2, 'Recursos da estação',                                        false),
  ( 3, 'Donos do equipamento',                                       false),
  ( 4, 'Mapa de contaminação',                                       false),
  ( 5, 'Tratamento das fontes de contaminação',                      false),
  ( 6, 'Grande Limpeza e restauração com registros antes e depois',  false),
  ( 7, 'Abertura de etiquetas no MAXIMO',                            true),
  ( 8, 'Monitoramento de etiquetas abertas x fechadas',              true),
  ( 9, 'Checklist de Limpeza e Inspeção',                            true),
  (10, 'Checklist de Lubrificação',                                  false)
) as v(numero, titulo, critica)
where p.numero = v.numero;

-- 3) Colunas: saem q11..q13
drop view if exists public.auditorias_resultado;
alter table public.auditorias drop column if exists q11, drop column if exists q12, drop column if exists q13;

-- 4) Resultado genérico: soma e máximo vêm da tabela perguntas
create view public.auditorias_resultado
with (security_invoker = true) as
select
  a.*,
  coalesce(nullif(trim(a.auditor_nome), ''),
           nullif(trim(a.nome), ''),
           nullif(nullif(trim(a.email), ''), 'anonymous'),
           'Não identificado')                                   as auditor,
  c.pontos,
  c.pontos_max,
  round(c.pontos * 100.0 / nullif(c.pontos_max, 0), 1)           as percentual,
  c.pontos * 100 >= 85 * c.pontos_max                            as criterio_pontos_ok,
  c.criticos_ok                                                  as criterio_criticos_ok,
  c.pontos * 100 >= 85 * c.pontos_max and c.criticos_ok          as aprovado,
  case
    when c.pontos * 100 < 85 * c.pontos_max and not c.criticos_ok
      then 'Pontuação abaixo de 85% e item crítico abaixo de 3'
    when c.pontos * 100 < 85 * c.pontos_max
      then 'Pontuação abaixo de 85%'
    when not c.criticos_ok
      then 'Item crítico abaixo de 3'
  end                                                            as motivo_reprovacao
from public.auditorias a
cross join lateral (
  select coalesce(sum(n.nota), 0)::int                           as pontos,
         (4 * count(*))::int                                     as pontos_max,
         bool_and(not n.critica or n.nota >= 3)                  as criticos_ok
  from (
    select p.critica,
           coalesce((to_jsonb(a) ->> ('q' || lpad(p.numero::text, 2, '0')))::int, 0) as nota
    from public.perguntas p
  ) n
) c;

revoke all on public.auditorias_resultado from anon, authenticated;
grant select on public.auditorias_resultado to anon, authenticated;

-- 5) Substituir/apagar base com as colunas do novo modelo
create or replace function public.substituir_auditorias(linhas jsonb)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  n integer;
begin
  if linhas is null or jsonb_typeof(linhas) <> 'array' then
    raise exception 'linhas deve ser uma lista';
  end if;

  insert into auditorias_backup (motivo, dados)
  select case when jsonb_array_length(linhas) = 0 then 'apagar tudo' else 'substituir base' end, to_jsonb(a)
  from auditorias a;

  delete from auditorias where true;

  insert into auditorias (resposta_id, inicio, conclusao, email, nome, auditor_nome, planta, area, equipamento, tag,
                          q01, q02, q03, q04, q05, q06, q07, q08, q09, q10, respostas_texto)
  select resposta_id, inicio, conclusao, email, nome, auditor_nome, planta, area, equipamento, tag,
         q01, q02, q03, q04, q05, q06, q07, q08, q09, q10, respostas_texto
  from jsonb_populate_recordset(null::auditorias, linhas);
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke all on function public.substituir_auditorias(jsonb) from public;
grant execute on function public.substituir_auditorias(jsonb) to anon, authenticated;
