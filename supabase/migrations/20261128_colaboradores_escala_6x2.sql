-- Cadastro inicial de colaboradores e ciclo 6x2 por equipe.
-- Executar após 20261127_cadastros_operacionais.sql.

create table if not exists public.escala_equipes (
  equipe text primary key check (equipe in ('A','B','C','D')),
  data_referencia date not null,
  turno_inicial text not null check (turno_inicial in ('Manhã','Tarde','Noite','Folga')),
  atualizado_em timestamptz not null default now()
);

alter table public.escala_equipes enable row level security;

drop policy if exists "escala leitura autenticada" on public.escala_equipes;
create policy "escala leitura autenticada"
on public.escala_equipes for select to authenticated
using (true);

drop policy if exists "escala gestao analista" on public.escala_equipes;
create policy "escala gestao analista"
on public.escala_equipes for all to authenticated
using (public.usuario_e_analista())
with check (public.usuario_e_analista());

grant select on public.escala_equipes to authenticated;
grant insert, update, delete on public.escala_equipes to authenticated;

insert into public.colaboradores (matricula,nome,equipe,ativo)
values
 ('38001697','JEAN CARLOS BRAZ PEREIRA','A',true),
 ('38001575','MARCELO ANTONIO LEAO','B',true),
 ('38001641','LUIZ FABIANO DE OLIVEIRA ROCHA','B',true),
 ('38001782','CARLOS ENRIQUE TINEO RAMOS','C',true),
 ('38001572','WESLEI APARECIDO DOS SANTOS','C',true),
 ('38001634','JHOVANNYS JESUS NIETO GARCIA','D',true),
 ('38001621','JOAO VITOR DA SILVA','D',true)
on conflict (matricula) do update
set nome=excluded.nome, equipe=excluded.equipe, ativo=excluded.ativo,
    atualizado_em=now();

insert into public.escala_equipes (equipe,data_referencia,turno_inicial)
values
 ('A','2026-11-26','Folga'),
 ('B','2026-11-26','Manhã'),
 ('C','2026-11-26','Tarde'),
 ('D','2026-11-26','Noite')
on conflict (equipe) do update
set data_referencia=excluded.data_referencia,
    turno_inicial=excluded.turno_inicial,
    atualizado_em=now();

create or replace function public.turno_da_equipe(p_equipe text, p_data date)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with base as (
    select data_referencia, turno_inicial
    from public.escala_equipes
    where equipe = p_equipe
  ),
  ordem as (
    select case turno_inicial
      when 'Manhã' then 0
      when 'Tarde' then 1
      when 'Noite' then 2
      when 'Folga' then 3
    end as inicio,
    (p_data - data_referencia) as dias
    from base
  )
  select case mod(((inicio + floor(dias::numeric / 2)::integer) % 4 + 4) % 4, 4)
    when 0 then 'Manhã'
    when 1 then 'Tarde'
    when 2 then 'Noite'
    else 'Folga'
  end
  from ordem;
$$;

revoke all on function public.turno_da_equipe(text,date) from public;
grant execute on function public.turno_da_equipe(text,date) to authenticated;
