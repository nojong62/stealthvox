// ====================================================================
// ❓ [INTRO-FAQ] 인트로 첫 화면 아래 FAQ 팝업의 글.
// --------------------------------------------------------------------
// 처음 온 사람이 "이게 나한테 맞나"를 판단하는 데 필요한 것만 고른다.
// 출처는 앱 안 사용 설명(`guide_ui_localization.dart`)과 지금 코드다 —
// `back/` 아래 옛 매뉴얼은 없어진 기능(Clone AI·Step Expand)이 섞여 있어
// 쓰지 않는다.
//
// 로그인 전 화면이라 폰 언어를 따른다(`IntroWelcomePageCopy`와 같은 규칙).
// 버튼·모드 이름은 앱 화면의 라벨(`talk_ui_localization.dart`)과 맞춘다.
// ====================================================================

import 'dart:ui' show PlatformDispatcher;

class IntroFaqCopy {
  const IntroFaqCopy._(this.title, this.items);

  final String title;

  /// [질문, 답] 순서. 첫 질문이 펼쳐진 채로 열린다.
  final List<List<String>> items;

  static IntroFaqCopy forSystemLocale() {
    final code = PlatformDispatcher.instance.locale.languageCode.toLowerCase();
    return _copies[code] ?? _copies['en']!;
  }

