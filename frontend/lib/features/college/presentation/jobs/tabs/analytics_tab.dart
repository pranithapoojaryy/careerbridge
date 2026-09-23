import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../../../../core/theme/app_theme.dart';

/// Analytics Tab - Shows placement statistics and insights
class AnalyticsTab extends ConsumerStatefulWidget {
  const AnalyticsTab({super.key});

  @override
  ConsumerState<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends ConsumerState<AnalyticsTab> {
  bool _isLoading = true;
  Map<String, dynamic> _stats = {};

  double _parseSalary(String? salary) {
    if (salary == null || salary.isEmpty) return 0.0;

    // Clean string and convert to uppercase
    final cleanSalary = salary.toUpperCase().replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleanSalary.isEmpty) return 0.0;

    try {
      return double.parse(cleanSalary);
    } catch (e) {
      return 0.0;
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // Get organization ID
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('organization_id')
          .eq('id', user.id)
          .single();

      final orgId = profile['organization_id'];

      // Fetch statistics
      final applications = await Supabase.instance.client
          .from('job_applications')
          .select('''
            *,
            job:jobs(
              salary_range,
              organization:organizations(name, logo_url)
            ),
            student:profiles!inner(organization_id),
            offer:offers(package_amount, offer_type)
          ''')
          .eq('student.organization_id', orgId);

      final jobs = await Supabase.instance.client
          .from('jobs')
          .select('id')
          .eq('status', 'open');

      // Calculate stats
      final totalApplications = applications.length;
      final totalDrives = jobs.length;
      final selectedStudents = applications
          .where((app) => app['status'] == 'selected')
          .length;

      // Group data by company
      final companyData = <String, Map<String, dynamic>>{};

      for (final app in applications) {
        final org = app['job']?['organization'];
        final companyName = org?['name'] as String? ?? 'Unknown';
        final logoUrl = org?['logo_url'] as String?;
        final isSelected = app['status'] == 'selected';

        // Correctly handle 'offer' which comes as a list from Supabase
        final offerDataRaw = app['offer'];
        Map<String, dynamic>? offerData;
        if (offerDataRaw is List && offerDataRaw.isNotEmpty) {
          offerData = offerDataRaw.first as Map<String, dynamic>;
        } else if (offerDataRaw is Map<String, dynamic>) {
          offerData = offerDataRaw;
        }

        double package = (offerData != null)
            ? (offerData['package_amount'] as num?)?.toDouble() ?? 0.0
            : 0.0;

        // Fallback to salary_range if package is 0
        if (package == 0.0 && app['job']?['salary_range'] != null) {
          package = _parseSalary(app['job']!['salary_range'].toString());
        }

        if (!companyData.containsKey(companyName)) {
          companyData[companyName] = {
            'name': companyName,
            'logo_url': logoUrl,
            'applications': 0,
            'selected': 0,
            'packages': <double>[],
          };
        }

        companyData[companyName]!['applications']++;
        if (isSelected) companyData[companyName]!['selected']++;
        if (package > 0) {
          (companyData[companyName]!['packages'] as List<double>).add(package);
        }
      }

      // Process company entries
      final processedCompanies = companyData.values.map((data) {
        final packages = data['packages'] as List<double>;
        final avgPackage = packages.isEmpty
            ? 0.0
            : packages.reduce((a, b) => a + b) / packages.length;
        final maxPackage = packages.isEmpty
            ? 0.0
            : packages.reduce((a, b) => a > b ? a : b);

        return {...data, 'avg_package': avgPackage, 'max_package': maxPackage};
      }).toList();

      // Sort by selections first, then applications
      processedCompanies.sort((a, b) {
        final selectionSort = (b['selected'] as int).compareTo(
          a['selected'] as int,
        );
        if (selectionSort != 0) return selectionSort;
        return (b['applications'] as int).compareTo(a['applications'] as int);
      });

      // Overall package metrics
      final allPackages = processedCompanies
          .expand((c) => c['packages'] as List<double>)
          .toList();

      final avgPackage = allPackages.isEmpty
          ? 0.0
          : allPackages.reduce((a, b) => a + b) / allPackages.length;
      final highestPackage = allPackages.isEmpty
          ? 0.0
          : allPackages.reduce((a, b) => a > b ? a : b);

      // Status distribution
      final statusCount = <String, int>{};
      for (final app in applications) {
        final status = app['status'] as String? ?? 'applied';
        statusCount[status] = (statusCount[status] ?? 0) + 1;
      }

      setState(() {
        _stats = {
          'total_drives': totalDrives,
          'total_applications': totalApplications,
          'selected_students': selectedStudents,
          'avg_package': avgPackage,
          'highest_package': highestPackage,
          'top_companies': processedCompanies,
          'status_distribution': statusCount,
          'placement_rate': totalApplications > 0
              ? (selectedStudents / totalApplications * 100).toStringAsFixed(1)
              : '0',
        };
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading stats: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats Cards
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Active Drives',
                  _stats['total_drives'].toString(),
                  Icons.business_center_rounded,
                  const Color(0xFF6C63FF),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  'Total Applications',
                  _stats['total_applications'].toString(),
                  Icons.assignment_turned_in_rounded,
                  const Color(0xFF0984E3),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  'Selected Students',
                  _stats['selected_students'].toString(),
                  Icons.check_circle_rounded,
                  const Color(0xFF00B894),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Package Stats
          Row(
            children: [
              Expanded(
                child: _buildPackageCard(
                  'Average Package',
                  '₹${_stats['avg_package'].toStringAsFixed(2)} LPA',
                  Icons.account_balance_wallet_rounded,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildPackageCard(
                  'Highest Package',
                  '₹${_stats['highest_package'].toStringAsFixed(2)} LPA',
                  Icons.trending_up_rounded,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildPackageCard(
                  'Placement Rate',
                  '${_stats['placement_rate']}%',
                  Icons.pie_chart_rounded,
                  const Color(0xFF6C63FF),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Charts Section
          if (_stats['top_companies'].isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Selection Overview',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildSelectionChart(),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Application Status',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildStatusPieChart(),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],

          // Top Companies
          Text(
            'Companies & Selections',
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textColor,
            ),
          ),
          const SizedBox(height: 16),

          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: _stats['top_companies'].isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No company data available yet',
                        style: GoogleFonts.outfit(color: Colors.grey[600]),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _stats['top_companies'].length,
                    separatorBuilder: (context, index) =>
                        Divider(height: 1, color: Colors.grey[100]),
                    itemBuilder: (context, index) {
                      final company = _stats['top_companies'][index];
                      final logoUrl = company['logo_url'] as String?;
                      final name = company['name'] as String;
                      final applied = company['applications'] as int;
                      final selected = company['selected'] as int;
                      final avgPkg = company['avg_package'] as double;
                      final maxPkg = company['max_package'] as double;

                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            // Company Logo
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey[100]!),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(4),
                              child: logoUrl != null && logoUrl.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Image.network(
                                        logoUrl,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) => Icon(
                                          Icons.business,
                                          color: AppTheme.primaryColor,
                                        ),
                                      ),
                                    )
                                  : Icon(
                                      Icons.business,
                                      color: AppTheme.primaryColor,
                                    ),
                            ),
                            const SizedBox(width: 16),
                            // Company Info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: GoogleFonts.outfit(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textColor,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: selected > 0
                                              ? Colors.green.withValues(alpha: 0.1)
                                              : Colors.blue.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          '$selected selected of $applied applied',
                                          style: GoogleFonts.outfit(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: selected > 0
                                                ? Colors.green[700]
                                                : Colors.blue[700],
                                          ),
                                        ),
                                      ),
                                      if (avgPkg > 0 && avgPkg != maxPkg) ...[
                                        const SizedBox(width: 8),
                                        Text(
                                          'Avg: ₹${avgPkg.toStringAsFixed(1)} LPA',
                                          style: GoogleFonts.outfit(
                                            fontSize: 10,
                                            color: Colors.grey[600],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // Package Info
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (maxPkg > 0) ...[
                                  Text(
                                    '₹${maxPkg.toStringAsFixed(1)} LPA',
                                    style: GoogleFonts.outfit(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green[700],
                                    ),
                                  ),
                                  Text(
                                    'Highest Package',
                                    style: GoogleFonts.outfit(
                                      fontSize: 10,
                                      color: Colors.grey[500],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ] else
                                  Text(
                                    'Pending',
                                    style: GoogleFonts.outfit(
                                      fontSize: 12,
                                      color: Colors.grey[400],
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionChart() {
    final companies = _stats['top_companies'] as List;
    if (companies.isEmpty) return const SizedBox.shrink();

    // Limit to top 5 for better visualization
    final displayCompanies = companies.take(5).toList();

    return Container(
      height: 300,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY:
              (displayCompanies
                      .map((c) => c['applications'] as int)
                      .reduce((a, b) => a > b ? a : b))
                  .toDouble() +
              1,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (group) =>
                  AppTheme.primaryColor.withValues(alpha: 0.9),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final company = displayCompanies[groupIndex];
                final type = rodIndex == 0 ? 'Selected' : 'Applied';
                return BarTooltipItem(
                  '${company['name']}\n$type: ${rod.toY.toInt()}',
                  GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= displayCompanies.length)
                    return const SizedBox.shrink();
                  final name = displayCompanies[index]['name'] as String;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      name.length > 8 ? '${name.substring(0, 7)}...' : name,
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600],
                      ),
                    ),
                  );
                },
                reservedSize: 30,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      color: Colors.grey[500],
                    ),
                  );
                },
                reservedSize: 20,
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 1,
            getDrawingHorizontalLine: (value) =>
                FlLine(color: Colors.grey[100], strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          barGroups: displayCompanies.asMap().entries.map((entry) {
            final index = entry.key;
            final company = entry.value;
            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: (company['selected'] as int).toDouble(),
                  color: Colors.green,
                  width: 12,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                ),
                BarChartRodData(
                  toY: (company['applications'] as int).toDouble(),
                  color: AppTheme.primaryColor.withValues(alpha: 0.3),
                  width: 12,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildStatusPieChart() {
    final distribution = _stats['status_distribution'] as Map<String, int>;
    if (distribution.isEmpty) return const SizedBox.shrink();

    // Sort entries to keep consistency
    final entries = distribution.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      height: 300,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Expanded(
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                sections: entries.map((entry) {
                  return PieChartSectionData(
                    color: _getStatusColor(entry.key),
                    value: entry.value.toDouble(),
                    title: '', // Hide title in segment, use legend
                    radius: 50,
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Legend
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: entries.map((entry) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _getStatusColor(entry.key),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${entry.key[0].toUpperCase()}${entry.key.substring(1)}: ${entry.value}',
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'selected':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'shortlisted':
        return Colors.orange;
      case 'applied':
        return AppTheme.primaryColor;
      default:
        return Colors.grey[400]!;
    }
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppTheme.textColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.1), color.withValues(alpha: 0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 12,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
