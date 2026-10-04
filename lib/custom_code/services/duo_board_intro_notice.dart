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

  static DuoBoardIntroNoticeCopy forSystemLocale() {
    final code = PlatformDispatcher.instance.locale.languageCode.toLowerCase();
    return _copies[code] ?? _copies['en']!;
  }

  static const _copies = <String, DuoBoardIntroNoticeCopy>{
    'ko': DuoBoardIntroNoticeCopy(
      title: 'Duo 통역 게시판 안내',
      body: '누구나 게시판에서 마음에 드는 주제를 올린 회원과 10분 동안 대화할 수 있습니다.\n\n'
          '대화하고 싶은 초대글을 누른 다음, 언어 설정에서 Chat Lang을 실제로 대화할 언어로 선택해 주세요. AI 통역을 통해 서로 다른 언어로도 자연스럽게 대화할 수 있습니다.\n\n'
          '대화 내용은 공부방에 저장되며, 회원은 저장된 대화를 대화 연습 자료로 활용할 수 있습니다.',
      cancel: '취소',
      openBoard: '게시판 보기',
    ),
    'en': DuoBoardIntroNoticeCopy(
      title: 'About the Duo Interpreter Board',
      body:
          'Anyone can have a 10-minute conversation with a member whose topic they like.\n\n'
          'Tap an invitation you want to join, then set Chat Lang in the language settings to the language you will speak. AI interpretation lets both people communicate naturally even when they use different languages.\n\n'
          'The conversation is saved in the Study Room. Members can use the saved conversation as speaking-practice material.',
      cancel: 'Cancel',
      openBoard: 'View board',
    ),
    'ja': DuoBoardIntroNoticeCopy(
      title: 'Duo通訳掲示板のご案内',
      body: '掲示板で気になる話題を投稿した会員と、どなたでも10分間会話できます。\n\n'
          '参加したい招待をタップし、言語設定のChat Langを実際に話す言語に設定してください。AI通訳により、異なる言語でも自然に会話できます。\n\n'
          '会話内容は学習ルームに保存されます。会員は保存された会話をスピーキング練習教材として利用できます。',
      cancel: 'キャンセル',
      openBoard: '掲示板を見る',
    ),
    'zh': DuoBoardIntroNoticeCopy(
      title: 'Duo 口译公告板说明',
      body: '任何人都可以与发布了感兴趣话题的会员进行10分钟对话。\n\n'
          '点击想参加的邀请，然后在语言设置中将 Chat Lang 设为您实际要使用的语言。通过 AI 口译，即使双方使用不同语言也能自然交流。\n\n'
          '对话内容会保存到学习室。会员可以将保存的对话用作口语练习资料。',
      cancel: '取消',
      openBoard: '查看公告板',
    ),
    'es': DuoBoardIntroNoticeCopy(
      title: 'Acerca del tablón de intérprete Duo',
      body:
          'Cualquier persona puede conversar durante 10 minutos con un miembro cuyo tema le interese.\n\n'
          'Toca la invitación a la que quieras unirte y configura Chat Lang con el idioma que vas a hablar. La interpretación con IA permite conversar con naturalidad aunque uséis idiomas diferentes.\n\n'
          'La conversación se guarda en la Sala de estudio. Los miembros pueden usarla como material para practicar conversación.',
      cancel: 'Cancelar',
      openBoard: 'Ver tablón',
    ),
    'fr': DuoBoardIntroNoticeCopy(
      title: 'À propos du tableau d’interprétation Duo',
      body:
          'Tout le monde peut discuter pendant 10 minutes avec un membre dont le sujet lui plaît.\n\n'
          'Touchez l’invitation qui vous intéresse, puis choisissez dans Chat Lang la langue que vous parlerez. L’interprétation par IA permet de converser naturellement même dans des langues différentes.\n\n'
          'La conversation est enregistrée dans la salle d’étude. Les membres peuvent l’utiliser comme support d’entraînement oral.',
      cancel: 'Annuler',
      openBoard: 'Voir le tableau',
    ),
    'de': DuoBoardIntroNoticeCopy(
      title: 'Über das Duo-Dolmetscherboard',
      body:
          'Jeder kann zehn Minuten lang mit einem Mitglied sprechen, dessen Thema ihm gefällt.\n\n'
          'Tippe auf eine passende Einladung und stelle Chat Lang auf die Sprache ein, die du sprechen wirst. Die KI-Übersetzung ermöglicht eine natürliche Unterhaltung auch in unterschiedlichen Sprachen.\n\n'
          'Das Gespräch wird im Lernraum gespeichert. Mitglieder können es als Material für Sprechübungen verwenden.',
      cancel: 'Abbrechen',
      openBoard: 'Board ansehen',
    ),
    'hi': DuoBoardIntroNoticeCopy(
      title: 'Duo दुभाषिया बोर्ड के बारे में',
      body:
          'कोई भी व्यक्ति अपनी पसंद के विषय वाले सदस्य के साथ 10 मिनट बातचीत कर सकता है।\n\n'
          'जिस निमंत्रण में आपकी रुचि हो उसे टैप करें, फिर भाषा सेटिंग में Chat Lang को उस भाषा पर सेट करें जिसमें आप बोलेंगे। AI दुभाषिया अलग-अलग भाषाओं में भी सहज बातचीत संभव बनाता है।\n\n'
          'बातचीत स्टडी रूम में सहेजी जाती है। सदस्य इसे बोलने के अभ्यास की सामग्री के रूप में उपयोग कर सकते हैं।',
      cancel: 'रद्द करें',
      openBoard: 'बोर्ड देखें',
    ),
    'ru': DuoBoardIntroNoticeCopy(
      title: 'О доске переводчика Duo',
      body:
          'Любой пользователь может десять минут поговорить с участником, тема которого ему интересна.\n\n'
          'Нажмите на подходящее приглашение и выберите в Chat Lang язык, на котором будете говорить. ИИ-перевод позволяет свободно общаться даже на разных языках.\n\n'
          'Разговор сохраняется в учебной комнате. Участники могут использовать его как материал для разговорной практики.',
      cancel: 'Отмена',
      openBoard: 'Открыть доску',
    ),
    'pt': DuoBoardIntroNoticeCopy(
      title: 'Sobre o mural de intérprete Duo',
      body:
          'Qualquer pessoa pode conversar por 10 minutos com um membro cujo tema lhe interesse.\n\n'
          'Toque no convite desejado e defina Chat Lang como o idioma que você vai falar. A interpretação por IA permite conversar naturalmente mesmo usando idiomas diferentes.\n\n'
          'A conversa é salva na Sala de Estudos. Os membros podem usá-la como material para praticar conversação.',
      cancel: 'Cancelar',
      openBoard: 'Ver mural',
    ),
    'it': DuoBoardIntroNoticeCopy(
      title: 'Informazioni sulla bacheca interprete Duo',
      body:
          'Chiunque può conversare per 10 minuti con un membro il cui argomento è di suo interesse.\n\n'
          'Tocca l’invito che preferisci e imposta Chat Lang sulla lingua che parlerai. L’interpretazione IA consente di comunicare naturalmente anche usando lingue diverse.\n\n'
          'La conversazione viene salvata nella Sala studio. I membri possono usarla come materiale per esercitarsi nel parlato.',
      cancel: 'Annulla',
      openBoard: 'Vedi bacheca',
    ),
    'nl': DuoBoardIntroNoticeCopy(
      title: 'Over het Duo-tolkenbord',
      body:
          'Iedereen kan tien minuten praten met een lid van wie het onderwerp aanspreekt.\n\n'
          'Tik op een uitnodiging waaraan je wilt deelnemen en stel Chat Lang in op de taal die je gaat spreken. Dankzij AI-vertolking kun je ook met verschillende talen natuurlijk met elkaar praten.\n\n'
          'Het gesprek wordt opgeslagen in de studieruimte. Leden kunnen het opgeslagen gesprek gebruiken als oefenmateriaal voor spreekvaardigheid.',
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
