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
| `supabase/functions/export-sheet` | Edge Function: indeling → tabblad CREW + ICE van de productiesheet (zie docs/export-productiesheet.md). |
| `supabase/functions/weekly-digest` | Edge Function: maandagmail aan bewegingsleiders met open screenings en voortgang (zie docs/weekoverzicht.md). |
| `export/sheets-export.gs` | Oude nachtelijke pull naar de gedeelde sheet; niet meer nodig nu de PL zelf exporteert. |

## Live zetten — stap voor stap

### 1. Supabase (10 min)
1. supabase.com → New project, regio **West EU (Ireland)**, database-wachtwoord in de wachtwoordkluis.
2. SQL Editor → New query → plak `supabase/schema.sql` → Run. Moet zonder fouten door.
3. Authentication → Providers → Email: **Enable email provider** aan, **Confirm email** uit, **Magic link** aan.
4. Authentication → URL Configuration: Site URL = straks het Pages-adres (`https://<org>.github.io/crewpoort/`); ook bij Redirect URLs. Voor lokaal testen `http://localhost:8000` toevoegen.
5. Project Settings → API Keys: noteer **Project URL** (vorm: `https://<ref>.supabase.co`, zónder pad erachter — niet de dashboard-URL) en de **publishable/anon key**. De secret/service_role key gebruik je nergens. Fout in de URL geeft in de app "Invalid path specified in request URL".

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
Supabase → Table Editor → de **bestaande** tabel `profiles_pending` (geen nieuwe tabel maken; de koppeling leest alleen deze). Eén rij per persoon: `email` (kleine letters), `naam`, `rol` = precies `kantoor`, `leider` of `crew` (een projectleider van een weekend is `crew`; zijn PL-rol wijs je toe onder Toewijzingen), `geslacht` = `M` of `V`. Bij eerste login via de mail-link wordt het profiel automatisch gekoppeld.
Daarna de bewegingsleiders koppelen, per label én geslacht (4Family: mannen Wouter, vrouwen Nadine): in de app onder **Crewbeheer → Bewegingsleiders** (zodra ze ingelogd zijn), of in SQL Editor:

```sql
update labels set leider_m=(select id from profiles where email='wouter@...') where id in ('4M','4F');
update labels set leider_v=(select id from profiles where email='nadine@...') where id in ('AR','4F');
update labels set leider_m=(select id from profiles where email='nadine@...') where id='AR'; -- mannen bij Arise screent Nadine ook
update labels set leider_m=(select id from profiles where email='auke@...'), leider_v=(select id from profiles where email='auke@...') where id='LI';
```

Projectleiders, GL/FL en coördinatoren (EHBO per label, Foto/video alle labels) wijs je toe in de app onder **Toewijzingen** (kantoor), of met de voorbeeld-inserts onderaan `schema.sql`.

### 4. Weekenden 2027
In de app onder **Weekenden** (kantoor): naam, label, datum, startdatum, plekken per rol (`PL:1, GL:1, Spreker:2`), en de bijbehorende startdag, crewmeeting en terugkomavond. Die bijeenkomsten ziet de vrijwilliger bij het weekend; beschikbaar voor het weekend = ook voor die dagen. **Crew: voor wie** beperkt per weekend wie het ziet en ingedeeld kan worden (standaard volgt het label; 4Family: vrouwen alleen bij Couples, Vader-dochter, Moeder-kind en Moeder-zoon, mannen overal).

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

- **crew**: ziet alleen labels voor de eigen doelgroep (4M = M, Arise = V, 4Family/LIFE/Promo = beide). Gastlabel (`labels.gast`, Arise = M): mannen krijgen bij stap 3 de vragen of ze eerder mee waren met Arise en of ze weer mee willen; eerder mee → Arise-weekenden direct zichtbaar, anders pas na goedkeuring van een rol door de Arise-leider. Vult per label intake in (ervaring, vervulde rollen, voorkeursrollen) en beschikbaarheid per weekend.
- **leider**: screent alleen eigen labels, per geslacht (4Family-vrouwen bij Nadine, -mannen bij Wouter). Vervulde functies zijn automatisch goedgekeurd (alleen afkeuren mogelijk, lijst "Ervaren crew per functie"); gewenste-niet-vervulde rollen (Potentieel) beoordeelt de leider. Kiesbaar voor de PL = goedgekeurd én gewenst voor 2027. Heeft de leider een `geslacht`, dan krijgt hij ook Mijn gegevens en Mijn beschikbaarheid en kan hij zelf mee als crew; zijn eigen rollen screent hij dan zelf. Bulk alleen voor "vervuld"-voorstellen; potentieel (voorkeur, nog niet vervuld) blijft handwerk.
- **kantoor**: stelt voor, beheert weekenden, toewijzingen, profielen en bewegingsleiders; kan als fallback ook screenen.
- **toewijzing** (extra op crew): PL/GL/FL van een weekend zien de aanmeldingen van dat weekend; een coördinator van een rol ziet alle aanmeldingen voor die rol binnen zijn labels. Tab **Aanmeldingen** verschijnt automatisch. Indelen: PL alle rollen behalve EHBO en Foto/video; GL alleen Spreker; FL alleen Facilitair; coördinator alleen zijn eigen rol; bewegingsleider en kantoor alles. Aantal plekken per rol: PL en kantoor. Export naar productiesheet: PL en kantoor.

## Regels die de database afdwingt

- Intake, beschikbaarheid en screening alleen voor labels die bij het geslacht van het crewlid passen.
- Indeling alleen gescreend voor (label, rol) én beschikbaar voor dat weekend.
- Afwijzen of intrekken van een screening haalt de persoon uit de indeling voor die rol; beschikbaarheid blijft staan.
- Export bevat geen mail, telefoon, notities of afgewezen rollen, en alleen gescreende crew.
- Toewijzingen bepalen zichtbaarheid van beschikbaarheid, intake en indeling via RLS; schrijfrecht op de indeling is per rol (`mag_indelen`): PL behalve EHBO/Foto-video, GL Spreker, FL Facilitair, coördinator eigen rol.

## Huisstijl per doelgroep

Mannen en de 4M/4Family-leider: Big Shoulders Display + Epilogue, rood `#DD0000`, verder zwart/wit. Vrouwen en de Arise-leider: Playfair Display + Lato, bordeaux `#6A3C3F`, goud `#A99F71`. Kantoor en LIFE: neutraal. Alles in de twee `:root[data-brand=…]`-blokken bovenaan `index.html`.

## Nog te beslissen

- Tweede screener per label bij uitval van de bewegingsleider.
- Bewaartermijn van afgewezen screenings (voorstel: één seizoen, daarna `verlopen`).
- Beheer naast Bart (voorstel: Arjen; alles staat in één repo en één Supabase-project).
