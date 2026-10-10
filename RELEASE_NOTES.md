# LabelPrint 0.2.0

## Deutsch

Erste öffentliche Version: PDFs öffnen, eine Seite auswählen, einen Bereich mit der Maus
zuschneiden, drehen und proportional auf 103 × 199 mm einpassen. Druck direkt über Bluetooth LE
auf einem Phomemo D520BT, ohne Herstellertreiber. Alles bleibt lokal auf dem Mac.

- Native macOS-App, macOS 14 oder neuer, Download für Apple Silicon (arm64).
- Schwarzweiß-Druckvorschau in 824 × 1592 Punkten, mindestens 3 mm weißer Rand.
- Verlustfreie Auslassung leerer Druckbereiche für kleinere Bluetooth-Aufträge.
- Mehrere echte PDF-Varianten erfolgreich gedruckt; Zuschneiden/Einpassen und alle getesteten Codes bestätigt.
- 15 automatisierte Tests für PDF, QR/Code128, Raster und Druckerrückmeldungen.

ZIP entpacken, **LabelPrint.app** nach **Programme** kopieren und öffnen. Bluetooth-Zugriff auf
Anfrage erlauben. Die App ist mit Developer ID signiert und von Apple notarisiert; das Ticket
ist an der App angeheftet. Den D520-Eintrag mit **BLE** verwenden. Classic ist experimentell.
Die Oberfläche ist deutsch; Dokumentation liegt auf Deutsch und Englisch vor.

## English

First public release: open a PDF, select a page, crop a region with the mouse, rotate it and
fit it proportionally onto a 103 × 199 mm label. Print directly to a Phomemo D520BT over
Bluetooth LE without installing a vendor driver. Processing stays on your Mac.

- Native macOS app, macOS 14 or newer; Apple Silicon (arm64) download.
- Final 824 × 1592 monochrome preview with at least 3 mm white margins.
- Empty areas omitted losslessly to reduce Bluetooth transfer size.
- Multiple real PDF variants printed successfully; cropping, fitting and all tested codes confirmed.
- 15 automated tests covering PDF, QR/Code128, raster and printer replies.

Extract the ZIP, copy **LabelPrint.app** to **Applications**, then open it and allow Bluetooth
access when prompted. Developer ID signed, Apple notarized, with the ticket stapled to the app.
Choose the D520 **BLE** entry; Classic remains experimental. The app UI is German; documentation
is available in German and English.

Licensed under GPL-3.0-only. Independent project, not affiliated with Phomemo or Labelife.
Intel builds and a separate clean-machine installation have not been validated.
