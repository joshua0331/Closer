import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CloserLoadingScreen extends StatelessWidget {
  const CloserLoadingScreen({super.key, this.error, this.onRetry});

  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFFFFF8F2),
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
    child: Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/branding/dreamy_peach_gradient_waves.png',
            fit: BoxFit.cover,
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.asset(
                        'assets/branding/closer-logo-transparent.png',
                        width: 188,
                        height: 188,
                        fit: BoxFit.scaleDown,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'A little closer, every day.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF754F45), fontSize: 15),
                    ),
                    const SizedBox(height: 44),
                    if (error == null)
                      SizedBox(
                        width: 82,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: const LinearProgressIndicator(
                            minHeight: 5,
                            color: Color(0xFFF47E69),
                            backgroundColor: Color(0x66FFFFFF),
                          ),
                        ),
                      )
                    else ...[
                      Text(error!, textAlign: TextAlign.center),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: onRetry,
                        child: const Text('Try again'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
