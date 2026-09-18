# PDF Word Editor (Flutter — Android + iOS)

Tap σε μια λέξη μέσα σε ένα PDF → η εφαρμογή αναγνωρίζει τη γραμματοσειρά
(family/serif-sans-mono, μέγεθος, bold/italic) → την επεξεργάζεσαι →
Save/Share το αποτέλεσμα ως νέο PDF.

## Γιατί δεν το build άρω/έτρεξα εγώ

Έγραψα όλο τον κώδικα σε ένα cloud sandbox χωρίς πρόσβαση στο
`storage.googleapis.com` (εκεί κατεβάζει το Flutter tool το engine/Dart
SDK), οπότε δεν μπόρεσα να τρέξω `flutter pub get` / `flutter run` /
`flutter analyze` εδώ για να το επιβεβαιώσω 100%. Έλεγξα χειροκίνητα τα
ακριβή API signatures που χρησιμοποιώ (Syncfusion `PdfTextExtractor`,
`TextWord`, `PdfGraphics.drawString/drawRectangle`, `pdfx`
`PdfDocument`/`PdfPage`) από την επίσημη τεκμηρίωση, οπότε θα έπρεπε να
κάνει compile καθαρά — αλλά σίγουρα θα χρειαστεί ένα-δύο γύρους
διορθώσεων μόλις το τρέξεις. Στείλε μου ό,τι σφάλμα δεις και το φτιάχνουμε.

## Setup (στο δικό σου μηχάνημα, όπου υπάρχει internet + Flutter)

1. Δημιούργησε ένα καθαρό Flutter project scaffold (αυτό φτιάχνει τα
   σωστά `android/` και `ios/` φακέλους για την έκδοση Flutter που έχεις
   εγκατεστημένη — γι' αυτό δεν τα έγραψα εγώ με το χέρι):

   ```powershell
   cd C:\src
   flutter create pdf_word_editor
   ```

2. Αντίγραψε ΠΑΝΩ από το νέο project αυτά τα δύο πράγματα από αυτό το
   πακέτο:
   - `pubspec.yaml` (αντικατάστησε το)
   - όλο το `lib/` (αντικατάστησε το)

3. Πρόσθεσε αυτές τις άδειες:

   **Android** — `android/app/src/main/AndroidManifest.xml`, μέσα στο
   `<manifest>`, πριν το `<application>`:
   ```xml
   <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
   ```

   **iOS** — `ios/Runner/Info.plist`, μέσα στο `<dict>`:
   ```xml
   <key>NSDocumentsFolderUsageDescription</key>
   <string>Χρειαζόμαστε πρόσβαση για να ανοίγεις PDF αρχεία.</string>
   ```

4. ```bash
   flutter pub get
   flutter run
   ```

## Πώς δουλεύει (αρχιτεκτονική)

- **`services/pdf_page_renderer.dart`** — `pdfx` (pdfium) κάνει rasterize
  κάθε σελίδα σε εικόνα, μόνο για προβολή. Δίνει επίσης το πλάτος/ύψος της
  σελίδας σε PDF points, που είναι η "κοινή γλώσσα" με τα bounds των
  λέξεων.
- **`services/pdf_edit_service.dart`** — `syncfusion_flutter_pdf` κρατάει
  το πραγματικό PDF document. `extractWords()` δίνει κάθε λέξη με bounds +
  fontName/fontSize/bold/italic. `replaceWord()` καλύπτει την παλιά λέξη
  και ζωγραφίζει την καινούρια με ταιριασμένη γραμματοσειρά. `save()`
  επιστρέφει τα τελικά bytes.
- **`services/pdf_font_matcher.dart`** — η λογική "κατάλαβε τη
  γραμματοσειρά": ταξινομεί το όνομα font σε serif/sans/mono/symbol,
  κρατάει size + bold/italic, διαλέγει το πλησιέστερο από τα 4
  ενσωματωμένα standard PDF fonts.
- **`widgets/pdf_page_overlay.dart`** — δείχνει την εικόνα σελίδας και
  μετατρέπει tap σε "ποια λέξη πατήθηκε" συγκρίνοντας συντεταγμένες σε PDF
  points.
- **`screens/editor_screen.dart`** — ενώνει τα παραπάνω: tap → dialog
  edit → ξανά-render μετά το save ώστε η οθόνη να δείχνει πάντα ό,τι θα
  βγει στο τελικό αρχείο.

## Γνωστοί περιορισμοί v1 (και τι θα κάνουμε μετά)

1. **Δεν ξαναχρησιμοποιεί την ακριβή αρχική γραμματοσειρά (τα glyphs).**
   Ταιριάζει στο πλησιέστερο από τα 4 standard PDF fonts (σαν τα
   περισσότερα PDF editors όταν η γραμματοσειρά δεν είναι embedded).
   Επόμενο βήμα: εξαγωγή του embedded font program από το PDF όταν
   υπάρχει, και χρήση του ίδιου.
2. **Το "κάλυμμα" της παλιάς λέξης είναι πάντα λευκό.** Σε έγγραφο με
   έγχρωμο/γκρι background θα φανεί σαν λευκό κουτάκι. Επόμενο βήμα:
   δειγματοληψία χρώματος γύρω από τη λέξη από την ήδη rendered εικόνα.
3. **Πολύ μεγαλύτερη λέξη-αντικατάσταση μπορεί να επικαλύψει τη διπλανή
   λέξη** (δίνουμε λίγο extra πλάτος αλλά όχι reflow ολόκληρης γραμμής).
4. **Page-by-page navigation, όχι continuous smooth scroll.** Δούλεψε
   καλά για το demo/MVP· αν θες πιο "φυσική" εμπειρία ανάγνωσης σαν τα
   άλλα readers, το επόμενο βήμα είναι δικό reading mode με continuous
   scroll (π.χ. με `syncfusion_flutter_pdfviewer`) και toggle σε αυτό το
   edit mode.
5. **Save = Share sheet** (όχι απευθείας αποθήκευση σε συγκεκριμένο
   φάκελο) — έτσι αποφεύγουμε storage permissions εντελώς. Αν θες κουμπί
   "Save to Downloads", προσθέτουμε `permission_handler` +
   `MANAGE_EXTERNAL_STORAGE` (Android) αργότερα.
6. Δεν έχω τρέξει `flutter build` εδώ — δες σημείωση στην αρχή.

## Σχέση με την έρευνα αγοράς

Οι δύο πιο κοινές αιτίες κακών reviews σε ανταγωνιστές (κρυφές χρεώσεις /
δύσκολη ακύρωση, forced watermark) δεν υπάρχουν καν σε αυτό το app ακόμα
— είναι θέμα business model, όχι κώδικα, οπότε το αποφασίζουμε όποτε
βάλουμε τιμολόγηση/IAP.
