-- Cria os tres bancos isolados por servico (database-per-service).
-- Executado automaticamente pelo container postgres na primeira inicializacao.

CREATE USER fiapx_auth_user WITH PASSWORD 'fiapx_auth_pass';
CREATE DATABASE fiapx_auth OWNER fiapx_auth_user;

CREATE USER fiapx_video_user WITH PASSWORD 'fiapx_video_pass';
CREATE DATABASE fiapx_video OWNER fiapx_video_user;

CREATE USER fiapx_processing_user WITH PASSWORD 'fiapx_processing_pass';
CREATE DATABASE fiapx_processing OWNER fiapx_processing_user;

GRANT ALL PRIVILEGES ON DATABASE fiapx_auth TO fiapx_auth_user;
GRANT ALL PRIVILEGES ON DATABASE fiapx_video TO fiapx_video_user;
GRANT ALL PRIVILEGES ON DATABASE fiapx_processing TO fiapx_processing_user;
