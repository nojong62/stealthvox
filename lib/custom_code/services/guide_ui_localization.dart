class GuideUiCopy {
  const GuideUiCopy._(this._values);
  final Map<String, String> _values;

  String operator [](String key) =>
      _values[key] ?? _copies['English']![key] ?? key;

  static GuideUiCopy forLanguage(String language) =>
      GuideUiCopy._(_copies[language.trim()] ?? _copies['English']!);

  static const Map<String, Map<String, String>> _copies = {
    'English': {
      'confirm': 'Confirm',
      'close': 'Close',
      'lobbyTitle': '[ User Guide ]',
      'modeTitle': 'Talk Mode Guide',
      'circleTitle': 'Circle Talk Guide',
      'scenarioTitle': 'Scenario Talk Guide',
      'studyTitle': 'Study Room Guide',
      'lobbyBody':
          'Talk naturally with AI in your own language and freely mix in the language you are learning. Conversations become Study Room material for listening, role-switching, shadowing, and AI tutoring. With Duo Connect, invite someone for a direct call or use live interpretation. After the call, the conversation becomes study material.',
      'modeBody':
          'Duo Connect offers a direct call using your real voices or live interpretation when you speak different languages. In Circle Talk, AI joins your chosen community and follows its interests and atmosphere. In Scenario Talk, practice realistic daily or business situations with assigned roles. Circle and Scenario conversations save every 10 minutes and continue on the same screen.',
      'circleBody':
          'Create a circle around an interest, job, or community and talk with AI as another member. AI reflects its atmosphere, terminology, and shared interests.\n\nStep 1 uses your Chat Lang. In Step 2, only AI uses your learning language while you reply in your language.\n\nA session is up to 10 minutes. Leaving early still saves it; at 10 minutes it saves and continues on the same screen.',
      'scenarioBody':
          'Practice a realistic situation by taking separate roles with AI. Before starting, review or edit the situation and both roles. AI speaks first and keeps its assigned role.\n\nStep 1 uses your Chat Lang. In Step 2, only AI uses your learning language while you reply in your language.\n\nA session is up to 10 minutes. Leaving early still saves it; at 10 minutes it saves and continues on the same screen.',
      'studyBody':
          'The Study Room turns conversations into speaking practice.\n\n📝 Edit misheard lines with the pencil; clear all text and save to remove a line.\n✅ Finalize Edits locks the reviewed lines once and makes them the source for all practice.\n🏋️ Use AI Tutoring, role-switch Practice, echoing, and shadowing.\n🔊 Lowering volume reduces only the AI voice while your voice records normally.\n💾 Hold a speech bubble for about 0.5 seconds to save it to Keepers.\n⏸️ After 60 seconds without activity, billing pauses; speaking or touching resumes it.',
    },
    'Korean': {
      'confirm': '확인',
      'close': '닫기',
      'lobbyTitle': '[ 사용 설명서 ]',
      'modeTitle': '대화 모드 설명서',
      'circleTitle': 'Circle Talk 사용설명서',
      'scenarioTitle': 'Scenario Talk 사용설명서',
      'studyTitle': '스터디룸 사용설명서',
      'lobbyBody':
          'AI와 모국어로 자연스럽게 대화하고 배우는 언어도 자유롭게 섞어 보세요. 대화는 공부방에서 다시 듣기, 역할 교환, 쉐도잉과 AI 튜터링 자료가 됩니다. Duo Connect에서는 상대를 초대해 직접 통화하거나 실시간 통역을 이용할 수 있으며, 통화 후에는 학습 자료가 됩니다.',
      'modeBody':
          'Duo Connect는 실제 목소리로 직접 통화하거나 서로 다른 언어를 실시간 통역합니다. Circle Talk에서는 AI가 선택한 커뮤니티의 구성원이 되어 관심사와 분위기를 반영합니다. Scenario Talk에서는 역할을 정해 현실적인 일상·비즈니스 상황을 연습합니다. Circle과 Scenario는 10분마다 저장하고 같은 화면에서 이어집니다.',
      'circleBody':
          '관심사, 직업 또는 커뮤니티를 만들고 AI와 구성원처럼 대화합니다. AI는 그곳의 분위기, 전문 용어와 공통 관심사를 반영합니다.\n\nStep 1에서는 Chat Lang으로 대화합니다. Step 2에서는 AI만 배울 언어로 말하고 나는 내 언어로 답합니다.\n\n한 세션은 최대 10분이며 일찍 나가도 저장됩니다. 10분이 되면 같은 화면에서 저장 후 계속됩니다.',
      'scenarioBody':
          'AI와 역할을 나누어 실제 상황을 연습합니다. 시작 전에 상황과 두 역할을 확인하거나 수정하세요. AI가 먼저 말하고 지정된 역할을 유지합니다.\n\nStep 1에서는 Chat Lang으로 대화합니다. Step 2에서는 AI만 배울 언어로 말하고 나는 내 언어로 답합니다.\n\n한 세션은 최대 10분이며 일찍 나가도 저장됩니다. 10분이 되면 같은 화면에서 저장 후 계속됩니다.',
      'studyBody':
          '스터디룸은 대화를 말하기 훈련으로 만듭니다.\n\n📝 연필로 잘못 들린 문장을 고치고, 모두 지워 저장하면 그 대사가 빠집니다.\n✅ 최종 수정 완료는 한 번만 가능하며 이후 모든 학습 자료의 재료가 됩니다.\n🏋️ AI 튜터링, 역할 교환 Practice, 에코잉과 쉐도잉을 연습합니다.\n🔊 볼륨을 줄여도 내 목소리는 정상 녹음됩니다.\n💾 말풍선을 약 0.5초 누르면 Keepers에 저장됩니다.\n⏸️ 60초 동안 반응이 없으면 과금이 멈추고 말하거나 터치하면 재개됩니다.',
    },
    'Japanese': {
      'confirm': '確認',
      'close': '閉じる',
      'lobbyTitle': '[ ユーザーガイド ]',
      'modeTitle': '会話モードガイド',
      'circleTitle': 'Circle Talk ガイド',
      'scenarioTitle': 'Scenario Talk ガイド',
      'studyTitle': '学習ルームガイド',
      'lobbyBody':
          '母語でAIと自然に話し、学習中の言語も自由に混ぜられます。会話は学習ルームで聞き直し、役割交代、シャドーイング、AI指導に使われます。Duo Connectでは直接通話またはリアルタイム通訳を利用でき、通話後は教材になります。',
      'modeBody':
          'Duo Connectは実際の声による直接通話とリアルタイム通訳に対応します。Circle TalkではAIがコミュニティの一員になり、Scenario Talkでは状況と役割を決めて練習します。会話は10分ごとに保存され、同じ画面で続けられます。',
      'circleBody':
          '関心、仕事、コミュニティのサークルを作り、AIとメンバー同士のように話します。Step 1はChat Lang、Step 2ではAIだけが学習言語を使います。最大10分で、途中退出でも保存されます。',
      'scenarioBody':
          'AIと役割を分けて現実的な状況を練習します。開始前に状況と役割を編集できます。Step 1はChat Lang、Step 2ではAIだけが学習言語を使います。最大10分で自動保存されます。',
      'studyBody':
          '会話をスピーキング練習に変えます。鉛筆で認識ミスを修正し、最終確定後にAI指導、役割交代、エコーイング、シャドーイングを行います。吹き出しを長押しするとKeepersに保存され、60秒操作がないと課金が一時停止します。',
    },
    'Chinese': {
      'confirm': '确认',
      'close': '关闭',
      'lobbyTitle': '[ 使用指南 ]',
      'modeTitle': '对话模式指南',
      'circleTitle': 'Circle Talk 指南',
      'scenarioTitle': 'Scenario Talk 指南',
      'studyTitle': '学习室指南',
      'lobbyBody':
          '用母语自然地与AI交流，也可混合正在学习的语言。对话会在学习室中用于回听、角色互换、跟读和AI辅导。Duo Connect支持直接通话和实时口译，通话后会生成学习资料。',
      'modeBody':
          'Duo Connect支持真实声音直接通话和实时口译。Circle Talk让AI成为社群成员；Scenario Talk按情境和角色练习。对话每10分钟保存一次，并可在同一页面继续。',
      'circleBody':
          '围绕兴趣、职业或社群创建圈子，与作为成员的AI交流。Step 1使用Chat Lang；Step 2只有AI使用学习语言。每次最长10分钟，提前离开也会保存。',
      'scenarioBody':
          '与AI分配角色并练习真实情境。开始前可编辑情境和角色。Step 1使用Chat Lang；Step 2只有AI使用学习语言。最长10分钟并自动保存。',
      'studyBody':
          '把对话转化为口语练习。用铅笔修正识别错误，最终确认后进行AI辅导、角色互换、复述和跟读。长按气泡可保存到Keepers；60秒无操作会暂停计费。',
    },
    'Spanish': {
      'confirm': 'Confirmar',
      'close': 'Cerrar',
      'lobbyTitle': '[ Guía del usuario ]',
      'modeTitle': 'Guía de modos',
      'circleTitle': 'Guía de Circle Talk',
      'scenarioTitle': 'Guía de Scenario Talk',
      'studyTitle': 'Guía de la sala de estudio',
      'lobbyBody':
          'Habla con la IA de forma natural en tu idioma y mezcla libremente el idioma que aprendes. Las conversaciones se convierten en material para escuchar, intercambiar roles, hacer shadowing y recibir tutoría. Duo Connect ofrece llamada directa e interpretación en vivo.',
      'modeBody':
          'Duo Connect permite llamadas con voces reales o interpretación en vivo. En Circle Talk la IA se integra en una comunidad; en Scenario Talk practicas situaciones y roles. Las conversaciones se guardan cada 10 minutos y continúan en la misma pantalla.',
      'circleBody':
          'Crea un círculo de interés, profesión o comunidad y habla con la IA como un miembro. Step 1 usa Chat Lang; en Step 2 solo la IA usa el idioma de aprendizaje. La sesión dura hasta 10 minutos y se guarda aunque salgas antes.',
      'scenarioBody':
          'Practica una situación realista con roles separados. Antes de empezar puedes editar la situación y los roles. Step 1 usa Chat Lang y en Step 2 solo la IA usa el idioma de aprendizaje. Se guarda a los 10 minutos.',
      'studyBody':
          'Convierte conversaciones en práctica oral. Corrige líneas con el lápiz y finalízalas antes de practicar tutoría, cambio de roles, eco y shadowing. Mantén pulsada una burbuja para guardarla en Keepers. Tras 60 segundos sin actividad, la facturación se pausa.',
    },
    'French': {
      'confirm': 'Confirmer',
      'close': 'Fermer',
      'lobbyTitle': '[ Guide utilisateur ]',
      'modeTitle': 'Guide des modes',
      'circleTitle': 'Guide Circle Talk',
      'scenarioTitle': 'Guide Scenario Talk',
      'studyTitle': 'Guide de l’espace d’étude',
      'lobbyBody':
          'Parlez naturellement avec l’IA dans votre langue et mélangez librement la langue étudiée. Les conversations deviennent des supports d’écoute, d’inversion des rôles, de shadowing et de tutorat. Duo Connect propose appel direct et interprétation en direct.',
      'modeBody':
          'Duo Connect permet un appel avec les vraies voix ou une interprétation en direct. Circle Talk place l’IA dans une communauté; Scenario Talk entraîne des situations et des rôles. Les conversations sont sauvegardées toutes les 10 minutes.',
      'circleBody':
          'Créez un cercle lié à un intérêt, un métier ou une communauté. Step 1 utilise Chat Lang; en Step 2 seule l’IA utilise la langue étudiée. Une session dure jusqu’à 10 minutes et reste sauvegardée en cas de départ anticipé.',
      'scenarioBody':
          'Entraînez une situation réaliste avec des rôles distincts. Vous pouvez modifier la situation et les rôles avant de commencer. Step 1 utilise Chat Lang; en Step 2 seule l’IA utilise la langue étudiée. Sauvegarde à 10 minutes.',
      'studyBody':
          'Transformez les conversations en entraînement oral. Corrigez les lignes au crayon, finalisez-les, puis utilisez tutorat IA, inversion des rôles, écho et shadowing. Maintenez une bulle pour l’ajouter à Keepers. Après 60 secondes d’inactivité, la facturation se met en pause.',
    },
    'German': {
      'confirm': 'Bestätigen',
      'close': 'Schließen',
      'lobbyTitle': '[ Benutzerhandbuch ]',
      'modeTitle': 'Anleitung für Gesprächsmodi',
      'circleTitle': 'Circle Talk Anleitung',
      'scenarioTitle': 'Scenario Talk Anleitung',
      'studyTitle': 'Lernraum-Anleitung',
      'lobbyBody':
          'Sprich natürlich in deiner Sprache mit der KI und mische die Lernsprache frei dazu. Gespräche werden zu Material für Hören, Rollenwechsel, Shadowing und KI-Tutoring. Duo Connect bietet Direktanruf und Live-Dolmetschen.',
      'modeBody':
          'Duo Connect unterstützt Gespräche mit echten Stimmen oder Live-Dolmetschen. Bei Circle Talk wird die KI Teil einer Community; bei Scenario Talk übst du Situationen und Rollen. Gespräche werden alle 10 Minuten gespeichert.',
      'circleBody':
          'Erstelle einen Kreis zu Interesse, Beruf oder Community. Step 1 nutzt Chat Lang; in Step 2 spricht nur die KI die Lernsprache. Eine Sitzung dauert bis zu 10 Minuten und wird auch beim früheren Verlassen gespeichert.',
      'scenarioBody':
          'Übe eine realistische Situation mit getrennten Rollen. Situation und Rollen können vorher bearbeitet werden. Step 1 nutzt Chat Lang; in Step 2 spricht nur die KI die Lernsprache. Nach 10 Minuten wird gespeichert.',
      'studyBody':
          'Verwandle Gespräche in Sprechübungen. Korrigiere Zeilen mit dem Stift und finalisiere sie für KI-Tutoring, Rollenwechsel, Echoing und Shadowing. Halte eine Sprechblase gedrückt, um sie in Keepers zu speichern. Nach 60 Sekunden Inaktivität pausiert die Abrechnung.',
    },
    'Hindi': {
      'confirm': 'पुष्टि करें',
      'close': 'बंद करें',
      'lobbyTitle': '[ उपयोगकर्ता गाइड ]',
      'modeTitle': 'बातचीत मोड गाइड',
      'circleTitle': 'Circle Talk गाइड',
      'scenarioTitle': 'Scenario Talk गाइड',
      'studyTitle': 'स्टडी रूम गाइड',
      'lobbyBody':
          'अपनी भाषा में AI से सहजता से बात करें और सीखी जा रही भाषा भी मिलाएँ। बातचीत सुनने, भूमिका बदलने, शैडोइंग और AI ट्यूटरिंग की सामग्री बनती है। Duo Connect सीधी कॉल और लाइव अनुवाद देता है।',
      'modeBody':
          'Duo Connect वास्तविक आवाज़ की कॉल या लाइव अनुवाद देता है। Circle Talk में AI समुदाय का सदस्य बनता है; Scenario Talk में स्थिति और भूमिकाओं का अभ्यास होता है। बातचीत हर 10 मिनट में सहेजी जाती है।',
      'circleBody':
          'रुचि, काम या समुदाय का सर्कल बनाएँ और AI से सदस्य की तरह बात करें। Step 1 Chat Lang का उपयोग करता है; Step 2 में केवल AI सीखने की भाषा बोलता है। सत्र अधिकतम 10 मिनट का है और जल्दी निकलने पर भी सहेजा जाता है।',
      'scenarioBody':
          'AI के साथ अलग भूमिकाओं में वास्तविक स्थिति का अभ्यास करें। शुरू करने से पहले स्थिति और भूमिकाएँ संपादित कर सकते हैं। Step 1 Chat Lang और Step 2 में केवल AI सीखने की भाषा उपयोग करता है।',
      'studyBody':
          'बातचीत को बोलने के अभ्यास में बदलें। पेंसिल से पंक्तियाँ सुधारें और फिर AI ट्यूटरिंग, भूमिका बदलाव, इकोइंग व शैडोइंग करें। बुलबुले को दबाकर Keepers में सहेजें। 60 सेकंड निष्क्रिय रहने पर बिलिंग रुकती है।',
    },
    'Russian': {
      'confirm': 'Подтвердить',
      'close': 'Закрыть',
      'lobbyTitle': '[ Руководство ]',
      'modeTitle': 'Руководство по режимам',
      'circleTitle': 'Руководство Circle Talk',
      'scenarioTitle': 'Руководство Scenario Talk',
      'studyTitle': 'Руководство учебной комнаты',
      'lobbyBody':
          'Свободно говорите с ИИ на своем языке и добавляйте изучаемый язык. Разговоры становятся материалом для аудирования, смены ролей, шэдоуинга и занятий с ИИ. Duo Connect поддерживает прямой звонок и синхронный перевод.',
      'modeBody':
          'Duo Connect предлагает звонок реальными голосами или синхронный перевод. В Circle Talk ИИ становится участником сообщества, а в Scenario Talk вы тренируете ситуации и роли. Разговоры сохраняются каждые 10 минут.',
      'circleBody':
          'Создайте круг по интересам, профессии или сообществу. Step 1 использует Chat Lang; в Step 2 только ИИ говорит на изучаемом языке. Сеанс длится до 10 минут и сохраняется даже при раннем выходе.',
      'scenarioBody':
          'Практикуйте реальную ситуацию с отдельными ролями. До начала можно изменить ситуацию и роли. Step 1 использует Chat Lang; в Step 2 только ИИ говорит на изучаемом языке. Сохранение происходит через 10 минут.',
      'studyBody':
          'Превратите разговоры в практику речи. Исправьте строки карандашом и завершите их для занятий с ИИ, смены ролей, повторения и шэдоуинга. Удерживайте пузырь, чтобы сохранить в Keepers. Через 60 секунд бездействия оплата приостанавливается.',
    },
    'Portuguese': {
      'confirm': 'Confirmar',
      'close': 'Fechar',
      'lobbyTitle': '[ Guia do usuário ]',
      'modeTitle': 'Guia dos modos',
      'circleTitle': 'Guia do Circle Talk',
      'scenarioTitle': 'Guia do Scenario Talk',
      'studyTitle': 'Guia da sala de estudo',
      'lobbyBody':
          'Fale naturalmente com a IA no seu idioma e misture o idioma estudado. As conversas viram material de escuta, troca de papéis, shadowing e tutoria. Duo Connect oferece chamada direta e interpretação ao vivo.',
      'modeBody':
          'Duo Connect permite chamada com vozes reais ou interpretação ao vivo. No Circle Talk a IA participa de uma comunidade; no Scenario Talk você pratica situações e papéis. As conversas salvam a cada 10 minutos.',
      'circleBody':
          'Crie um círculo de interesse, profissão ou comunidade. Step 1 usa Chat Lang; no Step 2 apenas a IA usa o idioma de estudo. A sessão dura até 10 minutos e é salva mesmo se você sair antes.',
      'scenarioBody':
          'Pratique uma situação realista com papéis separados. Edite a situação e os papéis antes de começar. Step 1 usa Chat Lang; no Step 2 apenas a IA usa o idioma de estudo. Salva após 10 minutos.',
      'studyBody':
          'Transforme conversas em prática oral. Corrija as falas com o lápis e finalize-as para tutoria por IA, troca de papéis, eco e shadowing. Segure um balão para salvar em Keepers. Após 60 segundos sem atividade, a cobrança pausa.',
    },
    'Italian': {
      'confirm': 'Conferma',
      'close': 'Chiudi',
      'lobbyTitle': '[ Guida utente ]',
      'modeTitle': 'Guida alle modalità',
      'circleTitle': 'Guida Circle Talk',
      'scenarioTitle': 'Guida Scenario Talk',
      'studyTitle': 'Guida alla sala studio',
      'lobbyBody':
          'Parla naturalmente con l’IA nella tua lingua e mescola liberamente quella che studi. Le conversazioni diventano materiale per ascolto, scambio di ruoli, shadowing e tutoraggio. Duo Connect offre chiamata diretta e interpretazione dal vivo.',
      'modeBody':
          'Duo Connect consente chiamate con voci reali o interpretazione dal vivo. In Circle Talk l’IA entra in una comunità; in Scenario Talk eserciti situazioni e ruoli. Le conversazioni salvano ogni 10 minuti.',
      'circleBody':
          'Crea un circolo per interesse, lavoro o comunità. Step 1 usa Chat Lang; in Step 2 solo l’IA usa la lingua da imparare. La sessione dura fino a 10 minuti e viene salvata anche uscendo prima.',
      'scenarioBody':
          'Esercita una situazione realistica con ruoli separati. Prima di iniziare puoi modificare situazione e ruoli. Step 1 usa Chat Lang; in Step 2 solo l’IA usa la lingua da imparare. Salvataggio dopo 10 minuti.',
      'studyBody':
          'Trasforma le conversazioni in esercizi orali. Correggi le battute con la matita e finalizzale per tutoraggio IA, scambio di ruoli, eco e shadowing. Tieni premuto un fumetto per salvarlo in Keepers. Dopo 60 secondi di inattività la fatturazione si sospende.',
    },
    'Dutch': {
      'confirm': 'Bevestigen',
      'close': 'Sluiten',
      'lobbyTitle': '[ Gebruikershandleiding ]',
      'modeTitle': 'Gids voor gespreksmodi',
      'circleTitle': 'Circle Talk-gids',
      'scenarioTitle': 'Scenario Talk-gids',
      'studyTitle': 'Studieruimte-gids',
      'lobbyBody':
          'Praat natuurlijk met AI in je eigen taal en meng de taal die je leert. Gesprekken worden materiaal voor luisteren, rollen wisselen, shadowing en AI-begeleiding. Duo Connect biedt een direct gesprek en live tolken.',
      'modeBody':
          'Duo Connect ondersteunt gesprekken met echte stemmen of live tolken. In Circle Talk wordt AI lid van een community; in Scenario Talk oefen je situaties en rollen. Gesprekken worden elke 10 minuten opgeslagen.',
      'circleBody':
          'Maak een kring rond een interesse, beroep of community. Step 1 gebruikt Chat Lang; in Step 2 spreekt alleen AI de leertaal. Een sessie duurt maximaal 10 minuten en wordt ook bij eerder vertrek opgeslagen.',
      'scenarioBody':
          'Oefen een realistische situatie met aparte rollen. Vooraf kun je de situatie en rollen wijzigen. Step 1 gebruikt Chat Lang; in Step 2 spreekt alleen AI de leertaal. Na 10 minuten wordt opgeslagen.',
      'studyBody':
          'Zet gesprekken om in spreekoefeningen. Corrigeer regels met het potlood en rond ze af voor AI-begeleiding, rollen wisselen, echoing en shadowing. Houd een tekstballon ingedrukt om in Keepers te bewaren. Na 60 seconden inactiviteit pauzeert de facturering.',
    },
  };
}
