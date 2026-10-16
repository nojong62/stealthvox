import 'package:flutter/foundation.dart';
import 'duo_invite_localization.dart';

class DuoBoardIntroNoticeCopy {
  const DuoBoardIntroNoticeCopy({
    required this.title,
    required this.body,
    required this.cancel,
    required this.openBoard,
  });

  final String title;
  final String body;
  final String cancel;
  final String openBoard;

  static DuoBoardIntroNoticeCopy forSystemLocale() => forLanguageCode(
        PlatformDispatcher.instance.locale.languageCode,
      );

  static DuoBoardIntroNoticeCopy forLanguageCode(String languageCode) =>
      _copies[languageCode.trim().toLowerCase()] ?? _copies['en']!;

  static const _copies = <String, DuoBoardIntroNoticeCopy>{
    'ko': DuoBoardIntroNoticeCopy(
      title: 'Duo 통역 게시판 안내',
      body: '누구나 게시판에서 마음에 드는 주제를 올린 회원과 10분 동안 대화할 수 있습니다.\n\n'
          '대화하고 싶은 초대글을 누른 다음, 언어 설정에서 Chat Lang을 실제로 대화할 언어로 선택해 주세요. AI 통역을 통해 서로 다른 언어로도 자연스럽게 대화할 수 있습니다.\n\n'
          '대화 내용은 공부방에 저장되며, 회원은 저장된 대화를 대화 연습 자료로 활용할 수 있습니다.\n\n'
          '공개 Duo 초대는 언어 연습을 위한 대화입니다. 게시된 주제와 동떨어진 이야기나 비속어 등으로 상대방을 불쾌하게 하지 않도록 배려해 주세요.',
      cancel: '취소',
      openBoard: '게시판 보기',
    ),
    'en': DuoBoardIntroNoticeCopy(
      title: 'About the Duo Interpreter Board',
      body:
          'Anyone can have a 10-minute conversation with a member whose topic they like.\n\n'
          'Tap an invitation you want to join, then set Chat Lang in the language settings to the language you will speak. AI interpretation lets both people communicate naturally even when they use different languages.\n\n'
          'The conversation is saved in the Study Room. Members can use the saved conversation as speaking-practice material.\n\n'
          'Public Duo invitations are for language-practice conversations. Please stay on the posted topic and avoid profanity or other language that could make the other person uncomfortable.',
      cancel: 'Cancel',
      openBoard: 'View board',
    ),
    'ja': DuoBoardIntroNoticeCopy(
      title: 'Duo通訳掲示板のご案内',
      body: '掲示板で気になる話題を投稿した会員と、どなたでも10分間会話できます。\n\n'
          '参加したい招待をタップし、言語設定のChat Langを実際に話す言語に設定してください。AI通訳により、異なる言語でも自然に会話できます。\n\n'
          '会話内容は学習ルームに保存されます。会員は保存された会話をスピーキング練習教材として利用できます。\n\n'
          '公開Duo招待は語学練習のための会話です。投稿されたテーマから大きく外れた話や暴言・不適切な言葉で相手を不快にさせないよう、ご配慮ください。',
      cancel: 'キャンセル',
      openBoard: '掲示板を見る',
    ),
    'zh': DuoBoardIntroNoticeCopy(
      title: 'Duo 口译公告板说明',
      body: '任何人都可以与发布了感兴趣话题的会员进行10分钟对话。\n\n'
          '点击想参加的邀请，然后在语言设置中将 Chat Lang 设为您实际要使用的语言。通过 AI 口译，即使双方使用不同语言也能自然交流。\n\n'
          '对话内容会保存到学习室。会员可以将保存的对话用作口语练习资料。\n\n'
          '公开的 Duo 邀请用于语言练习对话。请围绕发布的主题交流，并避免使用脏话或其他可能让对方感到不适的言语。',
      cancel: '取消',
      openBoard: '查看公告板',
    ),
    'es': DuoBoardIntroNoticeCopy(
      title: 'Acerca del tablón de intérprete Duo',
      body:
          'Cualquier persona puede conversar durante 10 minutos con un miembro cuyo tema le interese.\n\n'
          'Toca la invitación a la que quieras unirte y configura Chat Lang con el idioma que vas a hablar. La interpretación con IA permite conversar con naturalidad aunque uséis idiomas diferentes.\n\n'
          'La conversación se guarda en la Sala de estudio. Los miembros pueden usarla como material para practicar conversación.\n\n'
          'Las invitaciones públicas de Duo son para practicar idiomas. Mantén la conversación en el tema publicado y evita insultos u otras expresiones que puedan incomodar a la otra persona.',
      cancel: 'Cancelar',
      openBoard: 'Ver tablón',
    ),
    'fr': DuoBoardIntroNoticeCopy(
      title: 'À propos du tableau d’interprétation Duo',
      body:
          'Tout le monde peut discuter pendant 10 minutes avec un membre dont le sujet lui plaît.\n\n'
          'Touchez l’invitation qui vous intéresse, puis choisissez dans Chat Lang la langue que vous parlerez. L’interprétation par IA permet de converser naturellement même dans des langues différentes.\n\n'
          'La conversation est enregistrée dans la salle d’étude. Les membres peuvent l’utiliser comme support d’entraînement oral.\n\n'
          'Les invitations Duo publiques sont destinées à la pratique des langues. Restez dans le sujet publié et évitez les grossièretés ou tout propos susceptible de mettre l’autre personne mal à l’aise.',
      cancel: 'Annuler',
      openBoard: 'Voir le tableau',
    ),
    'de': DuoBoardIntroNoticeCopy(
      title: 'Über das Duo-Dolmetscherboard',
      body:
          'Jeder kann zehn Minuten lang mit einem Mitglied sprechen, dessen Thema ihm gefällt.\n\n'
          'Tippe auf eine passende Einladung und stelle Chat Lang auf die Sprache ein, die du sprechen wirst. Die KI-Übersetzung ermöglicht eine natürliche Unterhaltung auch in unterschiedlichen Sprachen.\n\n'
          'Das Gespräch wird im Lernraum gespeichert. Mitglieder können es als Material für Sprechübungen verwenden.\n\n'
          'Öffentliche Duo-Einladungen sind für Gespräche zum Sprachenüben gedacht. Bleibe beim veröffentlichten Thema und vermeide Schimpfwörter oder andere Äußerungen, die dein Gegenüber unangenehm berühren könnten.',
      cancel: 'Abbrechen',
      openBoard: 'Board ansehen',
    ),
    'hi': DuoBoardIntroNoticeCopy(
      title: 'Duo दुभाषिया बोर्ड के बारे में',
      body:
          'कोई भी व्यक्ति अपनी पसंद के विषय वाले सदस्य के साथ 10 मिनट बातचीत कर सकता है।\n\n'
          'जिस निमंत्रण में आपकी रुचि हो उसे टैप करें, फिर भाषा सेटिंग में Chat Lang को उस भाषा पर सेट करें जिसमें आप बोलेंगे। AI दुभाषिया अलग-अलग भाषाओं में भी सहज बातचीत संभव बनाता है।\n\n'
          'बातचीत स्टडी रूम में सहेजी जाती है। सदस्य इसे बोलने के अभ्यास की सामग्री के रूप में उपयोग कर सकते हैं।\n\n'
          'सार्वजनिक Duo निमंत्रण भाषा-अभ्यास की बातचीत के लिए हैं। पोस्ट किए गए विषय पर रहें और गाली-गलौज या ऐसी भाषा से बचें जिससे दूसरे व्यक्ति को असहज महसूस हो।',
      cancel: 'रद्द करें',
      openBoard: 'बोर्ड देखें',
    ),
    'ru': DuoBoardIntroNoticeCopy(
      title: 'О доске переводчика Duo',
      body:
          'Любой пользователь может десять минут поговорить с участником, тема которого ему интересна.\n\n'
          'Нажмите на подходящее приглашение и выберите в Chat Lang язык, на котором будете говорить. ИИ-перевод позволяет свободно общаться даже на разных языках.\n\n'
          'Разговор сохраняется в учебной комнате. Участники могут использовать его как материал для разговорной практики.\n\n'
          'Публичные приглашения Duo предназначены для языковой практики. Придерживайтесь заявленной темы и избегайте ругательств и других выражений, которые могут вызвать у собеседника дискомфорт.',
      cancel: 'Отмена',
      openBoard: 'Открыть доску',
    ),
    'pt': DuoBoardIntroNoticeCopy(
      title: 'Sobre o mural de intérprete Duo',
      body:
          'Qualquer pessoa pode conversar por 10 minutos com um membro cujo tema lhe interesse.\n\n'
          'Toque no convite desejado e defina Chat Lang como o idioma que você vai falar. A interpretação por IA permite conversar naturalmente mesmo usando idiomas diferentes.\n\n'
          'A conversa é salva na Sala de Estudos. Os membros podem usá-la como material para praticar conversação.\n\n'
          'Os convites públicos do Duo são destinados à prática de idiomas. Mantenha a conversa no tema publicado e evite palavrões ou outras falas que possam deixar a outra pessoa desconfortável.',
      cancel: 'Cancelar',
      openBoard: 'Ver mural',
    ),
    'it': DuoBoardIntroNoticeCopy(
      title: 'Informazioni sulla bacheca interprete Duo',
      body:
          'Chiunque può conversare per 10 minuti con un membro il cui argomento è di suo interesse.\n\n'
          'Tocca l’invito che preferisci e imposta Chat Lang sulla lingua che parlerai. L’interpretazione IA consente di comunicare naturalmente anche usando lingue diverse.\n\n'
          'La conversazione viene salvata nella Sala studio. I membri possono usarla come materiale per esercitarsi nel parlato.\n\n'
          'Gli inviti Duo pubblici sono destinati alla pratica linguistica. Rimani sul tema pubblicato ed evita parolacce o altre espressioni che potrebbero mettere a disagio l’altra persona.',
      cancel: 'Annulla',
      openBoard: 'Vedi bacheca',
    ),
    'nl': DuoBoardIntroNoticeCopy(
      title: 'Over het Duo-tolkenbord',
      body:
          'Iedereen kan tien minuten praten met een lid van wie het onderwerp aanspreekt.\n\n'
          'Tik op een uitnodiging waaraan je wilt deelnemen en stel Chat Lang in op de taal die je gaat spreken. Dankzij AI-vertolking kun je ook met verschillende talen natuurlijk met elkaar praten.\n\n'
          'Het gesprek wordt opgeslagen in de studieruimte. Leden kunnen het opgeslagen gesprek gebruiken als oefenmateriaal voor spreekvaardigheid.\n\n'
          'Openbare Duo-uitnodigingen zijn bedoeld voor taalgesprekken. Blijf bij het geplaatste onderwerp en vermijd scheldwoorden of andere taal die de ander een ongemakkelijk gevoel kan geven.',
      cancel: 'Annuleren',
      openBoard: 'Bord bekijken',
    ),
  };
}

