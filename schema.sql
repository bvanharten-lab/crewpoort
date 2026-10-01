-- CREW Poort — Supabase schema
-- Draai in de SQL-editor van een leeg Supabase-project. Alle autorisatie zit hier (RLS), niet in de frontend.

create extension if not exists pgcrypto;

-- ---------- Stamdata ----------
create table profiles (
  id        uuid primary key references auth.users(id) on delete cascade,
  naam      text not null,
  email     text not null unique,
  telefoon  text,
  rol       text not null check (rol in ('kantoor','leider','crew')),
  geslacht  text check (geslacht in ('M','V')),
  partner   uuid references profiles(id),
  aangemaakt timestamptz default now()
);

create table labels (
  id     text primary key,          -- '4M','4F','AR','LI','PR'
  naam     text not null,
  voor     text[] not null default '{M,V}',   -- doelgroep: 4M = {M}, Arise = {V}
  leider_m uuid references profiles(id),      -- bewegingsleider voor mannen in dit label
  leider_v uuid references profiles(id)       -- bewegingsleider voor vrouwen in dit label
);

create table rollen (
  id       text primary key,        -- 'PL','GL','FL','Spreker',...
  volgorde int not null
);

create table weekends (
  id          text primary key,
  label       text not null references labels(id),
  naam        text not null,
  datum       text not null,        -- weergave, bv '15–18 apr 2027'
  start_datum date,
  slots       jsonb not null default '{}'::jsonb,  -- {"PL":1,"GL":2,...}
  startdag      text default '',   -- bv 'Startdag 20 maart 2027'
  crewmeeting   text default '',   -- bv 'Online crewavond 6 april 2027'
  terugkomavond text default ''    -- bv 'Terugkomavond 20 mei 2027'
);

-- Wie ziet welke aanmeldingen buiten kantoor en bewegingsleiders om
create table toewijzingen (
  id      uuid primary key default gen_random_uuid(),
  "user"  uuid not null references profiles(id) on delete cascade,
  functie text not null,                     -- PL / GL / FL / Coördinator / Meekijker
  soort   text not null check (soort in ('weekend','label','rol')),
  weekend text references weekends(id) on delete cascade,
  label   text references labels(id),
  rol     text references rollen(id),
  check ((soort='weekend' and weekend is not null) or (soort='label' and label is not null) or (soort='rol' and rol is not null))
);

-- ---------- Proces ----------
create table intake (
  crew        uuid not null references profiles(id) on delete cascade,
  label       text not null references labels(id),
  ervaring    text not null check (ervaring in ('nieuw','1-3 keer','4-7 keer','8-15 keer','15+ keer')),
  vervuld     text[] not null default '{}',
  voorkeur    text[] not null default '{}',
  toelichting text default '',
  bijgewerkt  timestamptz default now(),
  primary key (crew,label)
);

create table goedkeuringen (
  crew    uuid not null references profiles(id) on delete cascade,
  label   text not null references labels(id),
  rol     text not null references rollen(id),
  status  text not null default 'voorgesteld' check (status in ('voorgesteld','goedgekeurd','afgewezen','verlopen')),
  bron    text not null default 'kantoor' check (bron in ('vervuld','voorkeur','kantoor')),
  door    uuid references profiles(id),
  datum   date default current_date,
  notitie text default '',           -- intern, nooit in export
  primary key (crew,label,rol)
);

create table beschikbaarheid (
  crew    uuid not null references profiles(id) on delete cascade,
  weekend text not null references weekends(id) on delete cascade,
  primary key (crew,weekend)
);

create table indeling (
  weekend text not null references weekends(id) on delete cascade,
  rol     text not null references rollen(id),
  plek    int  not null,
  crew    uuid not null references profiles(id) on delete cascade,
  primary key (weekend,rol,plek),
  unique (weekend,crew)              -- één plek per persoon per weekend
);

-- ---------- Hulpfuncties ----------
create or replace function mijn_rol() returns text language sql stable security definer as
$$ select rol from profiles where id = auth.uid() $$;

-- bewegingsleider van dit label voor dit crewlid (afhankelijk van geslacht)
create or replace function is_leider_van(p_label text, p_crew uuid default null) returns boolean language sql stable security definer as
$$ select exists (
     select 1 from labels l left join profiles p on p.id = p_crew
     where l.id = p_label
       and ( (p_crew is null and auth.uid() in (l.leider_m, l.leider_v))
          or (p.geslacht = 'M' and l.leider_m = auth.uid())
          or (p.geslacht = 'V' and l.leider_v = auth.uid())
          or (p.geslacht is null and auth.uid() in (l.leider_m, l.leider_v)) ) ) $$;

