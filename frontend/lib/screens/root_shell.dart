import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import 'home_screen.dart';
import 'inventario_home_screen.dart';

/// Punto de entrada de la app: dos secciones -"Buscar" (el catálogo en
/// vivo de Farmatodo, como siempre) e "Inventario" (vencimientos,
/// depósito y conteo, propios de la tienda)-. `IndexedStack` mantiene
/// ambas construidas (no se pierde el estado del buscador al cambiar
/// de pestaña), solo cambia cuál se muestra.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _pestana = 0;

  @override
  void initState() {
    super.initState();
    // No bloquea el arranque de la UI: se pide el permiso de
    // notificaciones en segundo plano apenas abre la app.
    NotificationService.instancia.inicializar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _pestana,
        children: const [
          HomeScreen(),
          InventarioHomeScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _pestana,
        onDestinationSelected: (indice) => setState(() => _pestana = indice),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.search_rounded), label: 'Buscar'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Inventario'),
        ],
      ),
    );
  }
}