/// Login-independent copy for the second Intro page.
///
/// This page is shown before the member has chosen an in-app language, so the
/// phone's system locale is authoritative. Unsupported locales fall back to
/// English.
class DuoBoardGuidePageCopy {
  DuoBoardGuidePageCopy._();

  static Map<String, String> forSystemLocale() {
    final code = PlatformDispatcher.instance.locale.languageCode.toLowerCase();
    final base = _copies[code] ?? _copies['en']!;
    return <String, String>{
      ...base,
      'step5Body': DuoInviteCopy.forSystemLocale()['sameOriginDirect'],
    };
  }

  static const _copies = <String, Map<String, String>>{
    'ko': {
      'back': '뒤로',
      'login': '로그인',
      'headline': '회원의 Duo 초대에\n참여하세요',
      'browse': 'Duo 초대글 보기',
      'step1Title': '회원 초대글 둘러보기',
      'step1Body': '회원들이 대화하고 싶은 주제를 올립니다.',
      'step2Title': '참여 요청 보내기',
      'step2Body': '원하는 주제를 골라 글을 올린 회원에게 참여를 요청하세요.',
      'step3Title': 'AI 통역으로 대화하기',
      'step3Body':
          '수락되면 각자 자기 언어로 말할 수 있습니다. 초대글을 올린 회원만 과금되며, 게시판에서 참여한 사람은 과금되지 않습니다.',
      'step4Title': '회원으로 복습하기',
      'step4Body': '로그인 회원은 저장된 대화를 공부방에서 다시 볼 수 있습니다.',
      'step5Title': 'Origin이 같으면 직접 통화',
      'findAccount': '로그인 방법이 기억나지 않나요? 계정 찾기',
      'phoneSetup': '휴대폰을 바꿨다면 계정을 찾기 전에 새 휴대폰에서 Google 계정과 카카오톡 설정을 완료해 주세요.',
      'microphone': '마이크 접근 권한이 필요합니다.',
      'swipeBack': '밀어서 이전으로',
    },
    'en': {
      'back': 'Back',
      'login': 'Log In',
      'headline': 'Join a Member from\nthe Duo Board',
      'browse': 'Browse Duo Invitations',
      'step1Title': 'Browse Member Invitations',
      'step1Body':
          'Members post the conversation topics they want to talk about.',
      'step2Title': 'Request to Join',
      'step2Body':
          'Choose a topic and send a join request to the member who posted it.',
      'step3Title': 'Talk with AI Interpretation',
      'step3Body':
          'Once accepted, each person can speak their own language. The member who posted the invitation is billed; the person joining from the board is not.',
      'step4Title': 'Review as a Member',
      'step4Body':
          'Signed-in members can revisit the saved conversation in the Study Room.',
      'step5Title': 'Direct Calls for Matching Origin',
      'findAccount': 'Forgot how you logged in? Find Your Account',
      'phoneSetup':
          'If you changed phones, finish setting up your Google Account and KakaoTalk on your new phone before trying to find your account.',
      'microphone': 'Microphone access is required.',
      'swipeBack': 'Swipe to Go Back',
    },
    'ja': {
      'back': '戻る',
      'login': 'ログイン',
      'headline': 'Duo掲示板から\n会員の招待に参加',
      'browse': 'Duoの招待を見る',
      'step1Title': '会員の招待を見る',
      'step1Body': '会員が話したいテーマを投稿しています。',
      'step2Title': '参加をリクエスト',
      'step2Body': '興味のあるテーマを選び、投稿した会員に参加をリクエストします。',
      'step3Title': 'AI通訳で会話',
      'step3Body':
          '承認されると、それぞれ自分の言語で話せます。料金は招待を投稿した会員にのみ発生し、掲示板から参加する人には発生しません。',
      'step4Title': '会員として復習',
      'step4Body': 'ログインした会員は、保存された会話を学習ルームで見直せます。',
      'step5Title': 'Originが同じなら直接通話',
      'findAccount': 'ログイン方法を忘れましたか？ アカウントを探す',
      'phoneSetup': '機種変更した場合は、アカウントを探す前に新しい端末でGoogleアカウントとカカオトークの設定を完了してください。',
      'microphone': 'マイクへのアクセスが必要です。',
      'swipeBack': 'スワイプして戻る',
    },
    'zh': {
      'back': '返回',
      'login': '登录',
      'headline': '从Duo公告板\n加入会员邀请',
      'browse': '浏览Duo邀请',
      'step1Title': '浏览会员邀请',
      'step1Body': '会员会发布他们想聊的话题。',
      'step2Title': '申请加入',
      'step2Body': '选择感兴趣的话题，并向发布该话题的会员发送加入申请。',
      'step3Title': '通过AI口译对话',
      'step3Body': '对方接受后，双方都可以使用自己的语言。费用仅由发布邀请的会员承担，从公告板加入的人不会被收费。',
      'step4Title': '会员复习',
      'step4Body': '已登录会员可以在学习室中重新查看保存的对话。',
      'step5Title': 'Origin 相同时直接通话',
      'findAccount': '忘记登录方式？查找账户',
      'phoneSetup': '如果更换了手机，请先在新手机上完成Google账户和KakaoTalk设置，再尝试查找账户。',
      'microphone': '需要麦克风权限。',
      'swipeBack': '滑动返回',
    },
    'es': {
      'back': 'Atrás',
      'login': 'Iniciar sesión',
      'headline': 'Únete a un miembro\ndesde el tablón Duo',
      'browse': 'Ver invitaciones Duo',
      'step1Title': 'Explora invitaciones',
      'step1Body':
          'Los miembros publican los temas sobre los que quieren hablar.',
      'step2Title': 'Solicita unirte',
      'step2Body':
          'Elige un tema y envía una solicitud al miembro que lo publicó.',
      'step3Title': 'Habla con interpretación por IA',
      'step3Body':
          'Tras la aceptación, cada persona puede hablar su idioma. Paga el miembro que publicó la invitación; quien se une desde el tablón no paga.',
      'step4Title': 'Repasa como miembro',
      'step4Body':
          'Los miembros con sesión iniciada pueden revisar la conversación guardada en la Sala de estudio.',
      'step5Title': 'Llamada directa con el mismo Origin',
      'findAccount': '¿Olvidaste cómo iniciaste sesión? Busca tu cuenta',
      'phoneSetup':
          'Si cambiaste de teléfono, configura tu cuenta de Google y KakaoTalk en el nuevo dispositivo antes de buscar tu cuenta.',
      'microphone': 'Se necesita acceso al micrófono.',
      'swipeBack': 'Desliza para volver',
    },
    'fr': {
      'back': 'Retour',
      'login': 'Connexion',
      'headline': 'Rejoignez un membre\ndepuis le tableau Duo',
      'browse': 'Voir les invitations Duo',
      'step1Title': 'Parcourez les invitations',
      'step1Body':
          'Les membres publient les sujets dont ils souhaitent parler.',
      'step2Title': 'Demandez à participer',
      'step2Body':
          'Choisissez un sujet et envoyez une demande au membre qui l’a publié.',
      'step3Title': 'Discutez avec l’interprétation IA',
      'step3Body':
          'Après acceptation, chacun parle sa langue. Le membre ayant publié l’invitation est facturé ; la personne qui rejoint depuis le tableau ne l’est pas.',
      'step4Title': 'Révisez en tant que membre',
      'step4Body':
          'Les membres connectés peuvent revoir la conversation enregistrée dans la salle d’étude.',
      'step5Title': 'Appel direct avec le même Origin',
      'findAccount':
          'Vous avez oublié votre mode de connexion ? Trouver votre compte',
      'phoneSetup':
          'Si vous avez changé de téléphone, configurez votre compte Google et KakaoTalk sur le nouvel appareil avant de rechercher votre compte.',
      'microphone': 'L’accès au microphone est requis.',
      'swipeBack': 'Balayez pour revenir',
    },
    'de': {
      'back': 'Zurück',
      'login': 'Anmelden',
      'headline': 'Tritt einem Mitglied\nüber das Duo-Board bei',
      'browse': 'Duo-Einladungen ansehen',
      'step1Title': 'Einladungen durchsuchen',
      'step1Body':
          'Mitglieder veröffentlichen Themen, über die sie sprechen möchten.',
      'step2Title': 'Teilnahme anfragen',
      'step2Body':
          'Wähle ein Thema und sende dem Mitglied, das es veröffentlicht hat, eine Anfrage.',
      'step3Title': 'Mit KI-Dolmetscher sprechen',
      'step3Body':
          'Nach der Annahme spricht jeder seine eigene Sprache. Bezahlt wird vom Mitglied, das die Einladung veröffentlicht hat; der Beitretende zahlt nichts.',
      'step4Title': 'Als Mitglied wiederholen',
      'step4Body':
          'Angemeldete Mitglieder können das gespeicherte Gespräch im Lernraum erneut ansehen.',
      'step5Title': 'Direktanruf bei gleichem Origin',
      'findAccount': 'Anmeldeart vergessen? Konto finden',
      'phoneSetup':
          'Richte nach einem Handywechsel zuerst dein Google-Konto und KakaoTalk auf dem neuen Gerät ein, bevor du dein Konto suchst.',
      'microphone': 'Mikrofonzugriff ist erforderlich.',
      'swipeBack': 'Zum Zurückgehen wischen',
    },
    'hi': {
      'back': 'वापस',
      'login': 'लॉग इन',
      'headline': 'Duo बोर्ड से\nकिसी सदस्य से जुड़ें',
      'browse': 'Duo आमंत्रण देखें',
      'step1Title': 'सदस्य आमंत्रण देखें',
      'step1Body':
          'सदस्य उन विषयों को पोस्ट करते हैं जिन पर वे बात करना चाहते हैं।',
      'step2Title': 'जुड़ने का अनुरोध करें',
      'step2Body':
          'कोई विषय चुनें और उसे पोस्ट करने वाले सदस्य को अनुरोध भेजें।',
      'step3Title': 'AI दुभाषिए के साथ बात करें',
      'step3Body':
          'स्वीकार होने पर दोनों अपनी भाषा में बोल सकते हैं। शुल्क आमंत्रण पोस्ट करने वाले सदस्य से लिया जाता है; बोर्ड से जुड़ने वाले से नहीं।',
      'step4Title': 'सदस्य के रूप में दोहराएँ',
      'step4Body':
          'लॉग-इन सदस्य सहेजी गई बातचीत को स्टडी रूम में फिर देख सकते हैं।',
      'step5Title': 'समान Origin पर सीधी कॉल',
      'findAccount': 'लॉग इन करने का तरीका भूल गए? अपना खाता खोजें',
      'phoneSetup':
          'फ़ोन बदलने पर खाता खोजने से पहले नए फ़ोन में Google खाता और KakaoTalk सेट करें।',
      'microphone': 'माइक्रोफ़ोन की अनुमति आवश्यक है।',
      'swipeBack': 'वापस जाने के लिए स्वाइप करें',
    },
    'ru': {
      'back': 'Назад',
      'login': 'Войти',
      'headline': 'Присоединяйтесь\nчерез доску Duo',
      'browse': 'Открыть приглашения Duo',
      'step1Title': 'Просмотрите приглашения',
      'step1Body': 'Участники публикуют темы, которые хотят обсудить.',
      'step2Title': 'Отправьте запрос',
      'step2Body':
          'Выберите тему и отправьте запрос участнику, который её опубликовал.',
      'step3Title': 'Общайтесь с ИИ-переводом',
      'step3Body':
          'После принятия каждый говорит на своём языке. Платит участник, разместивший приглашение; присоединившийся через доску не платит.',
      'step4Title': 'Повторяйте как участник',
      'step4Body':
          'Вошедшие участники могут просмотреть сохранённый разговор в учебной комнате.',
      'step5Title': 'Прямой звонок при одинаковом Origin',
      'findAccount': 'Забыли способ входа? Найти аккаунт',
      'phoneSetup':
          'После смены телефона настройте аккаунт Google и KakaoTalk на новом устройстве, прежде чем искать аккаунт.',
      'microphone': 'Требуется доступ к микрофону.',
      'swipeBack': 'Проведите, чтобы вернуться',
    },
    'pt': {
      'back': 'Voltar',
      'login': 'Entrar',
      'headline': 'Participe com um membro\npelo mural Duo',
      'browse': 'Ver convites Duo',
      'step1Title': 'Explore os convites',
      'step1Body':
          'Os membros publicam os assuntos sobre os quais querem conversar.',
      'step2Title': 'Peça para participar',
      'step2Body':
          'Escolha um assunto e envie um pedido ao membro que o publicou.',
      'step3Title': 'Converse com interpretação por IA',
      'step3Body':
          'Após a aceitação, cada pessoa fala seu idioma. A cobrança é feita ao membro que publicou o convite; quem entra pelo mural não paga.',
      'step4Title': 'Revise como membro',
      'step4Body':
          'Membros conectados podem rever a conversa salva na Sala de Estudos.',
      'step5Title': 'Chamada direta com o mesmo Origin',
      'findAccount': 'Esqueceu como entrou? Encontre sua conta',
      'phoneSetup':
          'Se trocou de telefone, configure sua Conta do Google e o KakaoTalk no novo aparelho antes de procurar sua conta.',
      'microphone': 'É necessário acesso ao microfone.',
      'swipeBack': 'Deslize para voltar',
    },
    'it': {
      'back': 'Indietro',
      'login': 'Accedi',
      'headline': 'Unisciti a un membro\ndalla bacheca Duo',
      'browse': 'Vedi gli inviti Duo',
      'step1Title': 'Sfoglia gli inviti',
      'step1Body': 'I membri pubblicano gli argomenti di cui vogliono parlare.',
      'step2Title': 'Chiedi di partecipare',
      'step2Body':
          'Scegli un argomento e invia una richiesta al membro che lo ha pubblicato.',
      'step3Title': 'Parla con l’interpretazione IA',
      'step3Body':
          'Dopo l’accettazione, ognuno parla la propria lingua. Paga il membro che ha pubblicato l’invito; chi entra dalla bacheca non paga.',
      'step4Title': 'Ripassa come membro',
      'step4Body':
          'I membri che hanno effettuato l’accesso possono rivedere la conversazione salvata nella Sala studio.',
      'step5Title': 'Chiamata diretta con lo stesso Origin',
      'findAccount':
          'Hai dimenticato come hai effettuato l’accesso? Trova il tuo account',
      'phoneSetup':
          'Se hai cambiato telefono, configura l’Account Google e KakaoTalk sul nuovo dispositivo prima di cercare il tuo account.',
      'microphone': 'È necessario l’accesso al microfono.',
      'swipeBack': 'Scorri per tornare indietro',
    },
    'nl': {
      'back': 'Terug',
      'login': 'Inloggen',
      'headline': 'Praat met een lid\nvia het Duo-bord',
      'browse': 'Duo-uitnodigingen bekijken',
      'step1Title': 'Bekijk uitnodigingen',
      'step1Body': 'Leden plaatsen onderwerpen waarover ze willen praten.',
      'step2Title': 'Vraag om deelname',
      'step2Body':
          'Kies een onderwerp en stuur een verzoek naar het lid dat het plaatste.',
      'step3Title': 'Praat met AI-vertolking',
      'step3Body':
          'Na acceptatie spreekt ieder zijn eigen taal. Het lid dat de uitnodiging plaatste betaalt; wie via het bord deelneemt niet.',
      'step4Title': 'Herhaal als lid',
      'step4Body':
          'Ingelogde leden kunnen het opgeslagen gesprek opnieuw bekijken in de studieruimte.',
      'step5Title': 'Direct bellen met dezelfde Origin',
      'findAccount': 'Vergeten hoe je inlogde? Zoek je account',
      'phoneSetup':
          'Stel na een telefoonwissel eerst je Google-account en KakaoTalk in op het nieuwe toestel voordat je je account zoekt.',
      'microphone': 'Microfoontoegang is vereist.',
      'swipeBack': 'Veeg om terug te gaan',
    },
  };
}

