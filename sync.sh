#!/bin/bash

# ENV
set -o allexport
source .env
set +o allexport

# Function
config_wal () {
    psql -h "$SUBSCRIBER_PGHOST" -p "$SUBSCRIBER_PGPORT" -U "$SUBSCRIBER_PGUSER" -c "CREATE DATABASE $DB;"
    pg_dump -h "$PUBLISHER_PGHOST" -p "$PUBLISHER_PGPORT" -U "$PUBLISHER_PGUSER" -d "$DB" --schema-only | psql -h "$SUBSCRIBER_PGHOST" -p "$SUBSCRIBER_PGPORT" -U "$SUBSCRIBER_PGUSER" -d "$DB"
    psql -h "$PUBLISHER_PGHOST" -p "$PUBLISHER_PGPORT" -U "$PUBLISHER_PGUSER" -d "$DB" -c "CREATE PUBLICATION migrate_pub_$DB FOR ALL TABLES;"
    psql -h "$SUBSCRIBER_PGHOST" -p "$SUBSCRIBER_PGPORT" -U "$SUBSCRIBER_PGUSER" -d "$DB" -c "CREATE SUBSCRIPTION migrate_sub_$DB CONNECTION 'host="$PUBLISHER_PGHOST" port="$PUBLISHER_PGPORT" user="$REPLICATOR_PGUSER" password="$REPLICATOR_PGPASSWORD" dbname="$DB"' PUBLICATION migrate_pub_$DB WITH (create_slot = true, copy_data = true, enabled = true);"
    psql -h "$PUBLISHER_PGHOST" -p "$PUBLISHER_PGPORT" -U "$PUBLISHER_PGUSER" -d "$DB" -c "GRANT SELECT ON ALL TABLES IN SCHEMA public TO replicator;"
    psql -h "$PUBLISHER_PGHOST" -p "$PUBLISHER_PGPORT" -U "$PUBLISHER_PGUSER" -d "$DB" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO replicator;"
}

remove_wal () {
    psql -h "$SUBSCRIBER_PGHOST" -p "$SUBSCRIBER_PGPORT" -U "$SUBSCRIBER_PGUSER" -d "$DB" -c "DROP SUBSCRIPTION migrate_sub_$DB;"
    psql -h "$PUBLISHER_PGHOST" -p "$PUBLISHER_PGPORT" -U "$PUBLISHER_PGUSER" -d "$DB" -c "DROP PUBLICATION migrate_pub_$DB;"
}

enable_wal () {
    databases=$(psql -h "$PUBLISHER_PGHOST" -p "$PUBLISHER_PGPORT" -U "$PUBLISHER_PGUSER" -Atc "$QUERY")
    echo "Restore Global Object (Y/N):"
    read -p "replication >> " INPUT
    if [[ "$INPUT" == "y" || "$INPUT" == "yes" ]]; then
        pg_dumpall -h "$PUBLISHER_PGHOST" -p "$PUBLISHER_PGPORT" -U "$PUBLISHER_PGUSER" --globals-only | psql -h "$SUBSCRIBER_PGHOST" -p "$SUBSCRIBER_PGPORT" -U "$SUBSCRIBER_PGUSER"
        for DB in $databases; do
            config_wal "PUBLISHER_PGHOST" "PUBLISHER_PGPORT" "PUBLISHER_PGUSER" "SUBSCRIBER_PGHOST" "SUBSCRIBER_PGPORT" "SUBSCRIBER_PGUSER" "DB" "REPLICATOR_PGUSER" "REPLICATOR_PGPASSWORD"
        done
    elif [[ "$INPUT" == "n" || "$INPUT" == "no" ]]; then
        for DB in $databases; do
            config_wal "PUBLISHER_PGHOST" "PUBLISHER_PGPORT" "PUBLISHER_PGUSER" "SUBSCRIBER_PGHOST" "SUBSCRIBER_PGPORT" "SUBSCRIBER_PGUSER" "DB" "REPLICATOR_PGUSER" "REPLICATOR_PGPASSWORD"
        done
    else
        echo "Wrong Input!"
    fi
}

