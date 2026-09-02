import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_font_resolver.dart';
import 'package:teampilot/theme/app_fonts.dart';
import 'package:teampilot/theme/app_markdown_style_sheet.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  test('buildAppMarkdownStyleSheet uses app mono, not monospace', () {
    final fonts = AppFontResolver.resolve(
      uiFontId: 'system',
      monoFontId: 'jetbrainsMono',
      platform: TargetPlatform.linux,
    );
    final theme = buildLightTheme(
      null,
      AppTypographyScale.standard,
      null,
      fonts,
    );
    final sheet = buildAppMarkdownStyleSheet(theme);
    final mono = theme.extension<TpFontTheme>()!;

    expect(sheet.code?.fontFamily, mono.monoFontFamily);
    expect(sheet.code?.fontFamilyFallback, mono.monoFontFamilyFallback);
    expect(sheet.code?.fontFamily, isNot('monospace'));
    expect(sheet.p?.fontFamily, fonts.uiFamily);
    expect(sheet.code?.fontSize, sheet.p?.fontSize);
    expect(sheet.code?.height, sheet.p?.height);
  });

  test('markdown styles keep line height above CJK natural metrics', () {
    // The bundled Noto Sans SC measures ~1.43–1.46em natural ascent+descent;
    // anything tighter overlaps Chinese lines. Guard every block style.
    final fonts = AppFontResolver.resolve(
      uiFontId: 'notoSansSc',
      monoFontId: 'jetbrainsMono',
      platform: TargetPlatform.linux,
    );
    final theme = buildLightTheme(
      null,
      AppTypographyScale.standard,
      null,
      fonts,
    );
    final sheet = buildAppMarkdownStyleSheet(theme);

    final heights = <String, double?>{
      'p': sheet.p?.height,
      'h1': sheet.h1?.height,
      'h2': sheet.h2?.height,
      'h3': sheet.h3?.height,
      'h4': sheet.h4?.height,
      'h5': sheet.h5?.height,
      'h6': sheet.h6?.height,
      'code': sheet.code?.height,
      'listBullet': sheet.listBullet?.height,
      'blockquote': sheet.blockquote?.height,
      'tableHead': sheet.tableHead?.height,
      'tableBody': sheet.tableBody?.height,
    };
    for (final entry in heights.entries) {
      expect(entry.value, greaterThanOrEqualTo(1.5), reason: entry.key);
    }
  });

  // Renders Chinese markdown with the real bundled Noto Sans SC and proves
  // the laid-out line box is not compressed below the font's natural metrics.
  // Skips when the synced google_fonts bundle is absent (clean checkout/CI).
  testWidgets('chinese markdown lines never overlap', (tester) async {
    const fontPath = 'google_fonts/NotoSansSC-Regular.ttf';
    if (!io.File(fontPath).existsSync()) {
      return;
    }
    TestWidgetsFlutterBinding.ensureInitialized();
    final loader = FontLoader('probe-noto-sc');
    loader.addFont(
      Future<ByteData>.value(
        io.File(fontPath).readAsBytesSync().buffer.asByteData(),
      ),
    );
    await loader.load();

    final fonts = AppFontResolver.resolve(
      uiFontId: 'system',
      monoFontId: 'jetbrainsMono',
      platform: TargetPlatform.linux,
    );
    final theme = buildLightTheme(
      null,
      AppTypographyScale.standard,
      null,
      fonts,
    ).copyWith(
      textTheme: ThemeData(brightness: Brightness.light).textTheme.apply(
        fontFamily: 'probe-noto-sc',
      ),
    );
    final baseSheet = buildAppMarkdownStyleSheet(theme);
    final sheet = baseSheet.copyWith(
      p: (baseSheet.p ?? const TextStyle()).copyWith(
        fontFamily: 'probe-noto-sc',
        fontSize: 14,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownBody(
            data: '批量新建服务器\n\n批量修改服务器配置',
            styleSheet: sheet,
          ),
        ),
      ),
    );
    await tester.pump();

    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText).first,
    );
    const fontSize = 14.0;
    final painter = TextPainter(
      text: TextSpan(
        text: '批量新建服务器',
        style: TextStyle(fontFamily: 'probe-noto-sc', fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    expect(paragraph.size.height, greaterThanOrEqualTo(painter.height - 1.0));
  });
}
