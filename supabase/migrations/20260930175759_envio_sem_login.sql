-- "Atualizar base" sem login (decisão do dono do painel): qualquer visitante
-- pode incluir e atualizar auditorias pela chave pública. Apagar continua
-- proibido, e a tabela de perguntas segue só leitura.
drop policy if exists "admin insere" on public.auditorias;
drop policy if exists "admin atualiza" on public.auditorias;
drop function if exists privado.eh_admin();
drop schema if exists privado;
drop table if exists public.administradores;

create policy "envio publico insere" on public.auditorias for insert to anon, authenticated with check (true);
create policy "envio publico atualiza" on public.auditorias for update to anon, authenticated using (true) with check (true);

revoke delete, truncate on public.auditorias from anon, authenticated;
grant select, insert, update on public.auditorias to anon, authenticated;
revoke insert, update, delete, truncate on public.perguntas from anon, authenticated;
