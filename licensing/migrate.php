<?php

// Only allow CLI execution
if (php_sapi_name() !== 'cli') {
    http_response_code(404);
    exit;
}

require __DIR__ . '/db.php';

$pdo = get_db();

// Create migrations tracking table
$pdo->exec('
    CREATE TABLE IF NOT EXISTS migrations (
        id SERIAL PRIMARY KEY,
        filename VARCHAR(255) NOT NULL UNIQUE,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
');

// Get already-applied migrations
$applied = $pdo->query('SELECT filename FROM migrations ORDER BY filename')
    ->fetchAll(PDO::FETCH_COLUMN);

$applied = array_flip($applied);

// Scan migration files
$dir = __DIR__ . '/migrations';
$files = glob($dir . '/*.sql');
sort($files);

$count = 0;

foreach ($files as $file) {
    $filename = basename($file);

    if (isset($applied[$filename])) {
        echo "SKIP  {$filename} (already applied)\n";
        continue;
    }

    $sql = file_get_contents($file);

    try {
        $pdo->beginTransaction();
        $pdo->exec($sql);

        $stmt = $pdo->prepare('INSERT INTO migrations (filename) VALUES (:filename)');
        $stmt->execute(['filename' => $filename]);

        $pdo->commit();
        echo "APPLY {$filename}\n";
        $count++;
    } catch (PDOException $e) {
        $pdo->rollBack();
        echo "ERROR {$filename}: {$e->getMessage()}\n";
        exit(1);
    }
}

if ($count === 0) {
    echo "Nothing to migrate.\n";
} else {
    echo "Applied {$count} migration(s).\n";
}
