import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'data/app_store.dart';
import 'data/database.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'FlClash liquid glass and navigation',
    ], await rootBundle.loadString('third_party/FlClash/LICENSE'));
  });
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const Bootstrap());
}

class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});
  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  late Future<AppStore> _opening = _open();
  Future<AppStore> _open() async {
    final store = AppStore(AppDatabase());
    try {
      await store.initialize();
      return store;
    } catch (_) {
      await store.db.close();
      store.dispose();
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AppStore>(
    future: _opening,
    builder: (context, snapshot) {
      if (snapshot.hasData) return OpenMarkjiApp(store: snapshot.data!);
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xff5479bc),
        ),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: snapshot.hasError
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.folder_off_outlined, size: 48),
                        const SizedBox(height: 16),
                        const Text('资料库暂时无法打开'),
                        const SizedBox(height: 12),
                        SelectableText('${snapshot.error}'),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: () => setState(() => _opening = _open()),
                          child: const Text('重试'),
                        ),
                      ],
                    )
                  : const CircularProgressIndicator(),
            ),
          ),
        ),
      );
    },
  );
}
