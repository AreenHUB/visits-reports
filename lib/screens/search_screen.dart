import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/repository.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../utils/formatting.dart';
import '../utils/theme.dart';
import '../widgets/common.dart';
import 'credits_screen.dart';
import 'home_screen.dart';
import 'scanner_screen.dart';
import 'visit_detail_screen.dart';

/// شاشة البحث: بحث في الزيارات، وتتبّع رقم تسلسلي عبر كل السجلات
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('البحث'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.event_note_rounded, size: 20), text: 'الزيارات'),
            Tab(icon: Icon(Icons.qr_code_2_rounded, size: 20), text: 'تتبّع رقم تسلسلي'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [_VisitSearchTab(), _SerialTraceTab()],
      ),
    );
  }
}

// ------------------------------------------------------------ بحث الزيارات

class _VisitSearchTab extends ConsumerWidget {
  const _VisitSearchTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visitsAsync = ref.watch(allVisitsProvider);
    final query = ref.watch(visitSearchProvider);

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: TextField(
          decoration: InputDecoration(
            hintText: 'ابحث بالاسم أو الهاتف أو الهدف',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear_rounded),
                    onPressed: () => ref.read(visitSearchProvider.notifier).state = '',
                  ),
          ),
          onChanged: (v) => ref.read(visitSearchProvider.notifier).state = v,
        ),
      ),
      Expanded(
        child: visitsAsync.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(e, onRetry: () => bumpRefresh(ref)),
          data: (visits) {
            if (visits.isEmpty) {
              return EmptyState(
                icon: query.isEmpty ? Icons.event_note_rounded : Icons.search_off_rounded,
                title: query.isEmpty ? 'لا توجد زيارات مسجّلة' : 'لا نتائج مطابقة',
                subtitle: query.isEmpty ? 'ابدأ بتسجيل زيارة من تبويب «اليوم»' : null,
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              itemCount: visits.length,
              itemBuilder: (context, i) => VisitCard(vf: visits[i], showDate: true),
            );
          },
        ),
      ),
    ]);
  }
}

// -------------------------------------------------------- تتبّع رقم تسلسلي

class _SerialTraceTab extends ConsumerStatefulWidget {
  const _SerialTraceTab();

  @override
  ConsumerState<_SerialTraceTab> createState() => _SerialTraceTabState();
}

class _SerialTraceTabState extends ConsumerState<_SerialTraceTab> {
  final _controller = TextEditingController();
  String _serial = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search(String value) {
    final v = value.trim();
    if (v.isEmpty) return;
    setState(() => _serial = v);
  }

  Future<void> _scan() async {
    final result = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerScreen(continuous: false)),
    );
    if (result == null || result.isEmpty) return;
    _controller.text = result.first;
    _search(result.first);
  }

  @override
  Widget build(BuildContext context) {
    final traceAsync = ref.watch(serialTraceProvider(_serial));
    final scheme = Theme.of(context).colorScheme;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _controller,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              decoration: InputDecoration(
                hintText: 'أدخل الرقم التسلسلي',
                hintTextDirection: TextDirection.rtl,
                prefixIcon: const Icon(Icons.qr_code_2_rounded),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _serial = '');
                        },
                      ),
              ),
              onSubmitted: _search,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _scan,
            icon: const Icon(Icons.qr_code_scanner_rounded),
            tooltip: 'مسح بالكاميرا',
            style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
          ),
        ]),
      ),

      Expanded(
        child: _serial.isEmpty
            ? const EmptyState(
                icon: Icons.qr_code_scanner_rounded,
                title: 'تتبّع أي قطعة',
                subtitle:
                    'امسح أو أدخل رقمًا تسلسليًا لترى أين ذهبت هذه القطعة ومتى، وعند من هي الآن',
              )
            : traceAsync.when(
                loading: () => const LoadingView(),
                error: (e, _) => ErrorView(e),
                data: (traces) {
                  if (traces.isEmpty) {
                    return EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'لا سجلات لهذا الرقم',
                      subtitle: _serial,
                    );
                  }

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    children: [
                      // ملخص: أين القطعة الآن
                      _CurrentLocationCard(traces: traces, serial: _serial),
                      const SizedBox(height: 6),
                      SectionHeader('سجل الحركة (${traces.length})',
                          icon: Icons.history_rounded),
                      ...traces.map((t) => _TraceTile(trace: t)),
                    ],
                  );
                },
              ),
      ),

      if (_serial.isNotEmpty)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
          child: Row(children: [
            Icon(Icons.tag_rounded, size: 15, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _serial,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.left,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ]),
        ),
    ]);
  }
}

/// يلخّص آخر حركة: هل القطعة عند العميل أم رجعت للمحل
class _CurrentLocationCard extends StatelessWidget {
  final List<SerialTrace> traces;
  final String serial;

  const _CurrentLocationCard({required this.traces, required this.serial});

  @override
  Widget build(BuildContext context) {
    // السجلات مرتّبة تنازليًا، فأحدثها هو الأول
    final latest = traces.first;
    final isOut = latest.item.kind == MovementKind.out;
    final color = isOut ? AppTheme.warning : AppTheme.success;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            isOut ? Icons.person_pin_circle_rounded : Icons.store_rounded,
            color: color,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isOut ? 'القطعة عند العميل' : 'القطعة راجعة للمحل',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(
              isOut
                  ? '${latest.partyName} — منذ ${Fmt.date(latest.date)}'
                  : 'رجعت بتاريخ ${Fmt.date(latest.date)}',
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 3),
            Text(latest.item.description,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ]),
        ),
      ]),
    );
  }
}

class _TraceTile extends StatelessWidget {
  final SerialTrace trace;
  const _TraceTile({required this.trace});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isOut = trace.item.kind == MovementKind.out;
    final color = isOut ? AppTheme.warning : AppTheme.success;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => trace.isVisit
                ? VisitDetailScreen(visitId: trace.recordId)
                : CreditDetailScreen(creditId: trace.recordId),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isOut ? Icons.upload_rounded : Icons.download_rounded,
                size: 18,
                color: color,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(trace.partyName,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      trace.isVisit ? 'زيارة' : 'سحب آجل',
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
                const SizedBox(height: 3),
                Text(
                  '${Fmt.dateWithDay(trace.date)}  •  ${trace.item.kind.label}',
                  style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 3),
                Text(trace.item.description, style: const TextStyle(fontSize: 12.5)),
              ]),
            ),
            Text(Fmt.moneyShort(trace.item.total),
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, color: color)),
          ]),
        ),
      ),
    );
  }
}
