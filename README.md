# Recanto dos Sabiás — Sistema da Portaria

Next.js 14 + TypeScript, Neon PostgreSQL, hospedagem Vercel. Perfis: **Desenvolvedor**, **Administração**, **Portaria**.
Sem módulos de visitantes e de veículos.

## Instalação
1. `npm install`
2. Copie `.env.example` para `.env.local` e preencha `DATABASE_URL` (Neon) e `ENCRYPTION_KEY` (`openssl rand -hex 32`).
3. `npm run migrate` (cria as tabelas; já foi aplicado no banco `recanto-dos-sabias`, o script apenas confirma)
4. `npm run create-developer` (pede usuário e senha na hora; nenhuma senha fica no código)
5. `npm run dev`

## Publicar na Vercel
Suba o projeto para um repositório no GitHub, importe na Vercel e cadastre as variáveis `DATABASE_URL` e `ENCRYPTION_KEY`
(Settings > Environment Variables). Região sugerida: São Paulo (gru1).

## Segurança
- Sessão por cookie httpOnly com token aleatório; só o hash fica no banco; expira em 12 h.
- Senhas com bcrypt (custo 12). 5 erros em 15 minutos bloqueiam novas tentativas.
- Toda API valida sessão e permissão no servidor; entradas validadas com Zod; consultas parametrizadas.
- CPF criptografado (AES-256-GCM). Exclusão lógica. Auditoria de login, cadastros, usuários e permissões.
- Recuperação de senha: Administração/Desenvolvedor gera link de uso único (2 h).

## Backup
Neon mantém histórico para restauração por ponto no tempo (ajuste a janela no painel do Neon). Recomenda-se também um
`pg_dump` semanal guardado fora do Neon.

## Limitações conhecidas
- Anexo de foto em ocorrências ainda não existe (requer armazenamento de arquivos).
- O banco usa SQL com migrations próprias (`migrations/`), não Prisma/Drizzle.
