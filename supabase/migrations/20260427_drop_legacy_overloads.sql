-- =============================================
-- Migration: Drop legacy function overloads
-- Remove as versões antigas sem p_user_weight que ficaram duplicadas
-- no Supabase por causa de sobrecarga de assinatura PostgreSQL.
-- A versão correta (com p_user_weight numeric) é mantida intacta.
-- =============================================

-- Drop versão antiga de get_athlete_planning_stats (sem weight)
DROP FUNCTION IF EXISTS public.get_athlete_planning_stats(p_email text);

-- Drop versão antiga de get_athlete_stats_by_range (sem weight)
-- Assinatura original: (p_email text, p_start_date date, p_end_date date)
DROP FUNCTION IF EXISTS public.get_athlete_stats_by_range(p_email text, p_start_date date, p_end_date date);
