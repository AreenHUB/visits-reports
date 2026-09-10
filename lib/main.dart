import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'db/app_database.dart';
import 'screens/cash_screen.dart';
import 'screens/credits_screen.dart';
import 'screens/home_screen.dart';
import 'screens/more_screen.dart';
import 'screens/reports_screen.dart';
import 'utils/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // نهيّئ كل اللغات المستخدمة: العربية للواجهة، و en_US للتواريخ والأرقام
  // في التقارير. بدون هذا يفشل توليد الـ PDF عند أول تنسيق تاريخ.
  await initializeDateFormatting('ar');
  await initializeDateFormatting('en_US');

  // نفتح قاعدة البيانات مبكرًا حتى لا تتأخر أول شاشة
  await AppDatabase.instance.database;

  runApp(const ProviderScope(child: AlAqsaApp()));
}

class AlAqsaApp extends StatelessWidget {
  const AlAqsaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'الأقصى - الزيارات',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,

      // التطبيق عربي بالكامل، الاتجاه من اليمين لليسار
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),

      home: const RootShell(),
    );
  }
}

/// الهيكل الرئيسي مع شريط التنقّل السفلي
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  // خمسة تبويبات فقط: البحث والإعدادات والرواتب والديون تحت «المزيد»
  // حتى لا يزدحم الشريط السفلي.
  static const _screens = [
    HomeScreen(),
    CashScreen(),
    CreditsScreen(),
    ReportsScreen(),
    MoreScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today_rounded),
            label: 'اليوم',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet_rounded),
            label: 'الصندوق',
          ),
          NavigationDestination(
            icon: Icon(Icons.handshake_outlined),
            selectedIcon: Icon(Icons.handshake_rounded),
            label: 'الآجل',
          ),
          NavigationDestination(
            icon: Icon(Icons.assessment_outlined),
            selectedIcon: Icon(Icons.assessment_rounded),
            label: 'التقارير',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'المزيد',
          ),
        ],
      ),
    );
  }
}
