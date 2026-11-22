# Play 스토어 등록정보 — 10개 언어 초안 (2026-10-28)

## 먼저 알아 둘 것

- **현재 영어·한국어 소개는 앱과 어긋난다.** 공부방 설명에 "Clear & Easy / Natural & Sharp"가 남아 있다.
  10-15부터 앱은 **PRACTICE | ESSAY** 두 장이다. 아래 초안은 지금 앱 기준으로 썼다(직역 아님).
  영어·한국어도 같은 구조로 고치는 게 맞다 → 맨 아래 "영어 원본(개정안)".
- 용어는 앱 화면 문구를 따랐다: `routine_mode_duo.dart`(직접 통화·통역 이름),
  `duo_board_intro_notice.dart`(학습실·튜터링·다른 표현·ESSAY 설명).
- 긴 설명은 유럽어 2,100~2,500자, 일본어·중국어 약 800~950자로 줄였다. 영어 원문(3,866자)을 그대로 옮기면 독일어·프랑스어·러시아어가 4,000자를 넘는다.
- 등록 코드:
  - 중국어는 앱이 간체라 **zh-CN**으로 쓴다. 대만·홍콩(zh-TW·zh-HK)은 번체가 필요해서 이번 범위에서 뺐다.
  - 스페인어는 **es-419**(중남미)와 **es-ES**에 같은 글을 넣어도 된다.
  - 포르투갈어는 브라질식으로 썼다 → **pt-BR**.
- 원어민 검수는 최소한 각 언어의 **제목·짧은 설명**만이라도 받는다.

---

## ja-JP — 일본어

**제목**
```
StealthVox: AI英会話・スピーキング練習
```

**짧은 설명**
```
実際の会話を英語スピーキング練習に。AIや相手との会話から学べます。
```

**자세한 설명**
```
実際の会話を、意味のあるスピーキング練習に。

StealthVoxは、相手やAIとの会話をそのまま英語の話す練習に変えるアプリです。話したあとは学習ルームで、自分が本当に言いたかった文を練習できます。

■ 会話モード

Duo — 招待リンクで相手とつながります。
• 直接通話：お互いの実際の声で話します。家族・友人・同僚との会話が、そのまま練習素材になります。
• 万能通訳：それぞれが自分の言語で話し、AIが通訳します。言葉が違っても1対1の会話を続けられます。

Circle Talk — 旅行・スポーツ・映画・ビジネスなどのコミュニティを選ぶと、AIがメンバーとして加わり、その場の話題・口調・雰囲気に合わせて話します。

Scenario Talk — 日常からビジネスまで、決まった役割と場面でAIと話します。台本を読むのではなく、相手の反応や自然な流れに応じて答える練習です。

■ 会話履歴

会話は最大10分ずつ保存されます。途中で終えても、それまでの内容は残ります。あとから直近の会話と短い要約を文脈にして続けられます。

■ 学習ルーム

1. 確認と確定 — 聞き取りが違っていた行を直し、Finalize Editsで確定します。確定した行が練習素材になります。
2. PRACTICE — AIと役割を入れ替えて、同じ会話をもう一度します。
3. ESSAY — 会話の内容を、自分の話として一つの文章にまとめます。意味のまとまりごとに区切って繰り返すSnap Echoingと、シャドーイングで練習します。
4. 実践チュータリング — 同じ構造で新しい文を作って声に出すと、AIが意味・文法・時制・語順・語の選び方を添削し、理由と自然な使い方を説明します。
5. 別の表現 — 同じことを別の言い方で確認できます。英語ではStandard・American・British・Nativeのスタイルを比べられます。
6. Keepers — 吹き出しを長押しすると保存できます。元の会話を削除しても、保存した文は残ります。

■ 学習ルーム体験

実際の会話から作られた学習ルームを10分間無料で試せます（端末1台につき1回）。

自分の会話から学び、本当に言いたい言葉を練習しましょう。
```

---

## zh-CN — 중국어(간체)

**제목**
```
StealthVox: AI英语口语练习
```

**짧은 설명**
```
把真实对话变成英语口语练习。与AI或朋友聊完，再到学习室开口练。
```

