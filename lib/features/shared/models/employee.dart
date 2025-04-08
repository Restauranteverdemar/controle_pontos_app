// lib/features/shared/models/employee.dart

/// Modelo que representa os dados de um funcionário, com campos mutáveis para UI.
class Employee {
  final String id; // O ID geralmente não muda, então pode ser final

  // Campos mutáveis para edição na UI
  String displayName;
  String email;
  String? role;
  String? department;
  bool isActive;
  int saldoPontosAprovados; // Mudado para int e não nulo

  Employee({
    required this.id,
    required this.displayName,
    required this.email,
    this.role,
    this.department,
    this.isActive = true,
    this.saldoPontosAprovados = 0, // Valor padrão 0
  });

  /// Cria uma instância de Employee a partir de um Map (geralmente do Firestore).
  /// O [id] do documento deve ser passado separadamente.
  factory Employee.fromFirestore(String id, Map<String, dynamic> data) {
    return Employee(
      id: id,
      displayName:
          data['displayName'] as String? ?? '', // Garante que não seja nulo
      email: data['email'] as String? ?? '', // Garante que não seja nulo
      role: data['role'] as String?, // Pode ser nulo
      department: data['department'] as String?, // Pode ser nulo
      isActive:
          data['isActive'] as bool? ?? true, // Padrão true se ausente/nulo
      // Lê o saldo como número (int ou double) do Firestore e converte para int.
      // Usa 0 como padrão se o campo não existir ou for nulo no Firestore.
      saldoPontosAprovados:
          (data['saldoPontosAprovados'] as num?)?.toInt() ?? 0,
    );
  }

  /// Converte a instância de Employee em um Map para salvar no Firestore.
  Map<String, dynamic> toFirestore() {
    return {
      'displayName': displayName,
      'email': email,
      // Inclui os campos apenas se não forem nulos (melhor prática para Firestore)
      // Se forem nulos, não são enviados, economizando espaço e evitando sobrescrever
      // com null caso o Firestore tenha alguma regra específica.
      if (role != null) 'role': role,
      if (department != null) 'department': department,
      'isActive': isActive,
      'saldoPontosAprovados': saldoPontosAprovados, // Sempre terá um valor int
    };
  }

  // --- Métodos Opcionais para Debugging/Comparação (Ajustados para Classe Mutável) ---

  @override
  String toString() {
    // Retorna uma representação string útil para logs
    return 'Employee(id: $id, displayName: $displayName, email: $email, role: $role, department: $department, isActive: $isActive, saldoPontosAprovados: $saldoPontosAprovados)';
  }

  // Atenção: Com campos mutáveis, a comparação (==) e o hashCode podem ter
  // comportamento inesperado se os objetos forem modificados após serem
  // colocados em coleções que dependem de hash (Set, Map keys).
  // Use com cuidado se precisar comparar instâncias modificadas.

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Employee &&
        other.id == id &&
        other.displayName == displayName &&
        other.email == email &&
        other.role == role &&
        other.department == department &&
        other.isActive == isActive &&
        other.saldoPontosAprovados == saldoPontosAprovados;
  }

  @override
  int get hashCode {
    // Recalcula o hash baseado nos valores atuais dos campos
    return id.hashCode ^
        displayName.hashCode ^
        email.hashCode ^
        role.hashCode ^
        department.hashCode ^
        isActive.hashCode ^
        saldoPontosAprovados.hashCode;
  }
}
