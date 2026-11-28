-- Controle de Abastecimento GLP
-- Execute no Supabase SQL Editor do projeto autorizado.
-- Não inclui credenciais nem dados pessoais dos colaboradores.

create or replace function public.usuario_e_analista()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'analista'
  );
$$;

revoke all on function public.usuario_e_analista() from public;
grant execute on function public.usuario_e_analista() to authenticated;

create table if not exists public.colaboradores (
  matricula text primary key,
  nome text not null,
  equipe text not null check (equipe in ('A','B','C','D')),
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create table if not exists public.maquinas (
  id uuid primary key default gen_random_uuid(),
  numero text not null,
  origem text not null check (origem in ('Operação','Outros locais')),
  ativo boolean not null default true,
  criado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  unique (numero, origem)
);

create table if not exists public.alertas_maquinas (
  chave text primary key,
  status text not null default 'Pendente'
    check (status in ('Pendente','Em verificação','Justificado','Inconsistência confirmada')),
  justificativa text,
  atualizado_por uuid references auth.users(id) on delete set null,
  atualizado_em timestamptz not null default now()
);

alter table public.colaboradores enable row level security;
alter table public.maquinas enable row level security;
alter table public.alertas_maquinas enable row level security;

drop policy if exists "colaboradores leitura autenticada" on public.colaboradores;
create policy "colaboradores leitura autenticada"
on public.colaboradores for select to authenticated
using (true);

drop policy if exists "colaboradores gestao analista" on public.colaboradores;
create policy "colaboradores gestao analista"
on public.colaboradores for all to authenticated
using (public.usuario_e_analista())
with check (public.usuario_e_analista());

drop policy if exists "maquinas leitura autenticada" on public.maquinas;
create policy "maquinas leitura autenticada"
on public.maquinas for select to authenticated
using (true);

drop policy if exists "maquinas gestao analista" on public.maquinas;
create policy "maquinas gestao analista"
on public.maquinas for all to authenticated
using (public.usuario_e_analista())
with check (public.usuario_e_analista());

drop policy if exists "alertas leitura analista" on public.alertas_maquinas;
create policy "alertas leitura analista"
on public.alertas_maquinas for select to authenticated
using (public.usuario_e_analista());

drop policy if exists "alertas gestao analista" on public.alertas_maquinas;
create policy "alertas gestao analista"
on public.alertas_maquinas for all to authenticated
using (public.usuario_e_analista())
with check (public.usuario_e_analista());

grant select on public.colaboradores, public.maquinas to authenticated;
grant insert, update, delete on public.colaboradores, public.maquinas to authenticated;
grant select, insert, update, delete on public.alertas_maquinas to authenticated;

-- Os registros de colaboradores serão inseridos separadamente após validar o schema.
