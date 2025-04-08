// lib/features/admin/screens/criar_funcionario_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart'; // Nova importação para Cloud Functions
import 'dart:developer'; // Para logs internos

class CriarFuncionarioPage extends StatefulWidget {
  const CriarFuncionarioPage({Key? key}) : super(key: key);

  @override
  State<CriarFuncionarioPage> createState() => _CriarFuncionarioPageState();
}

class _CriarFuncionarioPageState extends State<CriarFuncionarioPage> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();

  String? _selectedRole;
  final List<String> _roles = ['Funcionário', 'Admin'];

  String? _selectedDepartment;
  final List<String> _departments = ['Cozinha', 'Salão'];

  bool _obscurePassword = true;
  bool _isLoading = false;

  // ----- MODIFICAÇÃO NECESSÁRIA -----
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
      region: 'southamerica-east1'); // Especifica a região correta

  static final RegExp _emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  @override
  void dispose() {
    _nomeController.dispose();
    _emailController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  void _mostrarMensagem(String mensagem, bool isError) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor:
            isError ? Theme.of(context).colorScheme.error : Colors.green,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Fechar',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  // FUNÇÃO MODIFICADA para usar Cloud Function
  Future<void> _criarFuncionario() async {
    if (_isLoading) return;

    bool isDepartmentValid = true;
    if (_selectedRole == 'Funcionário' && _selectedDepartment == null) {
      isDepartmentValid = false;
      _mostrarMensagem(
          'Por favor, selecione o departamento para o funcionário.', true);
    }

    if ((_formKey.currentState?.validate() ?? false) && isDepartmentValid) {
      if (!mounted) return;
      setState(() {
        _isLoading = true;
      });

      try {
        final email = _emailController.text.trim();
        final senha = _senhaController.text.trim();
        final nome = _nomeController.text.trim();

        if (email.isEmpty || senha.isEmpty) {
          throw Exception('Email e senha não podem estar vazios');
        }

        // Em vez de criar o usuário diretamente com createUserWithEmailAndPassword,
        // vamos chamar nossa Cloud Function personalizada
        final callable = _functions.httpsCallable('createUser');

        log('Chamando Cloud Function createUser...', name: 'CriarFuncionario');

        // Enviar dados para a Cloud Function
        final result = await callable.call({
          'email': email,
          'password': senha,
          'displayName': nome,
          'role': _selectedRole,
          'department': _selectedDepartment,
        });

        // Verificar o resultado da Cloud Function
        log('Resultado da função: ${result.data}', name: 'CriarFuncionario');

        if (result.data['success'] == true) {
          if (mounted) {
            _mostrarMensagem('Usuário criado com sucesso!', false);
            Navigator.pop(context); // Voltar para a tela anterior
          }
        } else {
          throw Exception('Falha ao criar usuário: resposta indefinida');
        }
      } on FirebaseFunctionsException catch (e) {
        // Tratamento de erros específicos da Cloud Function
        String errorMessage = 'Erro ao criar usuário.';
        log('Erro na Cloud Function: ${e.code} - ${e.message}',
            name: 'CriarFuncionario');

        switch (e.code) {
          case 'permission-denied':
            errorMessage =
                'Permissão negada. Apenas administradores podem criar usuários.';
            break;
          case 'invalid-argument':
            errorMessage =
                'Dados inválidos. Verifique os campos e tente novamente.';
            break;
          case 'already-exists':
            errorMessage = 'Este email já está em uso por outra conta.';
            break;
          case 'unauthenticated':
            errorMessage = 'Você precisa estar logado como administrador.';
            break;
          default:
            errorMessage = 'Erro ao criar usuário: ${e.message}';
        }
        _mostrarMensagem(errorMessage, true);
      } catch (e, s) {
        // Tratamento de erros genéricos
        log('Erro inesperado ao criar usuário: $e',
            stackTrace: s, name: 'CriarFuncionario');
        _mostrarMensagem('Ocorreu um erro inesperado. Tente novamente.', true);
      } finally {
        // Garantir que o loading seja desativado
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } else if (!isDepartmentValid) {
      // Mensagem de departamento já mostrada
    } else {
      _mostrarMensagem('Por favor, corrija os erros no formulário.', true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // O método build permanece exatamente o mesmo
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Criar Novo Usuário'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // --- Campo Nome ---
                  TextFormField(
                    controller: _nomeController,
                    decoration: const InputDecoration(
                      labelText: 'Nome Completo',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Por favor, insira o nome.';
                      }
                      if (value.trim().length < 3) {
                        return 'O nome deve ter pelo menos 3 caracteres.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // --- Campo Email ---
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Por favor, insira o email.';
                      }
                      if (!_emailRegex.hasMatch(value.trim())) {
                        return 'Por favor, insira um email válido.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // --- Campo Senha ---
                  TextFormField(
                    controller: _senhaController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Senha',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock),
                      helperText:
                          'Mínimo 6 caracteres. Recomendamos incluir letras maiúsculas, números e símbolos.',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                        tooltip: _obscurePassword
                            ? 'Mostrar senha'
                            : 'Ocultar senha',
                      ),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Por favor, insira a senha.';
                      }
                      if (value.length < 6) {
                        return 'A senha deve ter pelo menos 6 caracteres.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // --- Campo Papel (Role) - Dropdown ---
                  DropdownButtonFormField<String>(
                    value: _selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Papel (Role)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.badge),
                    ),
                    hint: const Text('Selecione o papel'),
                    items: _roles.map((String role) {
                      return DropdownMenuItem<String>(
                        value: role,
                        child: Text(role),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedRole = newValue;
                        if (_selectedRole != 'Funcionário') {
                          _selectedDepartment = null;
                        }
                      });
                    },
                    validator: (value) {
                      if (value == null) {
                        return 'Por favor, selecione um papel.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // --- Campo Departamento (Condicional) ---
                  if (_selectedRole == 'Funcionário')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: DropdownButtonFormField<String>(
                        value: _selectedDepartment,
                        decoration: const InputDecoration(
                          labelText: 'Departamento',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.work_outline),
                        ),
                        hint: const Text('Selecione o departamento'),
                        items: _departments.map((String department) {
                          return DropdownMenuItem<String>(
                            value: department,
                            child: Text(department),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          setState(() {
                            _selectedDepartment = newValue;
                          });
                        },
                      ),
                    ),

                  const SizedBox(height: 16),

                  // --- Botão Criar ---
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton(
                          onPressed: _criarFuncionario,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            textStyle: const TextStyle(fontSize: 16),
                          ),
                          child: const Text('Criar Usuário'),
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
