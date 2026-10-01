import 'package:flutter/foundation.dart';

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