-- toewijzing: mag ik dit weekend zien (optioneel beperkt tot een rol)
create or replace function ziet_weekend(p_weekend text) returns boolean language sql stable security definer as
$$ select exists (
     select 1 from toewijzingen t join weekends w on w.id = p_weekend
     where t."user" = auth.uid()
       and ( (t.soort='weekend' and t.weekend = w.id)
          or (t.soort='label' and t.label = w.label)
          or (t.soort='rol' and (t.label is null or t.label = w.label)) ) ) $$;

create or replace function is_pl_van(p_weekend text) returns boolean language sql stable security definer as
$$ select exists (select 1 from toewijzingen where "user" = auth.uid() and soort='weekend' and weekend = p_weekend and functie = 'PL') $$;

create or replace function is_goedgekeurd(p_crew uuid, p_label text, p_rol text default null) returns boolean language sql stable as
$$ select exists (select 1 from goedkeuringen g where g.crew=p_crew and g.label=p_label and g.status='goedgekeurd' and (p_rol is null or g.rol=p_rol)) $$;

-- Na intake: voorstellen aanmaken (vervuld → bron 'vervuld', voorkeur-niet-vervuld → bron 'voorkeur'). Bestaande rijen blijven staan.
create or replace function stel_voor_uit_intake(p_crew uuid, p_label text) returns void language plpgsql security definer as $$
declare i intake%rowtype; r text;
begin
  select * into i from intake where crew=p_crew and label=p_label;
  if not found then return; end if;
  foreach r in array i.vervuld loop
    insert into goedkeuringen(crew,label,rol,status,bron,door) values (p_crew,p_label,r,'voorgesteld','vervuld',null)
    on conflict do nothing;
  end loop;
  foreach r in array i.voorkeur loop
    if not (r = any(i.vervuld)) then
      insert into goedkeuringen(crew,label,rol,status,bron,door) values (p_crew,p_label,r,'voorgesteld','voorkeur',p_crew)
      on conflict do nothing;
    end if;
  end loop;
end $$;

-- ---------- Harde regels (triggers) ----------
-- Label past bij geslacht van het crewlid (4M alleen M, Arise alleen V)
create or replace function past_bij_label(p_crew uuid, p_label text) returns boolean language sql stable security definer as
$$ select exists (select 1 from profiles p join labels l on l.id=p_label where p.id=p_crew and (p.geslacht is null or p.geslacht = any(l.voor))) $$;

create or replace function chk_label_doelgroep() returns trigger language plpgsql as $$
begin
  if not past_bij_label(new.crew,new.label) then raise exception 'Dit label is niet beschikbaar voor dit crewlid'; end if;
  return new;
end $$;
create trigger t_chk_intake_doelgroep before insert or update on intake for each row execute function chk_label_doelgroep();
create trigger t_chk_gk_doelgroep before insert or update on goedkeuringen for each row execute function chk_label_doelgroep();

-- Beschikbaarheid is vrij (binnen de doelgroep van het label); screening filtert pas bij het indelen.
create or replace function chk_beschikbaarheid() returns trigger language plpgsql as $$
begin
  if not past_bij_label(new.crew,(select label from weekends where id=new.weekend)) then
    raise exception 'Dit label is niet beschikbaar voor dit crewlid';
  end if;
  return new;
end $$;
create trigger t_chk_beschikbaarheid before insert or update on beschikbaarheid for each row execute function chk_beschikbaarheid();

-- Indeling alleen goedgekeurd voor (label,rol) én beschikbaar voor het weekend
create or replace function chk_indeling() returns trigger language plpgsql as $$
declare l text;
begin
  select label into l from weekends where id=new.weekend;
  if not is_goedgekeurd(new.crew,l,new.rol) then raise exception 'Niet goedgekeurd voor deze rol'; end if;
  if not exists (select 1 from beschikbaarheid b where b.crew=new.crew and b.weekend=new.weekend) then raise exception 'Niet beschikbaar voor dit weekend'; end if;
  return new;
end $$;
create trigger t_chk_indeling before insert or update on indeling for each row execute function chk_indeling();

-- Afwijzen of intrekken van een screening haalt de persoon uit de indeling voor die rol (beschikbaarheid blijft staan)
create or replace function na_goedkeuring_wijziging() returns trigger language plpgsql as $$
begin
  if new.status <> 'goedgekeurd' then
    delete from indeling i using weekends w where i.weekend=w.id and i.crew=new.crew and w.label=new.label and i.rol=new.rol;
  end if;
  return new;
end $$;
create trigger t_na_goedkeuring after update on goedkeuringen for each row execute function na_goedkeuring_wijziging();

