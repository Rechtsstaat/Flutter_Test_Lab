import 'package:flutter/material.dart';

import 'data/app_store.dart';
import 'design/tokens.dart';
import 'screens/splash_page.dart';

/// The pieces the widget and integration tests reach for. Keeping them exported
/// here means the file split stays an implementation detail.
export 'data/app_store.dart';
export 'design/components.dart';
export 'design/tokens.dart';
export 'fields.dart';
export 'models/listing.dart';
export 'mirror_session.dart';
export 'remote_form.dart';
export 'screens/home_page.dart';
export 'screens/listing_detail_page.dart';
export 'screens/listing_form_page.dart';
export 'screens/onboarding_flow.dart';
export 'screens/publish_flow_page.dart';
export 'screens/splash_page.dart';
export 'screens/takedown_flow_page.dart';

void main() => runApp(ListingApp(store: AppStore()));

class ListingApp extends StatelessWidget {
  const ListingApp({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '한방',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColor.bgPage,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColor.actionPrimary,
        primary: AppColor.actionPrimary,
        onPrimary: AppColor.actionPrimaryContent,
        surface: AppColor.bgSurface,
        onSurface: AppColor.textPrimary,
        error: AppColor.statusError,
      ),
      splashFactory: InkSparkle.splashFactory,
      dividerTheme: const DividerThemeData(
        color: AppColor.borderSubtle,
        space: 1,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColor.actionPrimary,
        selectionHandleColor: AppColor.actionPrimary,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColor.bgOverlay,
      ),
    ),
    home: SplashPage(store: store),
  );
}