/// Login-independent copy for the first Intro page. It follows the phone's
/// system locale because the member has not selected an in-app language yet.
class IntroWelcomePageCopy {
  IntroWelcomePageCopy._();

  static Map<String, String> forSystemLocale() {
    final code = PlatformDispatcher.instance.locale.languageCode.toLowerCase();
    return _copies[code] ?? _copies['en']!;
  }

  static const Map<String, Map<String, String>> _copies = {
    'en': {
      'tagline': 'Speak freely, Pick it up naturally',
      'headlineBefore': 'Your ',
      'headlineAccent': 'Story',
      'headlineAfter': ' Becomes\nLanguage.',
      'duoInvite': 'Duo Invite',
      'loginOrJoin': 'Login or Join',
      'swipeContinue': 'Swipe to Continue',
      'studyTrial': 'Try the Study Room',
      'studyTrialUsed': 'This phone has already used the trial.',
      'studyTrialUnavailable': "The trial isn't ready yet. Please try again later.",
      'studyTrialFailed': "Couldn't start the trial. Please try again."
    },
    'ko': {
      'tagline': '자유롭게 말하고, 자연스럽게 익히세요',
      'headlineBefore': '같이,\n얘기하실래요?',
      'headlineAccent': '',
      'headlineAfter': '',
      'duoInvite': 'Duo 초대',
      'loginOrJoin': '로그인 또는 가입',
      'swipeContinue': '스와이프하여 계속',
      'studyTrial': '공부방 체험',
      'studyTrialUsed': '이 폰에서는 이미 체험했어요.',
      'studyTrialUnavailable': '체험 대화를 준비 중이에요. 잠시 후 다시 시도해 주세요.',
      'studyTrialFailed': '체험을 시작하지 못했어요. 다시 시도해 주세요.'
    },
    'ja': {
      'tagline': '自由に話して、自然に身につけよう',
      'headlineBefore': 'あなたの ',
      'headlineAccent': '物語',
      'headlineAfter': 'が言語になります。',
      'duoInvite': 'Duo 招待',
      'loginOrJoin': 'ログイン・新規登録',
      'swipeContinue': 'スワイプして続ける',
      'studyTrial': '学習ルーム体験',
      'studyTrialUsed': 'この端末ではすでに体験済みです。',
      'studyTrialUnavailable': '体験の準備中です。しばらくしてからお試しください。',
      'studyTrialFailed': '体験を開始できませんでした。もう一度お試しください。'
    },
    'zh': {
      'tagline': '自在开口，自然习得',
      'headlineBefore': '你的 ',
      'headlineAccent': '故事',
      'headlineAfter': '会成为语言。',
      'duoInvite': 'Duo 邀请',
      'loginOrJoin': '登录或注册',
      'swipeContinue': '滑动以继续',
      'studyTrial': '体验学习室',
      'studyTrialUsed': '此手机已体验过。',
      'studyTrialUnavailable': '体验内容准备中，请稍后再试。',
      'studyTrialFailed': '无法开始体验，请重试。'
    },
    'es': {
      'tagline': 'Habla con libertad, aprende de forma natural',
      'headlineBefore': 'Tu ',
      'headlineAccent': 'historia',
      'headlineAfter': ' se convierte\nen idioma.',
      'duoInvite': 'Invitación Duo',
      'loginOrJoin': 'Iniciar sesión o unirse',
      'swipeContinue': 'Desliza para continuar',
      'studyTrial': 'Prueba la sala de estudio',
      'studyTrialUsed': 'Este teléfono ya usó la prueba.',
      'studyTrialUnavailable': 'La prueba aún no está lista. Inténtalo más tarde.',
      'studyTrialFailed': 'No se pudo iniciar la prueba. Inténtalo de nuevo.'
    },
    'fr': {
      'tagline': 'Parlez librement, apprenez naturellement',
      'headlineBefore': 'Votre ',
      'headlineAccent': 'histoire',
      'headlineAfter': ' devient\nlangue.',
      'duoInvite': 'Invitation Duo',
      'loginOrJoin': 'Se connecter ou s’inscrire',
      'swipeContinue': 'Balayez pour continuer',
      'studyTrial': 'Essayer la salle d’étude',
      'studyTrialUsed': 'Ce téléphone a déjà utilisé l’essai.',
      'studyTrialUnavailable': 'L’essai n’est pas encore prêt. Réessayez plus tard.',
      'studyTrialFailed': 'Impossible de lancer l’essai. Réessayez.'
    },
    'de': {
      'tagline': 'Sprich frei, lerne ganz natürlich',
      'headlineBefore': 'Deine ',
      'headlineAccent': 'Geschichte',
      'headlineAfter': ' wird\nSprache.',
      'duoInvite': 'Duo-Einladung',
      'loginOrJoin': 'Anmelden oder registrieren',
      'swipeContinue': 'Wischen zum Fortfahren',
      'studyTrial': 'Lernraum testen',
      'studyTrialUsed': 'Dieses Telefon hat den Test bereits genutzt.',
      'studyTrialUnavailable': 'Der Test ist noch nicht bereit. Bitte später erneut versuchen.',
      'studyTrialFailed': 'Der Test konnte nicht gestartet werden. Bitte erneut versuchen.'
    },
    'hi': {
      'tagline': 'बेझिझक बोलें, स्वाभाविक रूप से सीखें',
      'headlineBefore': 'आपकी ',
      'headlineAccent': 'कहानी',
      'headlineAfter': ' भाषा बनती है।',
      'duoInvite': 'Duo आमंत्रण',
      'loginOrJoin': 'लॉग इन या जुड़ें',
      'swipeContinue': 'जारी रखने के लिए स्वाइप करें',
      'studyTrial': 'स्टडी रूम आज़माएँ',
      'studyTrialUsed': 'इस फ़ोन पर ट्रायल पहले ही उपयोग हो चुका है।',
      'studyTrialUnavailable': 'ट्रायल अभी तैयार नहीं है। बाद में फिर कोशिश करें।',
      'studyTrialFailed': 'ट्रायल शुरू नहीं हो सका। फिर से कोशिश करें।'
    },
    'ru': {
      'tagline': 'Говорите свободно, учитесь естественно',
      'headlineBefore': 'Ваша ',
      'headlineAccent': 'история',
      'headlineAfter': ' становится\nязыком.',
      'duoInvite': 'Приглашение Duo',
      'loginOrJoin': 'Войти или зарегистрироваться',
      'swipeContinue': 'Смахните, чтобы продолжить',
      'studyTrial': 'Попробовать учебную комнату',
      'studyTrialUsed': 'На этом телефоне пробный доступ уже использован.',
      'studyTrialUnavailable': 'Пробный доступ ещё не готов. Попробуйте позже.',
      'studyTrialFailed': 'Не удалось начать пробный доступ. Попробуйте снова.'
    },
    'pt': {
      'tagline': 'Fale livremente, aprenda naturalmente',
      'headlineBefore': 'A sua ',
      'headlineAccent': 'história',
      'headlineAfter': ' torna-se\nlinguagem.',
      'duoInvite': 'Convite Duo',
      'loginOrJoin': 'Entrar ou cadastrar-se',
      'swipeContinue': 'Deslize para continuar',
      'studyTrial': 'Experimente a sala de estudo',
      'studyTrialUsed': 'Este telefone já usou o teste.',
      'studyTrialUnavailable': 'O teste ainda não está pronto. Tente mais tarde.',
      'studyTrialFailed': 'Não foi possível iniciar o teste. Tente novamente.'
    },
    'it': {
      'tagline': 'Parla liberamente, impara in modo naturale',
      'headlineBefore': 'La tua ',
      'headlineAccent': 'storia',
      'headlineAfter': ' diventa\nlinguaggio.',
      'duoInvite': 'Invito Duo',
      'loginOrJoin': 'Accedi o iscriviti',
      'swipeContinue': 'Scorri per continuare',
      'studyTrial': 'Prova la sala studio',
      'studyTrialUsed': 'Questo telefono ha già usato la prova.',
      'studyTrialUnavailable': 'La prova non è ancora pronta. Riprova più tardi.',
      'studyTrialFailed': 'Impossibile avviare la prova. Riprova.'
    },
    'nl': {
      'tagline': 'Spreek vrijuit, leer vanzelf',
      'headlineBefore': 'Jouw ',
      'headlineAccent': 'verhaal',
      'headlineAfter': ' wordt\ntaal.',
      'duoInvite': 'Duo-uitnodiging',
      'loginOrJoin': 'Inloggen of aanmelden',
      'swipeContinue': 'Veeg om door te gaan',
      'studyTrial': 'Probeer de studieruimte',
      'studyTrialUsed': 'Deze telefoon heeft de proef al gebruikt.',
      'studyTrialUnavailable': 'De proef is nog niet klaar. Probeer het later opnieuw.',
      'studyTrialFailed': 'De proef kon niet starten. Probeer het opnieuw.'
    },
  };
}

