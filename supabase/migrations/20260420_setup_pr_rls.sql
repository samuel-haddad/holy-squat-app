-- =============================================
-- Migration: Setup RLS Policies for PR tables
-- Ensures pr (global library) is readable and pr_log is manageable by owners.
-- =============================================

-- 1. Habilitar RLS nas tabelas
ALTER TABLE public.pr ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pr_log ENABLE ROW LEVEL SECURITY;

-- 2. Políticas para a tabela 'pr' (Biblioteca Global)
-- Permite que qualquer usuário autenticado leia a biblioteca
DROP POLICY IF EXISTS "Permitir leitura global de exercícios" ON public.pr;
CREATE POLICY "Permitir leitura global de exercícios" 
ON public.pr FOR SELECT 
USING (true);

-- 3. Políticas para a tabela 'pr_log' (Histórico de PRs)
-- Permite que usuários gerenciem apenas seus próprios registros baseados no user_email

-- SELECT (Ver seus próprios registros)
DROP POLICY IF EXISTS "Usuários veem seus próprios PRs" ON public.pr_log;
CREATE POLICY "Usuários veem seus próprios PRs" 
ON public.pr_log FOR SELECT 
USING (auth.jwt() ->> 'email' = user_email);

-- INSERT (Adicionar novos PRs)
DROP POLICY IF EXISTS "Usuários inserem seus próprios PRs" ON public.pr_log;
CREATE POLICY "Usuários inserem seus próprios PRs" 
ON public.pr_log FOR INSERT 
WITH CHECK (auth.jwt() ->> 'email' = user_email);

-- UPDATE (Editar seus próprios PRs)
DROP POLICY IF EXISTS "Usuários editam seus próprios PRs" ON public.pr_log;
CREATE POLICY "Usuários editam seus próprios PRs" 
ON public.pr_log FOR UPDATE 
USING (auth.jwt() ->> 'email' = user_email);

-- DELETE (Remover seus próprios PRs)
DROP POLICY IF EXISTS "Usuários removem seus próprios PRs" ON public.pr_log;
CREATE POLICY "Usuários removem seus próprios PRs" 
ON public.pr_log FOR DELETE 
USING (auth.jwt() ->> 'email' = user_email);