**자세한 설명**
```
把真实对话变成真正有用的口语练习。

StealthVox把你与他人或AI的对话，直接变成英语口语练习。聊完之后，在学习室里练习你真正想说的句子。

■ 对话模式

Duo — 通过邀请链接与对方连接。
• 直接通话：用彼此真实的声音交谈。和家人、朋友、同事的对话都能成为练习材料。
• 万能翻译：每个人用自己的语言说话，AI负责翻译，即使语言不同也能继续一对一交流。

Circle Talk — 选择旅行、体育、电影、商务等社群，AI作为成员加入，并配合社群的话题、语气和氛围。

Scenario Talk — 从日常生活到商务场景，在设定好的角色和情境中与AI对话。不是照着台词念，而是根据对方的反应和自然的对话节奏来回应。

■ 对话记录

对话按每段最长10分钟保存。提前结束时，已录下的内容也会保留。之后可以把最近的对话和简短摘要作为上下文继续聊。

■ 学习室

1. 检查与确定 — 修改识别有误的句子，然后点击 Finalize Edits。确定后的句子成为练习材料。
2. PRACTICE — 与AI互换角色，把同一段对话再说一遍。
3. ESSAY — 把对话内容编成一篇属于你自己的故事。用按意义单位切分跟读的 Snap Echoing 和影子跟读来练习。
4. 实战辅导 — 用相同结构造一个新句子并说出来，AI会检查意思、语法、时态、语序和用词，并解释原因和自然用法。
5. 其他表达 — 查看同一句话的不同说法。英语可以比较 Standard、American、British、Native 几种风格。
6. Keepers — 长按对话气泡即可保存。即使删除原对话，保存的句子也会保留。

■ 学习室体验

可以免费试用一个由真实对话生成的学习室，时长10分钟（每部手机一次）。

从自己的对话中学习，练习你真正想说的话。
```

---

## es-419 / es-ES — 스페인어

**제목**
```
StealthVox: Inglés oral con IA
```

**짧은 설명**
```
Convierte tus conversaciones reales en práctica oral de inglés con IA.
```

**자세한 설명**
```
Convierte tus conversaciones reales en práctica oral que de verdad sirve.

StealthVox transforma tus conversaciones con otras personas y con IA en práctica para hablar inglés. Después de hablar, entra en la sala de estudio y practica justo las frases que querías decir.

■ MODOS DE CONVERSACIÓN

Duo — Conecta con otra persona mediante un enlace de invitación.
• Llamada directa: hablen con sus propias voces. Las conversaciones con familia, amigos o compañeros de trabajo se convierten en material de práctica.
• Intérprete en vivo: cada persona habla en su idioma y la IA interpreta, para que la conversación uno a uno siga aunque no compartan idioma.

Circle Talk — Elige una comunidad: viajes, deportes, cine, negocios… La IA se une como un miembro más y se adapta a los temas, el tono y el ambiente del grupo.

Scenario Talk — Habla con la IA en un papel y una situación concretos, de la vida diaria a los negocios. No lees un guion: respondes a las reacciones y al ritmo natural de la conversación.

■ HISTORIAL

Las conversaciones se guardan en tramos de hasta 10 minutos. Si terminas antes, se guarda todo lo grabado hasta ese momento. Luego puedes continuar con la conversación reciente y un breve resumen como contexto.

■ SALA DE ESTUDIO

1. Revisa y confirma — Corrige las líneas mal transcritas y pulsa Finalize Edits. Las líneas confirmadas se convierten en material de práctica.
2. PRACTICE — Repite la misma conversación intercambiando papeles con la IA.
3. ESSAY — La conversación convertida en una historia propia, contada en primera persona. Practícala con Snap Echoing, que la divide en unidades de sentido, y con shadowing.
4. Tutoría práctica — Crea una frase nueva con la misma estructura y dila en voz alta. La IA revisa el significado, la gramática, el tiempo verbal, el orden y la elección de palabras, y te explica el porqué y cómo sonar natural.
5. Otras expresiones — Mira otras formas de decir lo mismo. En inglés puedes comparar los estilos Standard, American, British y Native.
6. Keepers — Mantén pulsada una burbuja para guardarla. Aunque borres la conversación original, lo guardado se conserva.

■ PRUEBA DE LA SALA DE ESTUDIO

Prueba gratis durante 10 minutos una sala de estudio creada a partir de una conversación real (una prueba por teléfono).

Aprende de tus propias conversaciones y practica lo que de verdad quieres decir.
```

---

## fr-FR — 프랑스어

**제목**
```
StealthVox: Parler anglais
```

**짧은 설명**
```
Transformez vos vraies conversations en pratique orale de l'anglais avec l'IA.
```

