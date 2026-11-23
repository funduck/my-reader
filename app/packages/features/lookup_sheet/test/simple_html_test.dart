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

  test('block tags start lines, empty lines collapse', () {
    expect(_plain('<div>a</div><div>b</div>'), 'a\nb');
    expect(_plain('<div>a<br><br>b</div>\n<p></p><h1>c</h1>'), 'a\nb\nc');
    expect(_plain('  <div> a </div> '), 'a');
    expect(
      _plain('<table><tr><td>a</td></tr><tr><td>b</td></tr></table>'),
      'a\nb',
    );
    expect(_plain('<blockquote>q</blockquote>after'), 'q\nafter');
  });

  test('lists: numbers, bullets and nesting', () {
    expect(
      _plain('<ol><li>a</li><li>b<ul><li>x</li><li>y</li></ul></li></ol>'),
      '1. a\n2. b\n  • x\n  • y',
    );
    expect(_plain('<li>loose</li>'), '• loose');
    expect(
      _plain('<ol><li><div>one</div></li><li> two </li></ol>'),
      '1. one\n2. two',
    );
  });

  test('article "scare" from the en-ru dictionary', () {
    const html =
        '<div>/<font color="gray">skeə</font>/, /<font color="gray">skeɹ</font>/<br>\n'
        '<div><font class="grammar" color="green">noun</font></div><ol><li>something that inspires fear<ol><li><div>жу́пел</div></li><li><div>пу́гало</div></li></ol></li><li>minor fright<ol><li><div>страх</div></li><li><div>испу́г</div></li><li><div>па́ника</div></li></ol></li></ol></div>\n'
        '<div>/<font color="gray">skeə</font>/<br>\n'
        '<div><font class="grammar" color="green">verb</font></div>to frighten<ol><li><div>пуга́ть</div></li><li><div>испуга́ть</div></li></ol></div>';
    expect(
      _plain(html),
      [
        '/skeə/, /skeɹ/',
        'noun',
        '1. something that inspires fear',
        '  1. жу́пел',
        '  2. пу́гало',
        '2. minor fright',
        '  1. страх',
        '  2. испу́г',
        '  3. па́ника',
        '/skeə/',
        'verb',
        'to frighten',
        '1. пуга́ть',
        '2. испуга́ть',
      ].join('\n'),
    );
  });

  test('sense prefix stays on the first line of the article', () {
    final span = TextSpan(
      children: [
        const TextSpan(text: '2. '),
        ...parseSimpleHtml('<div>a</div><div>b</div>'),
      ],
    );
    expect(span.toPlainText(), '2. a\nb');
  });
}
