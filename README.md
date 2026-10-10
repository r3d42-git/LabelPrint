# LabelPrint

[English](README.en.md) · [Download](https://github.com/r3d42-git/LabelPrint/releases/latest) · [Website & Architektur](https://r3d42-git.github.io/LabelPrint/)

**PDF-Etiketten lokal auf dem Mac zuschneiden und über Bluetooth LE auf einem D520BT drucken.** LabelPrint ist eine native macOS-App mit deutscher Oberfläche, festem Etikettenformat **103 × 199 mm** und einer Vorschau der tatsächlich gesendeten Schwarzweiß-Rasterpunkte.

Kein Herstellertreiber, kein Konto, keine Cloud und keine externen Laufzeitbibliotheken. PDFs bleiben auf deinem Mac; das Original wird weder verändert noch überschrieben. LabelPrint ist ein unabhängiges Projekt und steht in keiner Verbindung zu Phomemo oder Labelife.

## Download und Voraussetzungen

- **macOS 14 oder neuer**, Apple Silicon (arm64).
- D520BT mit Bluetooth LE und passenden 103 × 199 mm Etiketten.
- [LabelPrint 0.2.1 herunterladen](https://github.com/r3d42-git/LabelPrint/releases/download/v0.2.1/LabelPrint-0.2.1-macOS-arm64.zip), ZIP entpacken und `LabelPrint.app` in den Programme-Ordner ziehen.
- Mit Developer ID signiert und von Apple notarisiert, einschließlich angeheftetem Ticket. Der frische GitHub-Download wurde auf Prüfsumme, Signatur und Gatekeeper-Freigabe geprüft. Eine Intel-Version wird derzeit nicht angeboten.

## Ein Etikett drucken

1. **PDF öffnen …** wählen (⌘O), dann die gewünschte Seite auswählen.
2. Mit der Maus ein Rechteck um das Etikett aufziehen. Zoom erleichtert die Auswahl; **Ganze Seite** setzt den Ausschnitt zurück. Weiße Freiräume um QR- und Strichcodes erhalten.
3. Die Druckvorschau rechts prüfen und bei Bedarf um **90° drehen**. Der Ausschnitt wird proportional und zentriert mit **mindestens 3 mm weißem Rand** eingepasst.
4. Drucker einschalten und Etiketten einlegen. Andere aktive Verbindungen zum Drucker schließen, **Drucker suchen** wählen, die macOS-Bluetooth-Freigabe erteilen und **D520 · BLE** auswählen.
5. **Etikett drucken** sendet genau ein Etikett. LabelPrint verbindet den ausgewählten Drucker bei Bedarf automatisch.

**Druckeinstellungen und Diagnose** enthält Dichte, Tempo, Etikettenlücke, Grauton-Schwelle, PNG-Export, Testetiketten und ein kopierbares Protokoll. Standardwerte: Dichte 12, Tempo 3, Lücke 3 mm.

Ein Auftrag bleibt während Verbindung und Übertragung festgeschrieben. Es gibt keine automatischen Wiederholungen und keinen automatischen Druck beim Laden oder Verbinden. Nach einer Unterbrechung den Ausdruck prüfen; bereits gepufferte Daten können nicht zurückgeholt werden. Vor einem bewussten neuen Versuch den Drucker bei Bedarf aus- und einschalten.

## Druckqualität und Grenzen

PDF-Inhalt wird direkt in **824 × 1592 Punkte** gerendert (8 Punkte/mm, nominal 203 dpi), in 1 Bit ohne Dithering umgewandelt und verlustfrei übertragen. Die Seitenvorschau ist nicht die Druckvorlage. Druckvorschau und Druck verwenden dasselbe finale Raster.

Mehrere echte PDF-Varianten wurden vom Nutzer erfolgreich ausgeschnitten, eingepasst und auf dem D520BT gedruckt; alle dabei geprüften Codes waren lesbar. Das bestätigt diese konkreten Drucke. Andere PDF-Inhalte und Geräte benötigen eine eigene Prüfung auf Papier.

- Ein Ausschnitt einer Seite pro Druck, festes Format; kein Stapeldruck.
- Passwortgeschützte PDFs brauchen eine entsperrte Kopie. Interaktive Formularfelder und Annotationen vorher fest in den PDF-Seiteninhalt einbetten.
- Bewährter Transport: **BLE FF00/FF02** mit bestätigten Schreibvorgängen; FF01 liefert Druckerrückmeldungen.
- Bluetooth Classic ist experimentell und scheiterte am getesteten Gerät beim Verbindungsaufbau mit Timeouts.
- QR- und Strichcode-Lesbarkeit hängt von Ausgangsqualität, Ausschnitt, weißen Freiräumen und physischer Druckgröße ab.

## Aus dem Quellcode bauen

Xcode mit Swift und den macOS-SDKs wird benötigt. Das SwiftPM-Paket verwendet Swift-5-Sprachmodus und ausschließlich Apple-Systemframeworks.

```sh
swift test --disable-sandbox
./script/build_and_run.sh --verify
```

Das Entwicklungsskript erstellt `dist/LabelPrintTest.app` und startet die App. Der öffentliche Release heißt `LabelPrint.app`; interne SwiftPM-Target- und Bundle-Bezeichner bleiben aus Kompatibilitätsgründen unverändert.

Die Offline-Prüfer drucken nicht:

```sh
swift run --disable-sandbox LabelPrintCheck output
swift run --disable-sandbox LabelPrintCheck --pdf /path/to/example.pdf output/pdf-check
```

15 automatisierte Tests decken Raster/TSPL, fragmentierte Rückmeldungen, Auswahlgeometrie, PDF-Ausschnitte, Seitendrehung, weiße Ränder, Fehlerfälle, unveränderte Snapshots und QR-/Code-128-Erkennung mit Apple Vision ab.

## Aufbau

[Interaktive Architektur ansehen](https://r3d42-git.github.io/LabelPrint/diagrams/architecture.html). Die Beschriftung ist deutsch; feste Bedienelemente des Diagramm-Viewers sind englisch.

| Bereich | Aufgabe |
| --- | --- |
| `LabelPrintTest` | SwiftUI-Arbeitsfenster, AppKit-Auswahlfläche, Hintergrundrendering und Bluetooth-Transport |
| `LabelTestCore` | Unveränderlicher PDF-Snapshot, Zuschnitt/Rotation, 1-Bit-Raster, kompakte TSPL-Aufträge und Rückmeldungsparser |
| `LabelPrintCheck` | Lokale Raster- und PDF-Prüfung einschließlich Codeerkennung |

Veraltete Renderergebnisse können eine neuere Auswahl nicht überschreiben. Weiße Rasterbereiche werden ausgelassen; belegte Bereiche werden als TSPL `BITMAP`/`BAR` gesendet. Auf dem getesteten D520 entspricht `BITMAP` Modus 0 auf dem Draht **0 = schwarz, 1 = weiß**. `DOING`/`DONE` sind Druckerrückmeldungen; sie ersetzen keinen Scan des gedruckten Etiketts.

## Lizenz und Hinweise

[GNU GPL v3, ausschließlich Version 3](LICENSE) (`GPL-3.0-only`). Der öffentliche Quellcode enthält keine Herstellerpakete, Herstelleranleitungen oder privaten Versand-PDFs. Produktnamen dienen ausschließlich zur Beschreibung der Kompatibilität. Der eingebettete Archify-Diagramm-Viewer steht separat unter der [MIT-Lizenz](docs/diagrams/LICENSE.archify); die enthaltenen Font-Lizenzhinweise bleiben im HTML erhalten.

Protokollhintergrund: [TSPL/TSPL2-Referenz von TSC](https://fs.tscprinters.com/system/files/31-0000001-00_tspl_tspl2_programming_3_0.pdf) und [unabhängige Interoperabilitätsnotizen](https://github.com/thermal-label/labelife/blob/main/docs/protocol/tspl.md).