/// 🎟️ [STUDY-TRIAL] 체험 버튼을 누르면 서버를 부르기 **전에** 뜨는 요약 설명서.
///   체험방에서 실제로 누를 수 있는 것만 적는다. 확정이 끝난 방이라 대사 수정이
///   없고, Keepers는 담아도 볼 화면이 없어서 뺐다(실장님, 2026-10-16).
///   `resumeTime`의 {m}은 남은 분.
class StudyTrialGuideCopy {
  StudyTrialGuideCopy._();

  static Map<String, String> forSystemLocale() {
    final code = PlatformDispatcher.instance.locale.languageCode.toLowerCase();
    return _copies[code] ?? _copies['en']!;
  }

  static const Map<String, Map<String, String>> _copies = {
    'en': {
      'title': 'Study Room Trial · 10 min',
      'lead': 'Try one study room made from a real conversation for 10 minutes.',
      'bubbleTitle': 'Buttons next to each bubble',
      'tutoring': 'Practical tutoring — make a new sentence with the same structure, say it, and get corrections from the AI.',
      'altExpr': 'Other expressions — see different ways to say the same thing.',
      'speakTitle': 'Yellow button at the top · Speaking practice',
      'practice': 'PRACTICE — have the same conversation again, swapping roles with the AI.',
      'essay': 'ESSAY — the conversation woven into one story of your own. Practice it with Snap Echoing, which cuts it into meaning units, and shadowing. Voice, repeats and speed are set when you first press Start and stay that way.',
      'tipTitle': 'Tip',
      'tip': 'Turn the volume down while speaking along. Only the AI gets quieter; your voice is still recorded clearly.',
      'timeTitle': 'Time',
      'time': 'The 10 minutes start when you press [Start trial] and never pause. If you leave and come back, the time that passed is gone. One trial per phone.',
      'resumeTime': 'About {m} min left. The clock has kept running while you were away.',
      'close': 'Close',
      'start': 'Start trial',
      'resume': 'Continue',
    },
    'ko': {
      'title': '공부방 체험 · 10분',
      'lead': '실제 대화로 만든 공부방 하나를 10분 동안 써 볼 수 있습니다.',
      'bubbleTitle': '말풍선 옆 버튼',
      'tutoring': '실전 튜터링 — 같은 구조로 새 문장을 만들어 직접 말하고, AI에게 교정을 받습니다.',
      'altExpr': '다른 표현 보기 — 같은 말을 다르게 하는 방법을 봅니다.',
      'speakTitle': '위쪽 노란 버튼 · 말하기 연습',
      'practice': 'PRACTICE — AI와 역할을 바꿔 가며 같은 대화를 다시 해 봅니다.',
      'essay': 'ESSAY — 대화 내용을 내 이야기 한 편으로 엮은 글입니다. 의미 단위로 끊어 따라 말하는 Snap Echoing과 쉐도잉으로 연습합니다. 목소리·반복·속도는 처음 Start를 누를 때 정해지고, 그 뒤로는 바뀌지 않습니다.',
      'tipTitle': '팁',
      'tip': '따라 말할 때 볼륨을 줄이면 AI 소리만 작아집니다. 내 목소리는 그대로 또렷하게 녹음됩니다.',
      'timeTitle': '시간',
      'time': '[체험 시작]을 누르면 10분이 시작되고, 중간에 멈추지 않습니다. 나갔다 다시 들어오면 그동안 지난 시간만큼 줄어 있습니다. 체험은 폰 하나에 한 번입니다.',
      'resumeTime': '남은 시간 약 {m}분 · 나가 있는 동안에도 시간이 계속 흘렀습니다.',
      'close': '닫기',
      'start': '체험 시작',
      'resume': '이어서 하기',
    },
    'ja': {
      'title': '学習ルーム体験・10分',
      'lead': '実際の会話から作られた学習ルームを10分間使ってみられます。',
      'bubbleTitle': '吹き出し横のボタン',
      'tutoring': '実践チュータリング — 同じ構造で新しい文を作って話し、AIに添削してもらいます。',
      'altExpr': '別の表現 — 同じことを別の言い方で見られます。',
      'speakTitle': '上の黄色いボタン・スピーキング練習',
      'practice': 'PRACTICE — AIと役割を入れ替えて、同じ会話をもう一度します。',
      'essay': 'ESSAY — 会話の内容を自分の話一つにまとめた文章です。意味のまとまりごとに区切って繰り返すSnap Echoingとシャドーイングで練習します。声・反復・速度は最初にStartを押した時に決まり、その後は変わりません。',
      'tipTitle': 'ヒント',
      'tip': '一緒に話す時に音量を下げると、AIの声だけが小さくなります。自分の声はそのままはっきり録音されます。',
      'timeTitle': '時間',
      'time': '［体験を始める］を押すと10分が始まり、途中で止まりません。一度出て戻ると、その間に過ぎた分だけ減っています。体験は端末1台につき1回です。',
      'resumeTime': '残り約{m}分・離れている間も時間は進んでいました。',
      'close': '閉じる',
      'start': '体験を始める',
      'resume': '続ける',
    },
    'zh': {
      'title': '学习室体验 · 10分钟',
      'lead': '可以试用一个由真实对话生成的学习室，时长10分钟。',
      'bubbleTitle': '对话气泡旁的按钮',
      'tutoring': '实战辅导 — 用相同结构造一个新句子并说出来，由AI纠正。',
      'altExpr': '其他表达 — 查看同一句话的不同说法。',
      'speakTitle': '顶部黄色按钮 · 口语练习',
      'practice': 'PRACTICE — 与AI互换角色，把同一段对话再说一遍。',
      'essay': 'ESSAY — 把对话内容编成一篇属于你自己的故事。按意义单位切分跟读的Snap Echoing和影子跟读来练习。声音、重复次数和速度在第一次按Start时确定，之后不再改变。',
      'tipTitle': '提示',
      'tip': '跟读时调低音量，只有AI的声音会变小，你的声音仍会被清晰录下。',
      'timeTitle': '时间',
      'time': '按下［开始体验］后10分钟开始计时，中途不会暂停。离开后再回来，离开期间的时间会被扣除。每部手机只能体验一次。',
      'resumeTime': '剩余约{m}分钟 · 离开期间时间仍在流逝。',
      'close': '关闭',
      'start': '开始体验',
      'resume': '继续',
    },
    'es': {
      'title': 'Prueba de la sala de estudio · 10 min',
      'lead': 'Prueba durante 10 minutos una sala de estudio creada a partir de una conversación real.',
      'bubbleTitle': 'Botones junto a cada burbuja',
      'tutoring': 'Tutoría práctica — crea una frase nueva con la misma estructura, dila y recibe correcciones de la IA.',
      'altExpr': 'Otras expresiones — mira otras formas de decir lo mismo.',
      'speakTitle': 'Botón amarillo de arriba · Práctica oral',
      'practice': 'PRACTICE — repite la misma conversación intercambiando papeles con la IA.',
      'essay': 'ESSAY — la conversación convertida en una historia propia. Practícala con Snap Echoing, que la divide en unidades de sentido, y con shadowing. La voz, las repeticiones y la velocidad se fijan al pulsar Start por primera vez y ya no cambian.',
      'tipTitle': 'Consejo',
      'tip': 'Baja el volumen mientras repites. Solo se reduce la voz de la IA; tu voz se sigue grabando con claridad.',
      'timeTitle': 'Tiempo',
      'time': 'Los 10 minutos empiezan al pulsar [Empezar prueba] y no se detienen. Si sales y vuelves, el tiempo transcurrido ya se habrá descontado. Una prueba por teléfono.',
      'resumeTime': 'Quedan unos {m} min. El tiempo siguió corriendo mientras no estabas.',
      'close': 'Cerrar',
      'start': 'Empezar prueba',
      'resume': 'Continuar',
    },
    'fr': {
      'title': 'Essai de la salle d’étude · 10 min',
      'lead': 'Essayez pendant 10 minutes une salle d’étude créée à partir d’une vraie conversation.',
      'bubbleTitle': 'Boutons à côté des bulles',
      'tutoring': 'Tutorat pratique — formez une nouvelle phrase sur la même structure, dites-la et recevez les corrections de l’IA.',
      'altExpr': 'Autres expressions — découvrez d’autres façons de dire la même chose.',
      'speakTitle': 'Bouton jaune en haut · Expression orale',
      'practice': 'PRACTICE — refaites la même conversation en échangeant les rôles avec l’IA.',
      'essay': 'ESSAY — la conversation réécrite en une histoire bien à vous. Entraînez-vous avec le Snap Echoing, qui la découpe en unités de sens, et le shadowing. La voix, les répétitions et la vitesse sont fixées au premier appui sur Start et ne changent plus.',
      'tipTitle': 'Astuce',
      'tip': 'Baissez le volume quand vous répétez. Seule la voix de l’IA diminue ; la vôtre reste enregistrée clairement.',
      'timeTitle': 'Durée',
      'time': 'Les 10 minutes démarrent quand vous appuyez sur [Commencer l’essai] et ne s’arrêtent jamais. Si vous partez puis revenez, le temps écoulé est décompté. Un essai par téléphone.',
      'resumeTime': 'Environ {m} min restantes. Le temps a continué de s’écouler pendant votre absence.',
      'close': 'Fermer',
      'start': 'Commencer l’essai',
      'resume': 'Continuer',
    },
    'de': {
      'title': 'Lernraum-Test · 10 Min.',
      'lead': 'Teste 10 Minuten lang einen Lernraum, der aus einem echten Gespräch entstanden ist.',
      'bubbleTitle': 'Schaltflächen neben den Sprechblasen',
      'tutoring': 'Praxis-Tutoring — bilde einen neuen Satz mit derselben Struktur, sprich ihn und lass dich von der KI korrigieren.',
      'altExpr': 'Andere Ausdrücke — sieh dir an, wie man dasselbe anders sagen kann.',
      'speakTitle': 'Gelbe Schaltfläche oben · Sprechübung',
      'practice': 'PRACTICE — führe dasselbe Gespräch noch einmal und tausche dabei die Rollen mit der KI.',
      'essay': 'ESSAY — das Gespräch als deine eigene Geschichte. Übe sie mit Snap Echoing, das sie in Sinneinheiten teilt, und mit Shadowing. Stimme, Wiederholungen und Tempo werden beim ersten Druck auf Start festgelegt und bleiben dann so.',
      'tipTitle': 'Tipp',
      'tip': 'Dreh beim Mitsprechen die Lautstärke herunter. Nur die KI wird leiser; deine Stimme wird weiterhin klar aufgenommen.',
      'timeTitle': 'Zeit',
      'time': 'Die 10 Minuten beginnen, wenn du auf [Test starten] tippst, und laufen ohne Pause. Wenn du gehst und zurückkommst, ist die vergangene Zeit abgezogen. Ein Test pro Telefon.',
      'resumeTime': 'Noch etwa {m} Min. Die Zeit lief weiter, während du weg warst.',
      'close': 'Schließen',
      'start': 'Test starten',
      'resume': 'Weiter',
    },
    'hi': {
      'title': 'स्टडी रूम ट्रायल · 10 मिनट',
      'lead': 'असली बातचीत से बने एक स्टडी रूम को 10 मिनट तक आज़माएँ।',
      'bubbleTitle': 'हर बबल के पास के बटन',
      'tutoring': 'व्यावहारिक ट्यूटरिंग — उसी ढाँचे में नया वाक्य बनाकर बोलें और AI से सुधार पाएँ।',
      'altExpr': 'दूसरे भाव — वही बात कहने के दूसरे तरीके देखें।',
      'speakTitle': 'ऊपर का पीला बटन · बोलने का अभ्यास',
      'practice': 'PRACTICE — AI के साथ भूमिकाएँ बदलकर वही बातचीत फिर से करें।',
      'essay': 'ESSAY — बातचीत को आपकी अपनी एक कहानी के रूप में लिखा गया पाठ। इसे अर्थ-इकाइयों में बाँटकर दोहराने वाले Snap Echoing और शैडोइंग से अभ्यास करें। आवाज़, दोहराव और गति पहली बार Start दबाने पर तय होते हैं और फिर नहीं बदलते।',
      'tipTitle': 'सुझाव',
      'tip': 'साथ बोलते समय आवाज़ कम करें। सिर्फ़ AI की आवाज़ धीमी होती है; आपकी आवाज़ साफ़ रिकॉर्ड होती रहती है।',
      'timeTitle': 'समय',
      'time': '[ट्रायल शुरू करें] दबाते ही 10 मिनट शुरू हो जाते हैं और बीच में नहीं रुकते। बाहर जाकर लौटने पर बीता हुआ समय कट चुका होगा। हर फ़ोन पर एक ही ट्रायल।',
      'resumeTime': 'लगभग {m} मिनट बाकी · आपके बाहर रहने के दौरान भी समय चलता रहा।',
      'close': 'बंद करें',
      'start': 'ट्रायल शुरू करें',
      'resume': 'जारी रखें',
    },
    'ru': {
      'title': 'Пробная учебная комната · 10 мин',
      'lead': 'Попробуйте в течение 10 минут учебную комнату, созданную из настоящего разговора.',
      'bubbleTitle': 'Кнопки рядом с репликами',
      'tutoring': 'Практический разбор — составьте новое предложение той же структуры, произнесите его и получите исправления от ИИ.',
      'altExpr': 'Другие выражения — посмотрите, как сказать то же самое иначе.',
      'speakTitle': 'Жёлтая кнопка вверху · Разговорная практика',
      'practice': 'PRACTICE — повторите тот же разговор, поменявшись ролями с ИИ.',
      'essay': 'ESSAY — разговор, пересказанный как ваша собственная история. Тренируйтесь с помощью Snap Echoing, который делит текст на смысловые части, и шэдоуинга. Голос, повторы и скорость задаются при первом нажатии Start и потом не меняются.',
      'tipTitle': 'Совет',
      'tip': 'Убавьте громкость, когда повторяете. Тише станет только ИИ, а ваш голос по-прежнему запишется чётко.',
      'timeTitle': 'Время',
      'time': '10 минут начинаются после нажатия [Начать пробу] и не останавливаются. Если вы выйдете и вернётесь, прошедшее время уже будет списано. Одна проба на телефон.',
      'resumeTime': 'Осталось около {m} мин. Пока вас не было, время продолжало идти.',
      'close': 'Закрыть',
      'start': 'Начать пробу',
      'resume': 'Продолжить',
    },
    'pt': {
      'title': 'Teste da sala de estudo · 10 min',
      'lead': 'Experimente por 10 minutos uma sala de estudo criada a partir de uma conversa real.',
      'bubbleTitle': 'Botões ao lado de cada balão',
      'tutoring': 'Tutoria prática — crie uma frase nova com a mesma estrutura, diga-a e receba correções da IA.',
      'altExpr': 'Outras expressões — veja outras formas de dizer a mesma coisa.',
      'speakTitle': 'Botão amarelo no topo · Prática de fala',
      'practice': 'PRACTICE — refaça a mesma conversa trocando de papel com a IA.',
      'essay': 'ESSAY — a conversa transformada numa história sua. Pratique com o Snap Echoing, que a divide em unidades de sentido, e com shadowing. A voz, as repetições e a velocidade ficam definidas no primeiro toque em Start e não mudam depois.',
      'tipTitle': 'Dica',
      'tip': 'Abaixe o volume enquanto repete. Só a voz da IA fica mais baixa; a sua continua a ser gravada com clareza.',
      'timeTitle': 'Tempo',
      'time': 'Os 10 minutos começam ao tocar em [Começar teste] e não param. Se sair e voltar, o tempo que passou já terá sido descontado. Um teste por telefone.',
      'resumeTime': 'Restam cerca de {m} min. O tempo continuou a correr enquanto esteve fora.',
      'close': 'Fechar',
      'start': 'Começar teste',
      'resume': 'Continuar',
    },
    'it': {
      'title': 'Prova della sala studio · 10 min',
      'lead': 'Prova per 10 minuti una sala studio creata da una conversazione reale.',
      'bubbleTitle': 'Pulsanti accanto ai fumetti',
      'tutoring': 'Tutoraggio pratico — crea una nuova frase con la stessa struttura, pronunciala e ricevi le correzioni dell’IA.',
      'altExpr': 'Altre espressioni — scopri altri modi per dire la stessa cosa.',
      'speakTitle': 'Pulsante giallo in alto · Pratica orale',
      'practice': 'PRACTICE — rifai la stessa conversazione scambiandoti i ruoli con l’IA.',
      'essay': 'ESSAY — la conversazione trasformata in una tua storia. Esercitati con lo Snap Echoing, che la divide in unità di senso, e con lo shadowing. Voce, ripetizioni e velocità si fissano al primo tocco su Start e poi non cambiano.',
      'tipTitle': 'Suggerimento',
      'tip': 'Abbassa il volume mentre ripeti. Si abbassa solo la voce dell’IA; la tua resta registrata in modo chiaro.',
      'timeTitle': 'Tempo',
      'time': 'I 10 minuti partono quando tocchi [Inizia la prova] e non si fermano. Se esci e rientri, il tempo trascorso è già stato scalato. Una prova per telefono.',
      'resumeTime': 'Restano circa {m} min. Il tempo ha continuato a scorrere mentre eri via.',
      'close': 'Chiudi',
      'start': 'Inizia la prova',
      'resume': 'Continua',
    },
    'nl': {
      'title': 'Proef studieruimte · 10 min',
      'lead': 'Probeer 10 minuten lang een studieruimte die gemaakt is van een echt gesprek.',
      'bubbleTitle': 'Knoppen naast elke tekstballon',
      'tutoring': 'Praktische begeleiding — maak een nieuwe zin met dezelfde structuur, spreek hem uit en krijg correcties van de AI.',
      'altExpr': 'Andere uitdrukkingen — bekijk andere manieren om hetzelfde te zeggen.',
      'speakTitle': 'Gele knop bovenaan · Spreekoefening',
      'practice': 'PRACTICE — voer hetzelfde gesprek opnieuw en wissel van rol met de AI.',
      'essay': 'ESSAY — het gesprek verwerkt tot één eigen verhaal. Oefen het met Snap Echoing, dat het in betekeniseenheden opdeelt, en met shadowing. Stem, herhalingen en snelheid liggen vast zodra je voor het eerst op Start drukt.',
      'tipTitle': 'Tip',
      'tip': 'Zet het volume lager terwijl je meespreekt. Alleen de AI wordt zachter; jouw stem wordt nog steeds duidelijk opgenomen.',
      'timeTitle': 'Tijd',
      'time': 'De 10 minuten beginnen zodra je op [Proef starten] tikt en stoppen niet. Als je weggaat en terugkomt, is de verstreken tijd al afgetrokken. Eén proef per telefoon.',
      'resumeTime': 'Nog ongeveer {m} min. De tijd liep door terwijl je weg was.',
      'close': 'Sluiten',
      'start': 'Proef starten',
      'resume': 'Doorgaan',
    },
  };
}

