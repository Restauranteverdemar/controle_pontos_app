// lib/features/admin/screens/ocorrencias_submenu_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'gerenciar_tipos_ocorrencia_page.dart';
import 'aprovacao_pendentes_page.dart';
import 'controllers/registro_ocorrencia_controller.dart';
import 'registro_ocorrencia_page.dart';
import '../../shared/screens/historico_ocorrencias_page.dart';

/// Tela de submenu para gerenciamento de Ocorrências
/// Centraliza todas as funcionalidades relacionadas a ocorrências
class OcorrenciasSubmenuPage extends StatelessWidget {
  const OcorrenciasSubmenuPage({Key? key}) : super(key: key);

  // Constantes para padronização de espaçamento e tamanhos de componentes
  static const double _espacamentoVertical = 20.0;
  static const double _espacamentoVerticalPequeno = 10.0;
  static const double _espacamentoPadding = 16.0;
  static const double _tamanhoIconeTitulo = 60.0;
  static const double _paddingBotaoVertical = 16.0;
  static const double _tamanhoBordaArredondada = 8.0;
  static const double _elevacaoBotao = 3.0;
  static const Size _tamanhoMinimoBotao = Size(250, 50);

  /// Método para criar botões de navegação com aparência consistente
  Widget _criarBotaoNavegacao({
    required BuildContext context,
    required IconData icone,
    required String texto,
    required VoidCallback aoClicar,
    Color? corFundo,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ElevatedButton.icon(
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
        padding: const EdgeInsets.symmetric(vertical: _paddingBotaoVertical),
      ),
      onPressed: aoClicar,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerenciamento de Ocorrências'),
        backgroundColor: Colors.blueGrey,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
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
                  Icon(
                    Icons.assignment,
                    size: _tamanhoIconeTitulo,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  const SizedBox(height: _espacamentoVerticalPequeno),
                  Text(
                    'Central de Ocorrências',
                    style: textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 30.0),

                  // Botão Gerenciar Tipos de Ocorrência
                  _criarBotaoNavegacao(
                    context: context,
                    icone: Icons.category_outlined,
                    texto: 'Tipos de Ocorrência',
                    corFundo: Colors.amber[700],
                    aoClicar: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const GerenciarTiposOcorrenciaPage(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: _espacamentoVertical),

                  // Botão Registrar Ocorrência
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

                  // Botão Aprovar Ocorrências Pendentes
                  _criarBotaoNavegacao(
                    context: context,
                    icone: Icons.pending_actions_outlined,
                    texto: 'Aprovar Ocorrências',
                    corFundo: Colors.green[700],
                    aoClicar: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AprovacaoPendentesPage(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: _espacamentoVertical),

                  // Botão Histórico de Ocorrências
                  _criarBotaoNavegacao(
                    context: context,
                    icone: Icons.history,
                    texto: 'Histórico de Ocorrências',
                    corFundo: Colors.purple[700],
                    aoClicar: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const HistoricoOcorrenciasPage(),
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
