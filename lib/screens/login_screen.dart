import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:goldfish_pos/widgets/animated_goldfish.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailCtrl;
  late final TextEditingController _passCtrl;
  late final FocusNode _passFocusNode;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  late AnimationController _bubbleCtrl;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController();
    _passCtrl = TextEditingController();
    _passFocusNode = FocusNode();
    _bubbleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _passFocusNode.dispose();
    _bubbleCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final raw = _emailCtrl.text.trim();
      final email = raw.contains('@') ? raw : '$raw@goldfish.internal';
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: _passCtrl.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Unknown error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── Deep-water gradient background ──────────────────────────
          // SizedBox.expand() forces the Container to fill the Stack;
          // without it a Container with no child collapses to 0×0.
          SizedBox.expand(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF0A1628),
                    Color(0xFF0D2B45),
                    Color(0xFF0F4C75),
                    Color(0xFF1B6CA8),
                  ],
                  stops: [0.0, 0.35, 0.70, 1.0],
                ),
              ),
            ),
          ),

          // ── Floating background bubbles ─────────────────────────────
          AnimatedBuilder(
            animation: _bubbleCtrl,
            builder: (_, __) => CustomPaint(
              painter: _BubbleBackgroundPainter(_bubbleCtrl.value),
              child: const SizedBox.expand(),
            ),
          ),

          // ── Content ─────────────────────────────────────────────────
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
              child: SizedBox(
                width: 420,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ── Goldfish logo ────────────────────────────────────
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.08),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.18),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.35),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: Color(0xFF1B6CA8).withOpacity(0.5),
                            blurRadius: 40,
                            spreadRadius: -4,
                          ),
                        ],
                      ),
                      child: const AnimatedGoldfish(size: 78),
                    ),
                    const SizedBox(height: 28),

                    // ── Brand name ───────────────────────────────────────
                    const Text(
                      'Goldfish POS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'POINT OF SALE SYSTEM',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.50),
                        fontSize: 11,
                        letterSpacing: 3.5,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 44),

                    // ── Glassmorphism card ───────────────────────────────
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.15),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.30),
                            blurRadius: 32,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Welcome back',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Sign in to your account to continue',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.45),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 28),

                              // Username
                              _GlassField(
                                controller: _emailCtrl,
                                label: 'Username',
                                icon: Icons.person_outlined,
                                textInputAction: TextInputAction.next,
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                    ? 'Please enter your username'
                                    : null,
                              ),
                              const SizedBox(height: 16),

                              // Password
                              _GlassField(
                                controller: _passCtrl,
                                focusNode: _passFocusNode,
                                label: 'Password',
                                icon: Icons.lock_outline,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _signIn(),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: Colors.white54,
                                    size: 20,
                                  ),
                                  onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                                ),
                                validator: (v) => (v == null || v.isEmpty)
                                    ? 'Please enter your password'
                                    : null,
                              ),

                              // Error banner
                              if (_errorMessage != null) ...[
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.red.withOpacity(0.40),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.error_outline,
                                        color: Colors.redAccent,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _errorMessage!,
                                          style: const TextStyle(
                                            color: Colors.redAccent,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              const SizedBox(height: 28),

                              // Sign In button
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: _isLoading
                                    ? const Center(
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : ElevatedButton(
                                        onPressed: _signIn,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFFFF8C00,
                                          ),
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          shadowColor: Colors.transparent,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                        child: const Text(
                                          'Sign In',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),
                    Text(
                      '© ${DateTime.now().year} Goldfish POS. All rights reserved.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.28),
                        fontSize: 11,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable glass-style text field
// ─────────────────────────────────────────────────────────────────────────────

class _GlassField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final Widget? suffixIcon;
  final FormFieldValidator<String>? validator;

  const _GlassField({
    required this.controller,
    required this.label,
    required this.icon,
    this.focusNode,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onFieldSubmitted,
    this.suffixIcon,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      validator: validator,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      cursorColor: Color(0xFFFF8C00),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: Colors.white.withOpacity(0.55),
          fontSize: 13,
        ),
        prefixIcon: Icon(icon, color: Colors.white54, size: 19),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white.withOpacity(0.08),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFF8C00), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.redAccent.withOpacity(0.7)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 11),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Floating background bubble painter
// ─────────────────────────────────────────────────────────────────────────────

class _Bubble {
  final double x;
  final double phase;
  final double radius;
  final double speed;
  const _Bubble({
    required this.x,
    required this.phase,
    required this.radius,
    required this.speed,
  });
}

const _bubbles = [
  _Bubble(x: 0.08, phase: 0.00, radius: 5, speed: 1.0),
  _Bubble(x: 0.18, phase: 0.25, radius: 3, speed: 1.4),
  _Bubble(x: 0.32, phase: 0.55, radius: 7, speed: 0.8),
  _Bubble(x: 0.50, phase: 0.10, radius: 4, speed: 1.2),
  _Bubble(x: 0.65, phase: 0.70, radius: 6, speed: 0.9),
  _Bubble(x: 0.78, phase: 0.40, radius: 3, speed: 1.5),
  _Bubble(x: 0.90, phase: 0.85, radius: 5, speed: 1.1),
  _Bubble(x: 0.42, phase: 0.33, radius: 8, speed: 0.7),
  _Bubble(x: 0.12, phase: 0.60, radius: 3, speed: 1.3),
  _Bubble(x: 0.72, phase: 0.15, radius: 4, speed: 1.0),
];

class _BubbleBackgroundPainter extends CustomPainter {
  final double t;
  const _BubbleBackgroundPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (final b in _bubbles) {
      final progress = ((t * b.speed + b.phase) % 1.0);
      final opacity = math.sin(progress * math.pi).clamp(0.0, 1.0) * 0.14;
      final y = size.height * (1.0 - progress);
      final x = b.x * size.width + math.sin(progress * 4 * math.pi) * 12;
      paint.color = Colors.white.withOpacity(opacity);
      canvas.drawCircle(Offset(x, y), b.radius.toDouble(), paint);
    }
  }

  @override
  bool shouldRepaint(_BubbleBackgroundPainter old) => old.t != t;
}
