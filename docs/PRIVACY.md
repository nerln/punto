# Privacy

[English](#english) · [Italiano](#italiano)

## English

Punto 0.1.0 runs locally. The app contains no analytics, advertising, account system, update checker or diagnostic-upload service. Display controls work offline. Opening a project link in your browser connects to that website under its own policies.

### Display information

Punto reads macOS display APIs and relevant IOKit properties to inspect monitor names, identifiers, modes, geometry, connection-color formats, driver-reported timing and the associated GPU. Private APIs support native-mode selection and optional virtual displays. Reading a framebuffer’s dimensions is different from capturing its contents: Punto does not record screenshots, window contents, keystrokes, audio or video.

The Metal test pattern renders its own generated image on demand. It does not capture another application’s image.

### Local storage

- App preferences can store the chosen language, appearance and original connection-color format, keyed by display UUID, for later restoration.
- Each display trial creates a recovery snapshot inside a private `Punto-*` temporary directory with owner-only directory access. It includes display UUIDs, mode dimensions, placement, mirror relationships and recovery metadata. A separate local process uses it for rollback.
- Snapshots are normally removed when the trial is settled or recovery finishes. An interrupted process or power loss can leave a temporary file until local cleanup.
- Confirmed direct settings apply to the current macOS session. macOS manages its own display preferences and may retain information independently of Punto.

### Exported diagnostics

Export happens only when requested and at a destination you choose. Reports include OS version, GPU name, monitor names, transient display IDs, logical and rendering dimensions, available modes, reported physical timing and connection-color information. Display UUIDs and hardware serial numbers are omitted. Names and hardware characteristics can still identify your setup; review the JSON before sharing it.

Punto does not transmit the report. Attaching one to a public GitHub issue makes it public through your own submission.

### Permissions and changes

The verified direct path requires no administrator privileges, display-override installation, EDID edit, SIP change or Screen Recording permission. Advanced virtual-display controls create a local software display only when selected. An ordinary launch does not change display modes.

This document describes the app. GitHub, release downloads and the project website operate under their respective hosting providers’ policies.

## Italiano

Punto 0.1.0 funziona in locale. L’app non contiene analisi d’uso, pubblicità, account, controllo aggiornamenti o servizi per caricare diagnostiche. Il controllo del display funziona anche senza connessione. Aprire un collegamento nel browser avvia una connessione al sito esterno, soggetta alle sue regole.

### Informazioni sul display

Punto legge le API video macOS e alcune proprietà IOKit per esaminare nomi dei monitor, identificativi, modalità, geometria, formati colore della connessione, timing riportati dal driver e GPU associata. La selezione delle modalità native e il display virtuale opzionale usano API private. Leggere le dimensioni del framebuffer è diverso dal catturarne il contenuto: Punto non registra schermate, contenuti delle finestre, tasti premuti, audio o video.

Il pattern Metal disegna un’immagine generata dall’app soltanto su richiesta. Non cattura l’immagine di un’altra applicazione.

### Dati locali

- Le preferenze possono conservare la lingua, l’aspetto e il formato colore originale della connessione, associato all’UUID del display, per consentirne il ripristino.
- Ogni prova crea uno snapshot di recupero in una directory temporanea privata `Punto-*`, accessibile soltanto al proprietario. Contiene UUID, dimensioni delle modalità, posizioni, relazioni di mirroring e metadati di recupero. Un processo locale separato lo usa per il ripristino.
- Lo snapshot viene normalmente eliminato quando la prova o il recupero terminano. Un’interruzione o una perdita di alimentazione possono lasciare un file temporaneo fino alla sua pulizia locale.
- Le modalità dirette confermate si applicano alla sessione macOS corrente. macOS gestisce le proprie preferenze video e può conservare informazioni indipendentemente da Punto.

### Diagnostiche esportate

L’esportazione avviene soltanto su richiesta e nella destinazione scelta. Il rapporto include versione del sistema, nome GPU, nomi dei monitor, identificativi video temporanei, dimensioni logiche e di rendering, modalità disponibili, timing fisico riportato e informazioni sul formato colore. UUID dei display e seriali hardware sono esclusi. Nomi e caratteristiche possono comunque rendere riconoscibile la configurazione: controlla il JSON prima di condividerlo.

Punto non trasmette il rapporto. Se lo alleghi a un’issue pubblica GitHub, diventa pubblico attraverso il tuo invio.

### Permessi e modifiche

Il percorso diretto verificato non richiede privilegi amministrativi, installazione di override, modifiche EDID, interventi su SIP o permesso di registrazione dello schermo. I controlli avanzati creano uno schermo software locale soltanto se selezionati. L’avvio normale non cambia la modalità video.

Questo documento riguarda l’app. GitHub, i download delle release e il sito del progetto seguono le regole dei rispettivi servizi di hosting.