disable_wal () {
    databases=$(psql -h "$PUBLISHER_PGHOST" -p "$PUBLISHER_PGPORT" -U "$PUBLISHER_PGUSER" -Atc "$QUERY")
    for DB in $databases; do
        remove_wal "PUBLISHER_PGHOST" "PUBLISHER_PGPORT" "PUBLISHER_PGUSER" "SUBSCRIBER_PGHOST" "SUBSCRIBER_PGPORT" "SUBSCRIBER_PGUSER" "DB"
    done
}

status_wal () {
    PUBLISHER_OUTPUT=$(psql -h "$PUBLISHER_PGHOST" -p "$PUBLISHER_PGPORT" -U "$PUBLISHER_PGUSER" -At -c "$QUERY")
    SUBSCRIBER_OUTPUT=$(psql -h "$SUBSCRIBER_PGHOST" -p "$SUBSCRIBER_PGPORT" -U "$SUBSCRIBER_PGUSER" -At -c "$QUERY")
    printf "      +-----------------+------------+------------+\n"
    printf "      | %-15s | %10s | %10s |\n" "Database" "Publisher" "Subscriber"
    printf "      +-----------------+------------+------------+\n"
    while IFS="|" read -r DB_NAME PUB_SIZE; do
        SUB_SIZE=$(echo "$SUBSCRIBER_OUTPUT" | awk -F"|" -v db="$DB_NAME" '$1==db {print $2}')
        if [[ -n "$SUB_SIZE" ]]; then
            printf "      | %-15s | %10s | %10s |\n" "$DB_NAME" "$PUB_SIZE" "$SUB_SIZE"
            printf "      +-----------------+------------+------------+\n"
        fi
    done <<< "$PUBLISHER_OUTPUT"
}

# Script Execution
clear
figlet Wal - Replication
echo
echo "      =========================================================="
echo "          PostgreSQL WAL Replication Management Menu            "
echo "      =========================================================="
echo "        1. Enable WAL Replication                               "
echo "        2. Status WAL Replication                               "
echo "        3. Disable WAL Replication                              "
echo "        Q. Quit                                                 "
echo "      =========================================================="
echo
read -p "replication >> " OPTION

# Exclude Database
exclude_dbs="postgres template0 template1"
exclude_clause=""
for DB in $exclude_dbs; do
exclude_clause+="'$DB',"
done
exclude_clause=${exclude_clause%,}