-- ---------- RLS ----------
alter table profiles enable row level security;
alter table labels enable row level security;
alter table rollen enable row level security;
alter table weekends enable row level security;
alter table intake enable row level security;
alter table goedkeuringen enable row level security;
alter table beschikbaarheid enable row level security;
alter table indeling enable row level security;

-- Stamdata: iedereen ingelogd leest; alleen kantoor schrijft
create policy lees_labels on labels for select to authenticated using (true);
create policy lees_rollen on rollen for select to authenticated using (true);
create policy lees_weekends on weekends for select to authenticated using (true);
create policy kantoor_labels on labels for all to authenticated using (mijn_rol()='kantoor') with check (mijn_rol()='kantoor');
create policy kantoor_rollen on rollen for all to authenticated using (mijn_rol()='kantoor') with check (mijn_rol()='kantoor');
create policy kantoor_weekends on weekends for all to authenticated using (mijn_rol()='kantoor') with check (mijn_rol()='kantoor');

-- Profielen: naam + rol voor iedereen ingelogd (via view zonder contact), contact alleen kantoor of jezelf
create policy lees_eigen_profiel on profiles for select to authenticated using (id = auth.uid() or mijn_rol() in ('kantoor','leider'));
create policy kantoor_profiles on profiles for all to authenticated using (mijn_rol()='kantoor') with check (mijn_rol()='kantoor');
-- NB: de frontend leest profiles alleen met select id,naam,rol. Wil je telefoon/mail ook voor leiders afschermen: maak een view 'profiles_publiek' (id,naam,rol) en lees daaruit.

-- Intake: crew eigen rijen; leider zijn labels (lezen); kantoor alles
create policy intake_eigen on intake for all to authenticated using (crew = auth.uid()) with check (crew = auth.uid());
create policy intake_leider on intake for select to authenticated using (is_leider_van(label, crew));
create policy intake_toew on intake for select to authenticated using (exists (select 1 from weekends w where w.label = intake.label and ziet_weekend(w.id)));
create policy intake_kantoor on intake for all to authenticated using (mijn_rol()='kantoor') with check (mijn_rol()='kantoor');

-- Goedkeuringen: crew ziet eigen; leider ziet + beoordeelt zijn labels; kantoor leest alles en mag alleen voorstellen
create policy gk_eigen on goedkeuringen for select to authenticated using (crew = auth.uid());
create policy gk_leider_lees on goedkeuringen for select to authenticated using (is_leider_van(label, crew));
create policy gk_leider_update on goedkeuringen for update to authenticated using (is_leider_van(label, crew)) with check (is_leider_van(label, crew));
create policy gk_toew on goedkeuringen for select to authenticated using (exists (select 1 from weekends w where w.label = goedkeuringen.label and ziet_weekend(w.id)));
create policy gk_kantoor_lees on goedkeuringen for select to authenticated using (mijn_rol()='kantoor');
create policy gk_kantoor_voorstel on goedkeuringen for insert to authenticated with check (mijn_rol()='kantoor' and status='voorgesteld');

-- Beschikbaarheid: crew eigen; leider/kantoor lezen; kantoor mag corrigeren
create policy besch_eigen on beschikbaarheid for all to authenticated using (crew = auth.uid()) with check (crew = auth.uid());
create policy besch_leider on beschikbaarheid for select to authenticated using (exists (select 1 from weekends w where w.id=weekend and is_leider_van(w.label)));
create policy besch_toew on beschikbaarheid for select to authenticated using (ziet_weekend(weekend));
create policy besch_kantoor on beschikbaarheid for all to authenticated using (mijn_rol()='kantoor') with check (mijn_rol()='kantoor');

-- Indeling: leider zijn labels; kantoor alles; crew ziet eigen indeling
create policy ind_leider on indeling for all to authenticated using (exists (select 1 from weekends w where w.id=weekend and is_leider_van(w.label))) with check (exists (select 1 from weekends w where w.id=weekend and is_leider_van(w.label)));
create policy ind_kantoor on indeling for all to authenticated using (mijn_rol()='kantoor') with check (mijn_rol()='kantoor');
create policy ind_eigen on indeling for select to authenticated using (crew = auth.uid());
create policy ind_toew_lees on indeling for select to authenticated using (ziet_weekend(weekend));
create policy ind_pl on indeling for all to authenticated using (is_pl_van(weekend)) with check (is_pl_van(weekend));