**자세한 설명**
```
Transformez vos vraies conversations en une pratique orale vraiment utile.

StealthVox fait de vos conversations avec d'autres personnes ou avec l'IA un entraînement à l'anglais parlé. Après avoir parlé, ouvrez la salle d'étude et entraînez-vous sur les phrases que vous vouliez vraiment dire.

■ MODES DE CONVERSATION

Duo — Connectez-vous à une autre personne grâce à un lien d'invitation.
• Appel direct : parlez avec vos vraies voix. Les conversations avec votre famille, vos amis ou vos collègues deviennent du matériel d'entraînement.
• Interprète en direct : chacun parle sa propre langue et l'IA interprète, pour poursuivre une conversation en tête-à-tête malgré la barrière de la langue.

Circle Talk — Choisissez une communauté : voyage, sport, cinéma, affaires… L'IA la rejoint comme membre et s'adapte à ses sujets, à son ton et à son ambiance.

Scenario Talk — Parlez avec l'IA dans un rôle et une situation précis, de la vie quotidienne au monde professionnel. Pas de texte à lire : vous réagissez au fil naturel de l'échange.

■ HISTORIQUE

Les conversations sont enregistrées par segments de 10 minutes maximum. Si vous arrêtez plus tôt, tout ce qui a été enregistré est conservé. Vous pouvez ensuite reprendre avec la conversation récente et un court résumé comme contexte.

■ SALLE D'ÉTUDE

1. Vérifier et valider — Corrigez les lignes mal transcrites, puis touchez Finalize Edits. Les lignes validées deviennent votre matériel d'entraînement.
2. PRACTICE — Refaites la même conversation en échangeant les rôles avec l'IA.
3. ESSAY — La conversation réécrite en une histoire bien à vous, à la première personne. Entraînez-vous avec le Snap Echoing, qui la découpe en unités de sens, et le shadowing.
4. Tutorat pratique — Formez une nouvelle phrase sur la même structure et dites-la à voix haute. L'IA vérifie le sens, la grammaire, le temps, l'ordre des mots et le vocabulaire, et explique pourquoi et comment le dire naturellement.
5. Autres expressions — Découvrez d'autres façons de dire la même chose. En anglais, comparez les styles Standard, American, British et Native.
6. Keepers — Appuyez longuement sur une bulle pour l'enregistrer. Même si vous supprimez la conversation d'origine, vos phrases enregistrées restent.

■ ESSAI DE LA SALLE D'ÉTUDE

Essayez gratuitement pendant 10 minutes une salle d'étude créée à partir d'une vraie conversation (un essai par téléphone).

Apprenez de vos propres conversations et entraînez-vous à dire ce que vous voulez vraiment dire.
```

---

## de-DE — 독일어

**제목**
```
StealthVox: Englisch sprechen
```

**짧은 설명**
```
Mach echte Gespräche zu Englisch-Sprechübungen – mit KI und Gesprächspartnern.
```

**자세한 설명**
```
Mach aus echten Gesprächen Sprechübungen, die wirklich etwas bringen.

StealthVox verwandelt deine Gespräche mit anderen Menschen und mit KI in Übungen zum Englischsprechen. Nach dem Gespräch übst du im Lernraum genau die Sätze, die du sagen wolltest.

■ GESPRÄCHSMODI

Duo — Verbinde dich per Einladungslink mit einer anderen Person.
• Direktes Gespräch: Ihr sprecht mit euren echten Stimmen. Gespräche mit Familie, Freunden oder Kollegen werden zu Übungsmaterial.
• Live-Dolmetscher: Jeder spricht seine eigene Sprache, die KI dolmetscht – so läuft das Gespräch zu zweit auch über Sprachgrenzen hinweg weiter.

Circle Talk — Wähle eine Community wie Reisen, Sport, Filme oder Business. Die KI ist als Mitglied dabei und passt sich Themen, Ton und Stimmung der Runde an.

Scenario Talk — Sprich mit der KI in einer bestimmten Rolle und Situation, vom Alltag bis zum Beruf. Statt ein Skript abzulesen, reagierst du auf dein Gegenüber und den natürlichen Gesprächsfluss.

■ GESPRÄCHSVERLAUF

Gespräche werden in Abschnitten von bis zu 10 Minuten gespeichert. Wenn du früher aufhörst, bleibt alles bis dahin Aufgenommene erhalten. Später kannst du mit dem letzten Gespräch und einer kurzen Zusammenfassung als Kontext weitermachen.

■ LERNRAUM

1. Prüfen und festlegen — Korrigiere falsch erkannte Zeilen und tippe auf Finalize Edits. Festgelegte Zeilen werden zu deinem Übungsmaterial.
2. PRACTICE — Führe dasselbe Gespräch noch einmal und tausche dabei die Rollen mit der KI.
3. ESSAY — Das Gespräch als deine eigene Geschichte, in der Ich-Form. Übe sie mit Snap Echoing, das sie in Sinneinheiten teilt, und mit Shadowing.
4. Praxis-Tutoring — Bilde einen neuen Satz mit derselben Struktur und sprich ihn laut aus. Die KI prüft Bedeutung, Grammatik, Zeitform, Wortstellung und Wortwahl und erklärt, warum und wie es natürlich klingt.
5. Andere Ausdrücke — Sieh dir an, wie man dasselbe anders sagen kann. Im Englischen vergleichst du die Stile Standard, American, British und Native.
6. Keepers — Halte eine Sprechblase gedrückt, um sie zu speichern. Auch wenn du das ursprüngliche Gespräch löschst, bleiben gespeicherte Sätze erhalten.

■ LERNRAUM-TEST

Teste 10 Minuten lang kostenlos einen Lernraum, der aus einem echten Gespräch entstanden ist (ein Test pro Telefon).

Lerne aus deinen eigenen Gesprächen und übe die Worte, die du wirklich sagen willst.
```

---

## hi-IN — 힌디어

**제목**
```
StealthVox: इंग्लिश बोलें
```

**짧은 설명**
```
असली बातचीत को AI के साथ English speaking अभ्यास में बदलें।
```

