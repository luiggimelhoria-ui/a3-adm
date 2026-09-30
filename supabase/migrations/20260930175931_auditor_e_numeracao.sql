-- Campo "nome do auditor" no Forms: coluna própria, usada como auditor no painel.
alter table public.auditorias add column if not exists auditor_nome text;

-- Com o campo novo, as perguntas do checklist passam a ser P6..P18 no Forms
-- (críticas: P13 e P17). Dois passos por causa do unique em numero_forms.
update public.perguntas set numero_forms = numero + 100;
update public.perguntas set numero_forms = numero + 5;

-- Regra de aprovação (inalterada): pontos >= 85% de 52 (45+) e as duas
-- perguntas críticas (q08 = P13 "Abertura de etiquetas no MAXIMO",
-- q12 = P17 "Limpeza como momento de inspeção") com nota >= 3.
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
from public.auditorias a
cross join lateral (
  select (coalesce(a.q01,0) + coalesce(a.q02,0) + coalesce(a.q03,0) + coalesce(a.q04,0)
        + coalesce(a.q05,0) + coalesce(a.q06,0) + coalesce(a.q07,0) + coalesce(a.q08,0)
        + coalesce(a.q09,0) + coalesce(a.q10,0) + coalesce(a.q11,0) + coalesce(a.q12,0)
        + coalesce(a.q13,0))::int as pontos
) c;

revoke all on public.auditorias_resultado from anon, authenticated;
grant select on public.auditorias_resultado to anon, authenticated;
