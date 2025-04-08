// lib/features/admin/screens/lista_funcionarios_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// --- Imports Corrigidos ---
import 'package:controle_pontos_app/core/constants/app_colors.dart'; // Importa cores globais
import 'package:controle_pontos_app/core/constants/app_strings.dart'; // Importa strings globais
import 'package:controle_pontos_app/features/shared/models/employee.dart'; // Importa o modelo compartilhado
import 'package:controle_pontos_app/features/admin/screens/criar_funcionario_page.dart'; // Tela de criação
import 'package:controle_pontos_app/features/admin/screens/employee_detail_modal.dart'; // NOVO Modal
// Importação do modal de histórico
import 'package:controle_pontos_app/features/shared/widgets/balance_history_modal.dart'; // Modal do histórico de saldo

class ListaFuncionariosPage extends StatelessWidget {
  const ListaFuncionariosPage({Key? key}) : super(key: key);

  // Método para navegar para a tela de criação
  void _navegarParaCriarFuncionario(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CriarFuncionarioPage()),
    );
  }

  // Função para mostrar o Modal de Detalhes/Edição
  void _showEmployeeDetailsModal(BuildContext context, String userId) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return EmployeeDetailModal(userId: userId);
      },
    ).then((result) {
      if (result == true) {
        debugPrint("Modal fechado com sucesso (possivelmente salvo).");
      }
    });
  }

  // ADICIONADO: Função para mostrar o modal de histórico de saldo
  void _showBalanceHistoryModal(
      BuildContext context, String userId, String employeeName) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return BalanceHistoryModal(userId: userId, userName: employeeName);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Usando um título literal adequado para a página
        title: const Text('Gerenciar Funcionários'),
      ),
      body: _buildEmployeesList(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navegarParaCriarFuncionario(context),
        // Usando um tooltip literal adequado
        tooltip: 'Adicionar Novo Funcionário',
        child: const Icon(Icons.add),
      ),
    );
  }

  // Constrói a lista de funcionários
  Widget _buildEmployeesList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          // Ordenar por status ativo primeiro, depois por nome
          .orderBy('isActive', descending: true)
          .orderBy('displayName', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint("Erro ao buscar funcionários: ${snapshot.error}");
          // Usando uma string literal adequada
          return const Center(child: Text('Erro ao carregar funcionários.'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.data == null || snapshot.data!.docs.isEmpty) {
          // Usando uma string literal adequada
          return const Center(child: Text('Nenhum funcionário cadastrado.'));
        }

        // Usa o modelo Employee importado
        final List<Employee> employees = snapshot.data!.docs
            .map((doc) {
              try {
                return Employee.fromFirestore(
                    doc.id, doc.data() as Map<String, dynamic>);
              } catch (e) {
                debugPrint("Erro ao converter funcionário ${doc.id}: $e");
                // Retorna um objeto inválido ou nulo para indicar o erro,
                // poderia ser tratado no itemBuilder se necessário.
                // Aqui vamos apenas logar e pular.
                return null;
              }
            })
            .whereType<Employee>() // Filtra os nulos resultantes de erro
            .toList();

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 80), // Espaço para o FAB
          itemCount: employees.length,
          itemBuilder: (context, index) =>
              _buildEmployeeListItem(context, employees[index]),
        );
      },
    );
  }

  // Constrói cada item da lista
  Widget _buildEmployeeListItem(BuildContext context, Employee employee) {
    // Define a cor do avatar baseada no papel (role)
    // --- CORREÇÃO NULL SAFETY e USO DE ALTERNATIVAS ---
    // Usa cinza como padrão se o papel for nulo ou desconhecido
    final Color avatarBaseColor = (employee.role?.toLowerCase() ?? '') ==
            AppStrings.adminRole.toLowerCase()
        ? Colors.blueGrey // Alternativa para adminColor
        : (employee.role?.toLowerCase() ?? '') ==
                AppStrings.employeeRole.toLowerCase()
            ? Colors.teal // Alternativa para funcionarioColor
            : Colors.grey; // Cor padrão

    final Color avatarColor =
        employee.isActive ? avatarBaseColor : avatarBaseColor.withOpacity(0.5);
    final Color textColor = employee.isActive ? Colors.black87 : Colors.grey;
    final Color subtitleColor =
        employee.isActive ? Colors.grey.shade600 : Colors.grey.shade500;
    final TextDecoration textDecoration =
        employee.isActive ? TextDecoration.none : TextDecoration.lineThrough;

    // Constrói o texto do subtítulo
    // --- CORREÇÃO NULL SAFETY e LÓGICA ---
    List<String> subtitleParts = [];
    subtitleParts.add(employee.email); // Email sempre presente
    if (employee.role != null && employee.role!.isNotEmpty) {
      subtitleParts.add(employee.role!); // Adiciona role se existir
    } else {
      subtitleParts.add("Papel não definido");
    }
    if (employee.department != null &&
        employee.department!.isNotEmpty &&
        (employee.role?.toLowerCase() ?? '') ==
            AppStrings.employeeRole.toLowerCase()) {
      subtitleParts.add(
          '(${employee.department})'); // Adiciona departamento para funcionários
    }
    if (!employee.isActive) {
      subtitleParts.add('- Inativo'); // Adiciona status inativo
    }
    final String subtitleText = subtitleParts.join(' ');

    // ADICIONADO: Determina a cor do saldo com base no valor
    final int saldoPontos = employee.saldoPontosAprovados ?? 0;
    final Color saldoColor = saldoPontos > 0
        ? Colors.green.shade700
        : saldoPontos < 0
            ? Colors.red.shade700
            : Colors.grey.shade600;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 2,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundColor: avatarColor,
              foregroundColor:
                  AppColors.white.withOpacity(employee.isActive ? 1.0 : 0.7),
              // Garante que a inicial seja pega corretamente mesmo com nome vazio
              child: Text(employee.displayName.isNotEmpty
                  ? employee.displayName[0].toUpperCase()
                  : '?'),
            ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                employee.displayName,
                style: TextStyle(
                  color: textColor,
                  decoration: textDecoration,
                ),
              ),
            ),

            // ADICIONADO: Widget para exibir o saldo de pontos
            if ((employee.role?.toLowerCase() ?? '') ==
                AppStrings.employeeRole.toLowerCase())
              GestureDetector(
                onTap: () => _showBalanceHistoryModal(
                    context, employee.id, employee.displayName),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: saldoColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: saldoColor.withOpacity(0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        saldoPontos > 0
                            ? Icons.trending_up
                            : saldoPontos < 0
                                ? Icons.trending_down
                                : Icons.horizontal_rule,
                        color: saldoColor,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${saldoPontos > 0 ? '+' : ''}$saldoPontos pts',
                        style: TextStyle(
                          color: saldoColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              subtitleText,
              style: TextStyle(
                color: subtitleColor,
                decoration: textDecoration,
              ),
            ),
          ],
        ),
        trailing: IconButton(
          // --- CORREÇÃO DE CONSTANTE ---
          icon: Icon(Icons.edit_note,
              color:
                  Theme.of(context).primaryColor), // Usa cor primária do tema
          // --- CORREÇÃO DE CONSTANTE ---
          tooltip: 'Detalhes / Editar Funcionário', // Tooltip literal
          onPressed: () => _showEmployeeDetailsModal(context, employee.id),
        ),
        onTap: () => _showEmployeeDetailsModal(
            context, employee.id), // Clicar no item todo
      ),
    );
  }
}
