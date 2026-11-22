import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup_sheet/lookup_sheet.dart';

String _plain(String html) =>
    TextSpan(children: parseSimpleHtml(html)).toPlainText();

void main() {
  test('detects tags', () {
    expect(looksLikeHtml('a <b>b</b>'), isTrue);
    expect(looksLikeHtml('a < b and c > d'), isFalse);
    expect(looksLikeHtml('plain'), isFalse);
  });

  test('keeps text of unknown tags and drops the tags', () {
    expect(_plain('<div class="x">one <a href="u">two</a></div>'), 'one two');
  });

  test('br and p break lines', () {
    expect(_plain('one<br>two<p>three</p>four'), 'one\ntwo\nthree\nfour');
    expect(_plain('<p>first</p><p>second</p>'), 'first\nsecond');
  });

  test('b and i style their content', () {
    final spans = parseSimpleHtml('x <b>bold <i>both</i></b> <em>it</em>');
    final styled = [
      for (final s in spans.cast<TextSpan>())
        (s.text, s.style?.fontWeight, s.style?.fontStyle),
    ];
    expect(styled, [
      ('x ', null, null),
      ('bold ', FontWeight.bold, null),
      ('both', FontWeight.bold, FontStyle.italic),
      (' ', null, null),
      ('it', null, FontStyle.italic),
    ]);
  });

  test('decodes entities and drops script and style', () {
    expect(
      _plain('<style>p{}</style>a &amp; b &lt;c&gt; &#65;&#x42;'),
      'a & b <c> AB',
    );
    expect(_plain('x<script>alert(1)</script>y'), 'xy');
  });

  test('source line breaks are spaces', () {
    expect(_plain('one\n   two'), 'one two');
  });
}
