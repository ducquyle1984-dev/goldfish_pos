import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:goldfish_pos/screens/home_screen.dart';
import 'package:goldfish_pos/screens/kiosk_check_in_screen.dart';

/// Shown on web after login so the user can choose whether to open the
/// full POS or the customer self-check-in kiosk.
class DeviceRoleScreen extends StatelessWidget {
  const DeviceRoleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  const Icon(
                    Icons.storefront_rounded,
                    color: Colors.tealAccent,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Goldfish POS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (user?.email != null)
                    Text(
                      user!.email!,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    icon: const Icon(
                      Icons.logout,
                      color: Colors.white38,
                      size: 18,
                    ),
                    label: const Text(
                      'Sign out',
                      style: TextStyle(color: Colors.white38),
                    ),
                    onPressed: () => FirebaseAuth.instance.signOut(),
                  ),
                ],
              ),
            ),

            // ── Main content ──────────────────────────────────────────────
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'How would you like to use this device?',
                          style: TextStyle(color: Colors.white70, fontSize: 18),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 40),
                        // ── Role cards ────────────────────────────────────
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final wide = constraints.maxWidth > 500;
                            final cards = [
                              _RoleCard(
                                icon: Icons.point_of_sale_rounded,
                                title: 'POS Terminal',
                                subtitle:
                                    'Manage transactions, items,\nand staff operations.',
                                color: Colors.deepPurpleAccent,
                                onTap: () => _go(context, const HomeScreen()),
                              ),
                              _RoleCard(
                                icon: Icons.how_to_reg_rounded,
                                title: 'Customer Check-In',
                                subtitle:
                                    'Customers enter their phone\nnumber to check in.',
                                color: Colors.tealAccent,
                                onTap: () =>
                                    _go(context, const KioskCheckInScreen()),
                              ),
                            ];
                            return wide
                                ? Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(child: cards[0]),
                                      const SizedBox(width: 20),
                                      Expanded(child: cards[1]),
                                    ],
                                  )
                                : Column(
                                    children: [
                                      cards[0],
                                      const SizedBox(height: 20),
                                      cards[1],
                                    ],
                                  );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _go(BuildContext context, Widget screen) {
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => screen));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Role card widget
// ─────────────────────────────────────────────────────────────────────────────
class _RoleCard extends StatefulWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: _hovered
              ? Colors.white.withAlpha(25)
              : Colors.white.withAlpha(13),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _hovered
                ? widget.color.withAlpha(200)
                : Colors.white.withAlpha(30),
            width: 2,
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: widget.color.withAlpha(60),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ]
              : [],
        ),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withAlpha(30),
                    border: Border.all(
                      color: widget.color.withAlpha(150),
                      width: 2,
                    ),
                  ),
                  child: Icon(widget.icon, color: widget.color, size: 40),
                ),
                const SizedBox(height: 24),
                Text(
                  widget.title,
                  style: TextStyle(
                    color: widget.color,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.subtitle,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 14,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
