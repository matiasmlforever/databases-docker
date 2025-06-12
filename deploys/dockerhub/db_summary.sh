#!/bin/bash
# filepath: db-summary.sh

echo "🗄️  PostgreSQL Database Summary"
echo "================================="

docker exec postgres11_prod sh -c "
echo 'DATABASES:'
echo '----------'
PGPASSWORD='lacontrapostgres' psql -U postgres -d postgres -t -c \"
SELECT 
    '📁 ' || datname || ' (' || pg_size_pretty(pg_database_size(datname)) || ')'
FROM pg_database 
WHERE datistemplate = false 
ORDER BY datname;
\"

echo ''
echo 'TABLES IN POSTGRES DATABASE:'
echo '----------------------------'
PGPASSWORD='lacontrapostgres' psql -U postgres -d postgres -t -c \"
SELECT CASE 
    WHEN COUNT(*) = 0 THEN '   (No user tables)'
    ELSE '   📋 ' || string_agg(tablename, ', ')
END
FROM pg_tables 
WHERE schemaname = 'public';
\"

echo ''
echo 'TABLES IN APP_DB DATABASE:'
echo '--------------------------'
PGPASSWORD='lacontraapp' psql -U app_user -d app_db -t -c \"
SELECT CASE 
    WHEN COUNT(*) = 0 THEN '   (No user tables)'
    ELSE '   📋 ' || string_agg(tablename, ', ')
END
FROM pg_tables 
WHERE schemaname = 'public';
\"

echo ''
echo 'USER ACCOUNTS:'
echo '--------------'
PGPASSWORD='lacontrapostgres' psql -U postgres -d postgres -t -c \"
SELECT '   👤 ' || rolname || CASE 
    WHEN rolsuper THEN ' (superuser)'
    ELSE ' (regular user)'
END
FROM pg_roles 
WHERE rolcanlogin = true 
ORDER BY rolname;
\"
"