if [[ "$OPTION" == "1" ]]; then
    clear
    echo "      =========================================================="
    echo "           Enable WAL Replication                               "
    echo "      =========================================================="
    echo "        1. All Databases                                        "
    echo "        2. Selected Database                                    "
    echo "        3. Databases Below 1 GB                                 "
    echo "        4. Databases 1 GB and Above                             "
    echo "        Q. Quit                                                 "
    echo "      =========================================================="
    echo
    read -p "replication >> " ENABLE
    if [[ "$ENABLE" == "1" ]]; then
        echo
        psql -h "$PUBLISHER_PGHOST" -p "$PUBLISHER_PGPORT" -U "$PUBLISHER_PGUSER" -P border=3 -P unicode_border_linestyle=single -P unicode_column_linestyle=single -P unicode_header_linestyle=single -c "SELECT datname AS "Database", (pg_database_size(datname) / 1024 / 1024)::INT || ' MB' AS "Size" FROM pg_database WHERE datistemplate = false AND datname NOT IN ($exclude_clause) ORDER BY pg_database_size(datname);" | sed 's/^/      /'
        echo "Do you want to proceed? (Yes/No):"
        read -p "replication >> " INPUT
        if [[ "$INPUT" == "y" || "$INPUT" == "yes" ]]; then
            QUERY="SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ($exclude_clause);"
            enable_wal "QUERY" "PUBLISHER_PGHOST" "PUBLISHER_PGPORT" "PUBLISHER_PGUSER" "SUBSCRIBER_PGHOST" "SUBSCRIBER_PGPORT" "SUBSCRIBER_PGUSER" "REPLICATOR_PGUSER" "REPLICATOR_PGPASSWORD"
        else
            echo "Aborted!"
        fi
    elif [[ "$ENABLE" == "2" ]]; then
        echo
        psql -h "$PUBLISHER_PGHOST" -p "$PUBLISHER_PGPORT" -U "$PUBLISHER_PGUSER" -P border=3 -P unicode_border_linestyle=single -P unicode_column_linestyle=single -P unicode_header_linestyle=single -c "SELECT datname AS "Database", (pg_database_size(datname) / 1024 / 1024)::INT || ' MB' AS "Size" FROM pg_database WHERE datistemplate = false AND datname NOT IN ($exclude_clause) ORDER BY pg_database_size(datname);" | sed 's/^/      /'
        echo "Database name:"
        read -p "replication >> " DB
        echo "Restore Global Object (Y/N):"
        read -p "replication >> " INPUT
        if [[ "$INPUT" == "y" || "$INPUT" == "yes" ]]; then
            pg_dumpall -h "$PUBLISHER_PGHOST" -p "$PUBLISHER_PGPORT" -U "$PUBLISHER_PGUSER" --globals-only | psql -h "$SUBSCRIBER_PGHOST" -p "$SUBSCRIBER_PGPORT" -U "$SUBSCRIBER_PGUSER"
            config_wal "PUBLISHER_PGHOST" "PUBLISHER_PGPORT" "PUBLISHER_PGUSER" "SUBSCRIBER_PGHOST" "SUBSCRIBER_PGPORT" "SUBSCRIBER_PGUSER" "DB" "REPLICATOR_PGUSER" "REPLICATOR_PGPASSWORD"
        elif [[ "$INPUT" == "n" || "$INPUT" == "no" ]]; then
            config_wal "PUBLISHER_PGHOST" "PUBLISHER_PGPORT" "PUBLISHER_PGUSER" "SUBSCRIBER_PGHOST" "SUBSCRIBER_PGPORT" "SUBSCRIBER_PGUSER" "DB" "REPLICATOR_PGUSER" "REPLICATOR_PGPASSWORD"
        else
            echo "Wrong Input!"
        fi
    elif [[ "$ENABLE" == "3" ]]; then
        echo
        psql -h "$PUBLISHER_PGHOST" -p "$PUBLISHER_PGPORT" -U "$PUBLISHER_PGUSER" -P border=3 -P unicode_border_linestyle=single -P unicode_column_linestyle=single -P unicode_header_linestyle=single -c "SELECT datname AS "Database", (pg_database_size(datname) / 1024 / 1024)::INT || ' MB' AS "Size" FROM pg_database WHERE datistemplate = false AND datname NOT IN ($exclude_clause) AND pg_database_size(datname) < 1024 * 1024 * 1024 ORDER BY pg_database_size(datname);" | sed 's/^/      /'
        echo "Do you want to proceed? (Yes/No):"
        read -p "replication >> " INPUT
        if [[ "$INPUT" == "y" || "$INPUT" == "yes" ]]; then
            QUERY="SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ($exclude_clause) AND pg_database_size(datname) < 1024 * 1024 * 1024 ORDER BY datname;"
            enable_wal "QUERY" "PUBLISHER_PGHOST" "PUBLISHER_PGPORT" "PUBLISHER_PGUSER" "SUBSCRIBER_PGHOST" "SUBSCRIBER_PGPORT" "SUBSCRIBER_PGUSER" "REPLICATOR_PGUSER" "REPLICATOR_PGPASSWORD"
        else
            echo "Aborted!"
        fi
    elif [[ "$ENABLE" == "4" ]]; then
        echo
        psql -h "$PUBLISHER_PGHOST" -p "$PUBLISHER_PGPORT" -U "$PUBLISHER_PGUSER" -P border=3 -P unicode_border_linestyle=single -P unicode_column_linestyle=single -P unicode_header_linestyle=single -c "SELECT datname AS "Database",(pg_database_size(datname) / 1024 / 1024)::INT || ' MB' AS "Size" FROM pg_database WHERE datistemplate = false AND datname NOT IN ($exclude_clause) AND pg_database_size(datname) >= 1024 * 1024 * 1024 ORDER BY pg_database_size(datname);" | sed 's/^/      /'
        echo "Do you want to proceed? (Yes/No):"
        read -p "replication >> " INPUT
        if [[ "$INPUT" == "y" || "$INPUT" == "yes" ]]; then
            QUERY="SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ($exclude_clause) AND pg_database_size(datname) >= 1024 * 1024 * 1024 ORDER BY datname;"
            enable_wal "QUERY" "PUBLISHER_PGHOST" "PUBLISHER_PGPORT" "PUBLISHER_PGUSER" "SUBSCRIBER_PGHOST" "SUBSCRIBER_PGPORT" "SUBSCRIBER_PGUSER" "REPLICATOR_PGUSER" "REPLICATOR_PGPASSWORD"
        else
            echo "Aborted!"
        fi
    elif [[ "$ENABLE" == "q" || "$ENABLE" == "Q" ]]; then
        exit 0
    else
        echo "Wrong Input!"
    fi
