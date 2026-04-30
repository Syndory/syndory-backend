// Edge Function: generate-report
// Génère des rapports CSV/PDF pour les statistiques

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { corsHeaders } from '../_shared/cors.ts';
import { getSupabaseClient } from '../_shared/supabase.ts';

type ReportType = 'presence_global' | 'assiduite_etudiant' | 'occupation_salles' | 'charge_enseignante' | 'progression_pedagogique' | 'justificatifs';
type ReportFormat = 'csv' | 'json';

interface GenerateReportRequest {
  report_type: ReportType;
  format: ReportFormat;
  filters?: {
    filiere_id?: string;
    class_id?: string;
    matiere_id?: string;
    professor_id?: string;
    student_id?: string;
    start_date?: string;
    end_date?: string;
  };
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabase = getSupabaseClient(req);
    
    // Get current user
    const { data: { user }, error: userError } = await supabase.auth.getUser();
    
    if (userError || !user) {
      return new Response(
        JSON.stringify({ error: 'Non authentifié' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Check permissions
    const { data: userData } = await supabase
      .from('users')
      .select('role')
      .eq('id', user.id)
      .single();

    // Only admin and professors can generate reports
    const allowedRoles = ['admin', 'professor'];
    if (!allowedRoles.includes(userData?.role || '')) {
      return new Response(
        JSON.stringify({ error: 'Accès réservé' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Parse request
    const {
      report_type,
      format = 'json',
      filters = {}
    }: GenerateReportRequest = await req.json();

    if (!report_type) {
      return new Response(
        JSON.stringify({ error: 'Paramètre requis: report_type' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    let data: any[] = [];
    let columns: string[] = [];
    let reportTitle = '';

    // Generate report based on type
    switch (report_type) {
      case 'presence_global':
        reportTitle = 'Rapport de présence global';
        const { data: presenceStats } = await supabase.rpc('get_attendance_stats', {
          p_student_id: filters.student_id || null,
          p_class_id: filters.class_id || null,
          p_matiere_id: filters.matiere_id || null,
          p_start_date: filters.start_date || null,
          p_end_date: filters.end_date || null
        });
        data = presenceStats ? [presenceStats] : [];
        columns = ['total_seances', 'present_count', 'absent_count', 'late_count', 'justified_count', 'attendance_rate'];
        break;

      case 'assiduite_etudiant':
        reportTitle = 'Rapport d\'assiduité par étudiant';
        const { data: students } = await supabase
          .from('users')
          .select(`
            id, first_name, last_name, email,
            student_classes:class_id (class:classes (name))
          `)
          .in('role', ['student', 'class_representative'])
          .eq('is_active', true);
        
        // Get attendance for each student
        for (const student of students || []) {
          const { data: stats } = await supabase.rpc('get_attendance_stats', {
            p_student_id: student.id,
            p_start_date: filters.start_date || null,
            p_end_date: filters.end_date || null
          });
          data.push({
            ...student,
            ...stats
          });
        }
        columns = ['id', 'first_name', 'last_name', 'email', 'attendance_rate'];
        break;

      case 'charge_enseignante':
        reportTitle = 'Rapport de charge enseignante';
        const { data: professors } = await supabase
          .from('users')
          .select('id, first_name, last_name, email')
          .eq('role', 'professor')
          .eq('is_active', true);

        for (const prof of professors || []) {
          const { data: seances } = await supabase
            .from('seances')
            .select('id, start_time, end_time, date')
            .eq('professor_id', prof.id)
            .gte('date', filters.start_date || '2000-01-01')
            .lte('date', filters.end_date || '2099-12-31');
          
          const totalHours = (seances || []).reduce((acc, s) => {
            const start = new Date(`2000-01-01T${s.start_time}`);
            const end = new Date(`2000-01-01T${s.end_time}`);
            return acc + (end.getTime() - start.getTime()) / (1000 * 60 * 60);
          }, 0);

          data.push({
            ...prof,
            seance_count: seances?.length || 0,
            total_hours: Math.round(totalHours * 100) / 100
          });
        }
        columns = ['id', 'first_name', 'last_name', 'email', 'seance_count', 'total_hours'];
        break;

      case 'justificatifs':
        reportTitle = 'Rapport des justificatifs';
        const { data: justifs } = await supabase
          .from('justificatifs')
          .select(`
            *,
            student:student_id (first_name, last_name, email),
            presence:presence_id (session:session_id (seance:seance_id (date, matiere:matiere_id (name))))
          `)
          .gte('submitted_at', filters.start_date ? `${filters.start_date}T00:00:00` : '2000-01-01')
          .lte('submitted_at', filters.end_date ? `${filters.end_date}T23:59:59` : '2099-12-31');
        data = justifs || [];
        columns = ['id', 'student', 'status', 'submitted_at', 'reviewed_at'];
        break;

      default:
        return new Response(
          JSON.stringify({ error: 'Type de rapport non supporté' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
    }

    if (format === 'csv') {
      // Generate CSV
      const csvHeader = columns.join(',');
      const csvRows = data.map(row => {
        return columns.map(col => {
          const val = row[col];
          if (val === null || val === undefined) return '';
          if (typeof val === 'object') return JSON.stringify(val);
          return String(val).replace(/,/g, ';');
        }).join(',');
      });
      const csv = [csvHeader, ...csvRows].join('\n');

      return new Response(csv, {
        status: 200,
        headers: {
          ...corsHeaders,
          'Content-Type': 'text/csv',
          'Content-Disposition': `attachment; filename="${report_type}_${new Date().toISOString().split('T')[0]}.csv"`
        }
      });
    }

    // Return JSON
    return new Response(
      JSON.stringify({
        title: reportTitle,
        generated_at: new Date().toISOString(),
        filters,
        columns,
        data
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error: any) {
    console.error('Unexpected error:', error);
    return new Response(
      JSON.stringify({ error: 'Erreur serveur', details: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
