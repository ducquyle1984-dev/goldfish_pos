import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';

import 'providers/theme_provider.dart';
import 'themes/app_themes.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/kiosk_check_in_screen.dart';
import 'screens/device_role_screen.dart';
import 'screens/customer_booking_screen.dart';
import 'utils/platform_utils.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load theme preference synchronously (fast, local storage).
  final themeProvider = await ThemeProvider.load();
  // Call runApp immediately so Flutter renders a first frame and the HTML
  // loading spinner is dismissed. Firebase is initialised inside the widget
  // tree via AppInitializer, so a slow / failing network never blocks startup.
  runApp(
    ChangeNotifierProvider.value(
      value: themeProvider,
      child: const AppInitializer(),
    ),
  );
}

/// Initialises Firebase then hands off to [MyApp].
/// Using a FutureBuilder ensures runApp() is called immediately and Flutter
/// always fires its first frame, hiding the HTML loading screen.
class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  late final Future<void> _init;

  @override
  void initState() {
    super.initState();
    _init = Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _init,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return MaterialApp(
            home: Scaffold(
              backgroundColor: const Color(0xFF0D2B45),
              body: Center(
                child: Text(
                  'Could not connect to server.\nPlease refresh the page.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          // Firebase still loading — show a minimal Dart spinner so the
          // HTML overlay is dismissed while we wait.
          return const MaterialApp(
            home: Scaffold(
              backgroundColor: Color(0xFF0D2B45),
              body: Center(
                child: CircularProgressIndicator(color: Color(0xFFFF8C00)),
              ),
            ),
          );
        }
        return const MyApp();
      },
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    return MaterialApp(
      title: 'Goldfish POS',
      theme: themeProvider.useWaterTheme
          ? AppThemes.waterDark
          : AppThemes.light,
      home: _resolveHome(),
      routes: {
        '/kiosk': (_) => const KioskCheckInScreen(),
        '/book': (_) => const CustomerBookingScreen(),
      },
    );
  }

  Widget _resolveHome() {
    // On web, check if the URL path is /book — if so, go straight to the
    // customer booking page without requiring login.
    if (kIsWeb) {
      final path = Uri.base.path;
      if (path == '/book' || path.startsWith('/book/')) {
        return const CustomerBookingScreen();
      }
    }
    return const AuthenticationWrapper();
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}

/// Decides whether to show the login screen or the home page based on
/// Firebase authentication state.
class AuthenticationWrapper extends StatelessWidget {
  const AuthenticationWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          // Show the role-selection screen only when running in a mobile/tablet
          // browser (iPad, iPhone, Android). Desktop browsers and native apps
          // go straight to the POS.
          final showRoleScreen = kIsWeb && isMobileOrTabletBrowser();
          return showRoleScreen ? const DeviceRoleScreen() : const HomeScreen();
        }
        return const LoginScreen();
      },
    );
  }
}
