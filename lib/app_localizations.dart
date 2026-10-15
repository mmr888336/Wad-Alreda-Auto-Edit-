import 'package:flutter/foundation.dart';

class AppLocalizations {
  AppLocalizations._();

  static final ValueNotifier<String> language =
      ValueNotifier<String>('en');

  static const List<String> supportedLanguages = <String>[
    'en', 'ar', 'es', 'pt', 'fr', 'de', 'it',
    'nl', 'pl', 'sv', 'el', 'ru', 'tr',
  ];

  static bool get isRtl => language.value == 'ar';

  static void setLanguage(String code) {
    language.value = supportedLanguages.contains(code) ? code : 'en';
  }

  static const Map<String, String> _rows = <String, String>{
    'welcomeTagline':
        'Smart editing, clearer audio, and a video ready to publish¦مونتاج ذكي، صوت أوضح، وفيديو جاهز للنشر¦Edición inteligente, audio más claro y vídeo listo para publicar¦Edição inteligente, áudio mais claro e vídeo pronto para publicar¦Montage intelligent, audio plus clair et vidéo prête à publier¦Intelligenter Schnitt, klarerer Ton und ein veröffentlichungsfertiges Video¦Montaggio intelligente, audio più chiaro e video pronto per la pubblicazione¦Slimme montage, helderder geluid en een video die klaar is om te publiceren¦Inteligentny montaż, czystszy dźwięk i film gotowy do publikacji¦Smart redigering, tydligare ljud och en video redo att publiceras¦Έξυπνο μοντάζ, καθαρότερος ήχος και βίντεο έτοιμο για δημοσίευση¦Умный монтаж, чистый звук и видео, готовое к публикации¦Akıllı kurgu, daha net ses ve paylaşılmaya hazır video',
    'prophetBlessings':
        'Send blessings upon the Prophet 🌹 ﷺ¦صلِّ على النبي 🌹 ﷺ¦Envía bendiciones al Profeta 🌹 ﷺ¦Envie bênçãos ao Profeta 🌹 ﷺ¦Priez sur le Prophète 🌹 ﷺ¦Segenswünsche für den Propheten 🌹 ﷺ¦Invia benedizioni al Profeta 🌹 ﷺ¦Stuur zegeningen naar de Profeet 🌹 ﷺ¦Prześlij błogosławieństwa Prorokowi 🌹 ﷺ¦Sänd välsignelser över Profeten 🌹 ﷺ¦Στείλε ευλογίες στον Προφήτη 🌹 ﷺ¦Просите благословения для Пророка 🌹 ﷺ¦Peygamber’e salavat getir 🌹 ﷺ',
    'startNow':
        'Start now¦ابدأ الآن¦Comenzar ahora¦Começar agora¦Commencer¦Jetzt starten¦Inizia ora¦Start nu¦Zacznij teraz¦Starta nu¦Έναρξη τώρα¦Начать¦Şimdi başla',
    'settings':
        'Settings¦الإعدادات¦Ajustes¦Configurações¦Paramètres¦Einstellungen¦Impostazioni¦Instellingen¦Ustawienia¦Inställningar¦Ρυθμίσεις¦Настройки¦Ayarlar',
    'chooseVideo':
        'Choose video¦اختر فيديو¦Elegir vídeo¦Escolher vídeo¦Choisir une vidéo¦Video auswählen¦Scegli video¦Video kiezen¦Wybierz film¦Välj video¦Επιλογή βίντεο¦Выбрать видео¦Video seç',
    'changeVideo':
        'Change video¦تغيير الفيديو¦Cambiar vídeo¦Trocar vídeo¦Changer de vidéo¦Video ändern¦Cambia video¦Video wijzigen¦Zmień film¦Byt video¦Αλλαγή βίντεο¦Изменить видео¦Videoyu değiştir',
    'preparingVideo':
        'Preparing video...¦جاري تجهيز الفيديو...¦Preparando vídeo...¦Preparando vídeo...¦Préparation de la vidéo...¦Video wird vorbereitet...¦Preparazione video...¦Video voorbereiden...¦Przygotowywanie filmu...¦Förbereder video...¦Προετοιμασία βίντεο...¦Подготовка видео...¦Video hazırlanıyor...',
    'startExport':
        'Start editing and export¦ابدأ المونتاج والتصدير¦Iniciar edición y exportar¦Iniciar edição e exportar¦Lancer le montage et exporter¦Bearbeitung und Export starten¦Avvia montaggio ed esportazione¦Montage en export starten¦Rozpocznij montaż i eksport¦Starta redigering och exportera¦Έναρξη μοντάζ και εξαγωγής¦Начать монтаж и экспорт¦Kurguyu ve dışa aktarmayı başlat',
    'adNotice':
        'A rewarded ad appears during export. Export finishes only after the ad completes. Internet is required.¦أثناء التصدير سيظهر إعلان مكافأة ولا يكتمل التصدير إلا بعد انتهائه. يلزم اتصال بالإنترنت.¦Durante la exportación aparecerá un anuncio de recompensa. Se necesita Internet.¦Durante a exportação, será exibido um anúncio de recompensa. É necessária Internet.¦Une publicité récompensée s’affiche pendant l’export. Internet est nécessaire.¦Beim Export wird eine Werbeanzeige gezeigt. Internet ist erforderlich.¦Durante l’esportazione verrà mostrato un annuncio premio. Serve Internet.¦Tijdens het exporteren verschijnt een beloningsadvertentie. Internet is vereist.¦Podczas eksportowania pojawi się reklama z nagrodą. Wymagany jest Internet.¦En belöningsannons visas under exporten. Internet krävs.¦Κατά την εξαγωγή θα εμφανιστεί διαφήμιση ανταμοιβής. Απαιτείται Internet.¦Во время экспорта появится реклама. Требуется Интернет.¦Dışa aktarma sırasında ödüllü reklam gösterilir. İnternet gerekir.',
    'chooseVideoFirst':
        'Choose a video to begin¦اختر فيديو للبدء¦Elige un vídeo para empezar¦Escolha um vídeo para começar¦Choisissez une vidéo pour commencer¦Wähle ein Video zum Starten¦Scegli un video per iniziare¦Kies een video om te beginnen¦Wybierz film, aby rozpocząć¦Välj en video för att börja¦Επίλεξε βίντεο για να ξεκινήσεις¦Выберите видео для начала¦Başlamak için bir video seç',
    'selectedVideo':
        'Selected¦تم اختيار¦Seleccionado¦Selecionado¦Sélectionné¦Ausgewählt¦Selezionato¦Geselecteerd¦Wybrano¦Vald¦Επιλέχθηκε¦Выбрано¦Seçildi',
    'pressStartEditing':
        'Press “Start editing” to continue.¦اضغط «ابدأ المونتاج» للمتابعة.¦Pulsa «Iniciar edición» para continuar.¦Toque em «Iniciar edição» para continuar.¦Appuyez sur « Lancer le montage » pour continuer.¦Tippe auf „Bearbeitung starten“, um fortzufahren.¦Premi «Avvia montaggio» per continuare.¦Druk op ‘Montage starten’ om door te gaan.¦Naciśnij „Rozpocznij montaż”, aby kontynuować.¦Tryck på ”Starta redigering” för att fortsätta.¦Πάτησε «Έναρξη μοντάζ» για συνέχεια.¦Нажмите «Начать монтаж», чтобы продолжить.¦Devam etmek için “Kurguyu başlat” seçeneğine bas.',
    'pickFailedPrefix':
        'Could not choose video: ¦تعذر اختيار الفيديو: ¦No se pudo elegir el vídeo: ¦Não foi possível escolher o vídeo: ¦Impossible de choisir la vidéo : ¦Video konnte nicht ausgewählt werden: ¦Impossibile scegliere il video: ¦Video kiezen mislukt: ¦Nie można wybrać filmu: ¦Det gick inte att välja video: ¦Δεν ήταν δυνατή η επιλογή βίντεο: ¦Не удалось выбрать видео: ¦Video seçilemedi: ',
    'editingStarted':
        'Editing started in the background...¦بدأ المونتاج في الخلفية...¦La edición comenzó en segundo plano...¦A edição começou em segundo plano...¦Le montage a commencé en arrière-plan...¦Die Bearbeitung läuft im Hintergrund...¦Il montaggio è iniziato in background...¦Montage gestart op de achtergrond...¦Montaż rozpoczął się w tle...¦Redigeringen har startat i bakgrunden...¦Το μοντάζ ξεκίνησε στο παρασκήνιο...¦Монтаж запущен в фоне...¦Kurgu arka planda başladı...',
    'adExportStopped':
        'Export stopped because the ad was not completed. Check your internet connection and try again.¦تم إيقاف التصدير لأن الإعلان لم يكتمل. تأكد من الإنترنت ثم حاول مجددًا.¦La exportación se detuvo porque el anuncio no se completó.¦A exportação parou porque o anúncio não foi concluído.¦L’exportation a été arrêtée car la publicité n’a pas été terminée.¦Export abgebrochen, da die Anzeige nicht abgeschlossen wurde.¦Esportazione interrotta perché l’annuncio non è stato completato.¦Export gestopt omdat de advertentie niet is voltooid.¦Eksport zatrzymano, ponieważ reklama nie została ukończona.¦Exporten stoppades eftersom annonsen inte slutfördes.¦Η εξαγωγή σταμάτησε επειδή η διαφήμιση δεν ολοκληρώθηκε.¦Экспорт остановлен: реклама не была завершена.¦Reklam tamamlanmadığı için dışa aktarma durduruldu.',
    'adFinished':
        'Ad completed ✅ Finishing export...¦اكتمل الإعلان ✅ جاري إنهاء التصدير...¦Anuncio completado ✅ Finalizando exportación...¦Anúncio concluído ✅ Finalizando exportação...¦Publicité terminée ✅ Finalisation de l’export...¦Anzeige abgeschlossen ✅ Export wird beendet...¦Annuncio completato ✅ Finalizzazione esportazione...¦Advertentie voltooid ✅ Export afronden...¦Reklama ukończona ✅ Kończenie eksportu...¦Annons klar ✅ Slutför exporten...¦Η διαφήμιση ολοκληρώθηκε ✅ Ολοκλήρωση εξαγωγής...¦Реклама завершена ✅ Завершение экспорта...¦Reklam tamamlandı ✅ Dışa aktarma bitiriliyor...',
    'videoReady':
        'Video ready ✅¦تم تجهيز الفيديو ✅¦Vídeo listo ✅¦Vídeo pronto ✅¦Vidéo prête ✅¦Video fertig ✅¦Video pronto ✅¦Video klaar ✅¦Film gotowy ✅¦Videon är klar ✅¦Το βίντεο είναι έτοιμο ✅¦Видео готово ✅¦Video hazır ✅',
    'duration':
        'Duration¦المدة¦Duración¦Duração¦Durée¦Dauer¦Durata¦Duur¦Czas trwania¦Varaktighet¦Διάρκεια¦Длительность¦Süre',
    'resolution':
        'Resolution¦الدقة¦Resolución¦Resolução¦Résolution¦Auflösung¦Risoluzione¦Resolutie¦Rozdzielczość¦Upplösning¦Ανάλυση¦Разрешение¦Çözünürlük',
    'size':
        'Size¦الحجم¦Tamaño¦Tamanho¦Taille¦Größe¦Dimensione¦Grootte¦Rozmiar¦Storlek¦Μέγεθος¦Размер¦Boyut',
    'notes':
        'Notes¦ملاحظات¦Notas¦Notas¦Remarques¦Hinweise¦Note¦Opmerkingen¦Uwagi¦Anteckningar¦Σημειώσεις¦Примечания¦Notlar',
    'editingError':
        'Editing failed ❌¦حصل خطأ أثناء المونتاج ❌¦Error durante la edición ❌¦Falha na edição ❌¦Échec du montage ❌¦Bearbeitung fehlgeschlagen ❌¦Montaggio non riuscito ❌¦Montage mislukt ❌¦Błąd montażu ❌¦Redigeringen misslyckades ❌¦Αποτυχία μοντάζ ❌¦Ошибка монтажа ❌¦Kurgu başarısız ❌',
    'savingToGallery':
        'Saving video to gallery...¦جاري حفظ الفيديو في معرض الجوال...¦Guardando vídeo en la galería...¦Salvando vídeo na galeria...¦Enregistrement de la vidéo dans la galerie...¦Video wird in der Galerie gespeichert...¦Salvataggio video nella galleria...¦Video opslaan in galerij...¦Zapisywanie filmu w galerii...¦Sparar video i galleriet...¦Αποθήκευση βίντεο στη συλλογή...¦Сохранение видео в галерею...¦Video galeriye kaydediliyor...',
    'galleryPermission':
        'Gallery access was not granted. Allow it in phone settings and try again.¦لم يتم منح صلاحية الوصول إلى المعرض. اسمح بها من إعدادات الجوال ثم حاول مجددًا.¦No se concedió acceso a la galería.¦O acesso à galeria não foi concedido.¦L’accès à la galerie n’a pas été accordé.¦Kein Zugriff auf die Galerie.¦Accesso alla galleria non concesso.¦Geen toegang tot de galerij.¦Nie przyznano dostępu do galerii.¦Åtkomst till galleriet nekades.¦Δεν δόθηκε πρόσβαση στη συλλογή.¦Нет доступа к галерее.¦Galeri erişimi verilmedi.',
    'videoSaved':
        'Video saved to the Wad Alreda Studio album ✅¦تم حفظ الفيديو في المعرض داخل ألبوم Wad Alreda Studio ✅¦Vídeo guardado en el álbum Wad Alreda Studio ✅¦Vídeo salvo no álbum Wad Alreda Studio ✅¦Vidéo enregistrée dans l’album Wad Alreda Studio ✅¦Video im Album Wad Alreda Studio gespeichert ✅¦Video salvato nell’album Wad Alreda Studio ✅¦Video opgeslagen in album Wad Alreda Studio ✅¦Film zapisano w albumie Wad Alreda Studio ✅¦Video sparad i albumet Wad Alreda Studio ✅¦Το βίντεο αποθηκεύτηκε στο άλμπουμ Wad Alreda Studio ✅¦Видео сохранено в альбом Wad Alreda Studio ✅¦Video Wad Alreda Studio albümüne kaydedildi ✅',
    'coverSaved':
        'The cover was saved too.¦وتم حفظ الغلاف أيضًا.¦También se guardó la portada.¦A capa também foi salva.¦La couverture a également été enregistrée.¦Das Cover wurde ebenfalls gespeichert.¦Anche la copertina è stata salvata.¦De omslag is ook opgeslagen.¦Okładka również została zapisana.¦Omslaget sparades också.¦Το εξώφυλλο αποθηκεύτηκε επίσης.¦Обложка также сохранена.¦Kapak da kaydedildi.',
    'coverFailed':
        'Could not save the cover, but the video is saved.¦تعذر حفظ الغلاف، لكن الفيديو محفوظ.¦No se pudo guardar la portada, pero el vídeo está guardado.¦Não foi possível salvar a capa, mas o vídeo foi salvo.¦Impossible d’enregistrer la couverture, mais la vidéo est sauvegardée.¦Cover konnte nicht gespeichert werden, aber das Video ist gespeichert.¦Impossibile salvare la copertina, ma il video è salvato.¦Omslag kon niet worden opgeslagen, maar de video wel.¦Nie udało się zapisać okładki, ale film jest zapisany.¦Omslaget kunde inte sparas, men videon är sparad.¦Δεν αποθηκεύτηκε το εξώφυλλο, αλλά το βίντεο αποθηκεύτηκε.¦Не удалось сохранить обложку, но видео сохранено.¦Kapak kaydedilemedi ancak video kaydedildi.',
    'saveFailedPrefix':
        'Could not save video: ¦تعذر حفظ الفيديو: ¦No se pudo guardar el vídeo: ¦Não foi possível salvar o vídeo: ¦Impossible d’enregistrer la vidéo : ¦Video konnte nicht gespeichert werden: ¦Impossibile salvare il video: ¦Video opslaan mislukt: ¦Nie można zapisać filmu: ¦Det gick inte att spara videon: ¦Δεν ήταν δυνατή η αποθήκευση βίντεο: ¦Не удалось сохранить видео: ¦Video kaydedilemedi: ',
    'shareFailedPrefix':
        'Sharing failed: ¦تعذرت المشاركة: ¦Error al compartir: ¦Falha ao compartilhar: ¦Échec du partage : ¦Teilen fehlgeschlagen: ¦Condivisione non riuscita: ¦Delen mislukt: ¦Nie udało się udostępnić: ¦Det gick inte att dela: ¦Αποτυχία κοινής χρήσης: ¦Не удалось поделиться: ¦Paylaşım başarısız: ',
    'postCopied':
        'Post title, description, and hashtags copied.¦تم نسخ العنوان والوصف والهاشتاقات.¦Se copiaron el título, la descripción y los hashtags.¦Título, descrição e hashtags copiados.¦Titre, description et hashtags copiés.¦Titel, Başlık, açıklama ve hashtagler kopyalandı. ¦Titolo, descrizione e hashtag copiati.¦Titel, beschrijving en hashtags gekopieerd.¦Skopiowano tytuł, opis i hashtagi.¦Titel, beskrivning och hashtaggar kopierade.¦Αντιγράφηκαν τίτλος, περιγραφή και hashtag.¦Заголовок, описание и хештеги скопированы.¦Başlık, açıklama ve hashtag'ler kopyalandı.',
    'saveVideo':
        'Save video to phone¦حفظ الفيديو في الجوال¦Guardar vídeo en el teléfono¦Salvar vídeo no telemóvel¦Enregistrer la vidéo sur le téléphone¦Video auf dem Handy speichern¦Salva video sul telefono¦Video opslaan op telefoon¦Zapisz film w telefonie¦Spara video på telefonen¦Αποθήκευση βίντεο στο κινητό¦Сохранить видео на телефон¦Videoyu telefona kaydet',
    'saving':
        'Saving...¦جاري الحفظ...¦Guardando...¦Salvando...¦Enregistrement...¦Speichern...¦Salvataggio...¦Opslaan...¦Zapisywanie...¦Sparar...¦Αποθήκευση...¦Сохранение...¦Kaydediliyor...',
    'shareVideoCover':
        'Share video and cover¦مشاركة الفيديو والغلاف¦Compartir vídeo y portada¦Compartilhar vídeo e capa¦Partager la vidéo et la couverture¦Video und Cover teilen¦Condividi video e copertina¦Video en omslag delen¦Udostępnij film i okładkę¦Dela video och omslag¦Κοινή χρήση βίντεο και εξωφύλλου¦Поделиться видео и обложкой¦Video ve kapağı paylaş',
    'postDescription':
        'Post description¦وصف المنشور¦Descripción de la publicación¦Descrição da publicação¦Description de la publication¦Beitragsbeschreibung¦Descrizione del post¦Berichtbeschrijving¦Opis posta¦Inläggsbeskrivning¦Описание публикации¦Gönderi açıklaması',
    'copyPost':
        'Copy title and description¦نسخ العنوان والوصف¦Copiar título y descripción¦Copiar título e descrição¦Copier le titre et la description¦Titel und Beschreibung kopieren¦Copia titolo e descrizione¦Titel en beschrijving kopiëren¦Kopiuj tytuł i opis¦Kopiera titel och beskrivning¦Αντιγραφή τίτλου και περιγραφής¦Копировать заголовок и описание¦Başlığı ve açıklamayı kopyala',
    'countryLanguage':
        'Country and language¦الدولة واللغة¦País e idioma¦País e idioma¦Pays et langue¦Land und Sprache¦Paese e lingua¦Land en taal¦Kraj i język¦Land och språk¦Χώρα και γλώσσα¦Страна и язык¦Ülke ve dil',
    'country':
        'Country¦الدولة¦País¦País¦Pays¦Land¦Paese¦Land¦Kraj¦Land¦Χώρα¦Страна¦Ülke',
    'captionLanguage':
        'Caption language¦لغة الكابشن¦Idioma de los subtítulos¦Idioma das legendas¦Langue des sous-titres¦Sprache der Untertitel¦Lingua dei sottotitoli¦Ondertaal¦Język napisów¦Textningsspråk¦Γλώσσα υπότιτλων¦Язык субтитров¦Altyazı dili',
    'aiProviders':
        'AI providers¦مزودو الذكاء الاصطناعي¦Proveedores de IA¦Provedores de IA¦Fournisseurs d’IA¦KI-Anbieter¦Provider IA¦AI-providers¦Dostawcy AI¦AI-leverantörer¦Πάροχοι AI¦Провайдеры ИИ¦Yapay zekâ sağlayıcıları',
    'aiDesc':
        'The app tries configured keys in sequence and moves to another provider if one fails.¦يجرّب التطبيق المفاتيح بالتسلسل وينتقل لمزوّد آخر إذا فشل أحدها.¦La aplicación prueba las claves en orden y cambia de proveedor si una falla.¦O aplicativo testa as chaves em sequência e muda de provedor se uma falhar.¦L’application essaie les clés successivement et change de fournisseur en cas d’échec.¦Die App testet Schlüssel der Reihe nach und wechselt bei Fehlern den Anbieter.¦L’app prova le chiavi in sequenza e cambia provider in caso di errore.¦De app probeert sleutels op volgorde en wisselt van provider bij een fout.¦Aplikacja sprawdza klucze po kolei i zmienia dostawcę w razie błędu.¦Appen testar nycklar i ordning och byter leverantör vid fel.¦Η εφαρμογή δοκιμάζει τα κλειδιά διαδοχικά και αλλάζει πάροχο σε περίπτωση αποτυχίας.¦Приложение проверяет ключи по очереди и меняет провайдера при ошибке.¦Uygulama anahtarları sırayla dener, hata olursa sağlayıcı değiştirir.',
    'geminiKey':
        'Gemini API key¦مفتاح Gemini¦Clave de API de Gemini¦Chave de API do Gemini¦Clé API Gemini¦Gemini-API-Schlüssel¦Chiave API Gemini¦Gemini API-sleutel¦Klucz API Gemini¦Gemini API-nyckel¦Κλειδί API Gemini¦Ключ API Gemini¦Gemini API anahtarı',
    'geminiModel':
        'Gemini model name¦اسم نموذج Gemini¦Nombre del modelo Gemini¦Nome do modelo Gemini¦Nom du modèle Gemini¦Gemini-Modellname¦Nome modello Gemini¦Gemini-modelnaam¦Nazwa modelu Gemini¦Gemini-modellnamn¦Όνομα μοντέλου Gemini¦Название модели Gemini¦Gemini model adı',
    'geminiKey2':
        'Gemini backup key 2 (different project)¦مفتاح Gemini احتياطي 2 (من مشروع مختلف)¦Clave Gemini de respaldo 2¦Chave Gemini reserva 2¦Clé Gemini de secours 2¦Gemini-Ersatzschlüssel 2¦Chiave Gemini di riserva 2¦Gemini-reservesleutel 2¦Zapasowy klucz Gemini 2¦Gemini-reservnyckel 2¦Εφεδρικό κλειδί Gemini 2¦Резервный ключ Gemini 2¦Gemini yedek anahtar 2',
    'geminiKey3':
        'Gemini backup key 3 (different project)¦مفتاح Gemini احتياطي 3 (من مشروع مختلف)¦Clave Gemini de respaldo 3¦Chave Gemini reserva 3¦Clé Gemini de secours 3¦Gemini-Ersatzschlüssel 3¦Chiave Gemini di riserva 3¦Gemini-reservesleutel 3¦Zapasowy klucz Gemini 3¦Gemini-reservnyckel 3¦Εφεδρικό κλειδί Gemini 3¦Резервный ключ Gemini 3¦Gemini yedek anahtar 3',
    'groqKey':
        'Groq API key¦مفتاح Groq¦Clave de API Groq¦Chave de API Groq¦Clé API Groq¦Groq-API-Schlüssel¦Chiave API Groq¦Groq API-sleutel¦Klucz API Groq¦Groq API-nyckel¦Κλειδί API Groq¦Ключ API Groq¦Groq API anahtarı',
    'groqKey2':
        'Groq backup key 2¦مفتاح Groq احتياطي 2¦Clave Groq de respaldo 2¦Chave Groq reserva 2¦Clé Groq de secours 2¦Groq-Ersatzschlüssel 2¦Chiave Groq di riserva 2¦Groq-reservesleutel 2¦Zapasowy klucz Groq 2¦Groq-reservnyckel 2¦Εφεδρικό κλειδί Groq 2¦Резервный ключ Groq 2¦Groq yedek anahtar 2',
    'groqKey3':
        'Groq backup key 3¦مفتاح Groq احتياطي 3¦Clave Groq de respaldo 3¦Chave Groq reserva 3¦Clé Groq de secours 3¦Groq-Ersatzschlüssel 3¦Chiave Groq di riserva 3¦Groq-reservesleutel 3¦Zapasowy klucz Groq 3¦Groq-reservnyckel 3¦Εφεδρικό κλειδί Groq 3¦Groq yedek anahtar 3',
    'mistralKey':
        'Mistral API key¦مفتاح Mistral¦Clave de API Mistral¦Chave de API Mistral¦Clé API Mistral¦Mistral-API-Schlüssel¦Chiave API Mistral¦Mistral API-sleutel¦Klucz API Mistral¦Mistral API-nyckel¦Κλειδί API Mistral¦Ключ API Mistral¦Mistral API anahtarı',
    'mistralKey2':
        'Mistral backup key 2¦مفتاح Mistral احتياطي 2¦Clave Mistral de respaldo 2¦Chave Mistral reserva 2¦Clé Mistral de secours 2¦Mistral-Ersatzschlüssel 2¦Chiave Mistral di riserva 2¦Mistral-reservesleutel 2¦Zapasowy klucz Mistral 2¦Mistral-reservnyckel 2¦Εφεδρικό κλειδί Mistral 2¦Mistral yedek anahtar 2',
    'mistralKey3':
        'Mistral backup key 3¦مفتاح Mistral احتياطي 3¦Clave Mistral de respaldo 3¦Chave Mistral reserva 3¦Clé Mistral de secours 3¦Mistral-Ersatzschlüssel 3¦Chiave Mistral di riserva 3¦Mistral-reservesleutel 3¦Zapasowy klucz Mistral 3¦Mistral-reservnyckel 3¦Εφεδρικό κλειδί Mistral 3¦Mistral yedek anahtar 3',
    'mistralModel':
        'Mistral model name¦اسم نموذج Mistral¦Nombre del modelo Mistral¦Nome do modelo Mistral¦Nom du modèle Mistral¦Mistral-Modellname¦Nome modello Mistral¦Mistral-modelnaam¦Nazwa modelu Mistral¦Mistral-modellnamn¦Όνομα μοντέλου Mistral¦Название модели Mistral¦Mistral model adı',
    'testing':
        'Testing...¦جاري الاختبار...¦Probando...¦Testando...¦Test en cours...¦Test läuft...¦Test in corso...¦Testen...¦Testowanie...¦Testar...¦Δοκιμή...¦Проверка...¦Test ediliyor...',
    'saveTestKeys':
        'Save and test keys¦احفظ واختبر المفاتيح¦Guardar y probar claves¦Salvar e testar chaves¦Enregistrer et tester les clés¦Schlüssel speichern und testen¦Salva e testa le chiavi¦Sleutels opslaan en testen¦Zapisz i przetestuj klucze¦Spara och testa nycklar¦Αποθήκευση και δοκιμή κλειδιών¦Сохранить и проверить ключи¦Anahtarları kaydet ve test et',
    'editingFeatures':
        'Editing features¦ميزات المونتاج¦Funciones de edición¦Recursos de edição¦Fonctions de montage¦Bearbeitungsfunktionen¦Funzioni di montaggio¦Montagefuncties¦Funkcje montażu¦Redigeringsfunktioner¦Λειτουργίες μοντάζ¦Функции монтажа¦Kurgu özellikleri',
    'audioEnhance':
        'Audio enhancement¦تحسين الصوت¦Mejora de audio¦Melhoria de áudio¦Amélioration audio¦Audio verbessern¦Miglioramento audio¦Audio verbeteren¦Poprawa dźwięku¦Ljudförbättring¦Βελτίωση ήχου¦Улучшение звука¦Ses iyileştirme',
    'audioEnhanceDesc':
        'Reduce noise and balance volume¦تقليل الضوضاء وموازنة مستوى الصوت وضغطه¦Reducir ruido y equilibrar volumen¦Reduzir ruído e equilibrar volume¦Réduire le bruit et équilibrer le volume¦Rauschen reduzieren und Lautstärke ausgleichen¦Riduce il rumore e bilancia il volume¦Ruis verminderen en volume balanceren¦Redukcja szumu i wyrównanie głośności¦Minska brus och balansera volym¦Μείωση θορύβου και εξισορρόπηση έντασης¦Снижение шума и выравнивание громкости¦Gürültüyü azalt ve ses seviyesini dengele',
    'visualEffects':
        'Visual enhancements¦تحسينات بصرية¦Mejoras visuales¦Melhorias visuais¦Améliorations visuelles¦Visuelle Verbesserungen¦Miglioramenti visivi¦Visuele verbeteringen¦Ulepszenia obrazu¦Visuella förbättringar¦Οπτικές βελτιώσεις¦Улучшение изображения¦Görsel iyileştirmeler',
    'visualEffectsDesc':
        'Color and visual effects; export may be slower¦ألوان وتأثيرات بصرية (قد تبطّئ التصدير)¦Color y efectos visuales; la exportación puede tardar más¦Cores e efeitos visuais; a exportação pode demorar mais¦Couleurs et effets visuels ; l’export peut être plus lent¦Farben und Effekte; der Export kann langsamer sein¦Colori ed effetti; l’esportazione può essere più lenta¦Kleuren en effecten; exporteren kan langer duren¦Kolory i efekty; eksport może trwać dłużej¦Färger och effekter; exporten kan ta längre tid¦Χρώματα και εφέ· η εξαγωγή μπορεί να καθυστερήσει¦Цвета и эффекты; экспорт может замедлиться¦Renk ve efektler; dışa aktarma yavaşlayabilir',
    'colorStyle':
        'Color style¦نمط الألوان¦Estilo de color¦Estilo de cor¦Style de couleur¦Farbstil¦Stile colore¦Kleurstijl¦Styl kolorów¦Färgstil¦Στυλ χρωμάτων¦Цветовой стиль¦Renk stili',
    'clean':
        'Clean (light contrast)¦نظيف (تباين وحدة خفيفة)¦Limpio (contraste suave)¦Limpo (contraste leve)¦Sobre (contraste léger)¦Klar (leichter Kontrast)¦Pulito (contrasto leggero)¦Schoon (licht contrast)¦Czysty (lekki kontrast)¦Ren (lätt kontrast)¦Καθαρό (ήπια αντίθεση)¦Чистый (мягкий контраст)¦Temiz (hafif kontrast)',
    'cinematic':
        'Cinematic (warm and cool tones)¦سينمائي (ألوان دافئة وباردة + تظليل)¦Cinemático (tonos cálidos y fríos)¦Cinematográfico (tons quentes e frios)¦Cinéma (tons chauds et froids)¦Kinematisch (warme und kühle Töne)¦Cinematografico (toni caldi e freddi)¦Filmisch (warme en koele tinten)¦Filmowy (ciepłe i chłodne tony)¦Filmisk (varma och kalla toner)¦Κινηματογραφικό (θερμοί και ψυχροί τόνοι)¦Кинематографичный (тёплые и холодные тона)¦Sinematik (sıcak ve soğuk tonlar)',
    'vivid':
        'Vivid (stronger colors)¦حيوي (ألوان أقوى)¦Vívido (colores intensos)¦Vivo (cores fortes)¦Vif (couleurs fortes)¦Lebendig (kräftige Farben)¦Vivido (colori intensi)¦Levendig (sterke kleuren)¦Żywy (mocne kolory)¦Livlig (starkare färger)¦Έντονο (ισχυρά χρώματα)¦Яркий (насыщенные цвета)¦Canlı (daha güçlü renkler)',
    'punchZoom':
        'Quick zoom on cuts (Punch-in)¦تقريب سريع عند القطع (Punch-in)¦Zoom rápido en los cortes¦Zoom rápido nos cortes¦Zoom rapide aux coupes¦Schneller Zoom bei Schnitten¦Zoom rapido nei tagli¦Snelle zoom bij cuts¦Szybkie zbliżenie przy cięciu¦Snabb zoom vid klipp¦Γρήγορο ζουμ στις κοπές¦Быстрый зум на склейках¦Kesimlerde hızlı yakınlaştırma',
    'punchZoomDesc':
        'Alternating zoom makes cuts feel intentional¦يكبّر اللقطة بالتناوب ليبدو القطع مقصودًا¦El zoom alterno hace que los cortes parezcan intencionales¦O zoom alternado torna os cortes intencionais¦Le zoom alterné rend les coupes plus intentionnelles¦Abwechselnder Zoom lässt Schnitte bewusster wirken¦Lo zoom alternato rende i tagli intenzionali¦Afwisselende zoom laat cuts doelbewust lijken¦Naprzemienny zoom podkreśla cięcia¦Växlande zoom gör klippen mer avsiktliga¦Το εναλλασσόμενο ζουμ τονίζει τις κοπές¦Чередование зума подчёркивает монтаж¦Dönüşümlü yakınlaştırma kesimleri belirginleştirir',
    'flashTransitions':
        'Flash transition for B-roll¦وميض انتقالي عند B-roll¦Transición con destello para B-roll¦Transição com flash para B-roll¦Transition flash pour le B-roll¦Blitzübergang für B-Roll¦Transizione flash per B-roll¦Flitsovergang voor B-roll¦Błyskowe przejście dla B-roll¦Blixtövergång för B-roll¦Μετάβαση λάμψης για B-roll¦Вспышка-переход для B-roll¦B-roll için flaş geçişi',
    'progressBar':
        'Progress bar at bottom of video¦شريط تقدم أسفل الفيديو¦Barra de progreso inferior¦Barra de progresso na parte inferior¦Barre de progression en bas¦Fortschrittsbalken unten¦Barra di avanzamento in basso¦Voortgangsbalk onderaan¦Pasek postępu na dole¦Förloppsindikator längst ned¦Γραμμή προόδου κάτω¦Полоса прогресса внизу¦Videonun altında ilerleme çubuğu',
    'progressBarDesc':
        'Encourages viewers to finish the video¦يشجع المشاهد على إكمال الفيديو¦Anima a terminar el vídeo¦Incentiva a assistir até o fim¦Encourage à regarder jusqu’au bout¦Motiviert zum vollständigen Ansehen¦Invita a guardare fino alla fine¦Moedigt aan om te blijven kijken¦Zachęca do obejrzenia całości¦Uppmuntrar tittaren att se klart¦Ενθαρρύνει την ολοκλήρωση του βίντεο¦Помогает досмотреть видео¦İzleyiciyi videoyu bitirmeye teşvik eder',
    'captions':
        'Add captions¦إضافة كابشن¦Añadir subtítulos¦Adicionar legendas¦Ajouter des sous-titres¦Untertitel hinzufügen¦Aggiungi sottotitoli¦Ondertiteling toevoegen¦Dodaj napisy¦Lägg till textning¦Προσθήκη υπότιτλων¦Добавить субтитры¦Altyazı ekle',
    'captionsDesc':
        'Turn off if the video already has captions¦عطّله إذا كان الفيديو يحتوي على كابشن جاهز¦Desactívalo si el vídeo ya tiene subtítulos¦Desative se o vídeo já tiver legendas¦Désactivez si la vidéo a déjà des sous-titres¦Deaktivieren, wenn das Video bereits Untertitel hat¦Disattiva se il video ha già sottotitoli¦Schakel uit als de video al ondertiteling heeft¦Wyłącz, jeśli film ma już napisy¦Stäng av om videon redan har textning¦Απενεργοποίησε αν το βίντεο έχει ήδη υπότιτλους¦Отключите, если субтитры уже есть¦Videoda zaten altyazı varsa kapat',
    'hook':
        'Hook title in the first 3 seconds¦عنوان جذاب في أول 3 ثوانٍ¦Título atractivo en los primeros 3 segundos¦Título chamativo nos primeiros 3 segundos¦Titre accrocheur dans les 3 premières secondes¦Aufmerksamkeitsstarker Titel in den ersten 3 Sekunden¦Titolo d’impatto nei primi 3 secondi¦Aantrekkelijke titel in de eerste 3 seconden¦Przyciągający tytuł w pierwszych 3 sekundach¦Fängslande titel under de första 3 sekunderna¦Ελκυστικός τίτλος στα πρώτα 3 δευτερόλεπτα¦Цепляющий заголовок в первые 3 секунды¦İlk 3 saniyede dikkat çekici başlık',
    'broll':
        'B-roll (illustrative clips)¦B-roll (مقاطع توضيحية)¦B-roll (clips ilustrativos)¦B-roll (clipes ilustrativos)¦B-roll (plans d’illustration)¦B-Roll (Ergänzungsclips)¦B-roll (clip illustrativi)¦B-roll (illustratieve clips)¦B-roll (ujęcia ilustracyjne)¦B-roll (illustrativa klipp)¦B-roll (επεξηγηματικά πλάνα)¦B-roll (иллюстративные кадры)¦B-roll (açıklayıcı klipler)',
    'brollDesc':
        'Requires a Pexels or Pixabay key and internet access¦يحتاج مفتاح Pexels أو Pixabay واتصالًا بالإنترنت¦Requiere una clave de Pexels o Pixabay e Internet¦Requer uma chave Pexels ou Pixabay e Internet¦Nécessite une clé Pexels ou Pixabay et Internet¦Benötigt einen Pexels- oder Pixabay-Schlüssel und Internet¦Richiede una chiave Pexels o Pixabay e Internet¦Vereist een Pexels- of Pixabay-sleutel en internet¦Wymaga klucza Pexels lub Pixabay i Internetu¦Kräver Pexels- eller Pixabay-nyckel och internet¦Απαιτεί κλειδί Pexels ή Pixabay και Internet¦Нужен ключ Pexels или Pixabay и интернет¦Pexels veya Pixabay anahtarı ve internet gerekir',
    'sfx':
        'Transition sound effects¦مؤثرات صوتية انتقالية¦Efectos de sonido de transición¦Efeitos sonoros de transição¦Effets sonores de transition¦Übergangs-Soundeffekte¦Effetti sonori di transizione¦Overgangsgeluidseffecten¦Dźwiękowe efekty przejścia¦Övergångsljudeffekter¦Ηχητικά εφέ μετάβασης¦Звуковые эффекты перехода¦Geçiş ses efektleri',
    'brollSource':
        'B-roll source¦مصدر مقاطع B-roll¦Fuente de B-roll¦Fonte de B-roll¦Source B-roll¦B-Roll-Quelle¦Fonte B-roll¦B-roll-bron¦Źródło B-roll¦B-roll-källa¦Πηγή B-roll¦Источник B-roll¦B-roll kaynağı',
    'pexelsKey':
        'Pexels API key¦مفتاح Pexels¦Clave API de Pexels¦Chave API do Pexels¦Clé API Pexels¦Pexels-API-Schlüssel¦Chiave API Pexels¦Pexels API-sleutel¦Klucz API Pexels¦Pexels API-nyckel¦Κλειδί API Pexels¦Ключ API Pexels¦Pexels API anahtarı',
    'pixabayKey':
        'Pixabay API key¦مفتاح Pixabay¦Clave API de Pixabay¦Chave API do Pixabay¦Clé API Pixabay¦Pixabay-API-Schlüssel¦Chiave API Pixabay¦Pixabay API-sleutel¦Klucz API Pixabay¦Pixabay API-nyckel¦Κλειδί API Pixabay¦Ключ API Pixabay¦Pixabay API anahtarı',
    'export':
        'Export¦التصدير¦Exportar¦Exportar¦Exportation¦Export¦Esportazione¦Exporteren¦Eksport¦Exportera¦Εξαγωγή¦Экспорт¦Dışa aktarma',
    'resolution2k':
        '2K resolution¦دقة 2K¦Resolución 2K¦Resolução 2K¦Résolution 2K¦2K-Auflösung¦Risoluzione 2K¦2K-resolutie¦Rozdzielczość 2K¦2K-upplösning¦Ανάλυση 2K¦Разрешение 2K¦2K çözünürlük',
    'resolution2kDesc':
        'Uses more processing time and memory¦تستهلك وقتًا وذاكرة أكبر على الجوال¦Usa más tiempo y memoria¦Usa mais tempo e memória¦Utilise plus de temps et de mémoire¦Benötigt mehr Zeit und Speicher¦Richiede più tempo e memoria¦Gebruikt meer tijd en geheugen¦Zużywa więcej czasu i pamięci¦Använder mer tid och minne¦Χρησιμοποιεί περισσότερο χρόνο και μνήμη¦Требует больше времени и памяти¦Daha fazla işlem süresi ve bellek kullanır',
    'targetSize':
        'Target size: {size} MB per 30 seconds¦الحجم المستهدف: {size} ميجا لكل 30 ثانية¦Tamaño objetivo: {size} MB por 30 segundos¦Tamanho alvo: {size} MB por 30 segundos¦Taille cible : {size} Mo par 30 secondes¦Zielgröße: {size} MB pro 30 Sekunden¦Dimensione obiettivo: {size} MB ogni 30 secondi¦Doelgrootte: {size} MB per 30 seconden¦Docelowy rozmiar: {size} MB na 30 sekund¦Målstorlek: {size} MB per 30 sekunder¦Στόχος μεγέθους: {size} MB ανά 30 δευτερόλεπτα¦Целевой размер: {size} МБ на 30 секунд¦Hedef boyut: 30 saniyede {size} MB',
    'silenceSensitivity':
        'Silence sensitivity: {value} dB¦حساسية السكتة: {value} dB¦Sensibilidad del silencio: {value} dB¦Sensibilidade do silêncio: {value} dB¦Sensibilité du silence : {value} dB¦Stille-Empfindlichkeit: {value} dB¦Sensibilità del silenzio: {value} dB¦Stiltegevoeligheid: {value} dB¦Czułość ciszy: {value} dB¦Tystnadskänslighet: {value} dB¦Ευαισθησία σιωπής: {value} dB¦Чувствительность тишины: {value} дБ¦Sessizlik hassasiyeti: {value} dB',
    'silenceDesc':
        'Lower values cut quiet sounds more aggressively¦القيمة الأقل تقص الأصوات الخافتة أكثر¦Los valores bajos cortan más los sonidos suaves¦Valores menores cortam mais sons baixos¦Les valeurs basses coupent davantage les sons faibles¦Niedrigere Werte schneiden leise Töne stärker¦Valori bassi tagliano maggiormente i suoni deboli¦Lagere waarden knippen zachte geluiden sneller¦Niższe wartości mocniej wycinają ciche dźwięki¦Lägre värden klipper bort fler svaga ljud¦Οι χαμηλότερες τιμές κόβουν περισσότερο τους χαμηλούς ήχους¦Низкие значения сильнее обрезают тихие звуки¦Düşük değerler sessiz sesleri daha fazla keser',
    'minimumSilence':
        'Minimum silence to cut: {value} seconds¦أقل مدة سكتة تُقص: {value} ثانية¦Silencio mínimo que se corta: {value} segundos¦Silêncio mínimo a cortar: {value} segundos¦Silence minimum à couper : {value} secondes¦Mindeststille zum Schneiden: {value} Sekunden¦Silenzio minimo da tagliare: {value} secondi¦Minimale stilte om te knippen: {value} seconden¦Minimalna cisza do wycięcia: {value} sekundy¦Minsta tystnad att klippa: {value} sekunder¦Ελάχιστη σιωπή για αποκοπή: {value} δευτερόλεπτα¦Минимальная тишина для обрезки: {value} сек.¦Kesilecek en kısa sessizlik: {value} saniye',
    'saveSettings':
        'Save settings¦حفظ الإعدادات¦Guardar ajustes¦Salvar configurações¦Enregistrer les paramètres¦Einstellungen speichern¦Salva impostazioni¦Instellingen opslaan¦Zapisz ustawienia¦Spara inställningar¦Αποθήκευση ρυθμίσεων¦Сохранить настройки¦Ayarları kaydet',
    'languageSelect':
        'Choose your language¦اختر لغتك¦Elige tu idioma¦Escolha seu idioma¦Choisissez votre langue¦Wähle deine Sprache¦Scegli la lingua¦Kies je taal¦Wybierz język¦Välj språk¦Επίλεξε γλώσσα¦Выберите язык¦Dilini seç',
    'search':
        'Search¦بحث¦Buscar¦Pesquisar¦Rechercher¦Suchen¦Cerca¦Zoeken¦Szukaj¦Sök¦Αναζήτηση¦Поиск¦Ara',
    'languageSelectDesc':
        'This choice sets the caption language and the app interface. You can change it later in Settings.¦اختيارك يحدد لغة الكابشن وواجهة التطبيق، ويمكن تغييره لاحقًا من الإعدادات.¦Esta opción define el idioma de los subtítulos y de la interfaz.¦Esta opção define o idioma das legendas e da interface.¦Ce choix définit la langue des sous-titres et de l’interface.¦Diese Auswahl bestimmt Untertitel- und Oberflächensprache.¦Questa scelta imposta la lingua dei sottotitoli e dell’interfaccia.¦Deze keuze bepaalt de ondertitelingstaal en de interfacetaal.¦Ten wybór ustawia język napisów i interfejsu.¦Detta val ställer in textningsspråk och gränssnitt.¦Αυτή η επιλογή ορίζει τη γλώσσα υπότιτλων και διεπαφής.¦Этот выбор задаёт язык субтитров и интерфейса.¦Bu seçim altyazı ve arayüz dilini belirler.',
    'continue':
        'Continue¦متابعة¦Continuar¦Continuar¦Continuer¦Weiter¦Continua¦Doorgaan¦Kontynuuj¦Fortsätt¦Συνέχεια¦Продолжить¦Devam et',
    'adBeforeExport':
        'Ad before export¦إعلان قبل التصدير¦Anuncio antes de exportar¦Anúncio antes da exportação¦Publicité avant exportation¦Anzeige vor Export¦Annuncio prima dell’esportazione¦Advertentie vóór export¦Reklama przed eksportem¦Annons före export¦Διαφήμιση πριν από την εξαγωγή¦Реклама перед экспортом¦Dışa aktarmadan önce reklam',
    'adLoading':
       
        'Loading rewarded ad...¦جاري تحميل إعلان المكافأة...¦Cargando anuncio de recompensa...¦Carregando anúncio de recompensa...¦Chargement de la publicité récompensée...¦Belohnungsanzeige wird geladen...¦Caricamento annuncio premio...¦Beloningsadvertentie laden...¦Ładowanie reklamy z nagrodą...¦Laddar belöningsannons...¦Φόρτωση διαφήμισης ανταμοιβής...¦Загрузка рекламы...¦Ödüllü reklam yükleniyor...',
    'adExportStarts':
        'Final export starts after the ad is completed.¦التصدير النهائي يبدأ بعد اكتمال الإعلان.¦La exportación final comienza después del anuncio.¦A exportação final começa após o anúncio.¦L’export final commence après la publicité.¦Der endgültige Export beginnt nach der Anzeige.¦L’esportazione finale inizia dopo l’annuncio.¦De uiteindelijke export begint na de advertentie.¦Eksport końcowy rozpocznie się po reklamie.¦Slutlig export börjar när annonsen är klar.¦Η τελική εξαγωγή αρχίζει μετά τη διαφήμιση.¦Финальный экспорт начнётся после рекламы.¦Son dışa aktarma reklam bitince başlar.',
    'adNotFinished':
        'The ad was not completed. Watch it to the end to export.¦لم يكتمل الإعلان. شاهده حتى النهاية ليتم التصدير.¦El anuncio no se completó. Míralo hasta el final para exportar.¦O anúncio não foi concluído. Assista até o fim para exportar.¦La publicité n’a pas été terminée. Regardez-la jusqu’au bout.¦Die Anzeige wurde nicht abgeschlossen. Sieh sie vollständig an.¦L’annuncio non è stato completato. Guardalo fino alla fine.¦De advertentie is niet voltooid. Bekijk deze helemaal.¦Reklama nie została ukończona. Obejrzyj ją do końca.¦Annonsen slutfördes inte. Se den till slutet.¦Η διαφήμιση δεν ολοκληρώθηκε. Δες την μέχρι το τέλος.¦Реклама не завершена. Досмотрите её до конца.¦Reklam tamamlanmadı. Dışa aktarmak için sonuna kadar izle.',
    'adFailed':

        'Could not show ad. Check internet, disable ad blockers, and try again.¦تعذر عرض الإعلان. افتح الإنترنت وأوقف مانع الإعلانات ثم حاول مرة أخرى.¦No se pudo mostrar el anuncio. Comprueba Internet e inténtalo de nuevo.¦Não foi possível mostrar o anúncio. Verifique a Internet e tente novamente.¦Impossible d’afficher la publicité. Vérifiez Internet et réessayez.¦Anzeige konnte nicht gezeigt werden. Prüfe Internet und versuche es erneut.¦Impossibile mostrare l’annuncio. Controlla Internet e riprova.¦Advertentie kon niet worden getoond. Controleer internet en probeer opnieuw.¦Nie można wyświetlić reklamy. Sprawdź Internet i spróbuj ponownie.¦Annonsen kunde inte visas. Kontrollera internet och försök igen.¦Δεν ήταν δυνατή η εμφάνιση διαφήμισης. Έλεγξε το Internet.¦Не удалось показать рекламу. Проверьте Интернет и повторите попытку.¦Reklam gösterilemedi. İnterneti kontrol edip tekrar dene.',
    'retry':

        'Try again¦حاول تاني¦Intentar de nuevo¦Tentar novamente¦Réessayer¦Erneut versuchen¦Riprova¦Opnieuw proberen¦Spróbuj ponownie¦Försök igen¦Δοκίμασε ξανά¦Повторить¦Tekrar dene',
    'backWithoutExport':
        'Back without export¦رجوع بدون تصدير¦Volver sin exportar¦Voltar sem exportar¦Retour sans exporter¦Zurück ohne Export¦Torna senza esportare¦Terug zonder exporteren¦Wróć bez eksportu¦Tillbaka utan export¦Επιστροφή χωρίς εξαγωγή¦Назад без экспорта¦Dışa aktarmadan dön',
    'processing':
        'Processing video...¦جاري معالجة الفيديو...¦Procesando vídeo...¦Processando vídeo...¦Traitement de la vidéo...¦Video wird verarbeitet...¦Elaborazione video...¦Video verwerken...¦Przetwarzanie filmu...¦Bearbetar video...¦Επεξεργασία βίντεο...¦Обработка видео...¦Video işleniyor...',
  };
static String t(
    String key, {
    Map<String, String> args = const {},
  }) {
    final row = _rows[key];
    if (row == null) return key;

    final values = row.split('¦');
    final index = supportedLanguages.indexOf(language.value);
    var value = values.first;

    if (index >= 0 && index < values.length) {
      value = values[index];
    }

    args.forEach((name, replacement) {
      value = value.replaceAll('{$name}', replacement);
    });

    return value;
  }

  static String runtime(String value) {
if (value.startsWith('@')) {
      return t(value.substring(1));
    }

    const exact = <String, String>{
      'جاري فحص الفيديو...': 'processing',
      'جاري تحليل الصوت...': 'processing',
      'جاري تفريغ الصوت وتحليله بالذكاء الاصطناعي...': 'processing',
      'جاري تجهيز الكابشن...': 'processing',
      'جاري تحميل وفحص B-roll': 'processing',
      'جاري تجهيز الغلاف...': 'processing',
      'جاري التصدير بدون الفلاتر المتقدمة...': 'processing',
      'جاري التصدير البسيط...': 'processing',
    };

    if (exact.containsKey(value)) return t(exact[value]!);
    if (value.startsWith('جاري ')) return t('processing');

    return value;
  }
}
