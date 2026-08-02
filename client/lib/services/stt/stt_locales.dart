import 'speech_recognizer.dart';
import 'stt_provider.dart';

/// Fallback list for on-device recognition, used when the platform cannot
/// enumerate its own locales.
const _systemFallback = <SpeechLocale>[
  SpeechLocale(id: 'zh_CN', name: '简体中文'),
  SpeechLocale(id: 'en_US', name: 'English (US)'),
  SpeechLocale(id: 'en_GB', name: 'English (UK)'),
  SpeechLocale(id: 'ja_JP', name: '日本語'),
  SpeechLocale(id: 'ko_KR', name: '한국어'),
  SpeechLocale(id: 'fr_FR', name: 'Français'),
  SpeechLocale(id: 'de_DE', name: 'Deutsch'),
  SpeechLocale(id: 'es_ES', name: 'Español'),
  SpeechLocale(id: 'ru_RU', name: 'Русский'),
  SpeechLocale(id: 'pt_BR', name: 'Português (BR)'),
];

/// Volcengine's supported recognition languages.
const _volcengine = <SpeechLocale>[
  SpeechLocale(id: 'zh-CN', name: '简体中文'),
  SpeechLocale(id: 'en-US', name: 'English (US)'),
  SpeechLocale(id: 'ja-JP', name: '日本語'),
  SpeechLocale(id: 'ko-KR', name: '한국어'),
];

/// Alibaba NLS's supported recognition languages.
const _aliyun = <SpeechLocale>[
  SpeechLocale(id: 'zh-CN', name: '简体中文'),
  SpeechLocale(id: 'zh-HK', name: '粤语'),
  SpeechLocale(id: 'en-US', name: 'English (US)'),
  SpeechLocale(id: 'ja-JP', name: '日本語'),
  SpeechLocale(id: 'ko-KR', name: '한국어'),
  SpeechLocale(id: 'ru-RU', name: 'Русский'),
  SpeechLocale(id: 'id-ID', name: 'Bahasa Indonesia'),
];

/// The languages [type] can recognize.
///
/// Language names stay in their own language rather than going through l10n: a
/// picker that renders every entry in the current UI locale is harder to scan
/// than one where each row reads as the language it selects.
List<SpeechLocale> sttLocalesFor(SttProviderType type) => List.unmodifiable(
  switch (type) {
    SttProviderType.system => _systemFallback,
    SttProviderType.volcengine => _volcengine,
    SttProviderType.aliyun => _aliyun,
  },
);
