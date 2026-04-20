-- =============================================
-- Migration: Unify Benchmark Columns (bench_exercise -> exercise)
-- Align benchmarks and benchmarks_logs with the 'exercise' naming standard.
-- =============================================

-- 1. Renomear colunas na tabela 'benchmarks'
ALTER TABLE public.benchmarks 
RENAME COLUMN bench_exercise TO exercise;

-- 2. Renomear colunas na tabela 'benchmarks_logs'
ALTER TABLE public.benchmarks_logs 
RENAME COLUMN bench_exercise TO exercise;

-- 3. Habilitar RLS e Configurar Políticas

-- Tabela benchmarks (Biblioteca Global)
ALTER TABLE public.benchmarks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Qualquer um pode ler benchmarks" ON public.benchmarks;
CREATE POLICY "Qualquer um pode ler benchmarks" 
ON public.benchmarks FOR SELECT 
USING (true);

-- Tabela benchmarks_logs (Histórico do Usuário)
ALTER TABLE public.benchmarks_logs ENABLE ROW LEVEL SECURITY;

-- SELECT
DROP POLICY IF EXISTS "Usuários veem seus próprios benchmarks" ON public.benchmarks_logs;
CREATE POLICY "Usuários veem seus próprios benchmarks" 
ON public.benchmarks_logs FOR SELECT 
USING (auth.jwt() ->> 'email' = user_email);

-- INSERT
DROP POLICY IF EXISTS "Usuários inserem seus próprios benchmarks" ON public.benchmarks_logs;
CREATE POLICY "Usuários inserem seus próprios benchmarks" 
ON public.benchmarks_logs FOR INSERT 
WITH CHECK (auth.jwt() ->> 'email' = user_email);

-- UPDATE
DROP POLICY IF EXISTS "Usuários atualizam seus próprios benchmarks" ON public.benchmarks_logs;
CREATE POLICY "Usuários atualizam seus próprios benchmarks" 
ON public.benchmarks_logs FOR UPDATE 
USING (auth.jwt() ->> 'email' = user_email);

-- DELETE
DROP POLICY IF EXISTS "Usuários removem seus próprios benchmarks" ON public.benchmarks_logs;
CREATE POLICY "Usuários removem seus próprios benchmarks" 
ON public.benchmarks_logs FOR DELETE 
USING (auth.jwt() ->> 'email' = user_email);
