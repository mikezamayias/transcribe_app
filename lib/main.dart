import 'package:dartnative/dartnative.dart';

import 'dartnative_plugin_registrant.dart';
import 'home_screen.dart';

void main() {
  const isDebug = !bool.fromEnvironment('dart.vm.product');

  DartNativeLogger.run(
    () {
      DartNativePluginRegistrant.registerAll();
      SystemChrome.defaultStyle = const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      );
      runApp(const App(home: HomeScreen()));
    },
    verbose: isDebug,
    saveToFile: isDebug,
  );
}
