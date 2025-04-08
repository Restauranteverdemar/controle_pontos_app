// Enum para representar os possíveis status de uma ocorrência
enum OccurrenceStatus {
  pendente,
  aprovada,
  reprovada;

  // Método para converter o enum para string usada no Firestore
  String toJsonString() {
    switch (this) {
      case OccurrenceStatus.pendente:
        return 'Pendente';
      case OccurrenceStatus.aprovada:
        return 'Aprovada';
      case OccurrenceStatus.reprovada:
        return 'Reprovada';
    }
  }

  // Método para converter string do Firestore para enum
  static OccurrenceStatus fromString(String status) {
    switch (status) {
      case 'Pendente':
        return OccurrenceStatus.pendente;
      case 'Aprovada':
        return OccurrenceStatus.aprovada;
      case 'Reprovada':
        return OccurrenceStatus.reprovada;
      default:
        return OccurrenceStatus.pendente;
    }
  }
}
