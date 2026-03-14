<?php

return [
    'db' => [
        'host' => '127.0.0.1',
        'port' => 5432,
        'name' => 'speechy_licensing',
        'user' => 'your_db_user',
        'pass' => 'your_db_password',
    ],

    'admin_api_key' => 'generate-a-strong-random-key-here',

    'base_url' => 'https://licensing.speechy.app',

    'trial_duration_days' => 90,

    'onesignal' => [
        'app_id' => 'your-onesignal-app-id',
        'api_key' => 'your-onesignal-api-key',
        'from_name' => 'Speechy',
        'from_email' => 'noreply@speechy.app',
    ],
];
