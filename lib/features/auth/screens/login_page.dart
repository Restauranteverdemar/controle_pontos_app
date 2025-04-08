import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // Controllers
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // State variables
  bool _isPasswordVisible = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Função de login
  Future<void> _login() async {
    if (!mounted) return;

    final String email = _emailController.text.trim();
    final String password = _passwordController.text.trim();

    // Validação básica
    if (email.isEmpty || password.isEmpty) {
      showMessage('Por favor, preencha o email e a senha.', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Autenticação com Firebase
      final UserCredential userCredential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (!mounted) return;

      // TODO: Navegar para a próxima tela (Dashboard) após o login
      // Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => HomePage()));
    } on FirebaseAuthException catch (e) {
      debugPrint('Erro de login: ${e.code}');
      final String errorMessage = _getAuthErrorMessage(e.code);
      showMessage(errorMessage, isError: true);
    } catch (e) {
      debugPrint('Erro inesperado: $e');
      showMessage('Ocorreu um erro inesperado: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Mostrar mensagem para o usuário
  void showMessage(String message, {required bool isError}) {
    if (!mounted) return;

    final Color color = isError ? Colors.red : Colors.green;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
      ),
    );
  }

  // Mapear erros do Firebase para mensagens amigáveis
  String _getAuthErrorMessage(String errorCode) {
    switch (errorCode) {
      case 'user-not-found':
      case 'invalid-credential':
      case 'wrong-password':
      case 'invalid-email':
        return 'Email ou senha inválidos.';
      default:
        return 'Ocorreu um erro ao fazer login.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login - Controle de Pontos'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildEmailField(),
                const SizedBox(height: 16.0),
                _buildPasswordField(),
                const SizedBox(height: 24.0),
                _buildLoginButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Campos de entrada
  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      decoration: const InputDecoration(
        labelText: 'Email',
        hintText: 'Digite seu email',
        prefixIcon: Icon(Icons.email),
        border: OutlineInputBorder(),
      ),
      enabled: !_isLoading,
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: !_isPasswordVisible,
      decoration: InputDecoration(
        labelText: 'Senha',
        hintText: 'Digite sua senha',
        prefixIcon: const Icon(Icons.lock),
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(
            _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
          ),
          onPressed: () =>
              setState(() => _isPasswordVisible = !_isPasswordVisible),
        ),
      ),
      enabled: !_isLoading,
    );
  }

  // Botão de login
  Widget _buildLoginButton() {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : ElevatedButton.icon(
            icon: const Icon(Icons.login),
            label: const Text('Entrar'),
            onPressed: _login,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 15.0),
              textStyle: const TextStyle(fontSize: 16),
            ),
          );
  }
}
