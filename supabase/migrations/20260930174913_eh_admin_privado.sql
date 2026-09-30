-- Tira a função eh_admin() da API pública (/rest/v1/rpc), como recomenda o
-- Security Advisor do Supabase: ela passa para o schema "privado", que não é
-- exposto, e as políticas de gravação passam a usá-la de lá.
create schema if not exists privado;
revoke all on schema privado from public, anon;
grant usage on schema privado to authenticated;

create or replace function privado.eh_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.administradores
    where email = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;
revoke all on function privado.eh_admin() from public, anon;
grant execute on function privado.eh_admin() to authenticated;

drop policy if exists "admin insere" on public.auditorias;
create policy "admin insere" on public.auditorias for insert to authenticated with check (privado.eh_admin());

drop policy if exists "admin atualiza" on public.auditorias;
create policy "admin atualiza" on public.auditorias for update to authenticated using (privado.eh_admin()) with check (privado.eh_admin());

drop function if exists public.eh_admin();