**자세한 설명**
```
अपनी असली बातचीत को काम आने वाले बोलने के अभ्यास में बदलें।

StealthVox दूसरों के साथ और AI के साथ आपकी बातचीत को अंग्रेज़ी बोलने (English speaking) के अभ्यास में बदल देता है। बात करने के बाद स्टडी रूम में वही वाक्य बोलने का अभ्यास करें जो आप सच में कहना चाहते थे।

■ बातचीत के तरीके

Duo — न्योते के लिंक से किसी दूसरे व्यक्ति से जुड़ें।
• सीधी कॉल: आप दोनों अपनी असली आवाज़ में बात करते हैं। परिवार, दोस्तों या साथ काम करने वालों से हुई बातचीत अभ्यास की सामग्री बन जाती है।
• लाइव अनुवादक: हर व्यक्ति अपनी भाषा में बोलता है और AI अनुवाद करता है, ताकि भाषा अलग होने पर भी आमने-सामने की बातचीत चलती रहे।

Circle Talk — यात्रा, खेल, फ़िल्में या बिज़नेस जैसी कोई कम्युनिटी चुनें। AI एक सदस्य की तरह जुड़ता है और ग्रुप के विषय, लहजे और माहौल के हिसाब से बात करता है।

Scenario Talk — रोज़मर्रा की ज़िंदगी से लेकर बिज़नेस तक, किसी तय भूमिका और स्थिति में AI से बात करें। रटी हुई लाइनें पढ़ने के बजाय सामने वाले की प्रतिक्रिया और बातचीत के स्वाभाविक बहाव के हिसाब से जवाब दें।

■ बातचीत का रिकॉर्ड

बातचीत ज़्यादा से ज़्यादा 10 मिनट के हिस्सों में सेव होती है। पहले खत्म करने पर भी तब तक की रिकॉर्डिंग सेव रहती है। बाद में हाल की बातचीत और एक छोटे सारांश के साथ बात आगे जारी रख सकते हैं।

■ स्टडी रूम

1. जाँचें और पक्का करें — गलत सुनी गई लाइनें ठीक करें और Finalize Edits दबाएँ। पक्की की गई लाइनें अभ्यास की सामग्री बनती हैं।
2. PRACTICE — AI के साथ भूमिकाएँ बदलकर वही बातचीत फिर से करें।
3. ESSAY — बातचीत को आपकी अपनी एक कहानी के रूप में, अपनी ज़ुबानी लिखा गया पाठ। इसे अर्थ-इकाइयों में बाँटकर दोहराने वाले Snap Echoing और शैडोइंग से अभ्यास करें।
4. व्यावहारिक ट्यूटरिंग — उसी ढाँचे में नया वाक्य बनाकर ज़ोर से बोलें। AI अर्थ, व्याकरण, काल, शब्द-क्रम और शब्दों के चुनाव की जाँच करता है और वजह व स्वाभाविक इस्तेमाल समझाता है।
5. दूसरे भाव — वही बात कहने के दूसरे तरीके देखें। अंग्रेज़ी में Standard, American, British और Native स्टाइल की तुलना करें।
6. Keepers — किसी बबल को दबाकर रखें और सेव करें। मूल बातचीत डिलीट करने पर भी सेव किए गए वाक्य बने रहते हैं।

■ स्टडी रूम ट्रायल

असली बातचीत से बने एक स्टडी रूम को 10 मिनट तक मुफ़्त आज़माएँ (हर फ़ोन पर एक बार)।

अपनी ही बातचीत से सीखें और वही बोलने का अभ्यास करें जो आप सच में कहना चाहते हैं।
```

---

## ru-RU — 러시아어

**제목**
```
StealthVox: Английский с ИИ
```

**짧은 설명**
```
Превращайте реальные разговоры в практику разговорного английского с ИИ.
```

**자세한 설명**
```
Превратите реальные разговоры в разговорную практику, которая действительно помогает.

StealthVox превращает ваши разговоры с людьми и с ИИ в тренировку разговорного английского. После разговора откройте учебную комнату и потренируйте именно те фразы, которые вы хотели сказать.

■ РЕЖИМЫ РАЗГОВОРА

Duo — подключитесь к собеседнику по ссылке-приглашению.
• Прямой звонок: вы говорите своими настоящими голосами. Разговоры с семьёй, друзьями или коллегами становятся материалом для практики.
• Живой переводчик: каждый говорит на своём языке, а ИИ переводит, чтобы разговор один на один продолжался даже через языковой барьер.

Circle Talk — выберите сообщество: путешествия, спорт, кино, бизнес… ИИ присоединяется как участник и подстраивается под темы, тон и атмосферу группы.

Scenario Talk — говорите с ИИ в заданной роли и ситуации, от повседневной жизни до бизнеса. Не читайте по сценарию — отвечайте на реакции собеседника и естественный ход разговора.

■ ИСТОРИЯ РАЗГОВОРОВ

Разговоры сохраняются частями до 10 минут. Если вы закончите раньше, всё записанное к этому моменту сохранится. Потом можно продолжить, опираясь на недавний разговор и краткое резюме.

■ УЧЕБНАЯ КОМНАТА

1. Проверьте и утвердите — исправьте неверно распознанные реплики и нажмите Finalize Edits. Утверждённые реплики становятся материалом для практики.
2. PRACTICE — повторите тот же разговор, поменявшись ролями с ИИ.
3. ESSAY — разговор, пересказанный от первого лица как ваша собственная история. Тренируйтесь с помощью Snap Echoing, который делит текст на смысловые части, и шэдоуинга.
4. Практический разбор — составьте новое предложение той же структуры и произнесите его вслух. ИИ проверит смысл, грамматику, время, порядок и выбор слов и объяснит, почему и как сказать естественно.
5. Другие выражения — посмотрите, как сказать то же самое иначе. Для английского можно сравнить стили Standard, American, British и Native.
6. Keepers — нажмите и удерживайте реплику, чтобы сохранить её. Даже если удалить исходный разговор, сохранённые фразы останутся.

■ ПРОБНАЯ УЧЕБНАЯ КОМНАТА

Попробуйте бесплатно в течение 10 минут учебную комнату, созданную из настоящего разговора (одна проба на телефон).

Учитесь на своих разговорах и тренируйте слова, которые действительно хотите сказать.
```

