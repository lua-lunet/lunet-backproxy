return {
    driver = os.getenv("DB_DRIVER") or "sqlite",
    host = os.getenv("DB_HOST") or "127.0.0.1",
    port = tonumber(os.getenv("DB_PORT")) or 3306,
    user = os.getenv("DB_USER") or "root",
    password = os.getenv("DB_PASSWORD") or "root",
    database = os.getenv("DB_NAME") or "conduit",
    path = os.getenv("DB_PATH") or ".tmp/conduit.sqlite3",
}
