import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const localePrefKey = 'app_locale';

class LocaleController extends ChangeNotifier {
  Locale _locale = const Locale('en');

  Locale get locale => _locale;
  AppStrings get strings => AppStrings(_locale.languageCode);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(localePrefKey) ?? 'en';
    _locale = Locale(code == 'el' ? 'el' : 'en');
    notifyListeners();
  }

  Future<void> setCode(String code) async {
    final next = Locale(code == 'el' ? 'el' : 'en');
    if (next == _locale) return;
    _locale = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(localePrefKey, _locale.languageCode);
  }
}

class LocaleScope extends InheritedNotifier<LocaleController> {
  const LocaleScope({
    super.key,
    required LocaleController controller,
    required super.child,
  }) : super(notifier: controller);

  static LocaleController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LocaleScope>();
    assert(scope != null, 'LocaleScope missing');
    return scope!.notifier!;
  }
}

class AppStrings {
  AppStrings(this._code);

  final String _code;

  static AppStrings of(BuildContext context) => LocaleScope.of(context).strings;

  bool get _el => _code == 'el';

  String get appName => _el ? 'Επεξεργασία PDF & Υπογραφή' : 'Edit PDF Words & Sign';
  String get homeTagline => _el
      ? 'Άνοιξε ένα PDF. Πάτα μια λέξη για να την αλλάξεις. Βάλε υπογραφή όπου θέλεις.'
      : 'Open a PDF. Tap a word to change it. Sign anywhere on the page.';
  String get featureEditWord => _el ? 'Επεξεργασία λέξης' : 'Edit a word';
  String get featureMoveWord => _el ? 'Μετακίνηση λέξης' : 'Move a word';
  String get featureSign => _el ? 'Υπογραφή' : 'Add a signature';
  String get openPdf => _el ? 'Άνοιγμα PDF' : 'Open PDF';
  String get language => _el ? 'Γλώσσα' : 'Language';
  String get english => 'English';
  String get greek => 'Ελληνικά';
  String get skip => _el ? 'Παράλειψη' : 'Skip';
  String get howItWorks => _el ? 'Πώς δουλεύει' : 'How it works';
  String get howItWorksIntro => _el ? 'Τρία βήματα. Τίποτα άλλο.' : 'Three steps. That’s it.';
  String get gotIt => _el ? 'Κατάλαβα' : 'Got it';
  String get step1Title => _el ? 'Άνοιξε ένα PDF' : 'Open a PDF';
  String get step1Detail => _el ? 'Από τη συσκευή σου.' : 'From your device.';
  String get step2Title => _el ? 'Πάτα μια λέξη' : 'Tap a word';
  String get step2Detail => _el
      ? 'Άλλαξέ την ή μετακίνησέ την με τα βελάκια.'
      : 'Change it, or move it with the arrows.';
  String get step3Title => _el ? 'Βάλε υπογραφή' : 'Add a signature';
  String get step3Detail => _el
      ? 'Ζωγράφισέ την και σύρε την όπου θέλεις στη σελίδα.'
      : 'Draw it, then drag it where you want on the page.';
  String get editText => _el ? 'Επεξεργασία κειμένου' : 'Edit text';
  String get move => _el ? 'Μετακίνηση' : 'Move';
  String get editWord => _el ? 'Επεξεργασία λέξης' : 'Edit word';
  String get cancel => _el ? 'Άκυρο' : 'Cancel';
  String get continueLabel => _el ? 'Συνέχεια' : 'Continue';
  String editedUsing(String font) =>
      _el ? 'Επεξεργασία με $font' : 'Edited using $font';
  String get drawSignature => _el ? 'Ζωγραφιστή υπογραφή' : 'Draw signature';
  String get typeSignature => _el ? 'Πληκτρολόγηση υπογραφής' : 'Type signature';
  String get fromPhoto => _el ? 'Από φωτογραφία' : 'From photo';
  String get savedSignatures => _el ? 'Αποθηκευμένες υπογραφές' : 'Saved signatures';
  String get noSavedSignatures =>
      _el ? 'Δεν υπάρχουν αποθηκευμένες υπογραφές.' : 'No saved signatures yet.';
  String get exportAsFile => _el ? 'Εξαγωγή αρχείου' : 'Export as file';
  String get delete => _el ? 'Διαγραφή' : 'Delete';
  String get longPressHint => _el
      ? 'Παρατεταμένο πάτημα για εξαγωγή ή διαγραφή'
      : 'Long-press for export or delete';
  String get signatureAdded => _el ? 'Η υπογραφή προστέθηκε' : 'Signature added';
  String get whichPages => _el ? 'Ποιες σελίδες;' : 'Which pages?';
  String whichPagesBody(int count, int page) => _el
      ? 'Αυτό το PDF έχει $count σελίδες. Όλο το έγγραφο ή μόνο τη σελίδα $page;'
      : 'This PDF has $count pages. Whole document or only page $page?';
  String justPage(int page) => _el ? 'Μόνο σελίδα $page' : 'Just page $page';
  String get wholeDocument => _el ? 'Όλο το έγγραφο' : 'Whole document';
  String get saved => _el ? 'Αποθηκεύτηκε' : 'Saved';
  String get saveCancelled => _el ? 'Η αποθήκευση ακυρώθηκε' : 'Save cancelled';
  String get placeSignature => _el ? 'Τοποθέτηση υπογραφής' : 'Place signature';
  String get place => _el ? 'Τοποθέτηση' : 'Place';
  String get addSignature => _el ? 'Προσθήκη υπογραφής' : 'Add signature';
  String get undo => _el ? 'Αναίρεση' : 'Undo last change';
  String get share => _el ? 'Κοινοποίηση' : 'Share';
  String get save => _el ? 'Αποθήκευση' : 'Save';
  String get savePdf => _el ? 'Αποθήκευση PDF' : 'Save PDF';
  String get saveSignature => _el ? 'Αποθήκευση υπογραφής' : 'Save Signature';
  String get shuffleStyle => _el ? 'Ανακάτεμα στυλ' : 'Shuffle style';
  String get yourNamePlaceholder => _el ? 'Το όνομά σου' : 'Your Name';
  String pageOf(int current, int total) =>
      _el ? 'Σελίδα $current / $total' : 'Page $current / $total';
  String get clear => _el ? 'Καθαρισμός' : 'Clear';
  String get use => _el ? 'Χρήση' : 'Use';
  String get drawFirst =>
      _el ? 'Ζωγράφισε πρώτα την υπογραφή' : 'Draw your signature first';
  String get yourName => _el ? 'Το όνομά σου' : 'Your name';
  String get typeNameFirst =>
      _el ? 'Γράψε πρώτα το όνομά σου' : 'Type your name first';
  String get pickAStyle => _el ? 'Διάλεξε στυλ' : 'Pick a style';
  String get pickAStyleGreek =>
      _el ? 'Διάλεξε στυλ (μόνο με ελληνικά)' : 'Pick a style (Greek-friendly only)';
  String get shuffle => _el ? 'Ανακάτεμα' : 'Shuffle';
  String detected(String info) => _el ? 'Ανιχνεύθηκε: $info' : 'Detected: $info';
  String get bold => _el ? 'Έντονα' : 'Bold';
  String get italic => _el ? 'Πλάγια' : 'Italic';
  String get privacyPolicy => _el ? 'Πολιτική απορρήτου' : 'Privacy policy';
  String get privacyUpdated =>
      _el ? 'Τελευταία ενημέρωση: 18 Σεπτεμβρίου 2026' : 'Last updated: 18 September 2026';
  String get privacyIntro => _el
      ? 'Η Επεξεργασία PDF & Υπογραφή είναι τοπικός επεξεργαστής PDF.'
      : 'Edit PDF Words & Sign is a local PDF editor.';
  String get privacyWhatTitle => _el ? 'Τι κάνει η εφαρμογή' : 'What the app does';
  String get privacyWhatBody => _el
      ? 'Ανοίγεις ένα PDF από τη συσκευή σου, αλλάζεις ή μετακινείς λέξεις και βάζεις υπογραφή. Μπορείς να αποθηκεύσεις ή να κοινοποιήσεις το αποτέλεσμα.'
      : 'You open a PDF from your device, change or move words, and add a signature. You can save or share the result.';
  String get privacyDataTitle => _el ? 'Τι δεδομένα συλλέγουμε' : 'Data we collect';
  String get privacyDataBody => _el
      ? 'Δεν έχουμε διακομιστή. Δεν συλλέγουμε, δεν πουλάμε και δεν στέλνουμε σε εμάς τα αρχεία, τις υπογραφές ή προσωπικά σου δεδομένα.'
      : 'We do not operate a server and we do not collect, sell, or send your files, signatures, or personal data to us.';
  String get privacyBulletFiles => _el
      ? 'Τα PDF και οι φωτογραφίες που διαλέγεις μένουν στη συσκευή (και όπου εσύ επιλέξεις να τα αποθηκεύσεις ή να τα κοινοποιήσεις).'
      : 'PDFs and photos you pick stay on your device (and wherever you choose to save or share them).';
  String get privacyBulletLocal => _el
      ? 'Οι αποθηκευμένες υπογραφές και η γλώσσα φυλάσσονται μόνο στη συσκευή.'
      : 'Saved signatures and language preference are stored only on the device.';
  String get privacyBulletNoAccount => _el
      ? 'Δεν χρειάζεται λογαριασμός και δεν χρησιμοποιούμε διαφημιστικά SDK.'
      : 'The app does not require an account and does not use advertising SDKs.';
  String get privacyPermTitle => _el ? 'Άδειες' : 'Permissions';
  String get privacyPermBody => _el
      ? 'Η εφαρμογή χρησιμοποιεί τους επιλογείς αρχείων και φωτογραφιών του συστήματος. Δεν χρειάζεται συνεχή πρόσβαση στον αποθηκευτικό χώρο.'
      : 'The app uses the system file and photo pickers so you can choose a PDF or a signature image. It does not need continuous access to your storage.';
  String get privacyContactTitle => _el ? 'Επικοινωνία' : 'Contact';
  String get privacyContactBody => _el
      ? 'Για θέματα απορρήτου, επικοινώνησε μέσω της σελίδας της εφαρμογής στο Play Store.'
      : 'For privacy questions, contact the developer through the Play Store listing.';
}

class LanguagePickerButton extends StatelessWidget {
  const LanguagePickerButton({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    if (compact) {
      return IconButton(
        tooltip: s.language,
        icon: const Icon(Icons.language),
        onPressed: () => _pick(context),
      );
    }
    return TextButton.icon(
      onPressed: () => _pick(context),
      icon: const Icon(Icons.language),
      label: Text(s.language),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final controller = LocaleScope.of(context);
    final s = controller.strings;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(s.language),
            ),
            ListTile(
              leading: const Text('EN', style: TextStyle(fontWeight: FontWeight.w700)),
              title: Text(s.english),
              selected: controller.locale.languageCode == 'en',
              onTap: () => Navigator.pop(context, 'en'),
            ),
            ListTile(
              leading: const Text('EL', style: TextStyle(fontWeight: FontWeight.w700)),
              title: Text(s.greek),
              selected: controller.locale.languageCode == 'el',
              onTap: () => Navigator.pop(context, 'el'),
            ),
          ],
        ),
      ),
    );
    if (chosen != null) await controller.setCode(chosen);
  }
}