  static const Map<String, IntroFaqCopy> _copies = {
    'en': IntroFaqCopy._('FAQ', [
      [
        'What is StealthVox?',
        'A practice room where you learn a language from your own words. It works whether you can’t say a word yet or already talk freely. You can even call a friend who speaks another language — each of you speaks your own, and you pick up theirs.',
      ],
      [
        'I can’t speak the language at all. Is that OK?',
        'Yes. After signing in, set Origin to your native language and Target to the language you want to learn. Speak in your own language and the AI replies in it too; the Study Room then turns that conversation into sentences in the language you are learning. Switch to Step 2 during a talk and only the AI speaks the target language — listening practice.',
      ],
      [
        'I can already hold a conversation.',
        'On the screen where you start Circle Talk or Scenario Talk, check Free Talk. You talk in your lobby Target language from the start, and the Study Room shows what you said on top with its meaning in your Origin language below. All Study Room practice is in that language too.',
      ],
      [
        'I have no one to talk to.',
        'No problem. In Circle Talk you chat with several AI friends about topics you like, and in Scenario Talk you act out real situations, like an airport or a restaurant, with the AI.',
      ],
      [
        'Can I talk with a friend who speaks another language?',
        'Invite them with Duo. Each of you speaks your own language and the AI interprets. If both Origin settings match, Duo switches to a direct call where you hear each other’s voices. Only the member who sent the invitation is billed.',
      ],
      [
        'What happens after a conversation?',
        'It is saved in the Study Room (SR). Fix any lines that were misheard, then tap [Finish final edits] to open tutoring, Practice and shadowing built from that conversation. You can finalize only once, so check everything first.',
      ],
      [
        'How does pricing work?',
        'You pay only for the time you use; it is deducted from your remaining time. Top up in the Store. The Study Room trial on the first screen gives you 10 minutes without signing up, once per phone.',
      ],
    ]),
    'ko': IntroFaqCopy._('자주 묻는 질문', [
      [
        'StealthVox는 어떤 앱인가요?',
        '내 말로 연습하는 외국어 연습장입니다. 외국어를 한마디도 못 해도, 이미 자유롭게 대화할 수 있어도 쓸 수 있습니다. 서로 다른 언어를 쓰는 친구와도 각자 모국어로 통화하며 상대의 언어를 배울 수 있습니다.',
      ],
      [
        '외국어를 전혀 못 해도 되나요?',
        '네. 로그인한 뒤 Origin에 모국어를, Target에 배우고 싶은 언어를 고르세요. 모국어로 편하게 말하면 AI도 모국어로 대화하고, 그 대화가 공부방에서 배우는 언어의 문장으로 바뀝니다. 대화 중 Step 2로 바꾸면 AI만 배우는 언어로 말해 듣기 연습이 됩니다.',
      ],
      [
        '이미 외국어로 대화할 수 있어요.',
        '서클톡이나 시나리오톡을 시작하는 화면에서 Free Talk을 체크하세요. 로비에서 고른 Target 언어로 처음부터 대화하고, 공부방에는 내가 한 말이 위에, Origin(모국어) 뜻이 아래에 나옵니다. 공부방 연습도 모두 그 언어로 합니다.',
      ],
      [
        '말할 상대가 없어요.',
        '괜찮습니다. 서클톡에서는 AI 친구 여럿과 좋아하는 주제로 이야기하고, 시나리오톡에서는 공항·식당 같은 실제 상황을 AI와 역할을 나눠 연습합니다.',
      ],
      [
        '다른 언어를 쓰는 친구와도 대화할 수 있나요?',
        'Duo로 친구를 초대하면 각자 자기 언어로 말하고 AI가 통역합니다. 두 사람의 Origin이 같으면 서로의 목소리를 직접 듣는 직접 통화로 바뀝니다. 과금은 초대한 회원에게만 됩니다.',
      ],
      [
        '대화가 끝나면 무엇을 하나요?',
        '대화는 공부방(SR)에 저장됩니다. 잘못 들린 문장을 고치고 [최종 수정 완료]를 누르면, 그 대화로 실전 튜터링·Practice·쉐도잉 연습이 열립니다. 확정은 한 번뿐이니 꼼꼼히 확인한 뒤 눌러 주세요.',
      ],
      [
        '요금은 어떻게 되나요?',
        '쓴 시간만큼만 남은 시간에서 차감됩니다. 시간은 Store에서 충전합니다. 첫 화면의 공부방 체험은 폰 한 대당 한 번, 가입 없이 10분 동안 써 볼 수 있습니다.',
      ],
    ]),
    'ja': IntroFaqCopy._('よくある質問', [
      [
        'StealthVox はどんなアプリですか?',
        '自分の言葉で練習する外国語の練習場です。外国語がまったく話せなくても、すでに自由に会話できても使えます。違う言語を話す友だちとも、それぞれ母語で通話しながら相手の言語を学べます。',
      ],
      [
        '外国語がまったく話せなくても大丈夫?',
        'はい。ログイン後、Origin に母語、Target に学びたい言語を選んでください。母語で気軽に話すと AI も母語で会話し、その会話が学習ルームで学ぶ言語の文に変わります。会話中に Step 2 に切り替えると AI だけが学ぶ言語で話し、リスニング練習になります。',
      ],
      [
        'すでに外国語で会話できます。',
        'サークルトークやシナリオトークを始める画面で Free Talk にチェックを入れてください。ロビーで選んだ Target 言語で最初から会話し、学習ルームでは自分の言葉が上に、Origin(母語)の意味が下に表示されます。学習ルームの練習もすべてその言語で行います。',
      ],
      [
        '話し相手がいません。',
        '大丈夫です。サークルトークでは複数の AI の友だちと好きなテーマで話し、シナリオトークでは空港やレストランのような実際の場面を AI と役を分けて練習します。',
      ],
      [
        '違う言語を話す友だちとも会話できますか?',
        'Duo で友だちを招待すると、それぞれ自分の言語で話し AI が通訳します。二人の Origin が同じなら、お互いの声を直接聞く直接通話に切り替わります。課金されるのは招待した会員だけです。',
      ],
      [
        '会話が終わったら何をしますか?',
        '会話は学習ルーム(SR)に保存されます。聞き間違えた文を直して[最終編集を完了]を押すと、その会話から実践チュータリング・Practice・シャドーイングの練習が開きます。確定は一度きりなので、よく確認してから押してください。',
      ],
      [
        '料金はどうなりますか?',
        '使った時間の分だけ残り時間から差し引かれます。時間は Store でチャージします。最初の画面の学習ルーム体験は、端末1台につき1回、登録なしで10分間使えます。',
      ],
    ]),
    'zh': IntroFaqCopy._('常见问题', [
      [
        'StealthVox 是什么应用?',
        '用自己的话练习外语的练习场。无论一句外语都不会说,还是已经能自由对话,都可以使用。还能和说另一种语言的朋友各自用母语通话,学习对方的语言。',
      ],
      [
        '完全不会说外语也可以吗?',
        '可以。登录后,在 Origin 选择母语,在 Target 选择想学的语言。用母语轻松地说,AI 也用母语对话,这段对话会在学习室里变成所学语言的句子。对话中切换到 Step 2,只有 AI 用所学语言说话,成为听力练习。',
      ],
      [
        '我已经能用外语对话了。',
        '在开始社群对话或情景对话的画面勾选 Free Talk。从一开始就用大厅里选的 Target 语言对话,学习室里上方显示你说的话,下方显示 Origin(母语)的意思。学习室的练习也都用这种语言进行。',
      ],
      [
        '我没有说话的对象。',
        '没关系。在社群对话里,你可以和多位 AI 朋友聊喜欢的话题;在情景对话里,可以和 AI 分角色练习机场、餐厅等真实场景。',
      ],
      [
        '能和说其他语言的朋友对话吗?',
        '用 Duo 邀请朋友,各自说自己的语言,由 AI 口译。两人的 Origin 相同时,会切换为能直接听到彼此声音的直接通话。只向发出邀请的会员计费。',
      ],
      [
        '对话结束后做什么?',
        '对话会保存在学习室(SR)。修改听错的句子后点 [完成最终修改],就会开启用这段对话做的实战辅导、Practice 和跟读练习。确认只能进行一次,请仔细检查后再点。',
      ],
      [
        '如何收费?',
        '只按使用的时间从剩余时间中扣除。时间在 Store 充值。首页的学习室体验每部手机一次,无需注册即可使用 10 分钟。',
      ],
    ]),
    'es': IntroFaqCopy._('Preguntas frecuentes', [
      [
        '¿Qué es StealthVox?',
        'Una sala de práctica donde aprendes un idioma a partir de tus propias palabras. Sirve tanto si aún no sabes decir nada como si ya conversas con soltura. Incluso puedes llamar a un amigo que habla otro idioma: cada uno habla el suyo y aprendes el del otro.',
      ],
      [
        'No hablo nada del idioma. ¿Puedo usarla?',
        'Sí. Después de iniciar sesión, elige tu idioma nativo en Origin y el que quieres aprender en Target. Habla tranquilo en tu idioma y la IA también te responde en él; luego la sala de estudio convierte esa conversación en frases del idioma que aprendes. Si cambias a Step 2 durante la charla, solo la IA habla el idioma que aprendes: práctica de escucha.',
      ],
      [
        'Ya puedo mantener una conversación.',
        'En la pantalla donde empiezas Conversación de círculo o Conversación de escenario, marca Free Talk. Hablas desde el principio en tu idioma Target del lobby, y la sala de estudio muestra arriba lo que dijiste y abajo su significado en tu idioma Origin. Toda la práctica de la sala de estudio también es en ese idioma.',
      ],
      [
        'No tengo con quién hablar.',
        'No pasa nada. En Conversación de círculo charlas con varios amigos IA sobre temas que te gustan, y en Conversación de escenario practicas situaciones reales, como un aeropuerto o un restaurante, repartiendo papeles con la IA.',
      ],
      [
        '¿Puedo hablar con un amigo que habla otro idioma?',
        'Invítalo con Duo. Cada uno habla su idioma y la IA interpreta. Si los dos tienen el mismo Origin, Duo cambia a una llamada directa en la que os oís la voz. Solo se cobra al miembro que envió la invitación.',
      ],
      [
        '¿Qué hago al terminar una conversación?',
        'Se guarda en la sala de estudio (SR). Corrige las frases que se entendieron mal y pulsa [Terminar la edición final] para abrir la tutoría, Practice y el shadowing creados con esa conversación. Solo puedes confirmar una vez, así que revísalo todo antes.',
      ],
      [
        '¿Cómo se cobra?',
        'Solo pagas el tiempo que usas; se descuenta de tu tiempo restante. Recarga en la Store. La prueba de la sala de estudio en la primera pantalla te da 10 minutos sin registrarte, una vez por teléfono.',
      ],
    ]),
    'fr': IntroFaqCopy._('Questions fréquentes', [
      [
        'Qu’est-ce que StealthVox ?',
        'Une salle d’entraînement où vous apprenez une langue à partir de vos propres mots. Elle convient que vous ne sachiez encore rien dire ou que vous parliez déjà librement. Vous pouvez même appeler un ami qui parle une autre langue : chacun parle la sienne et vous apprenez celle de l’autre.',
      ],
      [
        'Je ne parle pas du tout la langue. Est-ce possible ?',
        'Oui. Une fois connecté, choisissez votre langue maternelle dans Origin et la langue à apprendre dans Target. Parlez tranquillement dans votre langue et l’IA vous répond dans la même ; la salle d’étude transforme ensuite cette conversation en phrases dans la langue apprise. Passez en Step 2 pendant la conversation et seule l’IA parle la langue apprise : un entraînement à l’écoute.',
      ],
      [
        'Je sais déjà tenir une conversation.',
        'Sur l’écran où vous lancez Dialogue de groupe ou Dialogue de scénario, cochez Free Talk. Vous parlez dès le début dans votre langue Target de l’accueil, et la salle d’étude affiche en haut ce que vous avez dit, en dessous son sens dans votre langue Origin. Tous les exercices de la salle d’étude se font aussi dans cette langue.',
      ],
      [
        'Je n’ai personne avec qui parler.',
        'Aucun souci. Dans Dialogue de groupe, vous discutez avec plusieurs amis IA de sujets qui vous plaisent ; dans Dialogue de scénario, vous jouez avec l’IA des situations réelles, comme un aéroport ou un restaurant.',
      ],
      [
        'Puis-je parler avec un ami qui parle une autre langue ?',
        'Invitez-le avec Duo. Chacun parle sa langue et l’IA interprète. Si vos deux Origin sont identiques, Duo passe en appel direct où vous entendez vos voix. Seul le membre qui a envoyé l’invitation est facturé.',
      ],
      [
        'Que faire après une conversation ?',
        'Elle est enregistrée dans la salle d’étude (SR). Corrigez les phrases mal entendues puis touchez [Terminer les modifications] pour ouvrir le tutorat, Practice et le shadowing tirés de cette conversation. La validation ne se fait qu’une fois : vérifiez tout avant.',
      ],
      [
        'Comment est-ce facturé ?',
        'Vous ne payez que le temps utilisé, déduit de votre temps restant. Rechargez dans le Store. L’essai de la salle d’étude sur le premier écran offre 10 minutes sans inscription, une fois par téléphone.',
      ],
    ]),
    'de': IntroFaqCopy._('Häufige Fragen', [
      [
        'Was ist StealthVox?',
        'Ein Übungsraum, in dem du eine Sprache aus deinen eigenen Worten lernst. Er passt, egal ob du noch kein Wort sagen kannst oder schon frei sprichst. Du kannst sogar mit einem Freund telefonieren, der eine andere Sprache spricht – jeder spricht seine eigene, und du lernst die des anderen.',
      ],
      [
        'Ich spreche die Sprache gar nicht. Geht das?',
        'Ja. Wähle nach dem Anmelden bei Origin deine Muttersprache und bei Target die Sprache, die du lernen willst. Sprich entspannt in deiner Sprache, die KI antwortet ebenfalls darin; der Lernraum macht aus dem Gespräch danach Sätze in der Lernsprache. Wechselst du im Gespräch zu Step 2, spricht nur die KI die Lernsprache – Hörtraining.',
      ],
      [
        'Ich kann mich schon unterhalten.',
        'Setze auf dem Startbildschirm von Gruppengespräch oder Szenario-Gespräch ein Häkchen bei Free Talk. Du sprichst von Anfang an in deiner Target-Sprache aus der Lobby, und der Lernraum zeigt oben, was du gesagt hast, darunter die Bedeutung in deiner Origin-Sprache. Auch alle Übungen im Lernraum laufen in dieser Sprache.',
      ],
      [
        'Ich habe niemanden zum Reden.',
        'Kein Problem. Im Gruppengespräch plauderst du mit mehreren KI-Freunden über Themen, die dich interessieren, und im Szenario-Gespräch spielst du mit der KI echte Situationen wie Flughafen oder Restaurant durch.',
      ],
      [
        'Kann ich mit einem Freund sprechen, der eine andere Sprache spricht?',
        'Lade ihn mit Duo ein. Jeder spricht seine eigene Sprache, die KI dolmetscht. Haben beide dieselbe Origin, wechselt Duo zu einem Direktanruf, bei dem ihr eure Stimmen hört. Berechnet wird nur das Mitglied, das eingeladen hat.',
      ],
      [
        'Was passiert nach einem Gespräch?',
        'Es wird im Lernraum (SR) gespeichert. Korrigiere falsch verstandene Sätze und tippe auf [Endbearbeitung abschließen], dann öffnen sich Tutoring, Practice und Shadowing aus diesem Gespräch. Abschließen geht nur einmal – prüfe vorher alles.',
      ],
      [
        'Wie wird abgerechnet?',
        'Du zahlst nur die genutzte Zeit; sie wird von deiner Restzeit abgezogen. Aufladen kannst du im Store. Der Lernraum-Test auf dem ersten Bildschirm gibt dir 10 Minuten ohne Registrierung, einmal pro Telefon.',
      ],
    ]),
    'hi': IntroFaqCopy._('अक्सर पूछे जाने वाले सवाल', [
      [
        'StealthVox क्या है?',
        'अपनी ही बातों से विदेशी भाषा का अभ्यास करने की जगह। चाहे आप अभी एक शब्द भी न बोल पाते हों या पहले से खुलकर बात करते हों, दोनों के लिए है। दूसरी भाषा बोलने वाले दोस्त से भी हर कोई अपनी भाषा में बात कर सकता है और आप उसकी भाषा सीखते हैं।',
      ],
      [
        'मुझे वह भाषा बिल्कुल नहीं आती। क्या चलेगा?',
        'हाँ। लॉग इन करने के बाद Origin में अपनी मातृभाषा और Target में सीखने वाली भाषा चुनें। अपनी भाषा में आराम से बोलें, AI भी उसी में जवाब देगा; फिर अध्ययन कक्ष उस बातचीत को सीखी जा रही भाषा के वाक्यों में बदल देता है। बातचीत के बीच Step 2 चुनें तो सिर्फ़ AI सीखी जा रही भाषा में बोलेगा — सुनने का अभ्यास।',
      ],
      [
        'मैं पहले से उस भाषा में बात कर सकता/सकती हूँ।',
        'समूह वार्ता या परिदृश्य वार्ता शुरू करने वाली स्क्रीन पर Free Talk पर निशान लगाएँ। आप शुरू से लॉबी में चुनी Target भाषा में बात करते हैं, और अध्ययन कक्ष में ऊपर आपकी कही बात और नीचे Origin (मातृभाषा) में उसका अर्थ दिखता है। अध्ययन कक्ष का सारा अभ्यास भी उसी भाषा में होता है।',
      ],
      [
        'मेरे पास बात करने के लिए कोई नहीं है।',
        'कोई बात नहीं। समूह वार्ता में आप कई AI दोस्तों से पसंदीदा विषयों पर बात करते हैं, और परिदृश्य वार्ता में हवाई अड्डे या रेस्टोरेंट जैसी असली स्थितियों का AI के साथ अभ्यास करते हैं।',
      ],
      [
        'क्या दूसरी भाषा बोलने वाले दोस्त से बात कर सकते हैं?',
        'Duo से दोस्त को आमंत्रित करें। हर कोई अपनी भाषा में बोलता है और AI अनुवाद करता है। दोनों का Origin एक जैसा हो तो Duo सीधी कॉल में बदल जाता है, जिसमें आप एक-दूसरे की आवाज़ सुनते हैं। शुल्क सिर्फ़ आमंत्रण भेजने वाले सदस्य से लिया जाता है।',
      ],
      [
        'बातचीत के बाद क्या करें?',
        'बातचीत अध्ययन कक्ष (SR) में सेव होती है। गलत सुने गए वाक्य ठीक करें और [अंतिम संपादन पूरा करें] दबाएँ, फिर उसी बातचीत से ट्यूटरिंग, Practice और शैडोइंग अभ्यास खुलते हैं। पुष्टि सिर्फ़ एक बार होती है, इसलिए पहले सब जाँच लें।',
      ],
      [
        'शुल्क कैसे लगता है?',
        'सिर्फ़ इस्तेमाल किए गए समय का भुगतान होता है; वह आपके बचे समय से घटता है। समय Store में रिचार्ज करें। पहली स्क्रीन का अध्ययन कक्ष ट्रायल हर फ़ोन पर एक बार, बिना साइन अप के 10 मिनट देता है।',
      ],
    ]),
    'ru': IntroFaqCopy._('Частые вопросы', [
      [
        'Что такое StealthVox?',
        'Площадка, где вы учите язык на своих собственных словах. Подходит и тем, кто пока не может сказать ни слова, и тем, кто уже свободно разговаривает. Можно даже созвониться с другом, говорящим на другом языке: каждый говорит на своём, а вы учите его язык.',
      ],
      [
        'Я совсем не говорю на этом языке. Можно?',
        'Да. После входа выберите в Origin родной язык, а в Target — язык, который хотите учить. Говорите спокойно на своём языке, и ИИ тоже отвечает на нём; затем учебная комната превращает этот разговор в фразы на изучаемом языке. Переключитесь на Step 2 во время разговора — и на изучаемом языке будет говорить только ИИ: тренировка восприятия на слух.',
      ],
      [
        'Я уже могу поддержать разговор.',
        'На экране запуска Группового или Сценарного разговора отметьте Free Talk. Вы с самого начала говорите на языке Target из лобби, а в учебной комнате сверху видно сказанное вами, снизу — его смысл на языке Origin. Все упражнения учебной комнаты тоже идут на этом языке.',
      ],
      [
        'Мне не с кем поговорить.',
        'Не страшно. В Групповом разговоре вы болтаете с несколькими ИИ-друзьями на любимые темы, а в Сценарном разговоре разыгрываете с ИИ реальные ситуации — аэропорт, ресторан.',
      ],
      [
        'Можно ли говорить с другом, который говорит на другом языке?',
        'Пригласите его через Duo. Каждый говорит на своём языке, ИИ переводит. Если у обоих одинаковый Origin, Duo переключается на прямой звонок, где вы слышите голоса друг друга. Списание идёт только у участника, отправившего приглашение.',
      ],
      [
        'Что делать после разговора?',
        'Разговор сохраняется в учебной комнате (SR). Исправьте неверно распознанные фразы и нажмите [Завершить правки] — откроются репетиторство, Practice и шэдоуинг по этому разговору. Подтвердить можно только один раз, поэтому сначала всё проверьте.',
      ],
      [
        'Как устроена оплата?',
        'Вы платите только за использованное время — оно списывается с остатка. Пополнить можно в Store. Пробная учебная комната на первом экране даёт 10 минут без регистрации, один раз на телефон.',
      ],
    ]),
    'pt': IntroFaqCopy._('Perguntas frequentes', [
      [
        'O que é o StealthVox?',
        'Uma sala de prática onde você aprende um idioma a partir das suas próprias palavras. Serve tanto para quem ainda não sabe dizer nada quanto para quem já conversa com facilidade. Você pode até ligar para um amigo que fala outro idioma: cada um fala o seu e você aprende o dele.',
      ],
      [
        'Não falo nada do idioma. Tudo bem?',
        'Sim. Depois de entrar, escolha seu idioma nativo em Origin e o idioma que quer aprender em Target. Fale à vontade no seu idioma e a IA também responde nele; depois a sala de estudo transforma essa conversa em frases no idioma que você aprende. Mude para Step 2 durante a conversa e só a IA fala o idioma que você aprende: treino de escuta.',
      ],
      [
        'Já consigo manter uma conversa.',
        'Na tela em que você inicia a Conversa em grupo ou a Conversa de cenário, marque Free Talk. Você conversa desde o início no seu idioma Target do lobby, e a sala de estudo mostra em cima o que você disse e embaixo o significado no seu idioma Origin. Toda a prática da sala de estudo também é nesse idioma.',
      ],
      [
        'Não tenho com quem conversar.',
        'Sem problema. Na Conversa em grupo você bate papo com vários amigos de IA sobre temas de que gosta, e na Conversa de cenário pratica situações reais, como aeroporto ou restaurante, dividindo papéis com a IA.',
      ],
      [
        'Posso conversar com um amigo que fala outro idioma?',
        'Convide-o pelo Duo. Cada um fala o próprio idioma e a IA interpreta. Se os dois tiverem o mesmo Origin, o Duo muda para uma chamada direta em que vocês ouvem a voz um do outro. Só o membro que enviou o convite é cobrado.',
      ],
      [
        'O que fazer depois de uma conversa?',
        'Ela fica salva na sala de estudo (SR). Corrija as frases que foram mal entendidas e toque em [Concluir edição final] para abrir a tutoria, o Practice e o shadowing feitos com essa conversa. Só dá para confirmar uma vez, então revise tudo antes.',
      ],
      [
        'Como funciona a cobrança?',
        'Você paga só pelo tempo que usa; ele é descontado do seu tempo restante. Recarregue na Store. O teste da sala de estudo na primeira tela dá 10 minutos sem cadastro, uma vez por telefone.',
      ],
    ]),
    'it': IntroFaqCopy._('Domande frequenti', [
      [
        'Che cos’è StealthVox?',
        'Una palestra in cui impari una lingua partendo dalle tue parole. Va bene sia se non sai ancora dire nulla sia se parli già liberamente. Puoi perfino chiamare un amico che parla un’altra lingua: ognuno parla la propria e tu impari la sua.',
      ],
      [
        'Non parlo affatto la lingua. Va bene lo stesso?',
        'Sì. Dopo l’accesso scegli la tua lingua madre in Origin e la lingua da imparare in Target. Parla tranquillo nella tua lingua e anche l’IA ti risponde in quella; poi la sala studio trasforma la conversazione in frasi nella lingua che stai imparando. Passa a Step 2 durante la conversazione e solo l’IA parla la lingua da imparare: allenamento all’ascolto.',
      ],
      [
        'So già sostenere una conversazione.',
        'Nella schermata da cui avvii Dialogo di gruppo o Dialogo di scenario, spunta Free Talk. Parli fin dall’inizio nella lingua Target scelta nella lobby, e la sala studio mostra sopra ciò che hai detto e sotto il significato nella tua lingua Origin. Anche tutta la pratica della sala studio è in quella lingua.',
      ],
      [
        'Non ho nessuno con cui parlare.',
        'Nessun problema. Nel Dialogo di gruppo chiacchieri con diversi amici IA sui temi che ti piacciono, e nel Dialogo di scenario reciti con l’IA situazioni reali, come un aeroporto o un ristorante.',
      ],
      [
        'Posso parlare con un amico che parla un’altra lingua?',
        'Invitalo con Duo. Ognuno parla la propria lingua e l’IA fa da interprete. Se entrambi avete lo stesso Origin, Duo passa a una chiamata diretta in cui sentite le vostre voci. Paga solo il membro che ha inviato l’invito.',
      ],
      [
        'Cosa succede dopo una conversazione?',
        'Viene salvata nella sala studio (SR). Correggi le frasi capite male e tocca [Completa le modifiche finali] per aprire tutoring, Practice e shadowing creati da quella conversazione. Puoi confermare una sola volta, quindi controlla tutto prima.',
      ],
      [
        'Come funziona il pagamento?',
        'Paghi solo il tempo che usi, scalato dal tempo rimanente. Ricarica nello Store. La prova della sala studio nella prima schermata ti dà 10 minuti senza registrazione, una volta per telefono.',
      ],
    ]),
    'nl': IntroFaqCopy._('Veelgestelde vragen', [
      [
        'Wat is StealthVox?',
        'Een oefenruimte waar je een taal leert vanuit je eigen woorden. Het werkt of je nu nog geen woord kunt zeggen of al vrij praat. Je kunt zelfs bellen met een vriend die een andere taal spreekt: ieder spreekt de eigen taal en jij leert die van de ander.',
      ],
      [
        'Ik spreek de taal helemaal niet. Kan dat?',
        'Ja. Kies na het inloggen je moedertaal bij Origin en de taal die je wilt leren bij Target. Praat ontspannen in je eigen taal en de AI antwoordt ook in die taal; daarna maakt de leerruimte van dat gesprek zinnen in de taal die je leert. Schakel tijdens het gesprek naar Step 2 en alleen de AI spreekt de leertaal: luistertraining.',
      ],
      [
        'Ik kan al een gesprek voeren.',
        'Vink Free Talk aan op het scherm waar je Groepsgesprek of Scenariogesprek start. Je praat vanaf het begin in je Target-taal uit de lobby, en de leerruimte toont bovenaan wat je zei en daaronder de betekenis in je Origin-taal. Ook alle oefeningen in de leerruimte zijn in die taal.',
      ],
      [
        'Ik heb niemand om mee te praten.',
        'Geen probleem. In Groepsgesprek klets je met meerdere AI-vrienden over onderwerpen die je leuk vindt, en in Scenariogesprek speel je met de AI echte situaties na, zoals een vliegveld of een restaurant.',
      ],
      [
        'Kan ik praten met een vriend die een andere taal spreekt?',
        'Nodig die uit met Duo. Ieder spreekt de eigen taal en de AI tolkt. Hebben jullie allebei dezelfde Origin, dan schakelt Duo over op een direct gesprek waarin je elkaars stem hoort. Alleen het lid dat de uitnodiging stuurde, betaalt.',
      ],
      [
        'Wat gebeurt er na een gesprek?',
        'Het wordt bewaard in de leerruimte (SR). Verbeter zinnen die verkeerd zijn verstaan en tik op [Laatste bewerkingen afronden]; dan openen tutoring, Practice en shadowing uit dat gesprek. Afronden kan maar één keer, dus controleer alles eerst.',
      ],
      [
        'Hoe werkt betalen?',
        'Je betaalt alleen voor de tijd die je gebruikt; die gaat van je resterende tijd af. Opwaarderen doe je in de Store. De proef van de leerruimte op het eerste scherm geeft je 10 minuten zonder account, één keer per telefoon.',
      ],
    ]),
  };
}
