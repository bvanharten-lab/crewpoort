/**
 * CREW Poort → Google Sheets export (pull, nachtelijk)
 * Het enige Google-stuk. Leest alleen de view export_weekend en de weekends-tabel
 * en overschrijft per weekend één tabblad in de gedeelde sheet. Geen contactgegevens.
 *
 * Installatie: Extensies > Apps Script in de gedeelde CREW-planning-sheet, plak dit,
 * vul SUPABASE_URL en SUPABASE_KEY (Project Settings > API: gebruik een aparte
 * 'export'-gebruiker met rol kantoor en een service-role key is NIET nodig — maak in
 * Supabase een rol/policy die alleen export_weekend + weekends leest), trigger: dagelijks 03:00.
 * Faalt de run, dan blijft het tabblad 'Export-log' op de vorige datum staan — dat is het signaal.
 */
const SUPABASE_URL = 'https://XXXX.supabase.co';
const SUPABASE_KEY = 'eyJ...'; // sleutel van de leesgebruiker

function exportAlles() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const weekends = get_('weekends?select=id,label,naam,datum,slots&order=start_datum');
  const rows = get_('export_weekend?select=*');
  weekends.forEach(w => {
    const naam = (w.naam + ' ' + w.datum).slice(0, 90);
    const sh = ss.getSheetByName(naam) || ss.insertSheet(naam);
    sh.clearContents();
    const av = rows.filter(r => r.weekend === w.id);
    // Links: beoogde indeling (rol × plek), rechts: beschikbare goedgekeurde crew
    const left = [['Beoogde indeling CREW', ''], ['Rol', 'Naam']];
    Object.entries(w.slots || {}).forEach(([rol, n]) => {
      for (let i = 1; i <= n; i++) {
        const p = av.find(r => (r.ingedeeld_als || '').split(', ').includes(rol + ' ' + i));
        left.push([rol, p ? p.naam : '']);
      }
    });
    const right = [['Beschikbare CREW', '', '', '', ''], ['Naam', 'Vervulde functies', 'Goedgekeurde functies', 'Ervaring', 'Aantal keer gekozen']];
    av.forEach(r => right.push([r.naam, r.vervulde_functies, r.goedgekeurde_functies, r.ervaring, r.aantal_keer_gekozen]));
    sh.getRange(1, 1, left.length, 2).setValues(left);
    sh.getRange(1, 4, right.length, 5).setValues(right);
    sh.getRange(1, 1, 1, 2).merge().setFontWeight('bold');
    sh.getRange(1, 4, 1, 5).merge().setFontWeight('bold');
  });
  const log = ss.getSheetByName('Export-log') || ss.insertSheet('Export-log');
  log.getRange('A1:B1').setValues([['Laatste export', new Date()]]);
}

function get_(path) {
  const res = UrlFetchApp.fetch(SUPABASE_URL + '/rest/v1/' + path, {
    headers: { apikey: SUPABASE_KEY, Authorization: 'Bearer ' + SUPABASE_KEY },
    muteHttpExceptions: true,
  });
  if (res.getResponseCode() >= 300) throw new Error('Supabase ' + res.getResponseCode() + ': ' + res.getContentText());
  return JSON.parse(res.getContentText());
}
