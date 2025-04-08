// lib/features/admin/widgets/reset_monthly_balance_button.dart
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:async'; // Para o TimeoutException

/// Widget de botão para executar reset mensal manualmente
class ResetMonthlyBalanceButton extends StatelessWidget {
  final bool smallSize;

  // Defina a região da sua função Cloud AQUI!
  // Ex: 'southamerica-east1', 'us-central1', etc.
  final String cloudFunctionRegion = 'southamerica-east1'; // <-- AJUSTE AQUI

  const ResetMonthlyBalanceButton({
    Key? key,
    this.smallSize = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return smallSize
        ? _buildSmallButton(context)
        : _buildRegularButton(context);
  }

  Widget _buildSmallButton(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.restart_alt),
      tooltip: 'Reset Manual de Saldo Mensal',
      color: Colors.amber.shade700,
      onPressed: () => _showConfirmationDialog(context),
    );
  }

  Widget _buildRegularButton(BuildContext context) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.restart_alt),
      label: const Text('Executar Reset Mensal Manual'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.amber.shade600,
        foregroundColor: Colors.black,
        elevation: 3,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      onPressed: () => _showConfirmationDialog(context),
    );
  }

  // Mostra diálogo de confirmação
  void _showConfirmationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        // Usar dialogContext aqui
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.amber.shade700),
            const SizedBox(width: 8),
            const Text('Atenção!'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Você está prestes a executar o reset mensal manualmente.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text(
              'Esta ação irá:\n'
              '• Salvar o saldo atual de todos os usuários em userBalanceSnapshots\n'
              '• Zerar o saldo (saldoPontosAprovados) de todos os usuários\n\n'
              'Deseja continuar?',
            ),
          ],
        ),
        actions: [
          TextButton(
            // Usar dialogContext para fechar o diálogo de confirmação
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () {
              // Fecha o diálogo de confirmação ANTES de chamar o reset
              Navigator.of(dialogContext).pop();
              // Chama a função de execução passando o context ORIGINAL do botão
              _executeManualResetSimplified(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade600,
              foregroundColor: Colors.black,
            ),
            child: const Text('CONFIRMAR'),
          ),
        ],
      ),
    );
  }

  // VERSÃO CORRIGIDA E UNIFICADA da execução
  Future<void> _executeManualResetSimplified(BuildContext context) async {
    // ***** NOVO: Capturar Navigator e ScaffoldMessenger ANTES *****
    // Usamos o context original aqui para obter o Navigator
    final navigator = Navigator.of(context, rootNavigator: true);
    // final scaffoldMessenger = ScaffoldMessenger.of(context); // Se precisar de SnackBars

    // 1. Mostrar um ÚNICO diálogo de loading
    // Usamos o 'context' original para mostrar o diálogo inicial
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return const Dialog(
          key: ValueKey('loadingDialog'),
          child: Padding(
            padding: EdgeInsets.all(20.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text("Executando reset..."),
              ],
            ),
          ),
        );
      },
    );

    HttpsCallableResult? result;
    dynamic errorData;

    try {
      print('--- Iniciando chamada para resetMonthlyBalanceManual ---');
      final functions =
          FirebaseFunctions.instanceFor(region: cloudFunctionRegion);
      final callable = functions.httpsCallable(
        'resetMonthlyBalanceManual',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 45)),
      );

      print('Chamando a função...');
      result = await callable.call<Map<String, dynamic>>({});
      print('--- Chamada concluída com sucesso ---');
      print('Resultado recebido: ${result.data}');
    } catch (e) {
      print('--- Erro durante a chamada da função ---');
      print('Erro: ${e.runtimeType}');
      print(e);
      errorData = e;
      if (e is FirebaseFunctionsException) {
        print('Código do erro Firebase: ${e.code}');
        print('Mensagem do erro Firebase: ${e.message}');
        print('Detalhes do erro Firebase: ${e.details}');
      }
    } finally {
      // 5. FECHAR o diálogo de loading usando o Navigator capturado ANTES
      if (navigator.canPop()) {
        navigator.pop();
        print('Diálogo de loading fechado via Navigator capturado.');
      } else {
        print(
            'Navigator capturado não pôde fechar o diálogo (talvez já fechado?).');
      }

      // Pequeno delay para garantir transição suave
      await Future.delayed(const Duration(milliseconds: 100));

      // 6. Mostrar o diálogo de resultado
      // ***** IMPORTANTE: Usar o 'navigator.context' para mostrar o próximo diálogo *****
      // E verificar se o widget original ainda está montado antes de tentar mostrar
      if (context.mounted) {
        print('Contexto original ainda montado. Tentando mostrar resultado...');
        if (errorData != null) {
          // Passa o navigator.context para a função que mostra o diálogo
          _showErrorDialog(navigator.context, errorData);
        } else if (result != null) {
          // Passa o navigator.context para a função que mostra o diálogo
          _showSuccessDialog(navigator.context, result.data);
        } else {
          _showErrorDialog(
              navigator.context, 'Resultado inesperado da operação.');
        }
      } else {
        print(
            'Contexto original não montado, diálogo de resultado não será mostrado.');
      }
    }
  }

  // Mostra diálogo de sucesso (MODIFICADO para aceitar context)
  void _showSuccessDialog(BuildContext context, dynamic data) {
    // <-- Aceita context
    final responseData = data as Map<dynamic, dynamic>? ?? {};
    final message =
        responseData['message'] as String? ?? 'Operação concluída com sucesso.';
    final details = responseData['details'] as Map<dynamic, dynamic>? ?? {};
    final processedUsers = details['processedUsers'] ?? 'N/A';
    final yearMonth = details['yearMonth'] ?? 'N/A';

    showDialog(
      context: context, // Usa o context recebido
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Sucesso!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 16),
            Text('Usuários Processados: $processedUsers'),
            Text('Mês Referência Salvo: $yearMonth'),
            // Text('Resposta Completa: $data'), // Opcional para debug
          ],
        ),
        actions: [
          ElevatedButton(
            // Usa dialogContext para fechar o diálogo de sucesso
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // Mostra diálogo de erro (MODIFICADO para aceitar context)
  void _showErrorDialog(BuildContext context, dynamic error) {
    // <-- Aceita context
    String errorTitle = 'Erro Desconhecido';
    String errorMessage = error.toString();
    String errorDetails = '';

    if (error is FirebaseFunctionsException) {
      errorTitle = 'Erro na Função Cloud (${error.code})';
      errorMessage =
          error.message ?? 'Ocorreu um erro ao executar a função no servidor.';
      errorDetails = 'Detalhes: ${error.details ?? 'N/A'}';
    } else if (error is TimeoutException) {
      errorTitle = 'Tempo Esgotado (Timeout)';
      errorMessage =
          'A operação demorou muito para responder. Verifique sua conexão ou tente novamente mais tarde.';
    } else {
      errorMessage = 'Ocorreu um erro inesperado: ${error.toString()}';
    }

    showDialog(
      context: context, // Usa o context recebido
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error, color: Colors.red),
            const SizedBox(width: 8),
            Text(errorTitle),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(errorMessage),
            if (errorDetails.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(errorDetails),
            ]
          ],
        ),
        actions: [
          ElevatedButton(
            // Usa dialogContext para fechar o diálogo de erro
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