elif [[ "$OPTION" == "2" ]]; then
    clear
    echo "      =========================================================="
    echo "           Status WAL Replication                              "
    echo "      =========================================================="
    echo "        1. All Databases                                        "
    echo "        2. Selected Database                                    "
    echo "        3. Databases Below 1 GB                                 "
    echo "        4. Databases 1 GB and Above                             "
    echo "        Q. Quit                                                 "
    echo "      =========================================================="
    echo
    read -p "replication >> " STATUS
    if [[ "$STATUS" == "1" ]]; then
        QUERY="SELECT datname, (pg_database_size(datname)/1024/1024)::int AS size_mb FROM pg_database WHERE datistemplate = false AND datname NOT IN ($exclude_clause);"
        status_wal "QUERY"
    elif [[ "$STATUS" == "2" ]]; then
        echo "Database name:"
        read -p "replication >> " DB
        QUERY="SELECT datname,(pg_database_size(datname)/1024/1024)::int AS size_mb FROM pg_database WHERE datistemplate = false AND datname = '$DB';"
        status_wal "QUERY"
    elif [[ "$STATUS" == "3" ]]; then
        QUERY="SELECT datname, (pg_database_size(datname)/1024/1024)::int AS size_mb FROM pg_database WHERE datistemplate = false AND datname NOT IN ($exclude_clause) AND pg_database_size(datname) < 1024*1024*1024 ORDER BY datname;"
        status_wal "QUERY"
    elif [[ "$STATUS" == "4" ]]; then
        QUERY="SELECT datname, (pg_database_size(datname)/1024/1024)::int AS size_mb FROM pg_database WHERE datistemplate = false AND datname NOT IN ($exclude_clause) AND pg_database_size(datname) >= 1024*1024*1024 ORDER BY datname;"
        status_wal "QUERY"
    elif [[ "$STATUS" == "q" || "$STATUS" == "Q" ]]; then
        exit 0
    else
        echo "Wrong Input!"
    fi
