# RadioProbe — test di compatibilità

Mini addon che verifica sul client WoW Forever quali API servono a Forever Radio.

## Installazione
1. I file di prova sono già in `media/`. I tre audio sono toni di altezza diversa, così capisci quale stai sentendo:
   `test.mp3` è il più grave (330 Hz), `test.wav` medio (440 Hz), `test.ogg` il più acuto (523 Hz).
3. Copia la cartella `RadioProbe` in `World of Warcraft/_forever_/Interface/AddOns/`
   (se non esiste `_forever_`, guarda quale cartella `_xxx_` c'è e usa quella).
4. **Riavvia completamente il client** (i file nuovi non vengono visti con /reload).
5. Nella schermata personaggi → AddOns: abilita "Radio Probe" (spunta "carica addon non aggiornati" se serve).

## Checklist dei test
Al login stampa in chat build, API mancanti ed eventi. Poi:

| Cosa fare | Comando / azione | Annota |
|---|---|---|
| Audio | `/rprobe sound` | Quali file hai **sentito** (ogg/mp3/wav) e se si fermano da soli dopo ~4s |
| PlayMusic | `/rprobe music` poi `/rprobe stopmusic` | Si sente? La musica di zona si ferma? |
| Copertine | `/rprobe tex` | Vedi il quadrato TGA? E il PNG? |
| Combattimento | attacca un mob | Compaiono le righe `[combat]` con eventuali `<SECRET>` |
| Élite / raro | attacca un élite o un raro nel mondo | Riga `[combat] UnitClassification(target)`: valore leggibile o `<SECRET>`? |
| Boss | entra in un dungeon e ingaggia un boss | Arriva `ENCOUNTER_START`? (solo boss di istanza, non rari/élite) |
| Volo | prendi un flight path | Compare `Stato taxi: false -> true`? |
| Campfire | accendi un fuoco da campo, siediti, `/rprobe auras` | Nome e spellId dell'aura del fuoco |
| Riepilogo | `/rprobe report` | Conteggio eventi ricevuti |

## Inviare i risultati
Fai `/reload` o esci dal gioco, poi mandami il file:
`World of Warcraft/_forever_/WTF/Account/<NOME_ACCOUNT>/SavedVariables/RadioProbe.lua`
