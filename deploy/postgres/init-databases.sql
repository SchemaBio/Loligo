SELECT format('CREATE ROLE loligo LOGIN PASSWORD %L', :'loligo_password')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'loligo') \gexec

SELECT 'CREATE DATABASE loligo OWNER loligo'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'loligo') \gexec
