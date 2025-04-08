// lib/core/constants/app_colors.dart

import 'package:flutter/material.dart';

/// Constantes de cores utilizadas em todo o aplicativo
///
/// Centraliza todas as cores para manter consistência visual
/// e facilitar alterações futuras no tema do aplicativo.
class AppColors {
  // Cores primárias da UI
  static const primaryColor = Colors.blue;
  static const secondaryColor = Colors.blueAccent;

  // Cores de feedback
  static const successColor = Colors.green;
  static const errorColor = Colors.red;
  static const warningColor = Colors.orange;

  // Cores específicas de funcionalidades
  static const resetPasswordButtonColor = Colors.orangeAccent;
  static const activeUserColor = Colors.green;
  static const inactiveUserColor = Colors.grey;

  // Cores neutras
  static const white = Colors.white;
  static const black = Colors.black;
  static const background = Color(0xFFF5F5F5);

  // Cores específicas de status de ocorrências
  static const pendingStatusColor = Colors.amber;
  static const approvedStatusColor = Colors.green;
  static const rejectedStatusColor = Colors.red;

  // Cores de departamentos
  static const kitchenDepartmentColor = Colors.orange;
  static const diningRoomDepartmentColor = Colors.purple;
}
