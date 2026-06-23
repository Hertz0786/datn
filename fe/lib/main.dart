import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app/app_shell.dart';
import 'app/app_theme.dart';
import 'core/session/auth_session.dart';
import 'features/call/screens/call_screen.dart';
import 'features/call/screens/outgoing_call_screen.dart';
import 'features/call/widgets/call_observer.dart';
import 'features/onboarding/onboarding_flow_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env', isOptional: true);
  await AuthSession.instance.restore();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AuthSession.instance.isAuthenticated,
      builder: (context, isAuthenticated, _) {
        final Widget home = isAuthenticated
            ? const CallObserver(child: AppShell())
            : const OnboardingFlowScreen();

        return MaterialApp(
          title: 'Kiddo Social',
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: scaffoldMessengerKey,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.system,
          home: home,
          routes: {
            '/call/active': (_) => const CallScreen(),
            '/call/outgoing': (_) => const OutgoingCallScreen(),
          },
        );
      },
    );
  }
}