---

## pt-BR — 포르투갈어(브라질)

**제목**
```
StealthVox: Fale inglês com IA
```

**짧은 설명**
```
Transforme conversas reais em prática de conversação em inglês com IA.
```

**자세한 설명**
```
Transforme conversas reais em prática de fala que faz diferença.

O StealthVox transforma suas conversas com outras pessoas e com IA em prática para falar inglês. Depois de conversar, abra a sala de estudo e pratique exatamente as frases que você queria dizer.

■ MODOS DE CONVERSA

Duo — Conecte-se com outra pessoa por um link de convite.
• Chamada direta: vocês conversam com as próprias vozes. Conversas com família, amigos ou colegas de trabalho viram material de prática.
• Intérprete ao vivo: cada pessoa fala no próprio idioma e a IA interpreta, para que a conversa a dois continue mesmo com a barreira do idioma.

Circle Talk — Escolha uma comunidade como viagem, esportes, filmes ou negócios. A IA entra como membro e se adapta aos assuntos, ao tom e ao clima do grupo.

Scenario Talk — Converse com a IA em um papel e uma situação definidos, do dia a dia aos negócios. Em vez de ler um roteiro, você responde às reações e ao fluxo natural da conversa.

■ HISTÓRICO

As conversas são salvas em trechos de até 10 minutos. Se você terminar antes, tudo o que foi gravado até ali fica salvo. Depois, dá para continuar usando a conversa recente e um breve resumo como contexto.

■ SALA DE ESTUDO

1. Revise e confirme — Corrija as falas transcritas errado e toque em Finalize Edits. As falas confirmadas viram material de prática.
2. PRACTICE — Refaça a mesma conversa trocando de papel com a IA.
3. ESSAY — A conversa transformada numa história sua, em primeira pessoa. Pratique com o Snap Echoing, que a divide em unidades de sentido, e com shadowing.
4. Tutoria prática — Crie uma frase nova com a mesma estrutura e fale em voz alta. A IA verifica o sentido, a gramática, o tempo verbal, a ordem e a escolha das palavras, e explica o porquê e como soar natural.
5. Outras expressões — Veja outras formas de dizer a mesma coisa. Em inglês, compare os estilos Standard, American, British e Native.
6. Keepers — Toque e segure um balão para salvá-lo. Mesmo que você apague a conversa original, as frases salvas continuam lá.

■ TESTE DA SALA DE ESTUDO

Experimente grátis por 10 minutos uma sala de estudo criada a partir de uma conversa real (um teste por telefone).

Aprenda com as suas próprias conversas e pratique o que você realmente quer dizer.
```

---

## it-IT — 이탈리아어

**제목**
```
StealthVox: Inglese parlato
```

**짧은 설명**
```
Trasforma le tue conversazioni reali in pratica di inglese parlato con l'IA.
```

