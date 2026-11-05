import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preload_page_view/preload_page_view.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:zai_x/modules/comic/reader/comic_reader_viewport.dart';
import 'package:zai_x/modules/comic/reader/comic_strip_viewport.dart';
import 'package:zai_x/widgets/chapter_swipe_boundary.dart';

TransformationController _transform(WidgetTester tester) => tester
    .widget<InteractiveViewer>(find.byType(InteractiveViewer))
    .transformationController!;

Future<void> _doubleTap(WidgetTester tester, Offset point,
    {bool settle = true}) async {
  await tester.tapAt(point);
  await tester.pump(kDoubleTapMinTime);
  await tester.tapAt(point);
  await tester.pump();
  if (settle) await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'edge double tap zooms around the tap without firing a single tap',
      (tester) async {
    final taps = <double>[];
    await tester.pumpWidget(MaterialApp(
      home: ComicReaderViewport(
        zoomEnabled: true,
        resetToken: 1,
        pageKey: 0,
        onTap: taps.add,
        onPreviousPage: () {},
        onNextPage: () {},
        builder: (_, locked, decoratePage) =>
            const ColoredBox(color: Colors.black),
      ),
    ));

    const point = Offset(750, 320);
    final transform = _transform(tester);
    await _doubleTap(tester, point, settle: false);
    expect(transform.value.getMaxScaleOnAxis(), 1);
    await tester.pump(const Duration(milliseconds: 110));
    expect(transform.value.getMaxScaleOnAxis(), inExclusiveRange(1.0, 2.5));
    expect((transform.toScene(point) - point).distance, lessThan(1e-6));
    await tester.pumpAndSettle();

    expect(transform.value.getMaxScaleOnAxis(), 2.5);
    expect(transform.toScene(point), point);
    expect(taps, isEmpty);

    await tester.tapAt(point);
    await tester.pump(kDoubleTapTimeout);
    expect(taps, [750 / 800]);
    taps.clear();

    await _doubleTap(tester, point, settle: false);
    expect(transform.value.getMaxScaleOnAxis(), 2.5);
    await tester.pump(const Duration(milliseconds: 110));
    expect(transform.value.getMaxScaleOnAxis(), inExclusiveRange(1.0, 2.5));
    await tester.pumpAndSettle();
    expect(transform.value.isIdentity(), isTrue);
    expect(taps, isEmpty);
  });

  testWidgets('pinch clamps scale and zoom reset keeps the same viewport',
      (tester) async {
    Widget reader(int chapter) => MaterialApp(
          home: ComicReaderViewport(
            zoomEnabled: true,
            resetToken: chapter,
            pageKey: 0,
            onTap: (_) {},
            onPreviousPage: () {},
            onNextPage: () {},
            builder: (_, locked, decoratePage) =>
                const ColoredBox(color: Colors.black),
          ),
        );
    await tester.pumpWidget(reader(1));
    final transform = _transform(tester);

    final left = await tester.startGesture(const Offset(380, 300));
    final right = await tester.startGesture(const Offset(420, 300));
    await tester.pump();
    await left.moveTo(const Offset(345, 300));
    await right.moveTo(const Offset(455, 300));
    await left.moveTo(const Offset(30, 300));
    await right.moveTo(const Offset(770, 300));
    await tester.pump();
    expect(transform.value.getMaxScaleOnAxis(), closeTo(4, 1e-6));

    await left.moveTo(const Offset(399, 300));
    await right.moveTo(const Offset(401, 300));
    await tester.pump();
    expect(transform.value.getMaxScaleOnAxis(), closeTo(1, 1e-6));
    await left.up();
    await right.up();
    await tester.pumpAndSettle();

    await _doubleTap(tester, const Offset(400, 300), settle: false);
    await tester.pump(const Duration(milliseconds: 110));
    expect(transform.value.getMaxScaleOnAxis(), greaterThan(1));
    await tester.pumpWidget(reader(2));
    await tester.pumpAndSettle();
    expect(_transform(tester), same(transform));
    expect(transform.value.isIdentity(), isTrue);
  });

  testWidgets('zoomed drag keeps its first delta and flings within the image',
      (tester) async {
    var pageTurns = 0;
    await tester.pumpWidget(MaterialApp(
      home: ComicReaderViewport(
        zoomEnabled: true,
        resetToken: 1,
        pageKey: 0,
        onTap: (_) {},
        onPreviousPage: () => pageTurns++,
        onNextPage: () => pageTurns++,
        builder: (_, locked, decoratePage) =>
            const ColoredBox(color: Colors.black),
      ),
    ));

    const center = Offset(400, 300);
    await _doubleTap(tester, center);
    final transform = _transform(tester);
    double x() => transform.value.getTranslation().x;
    final start = x();
    final drag = await tester.startGesture(center);
    await drag.moveBy(const Offset(-24, 0),
        timeStamp: const Duration(milliseconds: 16));
    await tester.pump();
    expect(x(), start - 24);
    await drag.moveBy(const Offset(-28, 0),
        timeStamp: const Duration(milliseconds: 32));
    final release = x();
    await drag.up(timeStamp: const Duration(milliseconds: 33));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    expect(x(), lessThan(release));

    final stopped = x();
    final grab = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 150));
    expect(x(), stopped);
    await grab.cancel();

    await tester.flingFrom(center, const Offset(-240, 0), 3500);
    await tester.pumpAndSettle();
    expect(x(), closeTo(-1200, 1e-6));
    expect(pageTurns, 0);
  });

  for (final reverse in [false, true]) {
    testWidgets(
        'edge drag follows the finger and restores zoom (RTL: $reverse)',
        (tester) async {
      final pages = PreloadPageController();
      addTearDown(pages.dispose);
      var currentPage = 0;
      var nextChapters = 0;
      void nextPage() {
        if (currentPage == 0) {
          pages.jumpToPage(1);
        } else {
          nextChapters++;
        }
      }

      await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(
          builder: (_, rebuild) => ComicReaderViewport(
            zoomEnabled: true,
            resetToken: 1,
            pageKey: currentPage,
            onTap: (_) {},
            reverse: reverse,
            onPreviousPage: () => pages.jumpToPage(0),
            onNextPage: nextPage,
            previewBuilder: (next) => (
              pageKey: next ? 1 : 0,
              child: const ColoredBox(
                key: ValueKey('adjacent-page'),
                color: Colors.green,
              ),
            ),
            builder: (_, locked, decoratePage) => ChapterSwipeBoundary(
              enabled: !locked,
              reverse: reverse,
              canGoPrevious: false,
              canGoNext: currentPage == 1,
              onPrevious: () {},
              onNext: () => nextChapters++,
              child: PreloadPageView.builder(
                controller: pages,
                reverse: reverse,
                itemCount: 2,
                physics: locked ? const NeverScrollableScrollPhysics() : null,
                onPageChanged: (index) => rebuild(() => currentPage = index),
                itemBuilder: (_, index) => decoratePage(
                  index,
                  ColoredBox(
                    key: ValueKey('page-$index'),
                    color: index == 0 ? Colors.black : Colors.blue,
                  ),
                ),
              ),
            ),
          ),
        ),
      ));

      const center = Offset(400, 300);
      final sign = reverse ? 1.0 : -1.0;
      final panStart = Offset(reverse ? 40 : 760, 300);
      final transform = _transform(tester);
      await _doubleTap(tester, center);
      final drag = await tester.startGesture(panStart);
      await drag.moveBy(Offset(sign * 700, 0));
      await tester.pump();
      final viewport = find.byType(InteractiveViewer);
      final pulled = tester.getTopLeft(viewport).dx * sign;
      expect(pulled, greaterThan(40));
      expect(find.byKey(const ValueKey('adjacent-page')), findsOneWidget);
      expect(pages.page, 0);

      await drag.moveBy(Offset(-sign * 25, 0));
      await tester.pump();
      expect(tester.getTopLeft(viewport).dx * sign, closeTo(pulled - 25, 1e-6));
      await tester.pump(const Duration(milliseconds: 200));
      await drag.up();
      await tester.pumpAndSettle();
      expect(pages.page, 0);
      expect(tester.getTopLeft(viewport).dx, 0);
      expect(
          transform.value.getTranslation().x, closeTo(reverse ? 0 : -1200, 1));

      await tester.flingFrom(center, Offset(sign * 250, 0), 1000);
      await tester.pumpAndSettle();
      expect(pages.page, 1);
      expect(currentPage, 1);
      expect(transform.value.getMaxScaleOnAxis(), 1);
      expect(transform.value.getTranslation().x, closeTo(0, 1e-6));

      await _doubleTap(tester, center);
      await tester.dragFrom(panStart, Offset(sign * 700, 0));
      await tester.pumpAndSettle();
      expect(nextChapters, 0);
      await tester.flingFrom(center, Offset(sign * 250, 0), 1000);
      await tester.pumpAndSettle();
      expect(nextChapters, 1);

      await _doubleTap(tester, center);
      final back = await tester.startGesture(Offset(reverse ? 760 : 40, 300));
      await back.moveBy(Offset(-sign * 40, 0));
      await back.moveBy(Offset(-sign * 200, 0));
      await tester.pump();
      expect(currentPage, 1);
      final pageA = find.byKey(const ValueKey('page-0'));
      double paintedScale() =>
          tester.renderObject(pageA).getTransformTo(null).getMaxScaleOnAxis();
      expect(paintedScale(), 2.5);

      await back.moveBy(Offset(-sign * 300, 0));
      await tester.pump();
      expect(currentPage, 0);
      expect(transform.value.getMaxScaleOnAxis(), 1);
      expect(paintedScale(), 2.5);
      await back.up();
      await tester.pumpAndSettle();
      expect(pages.page, 0);
      expect(transform.value.getMaxScaleOnAxis(), 2.5);
      expect(paintedScale(), 2.5);
      expect(
          transform.value.getTranslation().x, closeTo(reverse ? 0 : -1200, 1));
    });
  }

  testWidgets('strip zoom holds its focal point and scrolls across images',
      (tester) async {
    final pages = ItemScrollController();
    final positions = ItemPositionsListener.create();
    var chapterTurns = 0;
    await tester.pumpWidget(MaterialApp(
      home: ComicStripViewport(
        zoomEnabled: true,
        animateZoom: true,
        onTap: (_) {},
        builder: (_, locked) => EasyRefresh(
          onRefresh: locked ? null : () async => chapterTurns++,
          child: ScrollablePositionedList.builder(
            itemScrollController: pages,
            physics: locked ? const NeverScrollableScrollPhysics() : null,
            itemPositionsListener: positions,
            itemCount: 20,
            itemBuilder: (_, index) => SizedBox(
              key: ValueKey('strip-$index'),
              height: 170,
            ),
          ),
        ),
      ),
    ));

    final strip = find.byType(ScrollablePositionedList);
    final scrollable =
        find.descendant(of: strip, matching: find.byType(Scrollable));
    ScrollPosition position() =>
        tester.state<ScrollableState>(scrollable).position;
    double scale() =>
        tester.renderObject(strip).getTransformTo(null).getMaxScaleOnAxis();
    bool firstImageVisible() => positions.itemPositions.value.any((item) =>
        item.index == 0 &&
        item.itemTrailingEdge > 0 &&
        item.itemLeadingEdge < 1);
    final firstImage = find.byKey(const ValueKey('strip-0'));
    const focal = Offset(400, 120);
    await _doubleTap(tester, focal);
    expect(scale(), 2.5);
    expect(position().viewportDimension, 240);
    expect(position().pixels, closeTo(72, 1e-6));
    expect(tester.getTopLeft(firstImage).dy + 120 * scale(),
        closeTo(focal.dy, 1e-6));

    final scroll = await tester.startGesture(const Offset(400, 540));
    await scroll.moveBy(const Offset(0, -30));
    await scroll.moveBy(const Offset(0, -375));
    await tester.pump();
    expect(firstImageVisible(), isFalse);
    expect(scale(), 2.5);
    await scroll.moveBy(const Offset(0, 290));
    await tester.pump();
    expect(firstImageVisible(), isTrue);
    expect(scale(), 2.5);
    await scroll.up();
    await tester.pumpAndSettle();

    final y = position().pixels;
    double x() => tester.getTopLeft(strip).dx;
    final beforePan = x();
    final pan = await tester.startGesture(const Offset(400, 300));
    await pan.moveBy(const Offset(-24, 0),
        timeStamp: const Duration(milliseconds: 16));
    await tester.pump();
    expect(x(), closeTo(beforePan - 24, 1e-6));
    await pan.moveBy(const Offset(-28, 0),
        timeStamp: const Duration(milliseconds: 32));
    await tester.pump();
    final panRelease = x();
    await pan.up(timeStamp: const Duration(milliseconds: 33));
    await tester.pumpAndSettle();
    expect(position().pixels, y);
    expect(x(), lessThan(panRelease));

    await tester.flingFrom(const Offset(400, 500), const Offset(0, -140), 800);
    await tester.pump();
    final scrollRelease = position().pixels;
    await tester.pump(const Duration(milliseconds: 70));
    expect(position().pixels, greaterThan(scrollRelease));
    await tester.pumpAndSettle();
    expect(scale(), 2.5);
    expect(chapterTurns, 0);

    await _doubleTap(tester, focal);
    expect(scale(), 1);
    expect(position().viewportDimension, 600);

    final left = await tester.startGesture(const Offset(380, 300));
    final right = await tester.startGesture(const Offset(420, 300));
    await tester.pump();
    await left.moveTo(const Offset(345, 300));
    await right.moveTo(const Offset(455, 300));
    await left.moveTo(const Offset(30, 300));
    await right.moveTo(const Offset(770, 300));
    await tester.pump();
    expect(scale(), 4);
    expect(position().viewportDimension, 150);

    await left.moveTo(const Offset(399, 300));
    await right.moveTo(const Offset(401, 300));
    await tester.pump();
    expect(scale(), 1);
    await left.up();
    await right.up();
    await tester.pumpAndSettle();
    expect(chapterTurns, 0);
  });
}
