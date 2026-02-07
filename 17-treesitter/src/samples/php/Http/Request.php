<?php

function parseRequest($raw) {
    $parts = explode(' ', $raw);
    return ['method' => $parts[0], 'path' => $parts[1]];
}

function validateRequest($request) {
    if (empty($request['path'])) {
        return false;
    }
    return sanitizePath($request['path']);
}

function sanitizePath($path) {
    return trim($path, '/');
}