/// Rotating welcome-page pitch bubbles localized to the device language.
class IntroTaglinePitchCopy {
  static List<String> forSystemLocale(int index) {
    final locale =
        PlatformDispatcher.instance.locale.languageCode.toLowerCase();
    final pitches = _pitches[locale] ?? _pitches['en']!;
    return pitches[index % pitches.length];
  }

  static const Map<String, List<List<String>>> _pitches = {
    'en': [
      [
        '🎙️ Real-World AI Language Practice',
        'No grammar lectures. No pattern drills.\nJust real conversation.\nPay only for the time you use.'
      ],
      [
        '🎙️ No Lessons, Just Real Practice',
        'Practice real conversations with AI.\nPay only for the time you use.'
      ],
      [
        '🎙️ Your Personal AI Practice Room',
        'Learn through conversation, without lectures.\nPay only for the time you use.'
      ],
    ],
    'ko': [
      ['🎙️ 실전 AI 언어 연습', '문법 강의도, 패턴 훈련도 없습니다.\n진짜 대화만 하세요.\n사용한 시간만 결제하세요.'],
      ['🎙️ 수업 없이, 진짜 연습만', 'AI와 실제 대화를 연습하세요.\n사용한 시간만 결제하세요.'],
      ['🎙️ 나만의 AI 연습방', '강의 없이 대화로 익히세요.\n사용한 시간만 결제하세요.'],
    ],
    'ja': [
      ['🎙️ 実践AI語学練習', '文法講義もパターンドリルもありません。\n本当の会話だけ。\n使った時間分だけお支払いください。'],
      ['🎙️ レッスンなし、実践だけ', 'AIとリアルな会話を練習しましょう。\n使った時間分だけお支払いください。'],
      ['🎙️ あなた専用のAI練習室', '講義なしで、会話から身につけます。\n使った時間分だけお支払いください。'],
    ],
    'zh': [
      ['🎙️ AI实战语言练习', '没有语法讲解，也没有句型操练。\n只有真实对话。\n只按使用时间付费。'],
      ['🎙️ 不上课，只做真实练习', '和AI练习真实对话。\n只按使用时间付费。'],
      ['🎙️ 你的专属AI练习室', '通过对话学习，不需要讲课。\n只按使用时间付费。'],
    ],
    'es': [
      [
        '🎙️ Práctica de idiomas con IA real',
        'Sin clases de gramática ni ejercicios mecánicos.\nSolo conversación real.\nPaga solo por el tiempo que uses.'
      ],
      [
        '🎙️ Sin lecciones, solo práctica real',
        'Practica conversaciones reales con IA.\nPaga solo por el tiempo que uses.'
      ],
      [
        '🎙️ Tu sala personal de práctica con IA',
        'Aprende conversando, sin clases.\nPaga solo por el tiempo que uses.'
      ],
    ],
    'fr': [
      [
        '🎙️ Pratique linguistique avec une IA réelle',
        'Pas de cours de grammaire ni d’exercices mécaniques.\nSeulement de vraies conversations.\nPayez seulement le temps utilisé.'
      ],
      [
        '🎙️ Pas de leçons, de la vraie pratique',
        'Pratiquez de vraies conversations avec l’IA.\nPayez seulement le temps utilisé.'
      ],
      [
        '🎙️ Votre salle d’entraînement IA',
        'Apprenez par la conversation, sans cours.\nPayez seulement le temps utilisé.'
      ],
    ],
    'de': [
      [
        '🎙️ KI-Sprachpraxis aus dem echten Leben',
        'Keine Grammatikvorträge, keine Übungsdrills.\nNur echte Gespräche.\nDu zahlst nur für deine Nutzungszeit.'
      ],
      [
        '🎙️ Keine Lektionen, nur echte Praxis',
        'Übe echte Gespräche mit KI.\nDu zahlst nur für deine Nutzungszeit.'
      ],
      [
        '🎙️ Dein persönlicher KI-Übungsraum',
        'Lerne durch Gespräche, ganz ohne Vorträge.\nDu zahlst nur für deine Nutzungszeit.'
      ],
    ],
    'hi': [
      [
        '🎙️ वास्तविक दुनिया का AI भाषा अभ्यास',
        'व्याकरण के व्याख्यान या रटने वाले अभ्यास नहीं।\nबस वास्तविक बातचीत।\nकेवल इस्तेमाल किए समय का भुगतान करें।'
      ],
      [
        '🎙️ पाठ नहीं, सिर्फ वास्तविक अभ्यास',
        'AI के साथ वास्तविक बातचीत का अभ्यास करें।\nकेवल इस्तेमाल किए समय का भुगतान करें।'
      ],
      [
        '🎙️ आपका निजी AI अभ्यास कक्ष',
        'व्याख्यान के बिना बातचीत से सीखें।\nकेवल इस्तेमाल किए समय का भुगतान करें।'
      ],
    ],
    'ru': [
      [
        '🎙️ Практика языка с ИИ в реальной жизни',
        'Никаких лекций по грамматике и упражнений по шаблонам.\nТолько живое общение.\nПлатите только за время использования.'
      ],
      [
        '🎙️ Без уроков — только настоящая практика',
        'Практикуйте реальные разговоры с ИИ.\nПлатите только за время использования.'
      ],
      [
        '🎙️ Ваша личная комната практики с ИИ',
        'Учитесь через разговоры без лекций.\nПлатите только за время использования.'
      ],
    ],
    'pt': [
      [
        '🎙️ Prática de idiomas com IA no mundo real',
        'Sem aulas de gramática nem exercícios mecânicos.\nApenas conversas reais.\nPague somente pelo tempo usado.'
      ],
      [
        '🎙️ Sem aulas, apenas prática real',
        'Pratique conversas reais com IA.\nPague somente pelo tempo usado.'
      ],
      [
        '🎙️ Sua sala pessoal de prática com IA',
        'Aprenda conversando, sem aulas.\nPague somente pelo tempo usado.'
      ],
    ],
    'it': [
      [
        '🎙️ Pratica linguistica con IA nel mondo reale',
        'Niente lezioni di grammatica né esercizi meccanici.\nSolo conversazioni vere.\nPaghi solo il tempo che usi.'
      ],
      [
        '🎙️ Niente lezioni, solo pratica reale',
        'Esercitati in conversazioni vere con l’IA.\nPaghi solo il tempo che usi.'
      ],
      [
        '🎙️ La tua sala personale di pratica IA',
        'Impara conversando, senza lezioni.\nPaghi solo il tempo che usi.'
      ],
    ],
    'nl': [
      [
        '🎙️ Praktische taaltraining met AI',
        'Geen grammaticacolleges of patroonoefeningen.\nAlleen echte gesprekken.\nBetaal alleen voor je gebruikstijd.'
      ],
      [
        '🎙️ Geen lessen, alleen echte oefening',
        'Oefen echte gesprekken met AI.\nBetaal alleen voor je gebruikstijd.'
      ],
      [
        '🎙️ Jouw persoonlijke AI-oefenruimte',
        'Leer via gesprekken, zonder colleges.\nBetaal alleen voor je gebruikstijd.'
      ],
    ],
  };
}
