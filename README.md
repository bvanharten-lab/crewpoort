# CREW Poort 2027

Crewplanning voor 4M, 4Family, Arise, LIFE en Promo.
Crew vult intake en beschikbaarheid in; de bewegingsleider screent per label × rol; alleen gescreend + beschikbaar komt in de keuzelijst van de projectleider; het resultaat gaat nachtelijk naar de gedeelde Google Sheet.

## Bestanden

| Bestand | Wat |
|---|---|
| `index.html` | De hele frontend. Zonder `config.js` demo-modus met verzonnen data; mét `config.js` live op Supabase. |
| `config.example.js` | Voorbeeld. Lokaal testen: kopieer naar `config.js`. Staat in `.gitignore`. |
| `.github/workflows/pages.yml` | Publiceert naar GitHub Pages en schrijft `config.js` uit repository-secrets. |
| `supabase/schema.sql` | Tabellen, triggers (harde regels), RLS (rechten), exportview. Eén keer draaien. |
| `export/sheets-export.gs` | Nachtelijke pull vanuit de gedeelde sheet. Het enige Google-stuk. |

## Live zetten — stap voor stap

### 1. Supabase (10 min)
1. supabase.com → New project, regio **West EU (Ireland)**, database-wachtwoord in de wachtwoordkluis.
2. SQL Editor → New query → plak `supabase/schema.sql` → Run. Moet zonder fouten door.
3. Authentication → Providers → Email: **Enable email provider** aan, **Confirm email** uit, **Magic link** aan.
4. Authentication → URL Configuration: Site URL = straks het Pages-adres (`https://<org>.github.io/crewpoort/`); ook bij Redirect URLs. Voor lokaal testen `http://localhost:8000` toevoegen.
5. Project Settings → API: noteer **Project URL** en **anon public key**. De service_role key gebruik je nergens.

### 2. GitHub (5 min)
1. Nieuwe repo `crewpoort` (private kan; Pages op private repo's vereist GitHub Team/Pro, anders public — de code bevat geen gegevens).
2. Upload de inhoud van deze map (niet `config.js`).
3. Settings → Secrets and variables → Actions → New repository secret:
   - `SUPABASE_URL` = Project URL
   - `SUPABASE_ANON_KEY` = anon key
4. Settings → Pages → Source: **GitHub Actions**.
5. Actions → "Deploy CREW Poort" → Run workflow (of push een commit). Na ~1 min staat de app op `https://<org>.github.io/crewpoort/`.
6. Dat adres terugzetten in Supabase als Site URL (stap 1.4).

### 3. Mensen aanmelden (kantoor)
Supabase → Table Editor → `profiles_pending`: één rij per persoon met `email`, `naam`, `rol` (`kantoor` / `leider` / `crew`), `geslacht` (`M`/`V`). Bij eerste login via de mail-link wordt het profiel automatisch gekoppeld.
Daarna in SQL Editor de bewegingsleiders koppelen, per label én geslacht (4Family: mannen Wouter, vrouwen Nadine):

```sql
update labels set leider_m=(select id from profiles where email='wouter@...') where id in ('4M','4F');
update labels set leider_v=(select id from profiles where email='nadine@...') where id in ('AR','4F');
update labels set leider_m=(select id from profiles where email='auke@...'), leider_v=(select id from profiles where email='auke@...') where id='LI';
```

Projectleiders, GL/FL en coördinatoren (EHBO per label, Foto/video alle labels) wijs je toe in de app onder **Toewijzingen** (kantoor), of met de voorbeeld-inserts onderaan `schema.sql`.

### 4. Weekenden 2027
In de app onder **Weekenden** (kantoor): naam, label, datum, startdatum, plekken per rol (`PL:1, GL:1, Spreker:2`), en de bijbehorende startdag, crewmeeting en terugkomavond. Die bijeenkomsten ziet de vrijwilliger bij het weekend; beschikbaar voor het weekend = ook voor die dagen.

### 5. Export naar de gedeelde sheet
In de gedeelde CREW-planning-sheet: Extensies → Apps Script → plak `export/sheets-export.gs`. Maak in Supabase een policy die `export_weekend` en `weekends` leesbaar maakt voor een aparte leesgebruiker (of tijdelijk voor `anon`) en vul die sleutel in. Trigger: dagelijks 03:00.

## Testen met echte input

1. Eerst jijzelf als `kantoor`, Wouter/Nadine/Auke als `leider`, en 5–10 crewleden die je persoonlijk vraagt. Niet meteen alle 900.
2. Crew: inloggen → Mijn gegevens (per beweging) → Mijn beschikbaarheid.
3. Leider: Screening → een paar goedkeuren/afwijzen → Potentieel.
4. Kantoor: Indeling van één weekend → Exportsheet → "Kopieer voor Google Sheets" en plak in een testtabblad.
5. Pas als dat klopt: `sheets-export.gs` aanzetten en de rest van de crew uitnodigen.

Vanaf stap 1 staan er echte persoonsgegevens in Supabase. Spreek af wie kantoor-toegang heeft; dat zijn de enigen die mail en telefoon zien.

## Rollen

- **crew**: ziet alleen labels voor de eigen doelgroep (4M = M, Arise = V, 4Family/LIFE/Promo = beide). Vult per label intake in (ervaring, vervulde rollen, voorkeursrollen) en beschikbaarheid per weekend.
- **leider**: screent alleen eigen labels, per geslacht (4Family-vrouwen bij Nadine, -mannen bij Wouter). Bulk alleen voor "vervuld"-voorstellen; potentieel (voorkeur, nog niet vervuld) blijft handwerk.
- **kantoor**: stelt voor, beheert weekenden, toewijzingen en profielen, screent niet.
- **toewijzing** (extra op crew): PL/GL/FL van een weekend zien de aanmeldingen van dat weekend (PL deelt in); een coördinator van een rol ziet alle aanmeldingen voor die rol binnen zijn labels. Tab **Aanmeldingen** verschijnt automatisch.

## Regels die de database afdwingt

- Intake, beschikbaarheid en screening alleen voor labels die bij het geslacht van het crewlid passen.
- Indeling alleen gescreend voor (label, rol) én beschikbaar voor dat weekend.
- Afwijzen of intrekken van een screening haalt de persoon uit de indeling voor die rol; beschikbaarheid blijft staan.
- Export bevat geen mail, telefoon, notities of afgewezen rollen, en alleen gescreende crew.
- Toewijzingen bepalen zichtbaarheid van beschikbaarheid, intake en indeling via RLS; alleen een PL-toewijzing geeft schrijfrecht op de indeling van dat weekend.

## Huisstijl per doelgroep

Mannen en de 4M/4Family-leider: Big Shoulders Display + Epilogue, rood `#DD0000`, verder zwart/wit. Vrouwen en de Arise-leider: Playfair Display + Lato, bordeaux `#6A3C3F`, goud `#A99F71`. Kantoor en LIFE: neutraal. Alles in de twee `:root[data-brand=…]`-blokken bovenaan `index.html`.

## Nog te beslissen

- Tweede screener per label bij uitval van de bewegingsleider.
- Bewaartermijn van afgewezen screenings (voorstel: één seizoen, daarna `verlopen`).
- Beheer naast Bart (voorstel: Arjen; alles staat in één repo en één Supabase-project).
