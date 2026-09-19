<?php
$uploadDir = __DIR__ . '/uploads/';
$requested = isset($_GET['file']) ? basename(str_replace('\\', '/', $_GET['file'])) : '';
$path = $uploadDir . $requested;

if ($requested === '' || !is_file($path)) {
    http_response_code(404);
    exit('File not found.');
}

header('Content-Type: application/octet-stream');
header('Content-Disposition: attachment; filename="' . addcslashes($requested, '"\\') . '"');
header('Content-Length: ' . filesize($path));
header('X-Content-Type-Options: nosniff');
readfile($path);
