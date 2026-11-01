import 'system_ui_language.dart';

/// Duo 버디(서버 이름 talk host)와 푸시 받기 시간 문구. 폰 언어로 고르고,
/// 없는 키는 영어로 떨어진다. `{n}`·`{t}`·`{topic}`은 부르는 쪽이 채운다.
class DuoBuddyCopy {
  const DuoBuddyCopy._(this._values);

  final Map<String, String> _values;

  String operator [](String key) => _values[key] ?? _english[key] ?? key;

  String fill(String key, Map<String, String> values) {
    var out = this[key];
    values.forEach((k, v) => out = out.replaceAll('{$k}', v));
    return out;
  }

  String hours(int n) => n <= 0 ? this['pushOff'] : fill('hoursN', {'n': '$n'});

  static DuoBuddyCopy forSystemLocale() =>
      DuoBuddyCopy._(_copies[systemUiLanguageName().trim()] ?? _english);

  static const _english = <String, String>{
    'guestPostedPush':
        'Your invitation stays on the board for {n} h, even with the app closed. When someone taps it you get a notification. Accept it and a 3-minute interpreted call starts.',
    'pushFor': 'Get notified for',
    'pushOff': 'Off',
    'hoursN': '{n} h',
    'pushHint':
        'Even with the app closed, you get a notification when someone taps your invitation.',
    'pushDenied':
        'Notifications are off for StealthVox. Turn them on in your phone settings to get requests while the app is closed.',
    'pushLeft': 'Notifications · {t} left',
    'pushSent':
        'We notified the host. Waiting up to a minute while they open the app…',
    'requesterNoTime':
        'You have no remaining time. Charge time to talk with this person.',
    'buddyTitle': 'Duo Buddy',
    'buddyEntry': 'Talk with people around the world as much as you like',
    'buddyOn': 'Active · {n} h a day',
    'buddyIntro':
        'Duo Buddies keep the open Duo room lively. Your invitation comes back after every call (it is hidden while you talk), there is no daily call limit, and calls do not use your time.',
    'buddyHoursLabel': 'Hours a day you can keep the app on and talk (average)',
    'buddyNext': 'Next',
    'pledgeTitle': 'Good conversation pledge',
    'pledge1':
        'I will be polite and respect people of every country, age and background.',
    'pledge2':
        'I will not use profanity, sexual talk, hate speech or harassment.',
    'pledge3':
        'I will not ask for or share contacts, money or personal information, and I will not promote anything.',
    'pledge4':
        'If I cannot continue, I will end the call politely, and I will report anyone who breaks these rules.',
    'pledge5':
        'I understand that breaking this pledge can end my Duo Buddy role and restrict my account.',
    'pledgeAgree': 'I agree to the pledge',
    'buddyJoin': 'Become a Duo Buddy',
    'buddyJoined':
        'You are a Duo Buddy now. Post an invitation from a Duo room.',
    'buddyLeave': 'Stop being a Duo Buddy',
    'buddyLeft': 'You are no longer a Duo Buddy.',
    'buddyFailed': 'Could not save. Please try again.',
    'buddyAdminDisabled': 'This account cannot be a Duo Buddy.',
    'repostTitle': 'Post your invitation again?',
    'repostBody': 'It goes back on the board with the same topic:\n{topic}',
    'repostConfirm': 'Post again',
    'repostLater': 'Not now',
    'repostDone': 'Your invitation is back on the board.',
    'repostFailed': 'Could not post again. Please post from a Duo room.',
  };