**자세한 설명**
```
Trasforma le conversazioni reali in una pratica orale che serve davvero.

StealthVox trasforma le tue conversazioni con altre persone e con l'IA in esercizi per parlare inglese. Dopo aver parlato, apri la sala studio ed esercitati proprio sulle frasi che volevi dire.

■ MODALITÀ DI CONVERSAZIONE

Duo — Collegati a un'altra persona con un link di invito.
• Chiamata diretta: parlate con le vostre voci reali. Le conversazioni con famiglia, amici o colleghi diventano materiale per esercitarti.
• Interprete in diretta: ognuno parla nella propria lingua e l'IA interpreta, così la conversazione a due continua anche oltre la barriera linguistica.

Circle Talk — Scegli una community come viaggi, sport, film o business. L'IA si unisce come membro e si adatta agli argomenti, al tono e all'atmosfera del gruppo.

Scenario Talk — Parla con l'IA in un ruolo e una situazione precisi, dalla vita quotidiana al lavoro. Invece di leggere un copione, rispondi alle reazioni e al flusso naturale della conversazione.

■ CRONOLOGIA

Le conversazioni vengono salvate in segmenti di massimo 10 minuti. Se finisci prima, tutto ciò che è stato registrato fino a quel momento resta salvato. In seguito puoi continuare usando la conversazione recente e un breve riassunto come contesto.

■ SALA STUDIO

1. Controlla e conferma — Correggi le battute trascritte male e tocca Finalize Edits. Le battute confermate diventano materiale per esercitarti.
2. PRACTICE — Rifai la stessa conversazione scambiandoti i ruoli con l'IA.
3. ESSAY — La conversazione trasformata in una tua storia, in prima persona. Esercitati con lo Snap Echoing, che la divide in unità di senso, e con lo shadowing.
4. Tutoraggio pratico — Crea una nuova frase con la stessa struttura e pronunciala ad alta voce. L'IA controlla significato, grammatica, tempo verbale, ordine e scelta delle parole, e spiega il perché e come suonare naturale.
5. Altre espressioni — Scopri altri modi per dire la stessa cosa. In inglese puoi confrontare gli stili Standard, American, British e Native.
6. Keepers — Tieni premuto un fumetto per salvarlo. Anche se elimini la conversazione originale, le frasi salvate restano.

■ PROVA DELLA SALA STUDIO

Prova gratis per 10 minuti una sala studio creata da una conversazione reale (una prova per telefono).

Impara dalle tue conversazioni ed esercitati a dire quello che vuoi davvero dire.
```

---

## nl-NL — 네덜란드어

**제목**
```
StealthVox: Engels spreken
```

**짧은 설명**
```
Maak van echte gesprekken Engelse spreekoefeningen, met AI en gesprekspartners.
```

**자세한 설명**
```
Maak van echte gesprekken spreekoefeningen die er echt toe doen.

StealthVox maakt van je gesprekken met anderen en met AI oefeningen om Engels te spreken. Na het gesprek oefen je in de studieruimte precies de zinnen die je wilde zeggen.

■ GESPREKSMODI

Duo — Maak via een uitnodigingslink verbinding met iemand anders.
• Direct gesprek: jullie praten met je eigen echte stem. Gesprekken met familie, vrienden of collega's worden oefenmateriaal.
• Live tolk: iedereen spreekt zijn eigen taal en de AI tolkt, zodat het gesprek met z'n tweeën doorgaat, ook over taalgrenzen heen.

Circle Talk — Kies een community zoals reizen, sport, films of business. De AI doet mee als lid en past zich aan de onderwerpen, de toon en de sfeer van de groep aan.

Scenario Talk — Praat met de AI in een bepaalde rol en situatie, van het dagelijks leven tot zakelijk. In plaats van een script voor te lezen, reageer je op de ander en op de natuurlijke loop van het gesprek.

■ GESPREKSGESCHIEDENIS

Gesprekken worden opgeslagen in delen van maximaal 10 minuten. Stop je eerder, dan blijft alles wat tot dan is opgenomen bewaard. Later kun je verdergaan met het recente gesprek en een korte samenvatting als context.

■ STUDIERUIMTE

1. Controleren en vastleggen — Verbeter verkeerd herkende regels en tik op Finalize Edits. Vastgelegde regels worden je oefenmateriaal.
2. PRACTICE — Voer hetzelfde gesprek opnieuw en wissel van rol met de AI.
3. ESSAY — Het gesprek verwerkt tot één eigen verhaal, in de ik-vorm. Oefen het met Snap Echoing, dat het in betekeniseenheden opdeelt, en met shadowing.
4. Praktische begeleiding — Maak een nieuwe zin met dezelfde structuur en spreek hem hardop uit. De AI controleert betekenis, grammatica, tijd, woordvolgorde en woordkeuze en legt uit waarom en hoe het natuurlijk klinkt.
5. Andere uitdrukkingen — Bekijk andere manieren om hetzelfde te zeggen. In het Engels vergelijk je de stijlen Standard, American, British en Native.
6. Keepers — Houd een tekstballon ingedrukt om hem op te slaan. Ook als je het oorspronkelijke gesprek verwijdert, blijven opgeslagen zinnen bewaard.

■ PROEF STUDIERUIMTE

Probeer 10 minuten gratis een studieruimte die gemaakt is van een echt gesprek (één proef per telefoon).

Leer van je eigen gesprekken en oefen de woorden die je echt wilt zeggen.
```

---

## ko-KR — 한국어(개정안, 자세한 설명만)

기존 글의 말투는 그대로 두고 낡은 곳만 고쳤다. 스토어의 "개발자 연락처" 블록은 Play가 설명 아래에 따로 붙이는 것이라 본문에 넣지 않는다.

