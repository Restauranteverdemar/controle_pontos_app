// lib/features/admin/screens/admin_dashboard_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

// Importe as páginas e o controller
import 'lista_funcionarios_page.dart';
import 'registro_ocorrencia_page.dart';
import 'gerenciar_tipos_ocorrencia_page.dart';
import 'aprovacao_pendentes_page.dart';
import 'ocorrencias_submenu_page.dart'; // Novo import para o submenu
import 'controllers/registro_ocorrencia_controller.dart';
import 'automation_rules_page.dart'; // Nova importação para regras automáticas
import '../widgets/reset_monthly_balance_button.dart'; // Import do botão de reset

/// Tela de dashboard principal para usuários administradores
/// Apresenta botões para acessar as diferentes funcionalidades do sistema
class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key});

  // Constantes para padronização de espaçamento e tamanhos de componentes
  static const double _espacamentoVertical = 20.0;
  static const double _espacamentoVerticalPequeno = 10.0;
  static const double _espacamentoPadding = 16.0;
  static const double _espacamentoTitulo = 30.0;
  static const double _paddingBotaoVertical = 16.0;
  static const double _tamanhoBordaArredondada = 8.0;
  static const double _tamanhoIconeTitulo = 60.0;
  static const double _elevacaoBotao = 3.0;
  static const Size _tamanhoMinimoBotao = Size(250, 50);

  /// Método para realizar logout do usuário atual com tratamento de erros
  Future<void> _realizarLogout(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
            content: Text('Saindo...'), duration: Duration(milliseconds: 1500)),
      );
      await FirebaseAuth.instance.signOut();
      // A navegação será tratada pelo AuthWrapper
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Erro ao fazer logout: ${e.toString()}'),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }

  /// Método para criar botões de navegação com aparência consistente
  Widget _criarBotaoNavegacao({
    required BuildContext context,
    required IconData icone,
    required String texto,
    required VoidCallback aoClicar,
    Color? corFundo,
    bool isNew = false, // Novo parâmetro para destacar recursos novos
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Stack(
      children: [
        ElevatedButton.icon(
          icon: Icon(icone),
          label: Text(
            texto,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            minimumSize: _tamanhoMinimoBotao,
            backgroundColor: corFundo ?? colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_tamanhoBordaArredondada),
            ),
            elevation: _elevacaoBotao,
            padding:
                const EdgeInsets.symmetric(vertical: _paddingBotaoVertical),
          ),
          onPressed: aoClicar,
        ),
        if (isNew) // Mostrar badge "NOVO" se for um recurso novo
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'NOVO',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final textTheme = Theme.of(context).textTheme;
    final corPrincipalAppBar = Colors.blueGrey;

    final appBar = AppBar(
      title: const Text('Painel do Administrador'),
      backgroundColor: corPrincipalAppBar,
      foregroundColor: Colors.white,
      elevation: 4,
      actions: [
        // Botão de reset mensal adicionado de forma discreta
        const ResetMonthlyBalanceButton(smallSize: true),
        // Botão de logout
        IconButton(
          icon: const Icon(Icons.logout),
          tooltip: 'Sair',
          onPressed: () => _realizarLogout(context),
        ),
      ],
    );

    final cabecalho = Column(
      children: [
        Icon(
          Icons.admin_panel_settings,
          size: _tamanhoIconeTitulo,
          color: Theme.of(context).colorScheme.secondary,
        ),
        const SizedBox(height: _espacamentoVerticalPequeno),
        Text(
          'Bem-vindo(a), Administrador(a)!',
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        if (user?.email != null)
          Padding(
            padding: const EdgeInsets.only(
              top: 4.0,
              bottom: _espacamentoTitulo,
            ),
            child: Text(
              'Logado como: ${user!.email}',
              style: textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
            ),
          ),
        if (user?.email == null) const SizedBox(height: _espacamentoTitulo),
      ],
    );

    return Scaffold(
      appBar: appBar,
      body: Padding(
        padding: const EdgeInsets.all(_espacamentoPadding),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(vertical: _espacamentoVertical),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  cabecalho,

                  // Botão Gerenciar Funcionários
                  _criarBotaoNavegacao(
                    context: context,
                    icone: Icons.people_alt_outlined,
                    texto: 'Gerenciar Funcionários',
                    corFundo: Colors.blueGrey[700],
                    aoClicar: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ListaFuncionariosPage(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: _espacamentoVertical),

                  // Botão para Gerenciar Ocorrências (Submenu)
                  _criarBotaoNavegacao(
                    context: context,
                    icone: Icons.settings,
                    texto: 'Gerenciar Ocorrências',
                    corFundo: Colors.deepPurple,
                    aoClicar: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const OcorrenciasSubmenuPage(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: _espacamentoVertical),

                  // Botão Registrar Ocorrência (Mantido para acesso rápido)
                  _criarBotaoNavegacao(
                    context: context,
                    icone: Icons.note_add_outlined,
                    texto: 'Registrar Ocorrência',
                    corFundo: Colors.teal,
                    aoClicar: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChangeNotifierProvider(
                            create: (_) => RegistroOcorrenciaController(),
                            child: const RegistroOcorrenciaPage(),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: _espacamentoVertical),

                  // Novo botão para Regras Automáticas
                  _criarBotaoNavegacao(
                    context: context,
                    icone: Icons.auto_awesome,
                    texto: 'Regras Automáticas',
                    corFundo: Colors.orange[700],
                    isNew: true, // Destacar como novo recurso
                    aoClicar: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AutomationRulesPage(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
