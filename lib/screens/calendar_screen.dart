import 'package:flutter/material.dart';
import 'package:holy_squat_app/widgets/theme_toggle_button.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:holy_squat_app/theme/app_theme.dart';
import 'package:holy_squat_app/widgets/app_drawer.dart';
import 'package:holy_squat_app/widgets/app_bottom_nav.dart';
import 'package:holy_squat_app/core/app_state.dart';
import 'package:holy_squat_app/screens/main_screen.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      drawer: const AppDrawer(),
      appBar: AppBar(
        actions: const [ThemeToggleButton()],
        title: const Text('Calendar', style: TextStyle(fontWeight: FontWeight.w600)),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      body: Column(
        children: [
          TableCalendar(
            firstDay: DateTime.utc(2020, 10, 16),
            lastDay: DateTime.utc(2030, 3, 14),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) {
              return isSameDay(_selectedDay, day);
            },
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
              
              AppState.selectedWodDate.value = selectedDay;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const MainScreen(initialIndex: 0)),
                (route) => false,
              );
            },
            onHeaderTapped: (focusedDay) async {
              final picked = await showDatePicker(
                context: context,
                initialDate: focusedDay,
                initialDatePickerMode: DatePickerMode.year,
                firstDate: DateTime(2000),
                lastDate: DateTime(2050),
                builder: (context, child) {
                  return Theme(
                    data: ThemeData.dark().copyWith(
                      colorScheme: const ColorScheme.dark(
                        primary: AppTheme.primaryTeal,
                        onPrimary: Colors.black,
                        surface: AppTheme.cardColor,
                        onSurface: Colors.white,
                      ),
                    ),
                    child: child!,
                  );
                },
              );
              if (picked != null) {
                setState(() {
                  _focusedDay = picked;
                });
              }
            },
            calendarStyle: const CalendarStyle(
              todayDecoration: BoxDecoration(
                color: AppTheme.cardColor,
                shape: BoxShape.circle,
              ),
              selectedDecoration: BoxDecoration(
                color: AppTheme.primaryTeal,
                shape: BoxShape.circle,
              ),
              defaultTextStyle: TextStyle(color: Colors.white),
              weekendTextStyle: TextStyle(color: AppTheme.secondaryTextColor),
              outsideTextStyle: TextStyle(color: Colors.grey),
            ),
            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: TextStyle(color: Colors.white, fontSize: 18),
              leftChevronIcon: Icon(Icons.chevron_left, color: AppTheme.primaryTeal),
              rightChevronIcon: Icon(Icons.chevron_right, color: AppTheme.primaryTeal),
            ),
            daysOfWeekStyle: const DaysOfWeekStyle(
              weekdayStyle: TextStyle(color: AppTheme.secondaryTextColor),
              weekendStyle: TextStyle(color: AppTheme.secondaryTextColor),
            ),
          ),
          const SizedBox(height: 24),
          const Expanded(
            child: Center(
              child: Text(
                'No events for this day.',
                style: TextStyle(color: AppTheme.secondaryTextColor),
              ),
            ),
          )
        ],
      ),
      bottomNavigationBar: const AppBottomNav(activeIndex: null),
    );
  }
}
