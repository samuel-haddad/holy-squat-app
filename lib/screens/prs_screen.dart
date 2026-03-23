import 'package:flutter/material.dart';
import 'package:holy_squat_app/theme/app_theme.dart';
import 'package:holy_squat_app/widgets/app_drawer.dart';
import 'package:holy_squat_app/services/supabase_service.dart';
import 'package:holy_squat_app/screens/pr_detail_screen.dart';
import 'package:holy_squat_app/widgets/theme_toggle_button.dart';

class PrsScreen extends StatefulWidget {
  const PrsScreen({super.key});

  @override
  State<PrsScreen> createState() => _PrsScreenState();
}

class _PrsScreenState extends State<PrsScreen> {
  late Future<List<Map<String, dynamic>>> _prsFuture;

  @override
  void initState() {
    super.initState();
    _prsFuture = SupabaseService.getLatestPrs();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('PRs', style: TextStyle(fontWeight: FontWeight.w600)),
        actions: const [ThemeToggleButton()],
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text('Add', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryTeal,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: InputDecoration(
                hintText: 'Procurar',
                hintStyle: const TextStyle(color: AppTheme.secondaryTextColor),
                prefixIcon: const Icon(Icons.search, color: AppTheme.secondaryTextColor),
                filled: true,
                fillColor: AppTheme.cardColor,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
              child: Row(
                children: [
                  Expanded(flex: 3, child: Text('WORKOUTRELATION', style: TextStyle(color: AppTheme.secondaryTextColor, fontSize: 12, fontWeight: FontWeight.bold))),
                  Expanded(flex: 1, child: Text('PR', style: TextStyle(color: AppTheme.secondaryTextColor, fontSize: 12, fontWeight: FontWeight.bold))),
                  Expanded(flex: 1, child: Text('PR_UNIT', style: TextStyle(color: AppTheme.secondaryTextColor, fontSize: 12, fontWeight: FontWeight.bold))),
                  Expanded(flex: 2, child: Text('DATE', style: TextStyle(color: AppTheme.secondaryTextColor, fontSize: 12, fontWeight: FontWeight.bold))),
                ],
              ),
            ),
            const Divider(color: AppTheme.cardColor, height: 1),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _prsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: AppTheme.primaryTeal));
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
                  }

                  final prs = snapshot.data ?? [];
                  if (prs.isEmpty) {
                    return const Center(child: Text('No PRs found', style: TextStyle(color: AppTheme.secondaryTextColor)));
                  }

                  return ListView.separated(
                    itemCount: prs.length,
                    separatorBuilder: (context, index) => const Divider(color: AppTheme.cardColor, height: 1),
                    itemBuilder: (context, index) {
                      final pr = prs[index];
                      final ex = pr['exercise'] ?? 'Unknown';
                      return InkWell(
                        onTap: () {
                           Navigator.push(context, MaterialPageRoute(
                             builder: (context) => PrDetailScreen(exerciseName: ex),
                           ));
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 4.0),
                          child: Row(
                            children: [
                              Expanded(flex: 3, child: Text(ex, style: const TextStyle(fontWeight: FontWeight.w600))),
                              Expanded(flex: 1, child: Text(pr['pr']?.toString() ?? '-')),
                              Expanded(flex: 1, child: Text(pr['pr_unit'] ?? '')),
                              Expanded(flex: 2, child: Text(pr['date'] ?? '-')),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