  static const _copies = <String, Map<String, String>>{
    'English': _english,
    'Korean': {
      'guestPostedPush':
          '앱을 닫아도 {n}시간 동안 초대글이 게시판에 남아요. 누군가 누르면 알림이 오고, 수락하면 3분 통역 대화가 시작돼요.',
      'pushFor': '푸시 받기',
      'pushOff': '끄기',
      'hoursN': '{n}시간',
      'pushHint': '앱을 닫아도 누가 내 초대글을 누르면 알림이 와요.',
      'pushDenied':
          'StealthVox 알림이 꺼져 있어요. 앱을 닫은 동안 요청을 받으려면 폰 설정에서 알림을 켜 주세요.',
      'pushLeft': '푸시 · {t} 남음',
      'pushSent': '초대자에게 알림을 보냈어요. 앱을 열 때까지 최대 1분 기다려요…',
      'requesterNoTime': '남은 이용 시간이 없어요. 시간을 충전하면 이분과 대화할 수 있어요.',
      'buddyTitle': 'Duo 버디',
      'buddyEntry': '전 세계 사람들과 마음껏 대화하기',
      'buddyOn': '활동 중 · 하루 {n}시간',
      'buddyIntro':
          'Duo 버디는 열린 Duo 대화방을 지켜 주는 사람이에요. 통화가 끝날 때마다 초대글이 다시 올라가고(통화 중에는 안 보여요), 하루 통화 횟수 제한이 없고, 통화에 내 시간이 들지 않아요.',
      'buddyHoursLabel': '하루 평균 앱을 켜 두고 대화할 수 있는 시간',
      'buddyNext': '다음',
      'pledgeTitle': '건전 대화 서약',
      'pledge1': '나라·나이·배경이 다른 모든 사람을 존중하고 예의 있게 대화합니다.',
      'pledge2': '욕설, 성적인 대화, 혐오 표현, 괴롭힘을 하지 않습니다.',
      'pledge3': '연락처·돈·개인정보를 묻거나 주지 않고, 무엇도 홍보하지 않습니다.',
      'pledge4': '대화를 이어가기 어려우면 정중히 끝내고, 규칙을 어기는 사람은 신고합니다.',
      'pledge5': '서약을 어기면 Duo 버디가 해제되고 계정 이용이 제한될 수 있음을 압니다.',
      'pledgeAgree': '서약에 동의합니다',
      'buddyJoin': 'Duo 버디 되기',
      'buddyJoined': '이제 Duo 버디예요. Duo 방에서 초대글을 올려 주세요.',
      'buddyLeave': 'Duo 버디 그만하기',
      'buddyLeft': 'Duo 버디를 그만두었어요.',
      'buddyFailed': '저장하지 못했어요. 다시 시도해 주세요.',
      'buddyAdminDisabled': '이 계정은 Duo 버디가 될 수 없어요.',
      'repostTitle': '초대글을 다시 올릴까요?',
      'repostBody': '같은 주제로 게시판에 다시 올라가요:\n{topic}',
      'repostConfirm': '다시 올리기',
      'repostLater': '나중에',
      'repostDone': '초대글이 다시 올라갔어요.',
      'repostFailed': '다시 올리지 못했어요. Duo 방에서 올려 주세요.',
    },
    'Japanese': {
      'guestPostedPush':
          'アプリを閉じても{n}時間、招待が掲示板に残ります。誰かがタップすると通知が届き、応答すると3分間の通訳会話が始まります。',
      'pushFor': '通知を受け取る',
      'pushOff': 'オフ',
      'hoursN': '{n}時間',
      'pushHint': 'アプリを閉じていても、誰かが招待をタップすると通知が届きます。',
      'pushDenied':
          'StealthVoxの通知がオフです。アプリを閉じている間もリクエストを受けるには、端末の設定で通知をオンにしてください。',
      'pushLeft': '通知 · 残り{t}',
      'pushSent': '招待者に通知しました。アプリを開くまで最大1分待ちます…',
      'requesterNoTime': '残り時間がありません。チャージするとこの方と話せます。',
      'buddyTitle': 'Duoバディ',
      'buddyEntry': '世界中の人と思いきり話す',
      'buddyOn': '活動中 · 1日{n}時間',
      'buddyIntro':
          'Duoバディはオープンな Duo ルームを盛り上げる人です。通話が終わるたびに招待が再掲載され(通話中は非表示)、1日の通話回数の制限がなく、通話に自分の時間を使いません。',
      'buddyHoursLabel': '1日平均でアプリを開いて話せる時間',
      'buddyNext': '次へ',
      'pledgeTitle': '健全な会話の誓約',
      'pledge1': '国・年齢・背景の違うすべての人を尊重し、礼儀正しく話します。',
      'pledge2': '暴言、性的な会話、ヘイト表現、嫌がらせをしません。',
      'pledge3': '連絡先・お金・個人情報を求めたり渡したりせず、宣伝もしません。',
      'pledge4': '続けられないときは丁寧に終え、ルール違反は通報します。',
      'pledge5': '誓約に違反するとDuoバディが解除され、アカウントが制限される場合があることを理解します。',
      'pledgeAgree': '誓約に同意します',
      'buddyJoin': 'Duoバディになる',
      'buddyJoined': 'Duoバディになりました。Duoルームから招待を投稿してください。',
      'buddyLeave': 'Duoバディをやめる',
      'buddyLeft': 'Duoバディをやめました。',
      'buddyFailed': '保存できませんでした。もう一度お試しください。',
      'buddyAdminDisabled': 'このアカウントはDuoバディになれません。',
      'repostTitle': '招待をもう一度投稿しますか?',
      'repostBody': '同じトピックで掲示板に戻ります:\n{topic}',
      'repostConfirm': 'もう一度投稿',
      'repostLater': 'あとで',
      'repostDone': '招待を再投稿しました。',
      'repostFailed': '再投稿できませんでした。Duoルームから投稿してください。',
    },
    'Chinese': {
      'guestPostedPush': '即使关闭应用，邀请也会在公告板保留{n}小时。有人点击时你会收到通知，接听后开始3分钟翻译对话。',
      'pushFor': '接收通知',
      'pushOff': '关闭',
      'hoursN': '{n}小时',
      'pushHint': '即使关闭应用，有人点击你的邀请时也会收到通知。',
      'pushDenied': 'StealthVox 的通知已关闭。要在关闭应用时接收请求，请在手机设置中开启通知。',
      'pushLeft': '通知 · 剩余{t}',
      'pushSent': '已通知邀请者。等待对方打开应用，最多1分钟…',
      'requesterNoTime': '你没有剩余时间。充值后即可与此人对话。',
      'buddyTitle': 'Duo 伙伴',
      'buddyEntry': '与世界各地的人尽情聊天',
      'buddyOn': '活跃中 · 每天{n}小时',
      'buddyIntro':
          'Duo 伙伴让开放的 Duo 聊天室保持热闹。每次通话结束后邀请会重新发布(通话中不显示)，每天通话次数不限，通话不消耗你的时间。',
      'buddyHoursLabel': '平均每天能开着应用聊天的时间',
      'buddyNext': '下一步',
      'pledgeTitle': '文明对话承诺',
      'pledge1': '我会尊重不同国家、年龄和背景的每个人，礼貌交谈。',
      'pledge2': '我不会说脏话、进行性话题、仇恨言论或骚扰。',
      'pledge3': '我不会索要或提供联系方式、金钱或个人信息，也不做任何推广。',
      'pledge4': '无法继续时我会礼貌结束通话，并举报违反规则的人。',
      'pledge5': '我明白违反承诺可能会被取消 Duo 伙伴资格并限制账号。',
      'pledgeAgree': '我同意此承诺',
      'buddyJoin': '成为 Duo 伙伴',
      'buddyJoined': '你已成为 Duo 伙伴。请在 Duo 房间发布邀请。',
      'buddyLeave': '不再做 Duo 伙伴',
      'buddyLeft': '你已不再是 Duo 伙伴。',
      'buddyFailed': '保存失败，请重试。',
      'buddyAdminDisabled': '此账号不能成为 Duo 伙伴。',
      'repostTitle': '要再次发布邀请吗?',
      'repostBody': '将以相同主题回到公告板:\n{topic}',
      'repostConfirm': '再次发布',
      'repostLater': '以后再说',
      'repostDone': '邀请已重新发布。',
      'repostFailed': '无法重新发布，请在 Duo 房间发布。',
    },
    'Spanish': {
      'guestPostedPush':
          'Tu invitación se queda en el tablón {n} h, aunque cierres la app. Cuando alguien la toque recibirás un aviso; acepta y empieza una llamada interpretada de 3 minutos.',
      'pushFor': 'Recibir avisos durante',
      'pushOff': 'No',
      'hoursN': '{n} h',
      'pushHint':
          'Aunque cierres la app, te avisamos cuando alguien toque tu invitación.',
      'pushDenied':
          'Las notificaciones de StealthVox están desactivadas. Actívalas en los ajustes del teléfono para recibir solicitudes con la app cerrada.',
      'pushLeft': 'Avisos · quedan {t}',
      'pushSent':
          'Avisamos al anfitrión. Esperamos hasta un minuto a que abra la app…',
      'requesterNoTime':
          'No te queda tiempo. Recarga tiempo para hablar con esta persona.',
      'buddyTitle': 'Duo Buddy',
      'buddyEntry': 'Habla todo lo que quieras con gente de todo el mundo',
      'buddyOn': 'Activo · {n} h al día',
      'buddyIntro':
          'Los Duo Buddies mantienen viva la sala abierta de Duo. Tu invitación vuelve después de cada llamada (se oculta mientras hablas), no hay límite diario de llamadas y no gastan tu tiempo.',
      'buddyHoursLabel':
          'Horas al día que puedes tener la app abierta y hablar (promedio)',
      'buddyNext': 'Siguiente',
      'pledgeTitle': 'Compromiso de buena conversación',
      'pledge1':
          'Seré amable y respetaré a personas de cualquier país, edad y origen.',
      'pledge2':
          'No usaré insultos, conversación sexual, discurso de odio ni acoso.',
      'pledge3':
          'No pediré ni daré contactos, dinero ni datos personales, y no promocionaré nada.',
      'pledge4':
          'Si no puedo seguir, terminaré la llamada con educación y denunciaré a quien rompa las reglas.',
      'pledge5':
          'Entiendo que romper este compromiso puede quitarme el rol de Duo Buddy y limitar mi cuenta.',
      'pledgeAgree': 'Acepto el compromiso',
      'buddyJoin': 'Ser Duo Buddy',
      'buddyJoined':
          'Ya eres Duo Buddy. Publica una invitación desde una sala Duo.',
      'buddyLeave': 'Dejar de ser Duo Buddy',
      'buddyLeft': 'Ya no eres Duo Buddy.',
      'buddyFailed': 'No se pudo guardar. Inténtalo de nuevo.',
      'buddyAdminDisabled': 'Esta cuenta no puede ser Duo Buddy.',
      'repostTitle': '¿Publicar tu invitación de nuevo?',
      'repostBody': 'Vuelve al tablón con el mismo tema:\n{topic}',
      'repostConfirm': 'Publicar de nuevo',
      'repostLater': 'Ahora no',
      'repostDone': 'Tu invitación volvió al tablón.',
      'repostFailed': 'No se pudo publicar. Publica desde una sala Duo.',
    },
    'French': {
      'guestPostedPush':
          'Votre invitation reste sur le tableau {n} h, même app fermée. Quand quelqu’un la touche, vous recevez une notification ; acceptez et un appel interprété de 3 minutes démarre.',
      'pushFor': 'Recevoir les notifications pendant',
      'pushOff': 'Non',
      'hoursN': '{n} h',
      'pushHint':
          'Même app fermée, vous êtes averti quand quelqu’un touche votre invitation.',
      'pushDenied':
          'Les notifications de StealthVox sont désactivées. Activez-les dans les réglages du téléphone pour recevoir des demandes app fermée.',
      'pushLeft': 'Notifications · encore {t}',
      'pushSent':
          'L’hôte a été averti. On attend jusqu’à une minute qu’il ouvre l’app…',
      'requesterNoTime':
          'Il ne vous reste plus de temps. Rechargez pour parler avec cette personne.',
      'buddyTitle': 'Duo Buddy',
      'buddyEntry': 'Parlez autant que vous voulez avec le monde entier',
      'buddyOn': 'Actif · {n} h par jour',
      'buddyIntro':
          'Les Duo Buddies font vivre la salle ouverte Duo. Votre invitation revient après chaque appel (cachée pendant l’appel), sans limite d’appels par jour, et les appels n’utilisent pas votre temps.',
      'buddyHoursLabel':
          'Heures par jour où vous pouvez garder l’app ouverte et parler (moyenne)',
      'buddyNext': 'Suivant',
      'pledgeTitle': 'Engagement de bonne conversation',
      'pledge1':
          'Je serai poli et respecterai les gens de tout pays, âge et origine.',
      'pledge2':
          'Je n’utiliserai ni insultes, ni propos sexuels, ni discours haineux, ni harcèlement.',
      'pledge3':
          'Je ne demanderai ni ne donnerai de contacts, d’argent ou d’informations personnelles, et je ne ferai aucune promotion.',
      'pledge4':
          'Si je ne peux pas continuer, je terminerai poliment et je signalerai qui enfreint les règles.',
      'pledge5':
          'Je comprends qu’enfreindre cet engagement peut mettre fin à mon rôle de Duo Buddy et limiter mon compte.',
      'pledgeAgree': 'J’accepte l’engagement',
      'buddyJoin': 'Devenir Duo Buddy',
      'buddyJoined':
          'Vous êtes Duo Buddy. Publiez une invitation depuis une salle Duo.',
      'buddyLeave': 'Ne plus être Duo Buddy',
      'buddyLeft': 'Vous n’êtes plus Duo Buddy.',
      'buddyFailed': 'Enregistrement impossible. Réessayez.',
      'buddyAdminDisabled': 'Ce compte ne peut pas être Duo Buddy.',
      'repostTitle': 'Republier votre invitation ?',
      'repostBody': 'Elle revient sur le tableau avec le même sujet :\n{topic}',
      'repostConfirm': 'Republier',
      'repostLater': 'Plus tard',
      'repostDone': 'Votre invitation est de retour sur le tableau.',
      'repostFailed': 'Impossible de republier. Publiez depuis une salle Duo.',
    },
    'German': {
      'guestPostedPush':
          'Deine Einladung bleibt {n} Std. auf dem Board, auch bei geschlossener App. Tippt jemand darauf, bekommst du eine Benachrichtigung; nimm an und ein 3-minütiges Dolmetschgespräch beginnt.',
      'pushFor': 'Benachrichtigungen für',
      'pushOff': 'Aus',
      'hoursN': '{n} Std.',
      'pushHint':
          'Auch bei geschlossener App wirst du benachrichtigt, wenn jemand deine Einladung antippt.',
      'pushDenied':
          'Benachrichtigungen für StealthVox sind aus. Schalte sie in den Telefoneinstellungen ein, um Anfragen bei geschlossener App zu erhalten.',
      'pushLeft': 'Benachrichtigungen · noch {t}',
      'pushSent':
          'Der Gastgeber wurde benachrichtigt. Wir warten bis zu einer Minute, bis er die App öffnet…',
      'requesterNoTime':
          'Du hast keine Zeit mehr. Lade Zeit auf, um mit dieser Person zu sprechen.',
      'buddyTitle': 'Duo Buddy',
      'buddyEntry': 'Sprich so viel du willst mit Menschen aus aller Welt',
      'buddyOn': 'Aktiv · {n} Std. pro Tag',
      'buddyIntro':
          'Duo Buddies halten den offenen Duo-Raum lebendig. Deine Einladung kommt nach jedem Anruf zurück (während des Gesprächs ausgeblendet), es gibt kein Tageslimit und Anrufe verbrauchen nicht deine Zeit.',
      'buddyHoursLabel':
          'Stunden pro Tag, die du die App offen hältst und sprichst (Durchschnitt)',
      'buddyNext': 'Weiter',
      'pledgeTitle': 'Versprechen für gute Gespräche',
      'pledge1':
          'Ich bin höflich und respektiere Menschen jedes Landes, Alters und Hintergrunds.',
      'pledge2':
          'Ich benutze keine Beleidigungen, sexuellen Gespräche, Hassrede oder Belästigung.',
      'pledge3':
          'Ich frage nicht nach Kontakten, Geld oder persönlichen Daten, gebe sie nicht weiter und mache keine Werbung.',
      'pledge4':
          'Wenn ich nicht weitermachen kann, beende ich höflich und melde Regelverstöße.',
      'pledge5':
          'Mir ist klar, dass ein Verstoß meine Rolle als Duo Buddy beenden und mein Konto einschränken kann.',
      'pledgeAgree': 'Ich stimme dem Versprechen zu',
      'buddyJoin': 'Duo Buddy werden',
      'buddyJoined':
          'Du bist jetzt Duo Buddy. Veröffentliche eine Einladung aus einem Duo-Raum.',
      'buddyLeave': 'Kein Duo Buddy mehr sein',
      'buddyLeft': 'Du bist kein Duo Buddy mehr.',
      'buddyFailed': 'Speichern fehlgeschlagen. Bitte erneut versuchen.',
      'buddyAdminDisabled': 'Dieses Konto kann kein Duo Buddy sein.',
      'repostTitle': 'Einladung erneut veröffentlichen?',
      'repostBody': 'Sie kommt mit demselben Thema zurück aufs Board:\n{topic}',
      'repostConfirm': 'Erneut veröffentlichen',
      'repostLater': 'Später',
      'repostDone': 'Deine Einladung ist wieder auf dem Board.',
      'repostFailed':
          'Erneutes Veröffentlichen fehlgeschlagen. Bitte aus einem Duo-Raum posten.',
    },
    'Hindi': {
      'guestPostedPush':
          'ऐप बंद होने पर भी आपका निमंत्रण {n} घंटे बोर्ड पर रहेगा। कोई टैप करे तो सूचना आएगी; स्वीकार करते ही 3 मिनट की अनुवादित बातचीत शुरू होगी।',
      'pushFor': 'सूचना पाएँ',
      'pushOff': 'बंद',
      'hoursN': '{n} घंटे',
      'pushHint': 'ऐप बंद होने पर भी कोई आपका निमंत्रण टैप करे तो सूचना आएगी।',
      'pushDenied':
          'StealthVox की सूचनाएँ बंद हैं। ऐप बंद रहते अनुरोध पाने के लिए फ़ोन सेटिंग में सूचनाएँ चालू करें।',
      'pushLeft': 'सूचना · {t} बाकी',
      'pushSent': 'होस्ट को सूचना भेज दी। ऐप खुलने तक एक मिनट तक इंतज़ार…',
      'requesterNoTime':
          'आपका समय खत्म है। इस व्यक्ति से बात करने के लिए समय रिचार्ज करें।',
      'buddyTitle': 'Duo Buddy',
      'buddyEntry': 'दुनिया भर के लोगों से जी भर कर बात करें',
      'buddyOn': 'सक्रिय · रोज़ {n} घंटे',
      'buddyIntro':
          'Duo Buddy खुले Duo रूम को जीवंत रखते हैं। हर कॉल के बाद आपका निमंत्रण फिर से आता है (बात करते समय छिपा रहता है), रोज़ कॉल की कोई सीमा नहीं, और कॉल में आपका समय खर्च नहीं होता।',
      'buddyHoursLabel': 'रोज़ औसतन कितने घंटे ऐप खुला रखकर बात कर सकते हैं',
      'buddyNext': 'आगे',
      'pledgeTitle': 'अच्छी बातचीत की शपथ',
      'pledge1':
          'मैं हर देश, उम्र और पृष्ठभूमि के लोगों का सम्मान करूँगा और विनम्र रहूँगा।',
      'pledge2': 'मैं गाली, यौन बातें, नफ़रत भरी भाषा या उत्पीड़न नहीं करूँगा।',
      'pledge3':
          'मैं संपर्क, पैसे या निजी जानकारी नहीं माँगूँगा या दूँगा, और कुछ भी प्रचार नहीं करूँगा।',
      'pledge4':
          'जारी न रख सकूँ तो विनम्रता से कॉल खत्म करूँगा और नियम तोड़ने वालों की रिपोर्ट करूँगा।',
      'pledge5':
          'मैं समझता हूँ कि शपथ तोड़ने पर Duo Buddy भूमिका खत्म और खाता सीमित हो सकता है।',
      'pledgeAgree': 'मैं शपथ से सहमत हूँ',
      'buddyJoin': 'Duo Buddy बनें',
      'buddyJoined': 'अब आप Duo Buddy हैं। Duo रूम से निमंत्रण पोस्ट करें।',
      'buddyLeave': 'Duo Buddy छोड़ें',
      'buddyLeft': 'आप अब Duo Buddy नहीं हैं।',
      'buddyFailed': 'सहेजा नहीं जा सका। फिर कोशिश करें।',
      'buddyAdminDisabled': 'यह खाता Duo Buddy नहीं बन सकता।',
      'repostTitle': 'निमंत्रण फिर से पोस्ट करें?',
      'repostBody': 'उसी विषय के साथ बोर्ड पर वापस आएगा:\n{topic}',
      'repostConfirm': 'फिर से पोस्ट करें',
      'repostLater': 'अभी नहीं',
      'repostDone': 'आपका निमंत्रण फिर बोर्ड पर है।',
      'repostFailed': 'फिर से पोस्ट नहीं हो सका। Duo रूम से पोस्ट करें।',
    },
    'Russian': {
      'guestPostedPush':
          'Ваше приглашение останется на доске {n} ч, даже при закрытом приложении. Когда кто-то нажмёт, придёт уведомление; примите, и начнётся 3-минутный переводной разговор.',
      'pushFor': 'Уведомления на',
      'pushOff': 'Выкл.',
      'hoursN': '{n} ч',
      'pushHint':
          'Даже при закрытом приложении вы получите уведомление, когда кто-то нажмёт на ваше приглашение.',
      'pushDenied':
          'Уведомления StealthVox выключены. Включите их в настройках телефона, чтобы получать запросы при закрытом приложении.',
      'pushLeft': 'Уведомления · осталось {t}',
      'pushSent':
          'Мы уведомили хозяина. Ждём до минуты, пока он откроет приложение…',
      'requesterNoTime':
          'У вас не осталось времени. Пополните время, чтобы поговорить с этим человеком.',
      'buddyTitle': 'Duo Buddy',
      'buddyEntry': 'Общайтесь сколько хотите с людьми со всего мира',
      'buddyOn': 'Активен · {n} ч в день',
      'buddyIntro':
          'Duo Buddy поддерживают жизнь в открытой комнате Duo. Ваше приглашение возвращается после каждого звонка (во время разговора скрыто), дневного лимита звонков нет, и звонки не тратят ваше время.',
      'buddyHoursLabel':
          'Сколько часов в день вы можете держать приложение открытым и говорить (в среднем)',
      'buddyNext': 'Далее',
      'pledgeTitle': 'Обязательство вежливого общения',
      'pledge1':
          'Я буду вежлив и буду уважать людей любой страны, возраста и происхождения.',
      'pledge2':
          'Я не буду использовать мат, сексуальные разговоры, язык ненависти и травлю.',
      'pledge3':
          'Я не буду просить или давать контакты, деньги или личные данные и ничего не буду рекламировать.',
      'pledge4':
          'Если не смогу продолжать, вежливо закончу звонок и пожалуюсь на нарушителей.',
      'pledge5':
          'Я понимаю, что нарушение может лишить меня роли Duo Buddy и ограничить аккаунт.',
      'pledgeAgree': 'Я принимаю обязательство',
      'buddyJoin': 'Стать Duo Buddy',
      'buddyJoined':
          'Теперь вы Duo Buddy. Опубликуйте приглашение из комнаты Duo.',
      'buddyLeave': 'Перестать быть Duo Buddy',
      'buddyLeft': 'Вы больше не Duo Buddy.',
      'buddyFailed': 'Не удалось сохранить. Попробуйте ещё раз.',
      'buddyAdminDisabled': 'Этот аккаунт не может быть Duo Buddy.',
      'repostTitle': 'Опубликовать приглашение снова?',
      'repostBody': 'Оно вернётся на доску с той же темой:\n{topic}',
      'repostConfirm': 'Опубликовать снова',
      'repostLater': 'Не сейчас',
      'repostDone': 'Ваше приглашение снова на доске.',
      'repostFailed': 'Не удалось опубликовать. Опубликуйте из комнаты Duo.',
    },
    'Portuguese': {
      'guestPostedPush':
          'Seu convite fica no mural por {n} h, mesmo com o app fechado. Quando alguém tocar, você recebe um aviso; aceite e começa uma chamada interpretada de 3 minutos.',
      'pushFor': 'Receber avisos por',
      'pushOff': 'Não',
      'hoursN': '{n} h',
      'pushHint':
          'Mesmo com o app fechado, você recebe um aviso quando alguém toca no seu convite.',
      'pushDenied':
          'As notificações do StealthVox estão desligadas. Ative-as nas configurações do telefone para receber pedidos com o app fechado.',
      'pushLeft': 'Avisos · faltam {t}',
      'pushSent':
          'Avisamos o anfitrião. Esperando até um minuto ele abrir o app…',
      'requesterNoTime':
          'Você não tem tempo restante. Recarregue para conversar com esta pessoa.',
      'buddyTitle': 'Duo Buddy',
      'buddyEntry': 'Converse à vontade com pessoas do mundo todo',
      'buddyOn': 'Ativo · {n} h por dia',
      'buddyIntro':
          'Os Duo Buddies mantêm a sala aberta do Duo viva. Seu convite volta após cada chamada (fica oculto enquanto você fala), não há limite diário de chamadas e elas não gastam o seu tempo.',
      'buddyHoursLabel':
          'Horas por dia que você pode deixar o app aberto e conversar (média)',
      'buddyNext': 'Próximo',
      'pledgeTitle': 'Compromisso de boa conversa',
      'pledge1':
          'Serei educado e respeitarei pessoas de qualquer país, idade e origem.',
      'pledge2':
          'Não usarei palavrões, conversa sexual, discurso de ódio nem assédio.',
      'pledge3':
          'Não pedirei nem darei contatos, dinheiro ou dados pessoais, e não promoverei nada.',
      'pledge4':
          'Se não puder continuar, encerrarei com educação e denunciarei quem quebrar as regras.',
      'pledge5':
          'Entendo que quebrar este compromisso pode encerrar meu papel de Duo Buddy e limitar minha conta.',
      'pledgeAgree': 'Aceito o compromisso',
      'buddyJoin': 'Ser Duo Buddy',
      'buddyJoined':
          'Agora você é Duo Buddy. Publique um convite a partir de uma sala Duo.',
      'buddyLeave': 'Deixar de ser Duo Buddy',
      'buddyLeft': 'Você não é mais Duo Buddy.',
      'buddyFailed': 'Não foi possível salvar. Tente de novo.',
      'buddyAdminDisabled': 'Esta conta não pode ser Duo Buddy.',
      'repostTitle': 'Publicar seu convite de novo?',
      'repostBody': 'Ele volta ao mural com o mesmo tema:\n{topic}',
      'repostConfirm': 'Publicar de novo',
      'repostLater': 'Agora não',
      'repostDone': 'Seu convite voltou ao mural.',
      'repostFailed':
          'Não foi possível publicar. Publique a partir de uma sala Duo.',
    },
    'Italian': {
      'guestPostedPush':
          'Il tuo invito resta in bacheca per {n} h, anche con l’app chiusa. Quando qualcuno lo tocca ricevi una notifica; accetta e parte una chiamata interpretata di 3 minuti.',
      'pushFor': 'Ricevi notifiche per',
      'pushOff': 'No',
      'hoursN': '{n} h',
      'pushHint':
          'Anche con l’app chiusa ricevi una notifica quando qualcuno tocca il tuo invito.',
      'pushDenied':
          'Le notifiche di StealthVox sono disattivate. Attivale nelle impostazioni del telefono per ricevere richieste ad app chiusa.',
      'pushLeft': 'Notifiche · ancora {t}',
      'pushSent':
          'Abbiamo avvisato l’host. Aspettiamo fino a un minuto che apra l’app…',
      'requesterNoTime':
          'Non hai più tempo. Ricarica per parlare con questa persona.',
      'buddyTitle': 'Duo Buddy',
      'buddyEntry': 'Parla quanto vuoi con persone di tutto il mondo',
      'buddyOn': 'Attivo · {n} h al giorno',
      'buddyIntro':
          'I Duo Buddy tengono viva la stanza aperta Duo. Il tuo invito torna dopo ogni chiamata (nascosto mentre parli), non c’è limite giornaliero e le chiamate non usano il tuo tempo.',
      'buddyHoursLabel':
          'Ore al giorno in cui puoi tenere l’app aperta e parlare (media)',
      'buddyNext': 'Avanti',
      'pledgeTitle': 'Impegno per una buona conversazione',
      'pledge1':
          'Sarò cortese e rispetterò persone di ogni paese, età e provenienza.',
      'pledge2':
          'Non userò insulti, discorsi sessuali, linguaggio d’odio o molestie.',
      'pledge3':
          'Non chiederò né darò contatti, denaro o dati personali e non promuoverò nulla.',
      'pledge4':
          'Se non posso continuare chiuderò con cortesia e segnalerò chi infrange le regole.',
      'pledge5':
          'So che violare l’impegno può togliermi il ruolo di Duo Buddy e limitare il mio account.',
      'pledgeAgree': 'Accetto l’impegno',
      'buddyJoin': 'Diventa Duo Buddy',
      'buddyJoined': 'Ora sei Duo Buddy. Pubblica un invito da una stanza Duo.',
      'buddyLeave': 'Smetti di essere Duo Buddy',
      'buddyLeft': 'Non sei più Duo Buddy.',
      'buddyFailed': 'Impossibile salvare. Riprova.',
      'buddyAdminDisabled': 'Questo account non può essere Duo Buddy.',
      'repostTitle': 'Pubblicare di nuovo l’invito?',
      'repostBody': 'Torna in bacheca con lo stesso argomento:\n{topic}',
      'repostConfirm': 'Pubblica di nuovo',
      'repostLater': 'Non ora',
      'repostDone': 'Il tuo invito è di nuovo in bacheca.',
      'repostFailed': 'Impossibile pubblicare. Pubblica da una stanza Duo.',
    },
    'Dutch': {
      'guestPostedPush':
          'Je uitnodiging blijft {n} u op het bord staan, ook met gesloten app. Tikt iemand erop, dan krijg je een melding; accepteer en een tolkgesprek van 3 minuten begint.',
      'pushFor': 'Meldingen voor',
      'pushOff': 'Uit',
      'hoursN': '{n} u',
      'pushHint':
          'Ook als de app dicht is krijg je een melding wanneer iemand op je uitnodiging tikt.',
      'pushDenied':
          'Meldingen van StealthVox staan uit. Zet ze aan in je telefooninstellingen om verzoeken te krijgen als de app dicht is.',
      'pushLeft': 'Meldingen · nog {t}',
      'pushSent':
          'We hebben de gastheer gemeld. We wachten tot een minuut tot de app opent…',
      'requesterNoTime':
          'Je hebt geen tijd meer. Laad tijd op om met deze persoon te praten.',
      'buddyTitle': 'Duo Buddy',
      'buddyEntry': 'Praat zoveel je wilt met mensen over de hele wereld',
      'buddyOn': 'Actief · {n} u per dag',
      'buddyIntro':
          'Duo Buddies houden de open Duo-ruimte levendig. Je uitnodiging komt na elk gesprek terug (verborgen tijdens het praten), er is geen daglimiet en gesprekken kosten jouw tijd niet.',
      'buddyHoursLabel':
          'Uren per dag dat je de app open kunt houden en praten (gemiddeld)',
      'buddyNext': 'Volgende',
      'pledgeTitle': 'Belofte voor goede gesprekken',
      'pledge1':
          'Ik ben beleefd en respecteer mensen van elk land, elke leeftijd en achtergrond.',
      'pledge2':
          'Ik gebruik geen scheldwoorden, seksuele praat, haatzaaiende taal of intimidatie.',
      'pledge3':
          'Ik vraag of geef geen contactgegevens, geld of persoonlijke informatie en maak geen reclame.',
      'pledge4':
          'Kan ik niet verder, dan sluit ik beleefd af en meld ik wie de regels breekt.',
      'pledge5':
          'Ik begrijp dat het breken van deze belofte mijn Duo Buddy-rol kan beëindigen en mijn account kan beperken.',
      'pledgeAgree': 'Ik ga akkoord met de belofte',
      'buddyJoin': 'Duo Buddy worden',
      'buddyJoined':
          'Je bent nu Duo Buddy. Plaats een uitnodiging vanuit een Duo-ruimte.',
      'buddyLeave': 'Stoppen als Duo Buddy',
      'buddyLeft': 'Je bent geen Duo Buddy meer.',
      'buddyFailed': 'Opslaan mislukt. Probeer het opnieuw.',
      'buddyAdminDisabled': 'Dit account kan geen Duo Buddy zijn.',
      'repostTitle': 'Uitnodiging opnieuw plaatsen?',
      'repostBody':
          'Ze komt terug op het bord met hetzelfde onderwerp:\n{topic}',
      'repostConfirm': 'Opnieuw plaatsen',
      'repostLater': 'Niet nu',
      'repostDone': 'Je uitnodiging staat weer op het bord.',
      'repostFailed': 'Opnieuw plaatsen mislukt. Plaats vanuit een Duo-ruimte.',
    },
  };
}
