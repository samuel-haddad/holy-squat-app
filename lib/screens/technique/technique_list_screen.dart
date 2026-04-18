import 'package:flutter/material.dart';
import 'package:holy_squat_app/theme/app_theme.dart';
import 'package:holy_squat_app/services/supabase_service.dart';
import 'technique_analysis_screen.dart';
import 'technique_upload_screen.dart';

class TechniqueListScreen extends StatefulWidget {
  const TechniqueListScreen({super.key});

  @override
  State<TechniqueListScreen> createState() => _TechniqueListScreenState();
}

class _TechniqueListScreenState extends State<TechniqueListScreen> {
  List<Map<String, dynamic>> _recentFeedbacks = [];
  bool isLoadingFeedbacks = true;

  @override
  void initState() {
    super.initState();
    _loadFeedbacks();
  }

  Future<void> _loadFeedbacks() async {
    final feedbacks = await SupabaseService.getAllTechniqueFeedbacks();
    if (mounted) {
      setState(() {
        _recentFeedbacks = feedbacks;
        isLoadingFeedbacks = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Technique History', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: _loadFeedbacks,
        color: AppTheme.primaryTeal,
        child: isLoadingFeedbacks
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryTeal))
            : _recentFeedbacks.isEmpty
                ? SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height * 0.7,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.videocam, size: 64, color: AppTheme.primaryTeal),
                            const SizedBox(height: 16),
                            const Text(
                              'Your technical analysis history will appear here.',
                              style: TextStyle(color: AppTheme.secondaryTextColor),
                            ),
                            const SizedBox(height: 32),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryTeal,
                                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                              ),
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const TechniqueUploadScreen()),
                                );
                                _loadFeedbacks();
                              },
                              child: const Text('New Analysis', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                            )
                          ],
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _recentFeedbacks.length,
                    itemBuilder: (context, index) {
                      final f = _recentFeedbacks[index];
                      final exName = f['exercise_name'] ?? 'Unknown';
                      final status = f['status'] ?? 'pending';
                      final date = f['created_at'] != null ? DateTime.parse(f['created_at']).toLocal().toString().split(' ')[0] : '';
                      
                      Color statusColor = Colors.grey;
                      String statusText = 'Analyzed on $date';
                      
                      if (status == 'pending' || status == 'processing') {
                        statusColor = AppTheme.primaryTeal;
                        statusText = 'AI is analyzing...';
                      } else if (status == 'failed') {
                        statusColor = Colors.red[300]!;
                        statusText = 'Analysis failed';
                      }

                      return Card(
                        color: AppTheme.cardColor,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: Icon(
                            status == 'completed' ? Icons.fitness_center : Icons.hourglass_empty, 
                            color: statusColor
                          ),
                          title: Text(exName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          subtitle: Text(statusText, style: TextStyle(color: statusColor, fontSize: 12)),
                          trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => TechniqueAnalysisScreen(exerciseName: exName)),
                            );
                            _loadFeedbacks(); // Reload upon return to see if status updated
                          },
                        ),
                      );
                    },
                  ),
      ),
      bottomNavigationBar: _recentFeedbacks.isNotEmpty && !isLoadingFeedbacks
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const TechniqueUploadScreen()),
                    );
                    _loadFeedbacks();
                  },
                  icon: const Icon(Icons.add, color: Colors.black),
                  label: const Text('New Analysis', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryTeal,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
