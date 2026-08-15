NOTEPAD.R4X
===========

Kleine gehostete Desktop-System-App fuer Textdateien.

Build:

    cd Code\System\Software\Notepad
    ..\..\..\DevTools\Zig\zig.exe build

Ergebnis:

    Code\System\Software\Notepad\zig-out\NOTEPAD.R4X

Das Image-Build-Script kopiert diese Datei nach /R4OS/SOFTWARE/DESKTOP/NOTEPAD.R4X ins Boot-Image.

Projektstruktur seit 0.51.20:
- `build.zig` baut die App als eigenes SDK-Projekt.
- `build.zig.zon` bindet `r4os_sdk` als Paket.
- `module.R4MF` beschreibt Artefakt, Zielpfad, R4DESK-/R4DRAW-Imports und Contract.
- Der zentrale `cd Code`-Build baut weiterhin das Image-Artefakt
  `Code\zig-out\NOTEPAD.R4X`.

Contract:
- R4XStart-Entry: `notepad_main`
- App-Klasse: `gui`
- R4L-Imports: `R4SYS`, `R4DESK`, `R4DRAW`, `R4NET`, `R4DEV`
- Zielpfad im Image: `C:\R4OS\SOFTWARE\DESKTOP\NOTEPAD.R4X`

Aktueller Stand ab 0.62.1:
- Gehosteter Desktop-Modus mit Fenstertitel, Mindestgroesse, Resize-Handling
  und normalem Close-Event.
- Gemeinsame `r4os.gui.Menubar` mit `File`, `Settings`, `Edit` und `Search`.
- `File`: New, Open, Save, Save As, Exit.
- `Settings`: Change Font sowie an- und abschaltbarer Word Wrap.
- `Edit`: Copy und Paste. `Search` bietet Find mit `Ctrl+F`.
- Editorbereich nutzt `r4os.gui.TextArea` mit sichtbarem Caret, Mausposition,
  Mausauswahl, Tastaturbewegung, Auswahlanker, Copy/Cut/Paste, funktionierendem
  LF-/Return-Zeilenumbruch, dynamischem Wrapping und dauerhaft sichtbaren
  horizontalen sowie vertikalen Scrollbars. Nicht benoetigte Scrollbars sind
  deaktiviert.
- Open/Save/Save As laufen als App-interne Dialoge ueber `r4os.gui.FileDialog`.
- Save-Prompt erscheint bei New, Open, Exit und Fenster-Schliessen, wenn der
  Text geaendert wurde.
- `Change Font` oeffnet einen App-internen Fontdialog mit getrennten Listen
  fuer Familie, Stil und native Pixelgroesse. Der Dialog bietet nur wirklich
  installierte R4F-Faces an, zeigt eine Vorschau und stellt ausschliesslich den
  Editorbereich um. Cursor, Umbruch und Scrollbereiche verwenden danach die
  Metriken der neuen Groesse.
- Textdateien werden bis zum statischen 32-KB-Editorlimit geladen; groessere
  Dateien werden sichtbar als trunciert markiert. Direktes Ueberschreiben
  truncierter Dateien wird blockiert, Save As bleibt bewusst moeglich.
- Seit R4X v2 wird kein Stack-Budget mehr im Header gesetzt.

Der alte Vollbildpfad bleibt als einfacher Kompatibilitaetsfallback erhalten;
die eigentliche System-App ist der gehostete Desktop-Pfad.