**자세한 설명**
```
[스텔스복스 대화 모드 안내]

스텔스복스는 실제 대화와 AI 대화를 나만의 학습 자료로 연결하는 말하기 훈련 플랫폼입니다. 파트너와 이야기하거나 관심사와 상황에 맞는 AI 대화를 즐긴 뒤, 공부방에서 표현과 말하기를 연습해 보세요.

Duo Connect [초청 파트너 대화]

초청 링크로 파트너를 연결하고, 두 가지 방식 중 하나를 선택합니다.

초청 직접 대화
파트너와 서로의 실제 목소리로 자연스럽게 통화합니다. 가족, 친구, 동료와 나눈 일상 대화가 학습 자료로 남고, 통화가 끝나면 공부방에서 다시 연습할 수 있습니다.

초청 만능 통역
서로 다른 언어를 사용하는 파트너와 각자의 모국어로 대화합니다. AI가 상대방의 말을 실시간으로 통역해 주어, 언어 장벽을 넘어 1:1 대화를 이어갈 수 있습니다.

Circle Talk [커뮤니티 대화]

여행, 스포츠, 영화, 비즈니스 등 지금 참여하고 싶은 커뮤니티를 선택해 보세요. AI에게 추천받거나 원하는 커뮤니티를 직접 입력할 수 있습니다.

AI가 해당 서클의 구성원이 되어 관심사, 말투, 분위기에 맞춰 자연스럽게 대화합니다. 내가 좋아하는 주제로 이야기하며 분야별 표현과 대화 감각을 익혀보세요.

Scenario Talk [실전 상황 대화]

일상부터 비즈니스까지, 구체적인 역할과 상황 속에서 AI와 대화합니다. AI에게 다양한 상황을 추천받고, 그 장면에서 필요한 말을 직접 해보세요.

정해진 문장을 읽는 연습을 넘어, 상대의 반응과 대화 흐름에 맞춰 말하는 실전 대응력을 기릅니다.

대화 기록 안내

한 대화 세션은 최대 10분 단위로 저장됩니다. 10분을 모두 채우지 않아도, 대화를 마치면 그때까지의 기록이 남습니다. 저장 후에도 같은 화면에서 최근 대화와 짧은 요약을 바탕으로 이야기를 이어갈 수 있습니다.

———

[공부방 말하기 훈련 가이드]

공부방에서는 내가 실제로 나눈 대화를 바탕으로 표현을 살펴보고, 직접 말하고, 다시 듣는 훈련을 합니다.

1. 대사를 확인하고 학습 자료 확정하기

지난 대화 기록을 열고, 내가 한 말이 정확하게 기록됐는지 확인하세요.

잘못 기록된 문장은 말풍선의 연필 아이콘으로 수정할 수 있습니다. 학습에서 제외할 대사는 수정 화면에서 내용을 모두 지운 뒤 저장하세요.

검토를 마쳤다면 [최종 수정 완료]를 눌러 학습 자료를 확정합니다. 확정한 대사는 이후 훈련의 재료가 되며, 확정 후에는 다시 수정할 수 없으므로 신중하게 확인해 주세요.

2. 오늘의 목표에 맞는 학습 경로 선택하기

PRACTICE [역할 교환 대화 연습]
저장된 대화에서 내가 맡을 역할을 선택하고 AI와 번갈아 대사를 말합니다. 역할을 바꿔 상대방의 대사도 연습하면서, 표현뿐 아니라 대화 전체의 흐름과 주고받는 타이밍을 익힙니다.

ESSAY [내 이야기로 말하기]
대화 내용을 내 이야기 한 편으로 엮은 글입니다. 대화에 없던 내용을 덧붙이지 않고, 내가 1인칭으로 말하듯 정리합니다. 긴 대화를 나눴다면 그만큼 긴 글이 됩니다.

두 가지 경로는 정해진 순서 없이, 오늘의 목표에 맞춰 선택할 수 있습니다.

3. 실전 튜터링 [응용 → 도전 → 교정 → 습득]

저장된 문장을 그대로 외우는 데서 멈추지 않고, 같은 구조를 새로운 상황에서도 사용할 수 있도록 연습합니다.

STEP 1. 응용 — 같은 구조, 새로운 상황
AI가 선택한 문장의 핵심 문법과 어순을 활용해, 주제와 상황이 다른 새로운 문제를 제시합니다. 문제는 해당 대화의 원문 언어로 제공됩니다.

STEP 2. 도전 — 정답을 보기 전에 직접 말하기
제시된 뜻을 배울 언어로 직접 표현하고 녹음합니다. 한국어 대화를 영어로 공부하는 경우에는 한국어 문제를 보고 스스로 영어 문장을 만들어 말합니다.

STEP 3. 교정 — 의미와 표현을 함께 점검하기
AI가 문제의 뜻을 제대로 전달했는지, 문법·시제·어순·단어 선택이 적절한지 확인합니다. 올바르게 말한 문장은 존중하고, 실제 오류가 있는 부분을 교정합니다. 수정 이유와 더 자연스러운 표현의 활용 팁도 원문 언어로 안내합니다.

STEP 4. 습득 — 듣고 따라 말하기
교정된 문장을 AI 음성으로 듣고 소리 내어 따라 말합니다. 뜻을 이해하는 데서 한 걸음 더 나아가, 표현을 실제 말하기에 사용할 수 있도록 반복합니다.

4. 다른 표현 보기 [같은 뜻, 다양한 말투]

문장 옆의 [다른 표현 보기]를 눌러 같은 의미를 다른 스타일로 비교해 보세요.

영어 학습에서는 현재 적용 중인 스타일을 제외한 Standard, American, British, Native 표현을 확인할 수 있습니다. 뜻과 화자의 관점은 유지하면서, 어휘와 말투가 어떻게 달라지는지 살펴봅니다.

5. Snap Echoing·쉐도잉 [ESSAY를 내 목소리로 익히기]

ESSAY는 두 가지 방식으로 훈련할 수 있습니다.

Snap Echoing [듣고 나서 따라 말하기]

- AI 음성을 의미 단위로 끊어 듣고, 내 차례에 따라 말합니다.
- 이어서 전체를 듣고, AI 음성이 끝난 뒤 혼자 처음부터 끝까지 말합니다.
- AI 음성과 내 녹음을 다시 들으며 발음, 억양, 호흡을 비교합니다.

Shadowing [AI 음성과 함께 말하기]

- AI가 읽는 글 전체를 들으며 함께 따라 말합니다.
- 발음뿐 아니라 문장의 리듬과 자연스러운 연결을 연습합니다.
- 쉐도잉에서는 AI가 호흡 사이를 넉넉히 쉬어 읽어, 따라가기가 한결 편합니다.
- 연습 후 AI 음성과 내 녹음을 비교해 보세요.

에코잉과 쉐도잉은 각각 선택하는 훈련입니다. 에코잉을 마쳤다고 자동으로 쉐도잉으로 넘어가지는 않습니다.

팁: 따라 말할 때 볼륨을 줄이면 AI 소리만 작아집니다. 내 목소리는 그대로 또렷하게 녹음됩니다.

6. Keepers [내 표현 보관함]

다시 연습하고 싶은 말풍선을 길게 누르면 Keepers에 저장됩니다.

모아 둔 문장은 소리 듣기, 실전 튜터링, 다른 표현 보기로 복습할 수 있습니다. 자주 쓰고 싶은 표현을 모아 나만의 말하기 자료로 만들어 보세요.

Keepers는 원래 대화 기록과 별도로 보관됩니다. 대화방을 삭제해도 저장한 표현은 남고, Keepers에서 표현을 삭제해도 원래 대화는 바뀌지 않습니다.

[공부방 체험 · 10분]

실제 대화로 만든 공부방 하나를 10분 동안 무료로 써 볼 수 있습니다. 체험은 폰 하나에 한 번입니다.

내가 나눈 대화로 배우고, 내가 하고 싶은 말을 직접 연습하세요. 스텔스복스는 대화의 경험을 말하기 훈련으로 연결합니다.
```

