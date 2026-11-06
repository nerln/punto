# Punto

**Esplora le modalità native del monitor esterno e il rendering HiDPI su macOS.**

[English](README.md) · [Download](https://github.com/nerln/punto/releases/tag/v0.1.0) · [Privacy](docs/PRIVACY.md#italiano) · [Licenza MIT](LICENSE)

Punto è un’app macOS nativa e sperimentale per esaminare le modalità video e provare HiDPI mantenendo le dimensioni logiche del desktop. Espone le modalità già generate da WindowServer, comprese alcune che macOS nasconde all’API pubblica.

**Anteprima 0.1.0 · Download per Apple Silicon · Target di compilazione macOS 14+.** Le verifiche hardware finora riguardano un MacBook Pro M4 con macOS 27.2 e un Dell U2413. La compatibilità con altri dispositivi e versioni del sistema resta da verificare.

## Cosa fa

- Elenca le modalità pubbliche e private, distinguendo dimensioni logiche, buffer di rendering e timing fisico dell’output.
- Prova HiDPI diretto alle dimensioni native del desktop, quando WindowServer offre già la modalità necessaria.
- Richiede conferma entro 20 secondi per ogni cambio e avvia un processo separato per il ripristino.
- Esamina i formati colore della connessione ed esporta diagnostiche locali senza UUID del display o seriali hardware.
- Offre l’interfaccia in italiano e inglese e segue l’aspetto chiaro o scuro del sistema.
- Disegna un pattern Metal per confrontare la nitidezza soltanto su richiesta, senza rendering continuo.

L’avvio normale legge soltanto la configurazione. Una modalità diretta confermata può rimanere attiva dopo la chiusura di Punto; questo percorso non richiede che l’app resti aperta. Il comportamento dopo riconnessione o nuovo accesso dipende da macOS.

## Il risultato verificato

Sul Dell U2413 Punto ha applicato una modalità HiDPI diretta nascosta e verificato la geometria del desktop, il fattore AppKit e il timing fisico riportato dal driver:

| Dato | Nativo 1× | HiDPI diretto 2× |
| --- | --- | --- |
| Desktop logico | 1920 × 1200 punti | 1920 × 1200 punti |
| Buffer di rendering | 1920 × 1200 pixel | 3840 × 2400 pixel |
| Fattore AppKit | 1× | 2× |
| Timing fisico riportato dal driver | 1920 × 1200 a 60 Hz | 1920 × 1200 a 60 Hz |
| Display virtuale o mirroring | Assente | Assente |

**Chi ha provato l’app su questo Dell non ha percepito un miglioramento significativo nella nitidezza del testo.** Questa versione è un’anteprima per controllare e diagnosticare le modalità video, non una soluzione dimostrata al testo sgranato. Anche la prova RGB completo non ha prodotto un miglioramento visivo utile; l’output YCbCr iniziale era già 4:4:4.

L’indice numerico della modalità privata viene rilevato durante l’esecuzione, senza codificare nell’app quello osservato durante lo sviluppo.

## Cosa cambia con HiDPI

HiDPI alle stesse dimensioni logiche disegna un’immagine 2× lungo entrambi gli assi e poi la adatta al pannello. Un desktop di 1920 × 1200 usa un buffer di 3840 × 2400 pixel, mentre il monitor continua a ricevere il segnale nativo di 1920 × 1200. L’interfaccia conserva le sue dimensioni; il ricampionamento avviene comunque all’interno del sistema.

Aumentano i campioni di rendering, non i pixel fisici. Punto non sostituisce il motore del testo e non ripristina ClearType o l’antialiasing subpixel in tutte le applicazioni. Quattro volte i pixel del buffer è un rapporto teorico di area, non una misura del carico GPU. Punto non certifica una pipeline esclusivamente Metal per l’intero desktop macOS.

## Download e avvio

1. Scarica lo ZIP per Apple Silicon e il relativo checksum da [GitHub Releases](https://github.com/nerln/punto/releases/tag/v0.1.0).
2. Estrailo e sposta `Punto.app` in Applicazioni oppure nella cartella Applicazioni del tuo account.
3. Apri Punto e seleziona il monitor esterno da esaminare.

Le anteprime hanno **firma ad-hoc, senza firma Developer ID e senza notarizzazione Apple**. macOS potrebbe bloccare l’app scaricata. Se decidi di considerarla affidabile, segui il percorso documentato da Apple: **Impostazioni di Sistema → Privacy e Sicurezza → Apri comunque**. Consulta [le indicazioni Apple sulle app scaricate](https://support.apple.com/it-it/102445).

Il download contiene soltanto l’architettura arm64. Il codice ha come target macOS 14; questo non garantisce che tutte le API private funzionino su macOS 14 o su ogni Mac Apple Silicon.

## Uso

Seleziona il monitor, controlla la geometria attuale e prova HiDPI diretto se la modalità necessaria è disponibile. Conferma entro 20 secondi per mantenerla. L’azione nativa 1:1 ripristina la modalità senza scaling del pannello.

Durante una prova un processo separato conserva la configurazione precedente e tenta il recupero alla scadenza o in caso di uscita inattesa. Il ripristino dipende dal driver, che deve accettare la configurazione precedente: tieni disponibile lo schermo integrato durante le prove.

I controlli avanzati espongono anche le modalità elencate dal driver, i formati colore e il backend virtuale opzionale del prototipo iniziale. Il percorso principale HiDPI diretto non usa quel backend. Una sessione con display virtuale richiede che Punto resti aperto e termina all’uscita dall’app.

Il percorso diretto verificato non richiede privilegi amministrativi, override del display, modifiche EDID o interventi su SIP. Le API private possono cambiare e la presenza di una modalità nella tabella non garantisce che ogni driver la accetti.

## Compilazione e verifiche

Servono macOS, Xcode con Swift 6 o successivo e un Mac Apple Silicon per creare il pacchetto arm64. L’app non ha dipendenze esterne da altri pacchetti.

```sh
swift test
./scripts/build-app.sh
./scripts/package-release.sh 0.1.0
```

File prodotti:

- `build/Punto.app`
- `build/Punto-0.1.0-macOS-arm64.zip`
- `build/Punto-0.1.0-macOS-arm64.zip.sha256`

Per leggere la diagnostica dal terminale senza cambiare il display:

```sh
.build/debug/Punto --diagnose
```

`swift test` non cambia modalità video. I test che richiedono una particolare modalità hardware vengono saltati se quella condizione non è disponibile. La CI compila, verifica e prepara il pacchetto su un runner macOS arm64, senza certificare la qualità fisica dell’immagine o cambiare display.

I comandi di sviluppo come `--smoke-native-hidpi` e `--smoke-rgb` cambiano intenzionalmente un display collegato e poi controllano il ripristino. Sono separati dalla suite automatica. Sul dispositivo indicato sono state verificate l’applicazione HiDPI diretta e il normale ripristino; le verifiche dopo crash hanno coperto anche i percorsi precedenti RGB e display virtuale. Queste prove non certificano la qualità del testo, il consumo energetico o il comportamento dopo standby e riattivazione.

## Riferimenti tecnici

- [Apple: punti, pixel e rendering ad alta risoluzione](https://developer.apple.com/library/archive/documentation/GraphicsAnimation/Conceptual/HighResolutionOSX/Explained/Explained.html)
- [FineDisplay: selezione delle modalità WindowServer nascoste](https://github.com/ofbakirci/finedisplay/blob/main/Sources/FineDisplayKit/Display.swift)
- [AllRez: struttura delle modalità private](https://github.com/joevt/AllRez/blob/master/AllRez/AppleMisc.h)
- [WebKit: rimozione dell’antialiasing subpixel di sistema](https://bugs.webkit.org/show_bug.cgi?id=193095)

Un progetto di Eugenio Nerelli. Il codice è disponibile con [licenza MIT](LICENSE).
