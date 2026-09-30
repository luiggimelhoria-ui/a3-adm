-- Cópia de segurança de tudo que for removido pelo painel ("Substituir toda a
-- base" ou "Apagar todas"). Guarda a linha inteira em JSON, então continua
-- funcionando mesmo que as colunas de auditorias mudem no futuro.
create table if not exists public.auditorias_backup (
  id         bigint generated always as identity primary key,
  backup_em  timestamptz not null default now(),
  motivo     text not null,
  dados      jsonb not null
);
alter table public.auditorias_backup enable row level security;   -- sem política: não é lida pelo site
revoke all on public.auditorias_backup from anon, authenticated;

-- Troca toda a base pelas linhas enviadas, numa única transação: se qualquer
-- linha for inválida, nada é apagado. Lista vazia = apagar tudo.
-- Executável pela chave pública (painel sem login, decisão do dono).
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
                          q01, q02, q03, q04, q05, q06, q07, q08, q09, q10, q11, q12, q13, respostas_texto)
  select resposta_id, inicio, conclusao, email, nome, auditor_nome, planta, area, equipamento, tag,
         q01, q02, q03, q04, q05, q06, q07, q08, q09, q10, q11, q12, q13, respostas_texto
  from jsonb_populate_recordset(null::auditorias, linhas);
  get diagnostics n = row_count;
  return n;
end;
$$;

revoke all on function public.substituir_auditorias(jsonb) from public;
grant execute on function public.substituir_auditorias(jsonb) to anon, authenticated;
