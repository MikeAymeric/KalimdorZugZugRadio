# Kalimdor ZugZug Radio

Radio per WoW Forever: suona le **tue playlist**, create e scelte in gioco, in base a cosa sta facendo il personaggio, oppure liberamente senza condizioni.

## Aggiungere musica
1. Metti i brani in `KalimdorZugZugRadio/music/` (sottocartelle libere: servono solo a organizzare e a filtrare nella ricerca).
   Formati: qualsiasi cosa ffmpeg legga (mp3, ogg, mp4, m4a, flac, wav...). Copertina: quella incorporata nel file, oppure `cover.jpg`/`folder.jpg` nella cartella.
2. Esegui `python tools/import_music.py` (da dentro la cartella dell'addon o del progetto; altrimenti `--addon "percorso\KalimdorZugZugRadio"`). Dopo una conversione riuscita l'originale viene **eliminato** (e anche la cartella `music/_originali/`); con `--keep-originals` gli originali vengono invece conservati in `music/_originali/`.
   Le copertine identiche vengono salvate una sola volta in `covers/` e condivise tra i brani.
   File e cartelle con caratteri non latini (giapponese, accenti...) vengono rinominati in ASCII perché WoW potrebbe non aprirli; i nomi originali restano in `music/_nomi_originali.json` e si vedono in gioco. Per non rinominare: `--keep-names`.
3. **Riavvia il client** se ci sono file nuovi; se è cambiato solo `Library.lua` basta `/reload`.

## Libreria (in gioco)
Apri la libreria con il pulsante **Libreria** del player o con `/kzz lib`.

- **Playlist** (sinistra): crea, rinomina, elimina. *Tutta la libreria* contiene sempre tutti i brani.
- **Brani** (destra): seleziona una playlist e spunta i brani da includere. La ricerca filtra per titolo, artista, album o cartella; *Aggiungi visibili* aggiunge tutti i brani filtrati. `>` o doppio clic suona un brano.

## Impostazioni
*Opzioni > AddOns > Kalimdor ZugZug Radio*, oppure `/kzz config`, Ctrl+clic sul pulsante della minimappa, il pulsante *Impostazioni* della libreria o la voce nel menu del player.

- **Generale**: radio accesa, shuffle, pulsante sulla minimappa, blocco della finestra del player, **lingua** (+ pulsante *Ricarica UI*).
- **Condizioni**: spunta le condizioni da usare e scegli la playlist di ognuna. Vince la prima attiva dall'alto:

  Boss → Élite/Raro → Combattimento → Volo → Campfire → Dungeon → Città/Riposo → **Nessuna condizione**

  *Nessuna condizione* è la musica di quando non succede niente di particolare. Una condizione non spuntata viene ignorata; se nessuna condizione attiva ha una playlist, torna la musica di zona del gioco. Il nome della condizione è verde quando è attiva e arancione quando è quella che sta suonando.

Le impostazioni non si aprono in combattimento (limite del pannello Opzioni di WoW).

**Riproduzione libera**: scegli una playlist dal menu del player (o *Suona questa playlist*, o `>` su un brano) e le condizioni vengono ignorate finché non torni su *Automatico (condizioni)*.

Campfire: la musica parte quando sei seduto a un campfire (aure *Campfire Nearby* + *Welcoming Campfire*) e si ferma quando ti muovi.

## Installazione
Collega la cartella dell'addon al gioco con un junction (da `cmd`):

```
mklink /J "<WoW>\_forever_\Interface\AddOns\KalimdorZugZugRadio" "<repo>\KalimdorZugZugRadio"
```
In alternativa copia la cartella `KalimdorZugZugRadio` in `AddOns`.

## Pulsante sulla minimappa
Clic sinistro: player · Clic destro: libreria · Shift+clic: play/stop · Ctrl+clic: impostazioni · Trascina per spostarlo lungo il bordo.
Gli stessi comandi sono anche nel menu degli addon della minimappa (Addon Compartment), se il client lo mostra.

## Lingue
English, Français, Deutsch, Español (EU), Español (AL), Português (BR), Italiano, Русский, 简体中文, 繁體中文, 日本語.
La lingua segue quella del client; per cambiarla usa il menu *Lingua* nelle impostazioni o `/kzz lang <codice|auto>` (es. `/kzz lang ja`), poi `/reload`.
Il giapponese (che WoW non ha come lingua del client) usa il font M+ 1p incluso nell'addon (licenza OFL, `fonts/OFL-MPLUS1p.txt`); in quel caso i messaggi in chat restano in inglese perché la chat usa il font del gioco.

## Comandi
`/kzz` (o `/zugzug`) player · `/kzz lib` libreria · `/kzz config` impostazioni · `play` `stop` `next` `prev` `shuffle` · `on`/`off` · `auto` · `playlist <nome|tutti>` · `status` · `lock` · `reset` · `minimap` · `lang`.

Limiti di WoW: niente pausa vera (stop + riparte dall'inizio del brano) e niente seek; il volume è quello della **Musica** nelle opzioni audio.