-- Toewijzingen: kantoor beheert, iedereen ziet zijn eigen
alter table toewijzingen enable row level security;
create policy tw_eigen on toewijzingen for select to authenticated using ("user" = auth.uid());
create policy tw_kantoor on toewijzingen for all to authenticated using (mijn_rol()='kantoor') with check (mijn_rol()='kantoor');
-- leiders mogen namen zien van iedereen (nodig voor screening); crew met toewijzing ook
create policy lees_profiel_toew on profiles for select to authenticated using (exists (select 1 from toewijzingen where "user" = auth.uid()));

-- ---------- Exportview (geen contact, geen notities, geen afgewezen) ----------
create or replace view export_weekend as
select w.id as weekend, w.label, w.naam as weekend_naam, w.datum,
       p.naam,
       coalesce(array_to_string(i.vervuld, ', '),'') as vervulde_functies,
       (select string_agg(g.rol, ', ' order by r.volgorde) from goedkeuringen g join rollen r on r.id=g.rol where g.crew=p.id and g.label=w.label and g.status='goedgekeurd') as goedgekeurde_functies,
       coalesce(i.ervaring,'') as ervaring,
       (select count(*) from indeling x where x.crew=p.id) as aantal_keer_gekozen,
       (select string_agg(x.rol||' '||x.plek, ', ') from indeling x where x.crew=p.id and x.weekend=w.id) as ingedeeld_als
from weekends w
join beschikbaarheid b on b.weekend=w.id
join profiles p on p.id=b.crew
left join intake i on i.crew=p.id and i.label=w.label
where is_goedgekeurd(p.id, w.label);   -- alleen gescreende crew; niet-gescreende beschikbaarheid blijft intern

-- ---------- Profiel automatisch koppelen bij eerste login ----------
-- Kantoor zet vooraf een rij in profiles met het mailadres en id = gen_random_uuid()? Nee: id moet auth.uid zijn.
-- Werkwijze: kantoor voegt gebruikers toe via Supabase Auth (invite by email) en zet daarna de profiles-rij.
-- Deze trigger vult profiles aan zodra een uitgenodigde gebruiker inlogt en er al een 'pending' rij op mail bestaat.
create table profiles_pending (email text primary key, naam text not null, rol text not null check (rol in ('kantoor','leider','crew')), geslacht text, telefoon text);
alter table profiles_pending enable row level security;
create policy pending_kantoor on profiles_pending for all to authenticated using (mijn_rol()='kantoor') with check (mijn_rol()='kantoor');

create or replace function koppel_profiel() returns trigger language plpgsql security definer as $$
declare p profiles_pending%rowtype;
begin
  select * into p from profiles_pending where lower(email)=lower(new.email);
  if found then
    insert into profiles(id,naam,email,telefoon,rol,geslacht) values (new.id,p.naam,new.email,p.telefoon,p.rol,p.geslacht) on conflict do nothing;
    delete from profiles_pending where lower(email)=lower(new.email);
  end if;
  return new;
end $$;
create trigger t_koppel_profiel after insert on auth.users for each row execute function koppel_profiel();

-- ---------- Basisvulling ----------
insert into rollen(id,volgorde) values ('PL',1),('GL',2),('FL',3),('Spreker',4),('Route',5),('Routeleider',6),('Facilitair',7),('EHBO',8),('Coach',9),('Foto/video',10);
insert into labels(id,naam,voor) values ('4M','4M','{M}'),('4F','4Family','{M,V}'),('AR','Arise','{V}'),('LI','LIFE','{M,V}'),('PR','Promo','{M,V}');
-- bewegingsleiders koppelen zodra de profielen bestaan (per geslacht):
-- update labels set leider_m=(select id from profiles where email='wouter@...') where id in ('4M','4F');
-- update labels set leider_v=(select id from profiles where email='nadine@...') where id in ('AR','4F');
-- update labels set leider_m=(select id from profiles where email='auke@...'), leider_v=(select id from profiles where email='auke@...') where id='LI';
--
-- toewijzingen (voorbeeld; vul de mailadressen in):
-- EHBO-coördinator 4M + LIFE:
-- insert into toewijzingen("user",functie,soort,label,rol) select id,'Coördinator','rol',l,'EHBO' from profiles, unnest(array['4M','LI']) l where email='...';
-- EHBO-coördinator Arise + 4Family:
-- insert into toewijzingen("user",functie,soort,label,rol) select id,'Coördinator','rol',l,'EHBO' from profiles, unnest(array['AR','4F']) l where email='...';
-- Foto-coördinator alle labels:
-- insert into toewijzingen("user",functie,soort,label,rol) select id,'Coördinator','rol',null,'Foto/video' from profiles where email='...';
-- PL van een weekend:
-- insert into toewijzingen("user",functie,soort,weekend) select id,'PL','weekend','kw-schotland' from profiles where email='...';
