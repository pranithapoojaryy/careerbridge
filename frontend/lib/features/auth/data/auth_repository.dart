import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/logger_service.dart';

class AuthRepository {
  final SupabaseClient _supabase;

  AuthRepository(this._supabase);

  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  User? get currentUser => _supabase.auth.currentUser;

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String role,
    required Map<String, dynamic> additionalData,
  }) async {
    Map<String, dynamic> metadata = {'role': role, ...additionalData};

    // Auto-Link Logic for Students & Faculty
    if (role == 'student' || role == 'faculty') {
      try {
        final emailDomain = email.split('@').last.toLowerCase();
        final orgs = await _supabase
            .from('organizations')
            .select('id')
            .eq('allowed_emails_domain', emailDomain)
            .limit(1);

        if (orgs.isNotEmpty) {
          metadata['organization_id'] = orgs.first['id'];
        }
      } catch (_) {
        // Continue without linking if check fails
      }
    }

    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
      data: metadata,
    );

    // For students, create additional profile data after successful signup
    if (response.user != null && role == 'student') {
      try {
        // 1. Update the base profile
        await _supabase
            .from('profiles')
            .update({
              'full_name': additionalData['full_name'],
              'phone': additionalData['phone'],
              'organization_id': additionalData['college_id'],
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', response.user!.id);

        // 2. Update the student-specific profile (academic details)
        // Note: Using upsert because a trigger might have already created a basic record
        await _supabase.from('student_profiles').upsert({
          'id': response.user!.id,
          'usn': additionalData['usn'],
          'college_id': additionalData['college_id']?.toString(),
          'department_id': additionalData['department_id'],
          'program_id': additionalData['program_id'],
          'batch_id': additionalData['batch_id'],
          'semester': additionalData['current_semester'],
          'cgpa': additionalData['cgpa'],
          'updated_at': DateTime.now().toIso8601String(),
        });

        // Notify college about new student registration
        if (additionalData['college_id'] != null) {
          try {
            await _supabase.functions.invoke(
              'notify-college-student-registration',
              body: {
                'studentId': response.user!.id,
                'collegeId': additionalData['college_id'],
                'studentName': additionalData['full_name'],
                'studentEmail': email,
              },
            );
          } catch (e) {
            // Don't fail registration if notification fails
          }
        }
      } catch (e) {
        // Error updating student profile - continue with registration
        LoggerService.error('Error updating student profile data', e);
      }
    }

    return response;
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    final response = await _supabase
        .from('profiles')
        .select()
        .eq('id', userId)
        .single();
    return response;
  }
}