---

## 영어 원본(개정안) — en-US 교체용, 위 10개 언어의 기준

**제목** (그대로)
```
StealthVox: Practice Real Talk
```

**짧은 설명** (그대로)
```
Practice English with AI, partners, and conversations from your real life.
```

**자세한 설명**
```
Turn real conversations into speaking practice that matters.

StealthVox turns your conversations with people and with AI into English speaking practice. After you talk, open the Study Room and practice the exact sentences you wanted to say.

■ CONVERSATION MODES

Duo — Connect with a partner through an invitation link.
• Direct Call: Talk with your real voices. Conversations with family, friends, or coworkers become practice material.
• Live Interpreter: Each person speaks their own language while AI interprets, so a one-to-one conversation keeps going across language barriers.

Circle Talk — Choose a community such as travel, sports, movies, or business. AI joins as a member and adapts to the circle's topics, tone, and atmosphere.

Scenario Talk — Talk with AI in a specific role and situation, from everyday life to business. Instead of reading fixed lines, respond to reactions and the natural flow of the conversation.

■ CONVERSATION HISTORY

Conversations are saved in segments of up to 10 minutes. If you finish earlier, everything recorded up to that point is still saved. Continue later with the recent conversation and a short summary as context.

■ STUDY ROOM

1. Review and finalize — Fix lines that were heard wrong, then select Finalize Edits. Finalized lines become your practice material.
2. PRACTICE — Have the same conversation again, swapping roles with AI.
3. ESSAY — The conversation woven into one story of your own, in the first person. Practice it with Snap Echoing, which cuts it into meaning units, and Shadowing.
4. Practical tutoring — Make a new sentence with the same structure and say it aloud. AI checks meaning, grammar, tense, word order, and word choice, and explains why and how to sound natural.
5. Other expressions — See different ways to say the same thing. For English, compare Standard, American, British, and Native styles.
6. Keepers — Press and hold a bubble to save it. Saved lines stay even if you delete the original conversation.

■ STUDY ROOM TRIAL

Try a study room made from a real conversation free for 10 minutes (one trial per phone).

Learn from your own conversations and practice the words you actually want to say.
```
