# Required Parameter for Wal Replication
cron.use_background_workers: true
log_directory: /var/log/postgresql
log_line_prefix: '%m [%p] %d %u %h %c %l %s '
log_min_duration_statement: 1000
logging_collector: 'on'
max_connections: 100
max_logical_replication_workers: 40
max_replication_slots: 60
max_sync_workers_per_subscription: 2
max_wal_senders: 60
max_worker_processes: 80
wal_level: logical
wal_keep_size: 1GB
max_wal_size: 4GB
