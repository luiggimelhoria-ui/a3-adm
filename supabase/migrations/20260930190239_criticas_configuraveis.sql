-- Perguntas críticas (precisam de nota >= 3, senão a auditoria reprova):
-- Abertura de etiquetas no MAXIMO, Monitoramento de etiquetas abertas x
-- fechadas, Checklist de Limpeza e Checklist de Inspeção.
update public.perguntas set critica = numero in (8, 9, 10, 11);

-- A view passa a ler as críticas da tabela perguntas (coluna critica), em vez
-- de ter as colunas fixas na fórmula. Para mudar as críticas no futuro, basta
-- atualizar perguntas.critica.
drop view if exists public.auditorias_resultado;
create view public.auditorias_resultado
with (security_invoker = true) as
select
  a.*,
  coalesce(nullif(trim(a.auditor_nome), ''),
           nullif(trim(a.nome), ''),
           nullif(nullif(trim(a.email), ''), 'anonymous'),
           'Não identificado')                                   as auditor,
  c.pontos,
  52                                                             as pontos_max,
  round(c.pontos * 100.0 / 52, 1)                                as percentual,
  c.pontos * 100 >= 85 * 52                                      as criterio_pontos_ok,
  k.criticos_ok                                                  as criterio_criticos_ok,
  c.pontos * 100 >= 85 * 52 and k.criticos_ok                    as aprovado,
  case
    when c.pontos * 100 < 85 * 52 and not k.criticos_ok
      then 'Pontuação abaixo de 85% e item crítico abaixo de 3'
    when c.pontos * 100 < 85 * 52
      then 'Pontuação abaixo de 85%'
    when not k.criticos_ok
      then 'Item crítico abaixo de 3'
  end                                                            as motivo_reprovacao
from public.auditorias a
cross join lateral (
  select (coalesce(a.q01,0) + coalesce(a.q02,0) + coalesce(a.q03,0) + coalesce(a.q04,0)
        + coalesce(a.q05,0) + coalesce(a.q06,0) + coalesce(a.q07,0) + coalesce(a.q08,0)
        + coalesce(a.q09,0) + coalesce(a.q10,0) + coalesce(a.q11,0) + coalesce(a.q12,0)
        + coalesce(a.q13,0))::int as pontos
) c
cross join lateral (
  select not exists (
    select 1 from public.perguntas p
    where p.critica
      and coalesce((to_jsonb(a) ->> ('q' || lpad(p.numero::text, 2, '0')))::int, 0) < 3
  ) as criticos_ok
) k;

revoke all on public.auditorias_resultado from anon, authenticated;
grant select on public.auditorias_resultado to anon, authenticated;
