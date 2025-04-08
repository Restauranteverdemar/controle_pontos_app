// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:controle_pontos_app/features/auth/widgets/auth_wrapper.dart'; // Verifique o caminho se necessário
// Removido import não utilizado: import 'package:firebase_storage/firebase_storage.dart';
import 'package:provider/provider.dart'; // Importação necessária para o Provider

// --- IMPORTS DOS SERVIÇOS ---
// Importação para o serviço de regras automáticas (já existia)
import 'features/admin/services/automation_rule_service.dart';
// --- !!! IMPORTAÇÃO ADICIONADA PARA PointOccurrenceService !!! ---
// Certifique-se de que este caminho está correto no seu projeto
import 'features/shared/services/point_occurrence_service.dart';

// --- (Opcional) Importe outros serviços globais aqui, se houver ---
// Exemplo: import 'features/auth/services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Usa MultiProvider para fornecer múltiplos serviços globalmente
    return MultiProvider(
      providers: [
        // --- LISTA DE PROVIDERS GLOBAIS ---

        // Adicione aqui outros providers existentes do seu projeto
        // Exemplo: Se você tiver um serviço de autenticação global:
        // ChangeNotifierProvider(create: (_) => AuthService()),

        // Provider para o serviço de regras automáticas (já existia)
        ChangeNotifierProvider(
          create: (_) => AutomationRuleService(),
        ),

        // --- !!! PROVIDER ADICIONADO PARA PointOccurrenceService !!! ---
        ChangeNotifierProvider(
          create: (_) => PointOccurrenceService(),
        ),

        // Adicione mais providers globais aqui conforme necessário
      ],
      child: MaterialApp(
        title: 'Controle de Pontos', // Nome do seu aplicativo
        theme: ThemeData(
          // Define o tema do seu aplicativo
          colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.orange), // Exemplo usando orange
          useMaterial3: true, // Recomendado para temas mais modernos
          // Você pode personalizar mais o tema aqui (fontes, cores de botões, etc.)
          appBarTheme: AppBarTheme(
            backgroundColor: Colors.orange[700], // Cor padrão para AppBars
            foregroundColor: Colors.white, // Cor do texto/ícones na AppBar
          ),
          floatingActionButtonTheme: FloatingActionButtonThemeData(
            backgroundColor: Colors.orange[700], // Cor padrão para FABs
            foregroundColor: Colors.white,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange[700],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          )),
        ),
        debugShowCheckedModeBanner: false, // Remove a faixa de debug
        // Configuração para localização (suporte a Português-BR)
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('en', ''), // Inglês (fallback)
          Locale('pt', 'BR'), // Português Brasil
        ],
        locale: const Locale('pt', 'BR'), // Define pt-BR como padrão
        // Define a tela inicial ou o wrapper que decide qual tela mostrar
        home: const AuthWrapper(),
      ),
    );
  }
}
