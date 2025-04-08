// lib/features/auth/widgets/auth_wrapper.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Importe as novas telas de dashboard
import 'package:controle_pontos_app/features/admin/screens/admin_dashboard_page.dart';
import 'package:controle_pontos_app/features/employee/screens/employee_dashboard_page.dart';
import 'package:controle_pontos_app/features/auth/screens/login_page.dart';
// Remova ou comente o import da HomePage se não for mais usada diretamente aqui
// import 'package:controle_pontos_app/features/home/screens/home_page.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  // Constantes para os papéis de usuário
  static const String _roleAdmin = 'Admin';
  static const String _roleEmployee = 'Funcionário';
  static const String _usersCollection = 'users';
  static const String _roleField = 'role';

  // Widget de carregamento reutilizável
  // MODIFICAÇÃO: Adicionada mensagem informativa durante carregamento
  Widget _buildLoadingScreen() {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Carregando...'),
          ],
        ),
      ),
    );
  }

  // Widget de erro reutilizável
  // MODIFICAÇÃO: Melhorada a apresentação visual do erro
  Widget _buildErrorScreen(String message, String? subMessage) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // MODIFICAÇÃO: Adicionado ícone de erro para melhor feedback visual
              const Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              if (subMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  subMessage,
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                },
                child: const Text('Sair'),
              )
            ],
          ),
        ),
      ),
    );
  }

  // MODIFICAÇÃO: Adicionada função para log padronizado de erros
  void _logError(String message, [Object? error]) {
    debugPrint('🔴 Error: $message');
    if (error != null) {
      debugPrint('  Details: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        // 1. Verificando o estado da conexão do Stream de Autenticação
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          // Mostra um loading enquanto verifica o status de autenticação
          return _buildLoadingScreen();
        }

        // 2. Se o usuário ESTÁ logado (snapshot tem dados)
        if (authSnapshot.hasData) {
          final user = authSnapshot.data!; // Temos o usuário autenticado
          // Agora, precisamos buscar o 'role' dele no Firestore
          return FutureBuilder<DocumentSnapshot>(
            // Future que busca o documento do usuário no Firestore
            future: FirebaseFirestore.instance
                .collection(_usersCollection)
                .doc(user.uid) // Usa o UID do usuário logado
                .get(),
            builder: (context, userDocSnapshot) {
              // 2.1 Verificando o estado da conexão da busca no Firestore
              if (userDocSnapshot.connectionState == ConnectionState.waiting) {
                // Mostra loading enquanto busca dados do Firestore
                return _buildLoadingScreen();
              }

              // 2.2 Tratando erro na busca do Firestore
              if (userDocSnapshot.hasError) {
                // MODIFICAÇÃO: Usando a função de log padronizada
                _logError(
                    "Erro ao buscar dados do usuário", userDocSnapshot.error);
                return _buildErrorScreen(
                  'Erro ao carregar dados do usuário.',
                  'Tente novamente mais tarde.',
                );
              }

              // 2.3 Verificando se o documento do usuário existe no Firestore
              if (!userDocSnapshot.hasData || !userDocSnapshot.data!.exists) {
                // Usuário autenticado, mas sem dados correspondentes no Firestore
                // Isso pode acontecer se o registro no Firestore falhar ou for excluído.
                // O que fazer aqui?
                // Opção 1: Mostrar uma tela de erro/configuração pendente.
                // Opção 2: Deslogar o usuário. (Implementado abaixo)

                // MODIFICAÇÃO: Usando a função de log padronizada
                _logError(
                    "Documento do usuário ${user.uid} não encontrado no Firestore");
                return _buildErrorScreen(
                    'Erro: Dados do usuário não encontrados.',
                    'Contate o administrador.');
                // Poderia também redirecionar para uma página de "Complete seu perfil" se aplicável.
              }

              // 2.4 Se temos os dados do usuário do Firestore
              final userData =
                  userDocSnapshot.data!.data() as Map<String, dynamic>;

              // MODIFICAÇÃO: Verificação mais segura do campo role
              final String? role = userData.containsKey(_roleField)
                  ? userData[_roleField] as String?
                  : null;

              // 2.5 Redireciona com base no 'role'
              if (role == _roleAdmin) {
                return const AdminDashboardPage(); // Vai para o Dashboard Admin
              } else if (role == _roleEmployee) {
                // MODIFICAÇÃO: Mantido o nome original da classe para evitar erros
                return const EmployeeDashboardPage(); // Vai para o Dashboard Funcionário
              } else {
                // Role inválido ou não definido no documento
                _logError("Role inválido ('$role') para usuário ${user.uid}");
                return _buildErrorScreen(
                    'Erro: Função de usuário desconhecida.',
                    'Contate o administrador.');
              }
            },
          );
        }
        // 3. Se o usuário NÃO está logado (snapshot não tem dados)
        else {
          return const LoginPage(); // Mostra a tela de Login
        }
      },
    );
  }
}