elif [[ "$OPTION" == "3" ]]; then
    clear
    echo "      =========================================================="
    echo "           Disable WAL Replication                              "
    echo "      =========================================================="
    echo "        1. All Databases                                        "
    echo "        2. Selected Database                                    "
    echo "        3. Databases Below 1 GB                                 "
    echo "        4. Databases 1 GB and Above                             "
    echo "        Q. Quit                                                 "
    echo "      =========================================================="
    echo
    read -p "replication >> " DISABLE
    if [[ "$DISABLE" == "1" ]]; then
        echo
        psql -h "$PUBLISHER_PGHOST" -p "$PUBLISHER_PGPORT" -U "$PUBLISHER_PGUSER" -P border=3 -P unicode_border_linestyle=single -P unicode_column_linestyle=single -P unicode_header_linestyle=single -c "SELECT datname AS "Database", (pg_database_size(datname) / 1024 / 1024)::INT || ' MB' AS "Size" FROM pg_database WHERE datistemplate = false AND datname NOT IN ($exclude_clause) ORDER BY pg_database_size(datname);" | sed 's/^/      /'
        echo "Do you want to proceed? (Yes/No):"
        read -p "replication >> " INPUT
        if [[ "$INPUT" == "y" || "$INPUT" == "yes" ]]; then
            QUERY="SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ($exclude_clause);"
            disable_wal "QUERY" "PUBLISHER_PGHOST" "PUBLISHER_PGPORT" "PUBLISHER_PGUSER" "SUBSCRIBER_PGHOST" "SUBSCRIBER_PGPORT" "SUBSCRIBER_PGUSER"
        else
            echo "Aborted!"
        fi
    elif [[ "$DISABLE" == "2" ]]; then
        echo
        psql -h "$PUBLISHER_PGHOST" -p "$PUBLISHER_PGPORT" -U "$PUBLISHER_PGUSER" -P border=3 -P unicode_border_linestyle=single -P unicode_column_linestyle=single -P unicode_header_linestyle=single -c "SELECT datname AS "Database", (pg_database_size(datname) / 1024 / 1024)::INT || ' MB' AS "Size" FROM pg_database WHERE datistemplate = false AND datname NOT IN ($exclude_clause) ORDER BY pg_database_size(datname);" | sed 's/^/      /'
        echo "Database name:"
        read -p "replication >> " DB
        remove_wal "PUBLISHER_PGHOST" "PUBLISHER_PGPORT" "PUBLISHER_PGUSER" "SUBSCRIBER_PGHOST" "SUBSCRIBER_PGPORT" "SUBSCRIBER_PGUSER" "DB"
    elif [[ "$DISABLE" == "3" ]]; then
        echo
        psql -h "$PUBLISHER_PGHOST" -p "$PUBLISHER_PGPORT" -U "$PUBLISHER_PGUSER" -P border=3 -P unicode_border_linestyle=single -P unicode_column_linestyle=single -P unicode_header_linestyle=single -c "SELECT datname AS "Database", (pg_database_size(datname) / 1024 / 1024)::INT || ' MB' AS "Size" FROM pg_database WHERE datistemplate = false AND datname NOT IN ($exclude_clause) AND pg_database_size(datname) < 1024 * 1024 * 1024 ORDER BY pg_database_size(datname);" | sed 's/^/      /'
        echo "Do you want to proceed? (Yes/No):"
        read -p "replication >> " INPUT
        if [[ "$INPUT" == "y" || "$INPUT" == "yes" ]]; then
            QUERY="SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ($exclude_clause) AND pg_database_size(datname) < 1024 * 1024 * 1024 ORDER BY datname;"
            disable_wal "QUERY" "PUBLISHER_PGHOST" "PUBLISHER_PGPORT" "PUBLISHER_PGUSER" "SUBSCRIBER_PGHOST" "SUBSCRIBER_PGPORT" "SUBSCRIBER_PGUSER"
        else
            echo "Aborted!"
        fi
    elif [[ "$DISABLE" == "4" ]]; then
        echo
        psql -h "$PUBLISHER_PGHOST" -p "$PUBLISHER_PGPORT" -U "$PUBLISHER_PGUSER" -P border=3 -P unicode_border_linestyle=single -P unicode_column_linestyle=single -P unicode_header_linestyle=single -c "SELECT datname AS "Database",(pg_database_size(datname) / 1024 / 1024)::INT || ' MB' AS "Size" FROM pg_database WHERE datistemplate = false AND datname NOT IN ($exclude_clause) AND pg_database_size(datname) >= 1024 * 1024 * 1024 ORDER BY pg_database_size(datname);" | sed 's/^/      /'
        echo "Do you want to proceed? (Yes/No):"
        read -p "replication >> " INPUT
        if [[ "$INPUT" == "y" || "$INPUT" == "yes" ]]; then
            QUERY="SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ($exclude_clause) AND pg_database_size(datname) >= 1024 * 1024 * 1024 ORDER BY datname;"
            disable_wal "QUERY" "PUBLISHER_PGHOST" "PUBLISHER_PGPORT" "PUBLISHER_PGUSER" "SUBSCRIBER_PGHOST" "SUBSCRIBER_PGPORT" "SUBSCRIBER_PGUSER"
        else
            echo "Aborted!"
        fi
    elif [[ "$DISABLE" == "q" || "$DISABLE" == "Q" ]]; then
        exit 0
    else
        echo "Wrong Input!"
    fi
elif [[ "$OPTION" == "q" || "$OPTION" == "Q" ]]; then
    exit 0
else
    echo "Wrong Input!"
fi
