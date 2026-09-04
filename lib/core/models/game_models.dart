class TriviaQuestion {
  const TriviaQuestion({
    required this.id,
    required this.category,
    required this.difficulty,
    required this.question,
    required this.answer,
    this.acceptedAnswers = const <String>[],
    this.explanation,
  });
  final String id;
  final String category;
  final String difficulty;
  final String question;
  final String answer;
  final List<String> acceptedAnswers;
  final String? explanation;

  factory TriviaQuestion.fromJson(Map<String, dynamic> json) => TriviaQuestion(
    id: json['id'] as String,
    category: json['category'] as String,
    difficulty: json['difficulty'] as String,
    question: json['question'] as String,
    answer: json['answer'] as String,
    acceptedAnswers:
        (json['acceptedAnswers'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<String>()
            .toList(),
    explanation: json['explanation'] as String?,
  );
}

class TruthDareCard {
  const TruthDareCard({
    required this.id,
    required this.type,
    required this.text,
    required this.category,
    required this.intensity,
  });
  final String id;
  final String type;
  final String text;
  final String category;
  final int intensity;
  factory TruthDareCard.fromJson(Map<String, dynamic> json) => TruthDareCard(
    id: json['id'] as String,
    type: json['type'] as String,
    text: json['text'] as String,
    category: json['category'] as String,
    intensity: (json['intensity'] as num).toInt(),
  );
}

class PictionaryPrompt {
  const PictionaryPrompt({
    required this.id,
    required this.word,
    required this.category,
    required this.difficulty,
    this.hint,
  });
  final String id;
  final String word;
  final String category;
  final String difficulty;
  final String? hint;
  factory PictionaryPrompt.fromJson(Map<String, dynamic> json) =>
      PictionaryPrompt(
        id: json['id'] as String,
        word: json['word'] as String,
        category: json['category'] as String,
        difficulty: json['difficulty'] as String,
        hint: json['hint'] as String?,
      );
}

class ActingPrompt {
  const ActingPrompt({
    required this.id,
    required this.category,
    required this.text,
  });
  final String id;
  final String category;
  final String text;
  factory ActingPrompt.fromJson(Map<String, dynamic> json) => ActingPrompt(
    id: json['id'] as String,
    category: json['category'] as String,
    text: json['text'] as String,
  );
}

class CountdownPrompt {
  const CountdownPrompt({
    required this.id,
    required this.level,
    required this.text,
  });
  final String id;
  final int level;
  final String text;
  factory CountdownPrompt.fromJson(Map<String, dynamic> json) =>
      CountdownPrompt(
        id: json['id'] as String,
        level: (json['level'] as num).toInt(),
        text: json['text'] as String,
      );
}

class ImposterWord {
  const ImposterWord({
    required this.id,
    required this.category,
    required this.word,
    required this.groupId,
    required this.hint,
  });
  final String id;
  final String category;
  final String word;
  final String groupId;
  final String hint;
  factory ImposterWord.fromJson(Map<String, dynamic> json) => ImposterWord(
    id: json['id'] as String,
    category: json['category'] as String,
    word: json['word'] as String,
    groupId: json['groupId'] as String,
    hint: json['hint'] as String,
  );
}

class DrawPoint {
  const DrawPoint(this.x, this.y);
  final double x;
  final double y;
  Map<String, dynamic> toJson() => <String, dynamic>{'x': x, 'y': y};
  factory DrawPoint.fromJson(Map<String, dynamic> json) =>
      DrawPoint((json['x'] as num).toDouble(), (json['y'] as num).toDouble());
}

class DrawStroke {
  const DrawStroke({
    required this.colorValue,
    required this.width,
    required this.points,
  });
  final int colorValue;
  final double width;
  final List<DrawPoint> points;
  Map<String, dynamic> toJson() => <String, dynamic>{
    'colorValue': colorValue,
    'width': width,
    'points': points.map((DrawPoint point) => point.toJson()).toList(),
  };
}
