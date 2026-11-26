import 'package:flutter/material.dart';

/// Rodapé de autoria exibido no fim das telas principais.
class RodapeIG extends StatelessWidget {
  const RodapeIG({super.key});

  @override
  Widget build(BuildContext context) {
    final ano = DateTime.now().year;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
      child: Column(children: [
        const Divider(height: 1, color: Color(0x22000000)),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset('assets/marca/ig_logo.png', width: 36, height: 36),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('By IG Consultoria',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF262C38))),
              Text('© $ano • Todos os direitos reservados',
                  style: const TextStyle(fontSize: 11, color: Colors.black54)),
            ]),
          ),
        ]),
      ]),
    );
  }
}
